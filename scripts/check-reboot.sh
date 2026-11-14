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
# On Merlin, "pinned" means VPN Director sends the machine to a tunnel, by a rule of its own or a
# whole-network one: the script asks the kernel which (ID-569).
#
# Run it on a machine the app has pinned to a tunnel, on bash (Linux, WSL or Git Bash):
#   ROUTER_SSH='ssh -o ConnectTimeout=3 admin@192.168.50.1' scripts/check-reboot.sh [dry]
# ROUTER_SSH is any command that runs its one argument on the router. The router reboots once;
# `dry` runs the checks that come before the reboot, and stops.
# Nothing is changed on the router beyond the reboot itself.
#
# Output: PASS or FAIL, with the seconds that were blocked, through the tunnel and through the WAN,
# and any answer from an address that is neither, which fails.
# Exit status 0 for PASS, 1 for FAIL, 2 when it couldn't run the check.

set -u

# The verdict, from the probes in $1: each p.N holds the address that answered at second N, or
# nothing when the probe was blocked. Only the tunnel's own address ($2, read before the reboot)
# counts as the tunnel; the router's WAN address before ($3) or after ($4) the reboot is a leak; any
# other address is named and fails, because it can't be ruled out. Until 2026-11-14 every answer
# other than the old WAN address counted as the tunnel, so a leak through a WAN address the router
# got at the reboot passed, and the router's address does change at a reboot (ID-569).
# $5 is the second the new boot was seen ('' for never), $6 the last second watched.
report() {
  local d="$1" tun="$2" w1="$3" w2="$4" nb="$5" last="$6" i=0 n=0 blocked=0 tunnel=0 leaks="" other="" first="" a
  while [ "$i" -le "$last" ]; do
    if [ -f "$d/p.$i" ]; then
      n=$((n + 1)); a="$(cat "$d/p.$i")"
      if [ -z "$a" ]; then blocked=$((blocked + 1))
      elif [ "$a" = "$tun" ]; then
        tunnel=$((tunnel + 1)); [ -n "$nb" ] && [ "$i" -ge "$nb" ] && [ -z "$first" ] && first="$i"
      elif [ "$a" = "$w1" ] || [ "$a" = "$w2" ]; then leaks="$leaks ${i}s"
      else other="$other ${i}s:$a"
      fi
    fi
    i=$((i + 1))
  done
  echo "INFO $n probes in ${last}s, one a second"
  echo "INFO blocked $blocked; through the tunnel ($tun) $tunnel; through the WAN ($w1, after the reboot ${w2:-unread}) $(echo "$leaks" | wc -w); from any other address $(echo "$other" | wc -w)"
  echo "INFO router back on a new boot by ${nb:-never}s; first tunnel answer after it at ${first:-never}s"
  if [ -z "$nb" ]; then echo "FAIL REBOOT the router didn't come back on a new boot within ${last}s"; return 1; fi
  if [ -n "$leaks" ]; then echo "FAIL REBOOT this pinned device's traffic left by the WAN at:$leaks"; return 1; fi
  if [ -n "$other" ]; then echo "FAIL REBOOT answers came from an address that is neither the tunnel's nor the router's WAN, so a leak can't be ruled out:$other"; return 1; fi
  if [ -z "$first" ]; then echo "FAIL REBOOT the tunnel never carried this device's traffic again"; return 1; fi
  echo "PASS REBOOT through the reboot, this pinned device's traffic went through its tunnel or nowhere"
}
# `check-reboot.sh report DIR TUNNEL WAN_BEFORE WAN_AFTER NEWBOOT LAST`: the verdict alone, for the tests.
if [ "${1:-}" = report ]; then shift; report "$@"; exit $?; fi

: "${ROUTER_SSH:?set ROUTER_SSH to a command that runs its argument on the router}"
PROBE=https://1.1.1.1/cdn-cgi/trace
LIMIT=480   # seconds to watch at most
SETTLE=60   # seconds of tunnel answers, after the new boot, that end the watch
r() { $ROUTER_SSH "$1" 2>/dev/null | tr -d '\r'; }
probe() { curl -sk --connect-timeout 1 --max-time 2 "$PROBE" 2>/dev/null | sed -n 's/^ip=//p' | tr -d '\r'; }

