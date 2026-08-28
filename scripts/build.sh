#!/bin/bash
#
# SYNOPSIS: Builder script 
# VERSION: 0.2.1
#

###############################################################################
# Strict mode + error trap
###############################################################################
set -euo pipefail

trap 'echo -e "${RED}✖ Build failed at line ${LINENO}${RESET}" >&2; exit 1' ERR

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
# Help message (shown when no arguments provided)
###############################################################################
if [ "$#" -eq 0 ]; then
    echo -e "${WHITE}Flutter build script${RESET}"
    echo ""
    echo -e "${CYAN}Usage:${RESET}"
    echo "  ./build.sh [mode] [options]"
    echo ""
    echo -e "${CYAN}Modes:${RESET}"
    echo "  all         Build everything (default)"
    echo "  debug       Build only the debug APK"
    echo "  release     Build only the release APK"
    echo "  aab         Build only the Play Store AAB"
    echo ""
    echo -e "${CYAN}Options:${RESET}"
    echo "  --no-clean   Skip running 'flutter clean'"
    echo "  --skip-test  Skip running tests"
    echo "  --skip-icons Skip generating icons (use existing)"
    echo ""
    echo -e "${CYAN}Examples:${RESET}"
    echo "  ./build.sh all"
    echo "  ./build.sh release --no-clean"
    echo "  ./build.sh debug"
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
        *)
            echo -e "${RED}Unknown option: $arg${RESET}"
            echo "Run './build.sh' with no arguments for help"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}Build mode: $MODE${RESET}"
if [ "$RUN_CLEAN" = true ]; then
    echo -e "${CYAN}Clean: enabled${RESET}"
else
    echo -e "${YELLOW}Clean: disabled${RESET}"
fi

###############################################################################
# Logging (bash has no native transcript, so pipe everything through tee)
###############################################################################
LOGFILE="build.log"
exec > >(tee "$LOGFILE") 2>&1

###############################################################################
# Timing (overall + per build type)
###############################################################################
BUILD_START=$(date +%s)
DEBUG_BUILD_TIME=0
RELEASE_BUILD_TIME=0
AAB_BUILD_TIME=0

###############################################################################
# Detect Java & Android SDK (via Flutter)
###############################################################################
echo -e "${CYAN}Validating environment...${RESET}"

if ! command -v flutter >/dev/null 2>&1; then echo -e "${RED}Flutter not found${RESET}"; exit 1; fi
if ! command -v dart >/dev/null 2>&1; then echo -e "${RED}Dart not found${RESET}"; exit 1; fi

echo -e "${CYAN}Analyzing environment via Flutter (this may take a moment)...${RESET}"
# Run doctor once and keep it in memory to extract both paths efficiently
DOCTOR_OUTPUT=$(flutter doctor -v)

