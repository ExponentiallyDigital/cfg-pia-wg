// background_refresh_log.dart - when the phone let the widget refresh in the background, and what
// the refresh found (ID-424).
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
// iOS decides when an app gets background time, and nothing tells the app how often that will be.
// Each background run writes one line here, its time and outcome, and the app prints the last two
// days of them in its LOG screen as it starts, where they can be shared. Times and outcomes only:
// nothing read from the router is kept.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'widget_refresh.dart' show WidgetRefreshOutcome;

/// Filename under the app-support directory, beside router.txt.
const String kBackgroundRefreshLogFile = 'background_refresh.txt';

/// Lines kept. Android's fifteen-minute refresh writes about 100 a day, so this is several days there
/// and weeks at iOS's rate.
const int kBackgroundRefreshLogMax = 500;

/// How far back the LOG screen looks as the app starts.
const Duration kBackgroundRefreshLogShown = Duration(hours: 48);

/// One background run: when it started, and what [WidgetRefreshOutcome] it ended with.
class BackgroundRefreshEntry {
  const BackgroundRefreshEntry(this.at, this.outcome);

  final DateTime at;
  final WidgetRefreshOutcome outcome;
}

/// Reads and writes the run log. Like [RouterPrefs], it is inert under `flutter test` unless a test
/// passes [directory], and none of it ever throws: a log that can't be written must not stop a refresh.
class BackgroundRefreshLog {
  BackgroundRefreshLog({Future<Directory> Function()? directory})
      : _directory = directory ?? (Platform.environment.containsKey('FLUTTER_TEST') ? _inert : getApplicationSupportDirectory);

  static Future<Directory> _inert() async =>
      throw const FileSystemException('BackgroundRefreshLog stores nothing under flutter test - pass `directory` to test it');

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File('${(await _directory()).path}/$kBackgroundRefreshLogFile');

  /// Adds a line, keeping the newest [kBackgroundRefreshLogMax].
  Future<void> record(DateTime at, WidgetRefreshOutcome outcome) async {
    try {
      final f = await _file();
      final lines = await f.exists() ? await f.readAsLines() : <String>[];
      lines.add('${at.toUtc().toIso8601String()} ${outcome.name}');
      final kept = lines.length > kBackgroundRefreshLogMax ? lines.sublist(lines.length - kBackgroundRefreshLogMax) : lines;
      await f.writeAsString('${kept.join('\n')}\n');
    } catch (_) {
      // Nowhere to say so: this runs with no screen.
    }
  }

  /// Every run at or after [from], oldest first. Null when nothing was ever recorded, so the caller can
  /// tell "never set up" from "set up, and iOS gave no time". A line that doesn't parse is skipped.
  Future<List<BackgroundRefreshEntry>?> since(DateTime from) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final entries = <BackgroundRefreshEntry>[];
      for (final line in await f.readAsLines()) {
        final parts = line.split(' ');
        if (parts.length != 2) continue;
        final at = DateTime.tryParse(parts[0]);
        final outcome = WidgetRefreshOutcome.values.where((o) => o.name == parts[1]).firstOrNull;
        if (at == null || outcome == null || at.isBefore(from)) continue;
        entries.add(BackgroundRefreshEntry(at.toLocal(), outcome));
      }
      return entries;
    } catch (_) {
      return null;
    }
  }
}

/// What the LOG screen says about one outcome.
String backgroundRefreshOutcomeText(WidgetRefreshOutcome outcome) => switch (outcome) {
      WidgetRefreshOutcome.done => 'read the router',
      WidgetRefreshOutcome.locked => 'phone locked, nothing read',
      WidgetRefreshOutcome.unreachable => 'router not reached',
      WidgetRefreshOutcome.noKey => 'no widget key',
      WidgetRefreshOutcome.notSetUp => 'no router address or login',
      WidgetRefreshOutcome.noRecordedHostKey => 'no recorded host key',
      WidgetRefreshOutcome.failed => 'failed',
    };

/// The LOG screen's lines for [entries]: a count, then one line per run, `2026-10-25 03:12 read the
/// router`, in the phone's local time. Nothing at all for null, a phone that never ran one.
List<String> backgroundRefreshLogLines(List<BackgroundRefreshEntry>? entries) {
  if (entries == null) return const [];
  String two(int n) => n.toString().padLeft(2, '0');
  String when(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  final hours = kBackgroundRefreshLogShown.inHours;
  return [
    entries.isEmpty
        ? 'Background refreshes in the last $hours hours: none'
        : 'Background refreshes in the last $hours hours: ${entries.length}',
    for (final e in entries) '  ${when(e.at)} ${backgroundRefreshOutcomeText(e.outcome)}',
  ];
}
