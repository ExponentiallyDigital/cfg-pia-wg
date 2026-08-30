#!/bin/sh
#
# v0.1.01 cfg-pia-wg_cru (S50downloadmaster)
# Purpose: for testing purposes adds a router log message when invoked plus logs a msg every 5m via cru added job.
#
# Stock router firmware blocks extra scripts from exec in /opt/etc/init.d,
# this script *must* be named S50downloadmaster.
#
# Retains variables set by stock Download Master script, but Download Master is *not* enabled.
# Router fails to load network if Download Master is enabled but does not execute this script.

set -u
WATCHDOG_INTERVAL=5   # minutes between watchdog pings
DEBUG=on
log_debug() {
    if [ "$DEBUG" = "on" ]; then
        logger -t cfg-pia-wg_cru "$@"
    fi
}
log() {
    logger -t cfg-pia-wg_cru "$@"
}

log_debug "START /opt/etc/init.d/S50downloadmaster, trigger: $1"

# Clear restricted environment paths (matches Download Master startup)
unset LD_LIBRARY_PATH
PATH=/bin:/sbin:/usr/sbin:/usr/bin:/opt/bin

# --- Validate storage is mounted before doing any further work ---
if ! APPS_MOUNTED_PATH=$(nvram get apps_mounted_path 2>/dev/null) || [ -z "$APPS_MOUNTED_PATH" ]; then
    log "ERROR nvram apps_mounted_path is empty or unavailable"
    exit 1
fi

if ! APPS_INSTALL_FOLDER=$(nvram get apps_install_folder 2>/dev/null) || [ -z "$APPS_INSTALL_FOLDER" ]; then
    log "ERROR apps_install_folder is empty or unavailable"
    exit 1
fi

# APPS_INSTALL_PATH is reserved for future use by companion scripts.
APPS_INSTALL_PATH="$APPS_MOUNTED_PATH/$APPS_INSTALL_FOLDER"

case "$1" in
  start|force-reload|restart)
    log_debug "triggered by: $1"
    # delayed to match original script, without this the router fails to complete the startup process,
    # especially if the routerr starts with a VPN set active.
    sleep 10
    ;;

  firewall-start|firewall-restart)
    log_debug "triggered by: $1"
    # delayed start to match original script, without this the router fails to complete the startup process,
    # especially if the routerr starts with a VPN set active.
    sleep 3
    # Idempotent: remove any stale entry first, then add fresh.
    /usr/sbin/cru d cfg-pia-wg_watchdog 2>/dev/null
  
    if output=$(/usr/sbin/cru a cfg-pia-wg_watchdog \
        "*/$WATCHDOG_INTERVAL * * * * logger -t cfg-pia-wg_cru \"CRU_TEST_CRU_TEST\"" 2>&1); then
        log "watchdog added to cron successfully"
    else
        log "ERROR watchdog cron add failed. rc=$? output: $output"
        exit 1
    fi
    ;;
  
  stop|firewall-stop|lighttpd-restart|bt-restart|dir-change)
    log_debug "triggered by: $1 (no action taken)"
    ;;
  
  *)
    log_debug "unrecognised trigger: $1 (no action taken)"
    ;;
esac

log_debug "END script /opt/etc/init.d/S50downloadmaster trigger: $1"
exit 0
