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

import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'firmware.dart';
import 'router_watchdog.dart' show shellSingleQuote, kWatchdogLogTag;

// The per-slot WireGuard NVRAM keys (without the `wgcN_` prefix), in the order router_push.dart
// wrote them. Used for backup/restore, delete, and the parameter editor.
const List<String> kSlotNvramKeys = [
  'addr', // This is the local tunnel IP address assigned to the router by the VPN server in CIDR notation (e.g., `10.x.x.x/32`). This field is user editable.
  'alive', // The persistent keepalive interval, set to 25 (seconds) by default. This field is user editable.
  'desc', // The slot's PIA region name. This must match the actual PIA region name for the watchdog function to operate. _(include that as a comment next to this field)_. This field is user editable.
  'dns', // The two DNS servers to use. Optional, but defaults to `"9.9.9.9, 149.112.112.112"`. This field is user editable.
  'enable', // When set to `1` this enables this slot; when set to `0` this slot is disabled. This field is not user editable and its value is set by the ENABLE and DISABLE buttons in 2.1.2.
  'enforce', // When set to `1` this enables the killswitch on this slot; when set to `0` it is disabled. The killswitch blocks routed clients if the tunnel goes down. This field is user editable.
  'ep_addr', // The domain name (FQDN) or public IP address of the remote PIA WireGuard server (peer endpoint) you are connecting to. This field is user editable.
  'ep_addr_r', // If `wgcN_ep_addr` contains either a DNS name or an IP address, this is the resolved numeric IP address; if `wgcN_ep_addr` contains a direct IP address, this field will hold an identical value. This field is not user editable and is set when the interface is initialised.
  'ep_port', // The endpoint port, defaulting to `1337` for PIA. This field is user editable.
  'fw', // Set to `1` to enable the inbound firewall on this slot; set to `0` to disable it. This field is user editable.
  'mtu', // The MTU (Maximum Transmission Unit), set to `1420` by default. This field is user editable.
  'nat', // Set to `1` to enable network address translation (NAT); set to `0` to disable NAT. This field is user editable.
  'ppub', // The PIA VPN server public key. This field is user editable.
  'priv', // The PIA user's private key. This field should be rendered as an obscured input (like a password field) with a show/hide toggle, consistent with how SSH and PIA credentials are handled elsewhere in the app. This field is user editable.
  'psk', // This value is not used by PIA and is read-only for the user (reserved for a preshared key). This field is not user editable.
  'rip', // Stores the router's current external public IP address as seen by the internet. This field is not user editable.
  'aips', //The allowed IP addresses, defaults to `0.0.0.0/0`. This field is user editable.
];

// The five keys Merlin exposes that stock firmware does not (ARCHITECTURE.md). `desc` is
// absent from stock too, but the app writes it anyway as a private key of its own — the router-side
// watchdog needs the region name somewhere it can read with a bare `nvram get`, exactly as it
// already does for the extra `wgcN_wd_*` keys. Stock therefore skips only these three.
const List<String> kMerlinOnlySlotKeys = ['enforce', 'fw', 'rip'];

// The per-slot NVRAM keys worth writing on [firmware]: all 17 on Merlin, 13 on stock.
List<String> slotKeysFor(RouterFirmware firmware) => firmware == RouterFirmware.stock
    ? [
        for (final k in kSlotNvramKeys)
          if (!kMerlinOnlySlotKeys.contains(k)) k,
      ]
    : kSlotNvramKeys;

// ─── vpnc_clientlist (stock only) ─────────────────────────────────────────────────────
// Stock consolidates the region name and the active flag into one delimited nvram string holding
// up to five profiles: records separated by '<' (no leading delimiter), fields by '>'.
// See ARCHITECTURE.md 2.3.2 for the field schema.

// One `vpnc_clientlist` profile. Field numbers in the ARCHITECTURE.md are 1-based; [fields] is **0-based**.
class VpncRecord {
  static const int fieldCount = 12;
  static const int _descIdx = 0,
      _protocolIdx = 1,
      _slotIdx = 2,
      _routerPwd = 4,
      _activeIdx = 5,
      _iptablesIdx = 6,
      _tunnelIdx = 9,
      _wanIdx = 10,
      _tailIdx = 11;

