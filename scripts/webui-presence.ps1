<#
.SYNOPSIS
    Logs when the router's web interface changes its mind about whether one device is online (ID-165).

.DESCRIPTION
    The web interface's client list is filled from the router's `appGet.cgi?hook=get_clientlist()`,
    the same call the ASUS Router phone app makes. This logs in the way that app does, asks every few
    seconds, and prints a line only when the device's `isOnline` changes, with the time. Run it beside
    scripts/presence-probe.sh on the router, and the two logs say which router source follows the
    web interface, with nobody watching a screen.

    Reads only. Changes nothing on the router. The password is asked for when it starts and is never
    written anywhere.

    Stop it with Ctrl+C. It logs out on the way.

.PARAMETER Router
    The web interface's address as you open it in a browser, e.g. https://192.168.1.1:8443 or
    http://192.168.1.1.

.PARAMETER Mac
    The device's MAC address, as DEVICES shows it.

.PARAMETER Every
    Seconds between checks. Default 5.

.PARAMETER Log
    Where the log goes as well as the screen. Default: webui-presence.log in your temp folder, outside
    the repo, because it holds the device's MAC.

.EXAMPLE
    pwsh scripts/webui-presence.ps1 -Router https://192.168.1.1:8443 -Mac AA:BB:CC:DD:EE:FF
#>
param(
    [Parameter(Mandatory)] [string] $Router,
    [Parameter(Mandatory)] [string] $Mac,
    [int] $Every = 5,
    [string] $Log = (Join-Path ([IO.Path]::GetTempPath()) 'webui-presence.log')
)

$ErrorActionPreference = 'Stop'
$Router = $Router.TrimEnd('/')
$Mac = $Mac.ToUpper()
if ($Mac -notmatch '^([0-9A-F]{2}:){5}[0-9A-F]{2}$') { throw "MAC must look like AA:BB:CC:DD:EE:FF, got '$Mac'" }

# The phone app's user agent. The router treats a login from it as the app's, and a web-browser
# login elsewhere is more likely to survive it.
$Agent = 'asusrouter-Android-DUTUtil-1.0.0.245'
$User = Read-Host 'Router web login name'
$Secure = Read-Host 'Router web password' -AsSecureString
$Session = $null

function Write-Line([string] $Text) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $Text"
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

function Connect-Router {
    $plain = [Net.NetworkCredential]::new('', $Secure).Password
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${User}:$plain"))
    $plain = $null
    $script:Session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $r = Invoke-WebRequest -Uri "$Router/login.cgi" -Method Post -SkipCertificateCheck -WebSession $script:Session `
        -UserAgent $Agent -Headers @{ Referer = "$Router/" } -ContentType 'application/x-www-form-urlencoded' `
        -Body "login_authorization=$auth"
    $json = $r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $json.asus_token) {
        # Several wrong passwords lock the web login for a few minutes, so stop at the first.
        throw "The router refused the login: $($r.Content.Trim()). Check the name and password; it does not retry."
    }
    $script:Session.Cookies.Add([Net.Cookie]::new('asus_token', $json.asus_token, '/', ([Uri]$Router).Host))
}

# The device's isOnline as the web interface would show it, or 'not listed'. $null when the answer
# was not a client list at all, which is what an expired login returns.
function Get-Online {
    $r = Invoke-WebRequest -Uri "$Router/appGet.cgi" -Method Post -SkipCertificateCheck -WebSession $script:Session `
        -UserAgent $Agent -Headers @{ Referer = "$Router/" } -ContentType 'application/x-www-form-urlencoded' `
        -Body 'hook=get_clientlist()'
    $json = $r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $list = $json.get_clientlist
    if (-not $list) { return $null }
    $entry = $list.PSObject.Properties | Where-Object { $_.Name.ToUpper() -eq $Mac } | Select-Object -First 1
    if (-not $entry) { return 'not listed' }
    return "isOnline $($entry.Value.isOnline)"
}

Connect-Router
Write-Line "== $(Get-Date -Format 'yyyy-MM-dd') web interface presence for $Mac, every ${Every}s, logging to $Log"
$was = $null
try {
    while ($true) {
        $now = Get-Online
        if ($null -eq $now) {
            Write-Line 'login expired, logging in again'
            Connect-Router
            $now = Get-Online
            if ($null -eq $now) { throw 'The router is not answering with a client list after logging in again.' }
        }
        if ($now -ne $was) {
            Write-Line "webui: $(if ($was) { $was } else { '(start)' }) -> $now"
            $was = $now
        }
        Start-Sleep -Seconds $Every
    }
}
finally {
    if ($script:Session) {
        try { Invoke-WebRequest -Uri "$Router/Logout.asp" -SkipCertificateCheck -WebSession $script:Session -UserAgent $Agent | Out-Null } catch { }
    }
}
