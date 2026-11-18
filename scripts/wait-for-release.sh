#!/bin/sh
# wait-for-release.sh - waits for the GitHub release of a tag, and stops at once when it can't come.
#
# The iOS job of release.yml attaches its SBOM to the release the Android job creates, and runs
# beside that job, so it has to wait for the release to exist. When the Android job failed on
# 2026-11-17, the iOS job waited out all 30 minutes on a macOS runner for a release that was never
# going to appear, and a cancel did not interrupt it (ID-624).
#
# Usage: wait-for-release.sh TAG [TRIES] [SECONDS]
#   TRIES    how many times to look (default 60)
#   SECONDS  between looks (default 30), so 60 looks is 30 minutes
# Needs gh, GITHUB_REPOSITORY and GITHUB_RUN_ID, and the token's actions: read.
# Exit 0: the release exists. Exit 1: the Android job ended without one, or the time ran out.

TAG="$1"
TRIES="${2:-60}"
PAUSE="${3:-30}"
[ -n "$TAG" ] || { echo "usage: wait-for-release.sh TAG [TRIES] [SECONDS]" >&2; exit 2; }

I=1
while [ "$I" -le "$TRIES" ]; do
  gh release view "$TAG" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1 && exit 0

  # What the Android job has done so far: its conclusion once it has ended, "running" until then.
  JOB="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" \
    --jq '.jobs[] | select(.name == "Build and release") | .conclusion // "running"' 2> /dev/null)"
  case "$JOB" in
    failure | cancelled | skipped | timed_out)
      echo "::error::the Android release job ended as $JOB, so no release $TAG is coming and the iOS SBOM is only the run's artifact"
      exit 1
      ;;
    *) ;; # running, success or unknown: keep looking
  esac

  [ "$I" = "$TRIES" ] && break
  sleep "$PAUSE"
  I=$((I + 1))
done

echo "::error::no release $TAG after $((TRIES * PAUSE / 60)) minutes, so the iOS SBOM is only the run's artifact"
exit 1
