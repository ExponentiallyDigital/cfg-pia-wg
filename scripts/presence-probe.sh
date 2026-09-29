#!/bin/sh
# presence-probe.sh - every place the router says whether one device is online, logged as it changes (ID-165).
#
#   sh presence-probe.sh AA:BB:CC:DD:EE:FF [seconds]
#
# Checks every [seconds] (default 5) and prints a line only when a source changes its answer, with
# the time, and for a file, when the firmware last wrote it. So it can be left running on its own:
#
#   nohup sh /jffs/cfg-pia-wg/presence-probe.sh AA:BB:CC:DD:EE:FF > /tmp/presence.log 2>&1 &
#
# then switch the device off, and later on, and read /tmp/presence.log. Stop it with
# `kill $(cat /tmp/presence-probe.pid)`. Its PID looks as if it keeps changing in `ps`, because each
# check runs in a short-lived subshell; the loop's own PID is the one in that file.
#
# `nmp_cl_json` is exactly what DEVICE ASSIGNMENT shows: the app takes online/offline from that one
# field. What the web interface shows comes from its own client list, which
# scripts/webui-presence.ps1 logs from a PC. The source whose changes line up with the web
# interface's is the one the app should read.
#
# Why: on 2026-09-21 a tablet switched off at 09:34 showed offline in the web interface at once and
# online in the app until 09:40. Andrew's guess, 2026-09-27: the firmware writes /tmp first and
# /jffs later, to spare the flash; the write times test that.
#
# Reads only. Changes nothing.

MAC="$(echo "$1" | tr 'a-f' 'A-F')"
EVERY="${2:-5}"
case "$MAC" in
  ??:??:??:??:??:??) ;;
  *) echo "usage: sh presence-probe.sh AA:BB:CC:DD:EE:FF [seconds]"; exit 2 ;;
esac
LOWER="$(echo "$MAC" | tr 'A-F' 'a-f')"

# This device's record in a JSON file, whole.
entry() { [ -f "$1" ] && grep -io "\"$MAC\":{[^}]*}" "$1" | head -1; }
# When the firmware last wrote a file.
written() { [ -f "$1" ] && date -r "$1" '+%H:%M:%S' 2>/dev/null; }

# Each source reduced to its answer alone, so a line means the answer changed, not a signal
# strength or a byte count.
s_cl_json() {
  [ -f /jffs/nmp_cl_json.js ] || { echo "no file"; return; }
  v="$(entry /jffs/nmp_cl_json.js | grep -o '"online":[^,}]*' | head -1)"
  echo "${v:-not listed}"
}
s_cache() {
  [ -f /tmp/nmp_cache.js ] || { echo "no file"; return; }
  v="$(entry /tmp/nmp_cache.js | grep -o '"isOnline":[^,}]*' | head -1)"
  echo "${v:-not listed}"
}
s_clientlist() {
  [ -f /tmp/clientlist.json ] || { echo "no file"; return; }
  grep -qi "$MAC" /tmp/clientlist.json && echo "listed" || echo "not listed"
}
s_neigh() {
  v="$(ip neigh show | grep -i "$LOWER" | head -1 | awk '{print $NF}')"
  echo "${v:-none}"
}
s_wifi() {
  for IF in $(nvram get wl_ifnames); do
    if wl -i "$IF" assoclist 2>/dev/null | grep -qi "$MAC"; then echo "associated on $IF"; return; fi
  done
  echo "not associated"
}
s_lease() {
  grep -qi "$LOWER" /var/lib/misc/dnsmasq.leases 2>/dev/null && echo "leased" || echo "no lease"
}

echo $$ > /tmp/presence-probe.pid
trap 'rm -f /tmp/presence-probe.pid; exit 0' INT TERM
logger -t cfg-pia-wg "presence-probe started for $MAC"
echo "== $(date '+%Y-%m-%d %H:%M:%S') presence-probe for $MAC, every ${EVERY}s"
echo "== candidate files"
ls -l /jffs/nmp_*.js /tmp/nmp_*.js /tmp/clientlist.json /tmp/*client*.js* 2>/dev/null

# Remembers each source's last answer and prints only a change. The first pass prints them all.
P_cl_json="" P_cache="" P_clientlist="" P_neigh="" P_wifi="" P_lease=""
report() {
  name="$1" now="$2" file="$3"
  eval "was=\$P_$name"
  [ "$now" = "$was" ] && return
  eval "P_$name=\$now"
  line="$(date '+%H:%M:%S') $name: ${was:-(start)} -> $now"
  [ -f "$file" ] && line="$line [file written $(written "$file")]"
  echo "$line"
}

while :; do
  report cl_json "$(s_cl_json)" /jffs/nmp_cl_json.js
  report cache "$(s_cache)" /tmp/nmp_cache.js
  report clientlist "$(s_clientlist)" /tmp/clientlist.json
  report neigh "$(s_neigh)"
  report wifi "$(s_wifi)"
  report lease "$(s_lease)"
  sleep "$EVERY"
done
