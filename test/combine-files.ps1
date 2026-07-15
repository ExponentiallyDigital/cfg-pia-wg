# Path to your test directory
$testDir = "C:\Users\andrew\Documents\GitHubRepos\tools\cfg-pia-wg\test"

# Output file
$outputFile = "C:\Users\andrew\Documents\GitHubRepos\tools\cfg-pia-wg\test\combined_tests.txt"

# Remove output file if it already exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

# Get all .dart test files
$files = Get-ChildItem -Path $testDir -Filter "*.dart"

foreach ($file in $files) {
    # Write delimiter header
    Add-Content -Path $outputFile -Value "===== START FILE: $($file.Name) ====="
    Add-Content -Path $outputFile -Value ""

    # Append file contents
    Get-Content -Path $file.FullName | Add-Content -Path $outputFile

    # Write delimiter footer
    Add-Content -Path $outputFile -Value ""
    Add-Content -Path $outputFile -Value "===== END FILE: $($file.Name) ====="
    Add-Content -Path $outputFile -Value ""
}

Write-Host "Combined file created at: $outputFile"
