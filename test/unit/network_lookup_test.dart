// test/unit/network_lookup_test.dart - NETWORK's lookups (ID-458): the service's reply read, the
// phone's own request, and the router command run for real against a fake stock router.
//
// What matters for a tunnel row can't be seen from the command text: that a route the rule didn't
// change is NOROUTE and no request is sent at all - one that answered by the WAN would show the ISP's
// address as the tunnel's - and that no rule is ever left behind. The stand-in `ip` is ENABLE's
// (enable_ping_test.dart): rules kept in a file, table 10 - slot is wgc<slot>.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

// PIA's site-api/get-location-info, with every field it sent on 2026-10-25.
const _reply = '{"ip":"203.0.113.9","cc":"AU","cn":"Australia","cty":"Melbourne","pc":"3000","lat":-37.8,"lng":144.9,'
    '"isp":"Example Provider","rgn":"Victoria","org":"Example Org"}';

const _ip = r'''#!/bin/sh
case "$1 $2" in
  "rule add") echo "$4 $8" >> "$STATE/rules" ;;
  "rule del") grep -qx "$4 $8" "$STATE/rules" 2>/dev/null || exit 2
    grep -vx "$4 $8" "$STATE/rules" > "$STATE/r.new"; mv "$STATE/r.new" "$STATE/rules" ;;
  "route get")
    t="$(awk -v ip="$3" '$1 == ip {print $2; exit}' "$STATE/rules" 2>/dev/null)"
    if [ -n "$t" ] && [ ! -f "$STATE/rule_ignored_$((10 - t))" ]; then echo "$3 dev wgc$((10 - t))  src 10.0.0.4 "
    else echo "$3 via 198.51.100.1 dev eth0  src 198.51.100.7 "; fi ;;
esac
exit 0
''';

// Records each call, with the rules in force at the time, and answers as PIA does.
const _curl = r'''#!/bin/sh
echo "$* | rules: $(cat "$STATE/rules" 2>/dev/null | tr '\n' ' ')" >> "$STATE/curls"
[ -f "$STATE/curl_fails" ] && exit 28
printf '%s\n' "$REPLY"
''';

