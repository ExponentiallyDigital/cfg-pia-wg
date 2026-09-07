#!/bin/sh
# capture-baseline.sh - snapshot the router, and show what changed since the last snapshot.
#
#   sh capture-baseline.sh factory      # immediately after a factory reset, before ANY config
#   sh capture-baseline.sh configured   # after the manual runsheet + AiMesh node
#   sh capture-baseline.sh dm           # after installing DownloadMaster
#
# WHY THE FIRST ONE MATTERS MOST
#
# `clearall.sh` claims to return the router to a clean state, but "clean" was inferred, never
# measured - it sets `vpnc_default_wan=0` and blanks `vpnc_clientlist` because those looked right,
# not because anyone had seen a factory-fresh router. A snapshot taken between the reset and the
# first configuration change is the only chance to check that, and it does not come round often.
#
# The second and third exist to isolate what DownloadMaster actually installs. The app depends on
# it for boot persistence on stock (`/opt/etc/init.d/S50downloadmaster`) and `BACKLOG.md` 1.1 wants
# to detect and deploy those binaries itself - which needs to know exactly what a real install puts
# where.
#
# NO DEPENDENCIES. A factory reset wipes /jffs, so `diff` is gone; comparison is done in awk, which
# BusyBox always has.
#
# Snapshots go to /jffs/baseline (or /tmp if /jffs is not writable yet - copy them somewhere safe
# in that case, /tmp does not survive a reboot).

set -u

LABEL="${1:-}"
PREV="${2:-}"
if [ -z "$LABEL" ]; then
    echo "usage: sh capture-baseline.sh <label> [previous-label]" >&2
    echo "  e.g. sh capture-baseline.sh factory" >&2
    exit 1
fi

if ! nvram get lan_ipaddr >/dev/null 2>&1; then
    echo "ERROR: nvram did not answer - run this on the router." >&2
    exit 1
fi

OUT=/jffs/baseline
if ! mkdir -p "$OUT" 2>/dev/null || ! touch "$OUT/.w" 2>/dev/null; then
    OUT=/tmp/baseline
    mkdir -p "$OUT" || exit 1
    echo "NOTE: /jffs is not writable, using $OUT - this does NOT survive a reboot."
fi
rm -f "$OUT/.w"
D="$OUT/$LABEL"
mkdir -p "$D" || exit 1

echo "== capturing '$LABEL' into $D =="

nvram show 2>/dev/null | sort > "$D/nvram"

# The keys this project actually touches or reads, pulled out separately so a human can read them
# without wading through two thousand lines.
{
    for k in vpnc_clientlist vpnc_dev_policy_list vpnc_dev_policy_list_tmp vpnc_default_wan \
             vpnc_unit vpnc_max_conn dhcp_staticlist custom_clientlist dhcp_start dhcp_end \
             jffs2_scripts jffs2_on lan_ipaddr lan_ifname sw_mode wgs_enable \
             cfg_pia_wg_user cfg_pia_wg_sdate cfg_pia_wg_reconfig_ok cfg_pia_wg_reconfig_fail; do
        echo "$k=$(nvram get "$k")"
    done
    for s in 1 2 3 4 5; do
        echo "wgc${s}_enable=$(nvram get "wgc${s}_enable")"
        echo "wgc${s}_desc=$(nvram get "wgc${s}_desc")"
    done
} > "$D/keys"

# Anything at all in the namespaces this app writes. On a factory-fresh router this should be
# EMPTY - if it is not, a factory reset did not remove the app's keys, which is the claim the
# README section 6 warning makes about credential exposure when a router changes hands. The
# watchdog keys are the ones that matter: wgcN_wd_smtp_pass holds an SMTP password in plaintext.
nvram show 2>/dev/null | grep -E "^(cfg_pia_wg_|wgc[1-9]_wd_|arc_test_)" | sort > "$D/ourkeys"

