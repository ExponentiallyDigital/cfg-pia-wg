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

/// The one priority-100 rule each device in [records] should have, keyed by address.
///
/// A pinned device gets its profile's index 6, a device pinned to the plain internet gets `0`
/// (which reads as `lookup main`), and a device that follows the default connection gets `null` -
/// it should carry no rule at all. Feed the result to a sweep and the rules match the list.
///
/// Every device in the list is included, not only the ones an apply just changed. Measured
/// 2026-09-22: `restart_vpnc_dev_policy` re-installs a rule for EVERY record each time it runs, so
/// sweeping only the changed ones left one extra copy per untouched device per apply - four copies
/// of one device's rule after a morning's work, cleared only by a reboot. Duplicates that agree are
/// harmless; the moment one does not, the first match wins and the device leaves by the wrong
/// tunnel, which is the fault the sweep exists to prevent (ID-183).
Map<String, int?> expectedRuleTargets(List<DevicePolicy> records) => {
      for (final r in records)
        if (r.ip.isNotEmpty) r.ip: r.isAssigned ? (r.vpncIndex ?? 0) : null,
    };

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

/// The priority the firmware gives every per-device rule. The only one the stale-rule sweep may
/// touch, and so the one every `ip rule del` it issues has to name.
const int kFirmwareRulePriority = 100;

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
///
/// **Priority 100 only.** The fail-closed guard (fail_closed_guard.dart) keeps its own rules for
/// the same device at 90 and 91, and the one at 90 also reads `from <ip> lookup <table>`. Matching
/// at any priority would take it for a duplicate and delete it, leaving the device unguarded.
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
    if (!line.trimLeft().startsWith('$kFirmwareRulePriority:')) continue;
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

// ─── Is the tunnel a change moves devices onto actually carrying traffic? ──────────────

/// How recently a tunnel's server must have answered for APPLY to say nothing about it.
///
/// WireGuard re-handshakes every two minutes on a tunnel that is passing traffic, so three minutes
/// allows for one late renewal. Watchdog logs showed ages up to 111 seconds on healthy tunnels.
const Duration kStaleHandshake = Duration(minutes: 3);

/// A tunnel as APPLY sees it: whether its interface is up, and how long since its server answered.
class TunnelHealth {
  const TunnelHealth({required this.up, this.handshakeAgeSeconds});

  final bool up;

  /// Seconds since the latest handshake, or null when there has never been one.
  final int? handshakeAgeSeconds;

  /// Up, but its server has not answered within [kStaleHandshake], or ever.
  ///
  /// Not proof of a working path either way: measured 2026-09-13, a `us_alabama` server handshook
  /// normally while carrying no DNS. This catches "not answering", not every failure.
  bool get stale => up && (handshakeAgeSeconds == null || handshakeAgeSeconds! > kStaleHandshake.inSeconds);
}

/// The newest handshake in `wg show wgcN latest-handshakes` output, one `<peer key> <epoch>` line per
/// peer, or 0 when there has never been one.
int latestHandshakeEpoch(String raw) {
  var newest = 0;
  for (final line in raw.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final epoch = int.tryParse(parts.last) ?? 0;
    if (epoch > newest) newest = epoch;
  }
  return newest;
}

/// Joins the up-interface list, the router's clock and each slot's handshakes into [TunnelHealth].
///
/// Ages are taken against the ROUTER's clock, never the phone's: the two can disagree by minutes,
/// which is the whole size of the threshold. A clock that cannot be read raises no alarm.
Map<int, TunnelHealth> parseTunnelHealth({
  required String upInterfaces,
  required String routerNow,
  required Map<int, String> handshakes,
}) {
  final now = int.tryParse(routerNow.trim());
  final out = <int, TunnelHealth>{};
  handshakes.forEach((slot, raw) {
    final epoch = latestHandshakeEpoch(raw);
    final int? age;
    if (epoch == 0) {
      age = null;
    } else if (now == null) {
      age = 0;
    } else {
      age = now - epoch < 0 ? 0 : now - epoch;
    }
    out[slot] = TunnelHealth(up: upInterfaces.contains('wgc$slot'), handshakeAgeSeconds: age);
  });
  return out;
}