# 1. Parse Java Binary
JAVA_LINE=$(echo "$DOCTOR_OUTPUT" | grep "Java binary at:" || true)
if [ -n "$JAVA_LINE" ]; then
    JAVA_BIN=$(echo "$JAVA_LINE" | sed -E 's/.*Java binary at:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
    if [[ "$JAVA_BIN" != *.exe ]] && [ -f "${JAVA_BIN}.exe" ]; then
        JAVA_BIN="${JAVA_BIN}.exe"
    fi
else
    echo -e "${RED}Java binary not found via flutter doctor.${RESET}"
    exit 1
fi
echo -e "${GREEN}Using Java: $JAVA_BIN${RESET}"

# 2. Check or Parse ANDROID_HOME
if [ -z "${ANDROID_HOME:-}" ]; then
    SDK_LINE=$(echo "$DOCTOR_OUTPUT" | grep "Android SDK at" || true)
    if [ -n "$SDK_LINE" ]; then
        FLUTTER_ANDROID_SDK=$(echo "$SDK_LINE" | sed -E 's/.*Android SDK at[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
        if [ -d "$FLUTTER_ANDROID_SDK" ]; then
            export ANDROID_HOME="$FLUTTER_ANDROID_SDK"
        fi
    fi
fi

# 3. Final verification for ANDROID_HOME
if [ -z "${ANDROID_HOME:-}" ]; then
    echo -e "${RED}ANDROID_HOME is not set and could not be detected via Flutter.${RESET}"
    exit 1
fi

echo -e "${GREEN}Environment OK (ANDROID_HOME: $ANDROID_HOME)${RESET}"

# Extract version from pubspec.yaml and strip build number
VERSION=""
if [ -f pubspec.yaml ]; then
    PUBSPEC_VERSION=$(grep -E "^version:" pubspec.yaml || true)
    if [ -n "$PUBSPEC_VERSION" ]; then
        VERSION=$(echo "$PUBSPEC_VERSION" | sed -E 's/^version:[[:space:]]*//' | sed -E 's/\+.*$//' | sed -E 's/[[:space:]]*$//')
    fi
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
echo -e "${CYAN}Pre-warming Flutter and Gradle caches...${RESET}"
flutter precache --android
gradle --refresh-dependencies >/dev/null 2>&1 || true  # native equivalent of || true

###############################################################################
# Fetch dependencies + icons in parallel
###############################################################################
echo -e "${CYAN}Upgrading minor versions, fetching dependencies, and generating icons (parallel)...${RESET}"
#flutter pub upgrade
flutter pub get --enforce-lockfile

if [ "$SKIP_ICONS" = false ]; then
    dart run flutter_launcher_icons
else
    echo -e "${YELLOW}Skipping icon generation...${RESET}"
fi

###############################################################################
# Update GitHub action scripts to latest versions
###############################################################################
echo -e "${CYAN}Updating GitHub action SHAs to latest versions...${RESET}"
./scripts/pin-actions-latest.sh

###############################################################################
# Tests
###############################################################################
if [ "$SKIP_TEST" = false ]; then
    echo -e "${CYAN}Running tests...${RESET}"
    flutter analyze
    flutter test --coverage
else
    echo -e "${YELLOW}Skipping tests (--skip-test)...${RESET}"
fi

###############################################################################
# Build steps (conditional, timed)
###############################################################################
if [ "$MODE" = "debug" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling debug version...${RESET}"
    START=$(date +%s)
    flutter build apk --debug
    END=$(date +%s)
    DEBUG_BUILD_TIME=$((END - START))
fi

if [ "$MODE" = "release" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling release version...${RESET}"
    START=$(date +%s)
    flutter build apk --release
    DEFAULT_APK="build/app/outputs/flutter-apk/app-release.apk"
    TARGET_APK="build/cfg_pia_wg-v${VERSION}_release.apk"
    if [ -f "$DEFAULT_APK" ]; then
        mv -f "$DEFAULT_APK" "$TARGET_APK"
        echo -e "${GREEN}Renamed release APK to: $TARGET_APK${RESET}"
    fi
    END=$(date +%s)
    RELEASE_BUILD_TIME=$((END - START))
fi

if [ "$MODE" = "aab" ] || [ "$MODE" = "all" ]; then
    echo -e "${GREEN}Compiling signed Android App Bundle (.aab) for Google Play...${RESET}"
    START=$(date +%s)
    flutter build appbundle --release
    END=$(date +%s)
    AAB_BUILD_TIME=$((END - START))
fi

###############################################################################
# Artefact summary (sizes only)
###############################################################################
echo ""
echo -e "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

APK_DEBUG="build/app/outputs/flutter-apk/app-debug.apk"
APK_RELEASE="build/cfg_pia_wg-v${VERSION}_release.apk"
AAB_RELEASE="build/app/outputs/bundle/release/cfg_pia_wg-release.aab"

echo -e "${WHITE}Build artefacts:${RESET}"

# stat flags differ between GNU (Linux) and BSD (macOS), so try both
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null
}

for f in "$APK_DEBUG" "$APK_RELEASE" "$AAB_RELEASE"; do
    if [ -f "$f" ]; then
        SIZE=$(get_file_size "$f")
        # insert thousands separators for readability
        FORM_SIZE=$(printf "%d" "$SIZE" | sed -E ':a;s/\B[0-9]{3}\>/,&/;ta')
        echo -e "${GREEN}$f${RESET}  ${YELLOW}${FORM_SIZE} bytes${RESET}"
    else
        echo -e "${RED}Missing: $f${RESET}"
    fi
done

echo -e "${MAGENTA}-------------------------------------------------------------------------------${RESET}"

###############################################################################
# Build time summary
###############################################################################
echo -e "${CYAN}Build time per artefact:${RESET}"
if [ "$DEBUG_BUILD_TIME" -gt 0 ]; then
    echo -e "${WHITE}  Debug APK:${RESET}   ${YELLOW}${DEBUG_BUILD_TIME} seconds${RESET}"
fi
if [ "$RELEASE_BUILD_TIME" -gt 0 ]; then
    echo -e "${WHITE}  Release APK:${RESET} ${YELLOW}${RELEASE_BUILD_TIME} seconds${RESET}"
fi
if [ "$AAB_BUILD_TIME" -gt 0 ]; then
    echo -e "${WHITE}  Play Store AAB:${RESET} ${YELLOW}${AAB_BUILD_TIME} seconds${RESET}"
fi

###############################################################################
# Total time
###############################################################################
BUILD_END=$(date +%s)
TOTAL_TIME=$((BUILD_END - BUILD_START))
echo -e "${GREEN}✔ Total build completed in $TOTAL_TIME seconds${RESET}"
echo ""

# transcript is closed automatically once the tee'd process substitution exits
