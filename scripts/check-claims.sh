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
#   quick  the read-only checks, then on stock the guard broken on purpose and put back: a rule wiped
#          and the filter emptied, each repaired by the router's own firewall restart; a WAN route
#          planted in the guard's table; the table emptied with its tunnel up; and the tunnel
#          stopped, with rule 91 taken away for a moment to show the check sees the leak it stops.
#          One PIA login at most. About 5 minutes.
#   full   quick, then each DNS setup below applied in turn, each proved by a real rebuild of the
#          first watchdog's tunnel; PIA logins 30 s apart. About 15 minutes; the internet drops for
#          a few seconds at each DNS change.
#
# On Merlin (ID-353) the firmware-neutral checks run as they are: TLS, secrets, DNS-over-TLS. Mail is
# checked as Merlin sends it, openssl naming the server. There is no guard or filter to check; Merlin's
# own kill switch is measured instead, from the kernel, with a tunnel stopped (quick). Full adds one
# real rebuild with the router's DNS as it is, which proves the encrypted lookups and sends the alert.
#
# DNS setups (full): the router's own DNS servers the same as the slot's, with DNS-over-TLS off and
# on; different from the slot's; from the ISP; and the watchdog's DoH server dead, and unset. Each
# is checked applied (by reading /etc/resolv.conf and /tmp/resolv.dnsmasq) before it is tested.
#
# Safe by construction: every NVRAM key it touches is saved to /jffs/check-claims.restore first,
# a trap puts them back on any exit, and `/bin/sh /jffs/check-claims.restore` does it by hand if the
# script itself was killed. Watchdog schedules are paused while it runs, and put back, and so is the
# guard's per-minute entry on a router that still has one from builds 480 to 490.
# Stock and Merlin. BusyBox only: no seq, od, hexdump, xxd, base64, timeout, command or logread.
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
FW=stock; [ "$(nvram get 3rd-party)" = "merlin" ] && FW=merlin
# On stock most of this proves the guard, so it must be there. Merlin has none: its kill switch is
# the firmware's own.
[ "$FW" = merlin ] || [ -x "$D/guard.sh" ] || { echo "No $D/guard.sh: deploy a watchdog or APPLY in DEVICES first."; exit 2; }

# ---- snapshot and restore --------------------------------------------------------------------
KEYS="wan0_dns1_x wan0_dns2_x wan0_dnsenable_x dnspriv_enable"; [ "$FW" = stock ] && KEYS="$KEYS vpnc_unit filter_lwlist cfg_pia_wg_lwlist"
if [ "$MODE" != dry ]; then
  : > "$RESTORE"
  for K in $KEYS; do printf 'nvram set %s=%s\n' "$K" "'$(nvram get "$K")'" >> "$RESTORE"; done
  # restart_wan_if is what applies a DNS Server change; the hand restore always runs it.
  printf 'nvram commit\nservice "restart_wan_if 0"\nsleep 10\n' >> "$RESTORE"
  cru l | grep -E '#(watchdog_|cfg_pia_wg_guard)' > "$CRUSAVE"
  while read -r L; do X="${L%#}"; printf 'cru a %s "%s"\n' "${X##*#}" "$(X2="${X%#*}"; echo "${X2% }")" >> "$RESTORE"; done < "$CRUSAVE"
fi
# The tunnels up at the start: the restore brings back these, and only these.
UPSTART="$(ip -o link show up | awk -F': ' '$2 ~ /^wgc[0-9]$/ {print $2}' | tr '\n' ' ')"
unit_of() { nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v s="$1" 'length($0)==0 {next} {if ($3 == s) {print n + 0; exit} n++}'; }
handshake() { [ -n "$(wg show "$1" latest-handshakes 2>/dev/null | awk '$2 > 0')" ]; }
# A tunnel by slot number, the way the app starts and stops it on each firmware.
tunnel_start() { if [ "$FW" = merlin ]; then service "start_wgc $1"; service restart_vpnrouting0; else nvram set vpnc_unit="$(unit_of "$1")"; service restart_vpnc; fi; }
tunnel_stop() { if [ "$FW" = merlin ]; then service "stop_wgc $1"; service start_vpnrouting0; else nvram set vpnc_unit="$(unit_of "$1")"; service stop_vpnc; fi; }
guarded() { [ -x "$D/guard.sh" ] && "$D/guard.sh" 2>/dev/null | grep -o 'guarded [0-9]* of [0-9]*'; }
RESTORED=""
restore() {
  [ -n "$RESTORED" ] || [ "$MODE" = dry ] && return 0
  RESTORED=1
  echo "== restoring"
  # The WAN restart only when the DNS settings were changed: quick mode leaves them alone.
  if [ -n "$DNSCHANGED" ]; then /bin/sh "$RESTORE" >/dev/null 2>&1; else grep -v restart_wan_if "$RESTORE" > "$RESTORE.q"; /bin/sh "$RESTORE.q" >/dev/null 2>&1; rm -f "$RESTORE.q"; fi
  i=0; while [ "$i" -lt 30 ] && ! nslookup example.com 127.0.0.1 >/dev/null 2>&1; do sleep 2; i=$((i + 1)); done
  NOTBACK=""
  for IF in $UPSTART; do
    ip -o link show up | grep -q " $IF:" && handshake "$IF" && continue
    # A service call can be dropped while another runs, so try twice and read the result.
    for TRY in 1 2; do
      tunnel_start "${IF#wgc}"
      i=0; while [ "$i" -lt 45 ] && ! handshake "$IF"; do sleep 1; i=$((i + 1)); done
      handshake "$IF" && break
    done
    handshake "$IF" || NOTBACK="$NOTBACK $IF"
  done
  [ -x "$D/guard.sh" ] && "$D/guard.sh" >/dev/null 2>&1
  # Filter rules taken out of the firewall by hand come back only with a firewall restart.
  [ -n "$FILTERBROKEN" ] && service restart_firewall
  rm -f "$RESTORE" "$CRUSAVE" /tmp/check-claims-wd.sh
  GTXT=""; [ "$FW" = stock ] && GTXT=" guard $(guarded),"
  echo "== restored: $(cru l | grep -cE '#(watchdog_|cfg_pia_wg_guard)') schedules,$GTXT tunnels up at the start:${UPSTART:+ $UPSTART}"
  [ -z "$NOTBACK" ] || echo "== NOT RESTORED: no handshake on$NOTBACK. Enable it in MANAGE or the web interface."
}
trap restore EXIT INT TERM
WAN="$(nvram get wan0_ifname)"

logger "**CHECK-CLAIMS START** $MODE"
echo "== check-claims $MODE on $FW, $(date '+%Y-%m-%d %H:%M:%S')"

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
# Only curl's TLS handshake failure (35) is the refusal; a name or connection failure is no answer.
case "$RC" in
  0) fail TLS-floor "--tlsv1.2 refuses a TLS 1.1 server" "it connected" ;;
  35) pass TLS-floor "--tlsv1.2 refuses a TLS 1.1 server (rc=35, the handshake)" ;;
  *) info TLS-floor "tls-v1-1.badssl.com did not answer the TLS question (rc=$RC); not checked" ;;
