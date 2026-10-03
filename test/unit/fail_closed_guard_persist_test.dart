// test/unit/fail_closed_guard_persist_test.dart - what FailClosedGuard.ensure does to keep the guard
// running without the app: the boot hook kept current, and the per-minute cron entry of builds 480
// to 490 taken out (ID-364); and nothing changed when there is no count to go on (hostile review,
// ID-346).
import 'package:cfg_pia_wg/firmware.dart' show kS50Path;
import 'package:cfg_pia_wg/router_watchdog.dart' show writtenByteCount;
import 'package:cfg_pia_wg/s50_template.dart' show buildS50Script;
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/fail_closed_guard.dart';

const _check = 'cru a watchdog_wgc5 "*/5 * * * *" /jffs/cfg-pia-wg/watchdog_wgc5.sh';

/// The cron line builds 480 to 490 put in the boot hook to run the guard every minute (ID-316), as a
/// router still on one of them holds it. Nothing writes it any more (ID-364).
const kLegacyGuardCronLine = 'cru a $kLegacyGuardCronTag "* * * * *" $kGuardScriptPath';

/// A router with the guard installed, the old per-minute cron entry still running, and [hook] as its
/// boot hook. [output] is what guard.sh prints. [writes] is the hook body the router is expected to
/// end up holding, so the size check after a write passes when the right thing was written.
({FailClosedGuard guard, List<String> ran}) _router(
  String output, {
  String hook = '',
  String writes = '',
  List<(String, bool)>? logs,
}) {
  final ran = <String>[];
  Future<String> read(String cmd) async {
    if (cmd.startsWith('cat ') && cmd.contains('guard.sh')) return kGuardScript;
    if (cmd.contains("grep -c '#$kLegacyGuardCronTag#'")) return '1';
    if (cmd.startsWith("cat '$kS50Path'")) return hook;
    if (cmd.contains('[ -d ')) return 'yes';
    if (cmd.startsWith('wc -c') && cmd.contains(kS50Path)) return '${writtenByteCount(writes)}';
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

bool _wroteHook(List<String> ran) => ran.any((x) => x.contains(kS50Path) && x.contains('WATCHDOG_EOF'));

void main() {
  test('a run whose output was lost changes nothing', () async {
    for (final out in ['', 'Done.', 'guarded']) {
      final r = _router(out, hook: buildS50Script([kLegacyGuardCronLine, _check]));
      expect(await r.guard.ensure(), isNull, reason: out);
      expect(r.ran, isNot(contains('cru d $kLegacyGuardCronTag')), reason: 'output "$out" says nothing about the pins');
      expect(_wroteHook(r.ran), isFalse);
    }
  });

  group('the per-minute cron entry of builds 480 to 490 (ID-364)', () {
    for (final out in ['guarded 0 of 0', 'guarded 2 of 2']) {
      test('is taken out after "$out"', () async {
        final r = _router(out);
        await r.guard.ensure();
        expect(r.ran, contains('cru d $kLegacyGuardCronTag'));
        expect(r.ran.where((x) => x.startsWith('cru a')), isEmpty, reason: 'nothing schedules the guard any more');
      });
    }

    test("and its line goes from the boot hook, the watchdog's kept", () async {
      final r = _router('guarded 1 of 1', hook: buildS50Script([kLegacyGuardCronLine, _check]), writes: buildS50Script([_check]));
      await r.guard.ensure();
      expect(_wroteHook(r.ran), isTrue);
      final written = r.ran.where((x) => x.contains(kS50Path) && x.contains('WATCHDOG_EOF')).join('\n');
      expect(written, isNot(contains('cru a $kLegacyGuardCronTag')));
      expect(written, contains(_check));
      expect(written, contains('guard.sh soon'), reason: 'the hook that replaces it runs the guard on firewall-start');
    });
  });

  group('the boot hook', () {
    test('one that is already current is left alone', () async {
      final r = _router('guarded 1 of 1', hook: buildS50Script([_check]));
      await r.guard.ensure();
      expect(_wroteHook(r.ran), isFalse);
    });

    test("with nothing pinned, the router's own script is left alone", () async {
      final r = _router('guarded 0 of 0', hook: '#!/bin/sh\n# the stock Download Master script\n');
      await r.guard.ensure();
      expect(_wroteHook(r.ran), isFalse);
    });

    test("with a device pinned, the app's replaces the router's own, which is kept", () async {
      final r = _router('guarded 1 of 1',
          hook: '#!/bin/sh\n# the stock Download Master script\n', writes: buildS50Script(const []));
      await r.guard.ensure();
      expect(_wroteHook(r.ran), isTrue);
    });
  });

  // ID-348: what the script says about the router's Network Services Filter reaches the app log.
  group('the Network Services Filter', () {
    Future<List<(String, bool)>> logsFor(String out, {bool quiet = false}) async {
      final logs = <(String, bool)>[];
      await _router(out, hook: buildS50Script(const []), logs: logs).guard.ensure(quiet: quiet);
      return [for (final l in logs) if (l.$1.contains('Network Services Filter')) l];
    }

    test('a refusal is a warning that says why, and what it costs', () async {
      final l = await logsFor('filter refused: it is an allow list, where listing a device would let it out\nguarded 1 of 1');
      expect(l.single.$2, isTrue);
      expect(l.single.$1, allOf(contains('allow list'), contains('first half-minute')));
    });

    test('a filter short of some devices is a warning, even when quiet', () async {
      final l = await logsFor('filter held 1 of 2\nguarded 2 of 2', quiet: true);
      expect(l.single.$2, isTrue);
      expect(l.single.$1, allOf(contains('only 1 of 2'), contains('restarts its firewall')));
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
}
