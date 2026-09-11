#!/bin/sh
# verify-device-assignment.sh - settles every remaining unknown for in-app device assignment.
#
#   sh verify-device-assignment.sh
#
# One run, four phases, automatic restore. Answers two questions that decide how the feature is
# built and how it is described. See .claude/plans/plan_vpn_device_assignments.md items 9 and 10.
#
#   Q9  Is `restart_net_and_phy` really needed to apply a new DHCP reservation, or will the far
#       lighter `restart_dnsmasq` do? The WebUI uses the heavy one, which restarts the physical
#       layer: every switch port bounces, downstream routers and APs drop with everything behind
#       them, and the WAN re-leases. Measured 2026-09-06 - LAN down 20:11:41, WAN re-lease 20:11:58,
#       new public address 20:12:08. Removing a reservation is no gentler; it killed an RDP session.
#
#       The hypothesis is that the heavy call is unnecessary, because the device ALREADY HOLDS THE
#       IP through its current lease. The policy binds to a live address and should apply at once;
#       the reservation only has to matter at the NEXT renewal.
#
#   Q10 Does a per-device assignment fail CLOSED when its tunnel goes down, or fall back to the
#       plain WAN? Fail-closed was measured for "apply to all devices" (`vpnc_default_wan`) and
#       then assumed for per-device assignment. They are different mechanisms - a default route
#       versus an `ip rule` for one source address - and the assumption was never tested.
#
#       This is not a detail. Stock has no kill switch, and device assignment is the nearest thing
#       to one; that is the justification for the whole feature. If it fails OPEN, the app must say
#       so plainly rather than imply protection it does not provide.
#
# HOW IT ANSWERS THEM
#
# `ip route get <dest> from <device-ip> iif br0` asks the kernel directly how it would route a
# forwarded packet from that device. That is the authoritative answer, it needs nothing running on
# the device itself, and it works the same whether the tunnel is up or down.
#
# WHAT IT CHANGES, AND PUTS BACK
#
#   dhcp_staticlist            one record appended
#   vpnc_dev_policy_list       one record appended
#   vpnc_dev_policy_list_tmp   set to the previous list, as the WebUI does
#   the target tunnel          taken down in phase 3, brought back in phase 4
#
# Everything is backed up to /tmp/verify_da_backup first and restored in phase 4. If the script is
# interrupted, the restore commands are in /tmp/verify_da_backup/RESTORE.sh.
#
# STARTING CONDITION - all of this is checked, but set it up first and save yourself a rerun
#
#   1. A tunnel up with a working PIA config, and NO watchdog on it. A watchdog would repair the
#      tunnel during phase 3 and destroy the measurement, so use a slot you have not deployed one
#      to - creating a second slot for the purpose is the easiest route.
#   2. "Apply to all devices" must NOT point at the slot being tested.
#
#      If it does, the target already routes there and the assignment changes nothing observable,
#      so Q9 cannot be answered. Pointing at a DIFFERENT tunnel is fine - an explicit assignment
#      overrides the default - and pointing at "Internet Connection" is cleanest, because then a
#      fail-open in phase 3 lands on the WAN rather than on another tunnel, which would be a third
#      outcome the result table does not cover.
#
#   3. `vpnc_dev_policy_list` empty, or at least not mentioning the target device.
#   4. The target device: powered on, holding a lease, and with NO DHCP reservation.
#   5. The target device is NOT the machine you are typing on, NOT the one you are remoting in
#      from, and NOT plugged into either. Assigning it routes its traffic through the tunnel.
#
#   Any OTHER device assigned to that tunnel loses internet during phase 3. Expected, and brief.

set -u
BAK=/tmp/verify_da_backup
SYSLOG=/tmp/syslog.log
PROBE_DEST=1.1.1.1

if ! nvram get lan_ipaddr >/dev/null 2>&1; then
    echo "ERROR: nvram did not answer - run this on the router." >&2
    exit 1
fi

LANIF="$(nvram get lan_ifname)"
[ -n "$LANIF" ] || LANIF=br0

JQ=""
for c in /jffs/cfg-pia-wg/jq /opt/bin/jq /usr/sbin/jq /usr/bin/jq; do
    [ -x "$c" ] && JQ="$c" && break
done

# How would a packet from $1 be routed right now? Printed verbatim - the interface name in the
# output is the whole answer, and an error is itself informative (no route = fail closed).
route_from() {
    ip route get "$PROBE_DEST" from "$1" iif "$LANIF" 2>&1 | head -3
}

echo "=========================================================================="
echo " verify-device-assignment.sh"
echo "=========================================================================="
echo
echo "== current state =="
echo "lan interface        : $LANIF"
echo "dhcp_staticlist      : $(nvram get dhcp_staticlist)"
echo "vpnc_dev_policy_list : $(nvram get vpnc_dev_policy_list)"
echo "vpnc_clientlist      : $(nvram get vpnc_clientlist)"
echo "vpnc_default_wan     : $(nvram get vpnc_default_wan)"
echo "interfaces up        : $(wg show interfaces)"
echo

