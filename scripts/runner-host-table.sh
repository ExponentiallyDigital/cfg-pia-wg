#!/bin/sh
# runner-host-table.sh - which of the router's IPv4 addresses Broadcom's packet accelerator knows as
# the router's own, and whether an important one has been left out (ID-393).
#
#   /bin/sh /jffs/cfg-pia-wg/runner-host-table.sh            read the table now; changes nothing
#   /bin/sh /jffs/cfg-pia-wg/runner-host-table.sh wan        reconnect the WAN, and read it before and after
#
# The accelerator keeps a table of the router's own addresses: 8 places on the test router, first
# come first served, each given up when its interface goes down. Measured 2026-10-14 with five
# client tunnels up: all 8 in use, and the two tunnels started last left out, which costs nothing as
# far as is known, since WireGuard runs in software. What would matter is the WAN, a LAN or the
# WireGuard server being left out, because their traffic does pass through the accelerator. The
# kernel logs "[ERROR pktrunner] ... rdpa_system_ipv4_host_address_table_add ret=-3" for each
# address left out (ARCHITECTURE 4.2.6).
#
# Important: every address not on a client tunnel (wgcN) or loopback. Run `check` after a reboot,
# once the tunnels are up, to see whether the boot order left one out.
#
# `wan` asks for `service "restart_wan_if 0"`, which drops the internet for everyone for a few
# seconds to a minute, then waits for the WAN and for the tunnels that were up to come back, and
# reads the table again. It changes nothing else. Watchdogs are paused meanwhile so none rebuilds a
# tunnel while the WAN is down, and put back however it ends. A second copy stops at once.
#
# Output: the addresses, in or out, then ANSWERS. The exit status is the number of important
# addresses left out, or 3 if the table couldn't be read: an empty reading is never taken as an
# empty table, and `wan` reconnects nothing unless it read the table first. Stock and Merlin; BusyBox
# only: no seq, no timeout, no command.

MODE="${1:-check}"
case "$MODE" in check|wan) ;; *) echo "usage: /bin/sh runner-host-table.sh [check|wan]"; exit 2 ;; esac
BS=/bin/bs
[ -x "$BS" ] || { echo "REFUSED: no $BS on this router, so the accelerator's table can't be read"; exit 2; }
SYSLOG=/tmp/syslog.log
T=/tmp/runner-host-table
WAN="$(nvram get wan0_ifname)"

say() { echo "$(date '+%H:%M:%S') $1"; }
# The table as the accelerator holds it, one address a line. Each address is found by its shape, not
# by its place on the line: the first version matched the whole line with sed, and on 2026-10-14 read
# nothing on the router from output the desktop's sed read in full.
table() { "$BS" /b/e system 2>&1 | grep 'ipv4_host_address_table\[' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^0\.0\.0\.0$'; }
# The router's IPv4 addresses, "interface address" a line.
addrs() { ip -o -4 addr show 2>/dev/null | awk '{split($4, a, "/"); print $2, a[1]}'; }
errs() { E="$(grep -c 'rdpa_system_ipv4_host_address_table_add' "$SYSLOG" 2>/dev/null)"; echo "${E:-0}"; }
kind() {
  case "$1" in
    lo) echo loopback ;;
    wgc[0-9]) echo tunnel ;;
    "$WAN") echo "important, the WAN" ;;
    *) echo important ;;
  esac
}

# Reads the table against the addresses. Prints each, and sets IMPMISS (count), IMPLIST, TUNLIST.
report() {
  table > "$T.table"
  addrs > "$T.addrs"
  IMPMISS=0; IMPLIST=""; TUNLIST=""
  # An empty reading is a reading that failed, never a table with nothing in it: the router always
  # has addresses of its own. Calling every address "left out" on 2026-10-14 was this exact mistake.
  if [ ! -s "$T.table" ]; then
    echo "  UNREADABLE: $BS printed no table addresses. What it printed for the table:"
    "$BS" /b/e system 2>&1 | grep 'host_address' | head -3 | sed -n l
    rm -f "$T.table" "$T.addrs"
    return 1
  fi
  echo "  table: $(wc -l < "$T.table" | tr -d ' ') addresses in use"
  while read -r IF IP; do
    K="$(kind "$IF")"
    if grep -qx "$IP" "$T.table"; then
      echo "  in      $IF $IP ($K)"
    else
      echo "  NOT IN  $IF $IP ($K)"
      case "$K" in
        important*) IMPMISS=$((IMPMISS + 1)); IMPLIST="$IMPLIST $IF" ;;
        tunnel) TUNLIST="$TUNLIST $IF" ;;
      esac
    fi
  done < "$T.addrs"
  rm -f "$T.table" "$T.addrs"
}

