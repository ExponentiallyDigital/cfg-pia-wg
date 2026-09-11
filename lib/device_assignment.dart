// device_assignment.dart - which LAN device goes through which tunnel, as pure data.
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
// No SSH in this file. Everything here is parse, decide, serialise - so the rules that matter can
// be tested without a router, and the router layer is left with nothing but I/O.
//
// Two facts from ARCHITECTURE.md "vpnc_dev_policy_list - the assignment" shape the whole design:
//
//   1. A policy record is keyed by IP ADDRESS, not MAC. So a device whose address we do not know
//      cannot be assigned at all, and an assignment silently stops applying if the address moves.
//   2. Index 3 names a profile by its `vpnc_clientlist` INDEX 6 - which can point at OpenVPN,
//      PPTP, L2TP or a third-party provider just as easily as at a WireGuard slot. The web
//      interface allows 16 profiles of any kind. This app manages WireGuard only, so records
//      pointing anywhere else are carried through untouched rather than reinterpreted.

import 'dart:convert';

/// One record of `vpnc_dev_policy_list`: `enabled>IP>?>vpnc_idx>`.
///
/// Field access is total - short records are padded - but longer ones keep their extra fields, the
/// same discipline [VpncRecord] uses. A firmware that appends a field must not have it silently
/// dropped by us on the next write.
class DevicePolicy {
  static const int fieldCount = 5;
  static const int _enabledIdx = 0, _ipIdx = 1, _vpncIdx = 3;

  final List<String> fields;

  DevicePolicy(List<String> fields) : fields = List.unmodifiable(_sized(fields));

  static List<String> _sized(List<String> f) =>
      f.length >= fieldCount ? List.of(f) : [...f, ...List.filled(fieldCount - f.length, '')];

  /// `1` assigned, `0` not. Both forms occur in the wild - a pristine router seeds `0>IP>>0>`
  /// placeholder records for reserved devices, so presence in the list is NOT assignment.
  bool get enabled => fields[_enabledIdx] == '1';

  String get ip => fields[_ipIdx];

  /// Index 6 of the target profile's `vpnc_clientlist` record. `null` when unparseable, which is
  /// treated as "not ours" rather than guessed at.
  int? get vpncIndex => int.tryParse(fields[_vpncIdx]);

  /// True when this record PINS the device somewhere, whether to a tunnel or to the plain internet.
  ///
  /// The enabled flag is the whole test, and index 0 does not disqualify a record. Two records can
  /// both carry index 0 and mean opposite things (ARCHITECTURE.md "vpnc_dev_policy_list - the assignment", confirmed 2026-09-08):
  /// `1>IP>>0>` is PINNED to Internet Connection and ignores the default, while `0>IP>>0>` follows
  /// whatever the default is. Until 421 this returned false for both, so a device deliberately
  /// pinned to the internet was displayed - and rewritten - as though it followed the default. That
  /// is the difference between leaking and failing closed when a tunnel drops, so it is not a
  /// display detail.
  bool get isAssigned => enabled;

  String serialise() => fields.join('>');

  DevicePolicy copyWith({bool? enabled, int? vpncIndex}) {
    final f = List.of(fields);
    if (enabled != null) f[_enabledIdx] = enabled ? '1' : '0';
    if (vpncIndex != null) f[_vpncIdx] = '$vpncIndex';
    return DevicePolicy(f);
  }
}

List<DevicePolicy> parseDevicePolicyList(String raw) => [
      for (final chunk in raw.trim().split('<'))
        if (chunk.isNotEmpty) DevicePolicy(chunk.split('>')),
    ];

String serialiseDevicePolicyList(List<DevicePolicy> records) => records.map((r) => r.serialise()).join('<');

/// Points [ip] at [vpncIndex], or back at the default when [vpncIndex] is null.
///
/// Unassigning writes `0>IP>>0>` rather than deleting the record, which is what the web interface
/// leaves behind and keeps the list shaped the way the firmware expects. Every record for another
/// address is passed through byte for byte - including ones naming a VPN this app does not manage.
List<DevicePolicy> setDevicePolicy(List<DevicePolicy> records, {required String ip, int? vpncIndex}) {
  final out = List.of(records);
  final idx = out.indexWhere((r) => r.ip == ip);
  if (idx >= 0) {
    out[idx] = out[idx].copyWith(enabled: vpncIndex != null, vpncIndex: vpncIndex ?? 0);
  } else if (vpncIndex != null) {
    out.add(DevicePolicy(['1', ip, '', '$vpncIndex', '']));
  }
  return out;
}

