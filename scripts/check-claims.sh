#!/bin/sh
# check-claims.sh - proves, on the router, what cfg-pia-wg claims to protect (ID-345).
#
# Every check breaks the protected path on purpose, or asks the kernel where traffic really goes,
# and expects the protection to hold. A happy path proves nothing about a protection: the
# watchdog's "encrypted" lookups passed every test for two weeks while ASUS's curl ignored
# --doh-url, because a download over ordinary DNS succeeds exactly like one over DoH.
#
# Run it as `/bin/sh /jffs/check-claims.sh [dry|quick|full]`, never `sh ...`: over SSH, stock's PATH
# finds /usr/sbin/sh first, and that is a Broadcom memory tool, not the shell.
#
#   dry    prints what it would change, changes nothing, runs the read-only checks
#   quick  the read-only checks, a rule wipe the guard must repair, and one tunnel stopped and
#          put back; one PIA login at most. About 3 minutes.
#   full   quick, then each DNS setup below applied in turn, each proved by a real rebuild of the
#          first watchdog's tunnel; PIA logins 30 s apart. About 15 minutes; the internet drops for
#          a few seconds at each DNS change.
#
# DNS setups (full): the router's own DNS servers the same as the slot's, with DNS-over-TLS off and
# on; different from the slot's; from the ISP; and the watchdog's DoH server dead, and unset. Each
# is checked applied (by reading /etc/resolv.conf and /tmp/resolv.dnsmasq) before it is tested.
#
# Safe by construction: every NVRAM key it touches is saved to /jffs/check-claims.restore first,
# a trap puts them back on any exit, and `/bin/sh /jffs/check-claims.restore` does it by hand if the
# script itself was killed. Watchdog and guard schedules are paused while it runs, and put back.
# Stock only. BusyBox only: no seq, od, hexdump, xxd, base64, timeout, command or logread.
#
# Output: one line per check, `PASS <id> <what>`, `FAIL <id> <what>: <found>` or `INFO <id> <what>`,
# then a summary; the exit status is the number of failures. Nothing secret is printed.

MODE="${1:-quick}"
D=/jffs/cfg-pia-wg
RESTORE=/jffs/check-claims.restore
CRUSAVE=/tmp/check-claims.cru
LOG=/tmp/check-claims.log
PASSN=0; FAILN=0
case "$MODE" in dry|quick|full) ;; *) echo "usage: /bin/sh check-claims.sh [dry|quick|full]"; exit 2 ;; esac

pass() { PASSN=$((PASSN + 1)); echo "PASS $1 $2"; }
fail() { FAILN=$((FAILN + 1)); echo "FAIL $1 $2: $3"; }
info() { echo "INFO $1 $2"; }
# Runs "$@" for at most $T seconds; output in $LOG, status in RC (143 if it was stopped).
bounded() {
  "$@" > "$LOG" 2>&1 &
  BP=$!; BI=0
  while kill -0 "$BP" 2>/dev/null && [ "$BI" -lt "$T" ]; do sleep 1; BI=$((BI + 1)); done
  if kill -0 "$BP" 2>/dev/null; then kill "$BP" 2>/dev/null; wait "$BP" 2>/dev/null; RC=143; else wait "$BP"; RC=$?; fi
}
[ "$(nvram get 3rd-party)" = "merlin" ] && { echo "Stock only: this router runs Merlin."; exit 2; }
[ -x "$D/guard.sh" ] || { echo "No $D/guard.sh: deploy a watchdog or APPLY in DEVICES first."; exit 2; }

