#!/bin/sh
# Removes everything cfg-pia-wg creates on the router: NVRAM, cron entries, deployed files and the
# watchdog's volatile state. Destructive and unconditional - it does not ask.
#
# Not touched, deliberately:
#   jffs2_scripts / jffs2_on  - the app turns these on, but other scripts of yours may rely on them
#   /jffs/cfg-pia-wg/jq, mailsend-go - you installed those by hand; re-downloading them is a chore
#   the S50downloadmaster and services-start files themselves - only our cru lines are stripped

echo "== cru entries =="
# `cru d` on a name that is not scheduled prints an error; that is not a failure here.
for slot in 1 2 3 4 5; do
    for job in watchdog watchdog_log_rotate; do
        cru d "${job}_wgc${slot}" 2>/dev/null
    done
done
cru l

echo "== deployed files =="
for slot in 1 2 3 4 5; do
    rm -f "/jffs/cfg-pia-wg/watchdog_wgc${slot}.sh"
done
rm -f /jffs/cfg-pia-wg/pia_ca.rsa.4096.crt
# Volatile state: the log, the last-good stamp and the backoff counter.
rm -f /tmp/watchdog_wgc[1-9].log /tmp/watchdog_wgc[1-9].log.old \
      /tmp/watchdog_last_ping_success_wgc[1-9] /tmp/watchdog_backoff_wgc[1-9] \
      /tmp/mail.txt /tmp/mail_wgc[1-9].txt /tmp/wd_smtp_err*

echo "== boot persistence =="
# Strip only our two lines per slot; everything else in these files is left alone.
for f in /jffs/scripts/services-start /opt/etc/init.d/S50downloadmaster; do
    [ -f "$f" ] || continue
    # No `&&`: grep exits 1 when nothing survives the filter, which would strand the .tmp file.
    grep -v -E "watchdog_wgc[1-9] |watchdog_log_rotate_wgc[1-9] " "$f" > "$f.tmp" 2>/dev/null
    [ -f "$f.tmp" ] && mv "$f.tmp" "$f"
    chmod +x "$f"
    echo "cleaned $f"
done

echo "== wgcN_ slot + watchdog settings =="
# All 17 slot keys (enforce/fw/rip are Merlin-only but unsetting them on stock is harmless) plus
# the 10 wgcN_wd_ watchdog keys, for every slot rather than the two that used to be listed.
for slot in 1 2 3 4 5; do
    for field in addr aips alive desc dns enable enforce ep_addr ep_addr_r ep_port \
                 fw mtu nat ppub priv psk rip \
                 wd_check_interval wd_email_enabled wd_email_from wd_email_subject \
                 wd_email_to wd_primary_ip wd_secondary_ip \
                 wd_smtp_pass wd_smtp_server wd_smtp_user; do
        nvram unset "wgc${slot}_${field}"
    done
done
nvram commit

echo "== stock vpnc =="
# vpncN_ runtime keys are indexed by the profile's clientlist field 7, not by slot, so sweep the
# whole 1-16 range rather than guessing which ones were used.
i=1
while [ "$i" -le 16 ]; do
    for field in dns dut_disc sbstate_t state_t; do
        nvram unset "vpnc${i}_${field}"
    done
    i=$((i + 1))
done
nvram set vpnc_clientlist=
nvram set vpnc_unit=
nvram set vpnc_default_wan=0
nvram commit

echo "== cfg-pia-wg globals =="
# PIA credentials, and the lifetime counters reported in watchdog alert emails.
for v in cfg_pia_wg_user cfg_pia_wg_password \
         cfg_pia_wg_sdate cfg_pia_wg_reconfig_ok cfg_pia_wg_reconfig_fail; do
    nvram unset "$v"
done
nvram commit

echo "== interfaces =="
for i in wgc1 wgc2 wgc3 wgc4 wgc5; do
    ip link set dev "$i" down 2>/dev/null
    ip link del dev "$i" 2>/dev/null
done
wg show interfaces

echo
echo "Done. Reboot the router to be certain nothing is holding state in memory."
