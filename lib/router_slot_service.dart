// router_slot_service.dart - SSH-driven WireGuard slot operations for ASUS / Merlin routers.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Extracted from router_push.dart's _fetchSlots / _pushToRouter and extended for the
// "Manage router PIA WireGuard configuration" screen (spec 2.1.2): CREATE (write but leave
// disabled), ENABLE (with a connectivity check + revert-on-failure), DISABLE, DELETE, and the
// full slot-parameter read/write used by the EDIT screen (spec 3.3). The connection itself is
// owned by the caller (mirroring RouterWatchdog), so RecordingSSHClient drives these in tests.

import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'router_watchdog.dart' show shellSingleQuote, kWatchdogLogTag;

// The per-slot WireGuard NVRAM keys (without the `wgcN_` prefix), in the order router_push.dart
// wrote them. Used for backup/restore, delete, and the parameter editor.
const List<String> kSlotNvramKeys = [
  'addr',
  'alive',
  'desc',
  'dns',
  'enable',
  'enforce',
  'ep_addr',
  'ep_addr_r',
  'ep_port',
  'fw',
  'mtu',
  'nat',
  'ppub',
  'priv',
  'psk',
  'rip',
  'aips',
];

/// Opens a real SSH client to the router. Screens inject a test factory instead in tests.
Future<SSHClient> openSshClient(String ip, String user, String pass) async {
  final socket = await SSHSocket.connect(ip, 22, timeout: const Duration(seconds: 5));
  final client = SSHClient(socket, username: user, onPasswordRequest: () => pass);
  await client.authenticated;
  return client;
}

/// Per-slot summary shown in the slot modal.
class SlotInfo {
  final int index;
  final String desc; // wgcN_desc (region name); empty => unconfigured
  final bool killSwitch; // wgcN_enforce == 1
  final bool enabled; // wgcN_enable == 1
  final bool watchdogActive; // cru has watchdog_wgcN (Merlin only)
  const SlotInfo({
    required this.index,
    required this.desc,
    required this.killSwitch,
    required this.enabled,
    required this.watchdogActive,
  });

  bool get isEmpty => desc.trim().isEmpty;
}

/// Result of [RouterSlotService.fetchSlots].
class RouterSlots {
  final Map<int, SlotInfo> slots; // keys 1..5
  final int? activeSlot; // slot whose interface is up (`wg show interfaces`)
  final bool isMerlin;
  const RouterSlots({required this.slots, required this.activeSlot, required this.isMerlin});
}

class RouterSlotService {
  final SSHClient client;
  final void Function(String, {bool isError, bool isSuccess})? onLog;

  // Interface-up verification cadence (injectable so unit tests don't wait real time).
  final Duration verifyPollInterval;
  final int verifyMaxAttempts;

  RouterSlotService(
    this.client, {
    this.onLog,
    this.verifyPollInterval = const Duration(seconds: 2),
    this.verifyMaxAttempts = 30,
  });

  Future<String> _run(String cmd) async => utf8.decode(await client.run(cmd)).trim();

  // Best-effort router syslog entry (mirrors RouterWatchdog._logRouter); never fails the action.
  Future<void> _logRouter(String msg) async {
    try {
      await _run('logger -t $kWatchdogLogTag ${shellSingleQuote(msg)}');
    } catch (_) {}
  }

  // ── Read ─────────────────────────────────────────────────────────────────────
  Future<RouterSlots> fetchSlots() async {
    onLog?.call('Reading router configuration...');
    final isMerlin = (await _run('nvram get 3rd-party')) == 'merlin';

    final slots = <int, SlotInfo>{};
    for (int i = 1; i <= 5; i++) {
      final desc = await _run('nvram get wgc${i}_desc');
      final killSwitch = (await _run('nvram get wgc${i}_enforce')) == '1';
      final enabled = (await _run('nvram get wgc${i}_enable')) == '1';
      final watchdog = isMerlin && (await _run('cru l | grep -qw watchdog_wgc$i && echo 1 || echo 0')) == '1';
      slots[i] = SlotInfo(index: i, desc: desc, killSwitch: killSwitch, enabled: enabled, watchdogActive: watchdog);
    }

    final ifaceOutput = await _run('wg show interfaces');
    final activeMatch = RegExp(r'wgc(\d)').firstMatch(ifaceOutput);
    final activeSlot = activeMatch != null ? int.tryParse(activeMatch.group(1)!) : null;

    if (slots.values.every((s) => s.isEmpty)) {
      onLog?.call('All WireGuard slots are unconfigured.');
    }
    onLog?.call('Successfully retrieved router config.', isSuccess: true);
    return RouterSlots(slots: slots, activeSlot: activeSlot, isMerlin: isMerlin);
  }