  final List<String> fields;

  VpncRecord(List<String> fields) : fields = List.unmodifiable(_sized(fields));

  // Pads short records so field access is total; longer records keep their extra fields, since
  // the app must never discard something a future firmware appended.
  static List<String> _sized(List<String> f) =>
      f.length >= fieldCount ? List.of(f) : [...f, ...List.filled(fieldCount - f.length, '')];

  String get desc => fields[_descIdx];
  String get protocol => fields[_protocolIdx];
  int? get slot => int.tryParse(fields[_slotIdx].trim());
  bool get active => fields[_activeIdx] == '1';

  // Rewrites only the two fields the app owns; everything else is carried through untouched.
  VpncRecord copyWith({String? desc, bool? active}) {
    final next = List.of(fields);
    if (desc != null) next[_descIdx] = desc;
    if (active != null) next[_activeIdx] = active ? '1' : '0';
    return VpncRecord(next);
  }

  String serialise() => fields.join('>');
}

// Builds a record for a slot that has none yet. Fields 4, 5, 8 and 9 are left empty; the
// iptables ID (field 7) follows the `10 - slot` pattern observed on stock hardware.
VpncRecord buildVpncRecord({required int slot, required String desc, required bool active}) {
  final fields = List.filled(VpncRecord.fieldCount, '');
  fields[VpncRecord._descIdx] = desc;
  fields[VpncRecord._protocolIdx] = 'WireGuard';
  fields[VpncRecord._slotIdx] = '$slot';
  fields[VpncRecord._routerPwd] = 'password';
  fields[VpncRecord._activeIdx] = active ? '1' : '0';
  fields[VpncRecord._iptablesIdx] = '${10 - slot}';
  fields[VpncRecord._tunnelIdx] = '0';
  fields[VpncRecord._wanIdx] = '0';
  fields[VpncRecord._tailIdx] = 'cfg-pia-wg';
  return VpncRecord(fields);
}

List<VpncRecord> parseVpncClientlist(String raw) => [
      for (final chunk in raw.trim().split('<'))
        if (chunk.isNotEmpty) VpncRecord(chunk.split('>')),
    ];

String serialiseVpncClientlist(List<VpncRecord> records) => records.map((r) => r.serialise()).join('<');

/// Updates the record for [slot] in place, or appends a fresh one when the slot has none.
List<VpncRecord> upsertVpncRecord(List<VpncRecord> records, {required int slot, String? desc, bool? active}) {
  final out = List.of(records);
  final idx = out.indexWhere((r) => r.slot == slot);
  if (idx >= 0) {
    out[idx] = out[idx].copyWith(desc: desc, active: active);
  } else {
    out.add(buildVpncRecord(slot: slot, desc: desc ?? '', active: active ?? false));
  }
  return out;
}

List<VpncRecord> removeVpncRecord(List<VpncRecord> records, int slot) => [
      for (final r in records)
        if (r.slot != slot) r,
    ];

/// The 0-based position of [slot]'s record in vpnc_clientlist — what stock's `vpnc_unit` selects.
/// Null when the slot has no profile.
///
/// Measured against the WebUI, which is the reference implementation: with rows
/// `[slot 5, slot 1]`, enabling the slot-1 profile makes the WebUI write `vpnc_unit=1`.
///
/// This is NOT `5 - slot`. The WebUI can only create profiles in slot order 5,4,3,2,1, so for any
/// list it built the row index and `5 - slot` are the same number — which is how the wrong rule
/// went unnoticed. The app lets the user pick any slot, so its lists can be out of that order, and
/// there only the row index holds. Row index is a strict generalisation: it agrees with `5 - slot`
/// on every WebUI-ordered list, so it cannot regress the case that already worked.
int? vpncUnitForSlot(List<VpncRecord> records, int slot) {
  final idx = records.indexWhere((r) => r.slot == slot);
  return idx < 0 ? null : idx;
}