/// The addresses pinned to [vpncIndex], in list order.
///
/// Used when a profile is about to stop existing. A policy record keeps naming the index of a
/// deleted profile: the web interface cannot show it, the assignment screen can only call it
/// "profile N", and the device's traffic goes wherever that index now leads - including to whatever
/// region is next created in that slot. Measured on hardware 2026-09-11.
List<String> devicesPinnedTo(List<DevicePolicy> records, int vpncIndex) => [
      for (final r in records)
        if (r.isAssigned && r.vpncIndex == vpncIndex) r.ip,
    ];

/// Moves every device pinned to [vpncIndex] onto the plain internet.
///
/// **Internet, not the default connection**, which is what the web interface does when a profile is
/// deleted. Sending them to the default would put a device that was explicitly pinned onto whatever
/// tunnel the default happens to name, without anyone choosing that; the internet is the one
/// destination that is never a surprise. The record stays ENABLED with index 0 - `1>IP>>0>` - which
/// is a pin to the WAN, not `0>IP>>0>`, which would mean "follow the default".
///
/// Records for other addresses pass through byte for byte, including ones naming a VPN this app
/// does not manage.
List<DevicePolicy> releaseDevicesFrom(List<DevicePolicy> records, int vpncIndex) => [
      for (final r in records)
        if (r.isAssigned && r.vpncIndex == vpncIndex) r.copyWith(enabled: true, vpncIndex: 0) else r,
    ];

/// The `vpnc_clientlist` index 6 [ip] is pinned to: `0` for the plain internet, a profile index for
/// a tunnel, or null when the device has no pin and follows the default connection.
int? assignedIndexFor(List<DevicePolicy> records, String ip) {
  for (final r in records) {
    if (r.ip == ip) return r.isAssigned ? r.vpncIndex : null;
  }
  return null;
}

/// Lists the policy routing rules. Each assigned device gets one, `from <ip> lookup <index 6>`.
const String kIpRuleCommand = 'ip rule show';

/// The routing tables [ip] is still being sent to that it should not be, given that it now belongs
/// to [keepIndex] (or to the default connection when that is null).
///
/// Stock DOES NOT REMOVE a device's old rule when its assignment changes. Measured 2026-09-10: a
/// device moved from wgc1 to wgc5 ended up with both rules, at the same priority 100 -
///
/// ```text
/// 100:    from 192.168.1.51 lookup 9     <- wgc1, stale
/// 100:    from 192.168.1.51 lookup 5     <- wgc5, correct
/// ```
///
/// At equal priority the kernel takes them in insertion order, so the older rule matches first and
/// the new one is never reached. NVRAM, the web interface and this app all agreed the device was on
/// wgc5 while its traffic went out wgc1 - the assignment was written correctly and simply had no
/// effect. Neither `restart_vpnc_dev_policy`, `restart_vpnrouting0` nor a vpnc stop/restart clears
/// it; only `restart_net_and_phy` does, and that bounces every switch port and re-leases the WAN.
///
/// A duplicate of the CORRECT rule is stale too: one is kept and any further copies are returned.
///
/// **The table is not always a number.** Pinning a device to the plain internet - index 0 - makes
/// the firmware write `lookup main` for it, and matching only digits made that rule invisible here.
/// Measured 2026-09-11: a device moved to Internet and then to wgc5 kept both, with `main` first -
///
/// ```text
/// 100:    from 192.168.1.51 lookup main  <- Internet, stale, and matched first
/// 100:    from 192.168.1.51 lookup 5     <- wgc5, correct, never reached
/// ```
///
/// so once a device had been on Internet it stayed there until the router was rebooted. The `from`
/// address is what makes this safe: the global `32766: from all lookup main` and the priority-10000
/// `from all iif br0` rules name `all`, never a device, so they can never match.
List<String> staleRuleTables(String ipRuleOutput, {required String ip, int? keepIndex}) {
  // What this device SHOULD be routed by: its profile's table, `main` when it is pinned to the
  // plain internet, and nothing at all when it follows the default connection.
  final keep = keepIndex == null
      ? null
      : keepIndex == 0
          ? 'main'
          : '$keepIndex';
  final stale = <String>[];
  var kept = false;
  for (final line in ipRuleOutput.split('\n')) {
    final m = RegExp(r'from (\S+) lookup (\S+)').firstMatch(line);
    if (m == null || m.group(1) != ip) continue;
    final table = m.group(2)!;
    if (table == keep && !kept) {
      kept = true;
      continue;
    }
    stale.add(table);
  }
  return stale;
}

