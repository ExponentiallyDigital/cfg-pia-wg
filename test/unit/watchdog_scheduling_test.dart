// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): skipped restarts, spacing, and runs that find their watchdog gone.
//
// Each group reproduces something found on hardware, so the fault it guards against can never come
// back unnoticed. Skipped where no POSIX shell is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) h = WatchdogHarness.create(shell: shell)!;
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  group('the watchdog on a stock router', () {

    // ID-214. Seen on 2026-09-21: the router was busy, dropped the restart, and the old peer's old
    // handshake passed every check after it. The rebuild was reported as a SUCCESS that never happened.
    group('a restart the router skips (ID-214)', () {
      test('is noticed, and tried once more', () async {
        h.tunnelUp(handshakeAgo: null);
        h.skipRestarts(1);
        await h.run();
        expect(h.log, contains('The router skipped the restart of wgc1; trying once more'));
        expect(h.services.where((s) => s == 'restart_vpnc'), hasLength(2));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
      });

      test('twice is a FAILED, never a SUCCESS', () async {
        h.tunnelUp(handshakeAgo: null);
        h.skipRestarts(2);
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(h.log.any((l) => l.startsWith('ERROR: the router skipped the restart of wgc1 twice')), isTrue);
        expect(h.log.where((l) => l.contains('SUCCESS')), isEmpty);
      });

      test('a ghost rc_service marker is cleared before the restart', () async {
        h.tunnelUp(handshakeAgo: null);
        h.set('rc_service', 'restart_vpnc');
        h.set('rc_service_pid', '999999');
        await h.run();
        expect(h.log.any((l) => l.startsWith('Cleared a stale rc_service marker (restart_vpnc, pid 999999)')), isTrue);
        expect(h.get('rc_service'), isEmpty);
        expect(h.log.last, startsWith('Reconfig SUCCESS'));
      });
    });

    // ID-227, measured 2026-09-27: watchdog runs packed into a few seconds crash the firmware's asd,
  // and every crash restarts the firewall. Spaced 15 s apart they did not.
  group('spacing the watchdogs out (ID-227)', () {
    Future<List<String>> sleepsFor(int slot, String mode) async {
      final w = WatchdogHarness.create(slot: slot, shell: shell)!;
      addTearDown(w.dispose);
      await w.run(mode: mode);
      return w.sleeps;
    }

    test('a cron start waits 15 s for every slot below it', () async {
      expect(await sleepsFor(5, 'detached'), contains('60'));
      expect(await sleepsFor(3, 'detached'), contains('30'));
    });

    test('wgc1 starts at once', () async {
      expect((await sleepsFor(1, 'detached')).where((s) => s != '1'), isEmpty,
          reason: 'only the one-second waits for the hand-over to init');
    });

    test('a deploy and a run by hand are never delayed', () async {
      expect(await sleepsFor(5, 'deploy'), isNot(contains('60')));
      expect(await sleepsFor(5, 'foreground'), isNot(contains('60')));
    });
  });

  // ID-240: found 2026-09-27. MANAGE DELETE removed wgc2's watchdog while its cron run was waiting
  // its 15 s, and the run woke and carried on: the shell already had the script open.
  group('a watchdog paused or removed while its run waits', () {
    test('a cron run whose schedule has gone stands down, having done nothing', () async {
      h.unschedule();
      final r = await h.run(mode: 'detached');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(h.log.last, "wgc1's watchdog was paused or removed while this run waited; standing down");
      expect(h.lookups, isEmpty);
      expect(h.curls, isEmpty);
    });

    test('a cron run that is still scheduled carries on', () async {
      await h.run(mode: 'detached');
      expect(h.log, contains('Checking wgc1 pia-nz connectivity'));
    });

    test('a run whose settings have gone stands down, rather than pinging nothing', () async {
      h.set('wgc1_wd_check_interval', '');
      await h.run();
      expect(h.log.last, 'wgc1 has no watchdog settings; standing down');
      expect(h.log.where((l) => l.contains('no Internet on WAN')), isEmpty);
    });

    test('a deploy runs whatever the schedule says: it is what writes the schedule', () async {
      h.unschedule();
      await h.run(mode: 'deploy');
      expect(h.log.where((l) => l.contains('standing down')), isEmpty);
    });
  });
  }, skip: skip);
}