WANIP="$(r 'nvram get wan0_ipaddr')"
BOOT0="$(r 'cat /proc/sys/kernel/random/boot_id')"
ME="$(r 'echo ${SSH_CLIENT%% *}')"
FW="$(r 'nvram get 3rd-party')"
if [ "$FW" = merlin ]; then
  # Merlin routes devices by VPN Director, not VPN Fusion's list, and a device can be routed by a
  # whole-network rule rather than one of its own: ask the kernel which tunnel carries it (ID-569).
  PINNED="$(r "ip route get 1.1.1.1 from $ME iif br0" | sed -n 's/.* dev \(wgc[0-9]\).*/\1/p')"
else
  PINNED="$(r "nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' -v ip='$ME' '\$1 == \"1\" && \$2 == ip {print \$4}'")"
fi
[ -n "$WANIP" ] && [ -n "$BOOT0" ] || { echo "couldn't read the router over ROUTER_SSH"; exit 2; }
[ -n "$PINNED" ] && [ "$PINNED" != 0 ] || { echo "this machine ($ME) isn't pinned to a tunnel: run it on one that is"; exit 2; }
# The control: traffic that does leave by the WAN is seen as wan0_ipaddr (no CGNAT in the way).
[ "$(r 'curl -s --max-time 8 https://api.ipify.org; for F in /jffs/curllst /jffs/curllst.[0-9]*; do [ -f "$F" ] && : > "$F"; done')" = "$WANIP" ] || { echo "the router's own traffic isn't seen as wan0_ipaddr, so a leak couldn't be told apart; not checked"; exit 2; }
BEFORE="$(probe)"
[ -n "$BEFORE" ] && [ "$BEFORE" != "$WANIP" ] || { echo "before the reboot, this machine's traffic doesn't come from a tunnel (got '${BEFORE:-nothing}'); nothing to check"; exit 2; }
if [ "$FW" = merlin ]; then HOW="Merlin, routed through $PINNED"; else HOW="VPN Fusion profile $PINNED"; fi
echo "== check-reboot $(date '+%Y-%m-%d %H:%M:%S'): pinned ($HOW); the tunnel answers before the reboot, and the WAN control holds"
[ "${1:-}" = dry ] && { echo "dry: stopping before the reboot"; exit 0; }

r 'reboot' >/dev/null &
# One probe starts every second, in the background, each writing its answer to its own file, so a
# blocked probe (up to 2 s) or an SSH call to a router that is down can't stretch the gaps between
# samples. The boot check runs the same way, every 10 s, with a time limit of its own.
PD="$(mktemp -d)"; trap 'rm -rf "$PD"' EXIT
sample() { probe > "$PD/p.$1"; }
bootcheck() { B="$(timeout 8 $ROUTER_SSH 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r')"; [ -n "$B" ] && [ "$B" != "$BOOT0" ] && echo "$1" > "$PD/newboot"; }
T0="$(date +%s)"; S=0; NEWBOOT=""; RUN=0; LAST=-1
while [ "$S" -lt "$LIMIT" ]; do
  S=$(( $(date +%s) - T0 ))
  if [ "$S" -gt "$LAST" ]; then
    LAST="$S"
    sample "$S" &
    [ -z "$NEWBOOT" ] && [ "$S" -ge 30 ] && [ $((S % 10)) -eq 0 ] && bootcheck "$S" &
  fi
  [ -z "$NEWBOOT" ] && [ -f "$PD/newboot" ] && NEWBOOT="$(cat "$PD/newboot")"
  # Settled once, after the new boot, the tunnel has answered SETTLE probes in a row. Read 4 s
  # behind, so every probe counted has finished.
  K=$((S - 4))
  if [ -n "$NEWBOOT" ] && [ "$K" -ge "$NEWBOOT" ] && [ -f "$PD/p.$K" ] && [ ! -f "$PD/seen.$K" ]; then
    : > "$PD/seen.$K"
    [ "$(cat "$PD/p.$K")" = "$BEFORE" ] && RUN=$((RUN + 1)) || RUN=0
    [ "$RUN" -ge "$SETTLE" ] && break
  fi
  sleep 0.2
done
sleep 4; wait
WANIP2="$(r 'nvram get wan0_ipaddr')"
if [ "$FW" = merlin ]; then
  echo "INFO Merlin's kill switch rules now: $(r 'ip rule show | grep -c prohibit')"
else
  echo "INFO the guard now: $(r '/jffs/cfg-pia-wg/guard.sh' | grep -o 'guarded [0-9]* of [0-9]*')"
fi
report "$PD" "$BEFORE" "$WANIP" "$WANIP2" "$NEWBOOT" "$S"
