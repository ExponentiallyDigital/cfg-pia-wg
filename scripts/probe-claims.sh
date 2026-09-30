#!/bin/sh
# probe-claims.sh - settles the claims audit's open questions on a stock router (ID-345, first part).
#
# Run it as `/bin/sh /jffs/probe-claims.sh [a|b|c|all]`, never `sh ...`: over SSH, stock's PATH finds
# /usr/sbin/sh first, which is a Broadcom memory tool, not the shell.
#
#   a  reads only: guard rules per pinned device, boot hook, IPv6, secrets left in /jffs/curllst,
#      the PIA username in syslog, ip6tables for disabled devices, and whether mailsend-go and
#      openssl s_client really refuse a bad certificate (ID-311, ID-310).
#   b  stops one tunnel two ways and puts it back: what a pinned device's DNS does while its
#      tunnel is down (ID-318). The watchdogs are paused for the duration and put back by a trap.
#   c  times real service calls against the service queue's 10-second ghost rule (ID-334).
#
# Prints ANSWERS lines, `key=value`, and nothing secret: passwords are counted, never printed.
# Needs only what stock BusyBox has (no seq, no timeout, no command, no hexdump).

PART="${1:-all}"
OUT=/tmp/probe_claims.out
say() { echo "ANSWER $1"; }
note() { echo "  - $*"; }

# Runs "$@" for at most $T seconds; output in $OUT, exit code in RC (143 if it was stopped).
bounded() {
  "$@" > "$OUT" 2>&1 &
  p=$!; i=0
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt "$T" ]; do sleep 1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; RC=143; else wait "$p"; RC=$?; fi
}

