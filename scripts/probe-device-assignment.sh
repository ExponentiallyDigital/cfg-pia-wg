#!/bin/sh
# probe-device-assignment.sh - find where stock VPN Fusion stores a device-to-VPN binding.
#
#   ./probe-device-assignment.sh            # walks you through it, one WebUI action at a time
#
# WHY
#
# `vpnc_default_wan` is only the DEFAULT for unassigned devices, and `custom_clientlist` is the
# device name and icon list - none of its nine indexes is a VPN. So the per-device binding lives in
# a key we have not identified, and until we have it there is no data model for the feature. See
# .claude/plans/plan_vpn_device_assignments.md phase 0.
#
# HOW IT WORKS
#
# Snapshots all of NVRAM either side of each WebUI action, then diffs. Two of the steps deliberately
# change NOTHING relevant - one leaves the router alone entirely, the other disables and re-enables
# a tunnel without touching any assignment. Every key that moves in those two is noise, and the
# summary at the end suppresses it. What is left should be the assignment itself.
#
# BEFORE YOU START
#
#   - wgc1 and wgc5 both created and enabled in the app.
#   - Pick three devices. Do NOT pick the machine you are typing on, the one you are remoting in
#     from, or anything plugged into either - assigning a device routes its internet traffic
#     through the tunnel, and a tunnel that is down takes it offline. LAN access is unaffected.
#   - Nothing here is written to the repo. The device names you type stay on the router.

set -u
OUT=/tmp/probe
SYSLOG=/tmp/syslog.log

if ! nvram get lan_ipaddr >/dev/null 2>&1; then
    echo "ERROR: nvram did not answer - run this on the router." >&2
    exit 1
fi
mkdir -p "$OUT" || exit 1

# Stock has no diff. If you had to install one it is probably beside the app's other binaries.
if diff /dev/null /dev/null >/dev/null 2>&1; then
    DIFF=diff
elif [ -x /jffs/cfg-pia-wg/diff ]; then
    DIFF=/jffs/cfg-pia-wg/diff
else
    echo "ERROR: no diff found, and none at /jffs/cfg-pia-wg/diff." >&2
    exit 1
fi
echo "using diff: $DIFF"

echo "Three devices are needed. Names are only used to remind you what to click."
printf 'Device A - already named in the router, safe to route via a VPN : '; read -r DEV_A
printf 'Device B - a second safe device, also already named             : '; read -r DEV_B
printf 'Device C - a device the router has NOT named                    : '; read -r DEV_C
[ -n "$DEV_A" ] && [ -n "$DEV_B" ] && [ -n "$DEV_C" ] || { echo "ERROR: all three are needed." >&2; exit 1; }

# The persistent client list is snapshotted too: an assignment might be recorded there rather
# than in NVRAM, and it is the only place that remembers a device which is switched off.
NMP=/jffs/nmp_cl_json.js
# The installed diff may speak classic (< >) or unified (- +); this router speaks unified, and
# a classic-only parser reported every step as "no findings". Both are handled.
changed_lines() { grep -E '^([<>]|[-+])' "$1" 2>/dev/null | grep -vcE '^(---|\+\+\+|@@)' ; }
key_of() { echo "$1" | sed -n 's/^[<>+-] *\([A-Za-z0-9_]*\)=.*/\1/p'; }

snap() {
    nvram show 2>/dev/null | sort > "$OUT/nv.$1"
    if [ -f "$NMP" ]; then cp "$NMP" "$OUT/nmp.$1"; else : > "$OUT/nmp.$1"; fi
}
logmark() { [ -f "$SYSLOG" ] && wc -l < "$SYSLOG" || echo 0; }