# ---- snapshot and restore --------------------------------------------------------------------
KEYS="wan0_dns1_x wan0_dns2_x wan0_dnsenable_x dnspriv_enable vpnc_unit"
if [ "$MODE" != dry ]; then
  : > "$RESTORE"
  for K in $KEYS; do printf 'nvram set %s=%s\n' "$K" "'$(nvram get "$K")'" >> "$RESTORE"; done
  # restart_wan_if is what applies a DNS Server change; the hand restore always runs it.
  printf 'nvram commit\nservice "restart_wan_if 0"\nsleep 10\n' >> "$RESTORE"
  cru l | grep -E '#(watchdog_|cfg_pia_wg_guard)' > "$CRUSAVE"
  while read -r L; do X="${L%#}"; printf 'cru a %s "%s"\n' "${X##*#}" "$(X2="${X%#*}"; echo "${X2% }")" >> "$RESTORE"; done < "$CRUSAVE"
fi
RESTORED=""
restore() {
  [ -n "$RESTORED" ] || [ "$MODE" = dry ] && return 0
  RESTORED=1
  echo "== restoring"
  # The WAN restart only when the DNS settings were changed: quick mode leaves them alone.
  if [ -n "$DNSCHANGED" ]; then /bin/sh "$RESTORE" >/dev/null 2>&1; else grep -v restart_wan_if "$RESTORE" > "$RESTORE.q"; /bin/sh "$RESTORE.q" >/dev/null 2>&1; rm -f "$RESTORE.q"; fi
  i=0; while [ "$i" -lt 30 ] && ! nslookup example.com 127.0.0.1 >/dev/null 2>&1; do sleep 2; i=$((i + 1)); done
  for IF in $(nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' '$2 == "WireGuard" && $6 == "1" {print "wgc" $3}'); do
    ip -o link show up | grep -q " $IF:" && [ -n "$(wg show "$IF" latest-handshakes | awk '$2 > 0')" ] && continue
    U="$(nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="${IF#wgc}" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}')"
    nvram set vpnc_unit="$U"; service restart_vpnc; sleep 5
  done
  "$D/guard.sh" >/dev/null 2>&1
  rm -f "$RESTORE" "$CRUSAVE" /tmp/check-claims-wd.sh
  echo "== restored: $(cru l | grep -cE '#(watchdog_|cfg_pia_wg_guard)') schedules, guard $("$D/guard.sh" 2>/dev/null | grep -o 'guarded [0-9]* of [0-9]*')"
}
trap restore EXIT INT TERM
WAN="$(nvram get wan0_ifname)"

logger "**CHECK-CLAIMS START** $MODE"
echo "== check-claims $MODE, $(date '+%Y-%m-%d %H:%M:%S')"

# ---- 1. TLS: curl refuses bad certificates, and honours --cacert --------------------------------
T=20
bounded curl -s -o /dev/null --max-time 15 https://example.com/
[ "$RC" = 0 ] && pass TLS-0 "control: a good certificate is accepted" || fail TLS-0 "control: a good certificate is accepted" "rc=$RC"
for U in self-signed expired wrong.host; do
  bounded curl -s -o /dev/null --max-time 15 "https://$U.badssl.com/"
  # 28 and 7 are "no answer", not a verdict on the certificate: one more try, then say so.
  case "$RC" in 7|28) sleep 3; bounded curl -s -o /dev/null --max-time 15 "https://$U.badssl.com/" ;; esac
  case "$RC" in
    51|60) pass "TLS-$U" "curl refuses a $U certificate" ;;
    7|28) info "TLS-$U" "badssl.com did not answer (rc=$RC); not checked" ;;
    *) fail "TLS-$U" "curl refuses a $U certificate" "rc=$RC" ;;
  esac
done
if [ -f "$D/pia_ca.rsa.4096.crt" ]; then
  bounded curl -s -o /dev/null --max-time 15 --cacert "$D/pia_ca.rsa.4096.crt" https://www.privateinternetaccess.com/
  case "$RC" in 51|60) pass TLS-pin "--cacert holds addKey to PIA's CA: PIA's website is refused" ;; *) fail TLS-pin "--cacert holds addKey to PIA's CA" "rc=$RC" ;; esac
else
  info TLS-pin "no cached PIA CA yet; skipped"
