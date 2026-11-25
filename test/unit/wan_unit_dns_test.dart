// test/unit/wan_unit_dns_test.dart - the router's DNS Server setting is read from the WAN carrying the traffic (ID-721).
//
// Measured 2026-11-25 with the first WAN down and a phone on USB taking over: `wan_primary` was 1, `wan0_dns` held
// the setting made by hand (1.1.1.2 1.0.0.2, `wan0_dnsenable_x` 0) and `/tmp/resolv.conf` the phone's DNS, which the
// second WAN took from its carrier (`wan1_dnsenable_x` 1). ROUTER DNS ROUTING read only wan0's, so it described a
// setting nothing was using.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:cfg_pia_wg/router_dns.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _nvram = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/$2" 2>/dev/null
exit 0
''';

void main() {
  group('dnsFromIsp: the setting of the WAN carrying the traffic', () {
    test('the first WAN\'s when no unit is read, or the unit is 0', () {
      expect(dnsFromIsp({'wan0_dnsenable_x': '1', 'wan1_dnsenable_x': '0'}), isTrue);
      expect(dnsFromIsp({'wan_primary': '0', 'wan0_dnsenable_x': '0', 'wan1_dnsenable_x': '1'}), isFalse);
    });

    test('the second WAN\'s when it is primary', () {
      expect(dnsFromIsp({'wan_primary': '1', 'wan0_dnsenable_x': '0', 'wan1_dnsenable_x': '1'}), isTrue);
      expect(dnsFromIsp({'wan_primary': '1', 'wan0_dnsenable_x': '1', 'wan1_dnsenable_x': '0'}), isFalse);
    });

    test('a unit that is not 0 or 1 is not believed, and a setting not read is not "from ISP"', () {
      expect(dnsFromIsp({'wan_primary': '2', 'wan0_dnsenable_x': '1'}), isTrue, reason: 'read as the first');
      expect(dnsFromIsp({'wan_primary': '1'}), isFalse);
    });
  });

  // ID-728: with a second WAN carrying the traffic the DNS Server setting read is that WAN's, and the line says so, since
  // the router's web interface shows a DNS setting on each WAN's own tab and the first's would be a different number.
  group('dnsSettingSource: whose setting the router\'s own ordinary lookups use', () {
    test('the first WAN carrying the traffic says nothing more than before', () {
      expect(dnsSettingSource({'wan0_dnsenable_x': '0'}), 'DNS Server setting');
      expect(dnsSettingSource({'wan_primary': '0', 'wan0_dnsenable_x': '1'}), 'from your internet provider');
    });

    test('a second WAN is named, with its kind when the router lists it', () {
      expect(dnsSettingSource({'wan_primary': '1', 'wans_dualwan': 'wan usb', 'wan1_dnsenable_x': '1'}),
          'from your internet provider (secondary WAN, USB)');
      expect(dnsSettingSource({'wan_primary': '1', 'wans_dualwan': 'wan usb', 'wan1_dnsenable_x': '0'}),
          'DNS Server setting (secondary WAN, USB)');
      expect(dnsSettingSource({'wan_primary': '1'}), 'DNS Server setting (secondary WAN)');
      expect(dnsSettingSource({'wan_primary': '1', 'wans_dualwan': 'wan lan'}), 'DNS Server setting (secondary WAN, lan)');
    });

    test('the screen\'s line and its COPY text carry it, for an ordinary resolver of the router', () {
      const output = '@@RESOLV\nnameserver 10.193.0.108\n@@NVRAM\nwan_primary=1\nwans_dualwan=wan usb\nwan1_dnsenable_x=1\n';
      final r = parseDnsRouting(output, names: const {}, merlin: true);
      final text = dnsReportText('ROUTER DNS ROUTING', buildDnsRouting(r, readAt: '10:00'));
      expect(text, contains('10.193.0.108'));
      expect(text, contains('from your internet provider (secondary WAN, USB), ordinary DNS'));
      final first = parseDnsRouting('@@RESOLV\nnameserver 10.193.0.108\n@@NVRAM\nwan0_dnsenable_x=1\n', names: const {}, merlin: true);
      final plain = dnsReportText('ROUTER DNS ROUTING', buildDnsRouting(first, readAt: '10:00'));
      expect(plain, contains('from your internet provider, ordinary DNS'), reason: 'unchanged for the first WAN');
      expect(plain, isNot(contains('secondary WAN')));
    });
  });

  group('routerOwnAddresses: the addresses the router\'s own lookups go to', () {
    const nv = 'dnspriv_rulelist=<9.9.9.9>853>dns.quad9.net>\nwan0_dns=1.1.1.2 1.0.0.2\nwan1_dns=10.193.0.108\n';

    test('with DNS-over-TLS off, the first WAN\'s setting unless a second carries the traffic', () {
      expect(routerOwnAddresses(nv, dotOn: false), {'1.1.1.2', '1.0.0.2'});
      expect(routerOwnAddresses('wan_primary=0\n$nv', dotOn: false), {'1.1.1.2', '1.0.0.2'});
      expect(routerOwnAddresses('wan_primary=1\n$nv', dotOn: false), {'10.193.0.108'}, reason: 'the first WAN\'s was used');
    });

    test('with DNS-over-TLS on, the DoT list whichever WAN carries the traffic', () {
      expect(routerOwnAddresses('wan_primary=1\n$nv', dotOn: true), {'9.9.9.9'});
      expect(routerOwnAddresses(nv, dotOn: true), {'9.9.9.9'});
    });
  });

  // The command, against a fake nvram: the unit is read first and the setting is that unit's.
  group('kDotServerListCommand', () {
    final shell = findShell();
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('wan_unit_dns_');
      Directory('${dir.path}/bin').createSync();
      File('${dir.path}/bin/nvram').writeAsStringSync(_nvram);
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/nvram']);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Set<String>> addresses(Map<String, String> nvram) async {
      for (final e in nvram.entries) {
        File('${dir.path}/${e.key}').writeAsStringSync(e.value);
      }
      final sep = Platform.isWindows ? ';' : ':';
      final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': dir.path};
      final r = await runSh(shell!, ['-c', 'P="\${PATH%%:*}"; PATH="\$P:/usr/bin:/bin:\$PATH"; export PATH; $kDotServerListCommand'], environment: env);
      return parseDotServerList('${r.stdout}', dnsServerWhenOff: true);
    }

    test('with a second WAN primary, its setting; with the first, or no unit, the first\'s', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      const base = {'dnspriv_enable': '0', 'dnspriv_rulelist': '', 'wan0_dns': '1.1.1.2 1.0.0.2', 'wan1_dns': '10.193.0.108'};
      expect(await addresses({...base, 'wan_primary': '1'}), {'10.193.0.108'});
      expect(await addresses({...base, 'wan_primary': '0'}), {'1.1.1.2', '1.0.0.2'});
      File('${dir.path}/wan_primary').deleteSync();
      expect(await addresses(base), {'1.1.1.2', '1.0.0.2'});
    });
  });
}