/// "Box", "Box and Laptop", "Box, Laptop and Phone".
String joinNames(List<String> names) {
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// "1 minute", "16 minutes", "2 hours": how long a tunnel's server has been silent.
String describeSilence(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 120) return '$minutes minute${minutes == 1 ? '' : 's'}';
  return '${minutes ~/ 60} hours';
}

/// What APPLY's confirmation says about [tunnel] before moving [who] onto it, or null when it looks
/// healthy.
///
/// [blocked] is for devices PINNED to the tunnel: the fail-closed guard keeps them off the internet
/// until it runs again (ID-213). Before the guard they fell through to the default connection.
/// [fallback] names where anyone else goes; leave both unset for the default connection itself.
String? tunnelWarning(TunnelHealth health,
    {required String tunnel, required String who, String? fallback, bool blocked = false}) {
  if (!health.up) {
    if (blocked) return '$tunnel is not running. Until it is enabled, $who will have no internet.';
    return fallback == null
        ? '$tunnel is not running. Until it is, $who are not on that VPN.'
        : '$tunnel is not running. Until it is enabled, $who will use $fallback.';
  }
  if (!health.stale) return null;
  final age = health.handshakeAgeSeconds;
  final silence = age == null ? 'has not answered since it started' : 'has not answered for ${describeSilence(age)}';
  final subject = who.isEmpty ? who : who[0].toUpperCase() + who.substring(1);
  return '$tunnel is up, but its server $silence. $subject may have no internet.';
}

/// [actualExitIndex]'s answer for a device that has no way out at all.
const int kExitBlocked = -1;

/// Where a device's traffic actually leaves while its tunnel is not running, as a profile index 6 (0
/// is the plain internet), [kExitBlocked] when it cannot leave, or null when it leaves where its
/// assignment says or that cannot be told.
///
/// A device PINNED to a stopped tunnel is blocked: the fail-closed guard drops its traffic until the
/// tunnel runs again (ID-213). Without the guard it fell through to the default connection -
/// measured 2026-09-13 and again 2026-09-24 - which is the leak the guard exists to close. A device
/// that FOLLOWS a default that is not running leaves by the plain internet; the guard covers pins
/// only. [isUp] answers for a tunnel index, or null when that is not known - a VPN this app does not
/// manage, or a slot read that failed - and an unknown answers nothing.
int? actualExitIndex({required int? pinned, required int? defaultIndex, required bool? Function(int index) isUp}) {
  final def = defaultIndex ?? 0;
  final target = pinned ?? def;
  if (target == 0) return null;
  final up = isUp(target);
  if (up == null || up) return null;
  return pinned == null ? 0 : kExitBlocked;
}

// ─── Devices ────────────────────────────────────────────────────────────────────────

/// A LAN device as the assignment screen sees it, joined from up to four router sources.
///
/// The join is by uppercase MAC throughout: `nmp_cl_json.js` for the device set, `nmp_cache.js` for
/// its online state, `custom_clientlist` for the user's own name, `nmp_cache.js` or `dhcp_staticlist` for the
/// address, and `dhcp_staticlist` membership for whether it holds a reservation.
class LanDevice {
  const LanDevice({
    required this.mac,
    this.ip,
    this.customName,
    this.detectedName,
    this.online = true,
    this.reserved = false,
    this.type,
  });

  final String mac; // uppercase
  final String? ip; // null when no source knows it - see [assignable]
  final String? customName; // custom_clientlist, the name the user chose
  final String? detectedName; // nmp_cl_json.js, a vendor string or DHCP hostname
  /// `isOnline` from `nmp_cache.js`, the web interface's own source, else `online` from
  /// `nmp_cl_json.js` (ID-165). Measured 2026-09-27 through a full off, on and off again: the cache
  /// changed within a second of the web interface every time, and the /jffs file, rewritten only
  /// every few minutes, was 8.5 minutes late going offline and 3 late coming back. A 2026-09-08
  /// snapshot had pointed the other way, on a games console that may keep its network in standby.
  final bool online;

  final bool reserved; // present in dhcp_staticlist

