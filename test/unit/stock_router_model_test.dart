// The app's DEVICE ASSIGNMENT, default connection and MANAGE ENABLE/DISABLE, driven against a
// stock router that keeps state the way the hardware was measured to (test/stock_router_model.dart).
//
// After every step the question is the one the user asks: where does each device's traffic leave?
// A pinned device leaves through its tunnel or not at all; a tunnel that is switched on is running.
// ID-172, ID-183 and ID-220 were each a wrong answer to that question that passed every test
// checking commands alone (ID-206).
import 'dart:math';

import 'package:cfg_pia_wg/device_assignment_service.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stock_router_model.dart';
import '../watchdog_test_utils.dart';

const _a = '192.168.1.20';
const _b = '192.168.1.30';
const _c = '192.168.1.40';

/// The app's side, over the model.
class _App {
  _App(this.router) : client = router.client();
  final StockRouterModel router;
  final RecordingSSHClient client;

  DeviceAssignmentService get _assign => DeviceAssignmentService(client, pollInterval: Duration.zero, maxPolls: 3);
  RouterSlotService get _manage => RouterSlotService(client, verifyPollInterval: Duration.zero, verifyMaxAttempts: 3);

  /// Pins [ip] to a table (0 is Internet), or back to the default with null.
  Future<void> assign(String ip, int? table) async {
    final base = await _assign.read();
    await _assign.apply(base: base, changes: {ip: table}, reservationsToCreate: {});
  }

  Future<void> setDefault(int table) async {
    final base = await _assign.read();
    await _assign.apply(base: base, changes: {}, reservationsToCreate: {}, newDefaultIndex: table);
  }

  Future<void> disable(int slot) => _manage.disableSlot(slot);
  Future<void> enable(int slot) => _manage.enableSlot(slot, primaryIp: '192.0.2.1', secondaryIp: '192.0.2.2');
}

