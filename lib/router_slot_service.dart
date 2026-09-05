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
import 'router_watchdog.dart' show buildLoggerCommand, shellSingleQuote;

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

/// VPN Fusion runtime state the firmware writes per slot while a profile is up, and leaves behind
/// when it stops. Indexed by SLOT (`vpnc5_*` for wgc5), unlike `vpnc_unit`, which indexes the
/// vpnc_clientlist row. Stock only - Merlin does not drive WireGuard through VPN Fusion.
///
/// `vpncN_dns` is deliberately not here: it survives a stop too, but was left out of the DELETE
/// sweep by choice.
const List<String> kVpncRuntimeKeys = ['dut_disc', 'sbstate_t', 'state_t'];

/// Concurrent-tunnel cap assumed on stock when `vpnc_max_conn` cannot be read. Raising it on the
/// router is possible, but values above 2 are documented to break boot.
const int kDefaultStockMaxActiveSlots = 2;

// ─── Slot description / label ─────────────────────────────────────────────────────────
// A router can hold VPNs this app knows nothing about, so every description it writes carries a
// prefix. The description is ALSO the PIA region id the router-side watchdog looks up, so the
// script strips the prefix again before its jq `select(.id==$id)` - see regionIdFromDesc and the
// REGION line in _kWatchdogScriptTemplate. Change one and you must change the other.

/// Marks a slot description as written by this app.
const String kSlotDescPrefix = 'pia-';

/// The description to store for [regionId]. Idempotent, so re-saving a slot never compounds the
/// prefix into 'pia-pia-...'.
String slotDescFor(String regionId) {
  final id = regionId.trim();
  return (id.isEmpty || id.startsWith(kSlotDescPrefix)) ? id : '$kSlotDescPrefix$id';
}

/// The bare PIA region id behind a stored description - the inverse of [slotDescFor], and tolerant
/// of descriptions written before the prefix existed. Mirrors `${DESC#pia-}` in the router script.
String regionIdFromDesc(String desc) {
  final d = desc.trim();
  return d.startsWith(kSlotDescPrefix) ? d.substring(kSlotDescPrefix.length) : d;
}

/// How a slot is named in every app-log and router-syslog line: 'wgcN', or `wgcN:<description>`
/// once one is known, so a message says which VPN it is about.
String slotLabel(int slot, String desc) => desc.trim().isEmpty ? 'wgc$slot' : 'wgc$slot:${desc.trim()}';

/// Reads a slot's description from the router and formats it with [slotLabel].
///
/// Stock keeps the authoritative description in vpnc_clientlist field 0 - a profile created in the
/// router WebUI has no `wgcN_desc` mirror at all. Merlin has no clientlist, so `wgcN_desc` is it.
///
/// Best-effort by design: a label is decoration, so a failed lookup degrades to the bare 'wgcN'
/// rather than breaking the action being logged or masking the real error.
Future<String> fetchSlotLabel(int slot, Future<String> Function(String cmd) run) async {
  try {
    var desc = '';
    if (isStockFirmware) {
      for (final r in parseVpncClientlist(await run('nvram get vpnc_clientlist'))) {
        if (r.slot == slot) {
          desc = r.desc;
          break;
        }
      }
    } else {
      desc = await run('nvram get wgc${slot}_desc');
    }
    return slotLabel(slot, desc);
  } catch (_) {
    return 'wgc$slot';
  }
}

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

  /// Field 7. Documented as an "iptables ID", but it is also what VPN Fusion uses to index this
  /// profile's runtime state keys - `vpnc9_state_t` for a record whose field 7 is 9.
  /// See [vpncStateIndexForSlot].
  int? get vpncStateIndex => int.tryParse(fields[_iptablesIdx].trim());

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