echo "== devices with a lease but NO reservation (the ones worth testing) =="
if [ -n "$JQ" ] && [ -f /tmp/nmp_cache.js ]; then
    RESERVED="$(nvram get dhcp_staticlist)"
    "$JQ" -r 'to_entries[] | .key + " " + (.value.ip // "-") + " " + (.value.nickName // .value.name // "-")' \
        /tmp/nmp_cache.js 2>/dev/null | while read -r mac ip name; do
        [ "$ip" = "-" ] && continue
        case "$RESERVED" in
            *"<$mac>"*) ;;
            *) echo "  $mac  $ip  $name" ;;
        esac
    done
else
    echo "  (no jq or no /tmp/nmp_cache.js - read them off the WebUI client list;"
    echo "   IP Method 'Automatic IP' means no reservation)"
fi
echo

printf 'Target MAC (uppercase, colon separated) : '; read -r MAC
printf 'Target IP  (the address it holds NOW)   : '; read -r IP
printf 'Target slot number (1-5), must be UP    : '; read -r SLOT
[ -n "$MAC" ] && [ -n "$IP" ] && [ -n "$SLOT" ] || { echo "ERROR: all three are needed." >&2; exit 1; }

case "$(nvram get dhcp_staticlist)" in
    *"<$MAC>"*)
        echo "ERROR: $MAC already has a reservation, so it does not exercise the path being" >&2
        echo "       tested. Remove it in the WebUI, or pick another device." >&2
        exit 1 ;;
esac
case "$(nvram get vpnc_dev_policy_list)" in
    *">$IP>"*)
        echo "ERROR: $IP is already in vpnc_dev_policy_list - unassign it in the WebUI first," >&2
        echo "       or this writes a duplicate record and the result is unreadable." >&2
        exit 1 ;;
esac
case " $(wg show interfaces) " in
    *" wgc$SLOT "*) ;;
    *) echo "ERROR: wgc$SLOT is not up (up now: $(wg show interfaces)). Enable it first." >&2
       exit 1 ;;
esac

# Dropbear sets SSH_CLIENT to '<source ip> <sport> <dport>'. Assigning the address you are
# connected from would route this session into the tunnel and, in phase 3, cut it off entirely.
if [ -n "${SSH_CLIENT:-}" ]; then
    SRC="$(echo "$SSH_CLIENT" | cut -d' ' -f1)"
    if [ "$SRC" = "$IP" ]; then
        echo "ERROR: $IP is the address you are connected FROM. Phase 3 would cut off this" >&2
        echo "       session and leave the router mid-test. Pick another device." >&2
        exit 1
    fi
fi

# -- resolve the two indexes this slot needs -----------------------------------------------------
# ROW is the 0-based position in vpnc_clientlist, which is what `vpnc_unit` selects.
# IDX is that record's index 6, which is what the policy list and vpnc_default_wan use.
# They are different numbers and both are needed. See plan 3.3.6.
ROW=-1
IDX=""
n=0
OLDIFS="$IFS"
IFS='
'
for rec in $(nvram get vpnc_clientlist | tr '<' '\n'); do
    rslot=$(echo "$rec" | cut -d'>' -f3)
    if [ "$rslot" = "$SLOT" ]; then
        ROW=$n
        IDX=$(echo "$rec" | cut -d'>' -f7)
    fi
    n=$((n + 1))
done
IFS="$OLDIFS"
[ -n "$IDX" ] || { echo "ERROR: wgc$SLOT has no vpnc_clientlist profile - CREATE it in the app first." >&2; exit 1; }
echo "wgc$SLOT : clientlist row (vpnc_unit) = $ROW, index 6 = $IDX"

# "Apply to all devices" only defeats the test when it points at the SAME tunnel we are assigning
# to - then the target is already routed there and the assignment changes nothing observable. An
# explicit assignment overrides the default, so any OTHER tunnel being the default is fine.
DEFWAN="$(nvram get vpnc_default_wan)"
if [ "$DEFWAN" = "$IDX" ]; then
    echo "ERROR: 'apply to all devices' is on for wgc$SLOT (vpnc_default_wan=$DEFWAN), which is the" >&2
    echo "       tunnel being assigned to. The target already routes there, so the assignment would" >&2
    echo "       make no observable difference and Q9 cannot be answered. Turn it off, or pick a" >&2
    echo "       different slot." >&2
    exit 1
fi
if [ "$DEFWAN" != "0" ] && [ -n "$DEFWAN" ]; then
    echo "NOTE: 'apply to all devices' is on for index-6 $DEFWAN, not for wgc$SLOT - fine for Q9."
    echo "      For Q10 it means phase 3 shows this device failing closed while every OTHER device"
    echo "      keeps working, which is the cleaner result anyway."