void main() {
  setUp(useStock);

  late StockRouterModel router;
  late _App app;
  setUp(() {
    router = StockRouterModel(devices: [_a, _b, _c]);
    app = _App(router);
  });

  void expectSound() => expect(router.faults(), isEmpty, reason: router.describe());
  List<String> rulesFor(String ip, int priority) => [
        for (final r in router.rules)
          if (r.priority == priority && r.after('from') == ip) r.text
      ];

  group('DEV: assigning a device', () {
    test('a pinned device leaves through its tunnel, guarded', () async {
      await app.assign(_a, 9);
      expectSound();
      expect(router.actualExit(_a), 'wgc1');
      expect(rulesFor(_a, 90), ['from $_a lookup 9 suppress_prefixlength 0']);
      expect(rulesFor(_a, 91), ['from $_a blackhole']);
    });

    test('a device moved between tunnels keeps one rule, for the new one (6.8.11)', () async {
      await app.assign(_a, 9);
      await app.assign(_a, 5);
      expectSound();
      expect(router.actualExit(_a), 'wgc5');
      expect(rulesFor(_a, 100), ['from $_a lookup 5']);
    });

    test('a device moved from Internet to a tunnel loses its lookup main rule', () async {
      await app.assign(_a, 0);
      expect(router.actualExit(_a), kWan);
      await app.assign(_a, 5);
      expectSound();
      expect(rulesFor(_a, 100), ['from $_a lookup 5']);
    });

    test('repeated applies leave no duplicates behind (ID-183)', () async {
      await app.assign(_a, 9);
      await app.assign(_b, 5);
      await app.assign(_c, 9);
      await app.assign(_b, null);
      expectSound();
      for (final ip in [_a, _b, _c]) {
        expect(rulesFor(ip, 100).length, lessThanOrEqualTo(1), reason: router.describe());
      }
    });

    test('an unpinned device follows the default and loses its guard', () async {
      await app.assign(_a, 9);
      await app.assign(_a, null);
      expectSound();
      expect(router.actualExit(_a), kWan);
      expect(rulesFor(_a, 90), isEmpty);
      expect(rulesFor(_a, 91), isEmpty);
    });
  });

  group('DEF: the default connection', () {
    test('Internet to a tunnel sends unassigned devices through it', () async {
      await app.setDefault(5);
      expectSound();
      expect(router.actualExit(_b), 'wgc5');
    });

    // ID-220, found on hardware 2026-09-24 and passed by every command-level test.
    test('back to Internet leaves the outgoing tunnel running', () async {
      await app.setDefault(5);
      await app.setDefault(0);
      expectSound();
      expect(router.tunnels[5], Tunnel.up);
      expect(router.actualExit(_b), kWan);
    });

    test('from one tunnel to another leaves both running', () async {
      await app.setDefault(9);
      await app.setDefault(5);
      expectSound();
      expect(router.actualExit(_b), 'wgc5');
    });

    // ID-172: vpnc_unit left pointing at a switched-off tunnel must not start it.
    test('back to Internet does not start a switched-off tunnel', () async {
      await app.setDefault(5);
      await app.disable(1);
      await app.setDefault(0);
      expectSound();
      expect(router.tunnels[1], Tunnel.down);
    });

    test('a device pinned to the other tunnel is not disturbed', () async {
      await app.assign(_a, 9);
      await app.setDefault(5);
      await app.setDefault(0);
      expectSound();
      expect(router.actualExit(_a), 'wgc1');
    });
  });

  group('fail closed (ID-213)', () {
    test('DISABLE takes a pinned device offline, ENABLE brings it back', () async {
      await app.assign(_a, 9);
      await app.disable(1);
      expectSound();
      expect(router.actualExit(_a), kBlocked);
      await app.enable(1);
      expectSound();
      expect(router.actualExit(_a), 'wgc1');
    });

    test('DISABLE with the default on Internet does not leak in the clear', () async {
      await app.assign(_a, 5);
      await app.disable(5);
      expect(router.actualExit(_a), kBlocked, reason: router.describe());
    });

    test('an expired tunnel blocks, and a rebuild restores it', () async {
      await app.assign(_a, 9);
      router.expire(1);
      expect(router.actualExit(_a), kBlocked);
      router.rebuild(1);
      expectSound();
      expect(router.actualExit(_a), 'wgc1');
    });

    test('a reboot comes back with every device where it belongs', () async {
      await app.assign(_a, 9);
      await app.assign(_b, 0);
      await app.setDefault(5);
      router.reboot();
      expectSound();
      expect(router.actualExit(_a), 'wgc1');
      expect(router.actualExit(_b), kWan);
      expect(router.actualExit(_c), 'wgc5');
    });
  });

  // ID-214: a ghost marker makes the firmware drop every service call made behind it.
  test('a router stuck on a ghost rc_service marker is cleared first, and the APPLY still lands', () async {
    router.nvram['rc_service'] = 'restart_wlcscan';
    router.nvram['rc_service_pid'] = '4242';
    await app.assign(_a, 9);
    expectSound();
    expect(router.serviceLog.where((s) => s.startsWith('skipped')), isEmpty);
    expect(router.actualExit(_a), 'wgc1');
  });

  // Random sequences of everything a user or the router can do, checked after every step. A seed
  // that fails is a reproducible case: run it alone and read the steps in the reason.
  group('random sequences', () {
    for (var seed = 1; seed <= 40; seed++) {
      test('seed $seed', () async {
        final rnd = Random(seed);
        final steps = <String>[];
        for (var i = 0; i < 25; i++) {
          final ip = [_a, _b, _c][rnd.nextInt(3)];
          final running = [
            for (final p in router.profiles)
              if (p.active) p
          ];
          switch (rnd.nextInt(7)) {
            case 0 || 1:
              final to = [null, 0, 9, 5][rnd.nextInt(4)];
              steps.add('assign $ip to $to');
              await app.assign(ip, to);
            case 2:
              // The app offers switched-on tunnels as the default, and Internet.
              final to = [0, for (final p in running) p.vpncStateIndex!][rnd.nextInt(running.length + 1)];
              if ('$to' == router.nvram['vpnc_default_wan']) continue;
              steps.add('default to $to');
              await app.setDefault(to);
            case 3:
              final slot = [1, 5][rnd.nextInt(2)];
              final on = router.profiles.firstWhere((p) => p.slot == slot).active;
              steps.add('${on ? 'disable' : 'enable'} wgc$slot');
              await (on ? app.disable(slot) : app.enable(slot));
            case 4:
              if (running.isEmpty) continue;
              final slot = running[rnd.nextInt(running.length)].slot!;
              steps.add('wgc$slot expires');
              router.expire(slot);
              expect(router.faults(), isEmpty, reason: '${steps.join('\n')}\n${router.describe()}');
              steps.add('watchdog rebuilds wgc$slot');
              router.rebuild(slot);
            case 5:
              steps.add('reboot');
              router.reboot();
            default:
              steps.add('busy router, then assign $ip to 9');
              router.nvram['rc_service'] = 'restart_wlcscan';
              router.nvram['rc_service_pid'] = '4242';
              await app.assign(ip, 9);
          }
          expect(router.faults(), isEmpty, reason: '${steps.join('\n')}\n${router.describe()}');
        }
      });
    }
  });
}
