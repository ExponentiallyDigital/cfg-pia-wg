<#
.SYNOPSIS
Builder script (enhanced version) - PowerShell Port
#>

###############################################################################
# Strict mode + error trap
###############################################################################
$ErrorActionPreference = 'Stop'
trap {
    Write-Host -ForegroundColor Red "✖ Build failed at line $($_.InvocationInfo.ScriptLineNumber)"
    exit 1
}

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
# Help message (shown when no arguments provided)
###############################################################################
if ($args.Count -eq 0) {
    Write-Host "${WHITE}Flutter build script${RESET}"
    Write-Host ""
    Write-Host "${CYAN}Usage:${RESET}"
    Write-Host "  .\build.ps1 [mode] [options]"
    Write-Host ""
    Write-Host "${CYAN}Modes:${RESET}"
    Write-Host "  all         Build everything (default)"
    Write-Host "  debug       Build only the debug APK"
    Write-Host "  release     Build only the release APK"
    Write-Host "  aab         Build only the Play Store AAB"
    Write-Host ""
    Write-Host "${CYAN}Options:${RESET}"
    Write-Host "  --no-clean   Skip running 'flutter clean'"
    Write-Host "  --skip-test  Skip running tests"
    Write-Host "  --skip-icons Skip generating icons (use existing)"
    Write-Host ""
    Write-Host "${CYAN}Examples:${RESET}"
    Write-Host "  .\build.ps1 all"
    Write-Host "  .\build.ps1 release --no-clean"
    Write-Host "  .\build.ps1 debug"
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

foreach ($arg in $args) {
    switch -Regex ($arg) {
        "^(debug|release|aab|all)$" { $MODE = $arg }
        "^--no-clean$" { $RUN_CLEAN = $false }
        "^--clean$" { $RUN_CLEAN = $true }
        "^--skip-test$" { $SKIP_TEST = $true }
        "^--skip-icons$" { $SKIP_ICONS = $true }
        default {
            Write-Host "${RED}Unknown option: $arg${RESET}"
            Write-Host "Run '.\build.ps1' with no arguments for help"
            exit 1
        }
    }
}

Write-Host "${CYAN}Build mode: $MODE${RESET}"
if ($RUN_CLEAN) {
    Write-Host "${CYAN}Clean: enabled${RESET}"
} else {
    Write-Host "${YELLOW}Clean: disabled${RESET}"
}

###############################################################################
# Logging (Transcripts natively handle tee-like behavior)
###############################################################################
$LOGFILE = "build.log"
Start-Transcript -Path $LOGFILE -Force | Out-Null

###############################################################################
# Timing (overall + per build type)
###############################################################################
$BUILD_START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$DEBUG_BUILD_TIME = 0
$RELEASE_BUILD_TIME = 0
$AAB_BUILD_TIME = 0

###############################################################################
# Detect Java & Android SDK (via Flutter)
###############################################################################
Write-Host "${CYAN}Validating environment...${RESET}"

if (-not (Get-Command flutter -ErrorAction Ignore)) { Write-Host "${RED}Flutter not found${RESET}"; exit 1 }
if (-not (Get-Command dart -ErrorAction Ignore)) { Write-Host "${RED}Dart not found${RESET}"; exit 1 }

Write-Host "${CYAN}Analyzing environment via Flutter (this may take a moment)...${RESET}"
# Run doctor once and keep it in memory to extract both paths efficiently
$doctorOutput = flutter doctor -v

# 1. Parse Java Binary
$javaMatch = $doctorOutput | Select-String "Java binary at:"
if ($javaMatch -match 'Java binary at:\s*(.+)') {
    $JAVA_BIN = $matches[1].Trim()
    if (-not $JAVA_BIN.EndsWith(".exe") -and (Test-Path "$JAVA_BIN.exe")) {
        $JAVA_BIN = "$JAVA_BIN.exe"
    }
} else {
    Write-Host "${RED}Java binary not found via flutter doctor.${RESET}"
    exit 1
}
Write-Host "${GREEN}Using Java: $JAVA_BIN${RESET}"

# 2. Check or Parse ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    $sdkMatch = $doctorOutput | Select-String "Android SDK at"
    if ($sdkMatch -match 'Android SDK at\s*(.+)') {
        $FLUTTER_ANDROID_SDK = $matches[1].Trim()
        if (Test-Path $FLUTTER_ANDROID_SDK) {
            $env:ANDROID_HOME = $FLUTTER_ANDROID_SDK
        }
    }
}

# 3. Final verification for ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    Write-Host "${RED}ANDROID_HOME is not set and could not be detected via Flutter.${RESET}"
    exit 1
}

