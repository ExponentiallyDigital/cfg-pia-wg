// test/router_slot_service_test.dart - RouterSlotService tests over a fake SSH client.
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/router_slot_service.dart';

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
    test('parses desc, kill switch, enabled, watchdog, active slot and Merlin', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('3rd-party')) return 'merlin';
        if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
        if (cmd.contains('wgc1_enforce')) return '1';
        if (cmd.contains('wgc1_enable')) return '1';
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
        if (cmd.contains('wg show interfaces')) return 'wgc1';
        return '';
      });
      final result = await svc(c).fetchSlots();
      expect(result.isMerlin, isTrue);
      expect(result.activeSlot, 1);
      expect(result.slots[1]!.desc, 'aus_melbourne');
      expect(result.slots[1]!.killSwitch, isTrue);
      expect(result.slots[1]!.enabled, isTrue);
      expect(result.slots[1]!.watchdogActive, isTrue);
      expect(result.slots[1]!.isEmpty, isFalse);
      expect(result.slots[2]!.isEmpty, isTrue);
    });

    test('logs "unconfigured" when every slot is empty and reports success', () async {
      final logs = <String>[];
      final c = RecordingSSHClient(responder: (_) => '');
      await svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)).fetchSlots();
      expect(logs, contains('All WireGuard slots are unconfigured.'));
      expect(logs, contains('Successfully retrieved router config.'));
    });

    test('watchdog flag is false on non-Merlin firmware', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('cru l') ? '1' : '');
      final result = await svc(c).fetchSlots();
      expect(result.isMerlin, isFalse);
      expect(result.slots[1]!.watchdogActive, isFalse);
    });
  });

  group('createConfigToSlot', () {
    test('writes all 17 keys with enable=0 and commits; no tunnel start/verify', () async {
      final c = RecordingSSHClient(responder: (_) => ''); // empty slot -> no backup
      await svc(c).createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'aus_melbourne');

      expect(c.ran('nvram set wgc1_enable=0'), isTrue);
      expect(c.ran('nvram set wgc1_desc="aus_melbourne"'), isTrue);
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
        svc(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m))
            .createConfigToSlot(slot: 1, config: _sampleConfig, regionId: 'r'),
        throwsA(isA<Exception>()),
      );
      expect(logs.any((m) => m.contains('Backing up existing wgc1')), isTrue);
      expect(logs.any((m) => m.contains('wgc1 config restored')), isTrue);
    });
  });

  group('enableSlot', () {
    test('enables, verifies the interface, pings both targets and succeeds', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wg show interfaces')) return 'wgc1';
        if (cmd.contains('ping -I wgc1')) return 'OK';
        return '';
      });
      await svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
      expect(c.ran('nvram set wgc1_enable=1'), isTrue);
      expect(c.ran('service "start_wgc 1"'), isTrue);
      expect(c.ran('ping -I wgc1 -c 1 -W 5'), isTrue);
      // No revert on success.
      expect(c.ran('nvram set wgc1_enable=0'), isFalse);
    });

    test('reverts and throws when the interface never comes up', () async {
      final c = RecordingSSHClient(responder: (_) => ''); // wg show interfaces empty
      await expectLater(
        svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
        throwsA(isA<Exception>()),
      );
      expect(c.ran('nvram set wgc1_enable=0'), isTrue); // reverted
      expect(c.ran('service "stop_wgc 1"'), isTrue);
    });

    test('reverts and throws when a ping target is unreachable', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wg show interfaces')) return 'wgc1';
        if (cmd.contains('ping -I wgc1')) return 'FAIL';
        return '';
      });
      await expectLater(
        svc(c).enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
        throwsA(isA<Exception>()),
      );
      expect(c.ran('nvram set wgc1_enable=0'), isTrue);
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
      expect(c.count('nvram unset wgc3_'), kSlotNvramKeys.length);
      expect(c.ran('nvram commit'), isTrue);
    });
  });

  group('readSlotParams / writeSlotParams', () {
    test('readSlotParams returns a bare-keyed map', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wgc1_addr')) return '10.0.0.2/32';
        if (cmd.contains('wgc1_mtu')) return '1420';
        return '';
      });
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
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
        if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
        return '';
      });
      final s = svc(c);
      expect(await s.readWatchdogPingTargets(1), ('8.8.8.8', '1.1.1.1'));
      await s.writeWatchdogPingTargets(1, '9.9.9.9', '1.0.0.1');
      expect(c.ran("nvram set wgc1_wd_primary_ip='9.9.9.9'"), isTrue);
      expect(c.ran("nvram set wgc1_wd_secondary_ip='1.0.0.1'"), isTrue);
    });

    test('pingViaSlot binds to the interface with a 5s timeout', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await svc(ok).pingViaSlot('8.8.8.8', 2), isTrue);
      expect(ok.ran('ping -I wgc2 -c 1 -W 5'), isTrue);
      final fail = RecordingSSHClient(responder: (_) => 'FAIL');
      expect(await svc(fail).pingViaSlot('8.8.8.8', 2), isFalse);
    });
  });
}
