// router_log_paging.dart - reading a very large router log backwards, in pages.
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
// `/tmp/syslog.log` reached 512 KB on the maintainer's router in a day, and the firmware rotates it
// to `syslog.log-1` rather than truncating - so the history a user wants can span two files and
// three quarters of a megabyte. Pulling all of that over SSH and putting it in one text widget on a
// phone is not something to do on screen entry.
//
// So it is read in pages, newest first, and older pages are fetched only when the reader scrolls
// back far enough to need them. The paging is pure so it can be tested without a router: this file
// decides WHICH bytes to ask for, and the screen does the asking.
import 'dart:math';

/// One page. 32 KB is roughly 400-600 lines of the router's log - a comfortable screen's worth of
/// scrollback, and small enough that fetching one is not felt.
const int kLogPageBytes = 32768;

/// The live log, then the rotated one. Both are read the same way; the second simply continues
/// where the first runs out, which is what makes "scroll back far enough" reach yesterday.
const List<String> kRouterLogFiles = ['/tmp/syslog.log', '/tmp/syslog.log-1'];

/// Asks the router for the size of each log file that exists, in one round trip.
///
/// A file that is absent contributes nothing rather than an error: the rotated log only appears
/// once the live one has filled up at least once, so its absence is the ordinary case on a router
/// that rebooted recently.
String buildLogSizesCommand([List<String> files = kRouterLogFiles]) =>
    files.map((f) => "[ -f '$f' ] && wc -c < '$f' || echo 0").join('; ');

/// Parses [buildLogSizesCommand]'s output: one byte count per line, in the order asked for.
List<int> parseLogSizes(String raw, {int expected = 2}) {
  final out = <int>[];
  for (final line in raw.split('\n')) {
    final n = int.tryParse(line.trim());
    if (n != null) out.add(n);
  }
  while (out.length < expected) {
    out.add(0);
  }
  return out.take(expected).toList();
}

/// Which bytes of which file a page covers.
/// Who wrote a syslog line, as far as this app can tell.
enum RouterLogSource {
  /// Neither this app nor its watchdog - the firmware, the kernel, dropbear, everything else.
  other,

  /// This app, over SSH.
  app,

  /// The watchdog script running on the router.
  watchdog,
}

/// Both the app and the deployed watchdog write to syslog under the tag `cfg-pia-wg`. The script
/// prefixes every line with its interface, and that prefix is the only thing separating them:
///
/// ```text
/// cfg-pia-wg: wgc1: Checking wgc1 pia-region_name connectivity   <- the watchdog, on the router
/// cfg-pia-wg: Laptop (192.168.1.20) -> wgc5 reassigned           <- this app, over SSH
/// ```
///
/// Giving the script a tag of its own would be unambiguous, but a tag change only reaches a router
/// on the next watchdog deploy, so every router already in the field would go on emitting the old
/// one. This costs nothing and works today.
RouterLogSource classifyLogLine(String line) {
  final m = _tagPattern.firstMatch(line);
  if (m == null) return RouterLogSource.other;
  return m.group(1) == null ? RouterLogSource.app : RouterLogSource.watchdog;
}

final RegExp _tagPattern = RegExp(r'cfg-pia-wg:\s*(wgc\d+:)?');

class LogPage {
  const LogPage({required this.file, required this.fromEnd, required this.length, required this.reachesStart});

  /// The file to read.
  final String file;

  /// How many bytes from the END of that file this page ENDS at. Page 0 ends at the end.
  final int fromEnd;

  /// How many bytes this page holds.
  final int length;

  /// True when this page reaches byte 0 of its file, so the file has nothing older left.
  final bool reachesStart;

  /// The command that fetches it, doing the work on the router so only [length] bytes cross SSH.
  ///
  /// `tail -c N | head -c M` rather than `dd` or `tail -c +N`: BusyBox has both of these and they
  /// need no arithmetic on the router. Asking for more bytes than a file holds is not an error -
  /// tail simply returns the whole file - which is what makes the last page of a file safe.
  String get command => "tail -c ${fromEnd + length} '$file' 2>/dev/null | head -c $length";
}

/// The next page to fetch, or null when there is nothing older to read.
///
/// [consumed] is how many bytes have already been read from each file, in the order of [sizes].
/// Pages walk backwards through the first file, then backwards through the second.
LogPage? nextLogPage({required List<int> sizes, required List<int> consumed, List<String> files = kRouterLogFiles}) {
  for (var i = 0; i < files.length && i < sizes.length; i++) {
    final size = sizes[i];
    final done = i < consumed.length ? consumed[i] : 0;
    if (done >= size) continue; // this file is exhausted, fall through to the older one
    final length = min(kLogPageBytes, size - done);
    return LogPage(
      file: files[i],
      fromEnd: done,
      length: length,
      reachesStart: done + length >= size,
    );
  }
  return null;
}

/// Drops the leading partial line from a page.
///
/// Every page except the one that reaches the start of its file begins mid-line, because the cut is
/// made at a byte offset rather than a line boundary. Showing that fragment would put half a
/// timestamp at the top of the screen and make the page above it look corrupt.
String trimPartialFirstLine(String page, {required bool reachesStart}) {
  if (reachesStart) return page;
  final nl = page.indexOf('\n');
  return nl < 0 ? '' : page.substring(nl + 1);
}
