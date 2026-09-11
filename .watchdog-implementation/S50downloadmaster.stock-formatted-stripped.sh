#!/bin/sh
#
# v0.2.01 scripts\S50downloadmaster.stock-formatted-stripped.sh
# Purpose: to identify how this script gets called by VPN events.
#
# Stock router firmware blocks extra scripts from exec in /opt/etc/init.d,
# this script *must* be named S50downloadmaster.
#
# Router fails to load network at boot if Download Master is enabled but does
# not execute this script returning 0 to the parent.

DEBUG=on
log_debug() {
    if [ "$DEBUG" = "on" ]; then
        logger -t **********DOWNLOADMASTER-TEST********** "$@"
    fi
}
log() {
    logger -t **********DOWNLOADMASTER-TEST********** "$@"
}

log_debug "START S50downloadmaster, trigger: $1"

# to match original ASUS script
sleep 2

case "$1" in
  start|force-reload|restart)
    log_debug "triggered by: $1"
    sleep 10
  ;;
  stop)
    log_debug "triggered by: $1"
  ;;
  firewall-start)
    log_debug "triggered by: $1"
  ;;
  firewall-stop)
    log_debug "triggered by: $1"
  ;;
  firewall-restart)
    log_debug "triggered by: $1"
  ;;
  lighttpd-restart)
    log_debug "triggered by: $1"
    sleep 2
  ;;
  bt-restart)
    log_debug "triggered by: $1"
  ;;
  dir-change)
    log_debug "triggered by: $1"
  ;;
  general-renew)
    log_debug "triggered by: $1"
  ;;
  *)
    log_debug "triggered by: $1"
    exit 1
  ;;
esac

log_debug "END S50downloadmaster trigger: $1"
exit 0
