<#
.SYNOPSIS
    Pins GitHub Actions 'uses:' references to the commit SHA of their latest release, then checks every pin.

.DESCRIPTION
    For each action found in .github/workflows/*.yml (and *.yaml):
      1. Looks up the latest release tag via the GitHub API (cached with a 24h TTL)
      2. Resolves that tag to a full commit SHA (cached against the tag it was resolved from)
      3. Rewrites in-place as:  owner/repo@<sha> # v<latest>
    When the API cannot answer (offline, rate limit, bad token) the tag and SHA come from `git ls-remote`,
    which needs no token. Last of all every pin is checked against the tag named in its comment, again
    with `git ls-remote`.

    Each action gets one status line:
      ok          already pinned to its latest tag's commit
      UPDATED     a newer release was pinned
      FIXED       same version, but the pinned SHA was not that tag's commit
      PINNED      a tag or branch reference was replaced by a SHA
      SKIPPED     the newest tag is older than the pinned one (downgrade guard)
      UNRESOLVED  the tag or SHA could not be looked up; the line is left as it is

    Exit codes:
      0  every pin matches its tag, or could not be checked because git could not reach GitHub
      1  a pin does not match its tag, or the workflow directory is missing

.PARAMETER WorkflowDir
    Path to the workflows folder. Default: .github/workflows

.PARAMETER Token
    GitHub PAT. Defaults to $env:GITHUB_TOKEN. Without one the API allows 60 requests an hour.

.PARAMETER DryRun
    Prints changes without writing any workflow files. The check runs against the lines as they would be written.

.PARAMETER ForceRefresh
    Bypass the tag cache and always fetch the latest tag.

.PARAMETER Verbose
    Also print every API request and its HTTP status, tag counts, cache ages and git lookups.

.NOTES
    Requires: PowerShell 7+, git
    Set NO_COLOR to turn off colours.

.SYNTAX

    pin-actions-latest.ps1 [[-WorkflowDir] <String>] [[-Token] <String>] [-DryRun | -n] [-ForceRefresh | -f]
      [-Verbose | -v] [-Help | -h]
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
# build.ps1 turns this on, and a caller's preferences reach this script. git ls-remote failing is expected
# when offline and is handled here, so it must not throw.
$PSNativeCommandUseErrorActionPreference = $false
$Started = Get-Date

$ESC = [char]27
if ($env:NO_COLOR) {
    $GREEN = $YELLOW = $RED = $WHITE = $RESET = ""
} else {
    $GREEN = "$ESC[32m"; $YELLOW = "$ESC[33m"; $RED = "$ESC[31m"; $WHITE = "$ESC[97m"; $RESET = "$ESC[0m"
}

$CacheFile = ".github/pin-cache.json"
$CacheTtlSeconds = 24 * 60 * 60
$SemverPattern = '^v?\d+(\.\d+){0,2}$'
$ShaPattern = '^[0-9a-f]{40}$'
# Matches:  [leading ws][- ]uses: owner/repo[/path]@ref [# comment]
$UsesPattern = '^(?<prefix>\s*(-\s*)?uses:\s*)(?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?)@(?<ref>[^\s#]+)(?<comment>\s*#.*)?$'
$TagInCommentPattern = 'v?\d+(\.\d+){0,2}'

$cacheDir = Split-Path -Parent $CacheFile
if ($cacheDir -and -not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

$Cache = @{}
if (Test-Path $CacheFile) {
    try {
        $loaded = Get-Content $CacheFile -Raw | ConvertFrom-Json -AsHashtable
        if ($null -ne $loaded) { $Cache = $loaded }
    } catch {
        Write-Host "${YELLOW}  cache    $CacheFile is not valid JSON; starting empty${RESET}"
    }
}

$Headers = @{
    "User-Agent" = "pin-actions-latest-ps1"
    Accept       = "application/vnd.github+json"
}
if ($Token) { $Headers.Authorization = "Bearer $Token" }

$script:ApiCalls = 0
$script:ApiDown = $false
$RemoteTags = @{}

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

function Format-Age {
    param([double]$Seconds)
    if ($Seconds -lt 3600) { return "{0}m" -f [math]::Floor($Seconds / 60) }
    if ($Seconds -lt 172800) { return "{0}h" -f [math]::Floor($Seconds / 3600) }
    return "{0}d" -f [math]::Floor($Seconds / 86400)
}

function Get-ShortSha {
    param([string]$Sha)
    if ($Sha -and $Sha.Length -ge 12) { return $Sha.Substring(0, 12) }
    return $Sha
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

function Select-HighestSemver {
    # The highest plain semver tag; on a tie (v4 and v4.0.0) the longer, more specific name wins.
    param($Tags)
    return $Tags |
        Where-Object { $_ -match $SemverPattern } |
        Sort-Object -Property @{ Expression = { ConvertTo-SortableVersion $_ } }, @{ Expression = { $_.Length } } |
        Select-Object -Last 1
}

function Test-IsOlderVersion {
    # Returns $true only if candidate is a genuinely older semver than current.
    # Anything that doesn't look like a plain semver is treated as "unknown"
    # and never blocks an update, since there is nothing to compare.
    param([string]$Candidate, [string]$Current)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Current)) {
        return $false
    }
    if ($Candidate -notmatch $SemverPattern -or $Current -notmatch $SemverPattern) {
        return $false
    }
    if ($Candidate.TrimStart('v') -eq $Current.TrimStart('v')) {
        return $false
    }
    return ((ConvertTo-SortableVersion $Candidate) -lt (ConvertTo-SortableVersion $Current))
}

function Format-HttpStatus {
    param($Status)
    if (-not $Status) { return "no response" }
    if ($Status -eq 403 -or $Status -eq 429) { return "HTTP $Status (rate limit?)" }
    return "HTTP $Status"
}

function Invoke-GitHubApi {
    # Wraps Invoke-RestMethod and normalises errors down to a status code,
    # since the caller only ever needs to branch on 200 vs "anything else".
    param([string]$Uri)
    if ($script:ApiDown) {
        return @{ StatusCode = $null; Body = $null }
    }
    $script:ApiCalls++
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 20 -ErrorAction Stop
        Write-Verbose "GET $Uri -> 200"
        return @{ StatusCode = 200; Body = $response }
    } catch {
        $status = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        Write-Verbose "GET $Uri -> $(Format-HttpStatus $status) $($_.Exception.Message)"
        return @{ StatusCode = $status; Body = $null }
    }
}

function Get-RemoteTags {
    # Every tag in the repo mapped to the commit it points at, straight from git; $null when git cannot reach it.
    # Needs no token and uses no API quota, so it is both the fallback and the independent check.
    param([string]$Repo)
    if ($RemoteTags.ContainsKey($Repo)) { return $RemoteTags[$Repo] }
    $env:GIT_TERMINAL_PROMPT = "0"
    $lines = & git ls-remote --tags "https://github.com/$Repo.git" 2>$null
    $map = $null
    if ($LASTEXITCODE -eq 0) {
        $map = @{}
        foreach ($l in $lines) {
            if ($l -match '^([0-9a-f]{40})\s+refs/tags/(.+?)(\^\{\})?$') {
                # An annotated tag is listed twice; its ^{} line is the commit it points at, and wins.
                if ($Matches[3] -or -not $map.ContainsKey($Matches[2])) { $map[$Matches[2]] = $Matches[1] }
            }
        }
        Write-Verbose "git ls-remote $Repo -> $($map.Count) tags"
    } else {
        Write-Verbose "git ls-remote $Repo -> exit $LASTEXITCODE"
    }
    $RemoteTags[$Repo] = $map
    return $map
}

function Find-RemoteTag {
    # The tag name as git lists it, allowing for a comment that adds or drops the leading v.
    param($Remote, [string]$Tag)
    foreach ($name in @($Tag, "v$Tag", $Tag.TrimStart('v'))) {
        if ($Remote.ContainsKey($name)) { return $name }
    }
    return $null
}

function Get-TagForCommit {
    param([string]$Repo, [string]$Sha)
    $remote = Get-RemoteTags $Repo
    if ($null -eq $remote) { return "unknown, git could not reach GitHub" }
    $names = @($remote.GetEnumerator() | Where-Object { $_.Value -eq $Sha } | ForEach-Object { $_.Key })
    if ($names.Count -eq 0) { return "not a tagged commit" }
    $best = Select-HighestSemver $names
    if ($best) { return $best }
    return $names[0]
}

function Resolve-LatestTag {
    param([string]$Repo)

    $cachedTag = Get-CacheValue $Repo "latestTag"
    $cachedChecked = Get-CacheValue $Repo "lastChecked"
    if (-not $ForceRefresh -and $cachedTag -and $cachedChecked) {
        $age = Get-SecondsSince $cachedChecked
        if ($age -lt $CacheTtlSeconds) {
            Write-Verbose "$Repo cached tag $cachedTag, checked $(Format-Age $age) ago"
            return @{ Tag = $cachedTag; Source = "cache $(Format-Age $age)" }
        }
        Write-Verbose "$Repo cached tag $cachedTag is $(Format-Age $age) old, past the 24h TTL"
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
    $failure = $null
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $result = Invoke-GitHubApi "https://api.github.com/repos/$Repo/tags?per_page=100&page=$page"
        if ($result.StatusCode -ne 200) {
            $failure = "tags API $(Format-HttpStatus $result.StatusCode)"
            # A partial list could crown the wrong tag.
            $allTags.Clear()
            break
        }
        foreach ($t in $result.Body) { $allTags.Add($t.name) }
        if ($result.Body.Count -lt 100) { break }
        $page++
    }

    $tag = Select-HighestSemver $allTags
    $source = "API"
    if (-not $failure) {
        Write-Verbose "$Repo tags API: $($allTags.Count) tags over $page page(s), highest semver $tag"
    }

    # Fallback: repo has no semver-looking tags at all (rare - e.g. an
    # action that only ever cuts GitHub Releases without matching git
    # tags). Only in that case do we trust /releases/latest.
    if (-not $tag -and -not $failure) {
        $result = Invoke-GitHubApi "https://api.github.com/repos/$Repo/releases/latest"
        if ($result.StatusCode -eq 200) {
            $tag = $result.Body.tag_name
            $source = "releases API"
        } else {
            $failure = "no semver tags, releases API $(Format-HttpStatus $result.StatusCode)"
        }
    }

    if (-not $tag -and $failure) {
        $remote = Get-RemoteTags $Repo
        if ($remote) {
            $tag = Select-HighestSemver $remote.Keys
            $source = "git"
        }
    }

    if ($tag) {
        Set-CacheValue $Repo "latestTag" $tag
        Set-CacheValue $Repo "lastChecked" (Get-NowIso)
        return @{ Tag = $tag; Source = $source }
    }

    if ($cachedTag) {
        return @{ Tag = $cachedTag; Source = "stale cache, $failure" }
    }

    if (-not $failure) { $failure = "no usable tag in tags or releases" }
    return @{ Tag = $null; Failure = "$failure, git could not list tags" }
}

function Resolve-CommitSha {
    param([string]$Repo, [string]$Tag)

    $cachedSha = Get-CacheValue $Repo "sha"
    $cachedShaTag = Get-CacheValue $Repo "shaTag"
    Write-Verbose "$Repo cached sha $(Get-ShortSha $cachedSha) is for tag $(if ($cachedShaTag) { $cachedShaTag } else { '(not recorded)' })"
    # A cached SHA is only good for the tag it was resolved from. Matching on latestTag instead once paired a
    # freshly found tag with the previous tag's SHA, and wrote that pair into the workflows.
    if ($cachedSha -and $cachedShaTag -eq $Tag) {
        return @{ Sha = $cachedSha; Source = "cache" }
    }

    $sha = $null
    $source = $null
    $result = Invoke-GitHubApi "https://api.github.com/repos/$Repo/commits/$Tag"
    if ($result.StatusCode -eq 200 -and $result.Body.sha) {
        $sha = $result.Body.sha
        $source = "API"
    } else {
        $failure = "commits API $(Format-HttpStatus $result.StatusCode)"
        $remote = Get-RemoteTags $Repo
        $name = if ($remote) { Find-RemoteTag $remote $Tag } else { $null }
        if ($name) {
            $sha = $remote[$name]
            $source = "git"
        }
    }

    if ($sha) {
        Set-CacheValue $Repo "sha" $sha
        Set-CacheValue $Repo "shaTag" $Tag
        return @{ Sha = $sha; Source = $source }
    }
    return @{ Sha = $null; Failure = "$failure, git could not resolve it" }
}

###############################################################################
# Find every uses: line
###############################################################################
if (-not (Test-Path $WorkflowDir -PathType Container)) {
    Write-Host "${RED}Workflow directory not found: $WorkflowDir${RESET}"
    exit 1
}

$files = @(Get-ChildItem -Path $WorkflowDir -File | Where-Object { $_.Extension -in '.yml', '.yaml' } | Sort-Object Name)
$fileLines = @{}
$fileNewline = @{}
$entries = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    # Read and write the raw text so line endings and the final newline survive the rewrite.
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $fileNewline[$file.FullName] = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $fileLines[$file.FullName] = $lines
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch $UsesPattern -or $Matches['action'].StartsWith('./')) { continue }
        $action = $Matches['action']
        $entry = [pscustomobject]@{
            File     = $file
            Index    = $i
            Original = $lines[$i]
            Prefix   = $Matches['prefix']
            Action   = $action
            Repo     = (($action -split '/')[0..1] -join '/')
            Ref      = $Matches['ref']
            Tag      = $null
            NewLine  = $lines[$i]
            Status   = $null
            Detail   = $null
        }
        $comment = $Matches['comment']
        if ($comment -and $comment -match $TagInCommentPattern) { $entry.Tag = $Matches[0] }
        $entries.Add($entry)
    }
}

$repos = @($entries | ForEach-Object { $_.Repo } | Select-Object -Unique)

###############################################################################
# Header
###############################################################################
Write-Host "${WHITE}Pin GitHub Actions${RESET}: $($files.Count) workflow files, $($entries.Count) uses: lines, $($repos.Count) actions"

if ($Token) {
    $rate = Invoke-GitHubApi "https://api.github.com/rate_limit"
    $script:ApiCalls--   # the quota check is free
    if ($rate.StatusCode -eq 200) {
        $core = $rate.Body.resources.core
        # Not $reset: PowerShell names ignore case, and that would overwrite $RESET.
        $quotaResetsAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$core.reset).ToLocalTime().ToString("HH:mm")
        $colour = if ($core.remaining -lt 100) { $YELLOW } else { "" }
        Write-Host "${colour}  token    set (API quota $($core.remaining) of $($core.limit) left, resets $quotaResetsAt)${RESET}"
    } elseif ($rate.StatusCode -eq 401) {
        $script:ApiDown = $true
        Write-Host "${YELLOW}  token    rejected (HTTP 401): check GITHUB_TOKEN; looking up with git instead${RESET}"
    } else {
        $script:ApiDown = $true
        Write-Host "${YELLOW}  token    set, but the GitHub API gave $(Format-HttpStatus $rate.StatusCode); looking up with git and the cache${RESET}"
    }
} else {
    Write-Host "${YELLOW}  token    not set: unauthenticated API, 60 requests an hour${RESET}"
}

$cacheNote = if ($ForceRefresh) { ", tags bypassed (-ForceRefresh)" } else { "" }
Write-Host "  cache    $CacheFile, $($Cache.Count) entries, 24h TTL$cacheNote"
if ($DryRun) {
    Write-Host "${YELLOW}  mode     DRY RUN, no workflow file is written${RESET}"
} else {
    Write-Host "  mode     write"
}

if ($entries.Count -eq 0) {
    Write-Host ""
    Write-Host "  No uses: lines found."
    exit 0
}

###############################################################################
# List every repo's tags with git, in parallel: one at a time is most of a minute
###############################################################################
$gitStarted = Get-Date
$repos | ForEach-Object -ThrottleLimit 8 -Parallel {
    $env:GIT_TERMINAL_PROMPT = "0"
    $lines = & git ls-remote --tags "https://github.com/$_.git" 2>$null
    $map = $null
    if ($LASTEXITCODE -eq 0) {
        $map = @{}
        foreach ($l in $lines) {
            if ($l -match '^([0-9a-f]{40})\s+refs/tags/(.+?)(\^\{\})?$') {
                # An annotated tag is listed twice; its ^{} line is the commit it points at, and wins.
                if ($Matches[3] -or -not $map.ContainsKey($Matches[2])) { $map[$Matches[2]] = $Matches[1] }
            }
        }
    }
    [pscustomobject]@{ Repo = $_; Map = $map; Exit = $LASTEXITCODE }
} | ForEach-Object {
    $RemoteTags[$_.Repo] = $_.Map
    $found = if ($null -eq $_.Map) { "exit $($_.Exit)" } else { "$($_.Map.Count) tags" }
    Write-Verbose "git ls-remote $($_.Repo) -> $found"
}
$reachable = @($RemoteTags.Values | Where-Object { $null -ne $_ }).Count
$gitColour = if ($reachable -lt $repos.Count) { $YELLOW } else { "" }
Write-Host ("${gitColour}  git      tags listed for {0} of {1} actions in {2:N1}s${RESET}" -f $reachable, $repos.Count, ((Get-Date) - $gitStarted).TotalSeconds)
Write-Host ""

###############################################################################
# Resolve each action and decide what its lines become
###############################################################################
$counts = [ordered]@{ FIXED = 0; UPDATED = 0; PINNED = 0; ok = 0; SKIPPED = 0; UNRESOLVED = 0 }

foreach ($repo in $repos) {
    $mine = @($entries | Where-Object { $_.Repo -eq $repo })
    $latest = Resolve-LatestTag $repo
    $shaResult = if ($latest.Tag) { Resolve-CommitSha $repo $latest.Tag } else { $null }

    foreach ($e in $mine) {
        if (-not $latest.Tag) {
            $e.Status = "UNRESOLVED"
            $e.Detail = "$($latest.Failure); line left as it is"
            continue
        }
        if ($e.Tag -and (Test-IsOlderVersion -Candidate $latest.Tag -Current $e.Tag)) {
            $e.Status = "SKIPPED"
            $e.Detail = "newest tag $($latest.Tag) is older than pinned $($e.Tag)"
            continue
        }
        if (-not $shaResult.Sha) {
            $e.Status = "UNRESOLVED"
            $e.Detail = "no SHA for $($latest.Tag): $($shaResult.Failure); line left as it is"
            continue
        }

        $sha = $shaResult.Sha
        $e.NewLine = "$($e.Prefix)$($e.Action)@$sha # $($latest.Tag)"
        if ($e.NewLine -eq $e.Original) {
            $e.Status = "ok"
            $e.Detail = "tag $($latest.Source), sha $($shaResult.Source)"
        } elseif ($e.Ref -notmatch $ShaPattern) {
            $e.Status = "PINNED"
            $e.Detail = "@$($e.Ref) -> $(Get-ShortSha $sha)"
        } elseif ($e.Ref -eq $sha) {
            $e.Status = "UPDATED"
            $e.Detail = "comment only, now # $($latest.Tag)"
        } elseif ($e.Tag -and $e.Tag.TrimStart('v') -eq $latest.Tag.TrimStart('v')) {
            $e.Status = "FIXED"
            $e.Detail = "$(Get-ShortSha $e.Ref) -> $(Get-ShortSha $sha) (old SHA: $(Get-TagForCommit $repo $e.Ref))"
        } else {
            $was = if ($e.Tag) { $e.Tag } else { "untagged" }
            $e.Status = "UPDATED"
            $e.Detail = "$was -> $($latest.Tag), $(Get-ShortSha $e.Ref) -> $(Get-ShortSha $sha)"
        }
    }

    foreach ($g in @($mine | Group-Object -Property Status, Detail)) {
        $e = $g.Group[0]
        $counts[$e.Status] += $g.Count
        $name = if ($g.Count -gt 1) { "$repo x$($g.Count)" } else { $repo }
        $tagShown = if ($e.Status -in 'SKIPPED', 'UNRESOLVED') { $e.Tag } else { $latest.Tag }
        $colour = switch ($e.Status) {
            'ok' { "" }
            { $_ -in 'SKIPPED', 'UNRESOLVED' } { $YELLOW }
            default { $GREEN }
        }
        Write-Host ("  {0,-36} {1,-9} {2}{3,-10}{4} {5}" -f $name, $tagShown, $colour, $e.Status, $RESET, $e.Detail)
    }
}
Write-Host ""

###############################################################################
# Write the workflow files and the cache
###############################################################################
$written = New-Object System.Collections.Generic.List[string]
foreach ($fg in @($entries | Group-Object -Property { $_.File.FullName })) {
    $changed = @($fg.Group | Where-Object { $_.NewLine -ne $_.Original })
    if ($changed.Count -eq 0) { continue }
    $lines = $fileLines[$fg.Name]
    foreach ($c in $changed) { $lines[$c.Index] = $c.NewLine }
    if (-not $DryRun) {
        $text = $lines -join $fileNewline[$fg.Name]
        [System.IO.File]::WriteAllText($fg.Name, $text, (New-Object System.Text.UTF8Encoding $false))
    }
    $plural = if ($changed.Count -eq 1) { "" } else { "s" }
    $written.Add("$($fg.Group[0].File.Name) ($($changed.Count) line$plural)")
}

if ($written.Count -eq 0) {
    Write-Host "  written  nothing, every line is already current"
} elseif ($DryRun) {
    Write-Host "${YELLOW}  written  nothing (DRY RUN); would write $($written -join ', ')${RESET}"
} else {
    Write-Host "${GREEN}  written  $($written -join ', ')${RESET}"
}

$Cache | ConvertTo-Json -Depth 10 | Set-Content -Path $CacheFile
Write-Verbose "cache saved to $CacheFile, $($Cache.Count) entries"

###############################################################################
# Check every pin against its tag with git, independently of the API and the cache
###############################################################################
$verified = 0
$mismatches = New-Object System.Collections.Generic.List[string]
$unverified = New-Object System.Collections.Generic.List[string]
$unpinned = New-Object System.Collections.Generic.List[string]

foreach ($e in $entries) {
    if ($e.NewLine -notmatch $UsesPattern) { continue }
    $ref = $Matches['ref']
    $comment = $Matches['comment']
    $tag = if ($comment -and $comment -match $TagInCommentPattern) { $Matches[0] } else { $null }
    if ($ref -notmatch $ShaPattern) {
        $unpinned.Add("$($e.Action)@$ref is not pinned to a SHA")
        continue
    }
    if (-not $tag) {
        $unpinned.Add("$($e.Action) has no tag in its comment to check against")
        continue
    }
    $remote = Get-RemoteTags $e.Repo
    if ($null -eq $remote) {
        $unverified.Add($e.Action)
        continue
    }
    $name = Find-RemoteTag $remote $tag
    if (-not $name) {
        $mismatches.Add("$($e.Action) # ${tag}: no such tag")
    } elseif ($remote[$name] -ne $ref) {
        $mismatches.Add("$($e.Action) # ${tag}: pinned $(Get-ShortSha $ref) is $(Get-TagForCommit $e.Repo $ref), the tag is $(Get-ShortSha $remote[$name])")
    } else {
        $verified++
    }
}

$checkedWhat = if ($DryRun) { "as they would be written" } else { "git ls-remote" }
if ($mismatches.Count -gt 0) {
    Write-Host "${RED}  verify   FAILED: $($mismatches.Count) of $($entries.Count) pins do not match their tag ($checkedWhat)${RESET}"
    foreach ($m in $mismatches) { Write-Host "${RED}             $m${RESET}" }
} elseif ($verified -gt 0 -or $unverified.Count -eq 0) {
    $colour = if ($verified -eq $entries.Count) { $GREEN } else { "" }
    Write-Host "${colour}  verify   $verified of $($entries.Count) pins match their tag ($checkedWhat)${RESET}"
}
if ($unverified.Count -gt 0) {
    $unreached = @($unverified | ForEach-Object { ($_ -split '/')[0..1] -join '/' } | Select-Object -Unique)
    Write-Host "${YELLOW}  verify   $($unverified.Count) of $($entries.Count) pins not checked, git could not reach GitHub for: $($unreached -join ', ')${RESET}"
}
foreach ($u in $unpinned) { Write-Host "${YELLOW}  verify   $u${RESET}" }

###############################################################################
# Summary
###############################################################################
$summary = ($counts.GetEnumerator() | ForEach-Object { "$($_.Value) $($_.Key)" }) -join ", "
$elapsed = "{0:N1}s" -f ((Get-Date) - $Started).TotalSeconds
$resultColour = if ($mismatches.Count -gt 0) { $RED } elseif ($counts.SKIPPED + $counts.UNRESOLVED + $unverified.Count -gt 0) { $YELLOW } else { $GREEN }
Write-Host "${resultColour}  result   $summary; $($script:ApiCalls) API calls; $elapsed${RESET}"

if ($mismatches.Count -gt 0) { exit 1 }
exit 0