/// The index VPN Fusion uses for [slot]'s runtime state keys (`vpnc<N>_state_t` and friends), taken
/// from the profile's vpnc_clientlist field 7.
///
/// NOT the slot number, and not [vpncUnitForSlot] - three different indexes on the same profile.
/// Measured: wgc1, whose field 7 is 9, leaves `vpnc9_*` behind. An earlier reading of "slot number"
/// came from wgc5, where slot and field 7 are both 5 and so cannot tell the two apart.
///
/// Falls back to `10 - slot` when the slot has no record - what [buildVpncRecord] and the WebUI
/// both write. Reading the field rather than always computing it is a strict generalisation: the
/// two agree on every record seen so far, and reading stays right if one ever carries something
/// else.
int vpncStateIndexForSlot(List<VpncRecord> records, int slot) {
  for (final r in records) {
    if (r.slot == slot) return r.vpncStateIndex ?? (10 - slot);
  }
  return 10 - slot;
}

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
  final bool watchdogActive; // cru has watchdog_wgcN - i.e. it is SCHEDULED
  // wgcN_wd_check_interval is set: the watchdog's settings are on the router even if its cron
  // entry is not. That is what DISABLE leaves behind, and what ENABLE needs to put it back.
  final bool watchdogConfigured;
  final bool emailAlerting; // wgcN_wd_email_enabled == 1 (only meaningful while watchdogActive)
  const SlotInfo({
    required this.index,
    required this.desc,
    required this.killSwitch,
    required this.enabled,
    required this.watchdogActive,
    this.watchdogConfigured = false,
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
  // How many tunnels may run at once, or null for no limit. Stock enforces a cap (vpnc_max_conn,
  // normally 2); Merlin has no equivalent setting and is left unlimited.
  final int? maxActiveSlots;
  final bool isMerlin;
  const RouterSlots({
    required this.slots,
    required this.activeSlots,
    required this.isMerlin,
    this.maxActiveSlots,
  });
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

  // 'wgcN:<description>' for log lines. Cached because a service instance is short-lived (one
  // per user action), so the description is read at most once however many lines it appears in.
  final Map<int, String> _labelCache = {};
  Future<String> _label(int slot) async => _labelCache[slot] ??= await fetchSlotLabel(slot, _run);

  // Best-effort router syslog entry (mirrors RouterWatchdog._logRouter); never fails the action.
  Future<void> _logRouter(String msg) async {
    try {
      await _run(buildLoggerCommand(msg));
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

  // Stock's cap on simultaneous tunnels. Falls back to [kDefaultStockMaxActiveSlots] when the key
  // is missing or unparseable.
  Future<int> _readMaxActiveSlots() async {
    final raw = int.tryParse(await _run('nvram get vpnc_max_conn'));
    return (raw == null || raw < 1) ? kDefaultStockMaxActiveSlots : raw;
  }

  // Read/modify/write of vpnc_clientlist. The caller commits.
  Future<void> _editVpncClientlist(List<VpncRecord> Function(List<VpncRecord>) edit) async {
    final current = parseVpncClientlist(await _run('nvram get vpnc_clientlist'));
    await _run('nvram set vpnc_clientlist=${shellSingleQuote(serialiseVpncClientlist(edit(current)))}');
  }

  /// Writes the slot's description and/or active flag into `vpnc_clientlist`. A no-op on Merlin,
  /// which keeps both in per-slot NVRAM keys instead.
  ///
  /// Public because the watchdog deploy path needs it too: on stock this list is where
  /// [fetchSlots] reads the region name from, so a slot missing its row reads as unconfigured and
  /// the modal greys out every button that needs a description.
  Future<void> writeVpncProfile(int slot, {String? desc, bool? active}) async {
    if (!isStockFirmware) return;
    await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, desc: desc, active: active));
  }

  // Mirrors an enable/disable into the stock active flag; a no-op on Merlin.
  //
  // Carries the description as well: upsert APPENDS a row for a slot that has none, and a row
  // without a description shows as an empty slot in both this app and the router's own WebUI.
  // wgcN_desc is written by every path that creates a slot on stock, so it is the source to
  // repair from.
  Future<void> _setVpncActive(int slot, bool active) async {
    if (!isStockFirmware) return;
    final desc = (await _run('nvram get wgc${slot}_desc')).trim();
    await writeVpncProfile(slot, desc: desc.isEmpty ? null : desc, active: active);
  }

  // Stock drives WireGuard through VPN Fusion: point `vpnc_unit` at the profile's ROW in
  // vpnc_clientlist (see vpncUnitForSlot), then issue the service command.
  //
  // Callers must get the ordering right: read the unit AFTER any upsert that could append the
  // row (enable), and BEFORE any removal that drops it (delete).
  //
  // Returns false when the slot has no profile. [required] turns that into an error — enabling a
  // slot that VPN Fusion does not know about cannot work, whereas stopping one is already a no-op.
  /// Public so `RouterWatchdog` starts and stops a stock tunnel exactly as MANAGE does.
  Future<bool> runVpncService(int slot, String serviceCmd, {bool required = false}) async {
    final unit = vpncUnitForSlot(parseVpncClientlist(await _run('nvram get vpnc_clientlist')), slot);
    if (unit == null) {
      if (required) {
        throw Exception('wgc$slot has no vpnc_clientlist profile on the router. Create it with CREATE first.');
      }
      onLog?.call('wgc$slot has no vpnc_clientlist profile; nothing to stop.');
      return false;
    }
    final msg = '${await _label(slot)} is vpnc_clientlist row $unit; nvram set vpnc_unit=$unit, service $serviceCmd';
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
      // Stock keeps the region name in vpnc_clientlist, but fall back to wgcN_desc when the row
      // is missing or blank: a watchdog deployed before the deploy path wrote that row leaves the
      // slot looking empty, which greys out every button that needs a description. DELETE unsets
      // wgcN_desc along with the row, so this cannot resurrect a deleted slot.
      var desc = stock ? (vpnc[i]?.desc ?? '') : await _run('nvram get wgc${i}_desc');
      if (stock && desc.trim().isEmpty) desc = await _run('nvram get wgc${i}_desc');
      // Stock exposes no kill switch (ARCHITECTURE.md 2.3.1), so the badge never lights there.
      final killSwitch = stock ? false : (await _run('nvram get wgc${i}_enforce')) == '1';
      final enabled = stock ? (vpnc[i]?.active ?? false) : (await _run('nvram get wgc${i}_enable')) == '1';
      // A cron entry alone is not a watchdog: a failed deploy left cru pointing at a script that
      // was never written, and the app called that ACTIVE. Both have to be there.
      final watchdog = (await _run("cru l | grep -qw watchdog_wgc$i && [ -s '${watchdogScriptPath(i)}' ] "
              '&& echo 1 || echo 0')) ==
          '1';
      // Settings can outlive the cron entry: DISABLE removes the schedule and keeps the config.
      final watchdogConfigured = (await _run('nvram get wgc${i}_wd_check_interval')).isNotEmpty;
      // Email alerting is a watchdog feature; only read it for an active watchdog.
      final emailAlerting = watchdog && (await _run('nvram get wgc${i}_wd_email_enabled')) == '1';
      slots[i] = SlotInfo(
        index: i,
        desc: desc,
        killSwitch: killSwitch,
        enabled: enabled,
        watchdogActive: watchdog,
        watchdogConfigured: watchdogConfigured,
        emailAlerting: emailAlerting,
      );
    }

    // allMatches, not firstMatch: more than one tunnel can be up, and taking only the first
    // silently badged an arbitrary one of them.
    final ifaceOutput = await _run('wg show interfaces');
    final activeSlots = RegExp(r'wgc(\d)').allMatches(ifaceOutput).map((m) => int.parse(m.group(1)!)).toSet();

    // Stock caps concurrent tunnels; follow the router's own setting rather than assuming 2, so a
    // user who changed it gets what they configured. Merlin has no such key, so no limit.
    final maxActiveSlots = stock ? await _readMaxActiveSlots() : null;

    if (slots.values.every((s) => s.isEmpty)) {
      onLog?.call('All WireGuard slots are unconfigured.');
    }
    onLog?.call('Successfully retrieved router config.', isSuccess: true);
    return RouterSlots(slots: slots, activeSlots: activeSlots, isMerlin: isMerlin, maxActiveSlots: maxActiveSlots);
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
    // Stored descriptions carry the app's prefix so they stand out among any other VPNs on the
    // router; the router script strips it again before using the value as a PIA region id.
    final desc = slotDescFor(regionId);
    final wgMap = parseWgConfig(config);
    final epParts = wgMap['Endpoint']?.split(':') ?? [];
    final epIp = epParts.isNotEmpty ? epParts[0] : '';
    final epPort = epParts.length > 1 ? epParts[1] : '1337';

    // Written in kSlotNvramKeys order; stock skips the four keys its firmware does not have.
    final values = <String, String>{
      'addr': '"${wgMap['Address'] ?? ''}"',
      'alive': '25',
      'desc': '"$desc"',
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

    // Names the slot as it is NOW - the restore path puts this configuration back.
    final oldLabel = await _label(slot);

    Map<String, String>? backup;
    String? vpncBackup;
    try {
      // On stock the desc mirror is only present for slots this app created — a profile made in
      // the router web UI shows up in vpnc_clientlist alone, and must still be backed up.
      final existingDesc = await _run('nvram get wgc${slot}_desc');
      final existingVpnc = stock ? await _run('nvram get vpnc_clientlist') : '';
      final occupied = existingDesc.isNotEmpty || (stock && parseVpncClientlist(existingVpnc).any((r) => r.slot == slot));
      if (occupied) {
        onLog?.call('Backing up existing ${await _label(slot)} config...');
        backup = {};
        for (final key in keys) {
          backup['wgc${slot}_$key'] = await _run('nvram get wgc${slot}_$key');
        }
        if (stock) vpncBackup = existingVpnc;
      }

      _labelCache[slot] = slotLabel(slot, desc); // later lines name the slot by its new region
      onLog?.call('Writing NVRAM for ${_labelCache[slot]}...');
      for (final key in keys) {
        await _run('nvram set wgc${slot}_$key=${values[key]}');
      }
      // Stock keeps the region name and active flag here, so the router web UI sees the slot too.
      if (stock) {
        await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, desc: desc, active: false));
      }
      await _run('nvram commit');
      onLog?.call('NVRAM committed.', isSuccess: true);
      onLog?.call('Config written to ${await _label(slot)} (disabled).', isSuccess: true);
      await _logRouter('Created ${await _label(slot)} configuration');
    } catch (e) {
      if (backup != null) {
        onLog?.call('Create failed, restoring $oldLabel config...', isError: true);
        try {
          for (final entry in backup.entries) {
            await client.run('nvram set ${entry.key}="${entry.value}"');
          }
          if (vpncBackup != null) {
            await client.run('nvram set vpnc_clientlist=${shellSingleQuote(vpncBackup)}');
          }
          await client.run('nvram commit');
          onLog?.call('$oldLabel config restored.', isSuccess: true);
        } catch (_) {
          onLog?.call('CRITICAL: could not restore $oldLabel. Check router manually.', isError: true);
        }
      }
      rethrow;
    }
  }

  // ── Enable (with connectivity check + revert-on-failure) ────────────────────────────
  // Brings the interface up, waits for it to appear, then pings BOTH watchdog targets via
  // the slot interface (5s). Any failure reverts enable=0 and throws.
  Future<void> enableSlot(int slot, {required String primaryIp, required String secondaryIp}) async {
    final label = await _label(slot);
    onLog?.call('Enabling $label...');
    await _logRouter('Enabling $label...');
    await _run('nvram set wgc${slot}_enable=1');
    await _setVpncActive(slot, true);
    // Commit before the service call, so the service can never read a half-written slot.
    await _run('nvram commit');
    // stock requires a different start command to Merlin
    if (isStockFirmware) {
      // Must follow _setVpncActive: upsert appends a row for a slot that had none, and the unit
      // is that row's index. There is no start_vpnc on stock (ARCHITECTURE.md 4.2.2).
      await runVpncService(slot, 'restart_vpnc', required: true);
    } else {
      await _run('service "start_wgc $slot"; service restart_vpnrouting0');
    }

    onLog?.call('Verifying $label interface comes up...');
    var up = false;
    for (var retry = 0; retry < verifyMaxAttempts; retry++) {
      await Future.delayed(verifyPollInterval);
      final out = await _run('wg show interfaces');
      onLog?.call('  wg show interfaces: ${out.isEmpty ? '(none)' : out}');
      await _logRouter('wg show interfaces: ${out.isEmpty ? '(none)' : out}');
      if (out.contains('wgc$slot')) {
        up = true;
        onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: $label is active');
        break;
      }
      onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: $label not yet active');
    }
    if (!up) {
      await _revertEnable(slot);
      throw Exception('$label did not come up - the configuration may have expired. Recreate it with CREATE, then ENABLE.');
    }

    // The interface existing proves nothing: a PIA registration that has expired still produces a
    // wgcN device that sends and never receives, which is what leaves the router WebUI stuck on
    // "connecting". A handshake is the peer answering, so that is what ENABLE waits for.
    onLog?.call('Waiting for a WireGuard handshake on $label...');
    var handshake = false;
    for (var retry = 0; retry < verifyMaxAttempts; retry++) {
      final age = await handshakeAge(slot);
      if (age != null) {
        handshake = true;
        onLog?.call('  Handshake ${age}s ago.', isSuccess: true);
        await _logRouter('$label handshake ${age}s ago');
        break;
      }
      onLog?.call('  Check ${retry + 1}/$verifyMaxAttempts: no handshake yet');
      await Future.delayed(verifyPollInterval);
    }
    if (!handshake) {
      await _logRouter('$label came up but the peer never answered (no handshake)');
      await _revertEnable(slot);
      throw Exception('$label came up but the PIA server never answered it (no WireGuard handshake). '
          'The configuration has most likely expired - DELETE the slot and CREATE it again.');
    }

    final primaryOk = await pingViaSlot(primaryIp, slot);
    final secondaryOk = await pingViaSlot(secondaryIp, slot);
    await _logRouter('$label ENABLE connectivity check: '
        'primary $primaryIp ${primaryOk ? 'OK' : 'FAIL'}, secondary $secondaryIp ${secondaryOk ? 'OK' : 'FAIL'}');
    // On Merlin a ping bound to the tunnel is a real end-to-end test, so a failure still blocks
    // the enable. On stock it is neither: it pings from the tunnel's source address but routes
    // over the WAN, so it reported OK for a tunnel the peer had never answered. There the
    // handshake above is the gate and this is only logged.
    if (!isStockFirmware && (!primaryOk || !secondaryOk)) {
      await _revertEnable(slot);
      throw Exception('Connectivity check failed via $label '
          '(primary $primaryIp ${primaryOk ? 'OK' : 'FAIL'}, secondary $secondaryIp ${secondaryOk ? 'OK' : 'FAIL'}). '
          'Slot left disabled.');
    }
    if (isStockFirmware && !primaryOk && !secondaryOk) {
      onLog?.call('Neither ping target answered via $label, but the tunnel has a handshake.', isError: true);
    }
    await _logRouter('Enabled $label');
    onLog?.call('$label enabled and verified.', isSuccess: true);
  }

  Future<void> _revertEnable(int slot) async {
    onLog?.call('Reverting ${await _label(slot)} to disabled...', isError: true);
    await _run('nvram set wgc${slot}_enable=0');
    await _setVpncActive(slot, false);
    await _run('nvram commit');
    // stock requires a different stop command to Merlin
    if (isStockFirmware) {
      await runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    // Same reason as disableSlot: the caller refreshes as soon as this returns.
    await _awaitInterfaceDown(slot);
  }

  // ── Disable ─────────────────────────────────────────────────────────────────────────
  Future<void> disableSlot(int slot) async {
    onLog?.call('Disabling ${await _label(slot)}...');
    await _run('nvram set wgc${slot}_enable=0');
    await _setVpncActive(slot, false);
    await _run('nvram commit');
    // stock requires a different stop command to Merlin. `restart_vpnc` clears the nvram flags but
    // leaves the interface up (ARCHITECTURE.md 4.2.3 specifies stop_vpnc) — that mismatch is what
    // left a tunnel running behind a WebUI that reported it disconnected.
    if (isStockFirmware) {
      await runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    // Return only once the tunnel is really down. The stop is queued through notify_rc and returns
    // at once, so a caller that refreshes straight away reads `wg show interfaces` while the
    // interface is still listed and leaves the ACTIVE badge on a slot it just disabled.
    await _awaitInterfaceDown(slot);
    await _logRouter('Disabled ${await _label(slot)}');
    onLog?.call('${await _label(slot)} disabled.', isSuccess: true);
  }

  // ── Delete (clear the slot's WireGuard config) ──────────────────────────────────────
  Future<void> deleteSlot(int slot) async {
    // Read the label before the description is unset, so the later lines can still name the slot.
    final label = await _label(slot);
    onLog?.call('Deleting $label configuration...');
    await _run('nvram set wgc${slot}_enable=0');
    // stock requires a different stop command to Merlin. Must precede removeVpncRecord below:
    // the unit is the row's index, so dropping the row first would lose it.
    if (isStockFirmware) {
      await runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    // `service stop_vpnc` / `stop_wgc` return as soon as notify_rc is queued, and the firmware
    // writes slot state as it tears the tunnel down. Unsetting before that lands leaves keys
    // re-created behind us - wgcN_enable in particular - so wait for the interface to go first.
    await _awaitInterfaceDown(slot);

    for (final key in slotKeysFor(routerFirmware)) {
      await _run('nvram unset wgc${slot}_$key');
    }
    // also clear ping target keys
    await _run('nvram unset wgc${slot}_wd_primary_ip');
    await _run('nvram unset wgc${slot}_wd_secondary_ip');
    if (isStockFirmware) {
      // Resolve the runtime-state index from the record while it is still there - it is field 7,
      // not the slot number, so wgc1 leaves vpnc9_* behind.
      final stateIdx = vpncStateIndexForSlot(parseVpncClientlist(await _run('nvram get vpnc_clientlist')), slot);
      for (final key in kVpncRuntimeKeys) {
        await _run('nvram unset vpnc${stateIdx}_$key');
      }
      await _editVpncClientlist((recs) => removeVpncRecord(recs, slot));
    }
    await _run('nvram commit');
    await _logRouter('Deleted $label configuration');
    onLog?.call('$label configuration cleared.', isSuccess: true);
  }

  // Bounded wait for [slot]'s interface to leave `wg show interfaces`. Checks before sleeping, so
  // an already-stopped slot costs one command and tests stay instant. Reuses the same injectable
  // cadence as the enable-side verification.
  Future<void> _awaitInterfaceDown(int slot) async {
    for (var attempt = 0; attempt < verifyMaxAttempts; attempt++) {
      if (!(await _run('wg show interfaces')).contains('wgc$slot')) return;
      await Future.delayed(verifyPollInterval);
    }
    // Clearing the configuration is still the right thing to do; say so rather than fail the delete.
    onLog?.call('${await _label(slot)} is still up after the stop; clearing its configuration anyway.', isError: true);
  }

  // ── Edit: write the user-editable slot parameters back ──────────────────────────────
  // [params] keys are bare (e.g. 'addr', 'priv'). Values are shell-escaped.
  Future<void> writeSlotParams(int slot, Map<String, String> params) async {
    onLog?.call('Saving ${await _label(slot)} parameters...');
    final live = slotKeysFor(routerFirmware);
    for (final e in params.entries) {
      if (!live.contains(e.key)) continue; // stock has no enforce / fw / ep_addr_r / rip
      await _run('nvram set wgc${slot}_${e.key}=${shellSingleQuote(e.value)}');
    }
    // On stock the region must stay in step with its vpnc_clientlist record, which is what the
    // router web UI and fetchSlots both read.
    if (params.containsKey('desc')) {
      _labelCache.remove(slot); // the slot may have just been renamed
      if (isStockFirmware) {
        await _editVpncClientlist((recs) => upsertVpncRecord(recs, slot: slot, desc: params['desc']));
      }
    }
    await _run('nvram commit');
    onLog?.call('${await _label(slot)} parameters saved.', isSuccess: true);
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

  /// Seconds since the slot's most recent WireGuard handshake, or null if there has never been
  /// one (`wg` reports 0) or the interface is absent.
  ///
  /// This is the only liveness signal that means the same thing on both firmwares. `wg show
  /// interfaces` only says the device exists - an expired PIA registration still produces one that
  /// sends and never receives - and a ping bound to the tunnel is unreliable on stock, where the
  /// router's own traffic is not routed into wgcN.
  Future<int?> handshakeAge(int slot) async {
    try {
      final out = await _run("wg show wgc$slot latest-handshakes 2>/dev/null | "
          "awk '{if (\$2 > m) m = \$2} END {print m + 0}'");
      final stamp = int.tryParse(out.trim()) ?? 0;
      if (stamp <= 0) return null;
      final now = int.tryParse((await _run('date +%s')).trim());
      if (now == null) return null;
      final age = now - stamp;
      return age < 0 ? 0 : age;
    } catch (_) {
      return null;
    }
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
