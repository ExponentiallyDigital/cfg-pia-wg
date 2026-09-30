// The watchdog's own encrypted lookups (ID-307).
//
// ASUS's curl ignores --doh-url on both firmwares (measured 2026-09-30), so every lookup the
// watchdog called encrypted since ID-076 had gone out as ordinary DNS. The script now sends the DNS
// query itself and gives curl the answer with --resolve. These tests run the real awk program on
// real answers captured from Cloudflare and Google that day, and the real script against the
// harness's DoH server - including the ones where the DoH server fails, which is the only way to
// see that "encrypted" is observed and not assumed.
import 'dart:convert';
import 'dart:io';

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

  group('the answer reader (kDohAnswerAwk), run by awk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('doh_awk_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<ProcessResult> read(List<int> answer) async {
      final f = File('${dir.path}/a.b64')..writeAsStringSync('${base64.encode(answer)}\n');
      return Process.run(shell!, ['-c', r'awk "$1" "$2"', 'sh', kDohAnswerAwk, f.path.replaceAll('\\', '/')]);
    }

    test('reads the first address from Cloudflare\'s and Google\'s real answers', () async {
      for (final a in [cloudflare, google]) {
        final r = await read(a);
        expect(r.exitCode, 0);
        expect((r.stdout as String).trim(), '172.64.147.163');
      }
    });

    test('an answer that says FORMERR gives nothing', () async {
      final r = await read(formErr);
      expect(r.exitCode, isNot(0));
      expect((r.stdout as String).trim(), isEmpty);
    });

    test('Cloudflare\'s HTML error page gives nothing', () async {
      final r = await read(ascii.encode('<html>\r\n<head><title>400 Bad Request</title></head>\r\n</html>\r\n'));
      expect((r.stdout as String).trim(), isEmpty);
    });

    test('an answer cut short gives nothing, rather than reading past the end', () async {
      // Every cut before the first address ends (byte 63); a cut after it still holds it whole.
      for (final cut in [10, 20, 47, 55, 62]) {
        final r = await read(cloudflare.sublist(0, cut));
        expect((r.stdout as String).trim(), isEmpty, reason: 'cut at $cut');
      }
    });

    test('a query sent back without the response bit gives nothing', () async {
      final r = await read([...cloudflare.sublist(0, 2), 0x01, 0x00, ...cloudflare.sublist(4)]);
      expect((r.stdout as String).trim(), isEmpty);
    });

    test('a CNAME before the address is followed to the address', () async {
      final r = await read([
        0, 0, 0x81, 0x80, 0, 1, 0, 2, 0, 0, 0, 0,
        7, ...ascii.encode('example'), 3, ...ascii.encode('com'), 0, 0, 1, 0, 1,
        0xc0, 0x0c, 0, 5, 0, 1, 0, 0, 0, 60, 0, 5, 1, 0x61, 1, 0x62, 0, // CNAME a.b
        1, 0x61, 1, 0x62, 0, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 192, 0, 2, 7, // a.b A 192.0.2.7
      ]);
      expect((r.stdout as String).trim(), '192.0.2.7');
    });

    test('an answer with no A record gives nothing', () async {
      final r = await read([
        0, 0, 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0,
        7, ...ascii.encode('example'), 3, ...ascii.encode('com'), 0, 0, 28, 0, 1,
        0xc0, 0x0c, 0, 28, 0, 1, 0, 0, 0, 60, 0, 16, ...List.filled(16, 1),
      ]);
      expect((r.stdout as String).trim(), isEmpty);
    });

    test('holds no single quote, since the script carries it inside one', () {
      expect(kDohAnswerAwk, isNot(contains("'")));
    });
  }, skip: shell == null ? 'no POSIX shell' : false);

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

    test('with the router resolver down, every PIA name is found over DoH and the rebuild succeeds', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      h.systemDnsDown();
      await h.run(config: withDoh());
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
      expect(h.dohNames, piaHosts);
      expect(h.resolvedBySystem, isNot(anyElement(isIn(piaHosts))), reason: 'no PIA name asked of the ordinary resolver');
      for (final host in piaHosts) {
        expect(h.resolvedByResolve, contains(host));
        expect(h.log, contains('Looked up $host over encrypted DNS via security.cloudflare-dns.com (1.1.1.2)'));
      }
    });

    test('the query is a standard DNS query for the name, byte for byte', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      await h.run(config: withDoh());
      expect(h.dohQueries.first, queryFor('raw.githubusercontent.com'));
      expect(h.dohQueries[1], queryFor('www.privateinternetaccess.com'));
    });

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

    test('with no DoH server set, it says the lookups are not encrypted and asks none', () async {
      h.tunnelUp(handshakeAgo: null);
      await h.run();
      expect(h.log, contains('Name lookups are NOT encrypted (no DoH resolver configured)'));
      expect(h.dohNames, isEmpty);
    });

    test('the PIA username is not in the log, which FAILED emails quote (ID-322)', () async {
      h.tunnelUp(handshakeAgo: null);
      h.piaRejects();
      await h.run(config: withDoh());
      expect(h.log.join('\n'), isNot(contains('p123456789')));
    });

    test('curl\'s command-line log on flash is emptied after the lookups (ID-321)', () async {
      final curllst = File('${h.root.path}/jffs/curllst')..writeAsStringSync('curl -u p123456789:secret https://x\n');
      h.tunnelUp(handshakeAgo: null);
      await h.run(config: withDoh());
      expect(curllst.readAsStringSync(), isEmpty);
    });
  }, skip: shell == null ? 'no POSIX shell' : false);
}
