#!/bin/sh
# Removes everything cfg-pia-wg creates in ncram on the router
# Destructive and unconditional - it does not ask.

echo "== wgcN_ slot + watchdog settings =="
# All 17 slot keys (enforce/fw/rip are Merlin-only but unsetting them on stock is harmless) plus
# the 10 wgcN_wd_ watchdog keys, for every slot rather than the two that used to be listed.
for slot in 1 2 3 4 5; do
    for field in wd_check_interval wd_email_enabled wd_email_from wd_email_subject \
                 wd_email_to wd_primary_ip wd_secondary_ip \
                 wd_smtp_pass wd_smtp_server wd_smtp_user; do
        nvram unset "wgc${slot}_${field}"
    done
done
nvram commit


echo "== cfg-pia-wg globals =="
# PIA credentials, and the lifetime counters reported in watchdog alert emails.
for v in cfg_pia_wg_user cfg_pia_wg_password \
         cfg_pia_wg_sdate cfg_pia_wg_reconfig_ok cfg_pia_wg_reconfig_fail; do
    nvram unset "$v"
done
nvram commit

echo
echo "Done. Reboot the router to be certain nothing is holding state in memory."