esac
# The platform fact the watchdog's own DoH exists for. INFO, not PASS: it is ASUS's behaviour.
bounded curl -s -o /dev/null --max-time 15 --doh-url https://nothing.invalid/dns-query --resolve nothing.invalid:443:127.0.0.1 https://example.com/
[ "$RC" = 0 ] && info DOH-0 "curl still ignores --doh-url (a dead DoH server made no difference)" || info DOH-0 "curl now honours --doh-url (rc=$RC): the watchdog's own lookups are still what it uses"

# ---- 2. Mail: certificate names are checked ----------------------------------------------------
M="$D/mailsend-go"
SH="$(nvram get wgc1_wd_smtp_server)"; SP="${SH##*:}"; SH="${SH%%:*}"; [ -n "$SH" ] || SH=smtp.gmail.com
[ -n "$SP" ] && [ "$SP" != "$SH" ] || SP=465
SIP="$(nslookup "$SH" 2>/dev/null | awk '/^Address/ && $3 ~ /^[0-9.]+$/ {print $3}' | tail -1)"
if [ "$FW" = merlin ]; then
  # Merlin's sendmail hands the connection to openssl, as the watchdog's $SMTPCONN does (ID-310):
  # the name must be refused when it's wrong, or any publicly trusted certificate would do.
  T=25
  smtp_tls() { echo QUIT | openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -connect "$SH:$SP" -servername "$SH" -verify_hostname "$1"; }
  bounded smtp_tls wrong.example.com
  WRC="$RC"
  bounded smtp_tls "$SH"
  case "$RC:$WRC" in
    0:0) fail MAIL-name "openssl refuses a certificate for the wrong name" "it accepted wrong.example.com" ;;
    0:143) info MAIL-name "the wrong-name connection hung; not checked" ;;
    0:*) pass MAIL-name "openssl, as Merlin's mail uses it, refuses a certificate for the wrong name (rc=$WRC)" ;;
    *) info MAIL-name "$SH:$SP did not complete TLS for the right name either (rc=$RC); not checked" ;;
  esac
  [ "$RC" = 0 ] && pass MAIL-0 "control: the right name is accepted"
  for S in "$D"/watchdog_wgc*.sh; do
    [ -f "$S" ] || continue
    grep -q -- '-verify_return_error $SMTPCONN' "$S" && grep -q -- '-verify_hostname $SMTP_HOST' "$S" && pass "MAIL-script" "$(basename "$S") sends naming the server" || fail "MAIL-script" "$(basename "$S") sends naming the server" "missing"
  done
elif [ -x "$M" ] && [ -n "$SIP" ]; then
  T=25
  bounded "$M" -ssl -verifyCert -smtp "$SIP" -port 465 -f check@example.com -t check@example.com -sub check body -msg check auth -user check -pass check
  grep -q x509 "$LOG" && pass MAIL-name "mailsend-go -verifyCert refuses a certificate for the wrong name" || fail MAIL-name "mailsend-go -verifyCert refuses a certificate for the wrong name" "$(head -c 100 "$LOG")"
  bounded "$M" -ssl -smtp "$SIP" -port 465 -f check@example.com -t check@example.com -sub check body -msg check auth -user check -pass check
  grep -q 535 "$LOG" && pass MAIL-0 "control: without -verifyCert the same connection reaches the login" || info MAIL-0 "control did not reach the login: $(head -c 100 "$LOG")"
