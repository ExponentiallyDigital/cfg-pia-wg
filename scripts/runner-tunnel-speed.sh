#!/bin/sh
# runner-tunnel-speed.sh - does a tunnel left out of Broadcom's accelerator table run slower? (ID-393)
#
#   /bin/sh /jffs/cfg-pia-wg/runner-tunnel-speed.sh [T D ROUNDS]       T, D and ROUNDS default to 4, 3 and 3
#
# The accelerator keeps a table of the router's own addresses, 8 places on the test router, and the
# 4th and 5th WireGuard client tunnels started are left out of it (ARCHITECTURE 4.2.6). This times
# the same tunnel, T, in the table and out of it, so the table is the only difference: same tunnel,
# same server, same router. The table is full, so T gets a place only when D, a tunnel that has one,
# gives it up:
#
#   T in:   stop T and D, start T, then D     T takes D's place; D is left out
#   T out:  stop T and D, start D, then T     D takes it back; T is left out
#
# Each state is read back from the table before it is timed, and a timing taken in the wrong state is
# not counted. The states alternate in, out, out, in, in, out... so a slow minute at PIA's end can't
# pass for the table. Each timing is one 25 MB download from the router through T, and is counted
# only if T's own received-bytes counter grew by at least 20 MB while it ran.
#
# How the router's own download is sent through T: a rule for the download server's one address,
# into T's routing table (stock numbers it 10 minus the slot), added for the download and taken out
# after, as the watchdog's DNS probe does it - measured 2026-10-15, 5 MB through wgc4 this way, its
# counter up 5.3 MB. Two ways that don't work on stock, both tried: T's address as the source (the
# router routes it out of the WAN, 2026-10-14) and binding to T itself (it connects and nothing ever
# answers, 2026-10-15). The rule is priority 1001, clear of the watchdog's 1000s.
#
# Devices pinned to T or D have no internet for the half minute or so each switch takes: the
# fail-closed guard holds them. Their watchdogs are paused meanwhile and put back however it ends,
# and both tunnels are started again if it stopped them. It ends with T out and D in, as found.
# About 2 minutes a round. A second copy stops at once. Stock only; BusyBox only.

T="${1:-4}"; D="${2:-3}"; ROUNDS="${3:-3}"
case "$T$D" in *[!1-5]*|?|???*) echo "usage: /bin/sh runner-tunnel-speed.sh [T D ROUNDS], two slots from 1 to 5"; exit 2 ;; esac
case "$ROUNDS" in ''|*[!0-9]*|0) echo "usage: ROUNDS is a number from 1"; exit 2 ;; esac
[ "$T" = "$D" ] && { echo "usage: T and D must be different slots"; exit 2; }
[ "$(nvram get 3rd-party)" = merlin ] && { echo "REFUSED: stock only"; exit 2; }
BS=/bin/bs
[ -x "$BS" ] || { echo "REFUSED: no $BS on this router, so the accelerator's table can't be read"; exit 2; }
HOST=speed.cloudflare.com
URL="https://$HOST/__down?bytes=25000000"
TBL=$((10 - T))
ERRF=/tmp/runner-tunnel-speed.err
LOCK=/tmp/runner-tunnel-speed.lock
mkdir "$LOCK" 2>/dev/null || { echo "REFUSED: already running (or $LOCK left behind: rmdir it if not)"; exit 1; }