# Filesystem and runtime state. The DownloadMaster diff lives here more than in nvram.
{
    echo "--- wg show interfaces"; wg show interfaces 2>/dev/null
    echo "--- cru l"; cru l 2>/dev/null
    echo "--- ls /jffs"; ls -la /jffs 2>/dev/null
    echo "--- ls /jffs/scripts"; ls -la /jffs/scripts 2>/dev/null
    echo "--- ls /jffs/cfg-pia-wg"; ls -la /jffs/cfg-pia-wg 2>/dev/null
    echo "--- ls /opt"; ls -la /opt 2>/dev/null
    echo "--- ls /opt/etc/init.d"; ls -la /opt/etc/init.d 2>/dev/null
    echo "--- ls /opt/bin"; ls -la /opt/bin 2>/dev/null
    echo "--- mount"; mount 2>/dev/null
    echo "--- /jffs/nmp_cl_json.js"; ls -la /jffs/nmp_cl_json.js 2>/dev/null || echo "(absent)"
    echo "--- ip rule show"; ip rule show 2>/dev/null
    echo "--- ip route show"; ip route show 2>/dev/null
} > "$D/system" 2>&1

echo "  nvram keys : $(grep -c '=' "$D/nvram" 2>/dev/null)"
echo "  written    : $D/nvram, $D/keys, $D/ourkeys, $D/system"
echo
echo "  -- keys in this app's namespaces (should be EMPTY on a factory-fresh router) --"
if [ -s "$D/ourkeys" ]; then
    sed 's/^/    /' "$D/ourkeys"
else
    echo "    (none)"
fi

# -- comparison ----------------------------------------------------------------------------------
# Default to the previous label recorded by the last run, so the common case needs no argument.
[ -n "$PREV" ] || PREV="$(cat "$OUT/.last" 2>/dev/null)"
echo "$LABEL" > "$OUT/.last"

if [ -z "$PREV" ] || [ ! -f "$OUT/$PREV/nvram" ]; then
    echo
    echo "No previous snapshot to compare against - this is the baseline."
    exit 0
fi

echo
echo "=========================================================================="
echo " CHANGES: $PREV  ->  $LABEL"
echo "=========================================================================="

# Volatile by nature: clocks, counters, link stats, session tokens, DHCP leases. Excluded so the
# real changes are visible. Deliberately a deny-list - a key we have not seen before should show up
# rather than be silently swallowed.
NOISE='^(sys_uptime|.*_expires|.*_lease|.*_ipaddr|.*_realip|ddns_cache|ddns_ipaddr|.*_uptime|.*_status|.*_state_t|.*_sbstate_t|.*_time|.*_ts|.*_cnt|.*_count|aae_|httpd_handle|wan[0-9]_|link_|wl[0-9]|rc_service|nmp_|networkmap|cfg_device_list|asus_device_list|.*_stats|.*_seed|.*_key$|.*_hash)'

awk -F= -v noise="$NOISE" '
    NR == FNR {
        k = $1; sub(/^[^=]*=/, "", $0); old[k] = $0; seen[k] = 1; next
    }
    {
        k = $1; sub(/^[^=]*=/, "", $0); v = $0
        if (k ~ noise) next
        if (!(k in old))      { added[k] = v; na++ }
        else if (old[k] != v) { chg[k] = old[k] "  ->  " v; nc++ }
        now[k] = 1
    }
    END {
        for (k in old) if (!(k in now) && k !~ noise) { removed[k] = old[k]; nr++ }
        print ""
        print "ADDED (" na+0 ")"
        for (k in added)   print "  + " k "=" added[k]
        print ""
        print "REMOVED (" nr+0 ")"
        for (k in removed) print "  - " k "=" removed[k]
        print ""
        print "CHANGED (" nc+0 ")"
        for (k in chg)     print "  ~ " k ": " chg[k]
    }
' "$OUT/$PREV/nvram" "$D/nvram" | sort -t' ' -k2

echo
echo "--- system state, line by line (files, mounts, cron) ---"
awk '
    NR == FNR { old[$0] = 1; next }
    { if (!($0 in old)) print "  + " $0; now[$0] = 1 }
    END { for (l in old) if (!(l in now)) print "  - " l }
' "$OUT/$PREV/system" "$D/system"

echo
echo "=========================================================================="
echo "Full snapshots kept in $OUT. Compare any two later with:"
echo "  sh capture-baseline.sh <newlabel> <oldlabel>"
