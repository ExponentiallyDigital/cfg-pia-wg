// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): a healthy tunnel, the backoff ladder and a WAN outage.
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
    group('a healthy tunnel', () {
      test('is checked, passes, and resets the backoff', () async {
        h.backoff(3, 9999);
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log, contains('Checking wgc1 pia-nz connectivity'));
        expect(h.log.any((l) => l.startsWith('Handshake ')), isTrue);
        expect(h.backoffFile, '0\n0\n');
        expect(h.curls, isEmpty, reason: 'a healthy check asks PIA for nothing');
      });

      // ID-194: the router's own resolver, which every unpinned device depends on, gets a line of its
      // own on every run - and is never a reason to touch this tunnel.
      test("logs the router's own resolver as OK", () async {
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log, contains('Router resolver OK'));
      });

      test("a dead router resolver is logged, and the healthy tunnel is left alone", () async {
        h.routerResolverDown();
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log.any((l) => l.startsWith('Router resolver FAILED')), isTrue);
        expect(h.curls, isEmpty, reason: "no rebuild: it is not the tunnel's fault");
        expect(h.backoffFile, '0\n0\n');
      });

      test('a disabled slot stands down before any probe', () async {
        h.set('wgc1_enable', '0');
        await h.run();
        expect(h.log.last, 'wgc1 is disabled in the router; standing down until it is enabled again');
        expect(h.lookups, isEmpty);
      });
    });

    // BRK-6 on 2026-09-20 "failed" every rung because the test ran the script without a mode, so it
    // relaunched itself in the background and the test read the log before anything was written.
    // Run in the foreground, the ladder does what it says.
    group('the backoff ladder (ID-199)', () {
      const ladder = {1: 120, 2: 240, 3: 480, 4: 960, 5: 1800, 6: 3600, 7: 5400, 12: 5400};
      for (final e in ladder.entries) {
        test('after ${e.key} failed attempts a new check waits ${e.value}s, and asks PIA for nothing', () async {
          h.tunnelUp(handshakeAgo: null);
          h.backoff(e.key, 0);
          await h.run();
          expect(h.log.last,
              matches(RegExp('^Backing off after ${e.key} failed attempts: [0-9]+s of ${e.value}s elapsed\$')));
          expect(h.curls, isEmpty);
          expect(h.backoffFile.split('\n').first, '${e.key}', reason: 'a turned-away run leaves the count alone');
        });
      }
    });

    // BRK-7: a WAN outage is not the tunnel's fault and must not climb the ladder.
    test('a WAN outage exits without climbing the ladder', () async {
      h.tunnelUp(handshakeAgo: null);
      h.wan(false);
      h.backoff(2, 9999);
      await h.run();
      expect(h.log.last, 'no Internet on WAN interface, exiting.');
      expect(h.backoffFile.split('\n').first, '2');
    });
  }, skip: skip);
}