if [ "$MODE" = check ]; then
  say "the accelerator's table of the router's own addresses:"
  report || { echo; echo "ANSWERS"; echo "the table couldn't be read, so nothing is known about it"; exit 3; }
  echo
  echo "ANSWERS"
  echo "important addresses left out: $IMPMISS${IMPLIST:+ -$IMPLIST}"
  echo "tunnel addresses left out:${TUNLIST:- none}"
  echo "pktrunner errors in the log: $(errs)"
  exit "$IMPMISS"
fi

# ---- wan --------------------------------------------------------------------------------------
LOCK=/tmp/runner-host-table.lock
mkdir "$LOCK" 2>/dev/null || { echo "REFUSED: already running (or $LOCK left behind: rmdir it if not)"; exit 1; }
online() { ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; }
online || { echo "REFUSED: the router isn't online now, so a reconnect would prove nothing"; rmdir "$LOCK"; exit 2; }
up() { ip -o link show up 2>/dev/null | grep -q " $1:"; }
hs() { wg show "$1" latest-handshakes 2>/dev/null | awk '{if ($2 > m) m = $2} END {print m + 0}'; }
idle() {
  i=0
  while [ -n "$(nvram get rc_service)" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  [ -z "$(nvram get rc_service)" ]
}

CRUSAVE="$T.cru"
cru l | grep '#watchdog_wgc[0-9]#' > "$CRUSAVE"
restore() {
  while read -r L; do X="${L%#}"; cru a "${X##*#}" "$(X2="${X%#*}"; echo "${X2% }")"; done < "$CRUSAVE"
  rm -f "$CRUSAVE"; rmdir "$LOCK" 2>/dev/null
  logger "**RUNNER-HOST-TABLE END**"
}
trap restore EXIT
trap 'exit 1' INT TERM
logger "**RUNNER-HOST-TABLE START** wan"
while read -r L; do X="${L%#}"; cru d "${X##*#}"; done < "$CRUSAVE"
[ -s "$CRUSAVE" ] && say "paused $(wc -l < "$CRUSAVE" | tr -d ' ') watchdog(s)"

TUNS="$(ip -o link show up 2>/dev/null | grep -o ' wgc[0-9]:' | tr -d ' :' | tr '\n' ' ')"
say "before the reconnect (tunnels up: ${TUNS:-none}):"
report || { say "the table couldn't be read, so the WAN was NOT reconnected: nothing was changed"; exit 3; }
B_IMP="$IMPMISS"; B_IMPLIST="$IMPLIST"; B_TUN="$TUNLIST"
E0="$(errs)"

idle || { say "the router's service queue stayed busy for 30 s; nothing was changed"; exit 1; }
T0="$(date +%s)"
say "reconnecting the WAN: the internet drops for everyone for a few seconds"
service "restart_wan_if 0"
sleep 5
i=0; while [ "$i" -lt 120 ] && ! online; do sleep 1; i=$((i + 1)); done
online && say "online again after $(($(date +%s) - T0)) s" || say "NOT online again after $(($(date +%s) - T0)) s"
# The tunnels that were up, each up again with a handshake newer than the reconnect.
for N in $TUNS; do
  i=0; while [ "$i" -lt 120 ] && ! { up "$N" && [ "$(hs "$N")" -ge "$T0" ]; }; do sleep 1; i=$((i + 1)); done
done
BACK=""; NOTBACK=""
for N in $TUNS; do if up "$N" && [ "$(hs "$N")" -ge "$T0" ]; then BACK="$BACK $N"; else NOTBACK="$NOTBACK $N"; fi; done
sleep 10
say "after the reconnect:"
AFTERBAD=0
report || AFTERBAD=1
E1="$(errs)"

echo
echo "ANSWERS"
echo "important addresses left out before: $B_IMP${B_IMPLIST:+ -$B_IMPLIST}; after: $IMPMISS${IMPLIST:+ -$IMPLIST}"
echo "tunnel addresses left out before:${B_TUN:- none}; after:${TUNLIST:- none}"
echo "pktrunner errors during the reconnect: $((E1 - E0))"
echo "tunnels back with a fresh handshake:${BACK:- none}${NOTBACK:+; NOT back:$NOTBACK}"
if [ "$AFTERBAD" = 1 ]; then
  echo "VERDICT: none - the table couldn't be read after the reconnect"
  exit 3
elif ! online; then
  echo "VERDICT: the router didn't come back online in 2 minutes; the table reading after it means little"
elif [ "$IMPMISS" -gt 0 ]; then
  echo "VERDICT: HARMFUL ORDER - after the reconnect, an important address is left out:$IMPLIST"
else
  echo "VERDICT: the reconnect left every important address in the table"
fi
exit "$IMPMISS"
