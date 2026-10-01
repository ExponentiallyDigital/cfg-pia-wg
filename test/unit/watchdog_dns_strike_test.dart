// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): the two-strike DNS rule.
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

    // ID-192. Found by hand at BRK-8: the strike file was written and then deleted in the same run.
    group('the two-strike DNS rule (ID-192)', () {
      test('one miss is a warning, not a rebuild', () async {
        h.dns('fail');
        await h.run();
        expect(h.log, contains('no answer from 9.9.9.9; one more and it counts as broken'));
        // The router's own resolver is logged after every run's checks, this one included (ID-194).
        expect(h.log.last, 'Router resolver OK');
        expect(h.dnsFailFile, '1');
        expect(h.curls, isEmpty);
      });

      test('a second miss in a row rebuilds the tunnel', () async {
        h.dns('fail');
        await h.run();
        await h.run();
        expect(h.log, contains('wgc1 is up and handshaking, but 9.9.9.9 has answered nothing twice in a row'));
        expect(h.log.any((l) => l.startsWith('Name resolution lost on wgc1; reconfiguring')), isTrue);
      });

      // ID-329: the rebuild was reported as fixing the DNS failure without asking the DNS server again.
      test('a rebuild after a DNS failure asks again, and says so when it still does not answer', () async {
        h.dns('fail');
        await h.run();
        await h.run();
        expect(h.log, contains('Rebuilt wgc1, but 9.9.9.9 still does not answer through it'));
      });

      test('a rebuild after a DNS failure that fixes it is reported as fixed, after asking', () async {
        h.dns('fail');
        await h.run();
        h.dnsFailsUntilRebuild();
        await h.run();
        expect(h.log.where((l) => l.contains('still does not answer')), isEmpty);
        expect(h.lookups.length, greaterThanOrEqualTo(3), reason: 'two misses, then the check after the rebuild');
      });

      test('an answer in between starts the count again', () async {
        h.dns('fail');
        await h.run();
        h.dns('ok');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
        h.dns('fail');
        await h.run();
        // The count started again: this miss is a first strike, a warning, not the second of a pair.
        expect(h.dnsFailFile, '1');
        expect(h.log.where((l) => l.contains('twice in a row')), isEmpty);
      });

      // BRK-9.
      test('a slot with no DNS server set skips the check and passes', () async {
        h.set('wgc1_dns', '');
        await h.run();
        expect(h.log, contains('No DNS server set on wgc1; skipping the name check'));
        expect(h.lookups, isEmpty);
        expect(h.backoffFile, '0\n0\n');
      });

      test('the probe asks through its own tunnel', () async {
        await h.run();
        expect(h.lookups.single, contains('dev wgc1'));
        expect(h.rules.where((r) => r.startsWith('1000:')), isEmpty, reason: 'its temporary rule is removed');
      });
    });
  }, skip: skip);
}
