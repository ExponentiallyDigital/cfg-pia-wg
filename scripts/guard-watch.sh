#!/bin/sh
# guard-watch.sh - the fail-closed guard's two layers and the firmware's asd, sampled as they change (ID-360).
#
#   /bin/sh guard-watch.sh [seconds]
#
# Run it as `/bin/sh /jffs/cfg-pia-wg/guard-watch.sh`, never `sh ...`: over SSH, stock's PATH finds
# /usr/sbin/sh first, and that is a Broadcom memory tool, not the shell.
#
# Checks every [seconds] (default 5), and writes to /tmp/guard-watch.log only when something
# changes, so it can be left running for hours. Start it from cron, which no SSH session owns:
# `nohup` didn't survive dropbear's idle logout on 2026-10-02 (ID-365). The entry tries every
# minute, and while a copy is running the new one stops at once:
#
#   cru a guardwatch "* * * * *" "/bin/sh /jffs/cfg-pia-wg/guard-watch.sh 60 >/dev/null 2>&1"
#
# Read it with `tail -40 /tmp/guard-watch.log`, stop it with
# `cru d guardwatch; kill $(cat /tmp/guard-watch.pid)`. The log and the cron entry live in RAM, so a
# reboot ends the run and loses both; add the entry again afterwards.
#
# Why. On 2026-10-02 build 490's syslog showed the firmware's own asd daemon faulting about one
# watchdog run in six, a second or two after the run starts, and each fault followed within 11
# seconds by a firewall restart the app never asked for. ID-227 recorded the same pairing on
# 2026-09-27. asd is closed firmware and its crash is the firmware's business; the firewall restart
# is not, because the Network Services Filter lives in the firewall. So the question this answers is
# whether the guard's protection ever drops while that happens.
#
# Each sample records, for every device pinned to a tunnel:
#
#   f<n>     DROP rules the FORWARD chain holds for it, counted exactly as lw_sync counts them.
#            2 is healthy, one each for tcp and udp. This is the filter layer, and it is the one a
#            firewall restart rebuilds.
#   r<n><n>  the kernel's rule at priority 90 (into the guard's own table for the tunnel, 200 + slot,
#            from build 491, ID-364) and at 91 (blackhole everything else). 11 is healthy. These
#            are the fail-closed layer proper; they live in the routing policy database, which a
#            firewall restart does not touch. A device pinned to a profile that no longer exists
#            gets only the 91 rule, so 01 is correct for those.
#
# and alongside them asd's PID, so a fault shows as the PID changing. Reading both layers against
# asd in one line is the point. If r ever reads other than 11 outside a deliberate rebuild, the
# fail-closed promise broke and that is a release problem. If only f dips, the filter is the layer
# to repair. If neither moves while asd's PID changes underneath them, the crashes are noise and
# can be left to ASUS.
#
# It is also how to test a suspected trigger by hand: leave it running, run the thing you suspect
# (`/bin/sh /jffs/cfg-pia-wg/guard.sh`, say) several times, and read whether asd's PID changed.
#
# Pinned devices are worked out afresh on every sample from vpnc_dev_policy_list, the same source
# guard.sh uses, so a pin made or removed while this runs shows up as a change rather than being
# missed.
#
# Reads only. Changes nothing.

EVERY="${1:-5}"
case "$EVERY" in ''|*[!0-9]*) echo "usage: /bin/sh guard-watch.sh [seconds]"; exit 2 ;; esac
[ "$EVERY" -lt 1 ] && EVERY=1

OUT=/tmp/guard-watch.log
PIDFILE=/tmp/guard-watch.pid
# An "unchanged" line every 10 minutes, so the log shows the quiet periods too.
HEARTBEAT=$((600 / EVERY))
[ "$HEARTBEAT" -lt 1 ] && HEARTBEAT=1

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
  echo "already running as pid $(cat "$PIDFILE"); stop it first"
  exit 1
fi
echo $$ > "$PIDFILE"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Enabled pins only, the same field test guard.sh makes: 1>ip>name>table.
pinned() {
  nvram get vpnc_dev_policy_list 2>/dev/null | tr '<' '\n' |
    awk -F'>' '$1 == "1" && $2 != "" {print $2}' | sort -u
}

sig() {
  F="$(iptables -S FORWARD 2>/dev/null)"
  R="$(ip rule show 2>/dev/null)"
  S=""
  for IP in $(pinned); do
    E="$(echo "$IP" | sed 's/[.]/[.]/g')"
    N="$(echo "$F" | grep -cE -- "-s $E/32 -i br0 -o [^ ]+ -p (tcp|udp) -j DROP")"
    N90="$(echo "$R" | grep -cE "^90:.*from $E lookup 20[1-5]( |\$)")"
    N91="$(echo "$R" | grep -c "^91:.*from $E blackhole")"
    S="$S $IP:f$N/r$N90$N91"
  done
  [ -z "$S" ] && S=" (no device pinned)"
  echo "$S lw=$(nvram get fw_lw_enable_x) asd=$(pidof asd 2>/dev/null | awk '{print $1}')"
}

detail() {
  P="$(pinned | sed 's/[.]/[.]/g' | tr '\n' '|' | sed 's/|$//')"
  echo "    FORWARD:"
  if [ -n "$P" ]; then iptables -S FORWARD 2>/dev/null | grep -E -- "-s ($P)/32" | sed 's/^/      /'; fi
  echo "    ip rule 88-91:"
  ip rule show 2>/dev/null | grep -E "^(88|89|90|91):" | sed 's/^/      /'
  echo "    fw_lw_enable_x=$(nvram get fw_lw_enable_x)"
  echo "    filter_lwlist=$(nvram get filter_lwlist)"
  echo "    syslog:"
  grep -E "Watchdog started|Comm: asd|notify_rc restart_firewall|Network Services Filter" \
    /tmp/syslog.log 2>/dev/null | tail -8 | sed 's/^/      /'
}

echo "[$(ts)] guard-watch started, every ${EVERY}s, pid $$" >> "$OUT"
PREV=""
C=0
while :; do
  CUR="$(sig)"
  if [ "$CUR" != "$PREV" ]; then
    if [ -z "$PREV" ]; then
      echo "[$(ts)] baseline:$CUR" >> "$OUT"
    else
      echo "[$(ts)] CHANGED:$CUR" >> "$OUT"
      echo "[$(ts)]     was:$PREV" >> "$OUT"
    fi
    detail >> "$OUT"
    PREV="$CUR"
    C=0
  else
    C=$((C + 1))
    if [ "$C" -ge "$HEARTBEAT" ]; then
      echo "[$(ts)] unchanged:$CUR" >> "$OUT"
      C=0
    fi
  fi
  sleep "$EVERY"
done
