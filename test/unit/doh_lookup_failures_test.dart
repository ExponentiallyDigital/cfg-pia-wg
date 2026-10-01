// The watchdog's own encrypted lookups (ID-307). Part of the lookups against the harness DoH server: when the DoH server fails.
//
// ASUS's curl ignores --doh-url on both firmwares (measured 2026-09-30), so every lookup the
// watchdog called encrypted since ID-076 had gone out as ordinary DNS. The script now sends the DNS
// query itself and gives curl the answer with --resolve. These tests run the real awk program on
// real answers captured from Cloudflare and Google that day, and the real script against the
// harness's DoH server - including the ones where the DoH server fails, which is the only way to
// see that "encrypted" is observed and not assumed.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

List<int> hex(String s) => [for (final h in s.trim().split(RegExp(r'\s+'))) int.parse(h, radix: 16)];

// www.privateinternetaccess.com, type A, from Cloudflare (1.1.1.2) and Google (8.8.8.8), 2026-09-30.
final cloudflare = hex('00 00 81 80 00 01 00 02 00 00 00 00 03 77 77 77 15 70 72 69 76 61 74 65 69 6e 74 65 72 6e 65 74 '
    '61 63 63 65 73 73 03 63 6f 6d 00 00 01 00 01 c0 0c 00 01 00 01 00 00 00 26 00 04 ac 40 93 a3 c0 0c 00 01 00 01 00 00 '
    '00 26 00 04 68 12 28 5d');
final google = hex('00 00 81 80 00 01 00 02 00 00 00 00 03 77 77 77 15 70 72 69 76 61 74 65 69 6e 74 65 72 6e 65 74 '
    '61 63 63 65 73 73 03 63 6f 6d 00 00 01 00 01 c0 0c 00 01 00 01 00 00 01 2c 00 04 ac 40 93 a3 c0 0c 00 01 00 01 00 00 '
    '01 2c 00 04 68 12 28 5d');
// Google's answer to the malformed query I sent first that day: FORMERR, no question, no answer.
final formErr = hex('00 00 81 01 00 00 00 00 00 00 00 00');

/// The query the script must send for [name]: header, the name as labels, type A, class IN.
List<int> queryFor(String name) => [
      0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
      for (final l in name.split('.')) ...[l.length, ...ascii.encode(l)],
      0, 0, 1, 0, 1,
    ];

void main() {
  final shell = findShell();

  group('the watchdog\'s lookups, against the harness DoH server', () {
    late WatchdogHarness h;
    setUp(() => h = WatchdogHarness.create()!);
    tearDown(() => h.dispose());

    WatchdogConfig withDoh() => const WatchdogConfig(
          slotIndex: 1,
          cronIntervalMinutes: 5,
          primaryIp: '8.8.8.8',
          secondaryIp: '1.1.1.1',
          piaUsername: 'p123456789',
          piaPassword: 'secret',
          dohUrl: 'https://security.cloudflare-dns.com/dns-query',
          dohIp: '1.1.1.2',
        );

    const piaHosts = ['raw.githubusercontent.com', 'www.privateinternetaccess.com', 'serverlist.piaservers.net'];


    // The negative check the rule asks for: break the DoH path and the log must say the lookups
    // were NOT encrypted. Before ID-307 the log said "encrypted" whatever the DoH server did.
    for (final (label, breakIt) in [
      ('is down', (WatchdogHarness x) => x.dohDown()),
      ('answers FORMERR', (WatchdogHarness x) => x.dohFormErr()),
      ('answers an HTML error page', (WatchdogHarness x) => x.dohHtml()),
    ]) {
      test('a DoH server that $label is said so, and ordinary DNS is used instead', () async {
        h.tunnelUp(handshakeAgo: null);
        h.noCachedCert();
        breakIt(h);
        await h.run(config: withDoh());
        expect(h.log.last, startsWith('Reconfig SUCCESS'), reason: 'the tunnel still gets rebuilt');
        expect(h.log.where((l) => l.startsWith('Looked up')), isEmpty, reason: 'nothing claims to be encrypted');
        for (final host in piaHosts) {
          expect(h.log, contains('Encrypted lookup of $host via security.cloudflare-dns.com (1.1.1.2) failed; '
              'it will be looked up with ordinary DNS'));
          expect(h.resolvedBySystem, contains(host));
        }
      });
    }

  }, skip: shell == null ? 'no POSIX shell' : false);
}