fi
# The watchdog's TLS floor: --tlsv1.2 refuses a server that offers only TLS 1.1.
bounded curl -s -o /dev/null --max-time 15 --tlsv1.2 https://tls-v1-1.badssl.com:1011/
case "$RC" in
  0) fail TLS-floor "--tlsv1.2 refuses a TLS 1.1 server" "it connected" ;;
  7|28) info TLS-floor "tls-v1-1.badssl.com did not answer (rc=$RC); not checked" ;;
  *) pass TLS-floor "--tlsv1.2 refuses a TLS 1.1 server (rc=$RC)" ;;
esac
# The platform fact the watchdog's own DoH exists for. INFO, not PASS: it is ASUS's behaviour.
bounded curl -s -o /dev/null --max-time 15 --doh-url https://nothing.invalid/dns-query --resolve nothing.invalid:443:127.0.0.1 https://example.com/
[ "$RC" = 0 ] && info DOH-0 "curl still ignores --doh-url (a dead DoH server made no difference)" || info DOH-0 "curl now honours --doh-url (rc=$RC): the watchdog's own lookups are still what it uses"

# ---- 2. Mail: certificate names are checked ----------------------------------------------------
M="$D/mailsend-go"
SH="$(nvram get wgc1_wd_smtp_server)"; SH="${SH%%:*}"; [ -n "$SH" ] || SH=smtp.gmail.com
SIP="$(nslookup "$SH" 2>/dev/null | awk '/^Address/ && $3 ~ /^[0-9.]+$/ {print $3}' | tail -1)"
if [ -x "$M" ] && [ -n "$SIP" ]; then
  T=25
  bounded "$M" -ssl -verifyCert -smtp "$SIP" -port 465 -f check@example.com -t check@example.com -sub check body -msg check auth -user check -pass check
  grep -q x509 "$LOG" && pass MAIL-name "mailsend-go -verifyCert refuses a certificate for the wrong name" || fail MAIL-name "mailsend-go -verifyCert refuses a certificate for the wrong name" "$(head -c 100 "$LOG")"
  bounded "$M" -ssl -smtp "$SIP" -port 465 -f check@example.com -t check@example.com -sub check body -msg check auth -user check -pass check
  grep -q 535 "$LOG" && pass MAIL-0 "control: without -verifyCert the same connection reaches the login" || info MAIL-0 "control did not reach the login: $(head -c 100 "$LOG")"
else
  info MAIL-name "no mailsend-go or SMTP address; skipped"
fi
for S in "$D"/watchdog_wgc*.sh; do
  [ -f "$S" ] || continue
  grep -q -- '-verifyCert' "$S" && pass "MAIL-script" "$(basename "$S") sends with -verifyCert" || fail "MAIL-script" "$(basename "$S") sends with -verifyCert" "missing"
done

