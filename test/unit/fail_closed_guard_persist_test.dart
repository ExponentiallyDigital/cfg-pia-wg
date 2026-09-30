// test/unit/fail_closed_guard_persist_test.dart - the guard's cron follows the count the script
// reports, and is left alone when there is no count to follow (hostile review, ID-346).
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/fail_closed_guard.dart';

/// A router with the guard installed and its cron entry present; [output] is what guard.sh prints.
({FailClosedGuard guard, List<String> ran}) _router(String output) {
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

  return (guard: FailClosedGuard(read: read, run: run), ran: ran);
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

  test('a run that reports pinned devices keeps the cron', () async {
    final r = _router('guarded 2 of 2');
    expect(await r.guard.ensure(), 2);
    expect(r.ran, isNot(contains('cru d $kGuardCronTag')));
  });
}