say() { echo "$(date '+%H:%M:%S') $1"; }
unit_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$1" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}'; }
idx_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$1" '$3 == s {print $7; exit}'; }
up() { ip -o link show up 2>/dev/null | grep -q " wgc$1:"; }
up2() { up "$1" && sleep 1 && up "$1"; }
down2() { ! up "$1" && sleep 1 && ! up "$1"; }
hs() { wg show "wgc$1" latest-handshakes 2>/dev/null | awk '{if ($2 > m) m = $2} END {print m + 0}'; }
addr_of() { ip -o -4 addr show "wgc$1" 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}'; }
# Found by shape, not place on the line: see runner-host-table.sh for why.
table() { "$BS" /b/e system 2>&1 | grep 'ipv4_host_address_table\[' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^0\.0\.0\.0$'; }
intable() { A="$(addr_of "$1")"; [ -n "$A" ] && table | grep -qx "$A"; }
idle() {
  i=0
  while [ -n "$(nvram get rc_service)" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  [ -z "$(nvram get rc_service)" ]
}
stop_slot() {
  idle || return 1
  nvram set vpnc_unit="$(unit_of "$1")"; service stop_vpnc
  i=0; while [ "$i" -lt 30 ] && ! down2 "$1"; do sleep 1; i=$((i + 1)); done
  down2 "$1"
}
start_slot() {
  idle || return 1
  S0="$(date +%s)"
  nvram set vpnc_unit="$(unit_of "$1")"; service restart_vpnc
  i=0; while [ "$i" -lt 45 ] && ! { up2 "$1" && [ "$(hs "$1")" -ge "$S0" ]; }; do sleep 1; i=$((i + 1)); done
  up2 "$1" && [ "$(hs "$1")" -ge "$S0" ]
}
# Puts T in the table ("in") or leaves it out ("out"). True only if the table, read back, agrees.
switch() {
  stop_slot "$T" || return 1
  stop_slot "$D" || return 1
  if [ "$1" = in ]; then start_slot "$T" && start_slot "$D" || return 1
  else start_slot "$D" && start_slot "$T" || return 1; fi
  sleep 3
  if intable "$T"; then [ "$1" = in ]; else [ "$1" = out ]; fi
}
# One timed download through T. Prints the speed in KB/s, or nothing if it didn't count.
rxb() { cat "/sys/class/net/wgc$T/statistics/rx_bytes" 2>/dev/null || echo 0; }
rule_add() { ip rule add to "$IP" iif lo lookup "$TBL" priority 1001 2>/dev/null; }
rule_del() { while ip rule del to "$IP" iif lo lookup "$TBL" priority 1001 2>/dev/null; do :; done; }
# One timed download through T. Prints the speed in KB/s, or nothing if it didn't count.
timed() {
  rule_add
  RT="$(ip route get "$IP" 2>&1 | head -1)"
  case "$RT" in
    *" dev wgc$T "*|*" dev wgc$T") ;;
    *) rule_del; say "  not counted: the route to $IP is not through wgc$T: $RT" >&2; return 0 ;;
  esac
  R0="$(rxb)"
  W="$(curl -sS -o /dev/null --max-time 90 --resolve "$HOST:443:$IP" -w '%{http_code} %{speed_download} %{size_download}' "$URL" 2>"$ERRF")"
  R1="$(rxb)"
  rule_del
  set -- $W
  if [ "$1" != 200 ] || [ "${3%.*}" -lt 20000000 ]; then
    say "  not counted: the download failed (curl said: ${W:-nothing}; $(head -1 "$ERRF" 2>/dev/null))" >&2
  elif [ $((R1 - R0)) -lt 20000000 ]; then
    say "  not counted: wgc$T received only $((R1 - R0)) bytes during a ${3%.*}-byte download, so it didn't go through wgc$T" >&2
  else
    echo $(( ${2%.*} / 1024 ))
  fi
}

# ---- preconditions ----------------------------------------------------------------------------
[ -n "$(unit_of "$T")" ] && [ -n "$(unit_of "$D")" ] || { echo "REFUSED: wgc$T or wgc$D has no vpnc_clientlist row"; rmdir "$LOCK"; exit 2; }
DEF="$(nvram get vpnc_default_wan)"
for S in "$T" "$D"; do
  if [ -n "$DEF" ] && [ "$DEF" != 0 ] && [ "$(idx_of "$S")" = "$DEF" ]; then
    echo "REFUSED: wgc$S is the default connection; stopping it would cut the internet for every device that follows it"; rmdir "$LOCK"; exit 2
  fi
  up2 "$S" && [ "$(hs "$S")" -gt 0 ] || { echo "REFUSED: wgc$S isn't up and handshaking; start it first"; rmdir "$LOCK"; exit 2; }
done
[ -n "$(table)" ] || { echo "REFUSED: the accelerator's table couldn't be read"; rmdir "$LOCK"; exit 2; }
# One address for every timing, so each download goes to the same server.
IP="$(nslookup "$HOST" 127.0.0.1 2>/dev/null | sed -n '/^Name:/,$p' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$IP" ] || { echo "REFUSED: couldn't look up $HOST"; rmdir "$LOCK"; exit 2; }
# Exactly one of the two must hold a place, or stopping both frees none for T to take.
TIN=0; DIN=0; intable "$T" && TIN=1; intable "$D" && DIN=1
if [ "$TIN$DIN" != 01 ] && [ "$TIN$DIN" != 10 ]; then
  echo "REFUSED: exactly one of wgc$T and wgc$D must be in the accelerator's table now (wgc$T in: $TIN, wgc$D in: $DIN)."
  echo "Run /bin/sh /jffs/cfg-pia-wg/runner-host-table.sh to see which tunnels are in, and pick T from those left out and D from those in."
  rmdir "$LOCK"; exit 2
