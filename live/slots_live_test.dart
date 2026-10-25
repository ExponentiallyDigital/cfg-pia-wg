// live/slots_live_test.dart - stopping and starting a tunnel on a real router, through RouterOps
// (ID-449): DISABLE then ENABLE on one slot, as MANAGE does them.
//
//   flutter test live/slots_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER, CFG_LIVE_PASS and
// CFG_LIVE_SLOT (the tunnel to use, which must be up) are set; changes nothing unless CFG_LIVE_GO=1 as
// well, and without it says what it would do. Any device pinned to that tunnel has no internet while it
// is down, a few seconds, which is the fail-closed guard working. Whatever happens, the tunnel is
// started again, and a watchdog it had is resumed. The log goes to .claude/testing/, which git ignores.
//
//   SLT-1  DISABLE: the tunnel's interface is gone.
//   SLT-2  ENABLE: it is back, has handshaken, and answers its ping targets.
//   SLT-3  its watchdog, if it had one, is scheduled again.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS', 'CFG_LIVE_SLOT'];

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  test('stop and start a tunnel, on a live router', () async {
    final run = _SlotsRun(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!,
        int.parse(env['CFG_LIVE_SLOT']!.trim()), allowed: env['CFG_LIVE_GO']?.trim() == '1');
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

class _SlotsRun {
  _SlotsRun(this.router, this.user, this.pass, this.slot, {required this.allowed});

  final String router, user, pass;
  final int slot;
  /// CFG_LIVE_GO=1: without it the run only says what it would do.
  final bool allowed;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  SSHClient? _client;

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    _log.writeln(line);
  }

  void _result(String id, bool pass, String why) {
    _say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
    if (!pass) failures.add('$id: $why');
  }

  void _onLog(String m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => _log.writeln('  app: $m');

  // `ip -o link show up` prints `12: wgc1: <POINTOPOINT,...>`, the name with a colon after it; read as
  // fetchSlots reads it. The first version split on spaces and looked for `wgc1`, so it always said down.
  Future<bool> _up() async => RegExp('\\bwgc$slot:').hasMatch((await runRouterCommand(_client!, kUpInterfacesCommand, allowFailure: true)).stdout);

  Future<void> go() async {
    if (slot < 1 || slot > 5) {
      _result('SLT', false, 'CFG_LIVE_SLOT must be 1 to 5, not $slot');
      return;
    }
    _say('Connecting to $router as $user...');
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(router, user, pass, hostKeys: keys);
    final slots = RouterSlotService(_client!, onLog: _onLog);
    final watchdog = RouterWatchdog(_client!, onLog: _onLog);
    // Set as the app sets it when it connects; RouterOps takes Merlin's path until it is.
    final firmware = classifyFirmwareTag(await slots.readFirmwareTag());
    if (firmware == null) {
      _result('SLT', false, 'this router firmware is not supported');
      return;
    }
    setRouterFirmware(firmware);
    final start = await slots.fetchSlots();
    final info = start.slots[slot]!;
    _say('Firmware ${firmwareLabel(firmware)}; wgc$slot:${info.desc}, ${start.activeSlots.contains(slot) ? 'up' : 'down'}, '
        'watchdog ${info.watchdogActive ? 'scheduled' : 'not scheduled'}.');
    if (info.isEmpty || !start.activeSlots.contains(slot)) {
      _result('SLT', false, 'wgc$slot has to be set up and up to start with');
      return;
    }
    final (primary, secondary) = await slots.readWatchdogPingTargets(slot);
    final targets = (primary.isEmpty ? '8.8.8.8' : primary, secondary.isEmpty ? '1.1.1.1' : secondary);
    if (!allowed) {
      _say('Would: pause its watchdog if scheduled, DISABLE wgc$slot, check it is down, ENABLE it with '
          'ping targets ${targets.$1} and ${targets.$2}, check it is up and answering, then resume the watchdog. '
          'Set CFG_LIVE_GO=1 to do it.');
      return;
    }

    var stopped = false;
    try {
      // SLT-1: as MANAGE's DISABLE: a scheduled watchdog is paused first, or it would rebuild the tunnel.
      if (info.watchdogActive) await watchdog.disableWatchdog(slot);
      stopped = true;
      final wentDown = await slots.disableSlot(slot);
      _result('SLT-1', wentDown && !await _up(), wentDown ? 'wgc$slot is down' : 'wgc$slot was still up after DISABLE');
    } finally {
      // SLT-2: whatever happened, as MANAGE's ENABLE, which also checks the handshake and both targets.
      if (stopped) {
        try {
          await slots.enableSlot(slot, primaryIp: targets.$1, secondaryIp: targets.$2);
          final age = await slots.handshakeAge(slot);
          _result('SLT-2', await _up(), 'wgc$slot is up again, last handshake ${age ?? '?'} s ago, and answered its targets');
        } catch (e) {
          _result('SLT-2', false, 'ENABLE failed: $e');
        }
        if (info.watchdogActive) {
          try {
            await watchdog.enableWatchdog(slot);
            final scheduled = (await slots.fetchSlots()).slots[slot]!.watchdogActive;
            _result('SLT-3', scheduled, scheduled ? 'its watchdog is scheduled again' : 'its watchdog is not scheduled');
          } catch (e) {
            _result('SLT-3', false, 'resuming its watchdog failed: $e');
          }
        } else {
          _say('SLT-3 SKIP: wgc$slot had no watchdog scheduled.');
        }
      }
    }
  }

  Future<void> close() async {
    _client?.close();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_slots.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }
}
