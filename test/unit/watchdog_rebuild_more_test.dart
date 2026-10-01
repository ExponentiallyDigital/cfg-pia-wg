// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): a rebuild, part two.
//
// Each group reproduces something found on hardware, so the fault it guards against can never come
// back unnoticed. Skipped where no POSIX shell is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cfg_pia_wg/router_watchdog.dart';
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
    group('a rebuild', () {

      // ID-222: the certificate download had no fallback, so a resolver problem stopped the rebuild
    // at its first step, and said "not valid PEM" when nothing had been downloaded at all.
    WatchdogConfig withDoh() => WatchdogConfig(
          slotIndex: 1,
          cronIntervalMinutes: 5,
          primaryIp: '8.8.8.8',
          secondaryIp: '1.1.1.1',
          piaUsername: 'p123456789',
          piaPassword: 'secret',
          dohUrl: 'https://freedns.controld.com/p1',
          dohIp: '76.76.2.1',
        );

    test('downloads the certificate when it has none', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      await h.run(config: withDoh());
      expect(h.log, contains(startsWith('CA cert cached at')));
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
    });

    // ID-331: a DELETE made while a rebuild was under way was undone by it - the run wrote enable=1
    // and restarted the tunnel the user had just removed.
    test('a watchdog deleted mid-rebuild stops the rebuild before it writes anything', () async {
      h.tunnelUp(handshakeAgo: null);
      h.deletedDuringRebuild();
      await h.run();
      expect(h.log, contains("wgc1's watchdog was deleted while this run was rebuilding; stopping before writing anything"));
      expect(h.nvramWrites.where((w) => w.startsWith('set wgc1_')), isEmpty);
      expect(h.services, isEmpty, reason: 'nothing restarted');
    });

    // The CA pin, as measured on ASUS's curl 2026-09-30: --cacert is honoured, so a cached file that
    // is not PIA's CA stops the rebuild at addKey rather than trusting whoever answered (ID-341).
    test('addKey refuses a server when the cached CA is not PIA\'s', () async {
      h.tunnelUp(handshakeAgo: null);
      File('${h.root.path}/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt')
          .writeAsStringSync('-----BEGIN CERTIFICATE-----\nSOMEONE-ELSE\n-----END CERTIFICATE-----\n');
      await h.run();
      expect(h.log, contains(startsWith('ERROR: curl addKey failed (exit 60')));
      expect(h.log.where((l) => l.startsWith('Reconfig SUCCESS')), isEmpty);
    });

    // What MRL-8 found on 2026-09-30 (ID-307): the router's own resolver is down, and because ASUS's
    // curl ignores --doh-url, "encrypted DNS" was never a way round it. The script's own lookup is.
    test('with the router resolver down, the rebuild still finds PIA through its own DoH lookups (ID-307)', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      h.systemDnsDown();
      await h.run(config: withDoh());
      expect(h.resolvedBySystem, isEmpty, reason: 'nothing asked of the ordinary resolver');
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
    });

    test('a DoH pair stored the wrong way round is named in the log, not passed off as none (ID-221)', () async {
      h.tunnelUp(handshakeAgo: null);
      await h.run(
          config: WatchdogConfig(
        slotIndex: 1,
        cronIntervalMinutes: 5,
        primaryIp: '8.8.8.8',
        secondaryIp: '1.1.1.1',
        piaUsername: 'p123456789',
        piaPassword: 'secret',
        dohUrl: '76.76.2.1',
        dohIp: 'https://freedns.controld.com/p1',
      ));
      expect(h.log, contains(startsWith('Name lookups are NOT encrypted: encrypted DNS is set')));
    });

    test('clears the DNS strike count', () async {
        h.tunnelUp(handshakeAgo: null);
        File('${h.root.path}/tmp/watchdog_dnsfail_wgc1').writeAsStringSync('1');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
      });
    });
  }, skip: skip);
}