# Runs one step: snapshot, prompt, snapshot, diff, and capture whatever rc_service said meanwhile.
step() {
    id="$1"; shift
    wait_secs=0
    if [ "$1" = "--wait" ]; then wait_secs="$2"; shift 2; fi
    echo
    echo "--- step $id ---------------------------------------------------------"
    echo "  $*"
    snap "before$id"
    mark="$(logmark)"
    if [ "$wait_secs" -gt 0 ]; then
        # An unattended wait, so clocks and counters certainly move. Pressing Enter straight away
        # would leave them out of the noise set, and they would then surface as fake findings.
        echo "  nothing to do - waiting ${wait_secs}s."
        sleep "$wait_secs"
    else
        printf '  press Enter when the WebUI says it has applied... '
        read -r _
    fi
    snap "after$id"
    "$DIFF" "$OUT/nv.before$id" "$OUT/nv.after$id" > "$OUT/diff$id"
    "$DIFF" "$OUT/nmp.before$id" "$OUT/nmp.after$id" > "$OUT/nmpdiff$id"
    tail -n "+$((mark + 1))" "$SYSLOG" 2>/dev/null | grep 'rc_service' > "$OUT/svc$id"
    echo "  captured: $(changed_lines "$OUT/diff$id") changed lines, $(grep -c . "$OUT/svc$id") service calls"
}

step 0 --wait 60 "CONTROL - change nothing at all. This one runs itself."
step 1 "CONTROL - disable wgc5, then enable it again. Assign NOTHING."
step 2 "Disable wgc5, assign $DEV_A to it, enable wgc5."
step 3 "Disable wgc5, assign $DEV_B to it as well (both devices on wgc5), enable wgc5."
step 4 "Disable wgc1 and wgc5, move $DEV_A from wgc5 to wgc1, enable both."
step 5 "Disable wgc5, unassign $DEV_B completely, enable wgc5."
step 6 "Turn ON 'apply to all devices' for wgc1."
step 7 "Turn OFF 'apply to all devices' for wgc1."
step 8 "Disable wgc5, assign $DEV_C to it - the device the router has not named - enable wgc5."
echo
echo "  Step 9 is optional. /jffs/nmp_cl_json.js is already known to remember offline devices"
echo "  (it carries an online 0/1 flag), so this only checks whether an ASSIGNMENT survives the"
echo "  device going away. Skip it with Enter if you would rather not power anything off."
step 9 "OPTIONAL - press Enter to skip. Power OFF $DEV_C, wait ~30s, and note whether VPN Fusion still lists it and keeps its assignment."

# Keys that moved in either control step are noise: clocks, counters, and the enable/disable churn.
sed -n 's/^[<>+-] *\([A-Za-z0-9_]*\)=.*/\1/p' "$OUT/diff0" "$OUT/diff1" 2>/dev/null | sort -u > "$OUT/noise"

echo
echo "=== SUMMARY === noise keys suppressed: $(grep -c . "$OUT/noise")"
for i in 2 3 4 5 6 7 8 9; do
    echo
    echo "--- step $i ---"
    found=0
    while IFS= read -r line; do
        case "$line" in
            '--- '*|'+++ '*|'@@'*) continue ;;                  # diff furniture, either dialect
            '< '*|'> '*|'-'*|'+'*) ;;
            *) continue ;;
        esac
        key="$(key_of "$line")"
        if [ -z "$key" ] || ! grep -qx "$key" "$OUT/noise"; then
            echo "  $line"
            found=1
        fi
    done < "$OUT/diff$i"
    [ "$found" = 1 ] || echo "  (nothing beyond the control keys)"
    [ -s "$OUT/svc$i" ] && sed 's/^/  svc: /' "$OUT/svc$i"
    # Expected to churn on online/conn_ts alone, so only its presence is reported here.
    [ -s "$OUT/nmpdiff$i" ] && echo "  nmp_cl_json.js changed ($OUT/nmpdiff$i)"
done

echo
echo "Full snapshots, diffs and service calls are in $OUT/."
echo "Send back:  tar -cf - $OUT/diff* $OUT/nmpdiff* $OUT/svc* $OUT/noise | gzip | base64"
echo "Or just paste the SUMMARY above - it is the part that matters."