# Each pinned device as "ip>vpnc_idx", from the firmware's own list.
pins() { nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' '$1=="1" && $2!="" && $4!="" && $4!="0" {print $2">"$4}'; }

part_a() {
  echo "== A: read-only"
  say "ipv6_service=$(nvram get ipv6_service)"
  n=0; ok=0; bad=""
  for e in $(pins); do
    ip="${e%>*}"; t="${e#*>}"; n=$((n + 1))
    r90="$(ip rule show | grep -c "^90:.*from $ip lookup $t suppress_prefixlength 0")"
    r91="$(ip rule show | grep -c "^91:.*from $ip blackhole")"
    if [ "$r90" = 1 ] && [ "$r91" = 1 ]; then ok=$((ok + 1)); else bad="$bad $ip(90=$r90,91=$r91)"; fi
  done
  say "pinned_devices=$n guarded_both_rules=$ok missing=[${bad# }]"
  s50=/opt/etc/init.d/S50downloadmaster
  if [ -f "$s50" ]; then say "boot_hook_calls_guard=$(grep -c guard.sh "$s50")"; else say "boot_hook_calls_guard=no_S50"; fi
  PW="$(nvram get cfg_pia_wg_password)"
  if [ -n "$PW" ] && [ -f /jffs/curllst ]; then say "curllst_lines_with_pia_password=$(grep -cF -- "$PW" /jffs/curllst)"; else say "curllst_lines_with_pia_password=n/a"; fi
  for n in 1 2 3 4 5; do
    h="$(nvram get wgc${n}_wd_smtp_server)"; h="${h%%:*}"
    [ -n "$h" ] && [ -f /jffs/curllst ] && say "curllst_lines_with_smtp_host_wgc$n=$(grep -cF -- "$h" /jffs/curllst)"
  done
  U="$(nvram get cfg_pia_wg_user)"
  [ -n "$U" ] && say "syslog_lines_with_pia_user=$(grep -cF -- "$U" /tmp/syslog.log)"
  say "ip6tables_rules=$(ip6tables -S 2>/dev/null | grep -c .) ip6tables_mac_rules=$(ip6tables -S 2>/dev/null | grep -ic 'mac-source')"
  say "iptables_mac_drop_rules=$(iptables -S 2>/dev/null | grep -i 'mac-source' | grep -ic drop)"

  # mailsend-go (stock's mailer) against the real SMTP server by ADDRESS: the certificate names the
  # host, not the address, so -verifyCert must refuse it. The control, without -verifyCert, has to
  # get as far as the login (a 535), or the refusal proves nothing (ID-311). badssl.com resets
  # mailsend-go's connection before its certificate is checked, so it can't be used here.
  M=/jffs/cfg-pia-wg/mailsend-go
  SH="$(nvram get wgc1_wd_smtp_server)"; SH="${SH%%:*}"; [ -n "$SH" ] || SH=smtp.gmail.com
  SIP="$(nslookup "$SH" 2>/dev/null | awk '/^Address/ && $3 ~ /^[0-9.]+$/ {print $3}' | tail -1)"
  if [ -x "$M" ] && [ -n "$SIP" ]; then
    T=25
    bounded "$M" -ssl -verifyCert -smtp "$SIP" -port 465 -f probe@example.com -t probe@example.com -sub probe body -msg probe auth -user probe -pass probe
    say "mailsend_verifyCert_wrong_name rc=$RC x509_refused=$(grep -c 'x509' "$OUT")"
    bounded "$M" -ssl -smtp "$SIP" -port 465 -f probe@example.com -t probe@example.com -sub probe body -msg probe auth -user probe -pass probe
    say "mailsend_control_no_verifyCert rc=$RC reached_login=$(grep -c '535' "$OUT")"
  else
    say "mailsend=not_installed_or_no_smtp_address"
  fi

  # openssl s_client the way Merlin's mailer uses it: -verify_return_error alone checks the chain,
  # not the name, so a real certificate for another host would be accepted (ID-310).
  T=20
  bounded /bin/sh -c 'printf "QUIT\r\n" | openssl s_client -quiet -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -connect www.cloudflare.com:443'
  say "s_client_chain_only_other_host rc=$RC"
  bounded /bin/sh -c 'printf "QUIT\r\n" | openssl s_client -quiet -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -verify_hostname smtp.gmail.com -servername www.cloudflare.com -connect www.cloudflare.com:443'
  say "s_client_with_verify_hostname_other_host rc=$RC hostname_mismatch=$(grep -c 'Hostname mismatch' "$OUT")"
}

# ---- B: a pinned device's DNS with its tunnel down ------------------------------------------------
CRUSAVE=/tmp/probe_claims.cru
# A cru line reads "<schedule> <command> #<tag>#"; split it back into the two things `cru a` takes.
cru_tag() { x="${1%#}"; echo "${x##*#}"; }
cru_body() { x="${1%#}"; x="${x%#*}"; echo "${x% }"; }
pause_watchdogs() {
  cru l | grep '#watchdog_' > "$CRUSAVE"
  while read -r line; do cru d "$(cru_tag "$line")"; done < "$CRUSAVE"
}
resume_watchdogs() {
  [ -f "$CRUSAVE" ] || return 0
  while read -r line; do cru a "$(cru_tag "$line")" "$(cru_body "$line")"; done < "$CRUSAVE"
  rm -f "$CRUSAVE"
}

# The tunnel whose table is $1, as "slot unit" (unit = its row in vpnc_clientlist).
slot_of_table() {
  nvram get vpnc_clientlist | tr '<' '\n' | awk -F'>' -v t="$1" 'length($0)==0 {next} {if ($7 == t) {print $3" "(n + 0); exit} n++}'
}

wait_up() { i=0; while [ "$i" -lt 60 ]; do ip -o link show up | grep -q " $1:" && [ "$(wg show "$1" latest-handshakes | awk '{print $2}')" -gt 0 ] 2>/dev/null && return 0; sleep 1; i=$((i + 1)); done; return 1; }

dns_state() {
  label="$1"
  say "$label dnat_rules_for_device=$(iptables -t nat -S VPN_FUSION | grep -c -- "-s $D/32")"
  say "$label route_to_slot_dns=[$(ip route get "$SDNS" from "$D" iif br0 2>&1 | head -1)]"
  say "$label route_to_1.1.1.1=[$(ip route get 1.1.1.1 from "$D" iif br0 2>&1 | head -1)]"
  say "$label route_to_router_dns=[$(ip route get "$(nvram get wan0_dns | cut -d' ' -f1)" from "$D" iif br0 2>&1 | head -1)]"
}

# Put the tunnel back as ENABLE does (timed), then vpnc_unit, the guard and the watchdogs.
restore_b() {
  [ -n "$RESTORED" ] && return 0
  RESTORED=1
  t0="$(date +%s)"
  if ! ip -o link show up | grep -q " $IF:" || [ -z "$(wg show "$IF" peers 2>/dev/null)" ]; then
    nvram set vpnc_unit="$UNIT"; service restart_vpnc
  fi
  if wait_up "$IF"; then say "b3_restored_after=$(( $(date +%s) - t0 ))s"; else say "b3_restored=NO - $IF not back after 60s"; fi
  nvram set vpnc_unit="$OLDUNIT"
  [ -x /jffs/cfg-pia-wg/guard.sh ] && /jffs/cfg-pia-wg/guard.sh >/dev/null 2>&1
  resume_watchdogs
}

part_b() {
  echo "== B: a pinned device's DNS with its tunnel down (changes, then restores)"
  e="$(pins | head -1)"
  [ -n "$e" ] || { say "b=skipped_no_pinned_device"; return; }
  D="${e%>*}"; TBL="${e#*>}"
  set -- $(slot_of_table "$TBL"); SLOT="$1"; UNIT="$2"; IF="wgc$SLOT"
  SDNS="$(nvram get ${IF}_dns | tr -d ' ' | cut -d, -f1)"
  say "b_device=$D table=$TBL slot=$IF unit=$UNIT slot_dns=$SDNS"
  PEER="$(nvram get ${IF}_ppub)"
  OLDUNIT="$(nvram get vpnc_unit)"
  pause_watchdogs
  # Whatever happens, the tunnel comes back, vpnc_unit is put back and the watchdogs resume.
  trap 'restore_b' EXIT INT TERM
  dns_state "b0_up"

  # B1: the peer is gone but the interface stays up - what an expired key or dead server looks like.
  wg set "$IF" peer "$PEER" remove
  sleep 3
  dns_state "b1_peer_removed"

  # B2: DISABLE's own service call.
  nvram set vpnc_unit="$UNIT"; service stop_vpnc
  i=0; while [ "$i" -lt 30 ] && ip -o link show up | grep -q " $IF:"; do sleep 1; i=$((i + 1)); done
  say "b2_interface_down_after=${i}s"
  dns_state "b2_stopped"

  restore_b
  trap - EXIT INT TERM
  dns_state "b3_restored"
  say "b_watchdogs_restored=$(cru l | grep -c '#watchdog_') vpnc_unit_restored=$([ "$(nvram get vpnc_unit)" = "$OLDUNIT" ] && echo yes || echo NO)"
}

# ---- C: how long real service calls keep the queue busy -------------------------------------------
time_service() {
  svc="$1"; t0="$(date +%s)"; busy=0
  service "$svc"
  i=0
  while [ "$i" -lt 600 ]; do
    [ -z "$(nvram get rc_service)" ] && break
    usleep 100000; i=$((i + 1))
  done
  say "c_$svc queue_busy_tenths=$i wall=$(( $(date +%s) - t0 ))s"
}
part_c() {
  echo "== C: service timings"
  before="$(grep -c 'skip the event' /tmp/syslog.log)"
  time_service restart_dnsmasq
  sleep 2
  time_service restart_firewall
  sleep 5
  say "c_guard_rules_after_firewall=$(ip rule show | grep -cE '^9[01]:')"
  say "c_skip_events_during=$(( $(grep -c 'skip the event' /tmp/syslog.log) - before ))"
}

logger "**PROBE-CLAIMS START** $PART"
case "$PART" in
  a) part_a ;; b) part_b ;; c) part_c ;;
  all) part_a; part_b; part_c ;;
  *) echo "usage: /bin/sh probe-claims.sh [a|b|c|all]"; exit 2 ;;
esac
logger "**PROBE-CLAIMS END** $PART"
rm -f "$OUT"
