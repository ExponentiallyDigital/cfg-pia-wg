<#
.SYNOPSIS
Builder script

.VERSION
0.3.0
#>

###############################################################################
# Strict mode
###############################################################################
$ErrorActionPreference = 'Stop'
# $ErrorActionPreference only covers cmdlets. Without this a failing flutter analyze or flutter test
# does not stop the script, and it goes on to build and report success.
$PSNativeCommandUseErrorActionPreference = $true

###############################################################################
# ANSI colors (Using Escape character for cross-version support)
###############################################################################
$ESC = [char]27
$CYAN = "$ESC[36m"
$GREEN = "$ESC[32m"
$WHITE = "$ESC[97m"
$YELLOW = "$ESC[33m"
$MAGENTA = "$ESC[35m"
$RED = "$ESC[31m"
$RESET = "$ESC[0m"

###############################################################################
# Error trap: say what failed, not just where
###############################################################################
trap {
    Write-Host "${RED}✖ Build failed at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())${RESET}"
    Write-Host "${RED}  $($_.Exception.Message)${RESET}"
    try { Stop-Transcript | Out-Null } catch { }
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

function Stop-Build {
    param([string]$Message)
    Write-Host "${RED}✖ $Message Build stopped.${RESET}"
    try { Stop-Transcript | Out-Null } catch { }
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

###############################################################################
# Help message (shown when no arguments provided)
###############################################################################
if ($args.Count -eq 0) {
    Write-Host "${WHITE}Flutter build script${RESET}"
    Write-Host ""
    Write-Host "${CYAN}Usage:${RESET}"
    Write-Host "  .\scripts\build.ps1 [mode] [options]"
    Write-Host ""
    Write-Host "${CYAN}Modes:${RESET}"
    Write-Host "  all         Build everything"
    Write-Host "  debug       Build only the debug APK"
    Write-Host "  release     Build only the release APK"
    Write-Host "  aab         Build only the Play Store AAB"
    Write-Host ""
    Write-Host "${CYAN}Options:${RESET}"
    Write-Host "  --no-clean   Skip running 'flutter clean'"
    Write-Host "  --skip-test  Skip running analyze and tests"
    Write-Host "  --skip-icons Skip generating icons (use existing)"
    Write-Host "  --skip-pin   Skip pinning and checking the GitHub action SHAs"
    Write-Host ""
    Write-Host "${CYAN}Examples:${RESET}"
    Write-Host "  .\scripts\build.ps1 all"
    Write-Host "  .\scripts\build.ps1 release --no-clean"
    Write-Host "  .\scripts\build.ps1 debug"
    Write-Host ""
    exit 0
}

###############################################################################
# Parse command-line arguments
###############################################################################
$MODE = "all"
$RUN_CLEAN = $true
$SKIP_TEST = $false
$SKIP_ICONS = $false
$SKIP_PIN = $false

foreach ($arg in $args) {
    switch -Regex ($arg) {
        "^(debug|release|aab|all)$" { $MODE = $arg }
        "^--no-clean$" { $RUN_CLEAN = $false }
        "^--clean$" { $RUN_CLEAN = $true }
        "^--skip-test$" { $SKIP_TEST = $true }
        "^--skip-icons$" { $SKIP_ICONS = $true }
        "^--skip-pin$" { $SKIP_PIN = $true }
        default {
            Write-Host "${RED}Unknown option: $arg${RESET}"
            Write-Host "Run '.\scripts\build.ps1' with no arguments for help"
            exit 1
        }
    }
}

###############################################################################
# Work from the repo root, wherever the script was started from
###############################################################################
Push-Location (Split-Path -Parent $PSScriptRoot)

###############################################################################
# Logging (Transcripts natively handle tee-like behavior)
###############################################################################
$LOGFILE = "build.log"
Start-Transcript -Path $LOGFILE -Force | Out-Null

Write-Host "${CYAN}Build mode: $MODE${RESET}"
if ($RUN_CLEAN) {
    Write-Host "${CYAN}Clean: enabled${RESET}"
} else {
    Write-Host "${YELLOW}Clean: disabled${RESET}"
}

###############################################################################
# Timing (overall + per build type)
###############################################################################
$BUILD_STARTED_UTC = [DateTime]::UtcNow
$BUILD_START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$DEBUG_BUILD_TIME = 0
$RELEASE_BUILD_TIME = 0
$AAB_BUILD_TIME = 0

###############################################################################
# Validate environment
###############################################################################
Write-Host "${CYAN}Validating environment...${RESET}"

$tools = @('flutter', 'dart')
if (-not $SKIP_PIN) { $tools += 'git' }
foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction Ignore)) { Stop-Build "$tool not found in PATH." }
}