# ---- 3. The guard, per pinned device, from the kernel -------------------------------------------
pins() { nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' '$1=="1" && $2!="" && $4!="" && $4!="0" {print $2">"$4}'; }
slot_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v t="$1" '$7 == t {print $3; exit}'; }
wan_routes() { ip route show table "$1" | awk '$1 != "default" && $0 !~ / dev (wgc|br|lo|wgs)[0-9]* / {print $1}'; }
# Its own variable names throughout: shell variables are global, and reusing IP here once pointed
# the caller's repair check at the wrong device.
guard_check() {
  tag="$1"; GN=0; BAD=""
  for GE in $(pins); do
    GIP="${GE%>*}"; GTB="${GE#*>}"; GN=$((GN + 1)); GSL="$(slot_of "$GTB")"
    [ -n "$GSL" ] || continue
    [ "$(ip rule show | grep -c "^90:.*from $GIP lookup $GTB suppress_prefixlength 0")" = 1 ] || BAD="$BAD $GIP:no90"
    [ "$(ip rule show | grep -c "^91:.*from $GIP blackhole")" = 1 ] || BAD="$BAD $GIP:no91"
    UPIF="$(ip -o link show up | grep -c " wgc$GSL:")"
    for GX in 1.1.1.1 $(wan_routes "$GTB"); do
      GX1="${GX%/*}"
      # A subnet's own address is a broadcast address the kernel answers from its local table
      # before any rule, so ask about a host inside it instead: the network address plus two.
      case "$GX" in */*) GL="${GX1##*.}"; GX1="${GX1%.*}.$((GL + 2))" ;; esac
      GR="$(ip route get "$GX1" from "$GIP" iif br0 2>&1 | head -1)"
      case "$GR" in
        *" dev wgc$GSL"*) [ "$UPIF" = 1 ] || BAD="$BAD $GIP>$GX1:via-down-wgc$GSL" ;;
        *RTNETLINK*|*unreachable*|*prohibit*|*blackhole*) [ "$UPIF" = 0 ] || BAD="$BAD $GIP>$GX1:blocked-while-up" ;;
        *) BAD="$BAD $GIP>$GX1:WAN($GR)" ;;
      esac
    done
  done
  N="$GN"
  if [ "$2" = expect-broken ]; then
    # The negative control: with a rule removed on purpose, this check must see it.
    [ -n "$BAD" ] && pass "GUARD-$tag" "the check sees a guard broken on purpose: $(echo "$BAD" | cut -c1-80)" || fail "GUARD-$tag" "the check sees a broken guard" "it saw nothing wrong"
    return
  fi
  [ -z "$BAD" ] && pass "GUARD-$tag" "$N pinned device(s): rules held, every address through the tunnel or refused" || fail "GUARD-$tag" "the guard" "$(echo "$BAD" | cut -c1-300)"
}
guard_check now
if [ -n "$(pins)" ]; then
  cru l | grep -q '#cfg_pia_wg_guard#' && pass GUARD-cron "the guard runs every minute from cron" || fail GUARD-cron "the guard runs every minute from cron" "no cfg_pia_wg_guard entry"
  grep -q 'cru a cfg_pia_wg_guard' /opt/etc/init.d/S50downloadmaster 2>/dev/null && grep -q 'guard.sh' /opt/etc/init.d/S50downloadmaster && pass GUARD-boot "the boot hook puts the guard and its cron back" || fail GUARD-boot "the boot hook" "S50downloadmaster lacks the guard"
fi
# The pinned devices' DNS redirects, routed from the devices.
iptables -t nat -S VPN_FUSION 2>/dev/null | awk '{s=""; d=""; for (i = 1; i < NF; i++) {if ($i == "-s") s = $(i + 1); if ($i == "--to-destination") d = $(i + 1)} sub("/32", "", s); if (s != "" && d != "") print s, d}' > /tmp/check-claims.dnat
LEAK=""
while read -r S DD; do
  case "$(ip route get "$DD" from "$S" iif br0 2>&1 | head -1)" in *" dev wgc"*|*RTNETLINK*|*unreachable*|*prohibit*) ;; *) LEAK="$LEAK $S>$DD" ;; esac
done < /tmp/check-claims.dnat
rm -f /tmp/check-claims.dnat
[ -z "$LEAK" ] && pass DNS-pinned "pinned devices' redirected DNS goes through their tunnel, or nowhere" || fail DNS-pinned "pinned devices' DNS" "$LEAK"

# ---- 4. Secrets on flash and in the log -------------------------------------------------------
PW="$(nvram get cfg_pia_wg_password)"; U="$(nvram get cfg_pia_wg_user)"
[ -n "$PW" ] && { [ "$(grep -cF -- "$PW" /jffs/curllst 2>/dev/null)" = 0 ] && pass SECRET-curllst "the PIA password is not in /jffs/curllst" || fail SECRET-curllst "the PIA password is in /jffs/curllst" "present"; }
[ -n "$U" ] && { [ "$(grep -cF -- "Requesting PIA token for user $U" /tmp/syslog.log 2>/dev/null)" = 0 ] && pass SECRET-syslog "the watchdog logs no PIA user" || info SECRET-syslog "an older watchdog run logged the PIA user"; }

[ "$MODE" = dry ] && { info DRY "stopping before anything is changed: quick adds a rule wipe and a tunnel stop, full adds the DNS setups"; exit "$FAILN"; }

# From here on the router is changed, and put back by the trap.
while read -r L; do X="${L%#}"; cru d "${X##*#}"; done < "$CRUSAVE"

# ---- 4b. DNS-over-TLS: a lookup through the router sends no plain DNS out of the WAN -------------
# A counting rule (it only counts, and is removed straight after) sees every port-53 packet the
# router itself sends out of the WAN. The control: a plain query straight to a public server must
# be counted, or the rule would prove nothing.
if [ "$(nvram get dnspriv_enable)" = 1 ]; then
  iptables -I OUTPUT -o "$WAN" -p udp --dport 53 -m comment --comment cfgcheck53 -j RETURN 2>/dev/null ||
    iptables -I OUTPUT -o "$WAN" -p udp --dport 53 -j RETURN
  C0="$(iptables -vxnL OUTPUT | awk 'NR > 2 && $3 == "RETURN" && /dpt:53/ {print $1; exit}')"
  nslookup "cfg-check-$$-$(date +%s).example.com" 127.0.0.1 >/dev/null 2>&1
  nslookup "cfg-check2-$$-$(date +%s).example.org" 127.0.0.1 >/dev/null 2>&1
  C1="$(iptables -vxnL OUTPUT | awk 'NR > 2 && $3 == "RETURN" && /dpt:53/ {print $1; exit}')"
  nslookup "cfg-check3-$$.example.net" 198.51.100.53 >/dev/null 2>&1 &
  sleep 3; kill $! 2>/dev/null
  C2="$(iptables -vxnL OUTPUT | awk 'NR > 2 && $3 == "RETURN" && /dpt:53/ {print $1; exit}')"
  iptables -D OUTPUT -o "$WAN" -p udp --dport 53 -m comment --comment cfgcheck53 -j RETURN 2>/dev/null ||
    iptables -D OUTPUT -o "$WAN" -p udp --dport 53 -j RETURN
  if [ "$C2" -le "$C1" ]; then
    fail DNS-DoT "the counting rule sees plain DNS" "a direct query wasn't counted ($C1 -> $C2), so the check proves nothing"
  elif [ "$C1" = "$C0" ]; then
    pass DNS-DoT "with DNS-over-TLS on, two fresh lookups sent no plain DNS out of the WAN (control counted $((C2 - C1)))"
  else
    fail DNS-DoT "no plain DNS out of the WAN with DNS-over-TLS on" "$((C1 - C0)) packet(s) to port 53"
  fi
else
  info DNS-DoT "DNS-over-TLS is off on this router; not checked here (full mode turns it on)"
fi

# ---- 5. The guard repairs itself: rules wiped, as a firmware action does ------------------------
E="$(pins | head -1)"
if [ -n "$E" ]; then
  IP="${E%>*}"
  ip rule del from "$IP" priority 91 2>/dev/null
  for R in $(ip rule show | awk -v ip="$IP" '$1 == "89:" && $3 == ip {print $5}'); do ip rule del from "$IP" to "$R" priority 89 2>/dev/null; done
  for R in $(ip rule show | awk -v ip="$IP" '$1 == "88:" && $3 == ip {print $5}'); do ip rule del from "$IP" to "$R" priority 88 2>/dev/null; done
  guard_check broken expect-broken
  # The schedules are paused, so run what cron would: one minute's run.
  cru a cfg_pia_wg_guard "* * * * *" "$D/guard.sh"
  i=0; while [ "$i" -lt 80 ] && [ "$(ip rule show | grep -c "^91:.*from $IP blackhole")" = 0 ]; do sleep 1; i=$((i + 1)); done
  # Rule 91 goes back first; let that run finish its other rules before they are checked.
  j=0; while [ "$j" -lt 30 ] && [ -d /tmp/cfg-pia-wg-guard.lock ]; do sleep 1; j=$((j + 1)); done
  cru d cfg_pia_wg_guard
  [ "$(ip rule show | grep -c "^91:.*from $IP blackhole")" = 1 ] && pass GUARD-repair "a wiped rule was put back by cron in ${i}s" || fail GUARD-repair "a wiped rule was put back" "not within 80s"
  guard_check repaired
fi

# ---- 6. A tunnel stopped: its pinned devices are refused, not sent out the WAN ------------------
E="$(pins | head -1)"
if [ -n "$E" ]; then
  TB="${E#*>}"; SL="$(slot_of "$TB")"
  UNIT="$(nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$SL" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}')"
  nvram set vpnc_unit="$UNIT"; service stop_vpnc
  i=0; while [ "$i" -lt 30 ] && ip -o link show up | grep -q " wgc$SL:"; do sleep 1; i=$((i + 1)); done
  guard_check "wgc$SL-stopped"
  nvram set vpnc_unit="$UNIT"; service restart_vpnc
  i=0; while [ "$i" -lt 60 ] && [ -z "$(wg show "wgc$SL" latest-handshakes 2>/dev/null | awk '$2 > 0')" ]; do sleep 1; i=$((i + 1)); done
  sleep 3; "$D/guard.sh" >/dev/null 2>&1
  guard_check "wgc$SL-restarted"
fi

[ "$MODE" = quick ] && { echo "== $PASSN passed, $FAILN failed"; logger "**CHECK-CLAIMS END** $MODE: $PASSN passed, $FAILN failed"; exit "$FAILN"; }

# ---- 7. DNS setups, each proved by a real rebuild ---------------------------------------------
W1="$(for S in "$D"/watchdog_wgc*.sh; do [ -f "$S" ] && echo "$S" && break; done)"
[ -n "$W1" ] || { info SETUP "no watchdog deployed; the DNS setups need one"; echo "== $PASSN passed, $FAILN failed"; exit "$FAILN"; }
WS="$(basename "$W1" .sh)"; WS="${WS#watchdog_}"; WSL="${WS#wgc}"
SDNS="$(nvram get "${WS}_dns" | tr -d ' ')"; SD1="${SDNS%%,*}"; SD2="${SDNS#*,}"; [ "$SD2" = "$SDNS" ] && SD2="$SD1"
# Router DNS that is NOT the slot's: the first DoT server, or Cloudflare's filtering one.
OTHER1=1.1.1.2; OTHER2=1.0.0.2; [ "$SD1" = 1.1.1.2 ] && { OTHER1=9.9.9.9; OTHER2=149.112.112.112; }
WUNIT="$(nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$WSL" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}')"

apply_dns() {  # $1 dns1 $2 dns2 $3 isp(0/1) $4 dot(0/1)
  DNSCHANGED=1
  nvram set wan0_dnsenable_x="$3"; nvram set wan0_dns1_x="$1"; nvram set wan0_dns2_x="$2"; nvram set dnspriv_enable="$4"
  # Stock service takes the action and its unit as one argument.
  service "restart_wan_if 0"
  sleep 10
  i=0; while [ "$i" -lt 60 ] && ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; do sleep 2; i=$((i + 1)); done
  sleep 5
}
applied() {  # $1 dns1 $3 isp $4 dot: read what the router is really using
  OK=1
  [ "$3" = 0 ] && ! grep -q "nameserver $1" /etc/resolv.conf && OK=0
  if [ "$4" = 1 ]; then grep -q 127.0.1.1 /tmp/resolv.dnsmasq || OK=0; else grep -q 127.0.1.1 /tmp/resolv.dnsmasq && OK=0; fi
  [ "$OK" = 1 ]
}
rebuild() {  # $1 label, $2 expected: enc | plain | honest
  printf '0\n0\n' > "/tmp/watchdog_backoff_$WS"
  N0="$(wc -l < "/tmp/watchdog_$WS.log" 2>/dev/null || echo 0)"
  wg set "$WS" peer "$(nvram get "${WS}_ppub")" remove
  sleep 2
  T=240; bounded /bin/sh /tmp/check-claims-wd.sh foreground
  NEW="$(tail -n +"$((N0 + 1))" "/tmp/watchdog_$WS.log" 2>/dev/null | cut -c21-)"
  OKRB="$(echo "$NEW" | grep -c 'Reconfig SUCCESS')"
  ENC="$(echo "$NEW" | grep -c 'Looked up .* over encrypted DNS')"
  PLAIN="$(echo "$NEW" | grep -c 'Encrypted lookup of .* failed\|Name lookups are NOT encrypted')"
  case "$2" in
    enc) [ "$OKRB" = 1 ] && [ "$ENC" -ge 2 ] && [ "$PLAIN" = 0 ] && pass "SETUP-$1" "rebuilt, every PIA name looked up over DoH" || fail "SETUP-$1" "rebuild with DoH" "success=$OKRB encrypted=$ENC plain=$PLAIN; $(echo "$NEW" | grep -m1 ERROR | cut -c1-120)" ;;
    plain) [ "$ENC" = 0 ] && [ "$PLAIN" -ge 1 ] && pass "SETUP-$1" "no DoH claimed, and the log says the lookups were not encrypted (rebuilt=$OKRB)" || fail "SETUP-$1" "honest logging without DoH" "encrypted=$ENC plain=$PLAIN" ;;
  esac
  # Put the tunnel back for the next setup, whatever happened.
  if [ -z "$(wg show "$WS" latest-handshakes 2>/dev/null | awk '$2 > 0')" ]; then nvram set vpnc_unit="$WUNIT"; service restart_vpnc; sleep 8; fi
  guard_check "after-$1"
  sleep 30
}
variant() {  # $1 doh_ips (or "" for none), $2 email 0/1: a copy of the deployed script
  sed -e "s/^DOHIPS=.*/DOHIPS=\"$1\"/" -e "s/^EMAIL_ON=.*/EMAIL_ON=\"$2\"/" "$W1" > /tmp/check-claims-wd.sh
  [ -z "$1" ] && sed -i 's/^DOHURL=.*/DOHURL=""/' /tmp/check-claims-wd.sh
}
DOHIP="$(sed -n 's/^DOHIPS="\(.*\)"$/\1/p' "$W1")"

