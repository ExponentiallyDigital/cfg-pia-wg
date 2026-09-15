#!/bin/bash
#
# SYNOPSIS: Builder script
# VERSION: 0.3.0
#

###############################################################################
# Strict mode
###############################################################################
# -E: the ERR trap also fires inside functions and subshells, not just at the top level.
set -Eeuo pipefail

###############################################################################
# ANSI colors (using the escape character directly for portability)
###############################################################################
ESC=$'\033'
CYAN="${ESC}[36m"
GREEN="${ESC}[32m"
WHITE="${ESC}[97m"
YELLOW="${ESC}[33m"
MAGENTA="${ESC}[35m"
RED="${ESC}[31m"
RESET="${ESC}[0m"

###############################################################################
# Error trap: say what failed, not just where
###############################################################################
trap 'echo -e "${RED}✖ Build failed at line ${LINENO}: ${BASH_COMMAND}${RESET}" >&2; exit 1' ERR

fail() {
    echo -e "${RED}✖ $1 Build stopped.${RESET}" >&2
    exit 1
}

###############################################################################
# Help message (shown when no arguments provided)
###############################################################################
if [ "$#" -eq 0 ]; then
    echo -e "${WHITE}Flutter build script${RESET}"
    echo ""
    echo -e "${CYAN}Usage:${RESET}"
    echo "  ./scripts/build.sh [mode] [options]"
    echo ""
    echo -e "${CYAN}Modes:${RESET}"
    echo "  all         Build everything"
    echo "  debug       Build only the debug APK"
    echo "  release     Build only the release APK"
    echo "  aab         Build only the Play Store AAB"
    echo ""
    echo -e "${CYAN}Options:${RESET}"
    echo "  --no-clean   Skip running 'flutter clean'"
    echo "  --skip-test  Skip running analyze and tests"
    echo "  --skip-icons Skip generating icons (use existing)"
    echo "  --skip-pin   Skip pinning and checking the GitHub action SHAs"
    echo ""
    echo -e "${CYAN}Examples:${RESET}"
    echo "  ./scripts/build.sh all"
    echo "  ./scripts/build.sh release --no-clean"
    echo "  ./scripts/build.sh debug"
    echo ""
    exit 0
fi

###############################################################################
# Parse command-line arguments
###############################################################################
MODE="all"
RUN_CLEAN=true
SKIP_TEST=false
SKIP_ICONS=false
SKIP_PIN=false

for arg in "$@"; do
    case "$arg" in
        debug|release|aab|all)
            MODE="$arg"
            ;;
        --no-clean)
            RUN_CLEAN=false
            ;;
        --clean)
            RUN_CLEAN=true
            ;;
        --skip-test)
            SKIP_TEST=true
            ;;
        --skip-icons)
            SKIP_ICONS=true
            ;;
        --skip-pin)
            SKIP_PIN=true
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${RESET}"
            echo "Run './scripts/build.sh' with no arguments for help"
            exit 1
            ;;
    esac
done

###############################################################################
# Work from the repo root, wherever the script was started from
###############################################################################
cd "$(dirname "${BASH_SOURCE[0]}")/.."

###############################################################################
# Logging (bash has no native transcript, so pipe everything through tee)
###############################################################################
LOGFILE="build.log"
exec > >(tee "$LOGFILE") 2>&1

echo -e "${CYAN}Build mode: $MODE${RESET}"
if [ "$RUN_CLEAN" = true ]; then
    echo -e "${CYAN}Clean: enabled${RESET}"
else
    echo -e "${YELLOW}Clean: disabled${RESET}"
fi

###############################################################################
# Timing (overall + per build type)
###############################################################################
BUILD_START=$(date +%s)
# Artefacts older than this file were left over from an earlier build.
BUILD_STAMP=$(mktemp)
trap 'rm -f "$BUILD_STAMP"' EXIT
DEBUG_BUILD_TIME=0
RELEASE_BUILD_TIME=0
AAB_BUILD_TIME=0

###############################################################################
# Validate environment
###############################################################################
echo -e "${CYAN}Validating environment...${RESET}"