# flutter doctor is slow, so it only runs when ANDROID_HOME has to be found.
if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    Write-Host "${CYAN}ANDROID_HOME is not set; asking flutter doctor (this may take a moment)...${RESET}"
    # Only the SDK path is wanted here; nothing else doctor reports should stop the build.
    $doctorOutput = & { $PSNativeCommandUseErrorActionPreference = $false; flutter doctor -v }
    $sdkMatch = $doctorOutput | Select-String 'Android SDK at\s*(.+)' | Select-Object -First 1
    if ($sdkMatch) {
        $sdkPath = $sdkMatch.Matches[0].Groups[1].Value.Trim()
        if (Test-Path $sdkPath) { $env:ANDROID_HOME = $sdkPath }
    }
}
if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    Stop-Build "ANDROID_HOME is not set and could not be detected via Flutter."
}
Write-Host "${GREEN}Environment OK (ANDROID_HOME: $env:ANDROID_HOME)${RESET}"

# Version and build number from pubspec.yaml, for the release APK's name.
$pubspecLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if ($pubspecLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    Stop-Build "Could not read 'version: x.y.z+build' from pubspec.yaml (found '$pubspecLine')."
}
$VERSION = $Matches[1]
$BUILD_NUMBER = $Matches[2]
Write-Host "${GREEN}Version: v$VERSION build $BUILD_NUMBER${RESET}"

###############################################################################
# Pin GitHub actions: early, so a bad pin stops the build before a minute of cleaning and fetching
###############################################################################
if (-not $SKIP_PIN) {
    Write-Host "${CYAN}Pinning GitHub actions to their latest release SHAs...${RESET}"
    .\scripts\pin-actions-latest.ps1
    # A script's exit code does not trip $ErrorActionPreference, so check it: 1 means a pin does not match its tag.
    if ($LASTEXITCODE -ne 0) {
        Stop-Build "A GitHub action pin does not match its tag - see above."
    }
} else {
    Write-Host "${YELLOW}Skipping GitHub action pinning (--skip-pin)${RESET}"
}

###############################################################################
# Clean (optional)
###############################################################################
if ($RUN_CLEAN) {
    Write-Host "${CYAN}Wiping old caches...${RESET}"
    flutter clean
} else {
    Write-Host "${YELLOW}Skipping flutter clean${RESET}"
}

###############################################################################
# Pre-warm caches
###############################################################################
Write-Host "${CYAN}Pre-warming Flutter caches...${RESET}"
flutter precache --android

###############################################################################
# Fetch dependencies, then icons
###############################################################################
Write-Host "${CYAN}Fetching dependencies (versions as locked in pubspec.lock)...${RESET}"
#flutter pub upgrade
flutter pub get --enforce-lockfile

if (-not $SKIP_ICONS) {
    Write-Host "${CYAN}Generating launcher icons...${RESET}"
    dart run flutter_launcher_icons
} else {
    Write-Host "${YELLOW}Skipping icon generation...${RESET}"
}

###############################################################################
# Tests
###############################################################################
if (-not $SKIP_TEST) {
    Write-Host "${CYAN}Running analyze and tests...${RESET}"
    # --fatal-infos, as CI runs it: an info-level lint that passes here would fail there.
    flutter analyze --fatal-infos
    flutter test --coverage
} else {
    Write-Host "${YELLOW}Skipping analyze and tests (--skip-test)...${RESET}"
}

