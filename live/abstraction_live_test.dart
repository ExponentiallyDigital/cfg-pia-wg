// live/abstraction_live_test.dart - slices 2 to 4 of the firmware abstraction on a real router
// (ID-450, ID-451, ID-452): reading the slots, keeping a watchdog's schedule over a reboot, and
// deleting a slot, each through RouterOps, as the app does them.
//
//   flutter test live/abstraction_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER and CFG_LIVE_PASS
// are set. Reads only, unless CFG_LIVE_GO=1 as well: then it also pauses and resumes the watchdog of
// CFG_LIVE_SLOT (any slot with a watchdog scheduled when unset), and, with CFG_LIVE_PIA_USER and
// CFG_LIVE_PIA_PASS set, creates a throwaway configuration in an empty slot and deletes it. No tunnel
// that is up is touched. The log goes to .claude/testing/, which git ignores.
//
//   RDS-1  the app's reading of the slots agrees with the router's own lists.
//   SCH-1  pausing a watchdog takes its two lines out of the boot persistence.
//   SCH-2  resuming it puts them back.
//   DEL-1  CREATE writes a throwaway slot the app reads back.
//   DEL-2  DELETE leaves no key, no profile row and no runtime keys behind.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/server_list_signature.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS'];

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  test('slices 2 to 4 of the firmware abstraction, on a live router', () async {
    final run = _Run(env);
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

class _Run {
  _Run(this.env);

  final Map<String, String> env;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  SSHClient? _client;
  late RouterSlotService _slots;
  late RouterWatchdog _watchdog;
  late bool _stock;

  bool get _allowed => env['CFG_LIVE_GO']?.trim() == '1';

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

  Future<String> _sh(String cmd) async => (await runRouterCommand(_client!, cmd, allowFailure: true)).stdout.trim();

  Future<void> go() async {
    final router = env['CFG_LIVE_ROUTER']!.trim();
    _say('Connecting to $router as ${env['CFG_LIVE_USER']!.trim()}...');
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(router, env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!, hostKeys: keys);
    _slots = RouterSlotService(_client!, onLog: _onLog);
    _watchdog = RouterWatchdog(_client!, onLog: _onLog);
    final firmware = classifyFirmwareTag(await _slots.readFirmwareTag());
    if (firmware == null) {
      _result('RDS-1', false, 'this router firmware is not supported');
      return;
    }
    setRouterFirmware(firmware);
    _stock = firmware == RouterFirmware.stock;
    _say('Firmware ${firmwareLabel(firmware)}.');

    final slots = await _read();
    if (!_allowed) {
      _say('Reads only. Set CFG_LIVE_GO=1 to pause and resume a watchdog, and with CFG_LIVE_PIA_USER and '
          'CFG_LIVE_PIA_PASS, to create and delete a throwaway slot.');
      return;
    }
    await _schedule(slots);
    await _delete(slots);
  }

  /// RDS-1: what fetchSlots says against the router's own lists.
  Future<RouterSlots> _read() async {
    final slots = await _slots.fetchSlots();
    final up = RegExp(r'wgc(\d):').allMatches(await _sh(kUpInterfacesCommand)).map((m) => int.parse(m.group(1)!)).toSet();
    final problems = <String>[];
    if (slots.activeSlots.difference(up).isNotEmpty || up.difference(slots.activeSlots).isNotEmpty) {
      problems.add('up: app ${slots.activeSlots}, router $up');
    }
    for (final e in slots.slots.entries) {
      final desc = await _sh('nvram get wgc${e.key}_desc');
      final rowDesc = _stock ? parseVpncClientlist(await _sh('nvram get vpnc_clientlist')).where((r) => r.slot == e.key).firstOrNull?.desc : null;
      final expected = (rowDesc ?? '').trim().isNotEmpty ? rowDesc! : desc;
      if (e.value.desc != expected) problems.add('wgc${e.key}: app "${e.value.desc}", router "$expected"');
    }
    if (_stock && slots.maxActiveSlots == null) problems.add('stock with no tunnel cap read');
    _result('RDS-1', problems.isEmpty, problems.isEmpty
        ? '${slots.slots.values.where((s) => !s.isEmpty).length} slots set up, ${slots.activeSlots.length} up, '
            'cap ${slots.maxActiveSlots ?? 'none'}, ${slots.routerDotServers.length} router DoT server(s)'
        : problems.join('; '));
    for (final e in slots.slots.entries) {
      _say('  wgc${e.key}:${e.value.desc.isEmpty ? '(empty)' : e.value.desc} ${slots.activeSlots.contains(e.key) ? 'up' : 'down'}'
          '${e.value.watchdogActive ? ', watchdog scheduled' : ''}');
    }
    return slots;
  }

  /// The boot persistence's lines for [slot]'s watchdog: in S50downloadmaster on stock, services-start on Merlin.
  Future<int> _persisted(int slot) async {
    final file = _stock ? kS50Path : kServicesStartPath;
    return int.tryParse(await _sh("grep -cE 'watchdog_(log_rotate_)?wgc$slot ' '$file' 2>/dev/null || true")) ?? 0;
  }

  /// SCH-1, SCH-2: pause and resume one watchdog, as WATCHDOG's DISABLE and ENABLE do.
  Future<void> _schedule(RouterSlots slots) async {
    final asked = int.tryParse(env['CFG_LIVE_SLOT']?.trim() ?? '');
    final slot = asked ?? slots.slots.entries.where((e) => e.value.watchdogActive).map((e) => e.key).firstOrNull;
    if (slot == null || !(slots.slots[slot]?.watchdogActive ?? false)) {
      _say('SCH SKIP: no slot with a watchdog scheduled${asked == null ? '' : ' at wgc$asked'}.');
      return;
    }
    final before = await _persisted(slot);
    var paused = false;
    try {
      await _watchdog.disableWatchdog(slot);
      paused = true;
      final after = await _persisted(slot);
      _result('SCH-1', before == 2 && after == 0, 'wgc$slot boot lines $before before the pause, $after after');
    } finally {
      if (paused) {
        await _watchdog.enableWatchdog(slot);
        final back = await _persisted(slot);
        final scheduled = (await _slots.fetchSlots()).slots[slot]!.watchdogActive;
        _result('SCH-2', back == 2 && scheduled, 'wgc$slot boot lines $back after resuming, ${scheduled ? '' : 'not '}scheduled');
      }
    }
  }

  /// DEL-1, DEL-2: a throwaway configuration in an empty slot, created and deleted as MANAGE does.
  Future<void> _delete(RouterSlots slots) async {
    final user = env['CFG_LIVE_PIA_USER']?.trim() ?? '', pass = env['CFG_LIVE_PIA_PASS'] ?? '';
    final spare = slots.slots.entries.where((e) => e.value.isEmpty && !slots.activeSlots.contains(e.key)).map((e) => e.key).firstOrNull;
    if (user.isEmpty || pass.isEmpty) {
      _say('DEL SKIP: set CFG_LIVE_PIA_USER and CFG_LIVE_PIA_PASS to create and delete a throwaway slot.');
      return;
    }
    if (spare == null) {
      _say('DEL SKIP: no empty slot to use.');
      return;
    }
    final region = env['CFG_LIVE_REGION']?.trim().isNotEmpty == true ? env['CFG_LIVE_REGION']!.trim() : 'aus_melbourne';
    final storeDir = Directory('${Directory.systemTemp.path}/cfg-pia-wg-live-servers')..createSync();
    final pia = PiaService(serverListStore: ServerListStore(directory: () async => storeDir));
    final regions = await pia.fetchRegions();
    final selected = regions.where((r) => r.id == region).firstOrNull;
    if (selected == null) {
      _result('DEL-1', false, 'no PIA region "$region"');
      return;
    }
    var created = false;
    try {
      final config = await pia.generateConfig(region: region, selected: selected, username: user, password: pass, dns: '');
      await _slots.createConfigToSlot(slot: spare, config: config, regionId: region);
      created = true;
      final read = (await _slots.fetchSlots()).slots[spare]!;
      _result('DEL-1', !read.isEmpty && !read.enabled, 'wgc$spare created as "${read.desc}", disabled');
    } finally {
      if (created) {
        final stateIdx = _stock ? vpncStateIndexForSlot(parseVpncClientlist(await _sh('nvram get vpnc_clientlist')), spare) : null;
        await _slots.deleteSlot(spare);
        final key = await _sh('nvram get wgc${spare}_priv');
        final row = _stock && parseVpncClientlist(await _sh('nvram get vpnc_clientlist')).any((r) => r.slot == spare);
        final runtime = stateIdx == null ? 0 : int.tryParse(await _sh("nvram show 2>/dev/null | grep -c '^vpnc${stateIdx}_' || true")) ?? 0;
        _result('DEL-2', key.isEmpty && !row && runtime == 0,
            'wgc$spare deleted: private key ${key.isEmpty ? 'gone' : 'LEFT'}, profile row ${row ? 'LEFT' : 'gone'}, '
            '${stateIdx == null ? 'no runtime keys on Merlin' : '$runtime vpnc${stateIdx}_* key(s) left'}');
      }
    }
  }

  Future<void> close() async {
    _client?.close();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_abstraction.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }
}
