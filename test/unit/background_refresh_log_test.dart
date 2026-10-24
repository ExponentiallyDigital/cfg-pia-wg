// test/unit/background_refresh_log_test.dart - the record of background refreshes an iPhone was
// given, and what the LOG screen says about them (ID-424).
import 'dart:io';

import 'package:cfg_pia_wg/background_refresh_log.dart';
import 'package:cfg_pia_wg/widget_refresh.dart' show WidgetRefreshOutcome;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late BackgroundRefreshLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bg_refresh_log');
    log = BackgroundRefreshLog(directory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File file() => File('${dir.path}/$kBackgroundRefreshLogFile');

  test('nothing ever recorded reads as null, not as no runs', () async {
    expect(await log.since(DateTime(2000)), isNull);
  });

  test('runs read back oldest first, in local time, from the time asked', () async {
    final first = DateTime.utc(2026, 10, 24, 1);
    final second = DateTime.utc(2026, 10, 25, 3, 12);
    await log.record(first, WidgetRefreshOutcome.unreachable);
    await log.record(second, WidgetRefreshOutcome.done);

    final all = (await log.since(DateTime.utc(2026, 10, 1)))!;
    expect([for (final e in all) e.at], [first.toLocal(), second.toLocal()]);
    expect([for (final e in all) e.outcome], [WidgetRefreshOutcome.unreachable, WidgetRefreshOutcome.done]);

    expect((await log.since(DateTime.utc(2026, 10, 25)))!.single.at, second.toLocal());
    expect(await log.since(DateTime.utc(2026, 10, 26)), isEmpty, reason: 'recorded once, so empty rather than null');
  });

  test('only the time and the outcome are written', () async {
    await log.record(DateTime.utc(2026, 10, 25, 3, 12), WidgetRefreshOutcome.locked);
    expect(file().readAsStringSync(), '2026-10-25T03:12:00.000Z locked\n');
  });

  test('the newest $kBackgroundRefreshLogMax runs are kept', () async {
    final start = DateTime.utc(2026, 10, 1);
    for (var i = 0; i < kBackgroundRefreshLogMax + 3; i++) {
      await log.record(start.add(Duration(minutes: 15 * i)), WidgetRefreshOutcome.done);
    }
    final lines = file().readAsLinesSync();
    expect(lines, hasLength(kBackgroundRefreshLogMax));
    expect(lines.first, startsWith(start.add(const Duration(minutes: 45)).toIso8601String()));
  });

  test("a line that doesn't parse is skipped, not fatal", () async {
    file().writeAsStringSync('rubbish\n2026-10-25T03:12:00.000Z unknownOutcome\nnot-a-date done\n2026-10-25T04:00:00.000Z done\n');
    final entries = (await log.since(DateTime(2000)))!;
    expect(entries.single.outcome, WidgetRefreshOutcome.done);
  });

  test('a directory that fails neither throws nor records', () async {
    final broken = BackgroundRefreshLog(directory: () async => throw const FileSystemException('no'));
    await broken.record(DateTime(2026), WidgetRefreshOutcome.done);
    expect(await broken.since(DateTime(2000)), isNull);
  });

  test('under flutter test, the default directory is inert', () async {
    await BackgroundRefreshLog().record(DateTime(2026), WidgetRefreshOutcome.done);
    expect(await BackgroundRefreshLog().since(DateTime(2000)), isNull);
  });

  group('the LOG screen lines', () {
    test('nothing for a phone that never ran one', () {
      expect(backgroundRefreshLogLines(null), isEmpty);
    });

    test('says none when set up but given no time', () {
      expect(backgroundRefreshLogLines([]), ['Background refreshes in the last 48 hours: none']);
    });

    test('a count, then each run in local time with what it found', () {
      final lines = backgroundRefreshLogLines([
        BackgroundRefreshEntry(DateTime(2026, 10, 25, 3, 7), WidgetRefreshOutcome.locked),
        BackgroundRefreshEntry(DateTime(2026, 10, 25, 14, 30), WidgetRefreshOutcome.done),
      ]);
      expect(lines, [
        'Background refreshes in the last 48 hours: 2',
        '  2026-10-25 03:07 phone locked, nothing read',
        '  2026-10-25 14:30 read the router',
      ]);
    });

    test('every outcome has its own words', () {
      final words = {for (final o in WidgetRefreshOutcome.values) backgroundRefreshOutcomeText(o)};
      expect(words, hasLength(WidgetRefreshOutcome.values.length));
    });
  });
}
