// test/router_slot_service_test.dart - RouterSlotService tests over a fake SSH client.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';

import 'watchdog_test_utils.dart';

const _sampleConfig = '[Interface]\n'
    'PrivateKey = privkey==\n'
    'Address = 10.0.0.2/32\n'
    'DNS = 1.1.1.1\n'
    'MTU = 1420\n\n'
    '[Peer]\n'
    'PublicKey = pubkey==\n'
    'Endpoint = 203.0.113.5:1337\n'
    'AllowedIPs = 0.0.0.0/0\n';

// Fast service: no real delay during the interface-up verification loop.
RouterSlotService svc(
  RecordingSSHClient c, {
  void Function(String, {bool isError, bool isSuccess})? onLog,
  int verifyMaxAttempts = 2,
}) =>
    RouterSlotService(c, onLog: onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: verifyMaxAttempts);

void main() {
  group('fetchSlots', () {
    test('parses desc, kill switch, enabled, watchdog, email alerting, active slot and Merlin', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('3rd-party')) return 'merlin';
          if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
          if (cmd.contains('wgc1_enforce')) return '1';
          if (cmd.contains('wgc1_enable')) return '1';
          if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
          if (cmd.contains('wgc1_wd_email_enabled')) return '1';
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          return '';
        },
      );
      final result = await svc(c).fetchSlots();
      expect(result.isMerlin, isTrue);
      expect(result.activeSlots, {1});
      expect(result.slots[1]!.desc, 'aus_melbourne');
      expect(result.slots[1]!.killSwitch, isTrue);
      expect(result.slots[1]!.enabled, isTrue);
      expect(result.slots[1]!.watchdogActive, isTrue);
      expect(result.slots[1]!.emailAlerting, isTrue);
      expect(result.slots[1]!.isEmpty, isFalse);
      expect(result.slots[2]!.isEmpty, isTrue);
    });

    test('email alerting is not reported when the watchdog is inactive', () async {
      // email_enabled lingers in nvram but the watchdog cron is gone -> no email badge.
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('3rd-party')) return 'merlin';
          if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
          if (cmd.contains('wgc1_wd_email_enabled')) return '1';
          return ''; // cru l -> '' (watchdog inactive)
        },
      );
      final result = await svc(c).fetchSlots();
      expect(result.slots[1]!.watchdogActive, isFalse);
      expect(result.slots[1]!.emailAlerting, isFalse);
    });

    test('logs "unconfigured" when every slot is empty and reports success', () async {
      final logs = <String>[];
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)).fetchSlots();
      expect(logs, contains('All WireGuard slots are unconfigured.'));
      expect(logs, contains('Successfully retrieved router config.'));
    });

    // cru exists on stock too, so the watchdog probe is no longer gated on the firmware tag.
    test('watchdog flag follows cru regardless of the firmware tag', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('cru l') ? '1' : '');
      final result = await svc(c).fetchSlots();
      expect(result.isMerlin, isFalse);
      expect(result.slots[1]!.watchdogActive, isTrue);
    });
  });

  group('fetchSlots on stock', () {
    // One profile in slot 1 (active) and one in slot 3 (inactive); slot 3 also has a live watchdog.
    RecordingSSHClient stockRouter() => RecordingSSHClient(
          responder: (cmd) {
            if (cmd.contains('vpnc_clientlist')) {
              return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg<pia-aus_perth>WireGuard>3>>pw2>0>7>>>0>0>cfg-pia-wg';
            }
            if (cmd.contains('cru l') && cmd.contains('watchdog_wgc3')) return '1';
            if (cmd.contains('wg show interfaces')) return 'wgc1';
            // Any wgcN_desc / _enable / _enforce read would return this and must NOT be used.
            return 'STOCK-SHOULD-NOT-READ-THIS';
          },
        );

    test('reads desc and enabled from vpnc_clientlist, not from per-slot keys', () async {
      useStock();
      final c = stockRouter();
      final result = await svc(c).fetchSlots();

      expect(result.slots[1]!.desc, 'pia-aus_melbourne');
      expect(result.slots[1]!.enabled, isTrue);
      expect(result.slots[3]!.desc, 'pia-aus_perth');
      expect(result.slots[3]!.enabled, isFalse);
      expect(result.slots[2]!.isEmpty, isTrue);
      expect(result.activeSlots, {1});
      expect(result.slots[3]!.watchdogActive, isTrue);
      // The Merlin-only per-slot reads must not happen at all.
      expect(c.ran('nvram get wgc1_desc'), isFalse);
      expect(c.ran('nvram get wgc1_enable'), isFalse);
      expect(c.ran('nvram get wgc1_enforce'), isFalse);
    });

    test('never reports a kill switch (stock has no enforce field)', () async {
      useStock();
      final result = await svc(stockRouter()).fetchSlots();
      expect(result.slots.values.every((s) => !s.killSwitch), isTrue);
    });
  });

  // Regression: activeSlot used RegExp.firstMatch, so with two tunnels up only one was ever
  // badged, and which one depended on the order `wg` happened to print them.
  group('fetchSlots active interfaces', () {
    Future<Set<int>> active(String wgOutput) async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wg show interfaces') ? wgOutput : '');
      return (await svc(c).fetchSlots()).activeSlots;
    }

    test('reports every interface that is up, not just the first', () async {
      expect(await active('wgc1\nwgc3'), {1, 3});
      expect(await active('wgc5 wgc2'), {2, 5});
    });

    test('no interfaces up means no active slots', () async {
      expect(await active(''), isEmpty);
    });

    test('a single interface still reports one slot', () async {
      expect(await active('wgc4'), {4});
    });
  });

  group('createConfigToSlot', () {
    test('writes all 17 keys with enable=0 and commits; no tunnel start/verify', () async {
      final c = RecordingSSHClient(responder: (_) => ''); // empty slot -> no backup
      await svc(c).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'aus_melbourne');

      expect(c.ran('nvram set wgc1_enable=0'), isTrue);
      expect(c.ran('nvram set wgc1_desc="pia-aus_melbourne"'), isTrue); // stored with the app prefix
      expect(c.ran('nvram set wgc1_addr="10.0.0.2/32"'), isTrue);
      expect(c.ran('nvram set wgc1_ep_addr="203.0.113.5"'), isTrue);
      expect(c.ran('nvram set wgc1_ep_port="1337"'), isTrue);
      expect(c.ran('nvram set wgc1_ppub="pubkey=="'), isTrue);
      expect(c.ran('nvram set wgc1_priv="privkey=="'), isTrue);
      expect(c.ran('nvram commit'), isTrue);
      expect(c.count('nvram set wgc1_'), 17);
      // Must NOT activate the slot.
      expect(c.ran('start_wgc'), isFalse);
      expect(c.ran('wg show interfaces'), isFalse);
    });

    test('backs up an occupied slot and restores it on write failure', () async {
      final logs = <String>[];
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('nvram get') ? 'backup_val' : '',
        throwOn: ['wgc1_alive=25'], // fail mid-write, after backup
      );
      await expectLater(
        svc(
          c,
          onLog: (m, {isError = false, isSuccess = false}) => logs.add(m),
        ).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'r'),
        throwsA(isA<Exception>()),
      );
      expect(logs.any((m) => m.contains('Backing up existing wgc1')), isTrue);
      expect(logs.any((m) => m.contains('config restored')), isTrue);
    });
  });

  group('enableSlot', () {
    test('enables, verifies the interface, pings both targets and succeeds', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('ping -I wgc1')) return 'OK';
          return '';
        },
      );
      await svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
      expect(c.ran('nvram set wgc1_enable=1'), isTrue);
      expect(c.ran('service "start_wgc 1"'), isTrue);
      expect(c.ran('ping -I wgc1 -c 1 -w 5'), isTrue);
      // No revert on success.
      expect(c.ran('nvram set wgc1_enable=0'), isFalse);
    });

    test('reverts and throws when the interface never comes up', () async {
      final c = RecordingSSHClient(responder: (_) => ''); // wg show interfaces empty
      await expectLater(svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'), throwsA(isA<Exception>()));
      expect(c.ran('nvram set wgc1_enable=0'), isTrue); // reverted
      expect(c.ran('service "stop_wgc 1"'), isTrue);
    });

    test('reverts and throws when a ping target is unreachable', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('ping -I wgc1')) return 'FAIL';
          return '';
        },
      );
      await expectLater(svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'), throwsA(isA<Exception>()));
      expect(c.ran('nvram set wgc1_enable=0'), isTrue);
    });
  });

  // The caller refreshes as soon as these return, so they must not return while the interface is
  // still listed - that is what left the ACTIVE badge on a just-disabled slot.
  group('stop paths wait for the interface', () {
    RecordingSSHClient router({required int upFor}) {
      var polls = 0;
      return RecordingSSHClient(
        responder: (cmd) => cmd.contains('wg show interfaces') ? (polls++ < upFor ? 'wgc2' : '') : '',
      );
    }

    test('disableSlot returns only once the slot has gone', () async {
      final c = router(upFor: 2);
      await svc(c, verifyMaxAttempts: 5).disableSlot(2);
      expect(c.count('wg show interfaces'), 3); // two while up, one confirming it went
    });

    test('an already-stopped slot costs a single poll', () async {
      final c = router(upFor: 0);
      await svc(c).disableSlot(2);
      expect(c.count('wg show interfaces'), 1);
    });

    test('disableSlot gives up rather than hanging, and still reports', () async {
      final logs = <String>[];
      final c = router(upFor: 99);
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m), verifyMaxAttempts: 2).disableSlot(2);
      expect(logs.any((m) => m.contains('still up after the stop')), isTrue);
      expect(logs.any((m) => m.contains('disabled.')), isTrue);
    });

    test('a failed enable reverts and waits too', () async {
      // Interface never comes up -> _revertEnable, whose stop must also settle.
      final c = RecordingSSHClient(responder: (_) => '');
      await expectLater(svc(c).enableSlot(2, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'), throwsA(isA<Exception>()));
      expect(c.ran('nvram set wgc2_enable=0'), isTrue);
    });
  });

  group('disable / delete', () {
    test('disableSlot sets enable=0, commits and stops the interface', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).disableSlot(2);
      expect(c.ran('nvram set wgc2_enable=0'), isTrue);
      expect(c.ran('nvram commit'), isTrue);
      expect(c.ran('service "stop_wgc 2"'), isTrue);
    });

    test('deleteSlot unsets every key and commits', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).deleteSlot(3);
      expect(c.ran('service "stop_wgc 3"'), isTrue);
      expect(c.ran('nvram unset wgc3_desc'), isTrue);
      expect(c.ran('nvram unset wgc3_priv'), isTrue);
      // also include ping target keys
      expect(c.ran('nvram unset wgc3_wd_primary_ip'), isTrue);
      expect(c.ran('nvram unset wgc3_wd_secondary_ip'), isTrue);
      // the +2 accounts for the extra two manual keys being deleted
      expect(c.count('nvram unset wgc3_'), kSlotNvramKeys.length + 2);
      expect(c.ran('nvram commit'), isTrue);
    });
  });

  // The stop is asynchronous, so DELETE waits for the tunnel to actually go before clearing keys -
  // otherwise the firmware re-creates wgcN_enable behind the unset.
  group('deleteSlot cleanup', () {
    // Interface reported up for [upFor] polls, then gone.
    RecordingSSHClient router({int upFor = 0, String clientlist = ''}) {
      var polls = 0;
      return RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('vpnc_clientlist')) return clientlist;
          if (cmd.contains('wg show interfaces')) return polls++ < upFor ? 'wgc3' : '';
          return '';
        },
      );
    }

    test('waits for the interface to go before unsetting anything', () async {
      useStock();
      final c = router(upFor: 2, clientlist: 'a>WireGuard>3>>pw>1>7>>>0>0>cfg-pia-wg');
      await svc(c, verifyMaxAttempts: 5).deleteSlot(3);

      final lastPoll = c.commands.lastIndexOf('wg show interfaces');
      final firstUnset = c.commands.indexWhere((cmd) => cmd.startsWith('nvram unset'));
      expect(lastPoll, isNot(-1));
      expect(firstUnset, isNot(-1));
      expect(lastPoll, lessThan(firstUnset), reason: 'cleanup must not race the stop');
    });

    test('an already-stopped slot costs a single poll', () async {
      useStock();
      final c = router();
      await svc(c).deleteSlot(3);
      expect(c.count('wg show interfaces'), 1);
    });

    // Giving up must still clear the configuration - that is what the user asked for.
    test('clears anyway, with a warning, if the interface never goes', () async {
      useStock();
      final logs = <String>[];
      final c = router(upFor: 99, clientlist: 'pia-aus_perth>WireGuard>3>>pw>1>7>>>0>0>cfg-pia-wg');
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m), verifyMaxAttempts: 2).deleteSlot(3);

      expect(logs.any((m) => m.contains('wgc3:pia-aus_perth is still up after the stop')), isTrue);
      expect(c.ran('nvram unset wgc3_enable'), isTrue);
      expect(c.ran('nvram commit'), isTrue);
    });

    test('unsets wgcN_enable and the VPN Fusion runtime keys on stock', () async {
      useStock();
      // Slot 3's field 7 is 7, so its runtime keys are vpnc7_*, not vpnc3_*.
      final c = router(clientlist: 'a>WireGuard>3>>pw>1>7>>>0>0>cfg-pia-wg');
      await svc(c).deleteSlot(3);

      expect(c.ran('nvram unset wgc3_enable'), isTrue);
      for (final key in kVpncRuntimeKeys) {
        expect(c.ran('nvram unset vpnc7_$key'), isTrue, reason: key);
      }
      expect(kVpncRuntimeKeys, ['dut_disc', 'sbstate_t', 'state_t']);
      // Nothing else's runtime state is touched.
      expect(c.commands.any((cmd) => cmd.startsWith('nvram unset vpnc') && !cmd.contains('vpnc7_')), isFalse);
    });

    // Reproduces the hardware report: create + enable + delete wgc1 left vpnc9_* behind, because
    // the keys are indexed by field 7 (9 for slot 1), not by the slot number.
    test('wgc1 clears vpnc9_*, not vpnc1_*', () async {
      useStock();
      var polls = 0;
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('vpnc_clientlist')) return 'pia-aus_perth>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
          if (cmd.contains('wg show interfaces')) return polls++ < 1 ? 'wgc1' : '';
          return '';
        },
      );
      await svc(c).deleteSlot(1);

      for (final key in kVpncRuntimeKeys) {
        expect(c.ran('nvram unset vpnc9_$key'), isTrue, reason: key);
        expect(c.ran('nvram unset vpnc1_$key'), isFalse, reason: 'slot number is the wrong index');
      }
    });

    // vpncN_* is VPN Fusion state; Merlin does not drive WireGuard through it.
    test('leaves the VPN Fusion keys alone on Merlin', () async {
      useMerlin();
      final c = router();
      await svc(c).deleteSlot(3);
      expect(c.ran('nvram unset wgc3_enable'), isTrue);
      expect(c.commands.any((cmd) => cmd.startsWith('nvram unset vpnc')), isFalse);
    });

    // Deliberately excluded from the sweep.
    test('does not unset vpncN_dns', () async {
      useStock();
      final c = router(clientlist: 'a>WireGuard>3>>pw>1>7>>>0>0>cfg-pia-wg');
      await svc(c).deleteSlot(3);
      expect(c.ran('nvram unset vpnc3_dns'), isFalse);
    });
  });

  group('readSlotParams / writeSlotParams', () {
    test('readSlotParams returns a bare-keyed map', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wgc1_addr')) return '10.0.0.2/32';
          if (cmd.contains('wgc1_mtu')) return '1420';
          return '';
        },
      );
      final params = await svc(c).readSlotParams(1);
      expect(params['addr'], '10.0.0.2/32');
      expect(params['mtu'], '1420');
      expect(params.keys, containsAll(kSlotNvramKeys));
    });

    test('writeSlotParams shell-quotes values and commits', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).writeSlotParams(1, {'mtu': '1420', 'desc': 'aus_melbourne'});
      expect(c.ran("nvram set wgc1_mtu='1420'"), isTrue);
      expect(c.ran("nvram set wgc1_desc='aus_melbourne'"), isTrue);
      expect(c.ran('nvram commit'), isTrue);
    });
  });

  group('watchdog ping targets + pingViaSlot', () {
    test('reads and writes wgcN_wd_*_ip', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
          if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
          return '';
        },
      );
      final s = svc(c);
      expect(await s.readWatchdogPingTargets(1), ('8.8.8.8', '1.1.1.1'));
      await s.writeWatchdogPingTargets(1, '9.9.9.9', '1.0.0.1');
      expect(c.ran("nvram set wgc1_wd_primary_ip='9.9.9.9'"), isTrue);
      expect(c.ran("nvram set wgc1_wd_secondary_ip='1.0.0.1'"), isTrue);
    });

    test('pingViaSlot binds to the interface with a 5s timeout', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await svc(ok).pingViaSlot('8.8.8.8', 2), isTrue);
      expect(ok.ran('ping -I wgc2 -c 1 -w 5'), isTrue);
      final fail = RecordingSSHClient(responder: (_) => 'FAIL');
      expect(await svc(fail).pingViaSlot('8.8.8.8', 2), isFalse);
    });
  });

  // Stock caps concurrent tunnels via vpnc_max_conn; Merlin has no such key.
  group('fetchSlots concurrency cap', () {
    Future<int?> cap({required bool stock, String maxConn = ''}) async {
      stock ? useStock() : useMerlin();
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('vpnc_max_conn')) return maxConn;
          if (cmd.contains('3rd-party')) return stock ? '' : 'merlin';
          return '';
        },
      );
      return (await svc(c).fetchSlots()).maxActiveSlots;
    }

    test('stock follows the router setting', () async {
      expect(await cap(stock: true, maxConn: '2'), 2);
      expect(await cap(stock: true, maxConn: '3'), 3);
      expect(await cap(stock: true, maxConn: '1'), 1);
    });

    test('stock falls back to the documented default when unreadable', () async {
      expect(await cap(stock: true), kDefaultStockMaxActiveSlots);
      expect(await cap(stock: true, maxConn: 'not-a-number'), kDefaultStockMaxActiveSlots);
      expect(await cap(stock: true, maxConn: '0'), kDefaultStockMaxActiveSlots);
      expect(kDefaultStockMaxActiveSlots, 2);
    });

    test('Merlin reports no cap and is never asked', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : '');
      expect((await svc(c).fetchSlots()).maxActiveSlots, isNull);
      expect(c.ran('vpnc_max_conn'), isFalse);
    });
  });

  group('firmware detection + binary probes', () {
    test('readFirmwareTag returns the raw nvram value', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : '');
      expect(await svc(c).readFirmwareTag(), 'merlin');
      expect(c.ran('nvram get 3rd-party'), isTrue);
    });

    test('readFirmwareTag propagates an SSH failure', () async {
      final c = RecordingSSHClient(throwOn: ['3rd-party']);
      await expectLater(svc(c).readFirmwareTag(), throwsA(isA<Exception>()));
    });

    test('missingStockBinaries reports absent paths in probe order', () async {
      final none = RecordingSSHClient(responder: (_) => '1');
      expect(await svc(none).missingStockBinaries(needMailsend: true), isEmpty);

      final both = RecordingSSHClient(responder: (_) => '0');
      expect(await svc(both).missingStockBinaries(needMailsend: true), [kStockJqPath, kStockMailsendPath]);

      final jqOnly = RecordingSSHClient(responder: (cmd) => cmd.contains('mailsend-go') ? '1' : '0');
      expect(await svc(jqOnly).missingStockBinaries(needMailsend: true), [kStockJqPath]);
    });

    test('manage mode does not probe for the mail binary', () async {
      final c = RecordingSSHClient(responder: (_) => '1');
      await svc(c).missingStockBinaries(needMailsend: false);
      expect(c.ran(kStockJqPath), isTrue);
      expect(c.ran('mailsend-go'), isFalse);
    });
  });

  group('slot description prefix (pure)', () {
    test('slotDescFor adds the prefix', () {
      expect(slotDescFor('aus_melbourne'), 'pia-aus_melbourne');
      expect(kSlotDescPrefix, 'pia-');
    });

    // CREATE over an existing slot re-saves whatever is there; the prefix must not compound.
    test('slotDescFor is idempotent and leaves an empty id alone', () {
      expect(slotDescFor('pia-aus_melbourne'), 'pia-aus_melbourne');
      expect(slotDescFor(''), '');
      expect(slotDescFor('  aus_perth '), 'pia-aus_perth');
    });

    // The router script does the same with the shell's ${DESC#pia-}; they must agree.
    test('regionIdFromDesc is the inverse, and tolerates unprefixed descriptions', () {
      expect(regionIdFromDesc('pia-aus_melbourne'), 'aus_melbourne');
      expect(regionIdFromDesc('aus_melbourne'), 'aus_melbourne'); // written before the prefix existed
      expect(regionIdFromDesc(''), '');
      for (final id in ['aus_melbourne', 'us_east', 'uk_london']) {
        expect(regionIdFromDesc(slotDescFor(id)), id, reason: id);
      }
    });
  });

  // Three different indexes exist on one profile: the slot number, the clientlist row
  // (vpnc_unit), and field 7 (the vpncN_* runtime keys). They coincide often enough to mislead.
  group('vpncStateIndexForSlot (pure)', () {
    const sample = 'a>WireGuard>5>>pw>1>5>>>0>0>Web<b>WireGuard>1>>pw>0>9>>>0>0>Web';

    test('reads field 7, which is not the slot number', () {
      final recs = parseVpncClientlist(sample);
      expect(vpncStateIndexForSlot(recs, 1), 9); // the hardware case: wgc1 -> vpnc9_*
      expect(vpncStateIndexForSlot(recs, 5), 5); // slot 5 is where the two rules coincide
    });

    test('falls back to 10 - slot when the slot has no record', () {
      expect(vpncStateIndexForSlot(const [], 1), 9);
      expect(vpncStateIndexForSlot(const [], 4), 6);
    });

    test('honours a field 7 that does not follow 10 - slot', () {
      // Reading the record beats computing it: a profile carrying an unexpected value still
      // resolves to the keys the firmware actually created.
      final recs = parseVpncClientlist('a>WireGuard>2>>pw>1>3>>>0>0>Web');
      expect(vpncStateIndexForSlot(recs, 2), 3);
    });

    test('falls back when field 7 is blank or unparseable', () {
      expect(vpncStateIndexForSlot(parseVpncClientlist('a>WireGuard>2>>pw>1>>>>0>0>Web'), 2), 8);
      expect(vpncStateIndexForSlot(parseVpncClientlist('a>WireGuard>2>>pw>1>x>>>0>0>Web'), 2), 8);
    });

    test('is a different index from vpnc_unit and from the slot', () {
      final recs = parseVpncClientlist(sample);
      expect(vpncUnitForSlot(recs, 1), 1); // clientlist row
      expect(vpncStateIndexForSlot(recs, 1), 9); // field 7
      // and the slot itself is 1 - three distinct numbers for one profile.
    });

    test('buildVpncRecord writes a field 7 the helper reads back', () {
      for (final slot in [1, 2, 3, 4, 5]) {
        final rec = buildVpncRecord(slot: slot, desc: 'x', active: false);
        expect(vpncStateIndexForSlot([rec], slot), 10 - slot, reason: 'slot $slot');
      }
    });
  });

  group('slotLabel (pure)', () {
    test('names the slot with its description when there is one', () {
      expect(slotLabel(1, 'pia-aus_melbourne'), 'wgc1:pia-aus_melbourne');
      expect(slotLabel(5, ' pia-aus_perth '), 'wgc5:pia-aus_perth');
    });

    test('falls back to the bare slot for an unconfigured one', () {
      expect(slotLabel(3, ''), 'wgc3');
      expect(slotLabel(3, '   '), 'wgc3');
    });
  });

  group('fetchSlotLabel', () {
    test('stock reads the description from vpnc_clientlist, not the desc mirror', () async {
      useStock();
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus_perth>WireGuard>5>>pw>1>5>>>0>0>cfg-pia-wg' : 'MIRROR',
      );
      expect(await fetchSlotLabel(5, (cmd) async => c.responder!(cmd)), 'wgc5:pia-aus_perth');
    });

    test('Merlin reads wgcN_desc, having no clientlist', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc2_desc') ? 'pia-us_east' : '');
      expect(await fetchSlotLabel(2, (cmd) async => c.responder!(cmd)), 'wgc2:pia-us_east');
    });

    test('an unknown slot degrades to the bare name', () async {
      useStock();
      final c = RecordingSSHClient(responder: (_) => '');
      expect(await fetchSlotLabel(4, (cmd) async => c.responder!(cmd)), 'wgc4');
    });

    // A label is decoration: a lookup failure must never break or mask the action being logged.
    test('a failed lookup degrades to the bare name rather than throwing', () async {
      expect(await fetchSlotLabel(1, (_) async => throw Exception('ssh down')), 'wgc1');
    });
  });

  group('log messages name the slot', () {
    test('enable, disable and delete all carry the description', () async {
      useStock();
      for (final probe in [
        ('Enabling wgc1:pia-aus_perth...', (RouterSlotService s) => s.enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1')),
        ('Disabling wgc1:pia-aus_perth...', (RouterSlotService s) => s.disableSlot(1)),
        ('Deleting wgc1:pia-aus_perth configuration...', (RouterSlotService s) => s.deleteSlot(1)),
      ]) {
        final logs = <String>[];
        final c = RecordingSSHClient(
          responder: (cmd) {
            if (cmd.contains('vpnc_clientlist')) return 'pia-aus_perth>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
            if (cmd.contains('wg show interfaces')) return 'wgc1';
            if (cmd.contains('ping -I')) return 'OK';
            if (cmd.contains('ip -4 addr show wgc1')) return 'inet 10.0.0.2/32';
            return '';
          },
        );
        try {
          await probe.$2(svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)));
        } catch (_) {
          // The message content is what matters here, not whether the action succeeded.
        }
        expect(logs, contains(probe.$1));
        // No line still names the slot bare. Raw router output (`wg show interfaces: wgc1`) is
        // excluded - that is the router's own text, not the app naming a slot.
        final appLines = logs.where((m) => !m.contains('wg show interfaces:'));
        expect(appLines.any((m) => m.contains(RegExp(r'wgc1(?!:)'))), isFalse, reason: probe.$1);
      }
    });

    test('the router syslog gets the same label', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus_perth>WireGuard>2>>pw>1>8>>>0>0>cfg-pia-wg' : '');
      await svc(c).disableSlot(2);
      expect(c.commands.any((cmd) => cmd.contains('logger') && cmd.contains('wgc2:pia-aus_perth')), isTrue);
    });

    test('an unconfigured slot still logs, just without a description', () async {
      useMerlin();
      final logs = <String>[];
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)).disableSlot(3);
      expect(logs.any((m) => m.contains('Disabling wgc3...')), isTrue);
    });

    test('the description is read once however many lines mention it', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus_perth>WireGuard>2>>pw>1>8>>>0>0>cfg-pia-wg' : '');
      await svc(c).disableSlot(2);
      // disableSlot logs 3 lines naming the slot; _setVpncActive and _runVpncService read the
      // clientlist for their own reasons, so only assert the label did not add a read per line.
      expect(c.count('nvram get vpnc_clientlist'), lessThanOrEqualTo(3));
    });
  });

  group('vpnc_clientlist parsing (pure)', () {
    // Verbatim from ARCHITECTURE.md 2.3.2.
    const sample = 'pia-aus_melbourne>WireGuard>5>>mel-pwd>1>5>>>0>0>cfg-pia-wg'
        '<pia-aus>WireGuard>4>>aus-pwd>0>6>>>0>0>cfg-pia-wg'
        '<pia-au_brisbane-pf>WireGuard>3>>bris-pwd>0>7>>>0>0>cfg-pia-wg'
        '<pia-au_adelaide-pf>WireGuard>2>>adf-pwd>0>8>>>0>0>cfg-pia-wg'
        '<pia-aus_perth>WireGuard>1>>perth-pwd>0>9>>>0>0>cfg-pia-wg';

    test('parses the documented worked example', () {
      final recs = parseVpncClientlist(sample);
      expect(recs, hasLength(5));
      expect(recs.first.desc, 'pia-aus_melbourne');
      expect(recs.first.protocol, 'WireGuard');
      expect(recs.first.slot, 5);
      expect(recs.first.active, isTrue);
      expect(recs.last.slot, 1);
      expect(recs.last.active, isFalse);
    });

    test('round-trips byte-for-byte', () {
      expect(serialiseVpncClientlist(parseVpncClientlist(sample)), sample);
    });

    test('an empty nvram value parses to no records', () {
      expect(parseVpncClientlist(''), isEmpty);
      expect(parseVpncClientlist('   '), isEmpty);
      expect(serialiseVpncClientlist(const []), '');
    });

    test('short records are padded so field access is total', () {
      final r = parseVpncClientlist('desc>WireGuard>2').single;
      expect(r.fields, hasLength(VpncRecord.fieldCount));
      expect(r.active, isFalse);
      expect(r.slot, 2);
    });

    test('buildVpncRecord fills only the fields we understand', () {
      final f = buildVpncRecord(slot: 3, desc: 'pia-aus', active: true).fields;
      expect(f[0], 'pia-aus'); // description
      expect(f[1], 'WireGuard'); // protocol
      expect(f[2], '3'); // slot
      expect(f[4], 'password'); // password
      expect(f[5], '1'); // active
      expect(f[6], '7'); // iptables ID = 10 - slot
      expect(f[9], '0'); // tunnel = 0
      expect(f[10], '0'); // wan_idx = 0
      expect(f[11], 'cfg-pia-wg'); // 12 fixed
      for (final idx in [3, 7, 8]) {
        expect(f[idx], '', reason: 'field ${idx + 1} must be empty');
      }
    });

    test('upsert rewrites only desc and active, preserving unknown fields', () {
      final updated = upsertVpncRecord(parseVpncClientlist(sample), slot: 4, desc: 'pia-nz', active: true);
      final rec = updated.firstWhere((r) => r.slot == 4);
      expect(rec.desc, 'pia-nz');
      expect(rec.active, isTrue);
      expect(rec.fields[4], 'aus-pwd'); // field 5 untouched
      expect(rec.fields[6], '6'); // field 7 untouched
      expect(updated, hasLength(5)); // no record added
    });

    test('upsert appends a new record when the slot has none', () {
      final updated = upsertVpncRecord(const [], slot: 2, desc: 'pia-aus', active: false);
      expect(updated, hasLength(1));
      expect(updated.single.slot, 2);
      expect(updated.single.fields[6], '8');
    });

    test('remove drops just that slot', () {
      final updated = removeVpncRecord(parseVpncClientlist(sample), 3);
      expect(updated, hasLength(4));
      expect(updated.any((r) => r.slot == 3), isFalse);
    });
  });

  // vpnc_unit selects the profile's ROW in vpnc_clientlist, NOT `5 - slot`. Measured against the
  // WebUI: with rows [slot 5, slot 1] it writes vpnc_unit=1 for slot 1.
  group('vpncUnitForSlot (pure)', () {
    test('a WebUI-ordered list gives the same answers as the old 5 - slot rule', () {
      // The WebUI can only create profiles in slot order 5,4,3,2,1, which is exactly why the wrong
      // rule went unnoticed. Row index must not regress this case.
      final webUiOrder = parseVpncClientlist(
        'a>WireGuard>5>>pw>1>5>>>0>0>Web<b>WireGuard>4>>pw>0>6>>>0>0>Web<c>WireGuard>3>>pw>0>7>>>0>0>Web',
      );
      for (final slot in [5, 4, 3]) {
        expect(vpncUnitForSlot(webUiOrder, slot), 5 - slot, reason: 'slot $slot');
      }
    });

    test('an out-of-order list follows the row, which 5 - slot gets wrong', () {
      // The exact arrangement from the hardware measurement.
      final rows = parseVpncClientlist(
        'aus_melbourne>WireGuard>5>>password>0>5>>>0>0>cfg-pia-wg<aus_perth>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg',
      );
      expect(vpncUnitForSlot(rows, 5), 0);
      expect(vpncUnitForSlot(rows, 1), 1); // 5 - slot would say 4, a row that does not exist
    });

    test('a slot with no profile has no unit', () {
      expect(vpncUnitForSlot(parseVpncClientlist('a>WireGuard>5>>pw>1>5>>>0>0>Web'), 2), isNull);
      expect(vpncUnitForSlot(const [], 1), isNull);
    });
  });

  group('stock slot mutations', () {
    test('createConfigToSlot writes 14 keys and upserts vpnc_clientlist as inactive', () async {
      useStock();
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'aus_melbourne');
      expect(c.count('nvram set wgc1_'), slotKeysFor(RouterFirmware.stock).length);
      expect(c.count('nvram set wgc1_'), 14);
      // The region mirror the router-side watchdog reads with a bare `nvram get`.
      expect(c.ran('nvram set wgc1_desc="pia-aus_melbourne"'), isTrue); // stored with the app prefix
      // Fields stock does not have are never written.
      for (final key in kMerlinOnlySlotKeys) {
        expect(c.ran('nvram set wgc1_$key='), isFalse, reason: '$key is Merlin-only');
      }
      expect(c.ran("nvram set vpnc_clientlist='pia-aus_melbourne>WireGuard>1>>password>0>9>>>0>0>cfg-pia-wg'"), isTrue);
    });

    // A profile created in the router web UI has a vpnc_clientlist record but no desc mirror; it
    // must still be backed up, or an overwrite that fails halfway loses it.
    test('backs up a web-UI-created slot that has no desc mirror', () async {
      useStock();
      final logs = <String>[];
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg' : '',
        throwOn: ['wgc1_alive=25'],
      );
      await expectLater(
        svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m))
            .createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'r'),
        throwsA(isA<Exception>()),
      );
      expect(logs.any((m) => m.contains('Backing up existing wgc1')), isTrue);
      expect(c.ran("nvram set vpnc_clientlist='pia-aus>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg'"), isTrue);
    });

    test('does not back up a genuinely empty stock slot', () async {
      useStock();
      final logs = <String>[];
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m))
          .createConfigToSlot(slot: 2, config: _sampleConfig, regionId: 'r');
      expect(logs.any((m) => m.contains('Backing up')), isFalse);
    });

    test('createConfigToSlot restores vpnc_clientlist when the write fails', () async {
      useStock();
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('nvram get') ? 'backup_val' : '',
        throwOn: ['wgc1_alive=25'], // fail mid-write, after the backup
      );
      await expectLater(
        svc(c).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'r'),
        throwsA(isA<Exception>()),
      );
      expect(c.ran("nvram set vpnc_clientlist='backup_val'"), isTrue);
    });

    test('enableSlot flips the vpnc active flag as well as wgcN_enable', () async {
      useStock();
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('vpnc_clientlist')) return 'pia-aus>WireGuard>1>>pw>0>9>>>0>0>cfg-pia-wg';
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          // These need to be checked in reverse order of specificity: ping -I first
          if (cmd.contains('ping -I')) return 'OK';
          if (cmd.contains('ip -4 addr show wgc1')) return 'inet 10.0.0.2/32';
          return '';
        },
      );
      await svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
      expect(c.ran('nvram set wgc1_enable=1'), isTrue);
      expect(c.ran("nvram set vpnc_clientlist='pia-aus>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg'"), isTrue);
    });

    test('disableSlot clears the vpnc active flag', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus>WireGuard>2>>pw>1>8>>>0>0>cfg-pia-wg' : '');
      await svc(c).disableSlot(2);
      expect(c.ran("nvram set vpnc_clientlist='pia-aus>WireGuard>2>>pw>0>8>>>0>0>cfg-pia-wg'"), isTrue);
    });

    test('deleteSlot removes the vpnc record and skips the Merlin-only keys', () async {
      useStock();
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('vpnc_clientlist')
            ? 'a>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg<b>WireGuard>3>>pw>0>7>>>0>0>cfg-pia-wg'
            : '',
      );
      await svc(c).deleteSlot(3);
      expect(c.ran("nvram set vpnc_clientlist='a>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg'"), isTrue);
      expect(c.ran('nvram unset wgc3_desc'), isTrue); // the mirror is ours to clean up
      expect(c.ran('nvram unset wgc3_enforce'), isFalse);
      expect(c.count('nvram unset wgc3_'), slotKeysFor(RouterFirmware.stock).length + 2);
    });

    // Regression: disable used `service restart_vpnc`, which cleared wgcN_enable and the
    // clientlist active flag — so the WebUI read "disconnected" — but left the interface up.
    // ARCHITECTURE.md 4.2.3 specifies stop_vpnc, confirmed on hardware.
    test('disableSlot stops the tunnel rather than restarting it', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus>WireGuard>2>>pw>1>8>>>0>0>cfg-pia-wg' : '');
      await svc(c).disableSlot(2);
      expect(c.ran('service stop_vpnc'), isTrue);
      expect(c.ran('restart_vpnc'), isFalse);
    });

    test('deleteSlot stops the tunnel rather than restarting it', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus>WireGuard>3>>pw>1>7>>>0>0>cfg-pia-wg' : '');
      await svc(c).deleteSlot(3);
      expect(c.ran('service stop_vpnc'), isTrue);
      expect(c.ran('restart_vpnc'), isFalse);
    });

    test('a failed enable reverts with stop_vpnc', () async {
      useStock();
      // Interface never comes up -> _revertEnable.
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'pia-aus>WireGuard>1>>pw>0>9>>>0>0>cfg-pia-wg' : '');
      await expectLater(svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'), throwsA(isA<Exception>()));
      expect(c.ran('service stop_vpnc'), isTrue);
      expect(c.ran("nvram set vpnc_clientlist='pia-aus>WireGuard>1>>pw>0>9>>>0>0>cfg-pia-wg'"), isTrue);
    });

    // Enable is the one path that keeps restart_vpnc — there is no start_vpnc on stock.
    test('enableSlot still restarts, and targets the row not 5 - slot', () async {
      useStock();
      // Rows [slot 5, slot 1] — the arrangement that made the old rule ask for a nonexistent unit.
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('vpnc_clientlist')) {
            return 'aus_melbourne>WireGuard>5>>pw>0>5>>>0>0>cfg-pia-wg<aus_perth>WireGuard>1>>pw>0>9>>>0>0>cfg-pia-wg';
          }
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('ping -I')) return 'OK';
          if (cmd.contains('ip -4 addr show wgc1')) return 'inet 10.0.0.2/32';
          return '';
        },
      );
      await svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
      expect(c.ran('nvram set vpnc_unit=1'), isTrue); // row index
      expect(c.ran('nvram set vpnc_unit=4'), isFalse); // the old 5 - slot value
      expect(c.ran('service restart_vpnc'), isTrue);
    });

    test('the unit is read after the row is appended for a slot that had none', () async {
      useStock();
      // Slot 3 has no record; _setVpncActive appends it, so its unit is the new last row (1).
      var list = 'aus_melbourne>WireGuard>5>>pw>0>5>>>0>0>cfg-pia-wg';
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.startsWith('nvram set vpnc_clientlist=')) {
            list = cmd.substring("nvram set vpnc_clientlist='".length, cmd.length - 1);
            return '';
          }
          if (cmd.contains('vpnc_clientlist')) return list;
          if (cmd.contains('wg show interfaces')) return 'wgc3';
          if (cmd.contains('ping -I')) return 'OK';
          if (cmd.contains('ip -4 addr show wgc3')) return 'inet 10.0.0.2/32';
          return '';
        },
      );
      await svc(c).enableSlot(3, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
      expect(c.ran('nvram set vpnc_unit=1'), isTrue);
    });

    test('enabling a slot with no profile fails with an actionable message', () async {
      useStock();
      // No record, and _setVpncActive is bypassed by having the write silently drop.
      final c = RecordingSSHClient(responder: (_) => '');
      await expectLater(
        svc(c).enableSlot(2, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
        throwsA(predicate((e) => e.toString().contains('no vpnc_clientlist profile'))),
      );
    });

    test('stopping a slot with no profile is a no-op, not an error', () async {
      useStock();
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).disableSlot(4); // must not throw
      expect(c.ran('service stop_vpnc'), isFalse);
      expect(c.ran('nvram set wgc4_enable=0'), isTrue);
    });

    test('Merlin keeps its own service calls and never sets vpnc_unit', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).disableSlot(2);
      expect(c.ran('service "stop_wgc 2"; service start_vpnrouting0'), isTrue);
      expect(c.ran('vpnc_unit'), isFalse);
      expect(c.ran('stop_vpnc'), isFalse);
    });

    test('readSlotParams reports Merlin-only keys as empty without reading them', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc1_addr') ? '10.0.0.2/32' : '');
      final params = await svc(c).readSlotParams(1);
      expect(params['addr'], '10.0.0.2/32');
      expect(params.keys, containsAll(kSlotNvramKeys)); // shape stays stable for the editor
      for (final key in kMerlinOnlySlotKeys) {
        expect(params[key], '');
        expect(c.ran('nvram get wgc1_$key'), isFalse);
      }
    });

    test('writeSlotParams skips Merlin-only keys and keeps the vpnc desc in step', () async {
      useStock();
      final c = RecordingSSHClient(
          responder: (cmd) => cmd.contains('vpnc_clientlist') ? 'old>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg' : '');
      await svc(c).writeSlotParams(1, {'mtu': '1420', 'desc': 'pia-aus', 'enforce': '1', 'fw': '1'});
      expect(c.ran("nvram set wgc1_mtu='1420'"), isTrue);
      expect(c.ran("nvram set wgc1_desc='pia-aus'"), isTrue);
      expect(c.ran('nvram set wgc1_enforce'), isFalse);
      expect(c.ran('nvram set wgc1_fw'), isFalse);
      expect(c.ran("nvram set vpnc_clientlist='pia-aus>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg'"), isTrue);
    });

    test('Merlin leaves vpnc_clientlist alone entirely', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'r');
      await svc(c).disableSlot(1);
      await svc(c).deleteSlot(1);
      expect(c.ran('vpnc_clientlist'), isFalse);
    });
  });
}
