// test/unit/widget_status_service_test.dart - the one-round-trip read, over a fake SSH client (ID-376).
import 'package:cfg_pia_wg/router_slot_service.dart' show buildVpncRecord, serialiseVpncClientlist;
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:cfg_pia_wg/widget_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const String _marker = '@@CFGPIAWG-WIDGET@@';

/// The nine fields [WidgetStatusService.read] splits [kWidgetStatusCommand]'s reply into, in order:
/// vpnc_clientlist, vpnc_dev_policy_list, up interfaces, handshake ages, dhcp_staticlist,
/// custom_clientlist, cfg_device_list, nmp_cl_json, nmp_cache.
String _blob(List<String> fields) => ['', ...fields].join('\n$_marker\n');

void main() {
  test('reads exactly one command, and it is kWidgetStatusCommand', () async {
    final client = RecordingSSHClient(responder: (_) => '');
    await WidgetStatusService(client).read();

    expect(client.commands, [kWidgetStatusCommand]);
  });

  test('splits the nine-field reply back into a WidgetStatus with one tunnel, one pin', () async {
    final vpnc = serialiseVpncClientlist([buildVpncRecord(slot: 5, desc: 'Melbourne, Australia', active: true)]);
    const ip = '192.168.1.11';
    final client = RecordingSSHClient(
      responder: (cmd) => cmd == kWidgetStatusCommand
          ? _blob([
              vpnc, // vpnc_clientlist
              '1>$ip>>5>', // vpnc_dev_policy_list - pinned to slot 5's state index
              ' wgc5: ', // up interfaces
              'wgc5\tPEERKEY\t1700000000\n---\n1700000000', // handshake ages
              '', // dhcp_staticlist
              '', // custom_clientlist
              '', // cfg_device_list
              '', // nmp_cl_json (the inventory - ip comes from the cache below, not here)
              '{"AA:BB:CC:DD:EE:01":{"ip":"$ip","name":"TABLET","isOnline":"1"}}', // nmp_cache
            ])
          : '',
    );

    final status = await WidgetStatusService(client).read();

    expect(status.tunnels, hasLength(1));
    expect(status.tunnels.single.region, 'Melbourne, Australia');
    expect(status.tunnels.single.answering, isTrue);
    expect(status.tunnels.single.pinnedDeviceNames, ['TABLET']);
    expect(status.badge, WidgetBadge.protected);
  });

  // ID-570 and ID-571, seen on 388.13_0 on 2026-11-13: on Merlin the widget said "Not checked" with two
  // tunnels up, as it read only stock's lists. Merlin's part comes after the eleven stock fields.
  test("on Merlin, the tunnels and their pinned devices come from the wgcN keys and VPN Director's rules", () async {
    const ip = '192.168.1.11';
    final client = RecordingSSHClient(
      responder: (cmd) => cmd == kWidgetStatusCommand
          ? _blob([
              '', '', // no vpnc_clientlist or vpnc_dev_policy_list on Merlin
              ' wgc1: \n wgc5: ', // up interfaces
              'wgc1\tPEERKEY\t1700000000\nwgc5\tPEERKEY\t1700000000\n---\n1700000000', // handshake ages
              '', '', '', '', // dhcp_staticlist, custom_clientlist, cfg_device_list, nmp_cl_json
              '{"AA:BB:CC:DD:EE:01":{"ip":"$ip","name":"TABLET","isOnline":"1"}}', // nmp_cache
              '', '', // cru l, the watchdogs' heads and tails
              'merlin', // nvram get 3rd-party
              '1>pia-nz>1\n2>>\n3>>\n4>>\n5>pia-aus_melbourne>1', // the slots
              '<1>vd1>$ip>>WGC1<1>default>192.168.1.0/24>>WGC5', // VPN Director's rules
            ])
          : '',
    );

    final status = await WidgetStatusService(client).read();

    expect([for (final t in status.tunnels) 'wgc${t.slot}:${t.region} ${t.pinnedDeviceNames.join(',')}'.trim()], [
      'wgc1:pia-nz TABLET',
      'wgc5:pia-aus_melbourne',
    ]);
    expect(status.badge, WidgetBadge.protected, reason: 'not "Not checked"');
  });

  test('control: on stock the Merlin part is empty, and the stock lists decide as before', () async {
    final vpnc = serialiseVpncClientlist([buildVpncRecord(slot: 5, desc: 'Melbourne, Australia', active: true)]);
    final client = RecordingSSHClient(
      responder: (cmd) => cmd == kWidgetStatusCommand
          ? _blob([vpnc, '', ' wgc5: ', 'wgc5\tPEERKEY\t1700000000\n---\n1700000000', '', '', '', '', '', '', '', '', '', ''])
          : '',
    );
    final status = await WidgetStatusService(client).read();
    expect([for (final t in status.tunnels) t.slot], [5]);
  });

  test('a blank reply (nothing matched, or the router refused) reads as not checked, not a crash', () async {
    final client = RecordingSSHClient(responder: (_) => '');
    final status = await WidgetStatusService(client).read();

    expect(status.tunnels, isEmpty);
    expect(status.badge, WidgetBadge.notChecked);
  });
}
