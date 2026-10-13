#!/bin/sh
# move-watch.sh - one device, watched each second while it is moved between tunnels in the
# router's web interface (ID-302): is it unguarded part way through, and does anything leave by the
# internet connection while it is?
#
#   /bin/sh /jffs/cfg-pia-wg/move-watch.sh <device address> [seconds]
#
# Start it from cron, so nothing ties it to an SSH session; a second copy stops at once:
#
#   cru a movewatch "* * * * *" "/bin/sh /jffs/cfg-pia-wg/move-watch.sh 192.168.1.20 900 >/dev/null 2>&1"
#
# It takes its own cron entry out when it starts, stops after [seconds] (default 900), and writes
# /tmp/move-watch.log: a line whenever anything below changes, and an ANSWERS block at the end.
# Stop it early with `kill $(cat /tmp/move-watch.pid)`; it still writes the answers and cleans up.
#
# Why not guard-watch.sh: it follows the devices pinned at each sample, so it would lose the device
# at exactly the moment this is about - when the web interface has it pinned to nothing.
#
# Each second it records, for the one address:
#
#   pin    its entry in vpnc_dev_policy_list (enabled>address>name>profile), or "none"
#   r      its guard rules: priority 90 (into the guard's table) and 91 (blackhole). 11 is guarded.
#   f      its Network Services Filter DROP rules, as lw_sync counts them. 2 is held.
#   route  where the router sends it for 1.1.1.1: a tunnel, WAN, or BLOCKED
#   up     the WireGuard tunnels that are up
#   out    packets from it that actually LEFT by the internet connection, counted in the mangle
#          table's POSTROUTING, which runs after the filter: a packet the filter drops never gets
#          there, so it is never counted. Counting in FORWARD would count those too, and call a
#          protection that worked a leak.
#   in     packets to it that arrived from the internet connection (mangle FORWARD): replies.
#
# The two counters are its only change to the router: two chains of its own in the mangle table, one
# per direction (a rule matching the incoming interface can't sit in a chain POSTROUTING reaches),
# each matching and RETURNing, so it counts and lets every packet carry on exactly as before. A
# firewall restart, which a tunnel stopping or starting causes, may take them away; they are put
# back within a second and the counts carry on from where they were, so at most a second's packets
# go uncounted around each restart. Both are taken out when it stops.
#
# Stock and Merlin. BusyBox only.

IP="$1"; DUR="${2:-900}"
case "$IP" in *[!0-9.]*|'') echo "usage: /bin/sh move-watch.sh <device address> [seconds]"; exit 2 ;; esac
case "$DUR" in ''|*[!0-9]*) echo "usage: /bin/sh move-watch.sh <device address> [seconds]"; exit 2 ;; esac
cru d movewatch 2>/dev/null

OUT=/tmp/move-watch.log
PIDFILE=/tmp/move-watch.pid
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
  echo "already running as pid $(cat "$PIDFILE")"
  exit 1
fi
echo $$ > "$PIDFILE"

WAN="$(nvram get wan0_ifname)"
E="$(echo "$IP" | sed 's/[.]/[.]/g')"
CO_=MOVEWATCHO; CI_=MOVEWATCHI
ts() { date '+%H:%M:%S'; }

# The counting chains, put in if they aren't there. Prints 1 when they had to be (a firewall restart
# took them).
count_ensure() {
  if iptables -t mangle -S "$CO_" >/dev/null 2>&1 && iptables -t mangle -S "$CI_" >/dev/null 2>&1 &&
    iptables -t mangle -S POSTROUTING 2>/dev/null | grep -q -- "-j $CO_" &&
    iptables -t mangle -S FORWARD 2>/dev/null | grep -q -- "-j $CI_"; then
    echo 0; return
  fi
  iptables -t mangle -N "$CO_" 2>/dev/null; iptables -t mangle -F "$CO_"
  iptables -t mangle -A "$CO_" -s "$IP" -j RETURN
  iptables -t mangle -N "$CI_" 2>/dev/null; iptables -t mangle -F "$CI_"
  iptables -t mangle -A "$CI_" -d "$IP" -j RETURN
  iptables -t mangle -S POSTROUTING 2>/dev/null | grep -q -- "-j $CO_" || iptables -t mangle -I POSTROUTING 1 -o "$WAN" -j "$CO_"
  iptables -t mangle -S FORWARD 2>/dev/null | grep -q -- "-j $CI_" || iptables -t mangle -I FORWARD 1 -i "$WAN" -j "$CI_"
  echo 1
}
count_remove() {
  while iptables -t mangle -D POSTROUTING -o "$WAN" -j "$CO_" 2>/dev/null; do :; done
  while iptables -t mangle -D FORWARD -i "$WAN" -j "$CI_" 2>/dev/null; do :; done
  for C in "$CO_" "$CI_"; do iptables -t mangle -F "$C" 2>/dev/null; iptables -t mangle -X "$C" 2>/dev/null; done
}
# The packet counter of a chain's one rule.
count_one() { iptables -t mangle -L "$1" -v -x -n 2>/dev/null | awk '$3 == "RETURN" {print $1 + 0; f = 1; exit} END {if (!f) print 0}'; }
count_read() { echo "$(count_one "$CO_") $(count_one "$CI_")"; }