void main() {
  group('PIA', () {
    const p = PiaLookup();

    test('reads the address, country, town and provider', () {
      final f = p.parse(_reply)!;
      expect([f.ip, f.country, f.city, f.provider], ['203.0.113.9', 'Australia', 'Melbourne', 'Example Provider']);
    });

    test('a reply without an address, or not JSON, is not an answer', () {
      expect(p.parse('{"cn":"Australia"}'), isNull);
      expect(p.parse('<html>blocked</html>'), isNull);
    });

    test('is the service in use (Andrew, 2026-10-25), on PIA\'s own site', () {
      expect(kIpLookupService, isA<PiaLookup>());
      expect(kIpLookupService.host, 'www.privateinternetaccess.com');
      expect(kIpLookupService.sourceUrl, 'https://www.privateinternetaccess.com/what-is-my-ip');
    });
  });

  group('this device', () {
    test('asks the service over HTTPS and reads its answer', () async {
      Uri? asked;
      final facts = await lookUpThisPhone(client: MockClient((req) async {
        asked = req.url;
        return http.Response(_reply, 200);
      }));
      expect(asked.toString(), 'https://www.privateinternetaccess.com/site-api/get-location-info');
      expect(facts.ip, '203.0.113.9');
    });

    test('an error status or an unreadable answer throws', () async {
      expect(() => lookUpThisPhone(client: MockClient((_) async => http.Response('', 503))), throwsException);
      expect(() => lookUpThisPhone(client: MockClient((_) async => http.Response('nope', 200))), throwsException);
    });
  });

  group("the router's address for the service", () {
    Future<List<InternetAddress>> answers(List<String> a) async => [for (final s in a) InternetAddress(s)];

    test('the first IPv4 address below 128.0.0.0', () async {
      expect(await tunnelLookupAddress(lookup: (_) => answers(['2606:4700::6812:285d', '172.64.147.163', '104.18.40.93'])), '104.18.40.93');
    });

    test('none when every address is above what the tunnel table carries', () async {
      expect(await tunnelLookupAddress(lookup: (_) => answers(['185.65.135.1'])), isNull);
    });

    test('none when DNS fails', () async {
      expect(await tunnelLookupAddress(lookup: (_) async => throw const SocketException('no DNS')), isNull);
    });
  });

  test('the command refuses anything but an IPv4 address', () {
    expect(() => tunnelLookupCommand([1], '104.18.40.93; reboot', stock: true), throwsArgumentError);
    expect(() => tunnelLookupCommand([1], 'www.privateinternetaccess.com', stock: true), throwsArgumentError);
  });

  test("Merlin binds the request to the tunnel, as its ENABLE ping does", () {
    final cmd = tunnelLookupCommand([2], '104.18.40.93', stock: false);
    expect(cmd, contains('--interface "wgc\$N"'));
    expect(cmd, isNot(contains('ip rule')));
  });

  group('parsing the reply', () {
    test('each slot found, unroutable or failed; a slot missing from the reply failed', () {
      final raw = '\n${kTunnelLookupMarker}1\n$_reply\n\n${kTunnelLookupMarker}2\n@@NOROUTE\n\n${kTunnelLookupMarker}3\ncurl: (28)\n@@FAIL\n';
      final r = parseTunnelLookups(raw, [1, 2, 3, 5]);
      expect(r[1]!.outcome, TunnelLookupOutcome.found);
      expect(r[1]!.facts!.ip, '203.0.113.9');
      expect(r[2]!.outcome, TunnelLookupOutcome.noRoute);
      expect(r[3]!.outcome, TunnelLookupOutcome.failed);
      expect(r[5]!.outcome, TunnelLookupOutcome.failed);
    });
  });

  group('on a stock router', () {
    final shell = findShell();
    late Directory dir;
    late String state;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('network_lookup_');
      state = '${dir.path}/state';
      Directory(state).createSync();
      Directory('${dir.path}/bin').createSync();
      File('${dir.path}/bin/ip').writeAsStringSync(_ip);
      File('${dir.path}/bin/curl').writeAsStringSync(_curl);
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/ip', '${dir.path}/bin/curl']);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> run(List<int> slots) async {
      File('${dir.path}/c.sh').writeAsStringSync('${tunnelLookupCommand(slots, '104.18.40.93', stock: true)}\n');
      final sep = Platform.isWindows ? ';' : ':';
      final r = await runSh(shell!, ['-c', r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$1"', 'sh', '${dir.path}/c.sh'],
          environment: {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state, 'REPLY': _reply});
      return '${r.stdout}';
    }

    List<String> lines(String name) {
      final f = File('$state/$name');
      return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
    }

    test('asks through each tunnel by its own table, by name, and leaves no rule', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final r = parseTunnelLookups(await run([1, 5]), [1, 5]);
      expect(r[1]!.facts!.ip, '203.0.113.9');
      expect(r[5]!.outcome, TunnelLookupOutcome.found);
      final curls = lines('curls');
      expect(curls, hasLength(2));
      expect(curls[0], contains('--resolve www.privateinternetaccess.com:443:104.18.40.93 https://www.privateinternetaccess.com/site-api/get-location-info'));
      expect(curls[0], contains('rules: 104.18.40.93 9'), reason: 'wgc1 is table 9, in force while it asks');
      expect(curls[1], contains('rules: 104.18.40.93 5'), reason: 'wgc5 is table 5');
      expect(lines('rules'), isEmpty);
    });

    // The fault this guards against: an answer by the WAN, which would show the ISP's address as the tunnel's.
    test('a tunnel the rule does not reach is NOROUTE, nothing is sent for it, and no rule is left', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/rule_ignored_1').writeAsStringSync('');
      final r = parseTunnelLookups(await run([1, 5]), [1, 5]);
      expect(r[1]!.outcome, TunnelLookupOutcome.noRoute);
      expect(r[5]!.outcome, TunnelLookupOutcome.found);
      expect(lines('curls'), hasLength(1), reason: 'only wgc5 asked');
      expect(lines('rules'), isEmpty);
    });

    test('no answer through a tunnel is failed, and leaves no rule', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/curl_fails').writeAsStringSync('');
      expect(parseTunnelLookups(await run([4]), [4])[4]!.outcome, TunnelLookupOutcome.failed);
      expect(lines('rules'), isEmpty);
    });
  });
}
