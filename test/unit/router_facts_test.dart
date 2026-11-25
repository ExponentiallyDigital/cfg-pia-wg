// test/unit/router_facts_test.dart - the router's own details for NETWORK's box (ID-706), and the WAN in use (ID-720).
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:cfg_pia_wg/router_facts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

// A fake `nvram get <key>` that answers from files, and awk and the rest from the real system.
const _nvram = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/$2" 2>/dev/null
exit 0
''';

void main() {
  test('reads each line, with the DDNS name when DDNS is on', () {
    final f = parseRouterFacts('WAN=203.0.113.9\nDDNSON=1\nDDNS=myhome.example.net\nHOST=router\nDOMAIN=home.example.net\nLAN=192.168.1.1\n');
    expect(f.wanIp, '203.0.113.9');
    expect(f.ddns, 'myhome.example.net');
    expect(f.hostname, 'router');
    expect(f.domain, 'home.example.net');
    expect(f.lanIp, '192.168.1.1');
  });

  test('a DDNS name the router kept after DDNS was switched off is not shown', () {
    expect(parseRouterFacts('DDNSON=0\nDDNS=old.example.net\n').ddns, '');
    expect(parseRouterFacts('DDNS=old.example.net\n').ddns, '', reason: 'no setting read is not "on"');
  });

  test('nothing, or lines that are not settings, give empty values and no error', () {
    final f = parseRouterFacts('');
    expect((f.wanIp, f.ddns, f.hostname, f.domain, f.lanIp), ('', '', '', '', ''));
    expect(parseRouterFacts('garbage\n=x\nWAN\n').wanIp, '');
  });

  test('keeps an equals sign in a value, and trims what the router pads', () {
    expect(parseRouterFacts('HOST= a=b \r\n').hostname, 'a=b');
  });

  test('the command only reads', () {
    expect(kRouterFactsCommand, isNot(contains('nvram set')));
    expect(kRouterFactsCommand, isNot(contains('commit')));
    expect(RegExp(r'nvram get').allMatches(kRouterFactsCommand).length, 8);
  });

  // ID-720: with the first WAN down and a phone on USB carrying the traffic, `wan0_ipaddr` read 0.0.0.0 and the
  // card showed that; the address in use is the primary unit's, `wan1_primary` naming the unit (measured 2026-11-25).
  group('the WAN in use', () {
    test('the first WAN carrying the traffic shows its address alone', () {
      final f = parseRouterFacts('UNIT=0\nWAN=203.0.113.9\nWANKIND=wan\n');
      expect(f.wanUnit, 0);
      expect(f.wanText, '203.0.113.9');
    });

    test('a second WAN carrying the traffic is named with its kind', () {
      final f = parseRouterFacts('UNIT=1\nWAN=10.193.0.21\nWANKIND=usb\n');
      expect(f.wanUnit, 1);
      expect(f.wanText, '10.193.0.21 (secondary WAN, USB)');
    });

    test('a second WAN of a kind not known is still called secondary', () {
      expect(parseRouterFacts('UNIT=1\nWAN=10.0.0.5\nWANKIND=\n').wanText, '10.0.0.5 (secondary WAN)');
      expect(parseRouterFacts('UNIT=1\nWAN=10.0.0.5\nWANKIND=lan\n').wanText, '10.0.0.5 (secondary WAN, lan)');
    });

    test('no unit read means the first, and a unit that is not a number is not believed', () {
      expect(parseRouterFacts('WAN=203.0.113.9\n').wanUnit, 0);
      expect(parseRouterFacts('UNIT=x\nWAN=203.0.113.9\n').wanUnit, 0);
      expect(parseRouterFacts('UNIT=1\n').wanText, '(secondary WAN)', reason: 'no address read is not an address');
    });

    // The command itself, against a fake nvram: the unit is read first and the address is that unit's.
    final shell = findShell();
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('router_facts_');
      Directory('${dir.path}/bin').createSync();
      File('${dir.path}/bin/nvram').writeAsStringSync(_nvram);
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/nvram']);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<RouterFacts> run(Map<String, String> nvram) async {
      for (final e in nvram.entries) {
        File('${dir.path}/${e.key}').writeAsStringSync(e.value);
      }
      final sep = Platform.isWindows ? ';' : ':';
      final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': dir.path};
      final r = await runSh(shell!, ['-c', 'P="\${PATH%%:*}"; PATH="\$P:/usr/bin:/bin:\$PATH"; export PATH; $kRouterFactsCommand'], environment: env);
      return parseRouterFacts('${r.stdout}');
    }

    test('with the first WAN down and the second primary, the second\'s address is read', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final f = await run({
        'wan1_primary': '1', 'wan0_ipaddr': '0.0.0.0', 'wan1_ipaddr': '10.193.0.21', 'wans_dualwan': 'wan usb', //
        'lan_ipaddr': '192.168.1.1',
      });
      expect((f.wanUnit, f.wanIp, f.wanKind), (1, '10.193.0.21', 'usb'));
      expect(f.wanText, '10.193.0.21 (secondary WAN, USB)');
    });

    // ID-729: measured 2026-11-25 after a power cycle, wan_primary read 1 with the first WAN in use.
    test('wan_primary reading 1 with the first WAN primary still reads the first WAN', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final f = await run({
        'wan_primary': '1', 'wan0_primary': '1', 'wan1_primary': '0', 'wan0_ipaddr': '203.0.113.9', //
        'wan1_ipaddr': '10.193.0.21', 'wans_dualwan': 'wan usb',
      });
      expect((f.wanUnit, f.wanIp, f.wanKind), (0, '203.0.113.9', 'wan'));
      expect(f.wanText, '203.0.113.9', reason: 'no "secondary WAN"');
    });

    test('control: with the first WAN primary, or no unit given, the first\'s address is read', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final f = await run({'wan1_primary': '0', 'wan0_ipaddr': '203.0.113.9', 'wan1_ipaddr': '10.193.0.21', 'wans_dualwan': 'wan usb'});
      expect((f.wanUnit, f.wanIp, f.wanKind), (0, '203.0.113.9', 'wan'));
      File('${dir.path}/wan1_primary').deleteSync();
      expect((await run({})).wanIp, '203.0.113.9', reason: 'a router with no wan1_primary has one WAN');
    });
  });
}