TOOLS=(flutter dart)
if [ "$SKIP_PIN" = false ]; then
    TOOLS+=(git curl jq)
fi
for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "$tool not found in PATH."
    fi
done

# flutter doctor is slow, so it only runs when ANDROID_HOME has to be found.
if [ -z "${ANDROID_HOME:-}" ]; then
    echo -e "${CYAN}ANDROID_HOME is not set; asking flutter doctor (this may take a moment)...${RESET}"
    # Only the SDK path is wanted here; nothing else doctor reports should stop the build.
    DOCTOR_OUTPUT=$(flutter doctor -v || true)
    FLUTTER_ANDROID_SDK=$(echo "$DOCTOR_OUTPUT" | sed -nE 's/.*Android SDK at[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p' | head -n 1)
    if [ -n "$FLUTTER_ANDROID_SDK" ] && [ -d "$FLUTTER_ANDROID_SDK" ]; then
        export ANDROID_HOME="$FLUTTER_ANDROID_SDK"
    fi
fi
if [ -z "${ANDROID_HOME:-}" ]; then
    fail "ANDROID_HOME is not set and could not be detected via Flutter."
fi
echo -e "${GREEN}Environment OK (ANDROID_HOME: $ANDROID_HOME)${RESET}"

# Version and build number from pubspec.yaml, for the release APK's name.
PUBSPEC_VERSION=$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[[:space:]]*$/\1 \2/p' pubspec.yaml | head -n 1)
if [ -z "$PUBSPEC_VERSION" ]; then
    fail "Could not read 'version: x.y.z+build' from pubspec.yaml."
fi
read -r VERSION BUILD_NUMBER <<< "$PUBSPEC_VERSION"
echo -e "${GREEN}Version: v$VERSION build $BUILD_NUMBER${RESET}"

###############################################################################
# Pin GitHub actions: early, so a bad pin stops the build before a minute of cleaning and fetching
###############################################################################
if [ "$SKIP_PIN" = false ]; then
    echo -e "${CYAN}Pinning GitHub actions to their latest release SHAs...${RESET}"
    # Through bash: the script is not marked executable in git. Exit 1 means a pin does not match its tag.
    if ! bash ./scripts/pin-actions-latest.sh; then
        fail "A GitHub action pin does not match its tag - see above."
    fi
else
    echo -e "${YELLOW}Skipping GitHub action pinning (--skip-pin)${RESET}"
fi

###############################################################################
# Clean (optional)
###############################################################################
if [ "$RUN_CLEAN" = true ]; then
    echo -e "${CYAN}Wiping old caches...${RESET}"
    flutter clean
else
    echo -e "${YELLOW}Skipping flutter clean${RESET}"
fi

###############################################################################
# Pre-warm caches
###############################################################################
echo -e "${CYAN}Pre-warming Flutter caches...${RESET}"
flutter precache --android

###############################################################################
# Fetch dependencies, then icons
###############################################################################
echo -e "${CYAN}Fetching dependencies (versions as locked in pubspec.lock)...${RESET}"
#flutter pub upgrade
flutter pub get --enforce-lockfile

if [ "$SKIP_ICONS" = false ]; then
    echo -e "${CYAN}Generating launcher icons...${RESET}"
    dart run flutter_launcher_icons
else
    echo -e "${YELLOW}Skipping icon generation...${RESET}"
fi

###############################################################################
# Tests
###############################################################################
if [ "$SKIP_TEST" = false ]; then
    echo -e "${CYAN}Running analyze and tests...${RESET}"
    # --fatal-infos, as CI runs it: an info-level lint that passes here would fail there.
    flutter analyze --fatal-infos
    flutter test --coverage
else
    echo -e "${YELLOW}Skipping analyze and tests (--skip-test)...${RESET}"
fi

###############################################################################
# Build steps (conditional, timed)
###############################################################################
APK_DEBUG="build/app/outputs/flutter-apk/app-debug.apk"
APK_RELEASE="build/cfg-pia-wg-v${VERSION}_build${BUILD_NUMBER}_release.apk"
AAB_RELEASE="build/app/outputs/bundle/release/cfg_pia_wg-release.aab"

