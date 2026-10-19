#!/bin/sh
# ios/stamp_build_info.sh - writes the build facts ABOUT shows into the built app's Info.plist (ID-395).
#
# Run by the Runner target's "Stamp build info" phase, the last one, so it writes the Info.plist Xcode
# has already processed, before the app is signed. It is the iOS side of what android/app/build.gradle.kts
# bakes into BuildConfig, worked out the same way, so both ABOUT screens and both bug reports say the
# same things: the commit at --abbrev=7, the branch from GITHUB_REF_NAME in CI (a tag build's checkout
# is a detached HEAD, which git can only call "HEAD"), the run id or "Local Build", the time in UTC.
#
# AppDelegate.swift reads the keys; test/unit/ios_build_info_test.dart holds the two lists together.
# A fact it can't find is left for the app to show as "unknown". It never fails the build.

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$plist" ]; then
  echo "stamp_build_info: no Info.plist at $plist, nothing stamped"
  exit 0
fi
cd "${SRCROOT}/.." || exit 0

stamp() {
  [ -n "$2" ] || return 0
  plutil -replace "$1" -string "$2" "$plist" || echo "stamp_build_info: could not write $1"
}

fields=$(git log -1 --abbrev=7 --format='%h %cI' 2>/dev/null)
commit=${fields%% *}
commit_date=${fields#* }
[ "$commit_date" = "$fields" ] && commit_date=""

branch=${GITHUB_REF_NAME:-}
if [ -z "$branch" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$branch" = "HEAD" ] && branch=""
fi

stamp CfgGitCommit "$commit"
stamp CfgGitCommitDate "$commit_date"
stamp CfgGitBranch "$branch"
stamp CfgRunnerId "${GITHUB_RUN_ID:-Local Build}"
stamp CfgBuildTimestamp "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
stamp CfgBuildType "$(printf '%s' "${CONFIGURATION:-}" | tr '[:upper:]' '[:lower:]')"
echo "stamp_build_info: commit ${commit:-unknown}, branch ${branch:-unknown}, ${CONFIGURATION:-unknown}"
exit 0
