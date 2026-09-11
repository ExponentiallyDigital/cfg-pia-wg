#!/bin/sh
# test-backoff.sh - walk the watchdog backoff ladder in seconds, asking PIA for nothing.
#
# Usage:  ./test-backoff.sh [slot]        (slot defaults to 5)
#
# WHY THIS EXISTS
#
# Reaching the 90-minute rung honestly means seven consecutive FAILED reconfigures, each of which
# asks PIA for a token. That is exactly what got the account refused with HTTP 403 on 2026-09-04,
# and it would take most of a day. This reaches every rung in about two minutes with no PIA traffic
# at all.
#
# WHY IT IS SAFE
#
# The backoff gate sits AFTER the connectivity check and BEFORE the first PIA call. A run the gate
# turns away logs one line and exits, so pre-loading the counter exercises the real arithmetic in
# the real deployed script without a single token request.
#
# WHAT YOU MUST DO FIRST (the script checks both and refuses if they are not done)
#
#   1. PAUSE the watchdog for this slot in the app. Otherwise cron fires its own checks during the
#      test, and one arriving after a window has expired performs a genuine reconfigure - PIA
#      traffic, a new key, and a counter reset part-way through the loop.
#   2. Make the connectivity check fail, or the script exits at the handshake and never reaches the
#      backoff block:
#
#      wg set wgc5 peer "$(nvram get wgc5_ppub)" remove
#
# Full write-up in TESTING.md section 2.1.6.

SLOT="${1:-5}"
IFACE="wgc${SLOT}"
SCRIPT="/jffs/cfg-pia-wg/watchdog_${IFACE}.sh"
LOGFILE="/tmp/watchdog_${IFACE}.log"
BACKOFFFILE="/tmp/watchdog_backoff_${IFACE}"

# The ladder, as n:expected-seconds. Must match kBackoffLadder in lib/router_watchdog.dart.
LADDER="1:120 2:240 3:480 4:960 5:1800 6:3600 7:5400 12:5400"

die() { echo "ERROR: $1" >&2; exit 1; }

# `grep -c` prints 0 AND exits 1 when it matches nothing, so `grep -c ... || echo 0` yields two
# lines and every later arithmetic test blows up. Take the first line and insist it is a number.
count_in_log() {
    n="$(grep -c "$1" "$LOGFILE" 2>/dev/null | head -1)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    echo "$n"
}

echo "== preconditions for $IFACE =="

[ -s "$SCRIPT" ] || die "$SCRIPT is missing. Deploy a watchdog for $IFACE first."

if cru l 2>/dev/null | grep -qw "watchdog_${IFACE}"; then
    die "the $IFACE watchdog is still SCHEDULED.
       Pause it in the app first (WATCHDOG -> $IFACE -> DISABLE), or a cron-fired check will
       perform a real reconfigure part-way through this test and reset the counter."
fi
echo "  watchdog is paused (no cru entry)   OK"

# A healthy tunnel exits at the handshake check and never reaches the backoff block.
HS="$(wg show "$IFACE" latest-handshakes 2>/dev/null | awk '{if ($2 > m) m = $2} END {print m + 0}')"
AGE=$(( $(date +%s) - HS ))
if [ "$HS" -gt 0 ] && [ "$AGE" -lt 300 ]; then
    die "$IFACE handshook ${AGE}s ago, so its check will PASS and the backoff never runs.
       Break it first:  wg set $IFACE peer \"\$(nvram get ${IFACE}_ppub)\" remove"
fi
echo "  connectivity check will fail        OK"

TOKENS_BEFORE="$(count_in_log 'Requesting PIA token')"

echo
echo "== walking the ladder =="
FAILURES=0
LAST_N=0
for pair in $LADDER; do
    n="${pair%%:*}"
    want="${pair##*:}"
    LAST_N="$n"

    # A timestamp of NOW guarantees ~0 elapsed, so every rung is inside its window and every run
    # must be turned away - which is the state under test.
    printf '%s\n%s\n' "$n" "$(date +%s)" > "$BACKOFFFILE"

    seen_before="$(count_in_log 'Backing off')"
    "$SCRIPT" >/dev/null 2>&1
    seen_after="$(count_in_log 'Backing off')"

    if [ "$seen_after" -le "$seen_before" ]; then
        echo "  CNT=$n  FAIL  the run was not turned away - it logged no 'Backing off' line"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    line="$(grep 'Backing off' "$LOGFILE" | tail -1)"
    got="$(echo "$line" | sed -n 's/.*of \([0-9]*\)s elapsed.*/\1/p')"
    if [ "$got" = "$want" ]; then
        echo "  CNT=$n  OK    waits ${got}s"
    else
        echo "  CNT=$n  FAIL  expected ${want}s, got [${got:-nothing}] - $line"
        FAILURES=$((FAILURES + 1))
    fi
done

echo
echo "== the two properties most easily broken by a later change =="

# If the gate ever moves to AFTER the first PIA call, a broken tunnel hammers PIA on every check.
TOKENS_AFTER="$(count_in_log 'Requesting PIA token')"
if [ "$TOKENS_AFTER" -eq "$TOKENS_BEFORE" ]; then
    echo "  no PIA token requests during the test   OK"
else
    echo "  PIA token requests during the test      FAIL ($((TOKENS_AFTER - TOKENS_BEFORE)) new)"
    echo "        the backoff gate is running AFTER the first PIA call"
    FAILURES=$((FAILURES + 1))
fi

# If a turned-away run increments the counter, the ladder climbs at a rate that depends on the
# check interval - a 1 m watchdog would escalate five times faster than a 5 m one.
COUNT_NOW="$(head -1 "$BACKOFFFILE" 2>/dev/null)"
if [ "$COUNT_NOW" = "$LAST_N" ]; then
    echo "  turned-away runs left the counter alone OK"
else
    echo "  counter moved from $LAST_N to $COUNT_NOW      FAIL"
    echo "        a run the backoff refused must not increment it"
    FAILURES=$((FAILURES + 1))
fi

rm -f "$BACKOFFFILE"

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "PASS - all rungs correct, counter untouched, no PIA traffic."
else
    echo "$FAILURES CHECK(S) FAILED - see above."
fi
echo
echo "Cleaned up $BACKOFFFILE. Now re-enable the $IFACE watchdog in the app,"
echo "and bring the tunnel back (the next check will reconfigure it)."

[ "$FAILURES" -eq 0 ]
