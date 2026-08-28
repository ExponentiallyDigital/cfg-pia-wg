#!/bin/sh
#
# v0.1.0 S50downloadmaster-TEMPLATE - install two cru entries to maintain a persistent WireGuard VPN
#
# Stock router firmware blocks extra scripts from exec in /opt/etc/init.d,
# this script *must* be named S50downloadmaster.
#
# Retains variables set by stock Download Master script, but Download Master is *not* enabled.

set -u

# Delay to allow NTP to converge at boot so log timestamps are meaningful.
# NB sleeping affects every call to this script, eg called everytime a firewall restart is requested.
sleep 10

DEBUG=on
log_debug() {
    if [ "$DEBUG" = "on" ]; then
        logger -t cfg-pia-wg "$@"
    fi
}
log() {
    logger -t cfg-pia-wg "$@"
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
    log_debug "exec via trigger: $1"
    # Add cru jobs back after rebooting or power cycle
    # ********** REPLACEMENT START **********
    # 1 to N cruCheckLine entries
    # 1 to N cruRotateLine entries
    # ********** REPLACEMENT END **********
    ;;
  restart|force-reload|stop|firewall-start|firewall-restart|lighttpd-restart|dir-change)
    log_debug "exec via trigger: $1 (no action required)"
    ;;
  *)
    log_debug "unrecognised trigger: $1 (no action)"
    ;;
esac

log_debug "END script /opt/etc/init.d/S50downloadmaster trigger: $1"
exit 0