if [ "$MODE" = "debug" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling debug version...${RESET}"
    START=$(date +%s)
    flutter build apk --debug
    DEBUG_BUILD_TIME=$(( $(date +%s) - START ))
fi

if [ "$MODE" = "release" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling release version...${RESET}"
    START=$(date +%s)
    flutter build apk --release
    mv -f "build/app/outputs/flutter-apk/app-release.apk" "$APK_RELEASE"
    echo -e "${GREEN}Renamed release APK to: $APK_RELEASE${RESET}"
    RELEASE_BUILD_TIME=$(( $(date +%s) - START ))
fi

if [ "$MODE" = "aab" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling signed Android App Bundle (.aab) for Google Play...${RESET}"
    START=$(date +%s)
    flutter build appbundle --release
    AAB_BUILD_TIME=$(( $(date +%s) - START ))
fi

###############################################################################
# Third-party notices: regenerated in 'all' mode, once the builds have filled the Gradle cache
###############################################################################
if [ "$MODE" = "all" ]; then
    echo -e "${CYAN}Regenerating THIRD-PARTY-NOTICES.md...${RESET}"
    # Warn, never fail (ID-007): offline, it leaves the file as it is and exits 3.
    if ! dart run tool/third_party_notices.dart; then
        echo -e "${YELLOW}THIRD-PARTY-NOTICES.md was not regenerated - see above.${RESET}"
    fi
fi

###############################################################################
# Artefact summary: only what this mode builds, and only if this run wrote it
###############################################################################
# stat flags differ between GNU (Linux) and BSD (macOS), so try both
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null
}

# Thousands separators in plain bash; the sed version relied on GNU-only \B and \>.
with_commas() {
    local n="$1" out=""
    while (( ${#n} > 3 )); do
        out=",${n: -3}$out"
        n="${n:0:${#n}-3}"
    done
    echo "$n$out"
}

EXPECTED=()
if [ "$MODE" = "debug" ] || [ "$MODE" = "all" ]; then EXPECTED+=("Debug APK|$APK_DEBUG|$DEBUG_BUILD_TIME"); fi
if [ "$MODE" = "release" ] || [ "$MODE" = "all" ]; then EXPECTED+=("Release APK|$APK_RELEASE|$RELEASE_BUILD_TIME"); fi
if [ "$MODE" = "aab" ] || [ "$MODE" = "all" ]; then EXPECTED+=("Play Store AAB|$AAB_RELEASE|$AAB_BUILD_TIME"); fi

echo ""
echo -e "${MAGENTA}-------------------------------------------------------------------------------${RESET}"
echo -e "${WHITE}Build artefacts:${RESET}"

PROBLEMS=0
for entry in "${EXPECTED[@]}"; do
    IFS='|' read -r label path seconds <<< "$entry"
    label=$(printf "%-15s" "$label:")
    if [ ! -f "$path" ]; then
        echo -e "${RED}  $label Missing: $path${RESET}"
        PROBLEMS=$((PROBLEMS + 1))
        continue
    fi
    size="$(with_commas "$(get_file_size "$path")") bytes"
    if [ "$path" -nt "$BUILD_STAMP" ]; then
        echo -e "${WHITE}  $label${RESET} ${GREEN}$path${RESET}  ${YELLOW}$size, built in $seconds seconds${RESET}"
    else
        echo -e "${RED}  $label $path  $size  STALE - left over from an earlier build${RESET}"
        PROBLEMS=$((PROBLEMS + 1))
    fi
done

echo -e "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

if (( PROBLEMS > 0 )); then
    fail "$PROBLEMS artefact(s) missing or stale."
fi

###############################################################################
# Total time
###############################################################################
TOTAL_TIME=$(( $(date +%s) - BUILD_START ))
echo -e "${GREEN}✔ Total build completed in $TOTAL_TIME seconds${RESET}"
echo ""

# transcript is closed automatically once the tee'd process substitution exits