fi

# A watchdog on the target slot will fight phase 3. Taking the tunnel down is exactly the condition
# it exists to repair: within one check interval it reconfigures the slot and brings it back up,
# which destroys the measurement and leaves the router in a state the script did not intend.
#
# Build 413 made the watchdog stand down when `wgcN_enable=0`, but phase 3 uses `service stop_vpnc`
# and it is NOT established that the service clears that flag - the WebUI sets it separately. So
# this refuses rather than relies on it.
if cru l 2>/dev/null | grep -q "watchdog_wgc$SLOT "; then
    echo "ERROR: wgc$SLOT has an active watchdog. Phase 3 takes the tunnel down, which the watchdog" >&2
    echo "       would treat as an outage and repair mid-test. Use a slot with no watchdog, or" >&2
    echo "       disable this one in the app first." >&2
    exit 1
fi

# -- back up ------------------------------------------------------------------------------------
mkdir -p "$BAK" || exit 1
for v in dhcp_staticlist vpnc_dev_policy_list vpnc_dev_policy_list_tmp; do
    nvram get "$v" > "$BAK/$v"
done
{
    echo "#!/bin/sh"
    echo "# Written by verify-device-assignment.sh. Run this if the script was interrupted."
    echo "nvram set dhcp_staticlist=\"\$(cat $BAK/dhcp_staticlist)\""
    echo "nvram set vpnc_dev_policy_list=\"\$(cat $BAK/vpnc_dev_policy_list)\""
    echo "nvram set vpnc_dev_policy_list_tmp=\"\$(cat $BAK/vpnc_dev_policy_list_tmp)\""
    echo "nvram commit"
    echo "nvram set vpnc_unit=$ROW"
    echo "service restart_dnsmasq"
    echo "service restart_vpnc_dev_policy"
    echo "service restart_vpnc"
} > "$BAK/RESTORE.sh"
chmod +x "$BAK/RESTORE.sh" 2>/dev/null

OLD_DHCP="$(nvram get dhcp_staticlist)"
OLD_POL="$(nvram get vpnc_dev_policy_list)"
NEW_DHCP="$OLD_DHCP<$MAC>$IP>>"
if [ -z "$OLD_POL" ]; then NEW_POL="1>$IP>>$IDX>"; else NEW_POL="$OLD_POL<1>$IP>>$IDX>"; fi

echo
echo "== plan =="
echo "  phase 1  baseline: how is $IP routed with no assignment?"
echo "  phase 2  assign it to wgc$SLOT using ONLY restart_dnsmasq + restart_vpnc_dev_policy"
echo "  phase 3  take wgc$SLOT down, leaving the assignment - fail closed or fall back to WAN?"
echo "  phase 4  put everything back"
echo
echo "  will write dhcp_staticlist      : $NEW_DHCP"
echo "  will write vpnc_dev_policy_list : $NEW_POL"
echo "  restore script                  : $BAK/RESTORE.sh"
echo
printf 'Proceed? type yes : '; read -r OK
[ "$OK" = "yes" ] || { echo "nothing written."; exit 0; }

MARK=0
[ -f "$SYSLOG" ] && MARK="$(wc -l < "$SYSLOG")"
WAN_BEFORE="$(nvram get wan0_ipaddr)"

# ================================ PHASE 1 =======================================================
echo
echo "--- phase 1: baseline ------------------------------------------------------"
BASE_ROUTE="$(route_from "$IP")"
echo "$BASE_ROUTE" | sed 's/^/  /'
# It should leave by the WAN. Going out through the tunnel already means something else is
# routing it - a leftover policy record, or an 'apply to all devices' that slipped through.
case "$BASE_ROUTE" in
    *"wgc$SLOT"*)
        echo
        echo "  WARNING: the baseline ALREADY routes via wgc$SLOT, before anything was assigned." >&2
        echo "  Q9 cannot be answered from this state - the assignment has no visible effect to" >&2
        echo "  measure. Check vpnc_dev_policy_list and vpnc_default_wan, then rerun." >&2
        printf '  continue anyway (Q10 is still answerable)? type yes : '; read -r GO
        [ "$GO" = "yes" ] || exit 1 ;;
esac

# ================================ PHASE 2 =======================================================
echo
echo "--- phase 2: assign, light services only -----------------------------------"
nvram set dhcp_staticlist="$NEW_DHCP"
nvram set vpnc_dev_policy_list_tmp="$OLD_POL"
nvram set vpnc_dev_policy_list="$NEW_POL"
nvram commit
echo "  service restart_dnsmasq"
service restart_dnsmasq
echo "  service restart_vpnc_dev_policy"
service restart_vpnc_dev_policy

