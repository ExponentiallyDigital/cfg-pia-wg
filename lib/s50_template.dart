// s50_template.dart - The stock-firmware cron-persistence script and its replacement-block editor.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Stock firmware has no services-start equivalent and `cru` entries do not survive a reboot or
// power cycle, so the app hijacks /opt/etc/init.d/S50downloadmaster — an unused script the
// firmware already runs at boot and on a firewall restart. Only the region between the
// REPLACEMENT markers is ever rewritten; everything else is copied through untouched.
//
// [kS50DownloadmasterTemplate] mirrors ./scripts/S50downloadmaster-TEMPLATE.sh verbatim (modulo
// line endings — the repo copy is CRLF, which would make the router's kernel fail to exec the
// shebang, so what ships here and what is deployed is LF). test/unit/s50_template_test.dart fails
// if the two drift apart.

const String _kStartMarker = '# ********** REPLACEMENT START **********';
const String _kEndMarker = '# ********** REPLACEMENT END **********';

/// Rebuilds the full script with [cruLines] sitting between the REPLACEMENT markers, indented to
/// match the marker's own indentation (the markers live inside a `case` arm).
String buildS50Script(List<String> cruLines) {
  final lines = kS50DownloadmasterTemplate.split('\n');
  final start = lines.indexWhere((l) => l.contains(_kStartMarker));
  final end = lines.indexWhere((l) => l.contains(_kEndMarker));
  if (start < 0 || end <= start) {
    throw StateError('The S50downloadmaster template is missing its REPLACEMENT markers.');
  }
  final indent = lines[start].substring(0, lines[start].indexOf('#'));
  return [
    ...lines.sublist(0, start + 1),
    for (final line in cruLines) '$indent$line',
    ...lines.sublist(end),
  ].join('\n');
}

/// The cru lines currently held between the REPLACEMENT markers of an already-deployed script.
/// Comments (the pristine template's placeholders) and blank lines are dropped, so a first deploy
/// onto an untouched template yields an empty list. Returns empty for anything unrecognisable —
/// a missing file reads as '' and is simply rebuilt from the template.
List<String> extractS50CruLines(String existingScript) {
  final lines = existingScript.split('\n');
  final start = lines.indexWhere((l) => l.contains(_kStartMarker));
  final end = lines.indexWhere((l) => l.contains(_kEndMarker));
  if (start < 0 || end <= start) return const [];
  return [
    for (final line in lines.sublist(start + 1, end))
      if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim(),
  ];
}

const String kS50DownloadmasterTemplate = r'''#!/bin/sh
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
''';
