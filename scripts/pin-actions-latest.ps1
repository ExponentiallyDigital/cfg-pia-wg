<#
.SYNOPSIS
    Upgrades GitHub Actions 'uses:' references to the SHA of their latest release.

.DESCRIPTION
    For each action found in .github/workflows/*.yml:
      1. Looks up the latest release tag via the GitHub API (cached with a 24h TTL)
      2. Resolves that tag to a full commit SHA
      3. Rewrites in-place as:  owner/repo@<sha>  # v<latest>

.PARAMETER WorkflowDir
    Path to the workflows folder. Default: .github/workflows

.PARAMETER Token
    GitHub PAT. Defaults to $env:GITHUB_TOKEN if not supplied.

.PARAMETER DryRun
    Prints changes without writing any files.

.PARAMETER ForceRefresh
    Bypass the cache and always fetch the latest tag.

.NOTES
    Requires: PowerShell 7+

.SYNTAX

    pin-actions-latest.ps1 [[-WorkflowDir] <String>] [[-Token] 
      <String>] [-DryRun | -n] [-ForceRefresh] [-Help] [<CommonParameters>]
#>

[CmdletBinding()]
param(
    [Alias('d')]
    [string]$WorkflowDir = ".github/workflows",

    [Alias('t')]
    [string]$Token = $env:GITHUB_TOKEN,

    [Alias('n')]
    [switch]$DryRun,

    [Alias('f')]
    [switch]$ForceRefresh,

    [Alias('h')]
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "No GitHub token found. Set the GITHUB_TOKEN environment variable or pass -Token."
    exit 1
}

$CacheFile = ".github/pin-cache.json"
$CacheTtlSeconds = 24 * 60 * 60

$cacheDir = Split-Path -Parent $CacheFile
if ($cacheDir -and -not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

if (Test-Path $CacheFile) {
    try {
        $Cache = Get-Content $CacheFile -Raw | ConvertFrom-Json -AsHashtable
        if ($null -eq $Cache) { $Cache = @{} }
    } catch {
        $Cache = @{}
    }
} else {
    $Cache = @{}
}

$Headers = @{
    Authorization = "Bearer $Token"
    "User-Agent"  = "pin-actions-latest-ps1"
    Accept        = "application/vnd.github+json"
}

function Get-CacheValue {
    param([string]$Action, [string]$Field)
    if ($Cache.ContainsKey($Action) -and $Cache[$Action].ContainsKey($Field)) {
        return $Cache[$Action][$Field]
    }
    return $null
}

function Set-CacheValue {
    param([string]$Action, [string]$Field, [string]$Value)
    if (-not $Cache.ContainsKey($Action)) {
        $Cache[$Action] = @{}
    }
    $Cache[$Action][$Field] = $Value
}

function Get-NowIso {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-SecondsSince {
    param([string]$IsoTimestamp)
    try {
        $ts = [datetime]::Parse(
            $IsoTimestamp,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        )
    } catch {
        return [double]::MaxValue
    }
    return ((Get-Date).ToUniversalTime() - $ts).TotalSeconds
}

function ConvertTo-SortableVersion {
    # Pads x, x.y, x.y.z out to a full [version] (x.y.z) so short tags sort
    # correctly against longer ones, mirroring `sort -V` behaviour.
    param([string]$Value)
    $v = $Value.TrimStart('v', 'V')
    $parts = $v.Split('.')
    while ($parts.Count -lt 3) { $parts += "0" }
    $parts = $parts[0..2]
    try {
        return [version]($parts -join '.')
    } catch {
        return [version]"0.0.0"
    }
}

function Test-IsOlderVersion {
    # Returns $true only if candidate is a genuinely older semver than current.
    # Anything that doesn't look like a plain semver is treated as "unknown"
    # and never blocks an update, since there is nothing to compare.
    param([string]$Candidate, [string]$Current)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Current)) {
        return $false
    }
    $semverPattern = '^v?\d+(\.\d+){0,2}$'
    if ($Candidate -notmatch $semverPattern -or $Current -notmatch $semverPattern) {
        return $false
    }
    if ($Candidate.TrimStart('v') -eq $Current.TrimStart('v')) {
        return $false
    }
    $candidateVersion = ConvertTo-SortableVersion $Candidate
    $currentVersion = ConvertTo-SortableVersion $Current
    return ($candidateVersion -lt $currentVersion)
}

function Invoke-GitHubApi {
    # Wraps Invoke-RestMethod and normalises errors down to a status code,
    # since the caller only ever needs to branch on 200 vs "anything else".
    param([string]$Uri)
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -StatusCodeVariable statusCode -ErrorAction Stop
        return @{ StatusCode = 200; Body = $response }
    } catch {
        $status = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        return @{ StatusCode = $status; Body = $null; Error = $_ }
    }
}

function Get-LatestTag {
    param([string]$Action)

    if (-not $ForceRefresh) {
        $cachedTag = Get-CacheValue -Action $Action -Field "latestTag"
        $cachedChecked = Get-CacheValue -Action $Action -Field "lastChecked"
        if ($cachedTag -and $cachedChecked) {
            $age = Get-SecondsSince -IsoTimestamp $cachedChecked
            if ($age -lt $CacheTtlSeconds) {
                return $cachedTag
            }
        }
    }

    # Primary source of truth: scan the FULL tag list and pick the highest
    # semantic version. We deliberately do NOT trust /releases/latest as
    # authoritative here: that endpoint returns the release with the most
    # recent *publish event*, not the highest version number. If a
    # maintainer edits or re-publishes an old release (changelog fix,
    # security note, archival cleanup, etc.), its published_at timestamp
    # bumps and GitHub will report it as "latest" even though far newer
    # tags exist - which is exactly what happened with actions/setup-java
    # returning v1.4.5 while v5.7.0 existed.
    $allTags = New-Object System.Collections.Generic.List[string]
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $result = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Action/tags?per_page=100&page=$page"
        if ($result.StatusCode -ne 200) {
            Write-Warning "GET /repos/$Action/tags (page $page) returned HTTP $($result.StatusCode)"
            if ($result.StatusCode -eq 403) {
                Write-Warning "  -> looks like a rate limit (check GITHUB_TOKEN is valid and authenticating)."
            }
            break
        }
        foreach ($t in $result.Body) { $allTags.Add($t.name) }
        if ($result.Body.Count -lt 100) { break }
        $page++
    }

    $tag = $allTags |
        Where-Object { $_ -match '^v?\d+(\.\d+){0,2}$' } |
        Sort-Object -Property @{ Expression = { ConvertTo-SortableVersion $_ } } |
        Select-Object -Last 1

    # Fallback: repo has no semver-looking tags at all (rare - e.g. an
    # action that only ever cuts GitHub Releases without matching git
    # tags). Only in that case do we trust /releases/latest.
    if (-not $tag) {
        $result = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Action/releases/latest"
        if ($result.StatusCode -eq 200) {
            $tag = $result.Body.tag_name
        } else {
            Write-Warning "GET /repos/$Action/releases/latest returned HTTP $($result.StatusCode)"
        }
    }

    if (-not $tag) {
        Write-Warning "Could not determine a usable tag for $Action from tags or releases."
    }

    if ($tag) {
        Set-CacheValue -Action $Action -Field "latestTag" -Value $tag
        Set-CacheValue -Action $Action -Field "lastChecked" -Value (Get-NowIso)
        return $tag
    }

    $cachedTag = Get-CacheValue -Action $Action -Field "latestTag"
    if ($cachedTag) {
        Write-Warning "Failed to fetch latest tag for $Action - using cached (possibly stale) tag."
        return $cachedTag
    }

    return $null
}

function Get-CommitSha {
    param([string]$Action, [string]$Ref)

    $cachedTag = Get-CacheValue -Action $Action -Field "latestTag"
    $cachedSha = Get-CacheValue -Action $Action -Field "sha"
    if ($cachedTag -eq $Ref -and $cachedSha) {
        return $cachedSha
    }

    $result = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Action/commits/$Ref"
    $sha = $null
    if ($result.StatusCode -eq 200) {
        $sha = $result.Body.sha
    } else {
        Write-Warning "GET /repos/$Action/commits/$Ref returned HTTP $($result.StatusCode)"
    }

    if ($sha) {
        Set-CacheValue -Action $Action -Field "sha" -Value $sha
        if (-not (Get-CacheValue -Action $Action -Field "lastChecked")) {
            Set-CacheValue -Action $Action -Field "lastChecked" -Value (Get-NowIso)
        }
        return $sha
    }

    if ($cachedSha) {
        Write-Warning "Failed to fetch SHA for $Action@$Ref - using cached SHA."
        return $cachedSha
    }

    return $null
}

if (-not (Test-Path $WorkflowDir -PathType Container)) {
    Write-Error "Workflow directory not found: $WorkflowDir"
    exit 1
}

# Matches:  [leading ws][- ]uses: owner/repo[/path]@ref [# comment]
$UsesPattern = '^(?<prefix>\s*(-\s*)?uses:\s*)(?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?)@(?<ref>[^\s#]+)(?<comment>\s*#.*)?$'
$TagInCommentPattern = 'v?\d+(\.\d+){0,2}'

$AnyUpdates = $false
$workflowFiles = Get-ChildItem -Path $WorkflowDir -Filter "*.yml" -File -ErrorAction SilentlyContinue

foreach ($file in $workflowFiles) {
    $fileChanged = $false
    $originalLines = Get-Content -Path $file.FullName
    $newLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $originalLines) {
        if ($line -match $UsesPattern) {
            $prefix = $Matches['prefix']
            $action = $Matches['action']
            $currentComment = $Matches['comment']

            # Fixed: no comment on the line just means no current tag to
            # compare against - not something that needs an external
            # pipeline that can fail on an empty match.
            $currentTag = $null
            if ($currentComment -and ($currentComment -match $TagInCommentPattern)) {
                $currentTag = $Matches[0]
            }

            if ($action.StartsWith("./")) {
                $newLines.Add($line)
                continue
            }

            $repoParts = $action -split '/'
            $repo = "$($repoParts[0])/$($repoParts[1])"

            $latestTag = Get-LatestTag -Action $repo
            if (-not $latestTag) {
                $newLines.Add($line)
                continue
            }

            if ($currentTag -and (Test-IsOlderVersion -Candidate $latestTag -Current $currentTag)) {
                Write-Warning "Resolved tag $latestTag for $action is older than currently pinned $currentTag - skipping to avoid a downgrade."
                $newLines.Add($line)
                continue
            }

            $sha = Get-CommitSha -Action $repo -Ref $latestTag
            if (-not $sha) {
                $newLines.Add($line)
                continue
            }

            $newLine = "$prefix$action@$sha # $latestTag"

            if ($newLine -ne $line) {
                "[Update] {0,-45} -> {1}  ({2}...)" -f $action, $latestTag, $sha.Substring(0, 12) | Write-Host
                $fileChanged = $true
                $AnyUpdates = $true
            }

            $newLines.Add($newLine)
        } else {
            $newLines.Add($line)
        }
    }

    if ($fileChanged -and -not $DryRun) {
        Set-Content -Path $file.FullName -Value $newLines
        Write-Host "[File updated] $($file.Name)"
    }
}

$Cache | ConvertTo-Json -Depth 10 | Set-Content -Path $CacheFile

if (-not $AnyUpdates) {
    Write-Host "No updates needed."
} else {
    Write-Host "Done."
}