// Opens a real SSH client to the router. Screens inject a test factory instead in tests.
Future<SSHClient> openSshClient(String ip, String user, String pass) async {
  final socket = await SSHSocket.connect(ip, 22, timeout: const Duration(seconds: 5));
  final client = SSHClient(socket, username: user, onPasswordRequest: () => pass);
  await client.authenticated;
  return client;
}

// Per-slot summary shown in the slot modal.
class SlotInfo {
  final int index;
  final String desc; // wgcN_desc (region name); empty => unconfigured
  final bool killSwitch; // wgcN_enforce == 1 (Merlin only; always false on stock)
  final bool enabled; // wgcN_enable == 1 on Merlin, vpnc_clientlist field 6 on stock
  final bool watchdogActive; // cru has watchdog_wgcN
  final bool emailAlerting; // wgcN_wd_email_enabled == 1 (only meaningful while watchdogActive)
  const SlotInfo({
    required this.index,
    required this.desc,
    required this.killSwitch,
    required this.enabled,
    required this.watchdogActive,
    this.emailAlerting = false,
  });

  bool get isEmpty => desc.trim().isEmpty;
}

// Result of [RouterSlotService.fetchSlots].
class RouterSlots {
  final Map<int, SlotInfo> slots; // keys 1..5
  // Every slot whose interface is up per `wg show interfaces`. A Set, not a single index: stock
  // permits more than one tunnel at a time (vpnc_max_conn), and reporting only the first hid that.
  final Set<int> activeSlots;
  // Informational only — branching reads the session flag in firmware.dart. Kept so the two do not
  // silently disagree; folding them together is a job for the planned firmware abstraction.
  final bool isMerlin;
  const RouterSlots({required this.slots, required this.activeSlots, required this.isMerlin});
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
    // how many times to try to connect on this interface before pronouncing it dead
    this.verifyMaxAttempts = 5,
  });

  Future<String> _run(String cmd) async => utf8.decode(await client.run(cmd)).trim();

  // Best-effort router syslog entry (mirrors RouterWatchdog._logRouter); never fails the action.
  Future<void> _logRouter(String msg) async {
    try {
      await _run('logger -t $kWatchdogLogTag ${shellSingleQuote(msg)}');
    } catch (_) {}
  }

  // ── Firmware detection (spec: once per app session, on entry to either router screen) ────
  // Raw `nvram get 3rd-party` output for firmware.dart's classifyFirmwareTag. Throws on a non-zero
  // exit, an SSH failure, or a stalled channel; the caller treats any of those as "not detected".
  Future<String> readFirmwareTag() async => _run('nvram get 3rd-party').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timed out after 5s reading the router firmware type.'),
      );

  // Which of the stock helper binaries are absent, in probe order. [needMailsend] is false on the
  // manage screen, which never sends email.
  Future<List<String>> missingStockBinaries({required bool needMailsend}) async {
    final missing = <String>[];
    for (final path in [kStockJqPath, if (needMailsend) kStockMailsendPath]) {
      if ((await _run("[ -x '$path' ] && echo 1 || echo 0")) != '1') missing.add(path);
    }
    return missing;
  }

  // Reads vpnc_clientlist and indexes it by slot number (stock only).
  Future<Map<int, VpncRecord>> _readVpncBySlot() async {
    final records = parseVpncClientlist(await _run('nvram get vpnc_clientlist'));
    return {
      for (final r in records)
        if (r.slot != null) r.slot!: r,
    };
  }

  // Read/modify/write of vpnc_clientlist. The caller commits.
  Future<void> _editVpncClientlist(List<VpncRecord> Function(List<VpncRecord>) edit) async {
    final current = parseVpncClientlist(await _run('nvram get vpnc_clientlist'));
    await _run('nvram set vpnc_clientlist=${shellSingleQuote(serialiseVpncClientlist(edit(current)))}');
  }

  // Mirrors an enable/disable into the stock active flag; a no-op on Merlin.
  Future<void> _setVpncActive(int slot, bool active) async {
    if (!isStockFirmware) return;
    await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, active: active));
  }

  // Stock drives WireGuard through VPN Fusion: point `vpnc_unit` at the profile's ROW in
  // vpnc_clientlist (see vpncUnitForSlot), then issue the service command.
  //
  // Callers must get the ordering right: read the unit AFTER any upsert that could append the
  // row (enable), and BEFORE any removal that drops it (delete).
  //
  // Returns false when the slot has no profile. [required] turns that into an error — enabling a
  // slot that VPN Fusion does not know about cannot work, whereas stopping one is already a no-op.
  Future<bool> _runVpncService(int slot, String serviceCmd, {bool required = false}) async {
    final unit = vpncUnitForSlot(parseVpncClientlist(await _run('nvram get vpnc_clientlist')), slot);
    if (unit == null) {
      if (required) {
        throw Exception('wgc$slot has no vpnc_clientlist profile on the router. Create it with CREATE first.');
      }
      onLog?.call('wgc$slot has no vpnc_clientlist profile; nothing to stop.');
      return false;
    }
    final msg = 'wgc$slot is vpnc_clientlist row $unit; nvram set vpnc_unit=$unit, service $serviceCmd';
    onLog?.call(msg);
    await _logRouter(msg);
    await _run('nvram set vpnc_unit=$unit');
    await _run('service $serviceCmd');
    return true;
  }

  // ── Read ────────────────────────────────────────────────────────────────────────────
  Future<RouterSlots> fetchSlots() async {
    onLog?.call('Reading router configuration...');
    final isMerlin = (await _run('nvram get 3rd-party')) == 'merlin';
    final stock = isStockFirmware;
    // On stock the region name and active flag live in vpnc_clientlist, not in per-slot keys.
    final vpnc = stock ? await _readVpncBySlot() : const <int, VpncRecord>{};

    final slots = <int, SlotInfo>{};
    for (int i = 1; i <= 5; i++) {
      final desc = stock ? (vpnc[i]?.desc ?? '') : await _run('nvram get wgc${i}_desc');
      // Stock exposes no kill switch (ARCHITECTURE.md 2.3.1), so the badge never lights there.
      final killSwitch = stock ? false : (await _run('nvram get wgc${i}_enforce')) == '1';
      final enabled = stock ? (vpnc[i]?.active ?? false) : (await _run('nvram get wgc${i}_enable')) == '1';
      // cru exists on both firmwares, so the watchdog probe is firmware-independent.
      final watchdog = (await _run('cru l | grep -qw watchdog_wgc$i && echo 1 || echo 0')) == '1';
      // Email alerting is a watchdog feature; only read it for an active watchdog.
      final emailAlerting = watchdog && (await _run('nvram get wgc${i}_wd_email_enabled')) == '1';
      slots[i] = SlotInfo(
          index: i, desc: desc, killSwitch: killSwitch, enabled: enabled, watchdogActive: watchdog, emailAlerting: emailAlerting);
    }

    // allMatches, not firstMatch: more than one tunnel can be up, and taking only the first
    // silently badged an arbitrary one of them.
    final ifaceOutput = await _run('wg show interfaces');
    final activeSlots = RegExp(r'wgc(\d)').allMatches(ifaceOutput).map((m) => int.parse(m.group(1)!)).toSet();

    if (slots.values.every((s) => s.isEmpty)) {
      onLog?.call('All WireGuard slots are unconfigured.');
    }
    onLog?.call('Successfully retrieved router config.', isSuccess: true);
    return RouterSlots(slots: slots, activeSlots: activeSlots, isMerlin: isMerlin);
  }

  // Reads every per-slot NVRAM value (bare-keyed map) for the parameter editor. Keys the running
  // firmware does not have resolve to '' so the editor can key off presence without a null check.
  Future<Map<String, String>> readSlotParams(int slot) async {
    final live = slotKeysFor(routerFirmware);
    final m = {for (final k in kSlotNvramKeys) k: ''};
    for (final k in live) {
      m[k] = await _run('nvram get wgc${slot}_$k');
    }
    return m;
  }

  // ── Parse helper (from router_push.dart) ────────────────────────────────────────────
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

  // ── Create (write to NVRAM, leave DISABLED, do not touch the active tunnel) ─────────
  // Mirrors router_push.dart Step 4 but sets enable=0 and skips the stop/start/verify.
  Future<void> createConfigToSlot({required int slot, required String config, required String regionId}) async {
    final wgMap = parseWgConfig(config);
    final epParts = wgMap['Endpoint']?.split(':') ?? [];
    final epIp = epParts.isNotEmpty ? epParts[0] : '';
    final epPort = epParts.length > 1 ? epParts[1] : '1337';

    // Written in kSlotNvramKeys order; stock skips the four keys its firmware does not have.
    final values = <String, String>{
      'addr': '"${wgMap['Address'] ?? ''}"',
      'alive': '25',
      'desc': '"$regionId"',
      'dns': '"${wgMap['DNS'] ?? ''}"',
      'enable': '0', // created but not active (spec 2.1.2)
      'enforce': '0', // kill switch off on create (round-2)
      'ep_addr': '"$epIp"',
      'ep_addr_r': '""',
      'ep_port': '"$epPort"',
      'fw': '1',
      'mtu': '"${wgMap['MTU'] ?? '1420'}"',
      'nat': '1',
      'ppub': '"${wgMap['PublicKey'] ?? ''}"',
      'priv': '"${wgMap['PrivateKey'] ?? ''}"',
      'psk': '""',
      'rip': '""',
      'aips': '"${wgMap['AllowedIPs'] ?? '0.0.0.0/0'}"',
    };
    final stock = isStockFirmware;
    final keys = slotKeysFor(routerFirmware);

    Map<String, String>? backup;
    String? vpncBackup;
    try {
      // On stock the desc mirror is only present for slots this app created — a profile made in
      // the router web UI shows up in vpnc_clientlist alone, and must still be backed up.
      final existingDesc = await _run('nvram get wgc${slot}_desc');
      final existingVpnc = stock ? await _run('nvram get vpnc_clientlist') : '';
      final occupied = existingDesc.isNotEmpty || (stock && parseVpncClientlist(existingVpnc).any((r) => r.slot == slot));
      if (occupied) {
        onLog?.call('Backing up existing wgc$slot config...');
        backup = {};
        for (final key in keys) {
          backup['wgc${slot}_$key'] = await _run('nvram get wgc${slot}_$key');
        }
        if (stock) vpncBackup = existingVpnc;
      }

      onLog?.call('Writing NVRAM for wgc$slot...');
      for (final key in keys) {
        await _run('nvram set wgc${slot}_$key=${values[key]}');
      }
      // Stock keeps the region name and active flag here, so the router web UI sees the slot too.
      if (stock) {
        await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, desc: regionId, active: false));
      }
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
          if (vpncBackup != null) {
            await client.run('nvram set vpnc_clientlist=${shellSingleQuote(vpncBackup)}');
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

  // ── Enable (with connectivity check + revert-on-failure) ────────────────────────────
  // Brings the interface up, waits for it to appear, then pings BOTH watchdog targets via
  // the slot interface (5s). Any failure reverts enable=0 and throws.
  Future<void> enableSlot(int slot, {required String primaryIp, required String secondaryIp}) async {
    onLog?.call('Enabling wgc$slot...');
    await _logRouter('Enabling wgc$slot...');
    await _run('nvram set wgc${slot}_enable=1');
    await _setVpncActive(slot, true);
    // Commit before the service call, so the service can never read a half-written slot.
    await _run('nvram commit');
    // stock requires a different start command to Merlin
    if (isStockFirmware) {
      // Must follow _setVpncActive: upsert appends a row for a slot that had none, and the unit
      // is that row's index. There is no start_vpnc on stock (ARCHITECTURE.md 4.2.2).
      await _runVpncService(slot, 'restart_vpnc', required: true);
    } else {
      await _run('service "start_wgc $slot"; service restart_vpnrouting0');
    }

    onLog?.call('Verifying wgc$slot interface comes up...');
    var up = false;
    for (var retry = 0; retry < verifyMaxAttempts; retry++) {
      await Future.delayed(verifyPollInterval);
      final out = await _run('wg show interfaces');
      onLog?.call('  wg show interfaces: ${out.isEmpty ? '(none)' : out}');
      await _logRouter('wg show interfaces: ${out.isEmpty ? '(none)' : out}');
      if (out.contains('wgc$slot')) {
        up = true;
        onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: wgc$slot is active');
        break;
      }
      onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: wgc$slot not yet active');
    }
    if (!up) {
      await _revertEnable(slot);
      throw Exception('wgc$slot did not come up — the configuration may have expired. Recreate it with CREATE, then ENABLE.');
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
    await _setVpncActive(slot, false);
    await _run('nvram commit');
    // stock requires a different stop command to Merlin
    if (isStockFirmware) {
      await _runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
  }

  // ── Disable ─────────────────────────────────────────────────────────────────────────
  Future<void> disableSlot(int slot) async {
    onLog?.call('Disabling wgc$slot...');
    await _run('nvram set wgc${slot}_enable=0');
    await _setVpncActive(slot, false);
    await _run('nvram commit');
    // stock requires a different stop command to Merlin. `restart_vpnc` clears the nvram flags but
    // leaves the interface up (ARCHITECTURE.md 4.2.3 specifies stop_vpnc) — that mismatch is what
    // left a tunnel running behind a WebUI that reported it disconnected.
    if (isStockFirmware) {
      await _runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    await _logRouter('Disabled wgc$slot');
    onLog?.call('wgc$slot disabled.', isSuccess: true);
  }

  // ── Delete (clear the slot's WireGuard config) ──────────────────────────────────────
  Future<void> deleteSlot(int slot) async {
    onLog?.call('Deleting wgc$slot configuration...');
    await _run('nvram set wgc${slot}_enable=0');
    // stock requires a different stop command to Merlin. Must precede removeVpncRecord below:
    // the unit is the row's index, so dropping the row first would lose it.
    if (isStockFirmware) {
      await _runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    for (final key in slotKeysFor(routerFirmware)) {
      await _run('nvram unset wgc${slot}_$key');
    }
    // also clear ping target keys
    await _run('nvram unset wgc${slot}_wd_primary_ip');
    await _run('nvram unset wgc${slot}_wd_secondary_ip');
    if (isStockFirmware) {
      await _editVpncClientlist((recs) => removeVpncRecord(recs, slot));
    }
    await _run('nvram commit');
    await _logRouter('Deleted wgc$slot configuration');
    onLog?.call('wgc$slot configuration cleared.', isSuccess: true);
  }

  // ── Edit: write the user-editable slot parameters back ──────────────────────────────
  // [params] keys are bare (e.g. 'addr', 'priv'). Values are shell-escaped.
  Future<void> writeSlotParams(int slot, Map<String, String> params) async {
    onLog?.call('Saving wgc$slot parameters...');
    final live = slotKeysFor(routerFirmware);
    for (final e in params.entries) {
      if (!live.contains(e.key)) continue; // stock has no enforce / fw / ep_addr_r / rip
      await _run('nvram set wgc${slot}_${e.key}=${shellSingleQuote(e.value)}');
    }
    // On stock the region must stay in step with its vpnc_clientlist record, which is what the
    // router web UI and fetchSlots both read.
    if (isStockFirmware && params.containsKey('desc')) {
      await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, desc: params['desc']));
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

// ── Ping bound to the VPN interface with a 5s timeout ─────────────────────────────────
  Future<bool> pingViaSlot(String ip, int slot) async {
    final safeIp = shellSingleQuote(ip);
    final String cmd;

    if (isStockFirmware) {
      // Stock BusyBox ping requires a source IP address instead of an interface name.
      cmd = '''
      ADDR=\$(ip -4 addr show wgc$slot 2>/dev/null)
      case "\$ADDR" in
        *inet*)
          IP=\${ADDR#*inet }
          ping -I \${IP%%/*} -c 1 -w 5 $safeIp >/dev/null 2>&1 && echo OK
          ;;
      esac
      ''';
    } else {
      // Merlin firmware ping accepts interface name.
      cmd = 'ping -I wgc$slot -c 1 -w 5 $safeIp >/dev/null 2>&1 && echo OK';
    }

    try {
      final out = await _run(cmd);
      return out.trim() == 'OK';
    } catch (_) {
      return false;
    }
  }
}