Write-Host "${GREEN}Environment OK (ANDROID_HOME: $env:ANDROID_HOME)${RESET}"

# Extract version from pubspec.yaml and strip build number
$VERSION = ""
if (Test-Path pubspec.yaml) {
    $pubspecVersion = Get-Content pubspec.yaml | Where-Object { $_ -match "^version:" }
    if ($pubspecVersion -match "^version:\s*([^\+\s]+)") {
        $VERSION = $matches[1]
    }
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
Write-Host "${CYAN}Pre-warming Flutter and Gradle caches...${RESET}"
flutter precache --android
try { & gradle --refresh-dependencies 2>$null } catch { } # Native equivalent of || true

###############################################################################
# Fetch dependencies + icons in parallel
###############################################################################
Write-Host "${CYAN}Fetching dependencies and generating icons (parallel)...${RESET}"
flutter pub get --enforce-lockfile

if (-not $SKIP_ICONS) {
    dart run flutter_launcher_icons
} else {
    Write-Host "${YELLOW}Skipping icon generation...${RESET}"
}

###############################################################################
# Tests
###############################################################################
if (-not $SKIP_TEST) {
    Write-Host "${CYAN}Running tests...${RESET}"
    # Removed UNIX 'script' wrapper; standard PS invocation handles CI buffers gracefully
    flutter analyze
    flutter test --coverage
} else {
    Write-Host "${YELLOW}Skipping tests (--skip-test)...${RESET}"
}

###############################################################################
# Build steps (conditional, timed)
###############################################################################
if ($MODE -in "debug", "all") {
    Write-Host "${GREEN}Compiling debug version...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build apk --debug
    $END = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $DEBUG_BUILD_TIME = $END - $START
}

if ($MODE -in "release", "all") {
    Write-Host "${GREEN}Compiling release version...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build apk --release
    $DEFAULT_APK = "build/app/outputs/flutter-apk/app-release.apk"
    $TARGET_APK = "build/cfg_pia_wireguard-v${VERSION}_release.apk"
    if (Test-Path $DEFAULT_APK) {
        Move-Item -Path $DEFAULT_APK -Destination $TARGET_APK -Force
        Write-Host "${GREEN}Renamed release APK to: $TARGET_APK${RESET}"
    }
    $END = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $RELEASE_BUILD_TIME = $END - $START
}

if ($MODE -in "aab", "all") {
    Write-Host "${GREEN}Compiling signed Android App Bundle (.aab) for Google Play...${RESET}"
    $START = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    flutter build appbundle --release
    $END = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $AAB_BUILD_TIME = $END - $START
}

###############################################################################
# Artefact summary (sizes only)
###############################################################################
Write-Host ""
Write-Host "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

$APK_DEBUG = "build/app/outputs/flutter-apk/app-debug.apk"
$APK_RELEASE = "build/cfg_pia_wireguard-v${VERSION}_release.apk"
$AAB_RELEASE = "build/app/outputs/bundle/release/cfg_pia_wireguard-release.aab"

Write-Host "${WHITE}Build artefacts:${RESET}"

foreach ($f in $APK_DEBUG, $APK_RELEASE, $AAB_RELEASE) {
    if (Test-Path $f) {
        $SIZE = (Get-Item $f).Length
        $FORM_SIZE = "{0:N0}" -f $SIZE
        Write-Host "${GREEN}$f${RESET}  ${YELLOW}${FORM_SIZE} bytes${RESET}"
    } else {
        Write-Host "${RED}Missing: $f${RESET}"
    }
}

Write-Host "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

###############################################################################
# Build time summary
###############################################################################
Write-Host "${CYAN}Build time per artefact:${RESET}"
if ($DEBUG_BUILD_TIME -gt 0) {
    Write-Host "${WHITE}  Debug APK:${RESET}   ${YELLOW}${DEBUG_BUILD_TIME} seconds${RESET}"
}
if ($RELEASE_BUILD_TIME -gt 0) {
    Write-Host "${WHITE}  Release APK:${RESET} ${YELLOW}${RELEASE_BUILD_TIME} seconds${RESET}"
}
if ($AAB_BUILD_TIME -gt 0) {
    Write-Host "${WHITE}  Play Store AAB:${RESET} ${YELLOW}${AAB_BUILD_TIME} seconds${RESET}"
}

###############################################################################
# Total time
###############################################################################
$BUILD_END = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$TOTAL_TIME = $BUILD_END - $BUILD_START
Write-Host "${GREEN}✔ Total build completed in $TOTAL_TIME seconds${RESET}"
Write-Host ""

Stop-Transcript | Out-Null