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
    Write-Host "  all         Build everything (on a Mac, the .ipa too)"
    Write-Host "  debug       Build only the debug APK"
    Write-Host "  release     Build only the release APK"
    Write-Host "  aab         Build only the Play Store AAB"
    Write-Host "  ipa         Build only the iOS .ipa (Mac only)"
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
    Write-Host "  ./scripts/build.ps1 ipa --skip-test   (on a Mac)"
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
        "^(debug|release|aab|ipa|all)$" { $MODE = $arg }
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
$IPA_BUILD_TIME = 0

###############################################################################
# Validate environment
###############################################################################
Write-Host "${CYAN}Validating environment...${RESET}"

# ID-475: the .ipa needs Xcode, so only a Mac builds it, alone or as part of all.
if ($MODE -eq "ipa" -and -not $IsMacOS) { Stop-Build "An .ipa needs Xcode, so only a Mac can build one." }
$BUILD_IPA = $MODE -eq "ipa" -or ($MODE -eq "all" -and $IsMacOS)
$BUILD_ANDROID = $MODE -ne "ipa"

$tools = @('flutter', 'dart')
if (-not $SKIP_PIN) { $tools += 'git' }
if ($BUILD_IPA) { $tools += 'xcodebuild' }
foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction Ignore)) { Stop-Build "$tool not found in PATH." }
}

