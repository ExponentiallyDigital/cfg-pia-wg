// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart).
//
// Each group reproduces something found on hardware, so the fault it guards against can never come
// back unnoticed. Skipped where no POSIX shell is on the PATH.
import 'dart:io';

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

    // ID-192. Found by hand at BRK-8: the strike file was written and then deleted in the same run.
    group('the two-strike DNS rule (ID-192)', () {
      test('one miss is a warning, not a rebuild', () async {
        h.dns('fail');
        await h.run();
        expect(h.log.last, 'no answer from 9.9.9.9; one more and it counts as broken');
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

      test('an answer in between starts the count again', () async {
        h.dns('fail');
        await h.run();
        h.dns('ok');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
        h.dns('fail');
        await h.run();
        expect(h.log.last, 'no answer from 9.9.9.9; one more and it counts as broken');
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

    // A broken tunnel is rebuilt on a new key, restarted through VPN Fusion, and confirmed.
    group('a rebuild', () {
      test('ends in SUCCESS on the new server', () async {
        h.tunnelUp(handshakeAgo: null);
        final r = await h.run();
        expect(r.exitCode, 0, reason: h.log.join('\n'));
        expect(h.get('wgc1_ppub'), 'NEWSERVERKEY');
        expect(h.services, contains('restart_vpnc'));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
      });

      test('on stock, restarts through VPN Fusion on its own clientlist row', () async {
        h.tunnelUp(handshakeAgo: null);
        await h.run();
        expect(h.log, contains('Restarting wgc1 through VPN Fusion (vpnc_unit=0)'));
        expect(h.get('vpnc_unit'), '0');
      });

      // BRK-3.
      test('an interface that is down is rebuilt, and comes back up', () async {
        h.tunnelDown();
        await h.run();
        expect(h.log, contains('Interface wgc1 is down or absent'));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
        expect(h.isUp, isTrue);
      });

      // BRK-3, second half: the interface on its own is not a success.
      test('one that never handshakes is a FAILED', () async {
        h.tunnelUp(handshakeAgo: null);
        h.neverHandshakes();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(h.log.last, 'ERROR: wgc1 came up but the PIA server never answered it (no handshake in 20s)');
      });

      // BRK-5.
      test('a rejected PIA login says so, and counts one attempt', () async {
        h.tunnelUp(handshakeAgo: null);
        h.piaRejects();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(
            h.log.any(
                (l) => l.startsWith('ERROR: PIA rejected the username and password stored on this router (HTTP 403)')),
            isTrue,
            reason: h.log.join('\n'));
        expect(h.backoffFile.split('\n').first, '1');
        expect(h.services, isEmpty, reason: 'nothing is written or restarted without a token');
      });

      test('clears the DNS strike count', () async {
        h.tunnelUp(handshakeAgo: null);
        File('${h.root.path}/tmp/watchdog_dnsfail_wgc1').writeAsStringSync('1');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
      });
    });

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

    // ID-193. Two watchdogs start in the same second, and each used to sweep away the other's
    // temporary DNS rule at the start of its run.
    group('two watchdogs at once (ID-193)', () {
      test("a run leaves another slot's probe rule alone", () async {
        h.addRule('1000:\tfrom all to 9.9.9.9 iif lo lookup 5');
        await h.run();
        expect(h.rules, contains('1000: from all to 9.9.9.9 iif lo lookup 5'));
      });

      test('a run clears its own leftover probe rule', () async {
        h.addRule('1000:\tfrom all to 9.9.9.9 iif lo lookup 9');
        await h.run();
        expect(h.rules.where((r) => r.startsWith('1000:')), isEmpty);
      });

      test('a probe waits for the one before it, and leaves no lock behind', () async {
        final lock = Directory('${h.root.path}/tmp/cfg-pia-wg-dnsprobe.lock')..createSync();
        final r = await h.run();
        expect(r.exitCode, 0, reason: h.log.join('\n'));
        expect(h.lookups, hasLength(1), reason: 'a lock that old was left by a killed run, and is broken');
        expect(lock.existsSync(), isFalse);
      });
    });
  }, skip: skip);
}
