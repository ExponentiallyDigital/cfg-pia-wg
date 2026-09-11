<# function: extract-with-context.ps1

.SYNOPSIS:
    This script reads a text file or piped input, searches for lines containing a specified keyword, and outputs
    those lines along with one line before and after each match. If multiple matches are found, it will also indicate
    removed sections with "...".

.USAGE:
    .\extract-with-context.ps1 -FilePath "path\to\file.txt" [-Keyword "cfg-pia-wg_cru"]

#>

param(
    [string]$FilePath,
    [string]$Keyword = "cfg-pia-wg_cru"
)

# Read all lines from file or stdin
if ($FilePath) {
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        exit 1
    }
    $lines = Get-Content $FilePath
} else {
    $lines = @($input)  # if piped input
    if ($lines.Count -eq 0) {
        Write-Error "No input provided. Specify -FilePath or pipe content."
        exit 1
    }
}

$count = $lines.Count
$keep = [bool[]]::new($count)

# Mark kept lines: matches and their immediate neighbors
for ($i = 0; $i -lt $count; $i++) {
    if ($lines[$i] -match $Keyword) {
        $keep[$i] = $true
        if ($i -gt 0)       { $keep[$i-1] = $true }
        if ($i -lt $count-1) { $keep[$i+1] = $true }
    }
}

# Output: kept lines, and "..." for each contiguous removed block
$inRemovedBlock = $false
for ($i = 0; $i -lt $count; $i++) {
    if ($keep[$i]) {
        if ($inRemovedBlock) {
            # We just exited a removed block; we already printed "...", so reset flag
            $inRemovedBlock = $false
        }
        Write-Output $lines[$i]
    } else {
        if (-not $inRemovedBlock) {
            Write-Output "..."
            $inRemovedBlock = $true
        }
        # else still in removed block, do nothing extra
    }
}
# If the file ends with a removed block, we've already printed "...", so no extra needed.