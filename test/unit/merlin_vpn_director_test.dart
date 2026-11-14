// test/unit/merlin_vpn_director_test.dart - VPN Director's rules as DEVICES and the widget use them
// on Merlin (ID-557). The file format, rule numbers and behaviour are as measured on 3004.388.13_0,
// 2026-11-12 to 14; addresses are invented.
import 'package:cfg_pia_wg/device_assignment.dart' show assignedIndexFor;
import 'package:cfg_pia_wg/merlin_guard.dart';
import 'package:cfg_pia_wg/merlin_vpn_director.dart';
import 'package:flutter_test/flutter_test.dart';

const _subnet = '192.168.1.0/24';

void main() {
  group('the rules file', () {
    const raw = '<0>wanpin>192.168.1.94>>WAN<1>vd1 (tablet to NZ)>192.168.1.55>>WGC1<1>default (all devices to mel)>192.168.1.0/24>>WGC5';

    test('reads each record, and writes it back byte for byte, with no trailing newline', () {
      final rules = parseVpnDirectorRules(raw);
      expect(rules.map((r) => r.desc), ['wanpin', 'vd1 (tablet to NZ)', 'default (all devices to mel)']);
      expect(serialiseVpnDirectorRules(rules), raw);
      expect(serialiseVpnDirectorRules(rules).endsWith('\n'), isFalse);
    });

    test('an empty or missing file is no rules, and writes as nothing', () {
      expect(parseVpnDirectorRules(''), isEmpty);
      expect(serialiseVpnDirectorRules(const []), '');
    });

    test("a rule DEVICES doesn't own - a range, a remote address, OpenVPN - isn't a device rule", () {
      expect(const VpnDirectorRule(['1', 'r', '192.168.1.0/24', '', 'WGC1']).isDeviceRule, isFalse);
      expect(const VpnDirectorRule(['1', 'r', '192.168.1.5', '8.8.8.8', 'WGC1']).isDeviceRule, isFalse);
      expect(const VpnDirectorRule(['1', 'r', '192.168.1.5', '', 'OVPN1']).isDeviceRule, isFalse);
      expect(const VpnDirectorRule(['1', 'r', '192.168.1.5', '', 'WAN']).isDeviceRule, isTrue);
    });
  });

  group('as stock-shaped data', () {
    final rules = parseVpnDirectorRules(
        '<1>phone>192.168.1.94>>WAN<1>tablet>192.168.1.55>>WGC1<0>desktop>192.168.1.250>>WGC5<1>default>192.168.1.0/24>>WGC5');

    test('a slot is pinned to 10 - slot, WAN to 0, and a switched-off rule follows the default', () {
      final p = merlinPolicies(rules);
      expect(assignedIndexFor(p, '192.168.1.55'), 9);
      expect(assignedIndexFor(p, '192.168.1.94'), 0);
      expect(assignedIndexFor(p, '192.168.1.250'), isNull);
    });

    test('the default is the whole-network rule, and the internet when there is none', () {
      expect(merlinDefaultIndex(rules, _subnet), 5);
      expect(merlinDefaultIndex(parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC1'), _subnet), 0);
      expect(merlinDefaultIndex(parseVpnDirectorRules('<0>default>192.168.1.0/24>>WGC5'), _subnet), 0,
          reason: 'switched off');
    });

    test('slots become profiles with an index of 10 - slot, active when enabled', () {
      final p = parseMerlinSlots('1>pia-nz>1\n2>>\n3>>\n4>>\n5>pia-aus_melbourne>0');
      expect([for (final r in p) (r.slot, r.desc, r.active, r.vpncStateIndex)],
          [(1, 'pia-nz', true, 9), (5, 'pia-aus_melbourne', false, 5)]);
    });

    test('the LAN as a network, from address and netmask', () {
      expect(lanSubnet('192.168.1.254', '255.255.255.0'), '192.168.1.0/24');
      expect(lanSubnet('10.1.2.3', '255.255.0.0'), '10.1.0.0/16');
      expect(lanSubnet('', '255.255.255.0'), '');
    });
  });

  group("DEVICES' changes", () {
    final base = parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC1<1>default>192.168.1.0/24>>WGC5');

    test('a new pin adds a rule named for the device, after the others', () {
      final out = applyMerlinChanges(base, changes: {'192.168.1.20': 9}, subnet: _subnet, names: {'192.168.1.20': 'Box'});
      expect(serialiseVpnDirectorRules(out), '<1>tablet>192.168.1.55>>WGC1<1>default>192.168.1.0/24>>WGC5<1>Box>192.168.1.20>>WGC1');
    });

    test("a device's own rule is switched, keeping its description, and unpinning switches it off", () {
      final moved = applyMerlinChanges(base, changes: {'192.168.1.55': 0}, subnet: _subnet);
      expect(moved.first.serialise(), '1>tablet>192.168.1.55>>WAN');
      final unpinned = applyMerlinChanges(base, changes: {'192.168.1.55': null}, subnet: _subnet);
      expect(unpinned.first.serialise(), '0>tablet>192.168.1.55>>WGC1');
    });

    test('the default: moved, switched off for the internet, or added when there is none', () {
      expect(applyMerlinChanges(base, changes: const {}, newDefaultIndex: 9, subnet: _subnet).last.serialise(),
          '1>default>192.168.1.0/24>>WGC1');
      expect(applyMerlinChanges(base, changes: const {}, newDefaultIndex: 0, subnet: _subnet).last.serialise(),
          '0>default>192.168.1.0/24>>WGC5');
      final none = parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC1');
      expect(applyMerlinChanges(none, changes: const {}, newDefaultIndex: 5, subnet: _subnet).last.serialise(),
          '1>$kDefaultRuleDesc>192.168.1.0/24>>WGC5');
    });

    test('a pin to a slot above the default is found, and none when the default is the internet', () {
      final above = parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC5<1>default>192.168.1.0/24>>WGC1');
      expect(pinsAboveDefault(above, _subnet), ['192.168.1.55']);
      expect(pinsAboveDefault(base, _subnet), isEmpty, reason: 'wgc1 is below the default on wgc5');
      expect(pinsAboveDefault(parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC5'), _subnet), isEmpty);
    });

    test("a description loses the characters the web page refuses, and is cut to its 32", () {
      expect(vpnDirectorDesc("Ann's <tablet> 100%", fallback: 'x'), 'Anns tablet 100');
      expect(vpnDirectorDesc('<>', fallback: '192.168.1.5'), '192.168.1.5');
      expect(vpnDirectorDesc('a' * 40, fallback: 'x'), 'a' * 32);
    });
  });

  group('the read-back', () {
    final rules = parseVpnDirectorRules('<1>tablet>192.168.1.55>>WGC1<1>phone>192.168.1.94>>WAN<1>default>192.168.1.0/24>>WGC5');

    test('nothing to say when the kernel holds every rule', () {
      const ip = '0: from all lookup local\n10010: from 192.168.1.94 lookup main\n11210: from 192.168.1.55 lookup wgc1\n'
          '11409: from 192.168.1.55 prohibit\n12010: from 192.168.1.0/24 lookup wgc5';
      expect(merlinRuleProblems(rules, _subnet, ip), isEmpty);
    });

    test("names what's missing: a device's rule, its hold, and the default's", () {
      expect(merlinRuleProblems(rules, _subnet, '11210: from 192.168.1.55 lookup wgc1'), [
        '192.168.1.55 is not held to its tunnel',
        '192.168.1.94 has no VPN Director rule',
        'the default connection has no rule',
      ]);
    });
  });

  test("the guard script's priorities are the Dart constants", () {
    for (var slot = 1; slot <= 5; slot++) {
      expect(kMerlinGuardRulePattern, contains('${merlinGuardPriority(slot)}'));
    }
    expect(kMerlinGuardRulePattern, contains('$kMerlinRouterExemptPriority'));
    expect(kMerlinGuardScript, contains("OURS='$kMerlinGuardRulePattern'"));
    expect(kMerlinGuardScript, contains('echo "$kMerlinRouterExemptPriority \$LANIP lookup main"'));
    expect(kMerlinGuardScript, contains('\$((${merlinGuardPriority(0)} + 200 * N))'));
    expect(merlinGuardPriority(1), 11409, reason: 'the top of wgc1 range, measured to hold on 2026-11-14');
  });
}
