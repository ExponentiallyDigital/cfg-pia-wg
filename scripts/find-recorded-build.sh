#!/bin/sh
# find-recorded-build.sh - finds and writes what an earlier release run recorded for a source tree (ID-685).
#
# A release run on dev records two things against the source tree it ran on, as artifacts named with the
# tree's hash (`git rev-parse HEAD^{tree}`): that the quality and security checks passed ("verified-TREE"),
# and the signed iOS build with its SBOM ("cfg-pia-wg-ios-signed-TREE"). A merge of dev into main has the same
# tree as dev's last commit, so the tag run on it finds both and neither runs the checks again nor compiles
# iOS again. Nothing is taken that cannot be trusted: the artifact must come from a run of release.yml that
# succeeded on dev, on main or on a tag, which only someone who can push there can make.
#
# Usage:
#   find-recorded-build.sh verified                 print verified=true|false to $GITHUB_OUTPUT (tag runs only)
#   find-recorded-build.sh record-verified DIR      write DIR/verified.txt and RECORD_NAME to $GITHUB_ENV
#   find-recorded-build.sh signed-ios DIR           download a recorded signed iOS build into DIR, and print
#                                                   found=true|false and tree=TREE to $GITHUB_OUTPUT (tag runs only)
#   find-recorded-build.sh tree                     print the tree hash
# Needs git, and gh with GITHUB_REPOSITORY and GH_TOKEN (the token's actions: read) for the finding modes. IS_TAG
# is "true" for a tag run: any other run finds nothing, so a dry run or manual run always checks and builds.
# Exit 0 always for a finding mode (not found is an answer, not an error); 2 for a bad call.

MODE="$1"
DIR="$2"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

tree() { git rev-parse 'HEAD^{tree}'; }

# The id of the newest successful, unexpired, trusted release.yml run that kept artifact $1, or nothing.
trusted_run() {
  gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=$1&per_page=20" \
    --jq '.artifacts[] | select(.expired == false) | "\(.workflow_run.id) \(.workflow_run.head_branch)"' 2> /dev/null |
    while read -r RUN BRANCH; do
      [ -n "$RUN" ] || continue
      case "$BRANCH" in
        dev | main | v*) ;;
        *) continue ;;
      esac
      WHAT="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN" --jq '"\(.path) \(.conclusion)"' 2> /dev/null)"
      if [ "$WHAT" = ".github/workflows/release.yml success" ]; then
        echo "$RUN"
        break
      fi
    done
}

case "$MODE" in
  tree)
    tree
    ;;
  record-verified)
    [ -n "$DIR" ] || { echo "usage: find-recorded-build.sh record-verified DIR" >&2; exit 2; }
    T="$(tree)"
    mkdir -p "$DIR"
    printf 'The quality and security checks passed for tree %s in run %s of %s.\n' "$T" "${GITHUB_RUN_ID:-unknown}" "${GITHUB_REPOSITORY:-unknown}" > "$DIR/verified.txt"
    echo "RECORD_NAME=verified-$T" >> "${GITHUB_ENV:-/dev/stdout}"
    ;;
  verified)
    T="$(tree)"
    if [ "$IS_TAG" != "true" ]; then
      echo "Not a tag run: the checks run."
      echo "verified=false" >> "$OUT"
      exit 0
    fi
    RUN="$(trusted_run "verified-$T")"
    if [ -n "$RUN" ]; then
      echo "The checks passed for tree $T in run $RUN, so they are not run again."
      echo "verified=true" >> "$OUT"
    else
      echo "No recorded pass for tree $T: the checks run."
      echo "verified=false" >> "$OUT"
    fi
    ;;
  signed-ios)
    [ -n "$DIR" ] || { echo "usage: find-recorded-build.sh signed-ios DIR" >&2; exit 2; }
    T="$(tree)"
    echo "tree=$T" >> "$OUT"
    if [ "$IS_TAG" != "true" ]; then
      echo "Not a tag run: iOS is built."
      echo "found=false" >> "$OUT"
      exit 0
    fi
    RUN="$(trusted_run "cfg-pia-wg-ios-signed-$T")"
    if [ -n "$RUN" ] && gh run download "$RUN" --repo "$GITHUB_REPOSITORY" --name "cfg-pia-wg-ios-signed-$T" --dir "$DIR" > /dev/null 2>&1 &&
      [ -f "$DIR/validated.txt" ] && ls "$DIR"/*.ipa > /dev/null 2>&1; then
      echo "A signed iOS build of tree $T, validated by Apple, is in run $RUN, so iOS is not built again."
      echo "found=true" >> "$OUT"
    else
      echo "No usable signed iOS build for tree $T: iOS is built."
      echo "found=false" >> "$OUT"
    fi
    ;;
  *)
    echo "usage: find-recorded-build.sh tree | verified | record-verified DIR | signed-ios DIR" >&2
    exit 2
    ;;
esac
exit 0