setup() {  # $1 label, $2 dns1, $3 dns2, $4 isp, $5 dot, $6 doh ("" none, "dead", else real), $7 expect, $8 email
  apply_dns "$2" "$3" "$4" "$5"
  if ! applied "$2" "$3" "$4" "$5"; then fail "SETUP-$1" "the DNS setup was applied" "resolv.conf: $(grep nameserver /etc/resolv.conf | tr '\n' ' ')"; return; fi
  info "SETUP-$1" "router DNS $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' '); DoT $5; the router's own route to $2: $(ip route get "$2" 2>&1 | head -1 | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}')"
  case "$6" in dead) variant 192.0.2.1 "$8" ;; "") variant "" "$8" ;; *) variant "$DOHIP" "$8" ;; esac
  rebuild "$1" "$7"
}
[ -n "$DOHIP" ] || info SETUP "the deployed watchdog has no DoH server; the encrypted setups will say so"
setup same-as-slot-dot-off "$SD1" "$SD2" 0 0 real enc 0
setup same-as-slot-dot-on "$SD1" "$SD2" 0 1 real enc 0
setup different-dot-on "$OTHER1" "$OTHER2" 0 1 real enc 1
setup isp-dot-off "$OTHER1" "$OTHER2" 1 0 real enc 0
setup same-as-slot-doh-dead "$SD1" "$SD2" 0 0 dead plain 0
setup different-no-doh "$OTHER1" "$OTHER2" 0 0 "" plain 0

echo "== $PASSN passed, $FAILN failed"
logger "**CHECK-CLAIMS END** $MODE: $PASSN passed, $FAILN failed"
exit "$FAILN"
