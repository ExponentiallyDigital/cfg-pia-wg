#!/bin/sh
#
# v0.0.16 cfg-pia-wg_cru (S50downloadmaster) - install a cron entry to maintain a persistent WireGuard VPN
#
# Stock router firmware blocks extra scripts from exec in /opt/etc/init.d,
# this script *must* be named S50downloadmaster.
#

# set DEBUG=on to enable extra logging, set DEBUG=off to disable it
DEBUG=off
log_debug() {
[ "$DEBUG" = "on" ] && logger -t cfg-pia-wg_cru "$@"
}
log() {
logger -t cfg-pia-wg_cru "$@"
}

# Log startup and trigger parameter
log_debug "****** startup /opt/etc/init.d/S50downloadmaster, trigger is: $1 ******"

# Clear restricted environment paths (matches Download Master startup)
unset LD_LIBRARY_PATH
PATH=/bin:/sbin:/usr/sbin:/usr/bin:/opt/bin

# Extract mounted storage paths from NVRAM with explicit error check
if ! APPS_MOUNTED_PATH=$(nvram get apps_mounted_path 2>/dev/null); then
log_debug "ERROR ****** nvram get apps_mounted_path failed (command error) ******"
exit 1
fi
# Get install folder with explicit error check
if ! APPS_INSTALL_FOLDER=$(nvram get apps_install_folder 2>/dev/null); then
log_debug "ERROR ****** nvram get apps_install_folder failed (command error) ******"
exit 1
fi
APPS_INSTALL_PATH="$APPS_MOUNTED_PATH/$APPS_INSTALL_FOLDER"

# Block execution if the storage volume is not mounted
if [ -z "$APPS_MOUNTED_PATH" ]; then
log "ERROR ****** USB volume not mounted ******"
exit 1
fi

# Handle all Download Master startup trigger states
case "$1" in
start)
# delay to ensure ntp has started - valid logging timestamp
sleep 60
log_debug "****** executed via parameter: $1 ******"
# Add cron entry with 5m interval and capture outcome
if output=$(/usr/sbin/cru a cfg-pia-wg_watchdog "*/5 * * * * logger -t cfg-pia-wg_cru \"****** CRU_TEST_CRU_TEST ******\"" 2>&1); then
log "watchdog added to cron successfully"
else
exit_code=$?
log "ERROR ****** watchdog cron add failed. Exit code: $exit_code. Output: $output. ******"
exit 1
fi
;;
restart|force-reload)
log_debug "****** triggered by parameter: $1 ******"
;;
stop)
# router shutting down, no need to remove cron entry, it will be cleared on reboot
log_debug "****** shutting down ******"
;;
firewall-start|firewall-restart|lighttpd-restart|dir-change)
# Catch Download Master state triggers so they do not crash or log usage errors
log_debug "****** triggered by parameter: $1 ******"
;;

*)
# Default fallback
log_debug "****** default fallback ******"
;;
esac

log_debug "****** end script /opt/etc/init.d/S50downloadmaster started via: $1 ******"
exit 0