#!/bin/sh
# pktrunner-order.sh - does the router's pktrunner error follow the NUMBER of WireGuard client
# tunnels up, or particular slots?
#
#   /bin/sh /jffs/cfg-pia-wg/pktrunner-order.sh [A B]          A and B default to 2 and 4
#
# The error is the kernel's, from Broadcom's packet accelerator, a second or two after restart_vpnc:
#
#   [ERROR pktrunner] runnerUcast_inetaddr_event,220: Could not rdpa_system_ipv4_host_address_table_add ret=-3
#
# Measured 2026-10-14: enabling wgc3, the 3rd client tunnel up, logged nothing; wgc2, the 4th, and
# wgc4, the 5th, each logged it once. The reading that fits, not yet proved: the accelerator's table
# of the router's own addresses is full by then. If that's right the error follows the count, not
# the slot. So this stops A and B, then starts them the other way round: B as the 4th, A as the 5th.
#
# Stock only: restart_vpnc and vpnc_unit are stock's. Both tunnels must be up and handshaking, and
# neither may be the default connection. Devices pinned to A or B have no internet for the minute or
# two they are down: the fail-closed guard holds them, as it should. Their watchdogs, if any, are
# paused meanwhile, so neither rebuilds a tunnel this stopped. Whatever happens, both tunnels are
# started again if it stopped them, and the watchdogs and vpnc_unit put back.
#
# Output: a line per step, then ANSWERS. Changes nothing else. A second copy stops at once.
# Stock BusyBox only: no seq, no timeout, no command.

A="${1:-2}"; B="${2:-4}"
case "$A$B" in *[!1-5]*|?|???*) echo "usage: /bin/sh pktrunner-order.sh [A B], two slots from 1 to 5"; exit 2 ;; esac
[ "$A" = "$B" ] && { echo "usage: A and B must be different slots"; exit 2; }
[ "$(nvram get 3rd-party)" = merlin ] && { echo "REFUSED: stock only; Merlin starts tunnels another way"; exit 2; }

LOCK=/tmp/pktrunner-order.lock
SYSLOG=/tmp/syslog.log
mkdir "$LOCK" 2>/dev/null || { echo "REFUSED: already running (or $LOCK left behind: rmdir it if not)"; exit 1; }