# flutter doctor is slow, so it only runs when ANDROID_HOME has to be found.
if ($BUILD_ANDROID -and [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    Write-Host "${CYAN}ANDROID_HOME is not set; asking flutter doctor (this may take a moment)...${RESET}"
    # Only the SDK path is wanted here; nothing else doctor reports should stop the build.
    $doctorOutput = & { $PSNativeCommandUseErrorActionPreference = $false; flutter doctor -v }
    $sdkMatch = $doctorOutput | Select-String 'Android SDK at\s*(.+)' | Select-Object -First 1
    if ($sdkMatch) {
        $sdkPath = $sdkMatch.Matches[0].Groups[1].Value.Trim()
        if (Test-Path $sdkPath) { $env:ANDROID_HOME = $sdkPath }
    }
}
if ($BUILD_ANDROID -and [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    Stop-Build "ANDROID_HOME is not set and could not be detected via Flutter."
}

# Release signing, checked now rather than when Gradle signs: without it the release build fails
# after the tests and the debug build ("SigningConfig "release" is missing required property
# "storeFile""). Gradle resolves storeFile from android/app, so ../release.jks is android/release.jks.
if ($MODE -in "release", "aab", "all") {
    $keyProps = "android/key.properties"
    if (-not (Test-Path $keyProps)) {
        Stop-Build "$keyProps is missing, so a release can't be signed (see android/app/build.gradle.kts)."
    }
    $storeLine = Get-Content $keyProps | Where-Object { $_ -match '^\s*storeFile\s*=' } | Select-Object -First 1
    $storeFile = if ($storeLine) { ($storeLine -split '=', 2)[1].Trim() } else { '' }
    if ($storeFile -eq '') { Stop-Build "$keyProps has no storeFile." }
    $storePath = if ([IO.Path]::IsPathRooted($storeFile)) { $storeFile } else { Join-Path "android/app" $storeFile }
    if (-not (Test-Path $storePath)) {
        Stop-Build "The keystore $keyProps names, $storeFile, is not there (looked for $storePath)."
    }
    Write-Host "${GREEN}Release signing: $storePath${RESET}"
}
# The App Store key, as release.yml passes it. Without it the app can't ask who has paid, so every
# feature is unlocked: fine for trying a build on a phone, never for one that goes to Apple.
if ($BUILD_IPA -and [string]::IsNullOrWhiteSpace($env:REVENUECAT_IOS_KEY)) {
    Write-Host "${YELLOW}⚠ REVENUECAT_IOS_KEY is not set, so this .ipa has every feature unlocked. For testing only; App Store builds come from release.yml.${RESET}"
}
if ($BUILD_ANDROID) {
    Write-Host "${GREEN}Environment OK (ANDROID_HOME: $env:ANDROID_HOME)${RESET}"
} else {
    Write-Host "${GREEN}Environment OK${RESET}"
}

# ID-473: on macOS and Linux, Gradle's launcher (android/gradlew, which Flutter generates and git
# ignores, so it can't carry this) loads a native library, and Java 25 warns about it on every build:
# "A restricted method in java.lang.System has been called". Windows builds don't print it (ID-408).
if (-not $IsWindows) {
    $env:GRADLE_OPTS = "--enable-native-access=ALL-UNNAMED $env:GRADLE_OPTS".Trim()
}

# Version and build number from pubspec.yaml, for the release APK's name.
$pubspecLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if ($pubspecLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    Stop-Build "Could not read 'version: x.y.z+build' from pubspec.yaml (found '$pubspecLine')."
}
$VERSION = $Matches[1]
$BUILD_NUMBER = $Matches[2]
Write-Host "${GREEN}Version: v$VERSION build $BUILD_NUMBER${RESET}"

# ID-410: CI builds with the Flutter pinned in pubspec.yaml. Another one here is a warning, not a stop:
# a new Flutter is tried locally first, then the pin moves.
$pinLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^\s+flutter:\s*(\d+\.\d+\.\d+)\s*$' } | Select-Object -First 1
$FLUTTER_PIN = if ($pinLine -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { '' }
$FLUTTER_LOCAL = (flutter --version --machine | ConvertFrom-Json).frameworkVersion
if ($FLUTTER_PIN -eq '') {
    Write-Host "${YELLOW}⚠ No exact Flutter version pinned in pubspec.yaml's environment; CI can't match this build.${RESET}"
} elseif ($FLUTTER_LOCAL -ne $FLUTTER_PIN) {
    Write-Host "${YELLOW}⚠ Flutter here is $FLUTTER_LOCAL, but pubspec.yaml pins $FLUTTER_PIN, which CI builds with.${RESET}"
} else {
    Write-Host "${GREEN}Flutter: $FLUTTER_LOCAL, as pinned${RESET}"
}

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
if ($BUILD_ANDROID) { flutter precache --android }
if ($BUILD_IPA) { flutter precache --ios }

###############################################################################
# Fetch dependencies, then icons
###############################################################################
Write-Host "${CYAN}Fetching dependencies (versions as locked in pubspec.lock)...${RESET}"
#flutter pub upgrade
flutter pub get --enforce-lockfile

if (-not $SKIP_ICONS) {
    Write-Host "${CYAN}Generating launcher icons...${RESET}"
    # Through the wrapper, not the tool: the tool damages the Xcode project file (ID-374).
    dart run tool/launcher_icons.dart
    # The splash screen is generated from the same artwork and written into the platform folders,
    # so it belongs with the icons rather than with the build (ID-111).
    Write-Host "${CYAN}Generating the native splash screen...${RESET}"
    dart run flutter_native_splash:create
} else {
    Write-Host "${YELLOW}Skipping icon and splash generation...${RESET}"
}

###############################################################################
# Tests
###############################################################################
if (-not $SKIP_TEST) {
    Write-Host "${CYAN}Running analyze and tests...${RESET}"
    # --fatal-infos, as CI runs it: an info-level lint that passes here would fail there.
    flutter analyze --fatal-infos
    if (-not $IsMacOS) {
        flutter test --coverage
    } else {
        # On macOS a transcript splits flutter's output into lines, and a bare `r ends one, so each
        # redraw of the one-line progress became a line of its own: 2000 of them scrolling past. So
        # the transcript pauses, script(1) gives flutter the terminal itself and keeps a copy, and
        # the copy goes into the log with each line as it was last drawn.
        $testCopy = [IO.Path]::GetTempFileName()
        Stop-Transcript | Out-Null
        & { $PSNativeCommandUseErrorActionPreference = $false; bash -c "script -q '$testCopy' flutter test --coverage > /dev/tty" }
        $testExit = $LASTEXITCODE
        $raw = [IO.File]::ReadAllText($testCopy) -replace "`e\][^`a]*`a", '' -replace "`e\[[0-9;?]*[A-Za-z]", '' -replace "`e[=>]", ''
        $lines = $raw -split "`n" | ForEach-Object { "$(@($_ -split "`r" | Where-Object { $_ -ne '' })[-1])".TrimEnd() }
        Add-Content -Path $LOGFILE -Value $lines
        Remove-Item $testCopy -ErrorAction SilentlyContinue
        Start-Transcript -Path $LOGFILE -Append | Out-Null
        if ($testExit -ne 0) { Stop-Build "flutter test failed (exit $testExit) - see above, or $LOGFILE." }
    }
} else {
    Write-Host "${YELLOW}Skipping analyze and tests (--skip-test)...${RESET}"
}

###############################################################################
# Build steps (conditional, timed)
###############################################################################
$APK_DEBUG = "build/app/outputs/flutter-apk/app-debug.apk"
$APK_RELEASE = "build/cfg-pia-wg-v${VERSION}_build${BUILD_NUMBER}_release.apk"
$AAB_RELEASE = "build/app/outputs/bundle/release/cfg_pia_wg-release.aab"
$IPA_RELEASE = "build/cfg-pia-wg-v${VERSION}_build${BUILD_NUMBER}.ipa"

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

if ($BUILD_IPA) {
    # Signed for App Store Connect by team RL4UB6WKMV, with ios/ExportOptions.plist, as release.yml
    # exports it; locally Xcode signs with the Apple account in Xcode's Settings, Accounts.
    Write-Host "${GREEN}Compiling the iOS app (.ipa)...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ipaArgs = @('build', 'ipa', '--release', '--export-options-plist', 'ios/ExportOptions.plist')
    if (-not [string]::IsNullOrWhiteSpace($env:REVENUECAT_IOS_KEY)) { $ipaArgs += "--dart-define=REVENUECAT_IOS_KEY=$env:REVENUECAT_IOS_KEY" }
    flutter @ipaArgs
    $ipaBuilt = Get-ChildItem "build/ios/ipa/*.ipa" -ErrorAction Ignore | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if (-not $ipaBuilt) { Stop-Build "flutter build ipa left no .ipa in build/ios/ipa." }
    Move-Item -Path $ipaBuilt.FullName -Destination $IPA_RELEASE -Force
    Write-Host "${GREEN}Renamed the .ipa to: $IPA_RELEASE${RESET}"
    $IPA_BUILD_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $START
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
if ($BUILD_IPA) { $expected += @{ Label = "iOS IPA"; Path = $IPA_RELEASE; Seconds = $IPA_BUILD_TIME } }

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
