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
exit 0''';
