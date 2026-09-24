#!/bin/sh
# e2e.sh - one word per test step on the router: PASS or FAIL (ID-207).
#
#   sh e2e.sh <test-id> before
#   ... press the button in the app ...
#   sh e2e.sh <test-id> after [expectation ...]
#
# `before` marks the start in the router log and takes a snapshot. `after` takes another, prints
# what changed, marks the end, and checks each expectation:
#
#   exit <ip> <wgcN|WAN|BLOCKED>   where the kernel would send that device's traffic now
#   rule <ip> <table|main>         exactly one firmware rule (priority 100) for it, to that table
#   norule <ip>                    no firmware rule for it
#   guard <ip> <table>             the fail-closed guard's pair (90 and 91) for it
#   noguard <ip>                   no guard rule for it
#   default <index>                vpnc_default_wan (0 is Internet)
#   up <wgcN> | down <wgcN>        whether the tunnel is running
#
# For example, after pinning 192.168.1.20 to wgc5 (table 5):
#
#   sh e2e.sh DEV-3 after "exit 192.168.1.20 wgc5" "rule 192.168.1.20 5" "guard 192.168.1.20 5"
#
# `exit` asks the kernel, with `ip route get <address> from <ip> iif br0`, how it would route a
# packet from that device, so nothing needs to be running on the device. It is the routing
# decision, not proof that the tunnel carries traffic: a tunnel whose server has stopped answering
# still reads as its own wgcN. The exit IP check on the device (scripts/exit-ip.ps1) is that proof.
#
# Nothing is changed on the router except the two log lines. Snapshots live in $E2E_DIR.

E2E_DIR="${E2E_DIR:-/tmp/cfg-pia-wg-e2e}"
PROBE="${E2E_PROBE:-1.1.1.1}"
ID="$1"
PHASE="$2"
[ -n "$ID" ] && { [ "$PHASE" = "before" ] || [ "$PHASE" = "after" ]; } || {
  echo "usage: sh e2e.sh <test-id> before|after [expectation ...]"
  exit 2
}
shift 2
mkdir -p "$E2E_DIR"

snapshot() {
  echo "## ip rule"
  ip rule show
  echo "## tunnels running"
  ip -o link show up | awk -F': ' '$2 ~ /^wgc[0-9]/ {print $2}'
  for K in vpnc_default_wan vpnc_dev_policy_list vpnc_clientlist dhcp_staticlist; do
    echo "## $K"
    nvram get "$K" | tr '<' '\n' | grep .
  done
}

# Lines only in the first file with "-", only in the second with "+", under their section. No diff:
# a router's /jffs can be wiped, and BusyBox's diff is not everywhere.
changes() {
  awk '
    FNR == 1 { f++ }
    /^## / { s = $0; next }
    f == 1 { a[s SUBSEP $0]++; next }
    { b[s SUBSEP $0]++; if (!((s SUBSEP $0) in a)) { if (!(s in shown)) { print s; shown[s] = 1 } print "+ " $0 } }
    END {
      for (k in a) if (!(k in b)) { split(k, p, SUBSEP); print p[1] " (removed)"; print "- " p[2] }
    }' "$1" "$2"
}

rules_at() { ip rule show | awk -v p="$1:" -v ip="$2" '$1 == p { for (i = 2; i < NF; i++) if ($i == "from" && $(i + 1) == ip) print }'; }

exit_of() {
  R="$(ip route get "$PROBE" from "$1" iif br0 2>&1)"
  DEV="$(echo "$R" | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
  case "$DEV" in
    '') echo BLOCKED ;;
    wgc*) echo "$DEV" ;;
    *) echo WAN ;;
  esac
}

check() {
  set -- $1
  case "$1" in
    exit) GOT="$(exit_of "$2")"; WANT="$3" ;;
    rule)
      GOT="$(rules_at 100 "$2" | awk '{for (i = 2; i < NF; i++) if ($i == "lookup") print $(i + 1)}' | tr '\n' ' ' | sed 's/ $//')"
      WANT="$3" ;;
    norule) GOT="$(rules_at 100 "$2" | grep -c .)"; WANT=0 ;;
    guard)
      GOT="$(rules_at 90 "$2" | grep -c "lookup $3 suppress_prefixlength 0") $(rules_at 91 "$2" | grep -c blackhole)"
      WANT="1 1" ;;
    noguard) GOT="$(rules_at 90 "$2" | grep -c .) $(rules_at 91 "$2" | grep -c .)"; WANT="0 0" ;;
    default) GOT="$(nvram get vpnc_default_wan)"; WANT="$2" ;;
    up) ip -o link show up | grep -q " $2:" && GOT=up || GOT=down; WANT=up ;;
    down) ip -o link show up | grep -q " $2:" && GOT=up || GOT=down; WANT=down ;;
    *) echo "FAIL  $*: not an expectation this script knows"; return 1 ;;
  esac
  if [ "$GOT" = "$WANT" ]; then echo "PASS  $*"; return 0; fi
  echo "FAIL  $*: found \"$GOT\""
  return 1
}

if [ "$PHASE" = "before" ]; then
  snapshot > "$E2E_DIR/$ID.before"
  logger -t cfg-pia-wg "**TEST $ID** STARTED"
  echo "$ID: snapshot taken. Do the step, then: sh e2e.sh $ID after [expectation ...]"
  exit 0
fi

snapshot > "$E2E_DIR/$ID.after"
echo "== $ID: what changed"
if [ -f "$E2E_DIR/$ID.before" ]; then
  C="$(changes "$E2E_DIR/$ID.before" "$E2E_DIR/$ID.after")"
  if [ -n "$C" ]; then echo "$C"; else echo "(nothing)"; fi
else
  echo "(no before snapshot for $ID)"
fi

FAILS=0
if [ $# -gt 0 ]; then
  echo "== $ID: checks"
  for E in "$@"; do check "$E" || FAILS=$((FAILS + 1)); done
fi
if [ "$FAILS" -eq 0 ]; then RESULT=PASS; else RESULT="FAIL ($FAILS)"; fi
logger -t cfg-pia-wg "**TEST $ID** ENDED $RESULT"
echo "== $ID: $RESULT"
[ "$FAILS" -eq 0 ]
