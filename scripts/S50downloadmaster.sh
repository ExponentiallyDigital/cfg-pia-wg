#!/bin/sh
#
# v0.0.20 cfg-pia-wg_cru (S50downloadmaster) - install a cron entry to maintain a persistent WireGuard VPN
#
# Stock router firmware blocks extra scripts from exec in /opt/etc/init.d,
# this script *must* be named S50downloadmaster.
#
# Retains variables set by stock Download Master script, but Download Master is *not* enabled.

set -u

WATCHDOG_INTERVAL=5   # minutes between watchdog pings

# Delay to allow NTP to converge so cron job timestamps are meaningful.
# NB sleeping affects every call to this script, eg called everytime a firewall restart is requested.
sleep 10

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
  start)
    log_debug "executed via parameter: $1"

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
  restart|force-reload|stop|firewall-start|firewall-restart|lighttpd-restart|dir-change)
    log_debug "triggered by parameter: $1 (no action required)"
    ;;
  *)
    log_debug "unrecognised trigger: $1 (no action)"
    ;;
esac

log_debug "END script /opt/etc/init.d/S50downloadmaster trigger: $1"
exit 0