  /// The router's device type, the number behind its icon (`type` in the two device files). Carried
  /// into a `custom_clientlist` record the app creates, or the icon turns generic (ID-025).
  final String? type;

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

/// Separates the outputs of several reads sent as one command.
const String kSourceSeparator = '@@CFGPIAWG@@';

/// The five reads [buildDeviceList] joins, sent as one command. Anything that names a device - the
/// screen, a log line, a warning - reads through this, so a device has the same name everywhere. The
/// DELETE log named devices from `custom_clientlist` alone, and showed a bare address for any device
/// the user had not renamed there (ID-154).
const String kDeviceSourcesCommand = 'echo "$kSourceSeparator"; nvram get dhcp_staticlist; '
    'echo "$kSourceSeparator"; nvram get custom_clientlist; '
    'echo "$kSourceSeparator"; nvram get cfg_device_list; '
    'echo "$kSourceSeparator"; cat /jffs/nmp_cl_json.js 2>/dev/null; '
    'echo "$kSourceSeparator"; cat /tmp/nmp_cache.js 2>/dev/null; '
    'echo "$kSourceSeparator"';

/// The device list from the output of [kDeviceSourcesCommand].
List<LanDevice> parseDeviceSources(String output) {
  final parts = output.split(kSourceSeparator);
  String at(int i) => i + 1 < parts.length ? parts[i + 1].trim() : '';
  return buildDeviceList(
    dhcpStaticlist: at(0),
    customClientlist: at(1),
    cfgDeviceList: at(2),
    nmpClJson: at(3),
    nmpCache: at(4),
  );
}

/// Address to the name the screen shows, for every device with a known address. A device whose
/// only name is its MAC is left out, so the caller falls back to the address, which is what a
/// person can match against their router.
Map<String, String> deviceNamesByIp(List<LanDevice> devices) => {
      for (final d in devices)
        if (d.assignable && !d.isNameless) d.ip!: d.displayName,
    };

/// Joins the four sources into the list the screen shows, sorted and with the router and any mesh
/// node removed.
///
/// Which source wins for what, all of it measured rather than assumed:
///
///   - **device set** - `nmp_cl_json.js`, because it is in `/jffs` and lists devices that are off.
///   - **online** - `nmp_cache.js`'s `isOnline`, which the web interface follows to the second; else
///     `nmp_cl_json.js`, whose /jffs copy is written only every few minutes (ID-165).
///   - **address** - `nmp_cache.js` first, then `dhcp_staticlist`. An offline device keeps its `ip`
///     in the cache, so the reservation is a second source rather than the main one.
///   - **the user's name** - `custom_clientlist`, else `nickName` from `nmp_cache.js`.
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
      // `custom_clientlist` first: it is what a rename writes, and the cache's `nickName` catches up
      // with it only when the router next rewrites the cache, so a list re-read straight after a
      // rename showed the old name (ID-261).
      customName: customNames[mac] ?? str(cac, 'nickName'),
      detectedName: str(inv, 'name') ?? str(cac, 'name'),
      // The cache first: it is what the web interface shows, and the /jffs inventory lags it by
      // minutes (ID-165). Then the inventory, where `online` is an integer. Unknown to both reads as
      // online, since claiming a device is off is worse than not saying.
      online: str(cac, 'isOnline') != null ? str(cac, 'isOnline') != '0' : inv == null || '${inv['online']}' != '0',
      reserved: reservations.containsKey(mac),
      type: str(cac, 'type') ?? str(inv, 'type'),
    ));
  }
  return sortDevicesForDisplay(devices);
}

// ─── A device's own name (ID-261) ─────────────────────────────────────────────────────
//
// Measured 2026-09-28 against the web interface: renaming a device writes ONE key,
// `custom_clientlist`, and calls no service at all - the new name shows straight away. A record is
// `Name>MAC>group>type>...`, and the name is stored exactly as typed: a space, `'` or `&` needs no
// escaping. The web interface refuses `<` and `>`, the list's own delimiters, and keeps at most 32
// characters.

/// The longest name the router's web interface keeps.
const int kMaxDeviceNameLength = 32;

