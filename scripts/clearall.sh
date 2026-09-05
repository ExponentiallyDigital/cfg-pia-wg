#!/bin/sh
# Clears all NVRAM settings created/modified by the app.

# Clear vpnc_unit
nvram set vpnc_unit=

# Clear vpncN_ dut-discovery and state vars
for v in vpnc5_dns vpnc5_dut_disc vpnc6_dut_disc vpnc6_sbstate_t vpnc6_state_t \
         vpnc7_dut_disc vpnc8_dut_disc vpnc9_dut_disc vpnc9_dns \
         vpnc9_sbstate_t vpnc9_state_t vpnc5_sbstate_t vpnc5_state_t \
         vpnc8_sbstate_t vpnc8_state_t; do
    nvram unset "$v"
done
nvram commit

# the vpnc_unit variable is used to determine which vpncN_ variables are used for the VPN connection.
nvram set vpnc_unit=
nvram commit

# Clear wgc1-5 config vars, including watchdog email/SMTP fields
for slot in 1 2 3 4 5; do
    for field in desc addr aips alive dns enable ep_addr ep_addr_r ep_port \
                 mtu nat ppub priv psk wd_primary_ip wd_secondary_ip \
                 wd_check_interval wd_email_enabled wd_email_from \
                 wd_email_subject wd_email_to wd_smtp_pass wd_smtp_server \
                 wd_smtp_user; do
        nvram unset "wgc${slot}_${field}"
    done
done
nvram commit

# Clear enforce/fw/rip flags for wgc1 and wgc5
for v in wgc1_enforce wgc1_fw wgc1_rip wgc5_enforce wgc5_fw wgc5_rip; do
    nvram unset "$v"
done
nvram commit

# Clear PIA username and password
nvram unset cfg_pia_wg_user
nvram unset cfg_pia_wg_password

# Clear the lifetime counters reported in watchdog alert emails
nvram unset cfg_pia_wg_sdate
nvram unset cfg_pia_wg_reconfig_ok
nvram unset cfg_pia_wg_reconfig_fail
nvram commit