else
  info MAIL-name "no mailsend-go or SMTP address; skipped"
fi
[ "$FW" = stock ] && for S in "$D"/watchdog_wgc*.sh; do
  [ -f "$S" ] || continue
  grep -q -- '-verifyCert' "$S" && pass "MAIL-script" "$(basename "$S") sends with -verifyCert" || fail "MAIL-script" "$(basename "$S") sends with -verifyCert" "missing"
done

# ---- 3. The guard, per pinned device, from the kernel -------------------------------------------
# From build 491 (ID-364): rule 90 sends a pinned device to the guard's own table for its tunnel,
# 200 + slot, which holds the tunnel's default and the router's local routes and never a route out
# of the WAN, and rule 91 blackholes whatever that table can't route. Nothing runs the guard on a
# timer: the boot hook asks for a run on every firewall-start, 10 s after the last call of a burst.
#
# Pinned devices as ip>table>slot, the slot "other" for another kind of VPN, which the guard leaves
# alone, and "gone" for a profile that no longer exists, whose devices get rule 91 alone (ID-346).
# Worked out here rather than borrowed from guard.sh, so a fault there can't empty the list this
# checks and pass it.
pins() {
  PS=" $(nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' '$7 != "" {k = "other"; if ($2 == "WireGuard" && $3 != "") k = $3; printf "%s:%s ", $7, k}')"
  nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' -v s="$PS" '$1 == "1" && $2 != "" && $4 != "" && $4 != "0" {
    k = "gone"; n = split(s, p, " "); for (i = 1; i <= n; i++) { split(p[i], q, ":"); if (q[1] == $4) k = q[2] }
    print $2 ">" $4 ">" k }'
}
# The ones the guard holds: pinned to a WireGuard profile, or to one that no longer exists.
gpins() { pins | grep -v '>other$'; }
# Where the kernel sends a device's traffic for an address: wgcN, WAN, BLOCKED, or what it said.
route_of() {
  RO="$(ip route get "$2" from "$1" iif br0 2>&1 | head -1)"
  case "$RO" in
    *RTNETLINK*|*unreachable*|*prohibit*|*blackhole*) echo BLOCKED ;;
    *" dev wgc"[0-9]*) echo "$RO" | sed 's/.* dev \(wgc[0-9]\).*/\1/' ;;
    *" dev $WAN "*|*" dev $WAN") echo WAN ;;
    *) echo "$RO" | tr ' ' '_' ;;
  esac
}
# Every address main sends out of the WAN by more than its default - the gateway, the WAN subnet,
# the router's own DNS servers (ID-347) - and a public one: where a pinned device would leak.
leak_targets() {
  echo 1.1.1.1
  ip route show table main | awk -v w="$WAN" '$1 != "default" {for (i = 2; i < NF; i++) if ($i == "dev" && $(i + 1) == w) {print $1; next}}'
}
# Waits for a guard run the router's events have asked for, while one is pending or running, so a
# check reads what that run leaves rather than racing it. At most 40 s.
guard_settle() {
  GW=0
  while [ "$GW" -lt 40 ]; do
    GP="$(cat /tmp/cfg-pia-wg-guard.next 2>/dev/null)"
    { [ -n "$GP" ] && grep -q guard.sh "/proc/$GP/cmdline" 2>/dev/null; } || [ -d /tmp/cfg-pia-wg-guard.lock ] || return 0
    sleep 1; GW=$((GW + 1))
  done
}
# Its own variable names throughout: shell variables are global, and reusing IP here once pointed
# the caller's repair check at the wrong device.
guard_check() {
  tag="$1"; GN=0; BAD=""
  GRULES="$(ip rule show)"; GUP="$(ip -o link show up)"; GTGT="$(leak_targets)"
  for GE in $(gpins); do
    GIP="${GE%%>*}"; GSL="${GE##*>}"; GN=$((GN + 1))
    G90="$(echo "$GRULES" | grep -c "^90:.*from $GIP ")"
    [ "$(echo "$GRULES" | grep -c "^91:.*from $GIP blackhole")" = 1 ] || BAD="$BAD $GIP:no91"
    echo "$GRULES" | grep -qE "^8[89]:.*from $GIP " && BAD="$BAD $GIP:old88-89"
    if [ "$GSL" = gone ]; then
      [ "$G90" = 0 ] || BAD="$BAD $GIP:90-for-a-deleted-profile"
      GUPIF=0
    else
      { [ "$G90" = 1 ] && echo "$GRULES" | grep -qE "^90:.*from $GIP lookup $((200 + GSL))( |\$)"; } || BAD="$BAD $GIP:no90-to-$((200 + GSL))"
      GUPIF="$(echo "$GUP" | grep -c " wgc$GSL:")"
    fi
    for GX in $GTGT; do
      GX1="${GX%/*}"
      # A subnet's own address is a broadcast address the kernel answers from its local table
      # before any rule, so ask about a host inside it instead: the network address plus two.
      case "$GX" in */*) GL="${GX1##*.}"; GX1="${GX1%.*}.$((GL + 2))" ;; esac
      GR="$(route_of "$GIP" "$GX1")"
      case "$GR:$GUPIF" in
        "wgc$GSL:1" | BLOCKED:0) ;;
        BLOCKED:1) BAD="$BAD $GIP>$GX1:blocked-while-wgc$GSL-up" ;;
        *) BAD="$BAD $GIP>$GX1:$GR" ;;
      esac
    done
  done
  # The guard's tables: the tunnel's default and the router's local routes, and nothing else.
  for GSL in $(gpins | awk -F'>' '$3 ~ /^[0-9]+$/ {print $3}' | sort -u); do
    GX="$(ip route show table $((200 + GSL)) 2>/dev/null | grep -vE "^default dev wgc$GSL( |\$)" | grep -vE ' dev (br|lo|wgs|tun)[0-9.]*( |$)' | head -1)"
    [ -z "$GX" ] || BAD="$BAD table$((200 + GSL)):$(echo "$GX" | tr ' ' '_')"
  done
  N="$GN"
  if [ "$2" = expect-broken ]; then
    # The negative control: with the guard broken on purpose, this check must see it.
    [ -n "$BAD" ] && pass "GUARD-$tag" "the check sees a guard broken on purpose: $(echo "$BAD" | cut -c1-100)" || fail "GUARD-$tag" "the check sees a broken guard" "it saw nothing wrong"
    return
  fi
  [ -z "$BAD" ] && pass "GUARD-$tag" "$N pinned device(s): both rules held, no WAN route in the guard's tables, every address through the device's tunnel or refused" || fail "GUARD-$tag" "the guard" "$(echo "$BAD" | cut -c1-300)"
}
[ "$FW" = stock ] && { guard_settle; guard_check now; }
# The second layer (ID-348): each pinned device's TCP and UDP out of the WAN are dropped by the
# router's own Network Services Filter, read from the firewall itself, not the settings.
filter_check() {
  FRULES="$(iptables -S FORWARD)"; FN=0; FMISS=""
  for FE in $(gpins); do
    FIP="${FE%%>*}"; FN=$((FN + 1))
    for FP in tcp udp; do
      echo "$FRULES" | grep -qE -- "-s $(echo "$FIP" | sed 's/[.]/[.]/g')/32 -i br0 -o $WAN -p $FP -j DROP" || FMISS="$FMISS $FIP/$FP"
    done
  done
  [ "$FN" = 0 ] && return
  if [ "$2" = expect-broken ]; then
    [ -n "$FMISS" ] && pass "FILTER-$1" "the check sees a filter broken on purpose:$(echo "$FMISS" | cut -c1-100)" || fail "FILTER-$1" "the check sees a broken filter" "it saw nothing missing"
    return
  fi
  if [ "$(nvram get fw_lw_enable_x)" = 1 ] && [ -z "$FMISS" ]; then
    pass "FILTER-$1" "$FN pinned device(s): the router's firewall drops their TCP and UDP out of the WAN"
  else
    fail "FILTER-$1" "the Network Services Filter" "enabled=$(nvram get fw_lw_enable_x) missing:$(echo "$FMISS" | cut -c1-200)"
  fi
}
[ "$FW" = stock ] && filter_check now
if [ "$FW" = stock ] && [ -n "$(gpins)" ]; then
  # Nothing schedules the guard from build 491 (ID-364). Builds 480 to 490 ran it every minute, in the
  # same second as each watchdog tick's own run, and runs a second apart crash asd (ID-361).
  cru l | grep -q '#cfg_pia_wg_guard#' && fail GUARD-cron "nothing schedules the guard" "the per-minute entry of builds 480 to 490 is still there" || pass GUARD-cron "nothing schedules the guard: the router's events run it"
  HK=/opt/etc/init.d/S50downloadmaster
  if grep -q '"firewall-start"' "$HK" 2>/dev/null && grep -q 'guard.sh soon' "$HK" && grep -q 'guard.sh >/dev/null' "$HK" && ! grep -q 'cru a cfg_pia_wg_guard' "$HK"; then
    pass GUARD-boot "the boot hook runs the guard at boot, and asks for a run on every firewall-start"
  else
    fail GUARD-boot "the boot hook" "S50downloadmaster lacks the guard's boot run or its firewall-start call, or still schedules it"
  fi
  # Stock calls the hook on start and firewall-start only while Download Master is enabled.
  DME="$(/usr/sbin/app_get_field.sh downloadmaster Enabled 1 2>/dev/null)"
  [ "$DME" = yes ] && pass GUARD-hook "Download Master is enabled, so stock calls the boot hook" || fail GUARD-hook "Download Master is enabled, so stock calls the boot hook" "app_get_field.sh says \"$DME\""
fi
# The pinned devices' DNS redirects, routed from the devices.
iptables -t nat -S VPN_FUSION 2>/dev/null | awk '{s=""; d=""; for (i = 1; i < NF; i++) {if ($i == "-s") s = $(i + 1); if ($i == "--to-destination") d = $(i + 1)} sub("/32", "", s); if (s != "" && d != "") print s, d}' > /tmp/check-claims.dnat
LEAK=""
while read -r S DD; do
  case "$(ip route get "$DD" from "$S" iif br0 2>&1 | head -1)" in *" dev wgc"*|*RTNETLINK*|*unreachable*|*prohibit*) ;; *) LEAK="$LEAK $S>$DD" ;; esac
done < /tmp/check-claims.dnat
rm -f /tmp/check-claims.dnat
[ "$FW" = merlin ] || { [ -z "$LEAK" ] && pass DNS-pinned "pinned devices' redirected DNS goes through their tunnel, or nowhere" || fail DNS-pinned "pinned devices' DNS" "$LEAK"; }

# ---- 3m. Merlin: the kill switch, as the kernel has it ---------------------------------------
# VPN Director's rules send a device to a tunnel's table: `from <ip> lookup wgcN`. The claim the
# watchdog makes is only that the setting is on (ID-326); this measures what it does.
mdevs() { ip rule show | awk -v t="wgc$1" '$NF == t {for (i = 2; i < NF; i++) if ($i == "from" && $(i + 1) != "all") print $(i + 1)}' | sort -u; }
mroute() { ip route get 1.1.1.1 from "${1%/*}" iif br0 2>&1 | head -1; }
if [ "$FW" = merlin ]; then
  for SN in 1 2 3 4 5; do
    [ -n "$(nvram get "wgc${SN}_addr")" ] || continue
    info "KS-wgc$SN" "kill switch setting $(nvram get "wgc${SN}_enforce"), VPN Director devices: $(mdevs "$SN" | tr '\n' ' ')"
  done
fi

# ---- 4. Secrets on flash and in the log -------------------------------------------------------
PW="$(nvram get cfg_pia_wg_password)"; U="$(nvram get cfg_pia_wg_user)"
# The password is searched for from a file, never as an argument, so it isn't in `ps` meanwhile.
if [ -n "$PW" ] && [ ! -f /jffs/curllst ]; then
  pass SECRET-curllst "the PIA password is not in /jffs/curllst (there is no such file)"
elif [ -n "$PW" ]; then
  ( umask 077; printf '%s\n' "$PW" > /tmp/check-claims.pw )
  N="$(grep -cFf /tmp/check-claims.pw /jffs/curllst)"
  rm -f /tmp/check-claims.pw
  [ "$N" = 0 ] && pass SECRET-curllst "the PIA password is not in /jffs/curllst" || fail SECRET-curllst "the PIA password is in /jffs/curllst" "${N:-unreadable} line(s)"
fi
PW=""
[ -n "$U" ] && { [ "$(grep -cF -- "Requesting PIA token for user $U" /tmp/syslog.log 2>/dev/null)" = 0 ] && pass SECRET-syslog "the watchdog logs no PIA user" || info SECRET-syslog "an older watchdog run logged the PIA user"; }

[ "$MODE" = dry ] && { info DRY "stopping before anything is changed: quick breaks the guard on purpose and stops a tunnel, full adds the DNS setups"; exit "$FAILN"; }

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

# ---- 5. The router's own events put the guard back (ID-364) ------------------------------------
# Nothing runs the guard on a timer. A firewall restart raises firewall-start, and the boot hook asks
# for one guard run, 10 s after the last call of a burst; the app runs it itself after its actions.
E=""; [ "$FW" = stock ] && E="$(gpins | awk -F'>' '$3 ~ /^[0-9]+$/' | head -1)"
if [ -n "$E" ]; then
  IP="${E%%>*}"; SL="${E##*>}"; GT=$((200 + SL))
  guard_settle
  # Rule 90 wiped. Broken towards closed: rule 91 still drops everything, so the device is offline,
  # not out of the WAN, until the guard runs.
  ip rule del from "$IP" priority 90 2>/dev/null
  guard_check wiped expect-broken
  T0="$(date +%s)"
  service restart_firewall
  i=0; while [ "$i" -lt 60 ] && ! ip rule show | grep -qE "^90:.*from $IP lookup $GT( |\$)"; do sleep 1; i=$((i + 1)); done
  TE=$(($(date +%s) - T0))
  guard_settle
  ip rule show | grep -qE "^90:.*from $IP lookup $GT( |\$)" && pass GUARD-event "a wiped rule was put back by the router's own firewall restart, ${TE}s later" || fail GUARD-event "a wiped rule was put back by the router's own firewall restart" "not within 60s"
  guard_check repaired

  # A route out of the WAN planted in the guard's table, which nothing in the design puts there:
  # this check must see it, and the guard's next run must take it out.
  WR="$(ip route show table main | awk -v w="$WAN" '$1 != "default" {for (i = 2; i < NF; i++) if ($i == "dev" && $(i + 1) == w) {print; exit}}')"
  if [ -n "$WR" ]; then
    ip route add $WR table "$GT" 2>/dev/null
    guard_check planted expect-broken
    "$D/guard.sh" >/dev/null 2>&1
    ip route show table "$GT" | grep -q " dev $WAN" && fail GUARD-planted "the guard takes a WAN route out of its table" "it is still there" || pass GUARD-planted "the guard's next run took the planted WAN route out of its table"
  fi

  # The filter (ID-348, ID-362), short of this device in NVRAM and in the firewall, as a firewall
  # restart with a short list would leave it. The router's next firewall restart runs the guard, which
  # puts the list back and asks for one restart of its own; the run that one raises finds nothing to
  # change, so the chain ends. Counted by the guard's run requests, one per firewall-start.
  ER="$(echo "$IP" | sed 's/[.]/[.]/g')"
  FILTERBROKEN=1
  nvram set filter_lwlist="$(nvram get filter_lwlist | sed "s/<$ER>>>>TCP//; s/<$ER>>>>UDP//")"
  for FP in tcp udp; do iptables -D FORWARD -s "$IP/32" -i br0 -o "$WAN" -p "$FP" -j DROP 2>/dev/null; done
  filter_check emptied expect-broken
  NEXT=/tmp/cfg-pia-wg-guard.next; LAST="$(cat "$NEXT" 2>/dev/null)"; CALLS=0; QUIET=0; K=0
  service restart_firewall
  # Every 0.2 s, until 30 s pass with no new request, or two minutes in all.
  while [ "$QUIET" -lt 150 ] && [ "$K" -lt 600 ]; do
    V="$(cat "$NEXT" 2>/dev/null)"
    if [ "$V" != "$LAST" ]; then CALLS=$((CALLS + 1)); LAST="$V"; QUIET=0; else QUIET=$((QUIET + 1)); fi
    usleep 200000; K=$((K + 1))
  done
  guard_settle
  if [ "$QUIET" -ge 150 ]; then
    pass FILTER-chain "the firewall restarts stopped by themselves after $CALLS firewall-start call(s): ours, and the guard's one"
    [ "$CALLS" = 2 ] || info FILTER-chain "2 calls expected; $CALLS seen, so something else restarted the firewall meanwhile"
  else
    fail FILTER-chain "the firewall restarts stop by themselves" "$CALLS firewall-start calls in two minutes, and still coming"
  fi
  filter_check event
  [ -z "$FMISS" ] && FILTERBROKEN=""
fi

# ---- 6m. Merlin: a tunnel with its kill switch on stopped; its devices must be refused ----------
if [ "$FW" = merlin ]; then
  KSN=""
  for SN in 1 2 3 4 5; do
    [ "$(nvram get "wgc${SN}_enforce")" = 1 ] && handshake "wgc$SN" && [ -n "$(mdevs "$SN")" ] && { KSN="$SN"; break; }
  done
  if [ -z "$KSN" ]; then
    info KS-stopped "no running tunnel has its kill switch on and a VPN Director device; not checked"
  else
    KDEV="$(mdevs "$KSN" | head -1)"
    case "$(mroute "$KDEV")" in *" dev wgc$KSN"*) ;; *) info "KS-wgc$KSN-up" "with wgc$KSN up, $KDEV routes: $(mroute "$KDEV")" ;; esac
    tunnel_stop "$KSN"
    i=0; while [ "$i" -lt 30 ] && ip -o link show up | grep -q " wgc$KSN:"; do sleep 1; i=$((i + 1)); done
    sleep 3
    if ip -o link show up | grep -q " wgc$KSN:"; then
      info "KS-wgc$KSN-stopped" "wgc$KSN didn't stop within 30s; not checked"
    else
      KR="$(mroute "$KDEV")"
      KRULES="$(ip rule show | grep -c "lookup wgc$KSN\$")"
      case "$KR" in
        *RTNETLINK*|*unreachable*|*prohibit*|*blackhole*) pass "KS-wgc$KSN-stopped" "kill switch on, wgc$KSN stopped: $KDEV is refused ($KRULES rule(s) still send it to the tunnel's table)" ;;
        *" dev wgc$KSN"*) fail "KS-wgc$KSN-stopped" "kill switch on, wgc$KSN stopped" "$KDEV still routes to the stopped tunnel: $KR" ;;
        *) fail "KS-wgc$KSN-stopped" "kill switch on, wgc$KSN stopped: $KDEV is refused" "it goes out: $KR" ;;
      esac
    fi
    for TRY in 1 2; do
      tunnel_start "$KSN"
      i=0; while [ "$i" -lt 45 ] && ! handshake "wgc$KSN"; do sleep 1; i=$((i + 1)); done
      handshake "wgc$KSN" && break
    done
    handshake "wgc$KSN" && pass "KS-wgc$KSN-restarted" "wgc$KSN came back" || fail "KS-wgc$KSN-restarted" "wgc$KSN came back" "no handshake after two starts"
  fi
fi

# ---- 6. A tunnel stopped: its pinned devices are refused, not sent out the WAN ------------------
E=""; [ "$FW" = stock ] && E="$(gpins | awk -F'>' '$3 ~ /^[0-9]+$/' | head -1)"
if [ -n "$E" ]; then
  IP="${E%%>*}"; SL="${E##*>}"; GT=$((200 + SL))
  guard_settle
  # The guard's table without its default, as a rebuild leaves it until the guard's next run: with
  # the tunnel up, the device must be refused, not sent anywhere else.
  if handshake "wgc$SL"; then
    ip route del default dev "wgc$SL" table "$GT" 2>/dev/null
    R="$(route_of "$IP" 1.1.1.1)"
    [ "$R" = BLOCKED ] && pass "GUARD-wgc$SL-empty" "with wgc$SL up and the guard's table emptied of its default, $IP is refused" || fail "GUARD-wgc$SL-empty" "with the guard's table emptied of its default, $IP is refused" "it goes $R"
    "$D/guard.sh" >/dev/null 2>&1
    R="$(route_of "$IP" 1.1.1.1)"
    [ "$R" = "wgc$SL" ] && pass "GUARD-wgc$SL-refilled" "a guard run, as the app makes after its own actions, sent $IP back through wgc$SL" || fail "GUARD-wgc$SL-refilled" "a guard run sends $IP back through wgc$SL" "it goes $R"
  else
    info "GUARD-wgc$SL-empty" "wgc$SL has no handshake; not checked"
  fi
  # A service call can be dropped while another runs, so each is read back, and a check that
  # would be about a tunnel in the wrong state is not made.
  tunnel_stop "$SL"
  i=0; while [ "$i" -lt 30 ] && ip -o link show up | grep -q " wgc$SL:"; do sleep 1; i=$((i + 1)); done
  if ip -o link show up | grep -q " wgc$SL:"; then
    info "GUARD-wgc$SL-stopped" "wgc$SL didn't stop within 30s (the call may have been dropped); not checked"
  else
    guard_settle
    guard_check "wgc$SL-stopped"
    # The negative control (ID-364): with rule 91 gone, the same device must be seen going out, or
    # the check above couldn't tell a leak from the guard. Put back at once.
    ip rule del from "$IP" priority 91 2>/dev/null
    R="$(route_of "$IP" 1.1.1.1)"
    ip rule show | grep -q "^91:.*from $IP blackhole" || ip rule add from "$IP" blackhole priority 91
    [ "$R" != BLOCKED ] && pass "GUARD-wgc$SL-no91" "without rule 91, $IP's traffic goes $R: the check sees the leak rule 91 stops" || fail "GUARD-wgc$SL-no91" "without rule 91, the check sees $IP's traffic go out" "it was still refused, so this check can't tell a leak from the guard"
    R="$(route_of "$IP" 1.1.1.1)"
    [ "$R" = BLOCKED ] || fail "GUARD-wgc$SL-91back" "rule 91 put back" "$IP goes $R"
  fi
  T0="$(date +%s)"
  for TRY in 1 2; do
    tunnel_start "$SL"
    i=0; while [ "$i" -lt 45 ] && ! handshake "wgc$SL"; do sleep 1; i=$((i + 1)); done
    handshake "wgc$SL" && break
  done
  if handshake "wgc$SL"; then
    # No guard run from here: restart_vpnc raises firewall-start, and the run the hook asks for
    # refills the table 10 s after the last call (ID-364). Until then the device is refused.
    i=0; while [ "$i" -lt 45 ] && [ "$(route_of "$IP" 1.1.1.1)" != "wgc$SL" ]; do sleep 1; i=$((i + 1)); done
    TE=$(($(date +%s) - T0))
    R="$(route_of "$IP" 1.1.1.1)"
    [ "$R" = "wgc$SL" ] && pass "GUARD-wgc$SL-back" "$IP back through wgc$SL by the router's own events, ${TE}s after the tunnel was started" || fail "GUARD-wgc$SL-back" "$IP back through wgc$SL by the router's own events" "it goes $R, ${TE}s after the tunnel was started"
    guard_settle
    guard_check "wgc$SL-restarted"
  else
    fail "GUARD-wgc$SL-restarted" "wgc$SL came back" "no handshake after two restarts"
  fi
fi

[ "$MODE" = quick ] && { echo "== $PASSN passed, $FAILN failed"; logger "**CHECK-CLAIMS END** $MODE: $PASSN passed, $FAILN failed"; exit "$FAILN"; }

# ---- 7. DNS setups, each proved by a real rebuild ---------------------------------------------
W1="$(for S in "$D"/watchdog_wgc*.sh; do [ -f "$S" ] && echo "$S" && break; done)"
[ -n "$W1" ] || { info SETUP "no watchdog deployed; the DNS setups need one"; echo "== $PASSN passed, $FAILN failed"; exit "$FAILN"; }
WS="$(basename "$W1" .sh)"; WS="${WS#watchdog_}"; WSL="${WS#wgc}"
SDNS="$(nvram get "${WS}_dns" | tr -d ' ')"; SD1="${SDNS%%,*}"; SD2="${SDNS#*,}"; [ "$SD2" = "$SDNS" ] && SD2="$SD1"
# Router DNS that is NOT the slot's: the first DoT server, or Cloudflare's filtering one.
OTHER1=1.1.1.2; OTHER2=1.0.0.2; [ "$SD1" = 1.1.1.2 ] && { OTHER1=9.9.9.9; OTHER2=149.112.112.112; }

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
  # The router's own count of packets to the DoH server, so "encrypted" rests on more than the
  # watchdog's log. Counting rules only. The rebuild's tunnel restart rebuilds the firewall and
  # wipes them, after the lookups, so the count is polled during the run and its highest kept.
  VIPS="$(sed -n 's/^DOHIPS="\(.*\)"$/\1/p' /tmp/check-claims-wd.sh | tr ',' ' ')"
  for V in $VIPS; do iptables -I OUTPUT -d "$V" -p tcp --dport 443 -j RETURN; done
  dohcount() { iptables -vxnL OUTPUT | awk -v vs=" $VIPS " '$3 == "RETURN" && index(vs, " " $9 " ") && /dpt:443/ {s += $1} END {print s + 0}'; }
  rm -f /tmp/check-claims.stop; echo 0 > /tmp/check-claims.doh
  ( while [ ! -f /tmp/check-claims.stop ]; do
      C="$(dohcount)"; [ "$C" -gt "$(cat /tmp/check-claims.doh)" ] && echo "$C" > /tmp/check-claims.doh
      usleep 300000
    done ) &
  POLL=$!
  T=240; bounded /bin/sh /tmp/check-claims-wd.sh foreground
  touch /tmp/check-claims.stop; wait "$POLL" 2>/dev/null
  DC="$(cat /tmp/check-claims.doh)"; DC="${DC:-0}"
  rm -f /tmp/check-claims.stop /tmp/check-claims.doh
  for V in $VIPS; do iptables -D OUTPUT -d "$V" -p tcp --dport 443 -j RETURN 2>/dev/null; done
  NEW="$(tail -n +"$((N0 + 1))" "/tmp/watchdog_$WS.log" 2>/dev/null | cut -c21-)"
  OKRB="$(echo "$NEW" | grep -c 'Reconfig SUCCESS')"
  ENC="$(echo "$NEW" | grep -c 'Looked up .* over encrypted DNS')"
  PLAIN="$(echo "$NEW" | grep -c 'Encrypted lookup of .* failed\|Name lookups are NOT encrypted')"
  case "$2" in
    enc) [ "$OKRB" = 1 ] && [ "$ENC" -ge 2 ] && [ "$PLAIN" = 0 ] && [ "$DC" -gt 0 ] && pass "SETUP-$1" "rebuilt, every PIA name looked up over DoH ($DC packets to the DoH server, counted by the router)" || fail "SETUP-$1" "rebuild with DoH" "success=$OKRB encrypted=$ENC plain=$PLAIN doh_packets=$DC; $(echo "$NEW" | grep -m1 ERROR | cut -c1-120)" ;;
    plain) [ "$ENC" = 0 ] && [ "$PLAIN" -ge 1 ] && pass "SETUP-$1" "no DoH claimed, and the log says the lookups were not encrypted (rebuilt=$OKRB)" || fail "SETUP-$1" "honest logging without DoH" "encrypted=$ENC plain=$PLAIN" ;;
  esac
  # Put the tunnel back for the next setup, whatever happened, and read it back.
  for TRY in 1 2; do
    handshake "$WS" && break
    tunnel_start "$WSL"
    i=0; while [ "$i" -lt 45 ] && ! handshake "$WS"; do sleep 1; i=$((i + 1)); done
  done
  # The rebuild's tunnel restart and the watchdog both ask for a guard run, 10 s on (ID-364).
  [ "$FW" = stock ] && { guard_settle; guard_check "after-$1"; }
  [ "$FW" = stock ] && filter_check "after-$1"
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
if [ "$FW" = merlin ]; then
  # One rebuild with the router's DNS as it is: the DNS setups below are stock's question. The alert
  # email is sent, which proves Merlin's mail path end to end (MRL-8).
  variant "$DOHIP" 1
  rebuild as-is enc
  echo "$NEW" | grep -q 'Alert email sent (SUCCESS)' && pass MAIL-sent "the rebuild's SUCCESS email was sent" || fail MAIL-sent "the rebuild's SUCCESS email was sent" "$(echo "$NEW" | grep -E 'Email (FAILED|not sent)' | tail -1 | cut -c1-150)"
  echo "== $PASSN passed, $FAILN failed"
  logger "**CHECK-CLAIMS END** $MODE: $PASSN passed, $FAILN failed"
  exit "$FAILN"
fi
setup same-as-slot-dot-off "$SD1" "$SD2" 0 0 real enc 0
setup same-as-slot-dot-on "$SD1" "$SD2" 0 1 real enc 0
setup different-dot-on "$OTHER1" "$OTHER2" 0 1 real enc 1
setup isp-dot-off "$OTHER1" "$OTHER2" 1 0 real enc 0
setup same-as-slot-doh-dead "$SD1" "$SD2" 0 0 dead plain 0
setup different-no-doh "$OTHER1" "$OTHER2" 0 0 "" plain 0

echo "== $PASSN passed, $FAILN failed"
logger "**CHECK-CLAIMS END** $MODE: $PASSN passed, $FAILN failed"
exit "$FAILN"