/// Why [name] cannot be a device name, or null when it can. An empty name is allowed: it clears the
/// user's name, and the device shows its detected one again.
String? checkDeviceName(String name) {
  final n = name.trim();
  if (n.contains('<') || n.contains('>')) return 'A name cannot contain < or >.';
  if (n.length > kMaxDeviceNameLength) return 'A name can be at most $kMaxDeviceNameLength characters.';
  return null;
}

/// [raw] `custom_clientlist` with [mac]'s name set to [name], or its record removed when [name] is
/// empty, so the router shows the detected name again.
///
/// An existing record keeps every other field, including its type, which is the device's icon in the
/// web interface and the ASUS app. A device with no record gets one shaped like the web interface's,
/// `Name>MAC>0>type>>>>`, carrying [type] from the device files: a naive `0` would turn its icon
/// generic (ID-025). Every other record passes through byte for byte.
String setCustomName(String raw, {required String mac, required String name, String? type}) {
  final records = [for (final c in raw.trim().split('<')) if (c.isNotEmpty) c.split('>')];
  final n = name.trim();
  final i = records.indexWhere((f) => f.length >= 2 && f[1].toUpperCase() == mac.toUpperCase());
  if (i >= 0) {
    if (n.isEmpty) {
      records.removeAt(i);
    } else {
      records[i] = [n, ...records[i].skip(1)];
    }
  } else if (n.isNotEmpty) {
    records.add([n, mac.toUpperCase(), '0', (type ?? '').isEmpty ? '0' : type!, '', '', '', '']);
  }
  return records.isEmpty ? '' : '<${records.map((f) => f.join('>')).join('<')}';
}

// ─── Disabling a device's internet: the router's own Parental Controls (ID-261) ───────
//
// Andrew's decision: the app uses the router's own "Block Internet access" rather than a rule of its
// own, so a disabled device shows in the web interface and can be enabled there too. It is Parental
// Controls, Time Scheduling. Measured 2026-09-28, four runs:
//
//   - Five parallel lists, one entry per device in the order devices were added, separated by `>`:
//     `MULTIFILTER_MAC`, `MULTIFILTER_DEVICENAME`, `MULTIFILTER_ENABLE` (0 disable, 1 time, 2 block)
//     and `MULTIFILTER_MACFILTER_DAYTIME_V2`, one schedule per device with `<` inside it.
//   - `MULTIFILTER_ALL` is the Enable Time Scheduling switch for ALL of them. With it off nothing is
//     blocked, whatever the entries say.
//   - `restart_firewall` turns a block into three MAC rules (FORWARD to PControls, DROP in PControls,
//     DROP in WGNPControls for the guest bridge). The device loses the internet and every tunnel, and
//     keeps its LAN. An entry at 0 gets no rule. A block survives a reboot.
//   - `MULTIFILTER_BLOCK_ALL` is "Enable block all devices" and blocks the whole network. Never touched.

/// The value the web interface writes for a device set to block.
const String kParentalBlock = '2';

/// The schedule the web interface gives a new entry. Kept on a block, where it does nothing.
const String kParentalDefaultSchedule = 'W03E21000700<W04122000800';

/// One device in Time Scheduling.
class ParentalEntry {
  const ParentalEntry({required this.mac, required this.name, required this.mode, required this.schedule});

  final String mac, name, mode, schedule;

  ParentalEntry copyWith({String? mode}) => ParentalEntry(mac: mac, name: name, mode: mode ?? this.mode, schedule: schedule);
}

/// Time Scheduling as the router holds it.
class ParentalControls {
  const ParentalControls({required this.on, required this.entries});

  /// `MULTIFILTER_ALL`: Enable Time Scheduling.
  final bool on;
  final List<ParentalEntry> entries;

  static const empty = ParentalControls(on: false, entries: []);

  ParentalEntry? entryFor(String mac) {
    for (final e in entries) {
      if (e.mac.toUpperCase() == mac.toUpperCase()) return e;
    }
    return null;
  }

  /// Whether [mac] has no internet now: an entry at block, with Time Scheduling on.
  bool isBlocked(String mac) => on && entryFor(mac)?.mode == kParentalBlock;

