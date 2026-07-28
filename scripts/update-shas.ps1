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
.PARAMETER WhatIf
    Dry-run — prints changes without writing any files.
.PARAMETER ForceRefresh
    Bypass the cache and always fetch the latest tag from GitHub.
#>
param(
    [string]$WorkflowDir = ".github/workflows",
    [string]$Token       = $env:GITHUB_TOKEN,
    [switch]$WhatIf,
    [switch]$ForceRefresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Token) {
    throw "No GitHub token found. Set the GITHUB_TOKEN environment variable or pass -Token."
}

$CacheFile = ".github/pin-cache.json"
$CacheTTL  = [TimeSpan]::FromHours(24)
$PersistentCache = @{}

$headers = @{ "User-Agent" = "pin-actions-latest-ps1"; "Authorization" = "Bearer $Token" }

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)
    $hash = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
            $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
        } else {
            $hash[$prop.Name] = $prop.Value
        }
    }
    return $hash
}

if (Test-Path $CacheFile) {
    try {
        $PersistentCache = Get-Content $CacheFile | ConvertFrom-Json | ConvertTo-Hashtable
    } catch {
        $PersistentCache = @{}
    }
}

function Get-LatestTag {
    param([string]$Action)

    if (-not $ForceRefresh -and $PersistentCache.ContainsKey($Action)) {
        $entry = $PersistentCache[$Action]
        if ($entry.ContainsKey('lastChecked') -and $entry.ContainsKey('latestTag')) {
            $lastChecked = [datetime]$entry.lastChecked
            if ((Get-Date) - $lastChecked -lt $CacheTTL) {
                return $entry.latestTag
            }
        }
    }

    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Action/releases/latest" `
                                 -Headers $headers -ErrorAction Stop
        $tag = $rel.tag_name
        $PersistentCache[$Action] = @{
            latestTag   = $tag
            sha         = $null
            lastChecked = (Get-Date).ToString("o")
        }
        return $tag
    } catch {}

    try {
        $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/$Action/tags?per_page=1" `
                                  -Headers $headers -ErrorAction Stop
        if ($tags.Count -gt 0) {
            $tag = $tags[0].name
            $PersistentCache[$Action] = @{
                latestTag   = $tag
                sha         = $null
                lastChecked = (Get-Date).ToString("o")
            }
            return $tag
        }
    } catch {}

    if ($PersistentCache.ContainsKey($Action) -and $PersistentCache[$Action].ContainsKey('latestTag')) {
        Write-Warning "Failed to fetch latest tag for $Action – using cached (possibly stale) tag."
        return $PersistentCache[$Action].latestTag
    }

    return $null
}

function Get-CommitSha {
    param([string]$Action, [string]$Ref)

    if ($PersistentCache.ContainsKey($Action)) {
        $entry = $PersistentCache[$Action]
        if ($entry.latestTag -eq $Ref -and $entry.sha) {
            return $entry.sha
        }
    }

    try {
        $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$Action/commits/$Ref" `
                                    -Headers $headers -ErrorAction Stop

        if (-not $PersistentCache.ContainsKey($Action)) {
            $PersistentCache[$Action] = @{}
        }
        $PersistentCache[$Action].sha = $commit.sha
        if (-not $PersistentCache[$Action].ContainsKey('lastChecked')) {
            $PersistentCache[$Action].lastChecked = (Get-Date).ToString("o")
        }
        return $commit.sha
    } catch {
        if ($PersistentCache.ContainsKey($Action) -and $PersistentCache[$Action].sha) {
            Write-Warning "Failed to fetch SHA for $Action@$Ref – using cached SHA."
            return $PersistentCache[$Action].sha
        }
        return $null
    }
}

$files = Get-ChildItem -Path $WorkflowDir -Filter "*.yml" -File -ErrorAction Stop
$anyUpdates = $false

foreach ($file in $files) {
    $lines       = Get-Content $file.FullName
    $newLines    = [System.Collections.Generic.List[string]]::new()
    $fileChanged = $false

    foreach ($line in $lines) {
        if ($line -match '^(\s*(?:-\s*)?uses:\s*)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_./-]+)?)@([^\s#]+)(\s*#.*)?$') {
            $prefix = $Matches[1]
            $action = $Matches[2]
            $currentRef = $Matches[3]

            if ($action -like "./*") {
                $newLines.Add($line)
                continue
            }

            $parts = $action -split '/', 3
            $repo  = $parts[0] + '/' + $parts[1]

            $latestTag = Get-LatestTag -Action $repo
            if ($null -eq $latestTag) {
                $newLines.Add($line)
                continue
            }

            $sha = Get-CommitSha -Action $repo -Ref $latestTag
            if ($null -eq $sha) {
                $newLines.Add($line)
                continue
            }

            # 🟢 Replace the whole comment with the new version tag
            $newLine = "$prefix$action@$sha # $latestTag"

            if ($newLine -ne $line) {
                Write-Host ("[Update] {0,-45} {1} -> {2}  ({3})" -f $action, $currentRef, $latestTag, $sha.Substring(0,12) + "...") -ForegroundColor Green
                $fileChanged = $true
                $anyUpdates  = $true
            }

            $newLines.Add($newLine)
        } else {
            $newLines.Add($line)
        }
    }

    if ($fileChanged -and -not $WhatIf) {
        $newLines | Set-Content $file.FullName -Encoding UTF8
        Write-Host "[File Updated] $($file.Name)" -ForegroundColor Cyan
    }
}

$PersistentCache | ConvertTo-Json -Depth 5 | Set-Content $CacheFile -Encoding UTF8

if (-not $anyUpdates) {
    Write-Host "No updates needed." -ForegroundColor DarkGray
} else {
    Write-Host "Done." -ForegroundColor Green
}