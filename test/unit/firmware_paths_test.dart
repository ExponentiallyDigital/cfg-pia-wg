// test/unit/firmware_paths_test.dart - every operation the firmware abstraction will hold (ID-448),
// run under both firmwares, each checked to take its own firmware's path and not the other's.
//
// The abstraction (ID-449 to ID-452, plan_firmware-abstraction.md) moves these five behind one
// `RouterOps`, a slice at a time. A slice that loses one firmware's path - Merlin's command sent on
// stock, or stock's quietly dropped - fails here, whatever else still passes. The commands are what
// each firmware was measured to need (ARCHITECTURE.md "Enable existing slot", "Stop/Disable").
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

/// A router that lets every operation finish: wgc5 has its profile (stock keeps one per slot in
/// vpnc_clientlist), tunnels report up once switched on, pings answer, and a watchdog has stored
/// settings to restore.
RecordingSSHClient _router() => RecordingSSHClient(responder: (cmd) {
      if (cmd == 'nvram get vpnc_clientlist') {
        return serialiseVpncClientlist([buildVpncRecord(slot: 5, desc: 'pia-aus_melbourne', active: true)]);
      }
      if (cmd.contains('ping ') || cmd.contains(r'TBL=$((10 - N))')) return 'OK';
      if (cmd == 'nvram get wgc5_wd_check_interval') return '5';
      if (cmd == 'nvram get wgc5_desc') return 'pia-aus_melbourne';
      return '';
    });

/// One operation: what it runs, and a command only each firmware's path sends.
class _Op {
  const _Op(this.name, this.run, {required this.stock, required this.merlin});
  final String name;
  final Future<void> Function(RecordingSSHClient c) run;
  final String stock, merlin;
}

final _ops = <_Op>[
  _Op('start a slot', (c) => RouterSlotService(c).enableSlot(5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
      stock: 'restart_vpnc', merlin: 'service "start_wgc 5"'),
  _Op('stop a slot', (c) async => RouterSlotService(c).disableSlot(5), stock: 'stop_vpnc', merlin: 'service "stop_wgc 5"'),
  _Op('read the slots', (c) async => RouterSlotService(c).fetchSlots(),
      // Stock keeps names and states in one list; only Merlin has a per-slot kill switch to read.
      stock: 'nvram get vpnc_clientlist', merlin: 'nvram get wgc1_enforce'),
  _Op('persist the watchdog schedule', (c) => RouterWatchdog(c).enableWatchdog(5), stock: kS50Path, merlin: kServicesStartPath),
  _Op('delete a slot', (c) => RouterSlotService(c).deleteSlot(5),
      // Stock also clears the firmware's per-profile runtime keys, vpncN_*; Merlin has none.
      stock: 'nvram unset vpnc', merlin: 'service "stop_wgc 5"'),
];

void main() {
  test('the five operations the plan names are all here', () {
    expect(_ops.map((o) => o.name), [
      'start a slot',
      'stop a slot',
      'read the slots',
      'persist the watchdog schedule',
      'delete a slot',
    ]);
  });

  for (final op in _ops) {
    group(op.name, () {
      test('on stock, takes stock\'s path and not Merlin\'s', () async {
        useStock();
        final c = _router();
        await op.run(c);
        expect(c.ran(op.stock), isTrue, reason: 'stock sends ${op.stock}');
        expect(c.ran(op.merlin), isFalse, reason: 'Merlin\'s ${op.merlin} sent on stock');
      });

      test('on Merlin, takes Merlin\'s path and not stock\'s', () async {
        useMerlin();
        final c = _router();
        await op.run(c);
        expect(c.ran(op.merlin), isTrue, reason: 'Merlin sends ${op.merlin}');
        expect(c.ran(op.stock), isFalse, reason: 'stock\'s ${op.stock} sent on Merlin');
      });
    });
  }

  test('the firmware a test sets is the one these read', () {
    useStock();
    expect(isStockFirmware, isTrue);
    resetRouterFirmware();
    useMerlin();
    expect(isStockFirmware, isFalse);
  });
}
