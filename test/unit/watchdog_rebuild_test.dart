// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): a rebuild, part one.
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

      // Hostile review (ID-346): the login was on curl's command line, which ASUS's curl writes to
      // /jffs/curllst on flash and ps shows. It goes on stdin now.
      test('sends the PIA login on stdin, never on curl\'s command line', () async {
        h.tunnelUp(handshakeAgo: null);
        await h.run();
        expect(h.log.last, startsWith('Reconfig SUCCESS'));
        expect(h.tokenAuth, ['p123456789:secret'], reason: 'the login reached PIA');
        expect(h.curlArgv.where((a) => a.contains('secret') || a.contains('p123456789')), isEmpty);
      });

      test('a password with a quote and a backslash reaches PIA intact', () async {
        h
          ..set('cfg_pia_wg_password', r'pa"ss\wd')
          ..tunnelUp(handshakeAgo: null);
        await h.run();
        expect(h.tokenAuth.first, r'p123456789:pa"ss\wd');
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
      // ID-245: the email said "failed to obtain PIA token (exit 0, HTTP 504, body 16B: error code:
      // 504)", which reads as the router's fault.
      test("PIA's login service being down is named as PIA's, not the login's", () async {
        h.tunnelUp(handshakeAgo: null);
        h.piaDown();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(
            h.log,
            contains("ERROR: PIA's login service isn't answering (HTTP 504). This is at PIA's end; "
                'the watchdog will try again.'));
        expect(h.log.where((l) => l.contains('rejected the username')), isEmpty);
      });

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
    });
  }, skip: skip);
}
