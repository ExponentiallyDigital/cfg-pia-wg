#!/bin/sh
# wait-for-checks.sh - waits for this release run's quality and security checks, and stops at once when one fails.
#
# release.yml's two release jobs build and sign beside the checks instead of after them (ID-630), so what
# the checks decide is held back to the step that publishes. A job runs this before it uploads anything:
# when every check job of the run has ended well it exits 0, and when any has failed, been cancelled or
# timed out it exits 1 at once, so nothing is published for a build the checks did not pass.
#
# The checks are the jobs of this run named "Quality & security checks / ..." (release.yml's call of
# quality_and_security.yml). A skipped job counts as passed: the release run skips the builds the signed
# builds replace. No checks listed yet is not a pass, it is a look to repeat.
#
# When VERIFIED is "true" the checks were not run for this run because the same tree's checks had already passed on
# dev (ID-685, scripts/find-recorded-build.sh): there is nothing to wait for and the script says so and exits 0.
#
# Usage: wait-for-checks.sh [TRIES] [SECONDS]
#   TRIES    how many times to look (default 120)
#   SECONDS  between looks (default 30), so 120 looks is 60 minutes
# Needs gh, GITHUB_REPOSITORY and GITHUB_RUN_ID, and the token's actions: read.
# Exit 0: every check passed. Exit 1: a check failed, or the time ran out. Exit 2: a bad call.

TRIES="${1:-120}"
PAUSE="${2:-30}"
case "$TRIES$PAUSE" in
  *[!0-9]*)
    echo "usage: wait-for-checks.sh [TRIES] [SECONDS]" >&2
    exit 2
    ;;
  *) ;; # numbers: carry on
esac
[ -n "$GITHUB_REPOSITORY" ] && [ -n "$GITHUB_RUN_ID" ] || { echo "GITHUB_REPOSITORY and GITHUB_RUN_ID are needed" >&2; exit 2; }

if [ "$VERIFIED" = "true" ]; then
  echo "The quality and security checks were not run for this build: they had already passed for this source tree on dev."
  exit 0
fi

I=1
while [ "$I" -le "$TRIES" ]; do
  # One line per check job: its conclusion once it has ended, "running" until then.
  JOBS="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs?per_page=100" \
    --jq '.jobs[] | select(.name | startswith("Quality & security checks")) | (.conclusion // "running") + " " + .name' 2> /dev/null)"

  # A job that has ended without success or a skip has not passed, whatever the word for it: failure,
  # cancelled, timed_out, action_required or one GitHub adds later.
  FAILED="$(printf '%s\n' "$JOBS" | grep -vE '^(success|skipped|neutral|running) ' | grep -v '^$' | head -1)"
  if [ -n "$FAILED" ]; then
    echo "::error::a check did not pass (${FAILED}), so nothing is published for this build"
    exit 1
  fi

  if [ -n "$JOBS" ] && ! printf '%s\n' "$JOBS" | grep -qE '^running '; then
    echo "Every quality and security check has ended well: $(printf '%s\n' "$JOBS" | wc -l | tr -d ' ') jobs."
    exit 0
  fi

  [ "$I" = "$TRIES" ] && break
  sleep "$PAUSE"
  I=$((I + 1))
done

echo "::error::the quality and security checks had not all ended after $((TRIES * PAUSE / 60)) minutes, so nothing is published for this build"
exit 1