// ─── Devices ────────────────────────────────────────────────────────────────────────

/// A LAN device as the assignment screen sees it, joined from up to four router sources.
///
/// The join is by uppercase MAC throughout: `nmp_cl_json.js` for the device set and its online
/// state, `custom_clientlist` for the user's own name, `nmp_cache.js` or `dhcp_staticlist` for the
/// address, and `dhcp_staticlist` membership for whether it holds a reservation.
class LanDevice {
  const LanDevice({
    required this.mac,
    this.ip,
    this.customName,
    this.detectedName,
    this.online = true,
    this.reserved = false,
  });

  final String mac; // uppercase
  final String? ip; // null when no source knows it - see [assignable]
  final String? customName; // custom_clientlist, the name the user chose
  final String? detectedName; // nmp_cl_json.js, a vendor string or DHCP hostname
  /// Read from `nmp_cl_json.js`, NEVER from `nmp_cache.js`. Measured 2026-09-08 on a device
  /// powered off for ten minutes: the first had updated to `online: 0` while the second still said
  /// `isOnline: "1"`. Taking it from the file that supplies every other field would show every
  /// device as permanently online.
  final bool online;

  final bool reserved; // present in dhcp_staticlist

  /// The user's own name wins, then whatever the router auto-detected, then the MAC.
  ///
  /// The auto-detected name is not unique - two devices on the test router shared an identical
  /// generated hostname - so the screen always shows the address alongside this.
  String get displayName {
    final c = customName?.trim() ?? '';
    if (c.isNotEmpty) return c;
    final d = detectedName?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return mac;
  }

  /// True when the display name is only the MAC, which is what the screen uses to sort these last.
  bool get isNameless => displayName == mac;

  /// A policy record is keyed by IP, so no address means nothing can be written for this device.
  /// It is still listed - hiding it would be a silent hole in the list - but it cannot be assigned.
  bool get assignable => (ip ?? '').isNotEmpty;

  /// The locally-administered bit: second hex digit of the MAC is 2, 6, A or E.
  ///
  /// Phones and tablets rotate their MAC per network, and an assignment keyed on the old address
  /// then stops applying with no error and nothing in any log. This detects the ADDRESS IN USE,
  /// never the device's setting - a known randomiser connected on its factory MAC reads as stable -
  /// so the wording must be "this address looks randomised", not "this device randomises".
  bool get hasRandomisedMac {
    if (mac.length < 2) return false;
    return const {'2', '6', 'A', 'E'}.contains(mac[1].toUpperCase());
  }
}