fi

OLDUNIT="$(nvram get vpnc_unit)"
CRUSAVE=/tmp/runner-tunnel-speed.cru
cru l | grep -E "#watchdog_wgc($T|$D)#" > "$CRUSAVE"
# ASUS's curl writes every command line it runs to /jffs/curllst, rotating it to curllst.1 and on;
# ours leave nothing in any of them (ID-400).
curllst_clear() { for F in /jffs/curllst /jffs/curllst.[0-9]*; do [ -f "$F" ] && : > "$F"; done; return 0; }
restore() {
  rule_del
  rm -f "$ERRF"
  curllst_clear
  for S in "$T" "$D"; do up "$S" || { say "putting wgc$S back"; start_slot "$S" || say "wgc$S did NOT come back: start it in the app"; }; done
  while read -r L; do X="${L%#}"; cru a "${X##*#}" "$(X2="${X%#*}"; echo "${X2% }")"; done < "$CRUSAVE"
  nvram set vpnc_unit="$OLDUNIT"
  rm -f "$CRUSAVE"; rmdir "$LOCK" 2>/dev/null
  logger "**RUNNER-TUNNEL-SPEED END**"
}
trap restore EXIT
trap 'exit 1' INT TERM HUP
logger "**RUNNER-TUNNEL-SPEED START** wgc$T, with wgc$D, $ROUNDS rounds"
while read -r L; do X="${L%#}"; cru d "${X##*#}"; done < "$CRUSAVE"
say "timing wgc$T in and out of the accelerator's table, $ROUNDS rounds, giving way to wgc$D; downloads from $HOST at $IP"

# ---- the test ---------------------------------------------------------------------------------
INS=""; OUTS=""; BAD=0; R=1
while [ "$R" -le "$ROUNDS" ]; do
  if [ $((R % 2)) = 1 ]; then ORDER="in out"; else ORDER="out in"; fi
  for WANT in $ORDER; do
    if switch "$WANT"; then
      K="$(timed)"
      if [ -n "$K" ]; then
        say "round $R: wgc$T $WANT the table: $K KB/s"
        if [ "$WANT" = in ]; then INS="$INS $K"; else OUTS="$OUTS $K"; fi
      fi
    else
      BAD=$((BAD + 1))
      say "round $R: couldn't put wgc$T $WANT the table (read back: $(intable "$T" && echo in || echo out)); not timed"
    fi
  done
  R=$((R + 1))
done
# End as found: T out, D in.
intable "$T" && { say "putting wgc$T back out of the table, as it was"; switch out || say "couldn't: wgc$T is still in the table"; }

avg() { echo "$1" | awk '{s = 0; for (i = 1; i <= NF; i++) s += $i; if (NF) printf "%d", s / NF; else printf "none"}'; }
spread() { echo "$1" | awk '{if (!NF) {print "none"; exit} lo = $1; hi = $1; for (i = 2; i <= NF; i++) {if ($i < lo) lo = $i; if ($i > hi) hi = $i} print lo " to " hi}'; }
AI="$(avg "$INS")"; AO="$(avg "$OUTS")"
echo
echo "ANSWERS"
echo "wgc$T in the table:     average $AI KB/s, runs:${INS:- none} (range $(spread "$INS"))"
echo "wgc$T out of the table: average $AO KB/s, runs:${OUTS:- none} (range $(spread "$OUTS"))"
[ "$BAD" -gt 0 ] && echo "switches that didn't reach the intended state: $BAD (not timed)"
if [ "$AI" = none ] || [ "$AO" = none ]; then
  echo "VERDICT: none - not enough timings in one state or the other"
else
  P=$(( (AO - AI) * 100 / AI ))
  echo "out of the table vs in it: ${P}%"
  if [ "$P" -le -20 ]; then
    echo "VERDICT: SLOWER out of the table, by $((0 - P))% - more than the 20% allowed for noise"
  elif [ "$P" -ge 20 ]; then
    echo "VERDICT: faster out of the table, by $P% - not what the table could cause; likely noise at PIA's end"
  else
    echo "VERDICT: no difference beyond noise - within 20% either way"
  fi
fi
echo "Both tunnels are $(up "$T" && up "$D" && echo "up" || echo "NOT both up: check the app")."
