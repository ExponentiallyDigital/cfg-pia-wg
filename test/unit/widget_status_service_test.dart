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

  test('a blank reply (nothing matched, or the router refused) reads as not checked, not a crash', () async {
    final client = RecordingSSHClient(responder: (_) => '');
    final status = await WidgetStatusService(client).read();

    expect(status.tunnels, isEmpty);
    expect(status.badge, WidgetBadge.notChecked);
  });
}