say() { echo "$(date '+%H:%M:%S') $1"; }
# The tunnel's vpnc_clientlist row, as vpnc_unit names it (as check-claims.sh works it out).
unit_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$1" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}'; }
# The tunnel's index 6, which vpnc_default_wan holds when it is the default connection.
idx_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$1" '$3 == s {print $7; exit}'; }
up() { ip -o link show up 2>/dev/null | grep -q " wgc$1:"; }
# One sighting is not "up" (CONTEXT.md): a tunnel mid-restart is seen once.
up2() { up "$1" && sleep 1 && up "$1"; }
down2() { ! up "$1" && sleep 1 && ! up "$1"; }
hs() { wg show "wgc$1" latest-handshakes 2>/dev/null | awk '{if ($2 > m) m = $2} END {print m + 0}'; }
clients() { ip -o link show up 2>/dev/null | grep -c ' wgc[0-9]:'; }
errs() { E="$(grep -c 'rdpa_system_ipv4_host_address_table_add' "$SYSLOG" 2>/dev/null)"; echo "${E:-0}"; }
# The service queue: a call made while another runs can be dropped (CONTEXT.md, notify_rc).
idle() {
  i=0
  while [ -n "$(nvram get rc_service)" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  [ -z "$(nvram get rc_service)" ]
}

stop_slot() {
  idle || { say "the router's service queue stayed busy for 30 s; not stopping wgc$1"; return 1; }
  nvram set vpnc_unit="$(unit_of "$1")"; service stop_vpnc
  i=0; while [ "$i" -lt 30 ] && ! down2 "$1"; do sleep 1; i=$((i + 1)); done
  down2 "$1"
}
# Starts a tunnel and waits for it to be up with a handshake newer than the start. Sets STARTED_AS
# to how many client tunnels are up afterwards.
start_slot() {
  idle || { say "the router's service queue stayed busy for 30 s; not starting wgc$1"; return 1; }
  T0="$(date +%s)"
  nvram set vpnc_unit="$(unit_of "$1")"; service restart_vpnc
  i=0; while [ "$i" -lt 45 ] && ! { up2 "$1" && [ "$(hs "$1")" -ge "$T0" ]; }; do sleep 1; i=$((i + 1)); done
  STARTED_AS="$(clients)"
  up2 "$1" && [ "$(hs "$1")" -ge "$T0" ]
}

# ---- preconditions ----------------------------------------------------------------------------
UA="$(unit_of "$A")"; UB="$(unit_of "$B")"
[ -n "$UA" ] && [ -n "$UB" ] || { echo "REFUSED: wgc$A or wgc$B has no vpnc_clientlist row"; rmdir "$LOCK"; exit 2; }
DEF="$(nvram get vpnc_default_wan)"
for S in "$A" "$B"; do
  if [ -n "$DEF" ] && [ "$DEF" != 0 ] && [ "$(idx_of "$S")" = "$DEF" ]; then
    echo "REFUSED: wgc$S is the default connection; stopping it would cut the internet for every device that follows it"
    rmdir "$LOCK"; exit 2
  fi
  up2 "$S" && [ "$(hs "$S")" -gt 0 ] || { echo "REFUSED: wgc$S isn't up and handshaking; start it first"; rmdir "$LOCK"; exit 2; }
done
OLDUNIT="$(nvram get vpnc_unit)"
CRUSAVE=/tmp/pktrunner-order.cru
cru l | grep -E "#watchdog_wgc($A|$B)#" > "$CRUSAVE"

restore() {
  for S in "$A" "$B"; do up "$S" || { say "putting wgc$S back"; start_slot "$S" || say "wgc$S did NOT come back: start it in the app"; }; done
  while read -r L; do X="${L%#}"; cru a "${X##*#}" "$(X2="${X%#*}"; echo "${X2% }")"; done < "$CRUSAVE"
  nvram set vpnc_unit="$OLDUNIT"
  rm -f "$CRUSAVE"; rmdir "$LOCK" 2>/dev/null
  logger "**PKTRUNNER-ORDER END**"
}
trap restore EXIT
trap 'exit 1' INT TERM

logger "**PKTRUNNER-ORDER START** wgc$A and wgc$B"
say "start: $(clients) client tunnels up, $(errs) pktrunner errors in the log so far"
while read -r L; do X="${L%#}"; cru d "${X##*#}"; done < "$CRUSAVE"
[ -s "$CRUSAVE" ] && say "paused $(wc -l < "$CRUSAVE" | tr -d ' ') watchdog(s) on wgc$A and wgc$B"

# ---- the test ---------------------------------------------------------------------------------
E0="$(errs)"
stop_slot "$A" || { say "wgc$A didn't stop; nothing measured"; exit 1; }
stop_slot "$B" || { say "wgc$B didn't stop; nothing measured"; exit 1; }
E1="$(errs)"
say "stopped wgc$A and wgc$B: $(clients) client tunnels up, $((E1 - E0)) new errors"

start_slot "$B" || { say "wgc$B didn't come up with a fresh handshake in 45 s; nothing more measured"; exit 1; }
sleep 5
E2="$(errs)"; NB="$STARTED_AS"; DB=$((E2 - E1))
say "started wgc$B as client tunnel $NB: $DB new errors"

start_slot "$A" || { say "wgc$A didn't come up with a fresh handshake in 45 s; nothing more measured"; exit 1; }
sleep 5
E3="$(errs)"; NA="$STARTED_AS"; DA=$((E3 - E2))
say "started wgc$A as client tunnel $NA: $DA new errors"

echo
echo "ANSWERS"
echo "wgc$B started as client tunnel $NB: $DB pktrunner error(s)"
echo "wgc$A started as client tunnel $NA: $DA pktrunner error(s)"
[ "$E1" -lt "$E0" ] && echo "NOTE: the log rotated during the run, so these counts can't be trusted; run it again"
if [ "$NB" -lt 4 ] || [ "$NA" -lt 4 ]; then
  echo "VERDICT: not a fair test - fewer than 4 client tunnels were up when one started (another tunnel is down?)"
elif [ "$DB" -ge 1 ] && [ "$DA" -ge 1 ]; then
  echo "VERDICT: it follows the count - client tunnels 4 and 5 log it whichever slots they are"
elif [ "$DB" -eq 0 ] && [ "$DA" -eq 0 ]; then
  echo "VERDICT: neither logged it this time - the count theory isn't supported; it may follow something else"
else
  echo "VERDICT: only one logged it - it follows neither the count nor the slots cleanly"
fi
echo "Both tunnels are $(up "$A" && up "$B" && echo "up again" || echo "NOT both up: check the app")."
