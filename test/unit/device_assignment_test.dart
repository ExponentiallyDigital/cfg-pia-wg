// test/unit/device_assignment_test.dart - the rules that decide where a device's traffic goes.
//
// Two of these tests exist because getting them wrong destroys something the user set up rather
// than merely showing it oddly: a record naming a VPN this app does not manage must survive a
// write untouched, and a placeholder record must not read as an assignment.
import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

// Two profiles: wgc1 at clientlist index 6 = 9, wgc5 at index 6 = 5 (ARCHITECTURE.md "vpnc_dev_policy_list - the assignment").
const _twoAssigned = '1>192.168.1.20>>9><1>192.168.1.22>>5>';

void main() {
  group('releasing a profile that is going away', () {
    const list = '1>192.168.1.20>>5><1>192.168.1.21>>9><1>192.168.1.22>>5><0>192.168.1.23>>0>';

    test('names every device pinned to the index, in list order', () {
      expect(devicesPinnedTo(parseDevicePolicyList(list), 5), ['192.168.1.20', '192.168.1.22']);
    });

    test('an index nothing is pinned to yields nothing', () {
      expect(devicesPinnedTo(parseDevicePolicyList(list), 3), isEmpty);
    });

    test('index 0 is not a pin - those devices are already on the default', () {
      expect(devicesPinnedTo(parseDevicePolicyList(list), 0), isEmpty);
    });

    test('releasing sends only those devices back, leaving every other record untouched', () {
      final out = serialiseDevicePolicyList(releaseDevicesFrom(parseDevicePolicyList(list), 5));
      expect(out, '0>192.168.1.20>>0><1>192.168.1.21>>9><0>192.168.1.22>>0><0>192.168.1.23>>0>');
    });

    test('a record naming a VPN this app does not manage survives byte for byte', () {
      // Index 3 here is an OpenVPN profile. Releasing index 5 must not read it, rewrite it or drop
      // it - the user made that assignment somewhere else.
      const withForeign = '1>192.168.1.20>>5><1>192.168.1.50>>3>';
      expect(
        serialiseDevicePolicyList(releaseDevicesFrom(parseDevicePolicyList(withForeign), 5)),
        '0>192.168.1.20>>0><1>192.168.1.50>>3>',
      );
    });
  });

  group('DevicePolicy parsing', () {
    test('reads the address and the profile index from a real list', () {
      final recs = parseDevicePolicyList(_twoAssigned);
      expect(recs.length, 2);
      expect(recs[0].ip, '192.168.1.20');
      expect(recs[0].vpncIndex, 9);
      expect(recs[1].ip, '192.168.1.22');
      expect(recs[1].vpncIndex, 5);
    });

    test('an empty list parses to nothing rather than one blank record', () {
      expect(parseDevicePolicyList(''), isEmpty);
      expect(parseDevicePolicyList('   '), isEmpty);
    });

    test('a round trip is byte-for-byte', () {
      expect(serialiseDevicePolicyList(parseDevicePolicyList(_twoAssigned)), _twoAssigned);
    });

    test('a short record is padded for reading but keeps its own length on the way out', () {
      final r = DevicePolicy(['1', '192.168.1.30']);
      expect(r.ip, '192.168.1.30');
      expect(r.vpncIndex, isNull);
      expect(r.serialise(), '1>192.168.1.30>>>');
    });

    test('a longer record keeps the extra fields', () {
      // A firmware that appends a field must not have it dropped by us on the next write.
      final r = DevicePolicy(['1', '192.168.1.40', '', '9', '', 'future']);
      expect(r.serialise(), '1>192.168.1.40>>9>>future');
    });
  });

  group('what counts as assigned', () {
    test('a disabled placeholder is NOT an assignment', () {
      // A pristine router seeds `0>IP>>0>` for every reserved device. Reading presence as
      // assignment would show a brand-new router with every device already on a VPN.
      final r = parseDevicePolicyList('0>192.168.1.20>>0>').single;
      expect(r.enabled, isFalse);
      expect(r.isAssigned, isFalse);
    });

    // Two records can carry index 0 and mean opposite things. Confirmed 2026-09-08 by reading the
    // router's own interface with the tunnels stopped: a device holding an ENABLED index-0 record
    // showed as selected under Internet Connection, a disabled one as a greyed selection.
    test('ENABLED index 0 is a pin to the plain internet, not an absence of one', () {
      final r = parseDevicePolicyList('1>192.168.1.20>>0>').single;
      expect(r.isAssigned, isTrue);
      expect(assignedIndexFor([r], '192.168.1.20'), 0);
    });

    test('DISABLED index 0 follows the default connection, and has no index of its own', () {
      final r = parseDevicePolicyList('0>192.168.1.20>>0>').single;
      expect(r.isAssigned, isFalse);
      expect(assignedIndexFor([r], '192.168.1.20'), isNull);
    });

    // The difference decides whether a device leaks or fails closed when a tunnel drops, so
    // rewriting one as the other is a correctness bug rather than a display detail.
    test('pinning to the internet and unpinning write different records', () {
      final start = parseDevicePolicyList('1>192.168.1.20>>9>');
      expect(serialiseDevicePolicyList(setDevicePolicy(start, ip: '192.168.1.20', vpncIndex: 0)),
          '1>192.168.1.20>>0>');
      expect(serialiseDevicePolicyList(setDevicePolicy(start, ip: '192.168.1.20', vpncIndex: null)),
          '0>192.168.1.20>>0>');
    });

    test('enabled with a real index is an assignment', () {
      expect(parseDevicePolicyList('1>192.168.1.20>>9>').single.isAssigned, isTrue);
    });

    test('assignedIndexFor finds the profile, or null for an unknown address', () {
      final recs = parseDevicePolicyList(_twoAssigned);
      expect(assignedIndexFor(recs, '192.168.1.22'), 5);
      expect(assignedIndexFor(recs, '192.168.1.99'), isNull);
    });
  });

  group('setDevicePolicy', () {
    test('assigns an address that had no record', () {
      final out = setDevicePolicy(parseDevicePolicyList(''), ip: '192.168.1.30', vpncIndex: 5);
      expect(serialiseDevicePolicyList(out), '1>192.168.1.30>>5>');
    });

    test('moves an existing record to another profile', () {
      final out = setDevicePolicy(parseDevicePolicyList(_twoAssigned), ip: '192.168.1.20', vpncIndex: 5);
      expect(serialiseDevicePolicyList(out), '1>192.168.1.20>>5><1>192.168.1.22>>5>');
    });

    test('unassigning disables the record instead of deleting it', () {
      // The web interface leaves `0>IP>>0>` behind rather than removing the row, and matching it
      // keeps the list the shape the firmware expects.
      final out = setDevicePolicy(parseDevicePolicyList(_twoAssigned), ip: '192.168.1.20');
      expect(serialiseDevicePolicyList(out), '0>192.168.1.20>>0><1>192.168.1.22>>5>');
    });

    test('unassigning an address with no record writes nothing', () {
      final out = setDevicePolicy(parseDevicePolicyList(_twoAssigned), ip: '192.168.1.99');
      expect(serialiseDevicePolicyList(out), _twoAssigned);
    });

    test('A RECORD FOR ANOTHER VPN SURVIVES BYTE FOR BYTE', () {
      // The correctness rule from ARCHITECTURE.md "vpnc_dev_policy_list - the assignment". Index 3 can name an OpenVPN or PPTP
      // profile, and rewriting or dropping it would silently destroy an assignment the user made
      // elsewhere. 192.168.1.50 here is on a profile this app knows nothing about.
      const withForeign = '1>192.168.1.20>>9><1>192.168.1.50>>3><0>192.168.1.60>>0>';
      final out = setDevicePolicy(parseDevicePolicyList(withForeign), ip: '192.168.1.20', vpncIndex: 5);
      final result = serialiseDevicePolicyList(out);
      expect(result, contains('1>192.168.1.50>>3>'), reason: 'the foreign record is untouched');
      expect(result, contains('0>192.168.1.60>>0>'), reason: 'the placeholder is untouched');
      expect(result, '1>192.168.1.20>>5><1>192.168.1.50>>3><0>192.168.1.60>>0>');
    });
  });

  group('LanDevice naming', () {
    test('the user name wins, then the detected one, then the MAC', () {
      const mac = 'AA:BB:CC:DD:EE:FF';
      expect(const LanDevice(mac: mac, customName: 'Lounge TV', detectedName: 'Samsung').displayName, 'Lounge TV');
      expect(const LanDevice(mac: mac, detectedName: 'Samsung').displayName, 'Samsung');
      expect(const LanDevice(mac: mac).displayName, mac);
    });

    test('a blank or whitespace name falls through rather than showing empty', () {
      const mac = 'AA:BB:CC:DD:EE:FF';
      expect(const LanDevice(mac: mac, customName: '  ', detectedName: 'Samsung').displayName, 'Samsung');
      expect(const LanDevice(mac: mac, customName: '', detectedName: '  ').displayName, mac);
    });
  });

  group('assignable', () {
    test('no address means it cannot be assigned', () {
      // The policy record is keyed by IP. nmp_cl_json.js carries no address, so an offline device
      // absent from the /tmp cache and holding no reservation has nothing we could write.
      expect(const LanDevice(mac: 'AA:BB:CC:DD:EE:FF').assignable, isFalse);
      expect(const LanDevice(mac: 'AA:BB:CC:DD:EE:FF', ip: '').assignable, isFalse);
      expect(const LanDevice(mac: 'AA:BB:CC:DD:EE:FF', ip: '192.168.1.20').assignable, isTrue);
    });
  });

  group('randomised MAC', () {
    test('the locally-administered bit is the second hex digit', () {
      for (final d in ['2', '6', 'A', 'E', 'a', 'e']) {
        expect(LanDevice(mac: '0$d:BB:CC:DD:EE:FF').hasRandomisedMac, isTrue, reason: d);
      }
      for (final d in ['0', '4', '8', 'C', '1', 'F']) {
        expect(LanDevice(mac: '0$d:BB:CC:DD:EE:FF').hasRandomisedMac, isFalse, reason: d);
      }
    });

    test('a universally-administered MAC reads as stable', () {
      // Note AA:BB:CC:DD:EE:FF cannot be used here - its second digit is A, so the invented MAC
      // the privacy guard recommends is itself locally-administered.
      expect(const LanDevice(mac: '00:01:02:03:04:05').hasRandomisedMac, isFalse);
    });

    test('a malformed MAC does not throw', () {
      expect(const LanDevice(mac: '').hasRandomisedMac, isFalse);
      expect(const LanDevice(mac: 'A').hasRandomisedMac, isFalse);
    });
  });

  group('sort order', () {
    test('by name, case-insensitively, with nameless devices last', () {
      final sorted = sortDevicesForDisplay(const [
        LanDevice(mac: '0A:0B:0C:0D:0E:0F'), // nameless
        LanDevice(mac: 'AA:BB:CC:DD:EE:F1', customName: 'zebra'),
        LanDevice(mac: 'AA:BB:CC:DD:EE:F2', detectedName: 'Apple'),
        LanDevice(mac: 'AA:BB:CC:DD:EE:F3', customName: 'banana'),
      ]);
      expect(sorted.map((d) => d.displayName).toList(), ['Apple', 'banana', 'zebra', '0A:0B:0C:0D:0E:0F']);
    });

    test('sorting does not mutate the caller list', () {
      final input = <LanDevice>[
        const LanDevice(mac: 'AA:BB:CC:DD:EE:F1', customName: 'zebra'),
        const LanDevice(mac: 'AA:BB:CC:DD:EE:F2', customName: 'apple'),
      ];
      sortDevicesForDisplay(input);
      expect(input.first.displayName, 'zebra');
    });
  });

  // Stock never removes a device's old `ip rule` when its assignment changes, and both rules land
  // at priority 100, so the older one wins on insertion order. Measured on hardware 2026-09-10:
  // every list said wgc5 while the traffic left through wgc1.
  group('staleRuleTables', () {
    const twoRules = '0:\tfrom all lookup local\n'
        '100:\tfrom 192.168.1.51 lookup 9\n'
        '100:\tfrom 192.168.1.51 lookup 5\n'
        '10000:\tfrom all iif br0 lookup 5\n'
        '32766:\tfrom all lookup main\n';

    test('the rule for the tunnel the device left is stale', () {
      expect(staleRuleTables(twoRules, ip: '192.168.1.51', keepIndex: 5), [9]);
    });

    test('unassigning leaves nothing behind - every per-device rule goes', () {
      expect(staleRuleTables(twoRules, ip: '192.168.1.51', keepIndex: null), [9, 5]);
    });

    test('the default-connection rule is never touched', () {
      // `from all iif br0 lookup 5` at priority 10000 IS the default connection. Deleting it
      // would send every unassigned device straight out of the WAN.
      expect(staleRuleTables(twoRules, ip: 'all', keepIndex: null), isEmpty);
    });

    test('a duplicate of the correct rule is stale too, but one copy is kept', () {
      const dupes = '100:\tfrom 192.168.1.51 lookup 5\n100:\tfrom 192.168.1.51 lookup 5\n';
      expect(staleRuleTables(dupes, ip: '192.168.1.51', keepIndex: 5), [5]);
    });

    test('other devices are left alone, and a prefix match is not a match', () {
      const others = '100:\tfrom 192.168.1.5 lookup 9\n'
          '100:\tfrom 192.168.1.510 lookup 9\n'
          '100:\tfrom 192.168.1.51 lookup 9\n';
      expect(staleRuleTables(others, ip: '192.168.1.51', keepIndex: null), [9]);
    });

    test('nothing to do when the device already has only its own rule', () {
      expect(staleRuleTables(twoRules, ip: '192.168.1.51', keepIndex: 9), [5]);
      expect(staleRuleTables('100:\tfrom 192.168.1.51 lookup 5\n', ip: '192.168.1.51', keepIndex: 5), isEmpty);
      expect(staleRuleTables('', ip: '192.168.1.51', keepIndex: 5), isEmpty);
    });
  });
}