  /// The five key values to write, in the router's own format.
  Map<String, String> toNvram() => {
        'MULTIFILTER_ALL': on ? '1' : '0',
        'MULTIFILTER_MAC': entries.map((e) => e.mac).join('>'),
        'MULTIFILTER_DEVICENAME': entries.map((e) => e.name).join('>'),
        'MULTIFILTER_ENABLE': entries.map((e) => e.mode).join('>'),
        'MULTIFILTER_MACFILTER_DAYTIME_V2': entries.map((e) => e.schedule).join('>'),
      };
}

/// The five Time Scheduling keys, in the order the service reads them.
const List<String> kParentalKeys = [
  'MULTIFILTER_ALL',
  'MULTIFILTER_MAC',
  'MULTIFILTER_DEVICENAME',
  'MULTIFILTER_ENABLE',
  'MULTIFILTER_MACFILTER_DAYTIME_V2',
];

/// Time Scheduling from the five keys. The lists are parallel; a short one is padded rather than
/// trusted to line up, and an entry with no MAC is dropped, since nothing could be written for it.
ParentalControls parseParentalControls(Map<String, String> keys) {
  List<String> list(String k) {
    final v = (keys[k] ?? '').trim();
    return v.isEmpty ? <String>[] : v.split('>');
  }

  final macs = list('MULTIFILTER_MAC');
  final names = list('MULTIFILTER_DEVICENAME');
  final modes = list('MULTIFILTER_ENABLE');
  final schedules = list('MULTIFILTER_MACFILTER_DAYTIME_V2');
  String at(List<String> l, int i) => i < l.length ? l[i] : '';
  return ParentalControls(
    on: (keys['MULTIFILTER_ALL'] ?? '').trim() == '1',
    entries: [
      for (var i = 0; i < macs.length; i++)
        if (macs[i].trim().isNotEmpty)
          ParentalEntry(
            mac: macs[i].trim().toUpperCase(),
            name: at(names, i),
            mode: at(modes, i).isEmpty ? '0' : at(modes, i),
            schedule: at(schedules, i),
          ),
    ],
  );
}

/// [pc] with each device in [blocks] disabled (true) or not (false). [names] gives the name written
/// for a device that has no entry yet.
///
/// Disabling keeps a device's existing entry and its schedule, and sets it to block; a device with no
/// entry is added at the end, as the web interface does. Enabling again removes an entry whose
/// schedule is the web interface's default - one the app, or a plain block in the web interface, put
/// there - and sets any other back to 0, disable, so a schedule someone set up by hand is kept.
///
/// Time Scheduling is switched on when anything is disabled, and off when no entry is left. Every
/// other entry passes through as it was.
ParentalControls applyBlocks(ParentalControls pc, Map<String, bool> blocks, {Map<String, String> names = const {}}) {
  final entries = List.of(pc.entries);
  blocks.forEach((mac, block) {
    final m = mac.toUpperCase();
    final i = entries.indexWhere((e) => e.mac.toUpperCase() == m);
    if (block) {
      if (i >= 0) {
        entries[i] = entries[i].copyWith(mode: kParentalBlock);
      } else {
        final name = (names[mac] ?? names[m] ?? m).replaceAll(RegExp('[<>]'), '');
        entries.add(ParentalEntry(mac: m, name: name, mode: kParentalBlock, schedule: kParentalDefaultSchedule));
      }
    } else if (i >= 0) {
      if (entries[i].schedule == kParentalDefaultSchedule || entries[i].schedule.isEmpty) {
        entries.removeAt(i);
      } else {
        entries[i] = entries[i].copyWith(mode: '0');
      }
    }
  });
  final on = entries.isEmpty ? false : (pc.on || blocks.values.any((b) => b));
  return ParentalControls(on: on, entries: entries);
}

/// The entries, other than [changed], that switching Time Scheduling on would bring into force: the
/// ones set to time or block while it was off. Andrew's decision: the app turns Time Scheduling on
/// without asking only when this is empty; otherwise APPLY's confirmation names them first.
List<ParentalEntry> schedulesSwitchedOn(ParentalControls before, ParentalControls after, Set<String> changed) {
  if (before.on || !after.on) return const [];
  final c = {for (final m in changed) m.toUpperCase()};
  return [
    for (final e in after.entries)
      if (!c.contains(e.mac.toUpperCase()) && e.mode != '0') e,
  ];
}
