#!/bin/bash
# Builder script (enhanced version)

###############################################################################
# Strict mode + error trap
###############################################################################
set -euo pipefail
trap 'echo -e "\033[31m✖ Build failed at line $LINENO\033[0m"; exit 1' ERR

###############################################################################
# ANSI colors
###############################################################################
CYAN="\033[36m"
GREEN="\033[32m"
WHITE="\033[97m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
RED="\033[31m"
RESET="\033[0m"

###############################################################################
# Help message (shown when no arguments provided)
###############################################################################
if [[ $# -eq 0 ]]; then
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
if $RUN_CLEAN; then
    echo -e "${CYAN}Clean: enabled${RESET}"
else
    echo -e "${YELLOW}Clean: disabled${RESET}"
fi

###############################################################################
# Logging
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
# Detect Java (system or Android Studio JBR)
###############################################################################
echo -e "${CYAN}Validating environment...${RESET}"

command -v flutter >/dev/null 2>&1 || { echo -e "${RED}Flutter not found${RESET}"; exit 1; }
command -v dart >/dev/null 2>&1 || { echo -e "${RED}Dart not found${RESET}"; exit 1; }

if command -v java >/dev/null 2>&1; then
    JAVA_BIN=$(command -v java)
elif [[ -d "/opt/android-studio/jbr" ]]; then
    JAVA_BIN="/opt/android-studio/jbr/bin/java"
elif [[ -d "/snap/android-studio/current/android-studio/jbr" ]]; then
    JAVA_BIN="/snap/android-studio/current/android-studio/jbr/bin/java"
elif ls ~/.local/share/JetBrains/Toolbox/apps/android-studio/jbr/bin/java >/dev/null 2>&1; then
    # Grab the first matching path if multiple versions are installed
    JAVA_BIN=$(ls -1 ~/.local/share/JetBrains/Toolbox/apps/android-studio/jbr/bin/java | head -n 1)
else
    echo -e "${RED}Java not found (system or Android Studio JBR)${RESET}"
    exit 1
fi
echo -e "${GREEN}Using Java: $JAVA_BIN${RESET}"

# 1. Check if the environment variable is already set
if [[ -z "${ANDROID_HOME:-}" ]]; then
    # 2. If not, try to extract the Android SDK path from Flutter's configuration
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER_ANDROID_SDK=$(flutter config --list | grep "android-sdk:" | awk '{print $2}' | tr -d '"')

        if [[ -n "$FLUTTER_ANDROID_SDK" && -d "$FLUTTER_ANDROID_SDK" ]]; then
            export ANDROID_HOME="$FLUTTER_ANDROID_SDK"
        fi
    fi
fi

# 3. Final verification
if [[ -z "${ANDROID_HOME:-}" ]]; then
    echo -e "${RED}ANDROID_HOME is not set and could not be detected via Flutter.${RESET}"
    exit 1
fi

echo -e "${GREEN}Environment OK${RESET}"

###############################################################################
# Clean (optional)
###############################################################################
if $RUN_CLEAN; then
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
gradle --refresh-dependencies >/dev/null 2>&1 || true

###############################################################################
# Fetch dependencies + icons in parallel
###############################################################################
echo -e "${CYAN}Fetching dependencies and generating icons (parallel)...${RESET}"
flutter pub get --enforce-lockfile

if ! $SKIP_ICONS; then
    dart run flutter_launcher_icons
else
    echo -e "${YELLOW}Skipping icon generation...${RESET}"
fi

###############################################################################
# Tests
###############################################################################

if ! $SKIP_TEST; then
    echo -e "${CYAN}Running tests...${RESET}"
    # fix for scrolling output in CI logs
    script -q -c "flutter test --coverage" /dev/null
else
    echo -e "${YELLOW}Skipping tests (--skip-test)...${RESET}"
fi

###############################################################################
# Build steps (conditional, timed)
###############################################################################
if [[ "$MODE" == "debug" || "$MODE" == "all" ]]; then
    echo -e "${GREEN}Compiling debug version...${RESET}"
    START=$(date +%s)
    flutter build apk --debug
    END=$(date +%s)
    DEBUG_BUILD_TIME=$((END - START))
fi

if [[ "$MODE" == "release" || "$MODE" == "all" ]]; then
    echo -e "${GREEN}Compiling release version...${RESET}"
    START=$(date +%s)
    flutter build apk --release
    END=$(date +%s)
    RELEASE_BUILD_TIME=$((END - START))
fi

if [[ "$MODE" == "aab" || "$MODE" == "all" ]]; then
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
APK_RELEASE="build/app/outputs/flutter-apk/app-release.apk"
AAB_RELEASE="build/app/outputs/bundle/release/pia_wireguard_cfga-release.aab"

echo -e "${WHITE}Build artefacts:${RESET}"

for f in "$APK_DEBUG" "$APK_RELEASE" "$AAB_RELEASE"; do
    if [[ -f "$f" ]]; then
        SIZE=$(stat -c %s "$f")
        FORM_SIZE=$(printf "%'d" "$SIZE")
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
if [[ "$DEBUG_BUILD_TIME" -gt 0 ]]; then
    echo -e "${WHITE}  Debug APK:${RESET}   ${YELLOW}${DEBUG_BUILD_TIME} seconds${RESET}"
fi
if [[ "$RELEASE_BUILD_TIME" -gt 0 ]]; then
    echo -e "${WHITE}  Release APK:${RESET} ${YELLOW}${RELEASE_BUILD_TIME} seconds${RESET}"
fi
if [[ "$AAB_BUILD_TIME" -gt 0 ]]; then
    echo -e "${WHITE}  Play Store AAB:${RESET} ${YELLOW}${AAB_BUILD_TIME} seconds${RESET}"
fi

###############################################################################
# Total time
###############################################################################
BUILD_END=$(date +%s)
echo -e "${GREEN}✔ Total build completed in $((BUILD_END - BUILD_START)) seconds${RESET}"
echo ""
