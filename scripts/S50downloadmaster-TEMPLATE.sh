#!/bin/sh
# Minimal replacement for the stock Download Master init script.
# Sole purpose: install our cron job once at boot.
# Every other trigger (firewall-start, firewall-restart, restart,
# stop, lighttpd-restart, bt-restart, dir-change) returns instantly
# so VPN up/down events are never delayed.

# bootup/powercycle requires a delay otherwise the boot process is blocked
# and the VPN gets stuck in a "connecting" state.
BOOT_FLAG=/tmp/.dm_boot_delay_done
if [ ! -f "$BOOT_FLAG" ]; then
    touch "$BOOT_FLAG"
    sleep 10
fi

[ "$1" = "start" ] || exit 0
  # Add cru jobs back after rebooting or power cycle
  # ********** REPLACEMENT START **********
  # 1 to N cruCheckLine entries
  # 1 to N cruRotateLine entries
  # ********** REPLACEMENT END **********
exit 0