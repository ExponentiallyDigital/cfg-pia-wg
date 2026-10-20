// live/devices_live_test.dart - TESTING.md's DEVICES and default connection [script] tests, run
// unattended against a real router (ID-457).
//
//   flutter test live/devices_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER, CFG_LIVE_PASS,
// CFG_LIVE_TABLET and CFG_LIVE_DESKTOP are set; changes nothing unless CFG_LIVE_GO=1 as well. It
// makes the router calls APPLY and MANAGE make, through the app's own services, and runs e2e.sh
// before and after each, exactly as the sheet has a person do. The first FAIL stops the run, since
// every step starts from the one before it, and whatever happens TABLET and DESKTOP go back to the
// default, the default back to Internet, and wgc1 and wgc5 back up. The log, with each e2e.sh
// output, goes to .claude/testing/, which git ignores: it holds real addresses.
@Timeout(Duration(minutes: 40))
library;

import 'dart:io';

import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:cfg_pia_wg/device_assignment_service.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_plan.dart';

void main() {
  final missing = LiveConfig.missing(Platform.environment);
  test('DEVICES and the default connection, on a live router', () async {
    final run = _LiveRun(LiveConfig.fromEnv(Platform.environment)!);
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

class _LiveRun {
  _LiveRun(this.config);

  final LiveConfig config;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  late final SSHClient _client;
  late final DeviceAssignmentService _devices;
  late final RouterSlotService _slots;
  late final RouterWatchdog _watchdog;
  bool _connected = false;

  // What the run has changed that ENABLE must put back.
  final Set<int> _disabled = {};
  final Set<int> _pausedWatchdogs = {};
  Set<int> _watchdogsAtStart = {};

  Future<Set<int>> _scheduledWatchdogs() async {
    final slots = (await _slots.fetchSlots()).slots;
    return {for (final e in slots.entries) if (e.value.watchdogActive) e.key};
  }

  // TABLET's MAC, and the name it started with, which the restore gives back.
  String _tmac = '';
  String _tabletName = '';

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    _log.writeln(line);
  }

  void _onLog(String message, {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    final mark = switch ((isError, isWarning)) { (true, _) => 'ERROR ', (_, true) => 'WARN ', _ => '' };
    _say('    $mark$message');
  }

  Future<String> _sh(String cmd) async =>
      (await runRouterCommand(_client, cmd, allowFailure: true)).stdout;

  Future<void> go() async {
    _say('Connecting to ${config.router} as ${config.user}...');
    // A store of its own: under flutter test the app's is inert. The first run records the router's
    // key, and every later run is checked against it.
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(config.router, config.user, config.pass, hostKeys: keys);
    _connected = true;
    _devices = DeviceAssignmentService(_client, onLog: _onLog);
    _slots = RouterSlotService(_client, onLog: _onLog);
    _watchdog = RouterWatchdog(_client, onLog: _onLog);
    // The app sets this when it connects, and its code takes Merlin's path until it is set. Without
    // it, DEV-11's watchdog pause took Merlin's and failed on stock (2026-10-20).
    // Not recognised leaves it unset, and the start-state check stops the run as not stock.
    final firmware = classifyFirmwareTag(await _slots.readFirmwareTag());
    if (firmware != null) setRouterFirmware(firmware);

    final start = await _readStart();
    _watchdogsAtStart = await _scheduledWatchdogs();
    final stops = preflightProblems(start, config);
    if (stops.isNotEmpty) {
      stops.forEach(_say);
      failures.addAll(stops);
      return;
    }
    final tablet = start.devices.firstWhere((d) => d.ip == config.tablet);
    _tmac = tablet.mac;
    _tabletName = tablet.customName ?? '';
    final plan = buildPlan(
        t: config.tablet, d: config.desktop, i1: start.i1!, i5: start.i5!, tmac: _tmac, tabletName: _tabletName);
    _say('Start state holds. wgc1 is table ${start.i1}, wgc5 is table ${start.i5}. TABLET is $_tmac, '
        '${_tabletName.isEmpty ? 'with no name of its own' : 'named "$_tabletName"'}.');
    if (!tablet.reserved) {
      _say('TABLET has no reservation, so DEV-4 creates one, as on the sheet.');
    } else {
      _say('TABLET already has a reservation, so DEV-4 does not test creating one.');
    }
    if (!config.go) {
      _say('The plan, not run. Set CFG_LIVE_GO=1 to run it:');
      for (final s in plan) {
        _say('  ${s.id}: ${[...s.setup, ...s.actions]} then ${s.expect} ${s.checks.map((c) => c.runtimeType).toList()}');
      }
      return;
    }
    try {
      for (final step in plan) {
        if (step != plan.first) await Future<void>.delayed(kStepGap);
        if (!await _runStep(step)) break;
      }
    } finally {
      await _restore();
      await _writeLog();
    }
  }

  Future<StartState> _readStart() async {
    final state = await _devices.read();
    final up = (await _sh("ip -o link show up | awk -F': ' '{print \$2}'")).split('\n').map((l) => l.trim()).toSet();
    return StartState(
      stock: classifyFirmwareTag(await _slots.readFirmwareTag()) == RouterFirmware.stock,
      e2ePresent: (await _sh('[ -f $kE2ePath ] && echo yes')).trim() == 'yes',
      devices: state.devices,
      policies: state.policies,
      defaultIndex: state.defaultIndex,
      i1: _indexFor(state, 1),
      i5: _indexFor(state, 5),
      upTunnels: {for (final l in up) if (l.startsWith('wgc')) l.split('@').first},
      timeSchedulingClear: !state.parental.on && state.parental.entries.isEmpty,
    );
  }

  static int? _indexFor(AssignmentState state, int slot) {
    for (final p in state.profiles) {
      if (p.slot == slot) return p.vpncStateIndex;
    }
    return null;
  }

  Future<bool> _runStep(LiveStep step) async {
    _say('\n== ${step.id}');
    try {
      for (final a in step.setup) {
        await _act(a);
      }
      final snap = await _sh(e2eCommand(step.id, 'before'));
      if (!e2eSnapshotTaken(step.id, snap)) {
        _say(snap);
        _say('    FAIL  e2e.sh before took no snapshot');
        failures.add('${step.id}: e2e.sh before took no snapshot');
        return false;
      }
      final callsBefore = await _serviceCalls();
      for (final a in step.actions) {
        await _act(a);
      }
      final callsAfter = await _serviceCalls();
      final (out, tries) = await settle(
          () => _sh(e2eCommand(step.id, 'after', step.expect)), (o) => e2ePassed(step.id, o));
      _say(out);
      if (tries > 1) {
        final waited = (tries - 1) * kSettleGap.inSeconds;
        _say(e2ePassed(step.id, out)
            ? '    (the after check passed on try $tries, about ${waited}s after the step)'
            : '    (the after check still failed after $tries tries, ${waited}s)');
      }
      final problems = [
        if (!e2ePassed(step.id, out)) 'e2e.sh did not pass',
        for (final c in step.checks) ...await _check(c, callsBefore, callsAfter),
      ];
      for (final p in problems) {
        _say('    FAIL  $p');
      }
      if (problems.isNotEmpty) {
        failures.add('${step.id}: ${problems.join('; ')}');
        return false;
      }
      if (step.checks.isNotEmpty) _say('    PASS  ${step.checks.length} router check(s)');
      for (final a in step.cleanup) {
        await _act(a);
      }
      return true;
    } catch (e) {
      _say('    ${step.id} stopped: $e');
      failures.add('${step.id}: $e');
      return false;
    }
  }

  Future<void> _act(LiveAction a) async {
    _say('  - $a');
    switch (a) {
      case Pin(:final changes):
        await _apply(changes: changes);
      case SetDefault(:final index):
        await _apply(newDefault: index);
      case Disable(:final slot):
        await _disable(slot);
      case Enable(:final slot):
        await _enable(slot);
      case Rename(:final mac, :final name):
        await _apply(renames: {mac: name});
      case Block(:final mac, :final on):
        await _apply(blocks: {mac: on});
    }
  }

  Future<int> _serviceCalls() async =>
      int.tryParse((await _sh('grep -cE "rc_service|notify_rc" /tmp/syslog.log')).trim()) ?? 0;

  Future<List<String>> _check(RouterCheck c, int callsBefore, int callsAfter) async => switch (c) {
        NameIs(:final mac, :final name) => nameProblems(await _sh('nvram get custom_clientlist'), mac, name),
        NoServiceCall() => serviceCallProblems(callsBefore, callsAfter),
        BlockedIs(:final mac, :final on) => blockProblems(
            await _sh('nvram show 2>/dev/null | grep -E "^MULTIFILTER_(ALL|BLOCK_ALL|ENABLE|MAC)="'),
            await _sh('iptables -S | grep -i "$mac"'),
            mac,
            on),
        PinKept(:final ip, :final index) => pinKeptProblems(await _sh('nvram get vpnc_dev_policy_list'), ip, index),
      };

  // As DEVICES' APPLY builds its request, from a fresh read: reservations for devices that need one,
  // the router's device type with a new name so its icon stays, and the name Time Scheduling shows.
  Future<void> _apply(
      {Map<String, int?> changes = const {}, int? newDefault, Map<String, String> renames = const {}, Map<String, bool> blocks = const {}}) async {
    final base = await _devices.read();
    LanDevice byMac(String mac) => base.devices.firstWhere((d) => d.mac == mac, orElse: () => LanDevice(mac: mac));
    await _devices.apply(
      base: base,
      request: ApplyRequest(
        changes: changes,
        reservationsToCreate: reservationsFor(base.devices, changes),
        newDefaultIndex: newDefault,
        renames: renames,
        deviceTypes: {
          for (final mac in renames.keys)
            if (byMac(mac).type != null) mac: byMac(mac).type!,
        },
        blocks: blocks,
        blockNames: {for (final mac in blocks.keys) mac: byMac(mac).displayName},
      ),
    );
  }

  // As MANAGE's DISABLE: a running watchdog is paused first, or it would rebuild the tunnel.
  Future<void> _disable(int slot) async {
    if ((await _slots.fetchSlots()).slots[slot]?.watchdogActive ?? false) {
      // Recorded first: a pause that fails partway has still removed some of the schedule.
      _pausedWatchdogs.add(slot);
      await _watchdog.disableWatchdog(slot);
    }
    _disabled.add(slot);
    if (!await _slots.disableSlot(slot)) throw StateError('wgc$slot was disabled but its tunnel is still up');
  }

  // As MANAGE's ENABLE, with the slot's stored check targets, or MANAGE's own suggestions when it
  // has none. Nothing is written for them: the run leaves the router as it found it.
  Future<void> _enable(int slot) async {
    final (primary, secondary) = await _slots.readWatchdogPingTargets(slot);
    await _slots.enableSlot(slot,
        primaryIp: primary.isEmpty ? '8.8.8.8' : primary, secondaryIp: secondary.isEmpty ? '1.1.1.1' : secondary);
    _disabled.remove(slot);
    if (_pausedWatchdogs.remove(slot)) await _watchdog.enableWatchdog(slot);
  }

  /// Puts back what the run changed, then reads the start state again and says whether it holds.
  Future<void> _restore() async {
    _say('\n== Putting the router back');
    for (final slot in {..._disabled}) {
      try {
        await _act(Enable(slot));
      } catch (e) {
        _say('    could not enable wgc$slot: $e');
        failures.add('restore: wgc$slot not enabled: $e');
      }
    }
    // A watchdog paused for a slot that never got as far as being disabled.
    for (final slot in {..._pausedWatchdogs}) {
      try {
        await _watchdog.enableWatchdog(slot);
        _pausedWatchdogs.remove(slot);
      } catch (e) {
        _say("    could not resume wgc$slot's watchdog: $e");
        failures.add("restore: wgc$slot's watchdog not resumed: $e");
      }
    }
    try {
      final named = await _devices.read();
      final tablet = named.devices.where((d) => d.mac == _tmac).firstOrNull;
      final device = deviceRestoreFor(
          blocked: named.parental.isBlocked(_tmac), nameNow: tablet?.customName ?? '', nameAtStart: _tabletName);
      if (device.unblock ?? false) await _act(Block(_tmac, false));
      if (device.rename != null) await _act(Rename(_tmac, device.rename!));
      final now = await _devices.read();
      final undo = restoreFor(policies: now.policies, defaultIndex: now.defaultIndex, ips: [config.tablet, config.desktop]);
      if (undo != null) await _apply(changes: undo.changes, newDefault: undo.newDefault);
      final after = [
        ...preflightProblems(await _readStart(), config),
        ...watchdogProblems(atStart: _watchdogsAtStart, now: await _scheduledWatchdogs()),
      ];
      if (after.isEmpty) {
        _say('Read back: the router is in its start state again.');
      } else {
        after.forEach(_say);
        failures.add('restore: ${after.join('; ')}');
      }
    } catch (e) {
      _say('    could not put the devices back: $e');
      failures.add('restore: $e');
    }
    _say(failures.isEmpty ? '\nALL PASS' : '\nFAILED: ${failures.join('; ')}');
  }

  Future<void> _writeLog() async {
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_devices.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }

  Future<void> close() async {
    if (_connected) _client.close();
  }
}
