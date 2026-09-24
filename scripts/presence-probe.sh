#!/bin/sh
# presence-probe.sh - every place the router says whether one device is online, side by side (ID-165).
#
#   sh presence-probe.sh AA:BB:CC:DD:EE:FF [seconds]
#
# Prints one line per source every [seconds] (default 30) until Ctrl-C. Switch the device off, and
# on again, while it runs, and note when the WebUI's client list changes. The first source to
# follow the WebUI is the one the app should read.
#
# Why: the app reads online/offline from /jffs/nmp_cl_json.js. On 2026-09-21 a tablet switched off
# at 09:34 showed offline in the WebUI at once and online in the app until 09:40, and another
# device stayed "online" in the app for more than 48 hours. Which source the WebUI uses is not known.
#
# Reads only. Changes nothing.

MAC="$(echo "$1" | tr 'a-f' 'A-F')"
EVERY="${2:-30}"
case "$MAC" in
  ??:??:??:??:??:??) ;;
  *) echo "usage: sh presence-probe.sh AA:BB:CC:DD:EE:FF [seconds]"; exit 2 ;;
esac
LOWER="$(echo "$MAC" | tr 'A-F' 'a-f')"

entry() { [ -f "$1" ] && grep -io "\"$MAC\":{[^}]*}" "$1" | head -1 | cut -c1-160; }

logger -t cfg-pia-wg "presence-probe started for $MAC"
while :; do
  echo "== $(date '+%H:%M:%S')"
  echo "nmp_cl_json   : $(entry /jffs/nmp_cl_json.js)"
  echo "nmp_cache     : $(entry /tmp/nmp_cache.js)"
  [ -f /tmp/clientlist.json ] && echo "clientlist    : $(entry /tmp/clientlist.json)"
  IP="$(ip neigh show | grep -i "$LOWER" | head -1)"
  echo "ip neigh      : ${IP:-(none)}"
  for IF in $(nvram get wl_ifnames); do
    if wl -i "$IF" assoclist 2>/dev/null | grep -qi "$MAC"; then echo "wifi $IF    : associated"; fi
  done
  echo "dhcp lease    : $(grep -i "$LOWER" /var/lib/misc/dnsmasq.leases 2>/dev/null | head -1)"
  sleep "$EVERY"
done
