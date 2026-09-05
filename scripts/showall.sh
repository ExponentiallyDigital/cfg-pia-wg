#!/bin/sh
# Shows everything cfg-pia-wg creates or modifies on the router: NVRAM, deployed files, cron
# entries and the watchdog's volatile state. Read-only - see clearall.sh to remove it all.

echo "== wgc (slot config + wgcN_wd_ watchdog settings) =="
nvram show 2>/dev/null | grep -E "wgc[1-9]_" | sort

echo
echo "== vpncN_ (stock runtime state, indexed by clientlist field 7) =="
nvram show 2>/dev/null | grep -E "vpnc([1-9]|1[0-6])_" | sort

echo
echo "== vpnc_ (clientlist, unit being acted on, concurrent-VPN cap) =="
nvram show 2>/dev/null | grep -E "vpnc_" | sort

echo
echo "== cfg-pia-wg globals (credentials + lifetime counters) =="
nvram show 2>/dev/null | grep -i cfg_pia | sort

echo
echo "== JFFS (Merlin only - the app turns these on; clearall.sh leaves them alone) =="
for v in jffs2_scripts jffs2_on; do
    echo "$v=$(nvram get $v)"
done

echo
echo "== wg interfaces (a tunnel listed here is UP, whatever the flags say) =="
wg show interfaces

echo
echo "== cru l (watchdog check + log rotation, per slot) =="
cru l

echo
echo "== /jffs/cfg-pia-wg (watchdog scripts, cached PIA CA, and on stock jq + mailsend-go) =="
ls -la /jffs/cfg-pia-wg 2>/dev/null || echo "  (directory does not exist)"

echo
echo "== boot persistence =="
if [ -f /jffs/scripts/services-start ]; then
    echo "-- /jffs/scripts/services-start (Merlin)"
    grep -E "watchdog_wgc|watchdog_log_rotate_wgc" /jffs/scripts/services-start 2>/dev/null || echo "  (no cfg-pia-wg lines)"
fi
if [ -f /opt/etc/init.d/S50downloadmaster ]; then
    echo "-- /opt/etc/init.d/S50downloadmaster (stock)"
    grep -E "watchdog_wgc|watchdog_log_rotate_wgc" /opt/etc/init.d/S50downloadmaster 2>/dev/null || echo "  (no cfg-pia-wg lines)"
fi

echo
echo "== /tmp watchdog state (lost on reboot) =="
ls -la /tmp/watchdog_* 2>/dev/null || echo "  (none)"
for f in /tmp/watchdog_last_ping_success_wgc[1-9] /tmp/watchdog_backoff_wgc[1-9]; do
    [ -f "$f" ] && echo "-- $f: $(tr '\n' ' ' < "$f")"
done
