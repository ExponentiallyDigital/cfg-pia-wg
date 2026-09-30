// test/unit/fail_closed_guard_persist_test.dart - the guard's cron follows the count the script
// reports, and is left alone when there is no count to follow (hostile review, ID-346).
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/fail_closed_guard.dart';

/// A router with the guard installed and its cron entry present; [output] is what guard.sh prints.
({FailClosedGuard guard, List<String> ran}) _router(String output, {List<(String, bool)>? logs}) {
  final ran = <String>[];
  Future<String> read(String cmd) async {
    if (cmd.startsWith('cat ') && cmd.contains('guard.sh')) return kGuardScript;
    if (cmd.contains("grep -c '#$kGuardCronTag#'")) return '1';
    return '';
  }

  Future<String> run(String cmd) async {
    ran.add(cmd);
    return cmd == "'$kGuardScriptPath'" ? output : '';
  }

  return (
    guard: FailClosedGuard(
        read: read,
        run: run,
        onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs?.add((m, isWarning))),
    ran: ran,
  );
}

void main() {
  test('a run whose output was lost leaves the cron in place', () async {
    for (final out in ['', 'Done.', 'guarded']) {
      final r = _router(out);
      expect(await r.guard.ensure(), isNull, reason: out);
      expect(r.ran, isNot(contains('cru d $kGuardCronTag')), reason: 'output "$out" says nothing about the pins');
    }
  });

  test('a run that reports no pinned devices removes the cron', () async {
    final r = _router('guarded 0 of 0');
    expect(await r.guard.ensure(), 0);
    expect(r.ran, contains('cru d $kGuardCronTag'));
  });

  // ID-348: what the script says about the router's Network Services Filter reaches the app log.
  group('the Network Services Filter', () {
    Future<List<(String, bool)>> logsFor(String out, {bool quiet = false}) async {
      final logs = <(String, bool)>[];
      await _router(out, logs: logs).guard.ensure(quiet: quiet);
      return [for (final l in logs) if (l.$1.contains('Network Services Filter')) l];
    }

    test('a refusal is a warning that says why, and what it costs', () async {
      final l = await logsFor('filter refused: it is an allow list, where listing a device would let it out\nguarded 1 of 1');
      expect(l.single.$2, isTrue);
      expect(l.single.$1, allOf(contains('allow list'), contains('few seconds after a restart')));
    });

    test('a filter short of some devices is a warning, even when quiet', () async {
      final l = await logsFor('filter held 1 of 2\nguarded 2 of 2', quiet: true);
      expect(l.single.$2, isTrue);
      expect(l.single.$1, contains('only 1 of 2'));
    });

    test('a filter holding every device is said once, and not when quiet', () async {
      expect((await logsFor('filter held 2 of 2\nguarded 2 of 2')).single.$2, isFalse);
      expect(await logsFor('filter held 2 of 2\nguarded 2 of 2', quiet: true), isEmpty);
    });

    test('a timetable on the filter is a warning', () async {
      final l = await logsFor('filter held 1 of 1\nfilter scheduled\nguarded 1 of 1', quiet: true);
      expect(l.single.$1, contains('timetable'));
      expect(l.single.$2, isTrue);
    });
  });

  test('a run that reports pinned devices keeps the cron', () async {
    final r = _router('guarded 2 of 2');
    expect(await r.guard.ensure(), 2);
    expect(r.ran, isNot(contains('cru d $kGuardCronTag')));
  });
}
