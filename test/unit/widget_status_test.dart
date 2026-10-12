// test/unit/widget_status_test.dart - buildWidgetStatus as pure data, no router (ID-376).
import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show buildVpncRecord, serialiseVpncClientlist;
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime kAt = DateTime.utc(2026, 10, 12, 12, 0, 0);

const String kDesktop = '192.168.1.11', kTablet = '192.168.1.22';

const List<LanDevice> kDevices = [
  LanDevice(mac: 'AA:BB:CC:00:00:01', ip: kDesktop, customName: 'DESKTOP'),
  LanDevice(mac: 'AA:BB:CC:00:00:02', ip: kTablet, customName: 'TABLET'),
];

/// Two configured slots, matching what buildVpncRecord gives on hardware: slot N's state index
/// ("iptables ID") is 10 - N, so slot 1 is 9 and slot 5 is 5.
String twoSlots() => serialiseVpncClientlist([
      buildVpncRecord(slot: 1, desc: 'Auckland, New Zealand', active: true),
      buildVpncRecord(slot: 5, desc: 'Melbourne, Australia', active: true),
    ]);

/// A `vpnc_dev_policy_list` entry: `enabled>ip>?>stateIndex>`.
String policy(String ip, int stateIndex, {bool enabled = true}) => '${enabled ? 1 : 0}>$ip>>$stateIndex>';

void main() {
  group('buildWidgetStatus', () {
    test('a tunnel up and answering is protected; one down is not, and names who it blocks', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: '${policy(kDesktop, 9)}<${policy(kTablet, 5)}',
        upInterfaces: ' 12: wgc5: <POINTOPOINT> ',
        handshakeAgesRaw: 'wgc5\tPEERKEY\t1700000000\n---\n1700000300',
        devices: kDevices,
        checkedAt: kAt,
      );

      expect(status.tunnels, hasLength(2));
      final wgc1 = status.tunnels.firstWhere((t) => t.slot == 1);
      final wgc5 = status.tunnels.firstWhere((t) => t.slot == 5);

      expect(wgc1.region, 'Auckland, New Zealand');
      expect(wgc1.up, isFalse);
      expect(wgc1.handshakeAgeSeconds, isNull);
      expect(wgc1.pinnedDeviceNames, ['DESKTOP']);
      expect(wgc1.answering, isFalse);

      expect(wgc5.region, 'Melbourne, Australia');
      expect(wgc5.up, isTrue);
      expect(wgc5.handshakeAgeSeconds, 300); // exactly kAnsweringWithinSeconds - still answering
      expect(wgc5.pinnedDeviceNames, ['TABLET']);
      expect(wgc5.answering, isTrue);

      expect(status.badge, WidgetBadge.tunnelDown);
      expect(status.guardedOfflineDeviceNames, ['DESKTOP']);
      expect(status.checkedAt, kAt);
    });

    test('every configured tunnel answering is protected, with nobody held offline', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: '${policy(kDesktop, 9)}<${policy(kTablet, 5)}',
        upInterfaces: ' wgc1: <> wgc5: <> ',
        handshakeAgesRaw: 'wgc1\tPEERKEY\t1700000000\nwgc5\tPEERKEY\t1700000000\n---\n1700000000',
        devices: kDevices,
        checkedAt: kAt,
      );

      expect(status.badge, WidgetBadge.protected);
      expect(status.guardedOfflineDeviceNames, isEmpty);
    });

    test('no configured slot at all reads as not checked, not protected', () {
      final status = buildWidgetStatus(
        vpncClientlist: '',
        devicePolicyList: '',
        upInterfaces: '',
        handshakeAgesRaw: '---\n1700000000',
        devices: const [],
        checkedAt: kAt,
      );

      expect(status.tunnels, isEmpty);
      expect(status.badge, WidgetBadge.notChecked);
    });

    test('a slot with no region name configured yet is left out of the widget entirely', () {
      final status = buildWidgetStatus(
        vpncClientlist: serialiseVpncClientlist([buildVpncRecord(slot: 1, desc: '', active: false)]),
        devicePolicyList: '',
        upInterfaces: '',
        handshakeAgesRaw: '---\n1700000000',
        devices: const [],
        checkedAt: kAt,
      );

      expect(status.tunnels, isEmpty);
    });

    test('a device pinned to the plain internet (state index 0) is not shown against any tunnel', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: policy(kDesktop, 0),
        upInterfaces: ' wgc1: wgc5: ',
        handshakeAgesRaw: 'wgc1\tPEERKEY\t1700000000\nwgc5\tPEERKEY\t1700000000\n---\n1700000000',
        devices: kDevices,
        checkedAt: kAt,
      );

      for (final t in status.tunnels) {
        expect(t.pinnedDeviceNames, isEmpty);
      }
    });

    test('an unpinned (disabled) policy record does not count as a pin', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: policy(kDesktop, 9, enabled: false),
        upInterfaces: ' wgc1: ',
        handshakeAgesRaw: 'wgc1\tPEERKEY\t1700000000\n---\n1700000000',
        devices: kDevices,
        checkedAt: kAt,
      );

      expect(status.tunnels.firstWhere((t) => t.slot == 1).pinnedDeviceNames, isEmpty);
    });

    test('a pinned device with no matching entry in the device list falls back to its bare address', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: policy('192.168.1.33', 9),
        upInterfaces: '',
        handshakeAgesRaw: '---\n1700000000',
        devices: const [],
        checkedAt: kAt,
      );

      expect(status.tunnels.firstWhere((t) => t.slot == 1).pinnedDeviceNames, ['192.168.1.33']);
    });

    test('a handshake just past the answering window counts the tunnel as down', () {
      final status = buildWidgetStatus(
        vpncClientlist: twoSlots(),
        devicePolicyList: '',
        upInterfaces: ' wgc1: ',
        handshakeAgesRaw: 'wgc1\tPEERKEY\t1700000000\n---\n1700000301', // 301s, one past the 300s bar
        devices: const [],
        checkedAt: kAt,
      );

      expect(status.tunnels.firstWhere((t) => t.slot == 1).answering, isFalse);
    });
  });
}