/// Sorts by display name, case-insensitively, with MAC-only entries last.
///
/// Nameless devices go last because a column of hex among real names is noise, and they are the
/// entries a user is least likely to be looking for.
List<LanDevice> sortDevicesForDisplay(List<LanDevice> devices) {
  final out = List.of(devices);
  out.sort((a, b) {
    // Offline devices sink below online ones. The list is long enough that scrolling past greyed
    // rows to reach a device that is actually there was the common case.
    if (a.online != b.online) return a.online ? -1 : 1;
    if (a.isNameless != b.isNameless) return a.isNameless ? 1 : -1;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return out;
}

// ─── Reading the router's four device sources ───────────────────────────────────────
//
// The two `.js` files are plain JSON despite the extension, so they are decoded here rather than
// with `jq` on the router. That keeps the whole join unit-testable from fixture strings, avoids a
// layer of shell quoting, and means the device list does not depend on a helper binary being
// installed. Both files are small - 2 KB and 8 KB for eleven devices.

/// `AA:BB:CC:DD:EE:FF`, uppercase. Used to tell device keys apart from the non-device ones.
final RegExp _macKey = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

/// Decodes a MAC-keyed JSON object, keeping only entries that are actually devices.
///
/// `/tmp/nmp_cache.js` mixes two non-device keys in at the top level - `maclist`, an array of every
/// tracked MAC, and `ClientAPILevel`, a string. Assuming every value is a device object throws, so
/// both the key shape and the value type are checked. A file that fails to decode at all yields an
/// empty map rather than an exception: a missing `/tmp` file must degrade the screen, not break it.
Map<String, Map<String, dynamic>> parseDeviceJson(String raw) {
  if (raw.trim().isEmpty) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return {};
  }
  if (decoded is! Map) return {};
  final out = <String, Map<String, dynamic>>{};
  decoded.forEach((k, v) {
    final key = '$k'.toUpperCase();
    if (_macKey.hasMatch(key) && v is Map) out[key] = Map<String, dynamic>.from(v);
  });
  return out;
}

/// MAC to reserved IP, from `dhcp_staticlist`: `<MAC>IP>>name`.
///
/// Membership is also the answer to "does this device hold a reservation", which decides whether
/// assigning it is cheap or bounces the whole network.
Map<String, String> parseDhcpStaticlist(String raw) {
  final out = <String, String>{};
  for (final chunk in raw.trim().split('<')) {
    if (chunk.isEmpty) continue;
    final f = chunk.split('>');
    if (f.length >= 2 && f[0].isNotEmpty) out[f[0].toUpperCase()] = f[1];
  }
  return out;
}

/// MAC to the user's chosen name, from `custom_clientlist`: `Name>MAC>Group>Type>...`.
///
/// Only needed when `/tmp/nmp_cache.js` is absent - that file already carries the same value as
/// `nickName`. Records vary from six to nine fields, so nothing beyond index 1 may be assumed.
Map<String, String> parseCustomClientlistNames(String raw) {
  final out = <String, String>{};
  for (final chunk in raw.trim().split('<')) {
    if (chunk.isEmpty) continue;
    final f = chunk.split('>');
    if (f.length >= 2 && f[1].isNotEmpty) out[f[1].toUpperCase()] = f[0];
  }
  return out;
}

/// Every MAC in `cfg_device_list`: the router itself and each AiMesh node, as `name>IP>MAC>flag`.
///
/// Membership is the whole exclusion rule - the flag distinguishes router from node and needs no
/// interpreting. Without this a mesh node is indistinguishable from a laptop: it appears in
/// `nmp_cache.js` with `isGateway: "0"` exactly like an ordinary client.
Set<String> parseCfgDeviceListMacs(String raw) {
  final out = <String>{};
  for (final chunk in raw.trim().split('<')) {
    if (chunk.isEmpty) continue;
    final f = chunk.split('>');
    if (f.length >= 3 && _macKey.hasMatch(f[2].toUpperCase())) out.add(f[2].toUpperCase());
  }
  return out;
}

/// Joins the four sources into the list the screen shows, sorted and with the router and any mesh
/// node removed.
///
/// Which source wins for what, all of it measured rather than assumed:
///
///   - **device set** - `nmp_cl_json.js`, because it is in `/jffs` and lists devices that are off.
///   - **online** - `nmp_cl_json.js` ONLY. `nmp_cache.js`'s `isOnline` was still `"1"` ten minutes
///     after a device was powered off.
///   - **address** - `nmp_cache.js` first, then `dhcp_staticlist`. An offline device keeps its `ip`
///     in the cache, so the reservation is a second source rather than the main one.
///   - **the user's name** - `nickName` from `nmp_cache.js`, else `custom_clientlist`.
///   - **the detected name** - `name` from `nmp_cl_json.js`, else `nmp_cache.js`.
List<LanDevice> buildDeviceList({
  required String nmpClJson,
  required String nmpCache,
  required String customClientlist,
  required String dhcpStaticlist,
  required String cfgDeviceList,
}) {
  final inventory = parseDeviceJson(nmpClJson);
  final cache = parseDeviceJson(nmpCache);
  final reservations = parseDhcpStaticlist(dhcpStaticlist);
  final customNames = parseCustomClientlistNames(customClientlist);
  final excluded = parseCfgDeviceListMacs(cfgDeviceList);

  // Union rather than the inventory alone: the two files agreed on the test router, but a device
  // known to only one of them should still be listed rather than silently dropped.
  final macs = <String>{...inventory.keys, ...cache.keys}..removeAll(excluded);

  String? str(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  final devices = <LanDevice>[];
  for (final mac in macs) {
    final inv = inventory[mac];
    final cac = cache[mac];
    devices.add(LanDevice(
      mac: mac,
      ip: str(cac, 'ip') ?? reservations[mac],
      customName: str(cac, 'nickName') ?? customNames[mac],
      detectedName: str(inv, 'name') ?? str(cac, 'name'),
      // `online` is an integer here and absent from a device the inventory has never seen; treat
      // unknown as online, since claiming a device is off is worse than not saying.
      online: inv == null || '${inv['online']}' != '0',
      reserved: reservations.containsKey(mac),
    ));
  }
  return sortDevicesForDisplay(devices);
}