route_of() {
  RO="$(ip route get 1.1.1.1 from "$IP" iif br0 2>&1 | head -1)"
  case "$RO" in
    *RTNETLINK*|*unreachable*|*prohibit*|*blackhole*) echo BLOCKED ;;
    *" dev wgc"[0-9]*) echo "$RO" | sed 's/.* dev \(wgc[0-9]\).*/\1/' ;;
    *" dev $WAN "*|*" dev $WAN") echo WAN ;;
    *) echo "$RO" | tr ' ' '_' | cut -c1-40 ;;
  esac
}

state() {
  PIN="$(nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' -v ip="$IP" '$2 == ip {print; exit}')"
  R="$(ip rule show 2>/dev/null)"
  N90="$(echo "$R" | grep -cE "^90:.*from $E lookup 20[1-5]( |\$)")"
  N91="$(echo "$R" | grep -c "^91:.*from $E blackhole")"
  NF="$(iptables -S FORWARD 2>/dev/null | grep -cE -- "-s $E/32 -i br0 -o [^ ]+ -p (tcp|udp) -j DROP")"
  UP="$(ip -o link show up 2>/dev/null | awk -F': ' '$2 ~ /^wgc[0-9]$/ {print $2}' | tr '\n' ',' | sed 's/,$//')"
  echo "pin=${PIN:-none} r=$N90$N91 f=$NF route=$(route_of) up=${UP:-none}"
}

OUTT=0; INT=0; LO=0; LI=0; RESETS=0
UNG=0; UNGMAX=0; WANS=0; WANMAX=0; T0="$(date +%s)"
finish() {
  count_remove
  END="$(date +%s)"
  {
    echo "[$(ts)] stopped after $((END - T0)) s"
    echo "== ANSWERS for $IP"
    echo "   packets it sent out of the internet connection: $OUTT"
    echo "   packets to it from the internet connection: $INT"
    echo "   longest run of seconds without both guard rules (r not 11): $UNGMAX"
    echo "   longest run of seconds the router routed it to the WAN: $WANMAX"
    echo "   counting chain put back after a firewall restart: $RESETS time(s), up to a second uncounted each"
  } >> "$OUT"
  rm -f "$PIDFILE"
  exit 0
}
trap finish INT TERM

: > "$OUT"
echo "[$(ts)] move-watch started for $IP, WAN $WAN, for $DUR s, pid $$" >> "$OUT"
count_ensure >/dev/null
PREV=""
while [ "$(( $(date +%s) - T0 ))" -lt "$DUR" ]; do
  if [ "$(count_ensure)" = 1 ]; then RESETS=$((RESETS + 1)); LO=0; LI=0; fi
  set -- $(count_read); CO="${1:-0}"; CI="${2:-0}"
  # A counter lower than last time was reset under us; count from zero again.
  [ "$CO" -lt "$LO" ] && LO=0
  [ "$CI" -lt "$LI" ] && LI=0
  OUTT=$((OUTT + CO - LO)); INT=$((INT + CI - LI)); LO="$CO"; LI="$CI"
  S="$(state)"
  case "$S" in *" r=11 "*) UNG=0 ;; *) UNG=$((UNG + 1)); [ "$UNG" -gt "$UNGMAX" ] && UNGMAX="$UNG" ;; esac
  case "$S" in *" route=WAN "*) WANS=$((WANS + 1)); [ "$WANS" -gt "$WANMAX" ] && WANMAX="$WANS" ;; *) WANS=0 ;; esac
  CUR="$S out=$OUTT in=$INT"
  [ "$CUR" != "$PREV" ] && echo "[$(ts)] $CUR" >> "$OUT"
  PREV="$CUR"
  sleep 1
done
finish