###############################################################################
# Build steps (conditional, timed)
###############################################################################
$APK_DEBUG = "build/app/outputs/flutter-apk/app-debug.apk"
$APK_RELEASE = "build/cfg-pia-wg-v${VERSION}_build${BUILD_NUMBER}_release.apk"
$AAB_RELEASE = "build/app/outputs/bundle/release/cfg_pia_wg-release.aab"

if ($MODE -in "debug", "all") {
    Write-Host "${GREEN}Compiling debug version...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build apk --debug
    $DEBUG_BUILD_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $START
}

if ($MODE -in "release", "all") {
    Write-Host "${GREEN}Compiling release version...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build apk --release
    Move-Item -Path "build/app/outputs/flutter-apk/app-release.apk" -Destination $APK_RELEASE -Force
    Write-Host "${GREEN}Renamed release APK to: $APK_RELEASE${RESET}"
    $RELEASE_BUILD_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $START
}

if ($MODE -in "aab", "all") {
    Write-Host "${GREEN}Compiling signed Android App Bundle (.aab) for Google Play...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build appbundle --release
    $AAB_BUILD_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $START
}

###############################################################################
# Third-party notices: regenerated in 'all' mode, once the builds have filled the Gradle cache
###############################################################################
if ($MODE -eq "all") {
    Write-Host "${CYAN}Regenerating THIRD-PARTY-NOTICES.md...${RESET}"
    # Warn, never fail (ID-007): offline, it leaves the file as it is and exits 3.
    & { $PSNativeCommandUseErrorActionPreference = $false; dart run tool/third_party_notices.dart }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "${YELLOW}THIRD-PARTY-NOTICES.md was not regenerated (exit $LASTEXITCODE) - see above.${RESET}"
    }
}

###############################################################################
# Artefact summary: only what this mode builds, and only if this run wrote it
###############################################################################
$expected = @()
if ($MODE -in "debug", "all") { $expected += @{ Label = "Debug APK"; Path = $APK_DEBUG; Seconds = $DEBUG_BUILD_TIME } }
if ($MODE -in "release", "all") { $expected += @{ Label = "Release APK"; Path = $APK_RELEASE; Seconds = $RELEASE_BUILD_TIME } }
if ($MODE -in "aab", "all") { $expected += @{ Label = "Play Store AAB"; Path = $AAB_RELEASE; Seconds = $AAB_BUILD_TIME } }

Write-Host ""
Write-Host "${MAGENTA}-------------------------------------------------------------------------------${RESET}"
Write-Host "${WHITE}Build artefacts:${RESET}"

$problems = 0
foreach ($a in $expected) {
    $label = "{0,-15}" -f "$($a.Label):"
    if (-not (Test-Path $a.Path)) {
        Write-Host "${RED}  $label Missing: $($a.Path)${RESET}"
        $problems++
        continue
    }
    $item = Get-Item $a.Path
    $size = "{0:N0} bytes" -f $item.Length
    if ($item.LastWriteTimeUtc -lt $BUILD_STARTED_UTC) {
        Write-Host "${RED}  $label $($a.Path)  $size  STALE - left over from an earlier build${RESET}"
        $problems++
    } else {
        Write-Host "${WHITE}  $label${RESET} ${GREEN}$($a.Path)${RESET}  ${YELLOW}$size, built in $($a.Seconds) seconds${RESET}"
    }
}

Write-Host "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

if ($problems -gt 0) {
    Stop-Build "$problems artefact(s) missing or stale."
}

###############################################################################
# Total time
###############################################################################
$TOTAL_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $BUILD_START
Write-Host "${GREEN}✔ Total build completed in $TOTAL_TIME seconds${RESET}"
Write-Host ""

Stop-Transcript | Out-Null
Pop-Location
