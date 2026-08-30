#!/bin/sh
#
# v0.2.01 scripts\S50asuslighttpd.stock-formatted-stripped.sh
# Purpose: to identify how this script gets called by VPN events.

DEBUG=on
log_debug() {
    if [ "$DEBUG" = "on" ]; then
        logger -t *****ASUSLIGHTTTPD-TEST***** "$@"
    fi
}
log() {
    logger -t *****ASUSLIGHTTTPD-TEST***** "$@"
}

log_debug "START S50asuslighttpd, trigger: $1"

case "$1" in
  start|force-reload|restart)
    log_debug "triggered by: $1"
    # was 3, try 5.
    sleep 5
  ;;
  stop)
    log_debug "triggered by: $1"
  ;;
  lighttpd-restart)
    log_debug "triggered by: $1"
    sleep 2
  ;;
  firewall-start|firewall-restart)
    log_debug "triggered by: $1"
    sleep 2
  ;;
  *)
    log_debug "triggered by: $1"  
    exit 1
  ;;
esac

log_debug "END S50asuslighttpd trigger: $1"
exit 0
