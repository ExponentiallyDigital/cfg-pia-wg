#!/bin/sh
# scripts/coverage-html.sh - line and branch coverage as an HTML report (ID-718).
#
# Usage:  scripts/coverage-html.sh [--no-test] [LCOV_FILE]
#
#   --no-test   do not run `flutter test` first; read LCOV_FILE as it is
#   LCOV_FILE   default coverage/lcov.info, from `flutter test --coverage --branch-coverage`
#
# Writes coverage/html/index.html and prints the line and branch totals. Needs genhtml from lcov 2.0 or
# newer (`sudo apt-get install lcov`); run it where genhtml is, which on Windows is WSL.
#
# Two things in Flutter's output stop genhtml, and this script deals with both:
#   - On Windows the source paths (SF: lines) have backslashes, which Linux cannot open, so they are
#     changed to slashes in a copy, coverage/lcov.fixed.info.
#   - With --branch-coverage Dart records some branches on lines that have no line record (an `if` just
#     after an `await`, for one), which genhtml refuses as inconsistent. They are ignored, and those
#     lines show no line data in the report; the branches still count.
set -eu
cd "$(dirname "$0")/.."

run_tests=1
input=coverage/lcov.info
for arg in "$@"; do
  case "$arg" in
    --no-test) run_tests=0 ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) input="$arg" ;;
  esac
done

if [ "$run_tests" = 1 ]; then
  flutter test --coverage --branch-coverage
fi
if [ ! -f "$input" ]; then
  echo "$input not found: run flutter test --coverage --branch-coverage first." >&2
  exit 1
fi
if ! command -v genhtml > /dev/null 2>&1; then
  echo "genhtml is not installed: sudo apt-get install lcov (version 2.0 or newer)." >&2
  exit 1
fi

fixed=coverage/lcov.fixed.info
sed '/^SF:/ s#\\#/#g' "$input" > "$fixed"
if ! out=$(genhtml --branch-coverage --ignore-errors inconsistent,corrupt "$fixed" -o coverage/html 2>&1); then
  printf '%s\n' "$out" >&2
  exit 1
fi
summary=$(printf '%s\n' "$out" | grep -E '^ +(lines|branches)\.' || true)
printf '%s\n' "$summary"
echo "Report: coverage/html/index.html"

# In a GitHub Actions run, the totals go on the run's summary page.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo '### Coverage'
    echo '```'
    printf '%s\n' "$summary"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
