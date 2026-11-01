// live/day_of_runs.dart: what LOG-9 makes of a watchdog's own log (ID-494).
import 'package:flutter_test/flutter_test.dart';

import '../../live/day_of_runs.dart';

const String _log = '''
2026-11-01 15:00:00 Watchdog started for wgc1 [script v0.8.183 build 553]
2026-11-01 15:00:02 This watchdog's last run reported a script error: [from build 553, not counted]
2026-11-01 16:20:00 Watchdog started for wgc1 [script v0.8.185 build 555]
2026-11-01 16:20:02 Router resolver OK
2026-11-01 16:24:59 ERROR: This watchdog's last run reported a script error: [LOG-8 test error]
2026-11-01 16:24:59 ERROR: This watchdog's last run reported a script error: [check-claims test error 1234]
2026-11-01 16:25:00 Watchdog started for wgc1 [script v0.8.185 build 555]
2026-11-02 16:29:59 ERROR: This watchdog's last run reported a script error: [wg: unknown command]
2026-11-02 16:30:00 Watchdog started for wgc1 [script v0.8.185 build 555]
''';

void main() {
  test('counts runs from build 554 on, and only their errors that no test left', () {
    final r = dayOfRuns(_log);
    expect(r.runs, 3);
    expect(r.first, DateTime(2026, 11, 1, 16, 20));
    expect(r.last, DateTime(2026, 11, 2, 16, 30));
    expect(r.errors, hasLength(1));
    expect(r.errors.single, contains('[wg: unknown command]'));
  });

  test('a log with nothing from build 554 on has no first run and no errors', () {
    final r = dayOfRuns(_log.split('\n').take(2).join('\n'));
    expect(r.first, isNull);
    expect(r.runs, 0);
    expect(r.errors, isEmpty);
  });

  test("the tests' own errors are known by their text", () {
    expect(deliberate('... [LOG-8 test error]'), isTrue);
    expect(deliberate('... [check-claims test error 99]'), isTrue);
    expect(deliberate('... [/tmp/cfgpia-live-485-end.sh: line 3012: cfgpia_test_fail_end: not found]'), isTrue);
    expect(deliberate('... [syntax error]'), isFalse);
  });

  test('a line time is read from its first 19 characters', () {
    expect(lineTime('2026-11-02 16:30:00 anything'), DateTime(2026, 11, 2, 16, 30));
    expect(lineTime('short'), isNull);
  });
}