# notify_rc queues and returns immediately - neither call has finished yet. Poll, do not guess:
# the same trap that produced the watchdog deploy race in build 409.
n=0
while [ "$n" -lt 10 ]; do
    ip rule show 2>/dev/null | grep -qF "$IP" && break
    n=$((n + 1))
    sleep 2
done

Q9="light"
if ip rule show 2>/dev/null | grep -qF "$IP"; then
    echo "  ip rule appeared after the light calls alone."
else
    echo "  no ip rule yet - escalating to restart_vpnc as well."
    service restart_vpnc
    n=0
    while [ "$n" -lt 15 ]; do
        ip rule show 2>/dev/null | grep -qF "$IP" && break
        n=$((n + 1))
        sleep 2
    done
    Q9="needs_restart_vpnc"
    ip rule show 2>/dev/null | grep -qF "$IP" || Q9="failed"
fi

echo "  ip rule for $IP:"
ip rule show 2>/dev/null | grep -F "$IP" | sed 's/^/    /' || echo "    (none)"
ASSIGNED_ROUTE="$(route_from "$IP")"
echo "  routing:"
echo "$ASSIGNED_ROUTE" | sed 's/^/    /'

# ================================ PHASE 3 =======================================================
echo
echo "--- phase 3: tunnel down, assignment left in place -------------------------"
echo "  (any other device on wgc$SLOT loses internet for the next minute - expected)"
nvram set vpnc_unit="$ROW"
service stop_vpnc
n=0
while [ "$n" -lt 15 ]; do
    case " $(wg show interfaces) " in *" wgc$SLOT "*) ;; *) break ;; esac
    n=$((n + 1))
    sleep 2
done
echo "  interfaces up now: $(wg show interfaces)"
DOWN_ROUTE="$(route_from "$IP")"
echo "  routing with the tunnel down:"
echo "$DOWN_ROUTE" | sed 's/^/    /'

# ================================ PHASE 4 =======================================================
echo
echo "--- phase 4: restore -------------------------------------------------------"
nvram set dhcp_staticlist="$(cat "$BAK/dhcp_staticlist")"
nvram set vpnc_dev_policy_list="$(cat "$BAK/vpnc_dev_policy_list")"
nvram set vpnc_dev_policy_list_tmp="$(cat "$BAK/vpnc_dev_policy_list_tmp")"
nvram commit
nvram set vpnc_unit="$ROW"
service restart_dnsmasq
service restart_vpnc_dev_policy
service restart_vpnc
n=0
while [ "$n" -lt 20 ]; do
    case " $(wg show interfaces) " in *" wgc$SLOT "*) break ;; esac
    n=$((n + 1))
    sleep 2
done
echo "  interfaces up: $(wg show interfaces)"
echo "  dhcp_staticlist      : $(nvram get dhcp_staticlist)"
echo "  vpnc_dev_policy_list : $(nvram get vpnc_dev_policy_list)"

# ================================ ANSWERS =======================================================
WAN_AFTER="$(nvram get wan0_ipaddr)"
BOUNCED=no
if [ -f "$SYSLOG" ]; then
    tail -n "+$((MARK + 1))" "$SYSLOG" | grep -q "net_and_phy" && BOUNCED=yes
fi
[ "$WAN_BEFORE" = "$WAN_AFTER" ] || BOUNCED="yes (WAN address changed)"

echo
echo "=========================================================================="
echo " ANSWERS - this block is all that needs pasting back"
echo "=========================================================================="
echo
echo "Q9  minimum calls to apply an assignment : $Q9"
echo "      light              = restart_dnsmasq + restart_vpnc_dev_policy was enough"
echo "      needs_restart_vpnc = restart_vpnc was also required"
echo "      failed             = the rule never appeared; more than these calls is needed"
echo
echo "Q9  did anything bounce                  : $BOUNCED"
echo "      wan0_ipaddr before : $WAN_BEFORE"
echo "      wan0_ipaddr after  : $WAN_AFTER"
echo
echo "Q10 routing for $IP:"
echo "      unassigned      : $(echo "$BASE_ROUTE" | head -1)"
echo "      assigned, up    : $(echo "$ASSIGNED_ROUTE" | head -1)"
echo "      assigned, DOWN  : $(echo "$DOWN_ROUTE" | head -1)"
echo
echo "      If the last line names the WAN interface, per-device assignment FAILS OPEN."
echo "      If it errors or names no usable route, it FAILS CLOSED."
echo
echo "syslog during the run (net_and_phy here means the light path was not light):"
if [ -f "$SYSLOG" ]; then
    tail -n "+$((MARK + 1))" "$SYSLOG" | grep -E "net_and_phy|dnsmasq|vpnc|wan|udhcpc" | sed 's/^/  /'
fi
echo
echo "Did your own session drop, or any other device? Only you can see that."
echo "=========================================================================="
