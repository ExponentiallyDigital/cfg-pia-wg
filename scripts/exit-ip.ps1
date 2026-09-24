# exit-ip.ps1 - where this computer's internet traffic leaves, in one line (ID-207).
#
#   pwsh scripts/exit-ip.ps1              # print the exit address, country, city and provider
#   pwsh scripts/exit-ip.ps1 -Expect NZ   # PASS if it leaves in New Zealand, FAIL otherwise
#   pwsh scripts/exit-ip.ps1 -Expect BLOCKED
#
# The device-side half of scripts/e2e.sh: that one says where the router would send this device's
# traffic, this one proves where it actually came out. -Expect takes a two-letter country code, a
# word from the provider's name, or BLOCKED for a device that should have no internet at all.
param([string]$Expect = '')

try {
    $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 10
    $got = "$($r.ip)  $($r.country)  $($r.city)  $($r.org)"
    $blocked = $false
} catch {
    $got = 'BLOCKED (no answer in 10 seconds)'
    $blocked = $true
}
Write-Output $got
if ($Expect -eq '') { exit 0 }

$pass = if ($Expect -eq 'BLOCKED') { $blocked } else { -not $blocked -and ($r.country -eq $Expect -or $r.org -match [regex]::Escape($Expect)) }
if ($pass) { Write-Output 'PASS'; exit 0 }
Write-Output "FAIL: expected $Expect"
exit 1
