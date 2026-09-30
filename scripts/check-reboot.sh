#!/bin/bash
# check-reboot.sh - watches, from a pinned device, whether its traffic leaves by the WAN while the
# router reboots (ID-344).
#
# The guard's rules live in the kernel, so a reboot clears them, and the boot hook that puts them
# back runs late: /opt mounts well after the WAN is up. Syslog times can't say what a device's
# traffic did in between. This asks the device itself: once a second, from the moment the reboot
# is sent until the tunnel has carried traffic for a while, it fetches Cloudflare's trace page by IP
# address (no DNS involved) and records which public address it came from. An answer from the
# router's WAN address is a leak; the tunnel's address, or no answer, is the claim holding.
#
# Run it on a machine the app has pinned to a tunnel, on bash (Linux, WSL or Git Bash):
#   ROUTER_SSH='ssh admin@192.168.50.1' scripts/check-reboot.sh [dry]
# ROUTER_SSH is any command that runs its one argument on the router. The router reboots once;
# `dry` runs the checks that come before the reboot, and stops.
# Nothing is changed on the router beyond the reboot itself.
#
# Output: PASS or FAIL, with the seconds that were blocked, through the tunnel and through the WAN.
# Exit status 0 for PASS, 1 for FAIL, 2 when it couldn't run the check.

set -u
: "${ROUTER_SSH:?set ROUTER_SSH to a command that runs its argument on the router}"
PROBE=https://1.1.1.1/cdn-cgi/trace
LIMIT=480   # seconds to watch at most
SETTLE=60   # seconds of tunnel answers, after the new boot, that end the watch
r() { $ROUTER_SSH "$1" 2>/dev/null | tr -d '\r'; }
probe() { curl -sk --connect-timeout 2 --max-time 3 "$PROBE" 2>/dev/null | sed -n 's/^ip=//p' | tr -d '\r'; }

WANIP="$(r 'nvram get wan0_ipaddr')"
BOOT0="$(r 'cat /proc/sys/kernel/random/boot_id')"
ME="$(r 'echo ${SSH_CLIENT%% *}')"
PINNED="$(r "nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' -v ip='$ME' '\$1 == \"1\" && \$2 == ip {print \$4}'")"
[ -n "$WANIP" ] && [ -n "$BOOT0" ] || { echo "couldn't read the router over ROUTER_SSH"; exit 2; }
[ -n "$PINNED" ] && [ "$PINNED" != 0 ] || { echo "this machine ($ME) isn't pinned to a tunnel: run it on one that is"; exit 2; }
# The control: traffic that does leave by the WAN is seen as wan0_ipaddr (no CGNAT in the way).
[ "$(r 'curl -s --max-time 8 https://api.ipify.org')" = "$WANIP" ] || { echo "the router's own traffic isn't seen as wan0_ipaddr, so a leak couldn't be told apart; not checked"; exit 2; }
BEFORE="$(probe)"
[ -n "$BEFORE" ] && [ "$BEFORE" != "$WANIP" ] || { echo "before the reboot, this machine's traffic doesn't come from a tunnel (got '${BEFORE:-nothing}'); nothing to check"; exit 2; }
echo "== check-reboot $(date '+%Y-%m-%d %H:%M:%S'): pinned (VPN Fusion profile $PINNED); the tunnel answers before the reboot, and the WAN control holds"
[ "${1:-}" = dry ] && { echo "dry: stopping before the reboot"; exit 0; }

r 'reboot' >/dev/null &
T0="$(date +%s)"; BLOCKED=0; TUNNEL=0; LEAKS=""; RUN=0; NEWBOOT=""; FIRST=""
while :; do
  NOW="$(date +%s)"; S=$((NOW - T0))
  [ "$S" -ge "$LIMIT" ] && break
  A="$(probe)"
  if [ -z "$A" ]; then BLOCKED=$((BLOCKED + 1)); RUN=0
  elif [ "$A" = "$WANIP" ]; then LEAKS="$LEAKS ${S}s"; RUN=0
  else TUNNEL=$((TUNNEL + 1)); RUN=$((RUN + 1)); [ -n "$NEWBOOT" ] && [ -z "$FIRST" ] && FIRST="$S"
  fi
  # Once the router is back on a new boot and the tunnel has carried traffic for SETTLE seconds.
  if [ -z "$NEWBOOT" ] && [ "$S" -ge 30 ] && [ $((S % 10)) -eq 0 ]; then
    B="$(r 'cat /proc/sys/kernel/random/boot_id')"; [ -n "$B" ] && [ "$B" != "$BOOT0" ] && NEWBOOT="$S"
  fi
  [ -n "$NEWBOOT" ] && [ "$RUN" -ge "$SETTLE" ] && break
  W=$(( $(date +%s) - NOW )); [ "$W" -lt 1 ] && sleep 1
done

echo "INFO watched ${S}s: blocked ${BLOCKED} probes, through the tunnel ${TUNNEL}, through the WAN $(echo "$LEAKS" | wc -w)"
echo "INFO router back on a new boot by ${NEWBOOT:-never}s; first tunnel answer after it at ${FIRST:-never}s"
echo "INFO the guard now: $(r '/jffs/cfg-pia-wg/guard.sh' | grep -o 'guarded [0-9]* of [0-9]*')"
if [ -z "$NEWBOOT" ]; then echo "FAIL REBOOT the router didn't come back on a new boot within ${LIMIT}s"; exit 1; fi
if [ -n "$LEAKS" ]; then echo "FAIL REBOOT this pinned device's traffic left by the WAN at:$LEAKS"; exit 1; fi
if [ -z "$FIRST" ]; then echo "FAIL REBOOT the tunnel never carried this device's traffic again"; exit 1; fi
echo "PASS REBOOT through the reboot, this pinned device's traffic went through its tunnel or nowhere"
