// test/unit/grep_count_reads_test.dart - a `grep -c` the app sends the router ends `|| true` (ID-387).
//
// `grep -c` prints its count and exits 1 when the count is 0. The app logs every router read that
// exits non-zero as "router command failed" (router_command.dart), so a count of nothing - the
// common, healthy answer - showed up in APP LOG as a failure on every guard run: seen 2026-10-13,
// `router command failed (exit 1): cru l | grep -c '#cfg_pia_wg_guard#'`. `|| true` keeps the count
// on stdout and the exit at 0. Read from the source, because a fake router can't reproduce an exit
// code it was never told to return.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every line under lib/ that sends a `grep -c` as a command of its own and doesn't end it with
/// `|| true`. Comments don't count, and nor does one inside `$(...)` or a `[ ... ]` test in a
/// script the app writes: there the count is used and the exit status is not.
List<String> bareGrepCounts(Directory lib) => [
      for (final f in lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (line.contains('grep -c') &&
              !line.trimLeft().startsWith('//') &&
              !line.contains(r'$(') &&
              !line.contains('|| true'))
            '${f.path}:${i + 1}: ${line.trim()}',
    ];

void main() {
  test('every grep -c the app sends the router ends || true, so a count of nothing is not logged as a failure', () {
    expect(bareGrepCounts(Directory('lib')), isEmpty);
  });

  test('the scan finds one: a bare grep -c in a read is caught', () {
    final dir = Directory.systemTemp.createTempSync('grep_count_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a.dart').writeAsStringSync('''
// A comment saying grep -c is fine.
final a = read("cru l | grep -c '#x#'");
final b = read("cru l | grep -c '#x#' || true");
const s = r'[ "\$(echo "\$R" | grep -c "^91:")" = 1 ]';
''');
    expect(bareGrepCounts(dir), [contains('a.dart:2:')]);
  });
}