  // Reads every per-slot NVRAM value (bare-keyed map) for the parameter editor.
  Future<Map<String, String>> readSlotParams(int slot) async {
    final m = <String, String>{};
    for (final k in kSlotNvramKeys) {
      m[k] = await _run('nvram get wgc${slot}_$k');
    }
    return m;
  }

  // ── Parse helper (from router_push.dart) ──────────────────────────────────────
  Map<String, String> parseWgConfig(String conf) {
    final map = <String, String>{};
    for (final line in conf.split('\n')) {
      final parts = line.split('=');
      if (parts.length >= 2) {
        map[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }
    return map;
  }

  // ── Create (write to NVRAM, leave DISABLED, do not touch the active tunnel) ─────
  // Mirrors router_push.dart Step 4 but sets enable=0 and skips the stop/start/verify.
  Future<void> createConfigToSlot({required int slot, required String config, required String regionId}) async {
    final wgMap = parseWgConfig(config);
    final epParts = wgMap['Endpoint']?.split(':') ?? [];
    final epIp = epParts.isNotEmpty ? epParts[0] : '';
    final epPort = epParts.length > 1 ? epParts[1] : '1337';

    Map<String, String>? backup;
    try {
      final existingDesc = await _run('nvram get wgc${slot}_desc');
      if (existingDesc.isNotEmpty) {
        onLog?.call('Backing up existing wgc$slot config...');
        backup = {};
        for (final key in kSlotNvramKeys) {
          backup['wgc${slot}_$key'] = await _run('nvram get wgc${slot}_$key');
        }
      }

      onLog?.call('Writing NVRAM for wgc$slot...');
      await _run('nvram set wgc${slot}_addr="${wgMap['Address'] ?? ''}"');
      await _run('nvram set wgc${slot}_alive=25');
      await _run('nvram set wgc${slot}_desc="$regionId"');
      await _run('nvram set wgc${slot}_dns="${wgMap['DNS'] ?? ''}"');
      await _run('nvram set wgc${slot}_enable=0'); // created but not active (spec 2.1.2)
      await _run('nvram set wgc${slot}_enforce=0'); // kill switch off on create (round-2)
      await _run('nvram set wgc${slot}_ep_addr="$epIp"');
      await _run('nvram set wgc${slot}_ep_addr_r=""');
      await _run('nvram set wgc${slot}_ep_port="$epPort"');
      await _run('nvram set wgc${slot}_fw=1');
      await _run('nvram set wgc${slot}_mtu="${wgMap['MTU'] ?? '1420'}"');
      await _run('nvram set wgc${slot}_nat=1');
      await _run('nvram set wgc${slot}_ppub="${wgMap['PublicKey'] ?? ''}"');
      await _run('nvram set wgc${slot}_priv="${wgMap['PrivateKey'] ?? ''}"');
      await _run('nvram set wgc${slot}_psk=""');
      await _run('nvram set wgc${slot}_rip=""');
      await _run('nvram set wgc${slot}_aips="${wgMap['AllowedIPs'] ?? '0.0.0.0/0'}"');
      await _run('nvram commit');
      onLog?.call('NVRAM committed.', isSuccess: true);
      onLog?.call('Config written to wgc$slot (disabled).', isSuccess: true);
      await _logRouter('Created wgc$slot configuration ($regionId)');
    } catch (e) {
      if (backup != null) {
        onLog?.call('Create failed, restoring wgc$slot config...', isError: true);
        try {
          for (final entry in backup.entries) {
            await client.run('nvram set ${entry.key}="${entry.value}"');
          }
          await client.run('nvram commit');
          onLog?.call('wgc$slot config restored.', isSuccess: true);
        } catch (_) {
          onLog?.call('CRITICAL: could not restore wgc$slot. Check router manually.', isError: true);
        }
      }
      rethrow;
    }
  }

  // ── Enable (with connectivity check + revert-on-failure) ────────────────────────
  // Brings the interface up, waits for it to appear, then pings BOTH watchdog targets via
  // the slot interface (5s). Any failure reverts enable=0 and throws (spec 2.1.2, decision #2).
  Future<void> enableSlot(int slot, {required String primaryIp, required String secondaryIp}) async {
    onLog?.call('Enabling wgc$slot...');
    await _run('nvram set wgc${slot}_enable=1');
    await _run('nvram commit');
    await _run('service "start_wgc $slot"; service restart_vpnrouting0');

    onLog?.call('Verifying wgc$slot interface comes up...');
    var up = false;
    for (var retry = 0; retry < verifyMaxAttempts; retry++) {
      await Future.delayed(verifyPollInterval);
      final out = await _run('wg show interfaces');
      if (out.contains('wgc$slot')) {
        up = true;
        onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: wgc$slot is active');
        break;
      }
      onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: wgc$slot not yet active');
    }
    if (!up) {
      await _revertEnable(slot);
      throw Exception(
          'wgc$slot did not come up — the configuration may have expired. Recreate it with CREATE, then ENABLE.');
    }

    final primaryOk = await pingViaSlot(primaryIp, slot);
    final secondaryOk = await pingViaSlot(secondaryIp, slot);
    await _logRouter('wgc$slot ENABLE connectivity check: '
        'primary $primaryIp ${primaryOk ? 'OK' : 'FAIL'}, secondary $secondaryIp ${secondaryOk ? 'OK' : 'FAIL'}');
    if (!primaryOk || !secondaryOk) {
      await _revertEnable(slot);
      throw Exception('Connectivity check failed via wgc$slot '
          '(primary $primaryIp ${primaryOk ? 'OK' : 'FAIL'}, secondary $secondaryIp ${secondaryOk ? 'OK' : 'FAIL'}). '
          'Slot left disabled.');
    }
    await _logRouter('Enabled wgc$slot');
    onLog?.call('wgc$slot enabled and verified.', isSuccess: true);
  }

  Future<void> _revertEnable(int slot) async {
    onLog?.call('Reverting wgc$slot to disabled...', isError: true);
    await _run('nvram set wgc${slot}_enable=0');
    await _run('nvram commit');
    await _run('service "stop_wgc $slot"; service start_vpnrouting0');
  }

  // ── Disable ─────────────────────────────────────────────────────────────────────
  Future<void> disableSlot(int slot) async {
    onLog?.call('Disabling wgc$slot...');
    await _run('nvram set wgc${slot}_enable=0');
    await _run('nvram commit');
    await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    await _logRouter('Disabled wgc$slot');
    onLog?.call('wgc$slot disabled.', isSuccess: true);
  }

  // ── Delete (clear the slot's WireGuard config) ────────────────────────────────────
  Future<void> deleteSlot(int slot) async {
    onLog?.call('Deleting wgc$slot configuration...');
    await _run('nvram set wgc${slot}_enable=0');
    await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    for (final key in kSlotNvramKeys) {
      await _run('nvram unset wgc${slot}_$key');
    }
    await _run('nvram commit');
    await _logRouter('Deleted wgc$slot configuration');
    onLog?.call('wgc$slot configuration cleared.', isSuccess: true);
  }

  // ── Edit: write the user-editable slot parameters back ────────────────────────────
  // [params] keys are bare (e.g. 'addr', 'priv'). Values are shell-escaped.
  Future<void> writeSlotParams(int slot, Map<String, String> params) async {
    onLog?.call('Saving wgc$slot parameters...');
    for (final e in params.entries) {
      await _run('nvram set wgc${slot}_${e.key}=${shellSingleQuote(e.value)}');
    }
    await _run('nvram commit');
    onLog?.call('wgc$slot parameters saved.', isSuccess: true);
  }

  // ── Watchdog ping-target NVRAM (shared with the ENABLE check & the watchdog script) ─
  Future<(String, String)> readWatchdogPingTargets(int slot) async {
    final primary = await _run('nvram get wgc${slot}_wd_primary_ip');
    final secondary = await _run('nvram get wgc${slot}_wd_secondary_ip');
    return (primary, secondary);
  }

  Future<void> writeWatchdogPingTargets(int slot, String primaryIp, String secondaryIp) async {
    await _run('nvram set wgc${slot}_wd_primary_ip=${shellSingleQuote(primaryIp)}');
    await _run('nvram set wgc${slot}_wd_secondary_ip=${shellSingleQuote(secondaryIp)}');
    await _run('nvram commit');
  }

  // Ping bound to the VPN interface with a 5s timeout (spec 2.1.2).
  Future<bool> pingViaSlot(String ip, int slot) async {
    try {
      final out = await _run('ping -I wgc$slot -c 1 -W 5 ${shellSingleQuote(ip)} >/dev/null 2>&1 && echo OK || echo FAIL');
      return out == 'OK';
    } catch (_) {
      return false;
    }
  }
}
