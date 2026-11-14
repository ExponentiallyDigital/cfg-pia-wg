// merlin_vpn_director.dart - DEVICES on Merlin, as pure data: VPN Director's rules (ID-557).
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
// No SSH here. On Merlin a device is sent to a tunnel by a VPN Director rule in
// `/jffs/openvpn/vpndirector_rulelist`, not by VPN Fusion's `vpnc_dev_policy_list`, and the
// default connection is a rule for the whole network. This file turns those rules into the shapes
// DEVICES and the widget already work with on stock - profiles with an index 6 of `10 - slot`, and
// device policies naming that index - and turns DEVICES' changes back into rules, so the screens
// need no Merlin branch of their own. Measured on 3004.388.13_0, 2026-11-12 to 14; the plan file
// `.claude/plans/plan_devices-on-merlin.md` has each measurement.

import 'device_assignment.dart' show DevicePolicy;
import 'router_slot_service.dart' show VpncRecord, buildVpncRecord;

/// Where Merlin keeps VPN Director's rules. The web page and `service restart_vpnrouting0` both read
/// it; the second applies it (measured 2026-11-14).
const String kVpnDirectorRulelistPath = '/jffs/openvpn/vpndirector_rulelist';

/// What the web page refuses in a description ("<,>,',% are invalid characters"): `<` and `>`
/// separate the file's records and fields.
const String kVpnDirectorBadChars = "<>'%";

/// The web page's limit on a description (`maxlength="32"`, Advanced_VPNDirector.asp at 388.13).
const int kVpnDirectorDescMax = 32;

/// The description the app gives the whole-network rule it writes for the default connection.
const String kDefaultRuleDesc = 'default (cfg-pia-wg)';

/// One VPN Director rule: `enable>description>local IP>remote IP>interface`, interface `WGC1` to
/// `WGC5`, `OVPN1` to `OVPN5` or `WAN`. Fields the app doesn't own pass through untouched.
class VpnDirectorRule {
  const VpnDirectorRule(this.fields);

  final List<String> fields;

  factory VpnDirectorRule.of({required bool enabled, required String desc, required String local, required String iface}) =>
      VpnDirectorRule([enabled ? '1' : '0', desc, local, '', iface]);

  String _f(int i) => i < fields.length ? fields[i] : '';
  bool get enabled => _f(0) == '1';
  String get desc => _f(1);
  String get local => _f(2);
  String get remote => _f(3);
  String get iface => _f(4);

  /// The WireGuard slot this rule sends to, or null for WAN, OpenVPN or anything else.
  int? get wgSlot {
    final m = RegExp(r'^WGC([1-5])$').firstMatch(iface);
    return m == null ? null : int.parse(m.group(1)!);
  }

  bool get toWan => iface == 'WAN';

  /// A rule DEVICES can show and change: one device's address, no remote address, to a WireGuard
  /// slot or WAN. Everything else (a range, a remote, OpenVPN) is the user's own and is left alone.
  bool get isDeviceRule => remote.isEmpty && local.isNotEmpty && !local.contains('/') && (wgSlot != null || toWan);

  VpnDirectorRule copyWith({bool? enabled, String? iface}) {
    final f = [for (var i = 0; i < 5; i++) _f(i), ...fields.skip(5)];
    if (enabled != null) f[0] = enabled ? '1' : '0';
    if (iface != null) f[4] = iface;
    return VpnDirectorRule(f);
  }

  String serialise() => fields.join('>');
}

/// The rules as the file holds them: records each begun by `<`, no trailing newline.
List<VpnDirectorRule> parseVpnDirectorRules(String raw) => [
      for (final chunk in raw.trim().split('<'))
        if (chunk.trim().isNotEmpty) VpnDirectorRule(chunk.trim().split('>')),
    ];

/// Back to the file's form, byte for byte as the web page writes it: `<` before every record and
/// no newline, which would end up in the last rule's interface name.
String serialiseVpnDirectorRules(List<VpnDirectorRule> rules) => rules.map((r) => '<${r.serialise()}').join();

/// The interface name for a slot, as VPN Director writes it.
String wgIface(int slot) => 'WGC$slot';

/// The index 6 the stock-shaped profile for [slot] carries, as [buildVpncRecord] gives it.
int indexForSlot(int slot) => 10 - slot;

/// The slot a stock-shaped index names, or null for 0 (the internet) and anything out of range.
int? slotForIndex(int? index) => index == null || index < 5 || index > 9 ? null : 10 - index;

/// One line per slot, `N>desc>enable`: what [parseMerlinSlots] reads. Written out rather than looped,
/// for the reason device_assignment_service.dart gives.
const String kMerlinSlotsCommand = 'echo "1>\$(nvram get wgc1_desc)>\$(nvram get wgc1_enable)"; '
    'echo "2>\$(nvram get wgc2_desc)>\$(nvram get wgc2_enable)"; '
    'echo "3>\$(nvram get wgc3_desc)>\$(nvram get wgc3_enable)"; '
    'echo "4>\$(nvram get wgc4_desc)>\$(nvram get wgc4_enable)"; '
    'echo "5>\$(nvram get wgc5_desc)>\$(nvram get wgc5_enable)"';

/// Merlin's slots as stock-shaped profiles: one for each slot with a description, active when
/// `wgcN_enable` is 1, index 6 `10 - slot`.
List<VpncRecord> parseMerlinSlots(String raw) => [
      for (final line in raw.split('\n'))
        if (RegExp(r'^[1-5]>[^>]').hasMatch(line.trim()))
          buildVpncRecord(
            slot: int.parse(line.trim()[0]),
            desc: line.trim().split('>')[1],
            active: line.trim().split('>').length > 2 && line.trim().split('>')[2].trim() == '1',
          ),
    ];

/// The LAN as a network, `192.168.1.0/24`, from the router's address and netmask; empty when either
/// can't be read.
String lanSubnet(String ip, String mask) {
  List<int>? octets(String s) {
    final p = s.trim().split('.');
    if (p.length != 4) return null;
    final n = p.map(int.tryParse).toList();
    return n.any((x) => x == null || x < 0 || x > 255) ? null : n.cast<int>();
  }

  final a = octets(ip), m = octets(mask);
  if (a == null || m == null) return '';
  final bits = m.fold<int>(0, (s, o) => s + o.toRadixString(2).replaceAll('0', '').length);
  return '${[for (var i = 0; i < 4; i++) a[i] & m[i]].join('.')}/$bits';
}

/// The rule that is the default connection: enabled, for [subnet], to a WireGuard slot.
VpnDirectorRule? defaultRuleFor(List<VpnDirectorRule> rules, String subnet) {
  for (final r in rules) {
    if (subnet.isNotEmpty && r.local == subnet && r.remote.isEmpty && r.wgSlot != null && r.enabled) return r;
  }
  return null;
}

/// The default connection as a stock-shaped index: the whole-network rule's slot's, or 0 for the
/// internet when there is none.
int merlinDefaultIndex(List<VpnDirectorRule> rules, String subnet) {
  final slot = defaultRuleFor(rules, subnet)?.wgSlot;
  return slot == null ? 0 : indexForSlot(slot);
}

/// The device rules as stock-shaped policies: an enabled rule to a slot pins to `10 - slot`, to WAN
/// pins to 0 (the internet), and a disabled one follows the default. Where a device has more than
/// one rule, the first enabled one is what VPN Director acts on first among rules of its kind, and
/// is what's shown.
List<DevicePolicy> merlinPolicies(List<VpnDirectorRule> rules) {
  final out = <String, DevicePolicy>{};
  for (final r in rules.where((r) => r.isDeviceRule)) {
    final existing = out[r.local];
    if (existing != null && existing.enabled) continue;
    final slot = r.wgSlot;
    out[r.local] = DevicePolicy([r.enabled ? '1' : '0', r.local, '', '${slot == null ? 0 : indexForSlot(slot)}', '']);
  }
  return out.values.toList();
}

/// [name], made fit for a description: the four characters the web page refuses taken out, and cut
/// to its length. Falls back to [fallback] when nothing is left.
String vpnDirectorDesc(String name, {required String fallback}) {
  final cleaned = name.split('').where((c) => !kVpnDirectorBadChars.contains(c)).join().trim();
  final d = cleaned.isEmpty ? fallback : cleaned;
  return d.length <= kVpnDirectorDescMax ? d : d.substring(0, kVpnDirectorDescMax).trimRight();
}

/// DEVICES' changes applied to the rules. [changes] is device address to stock-shaped index (a
/// slot's, 0 for the internet) or null to follow the default; [newDefaultIndex] is the default
/// connection's, 0 for the internet. A device's existing rule is switched rather than added to,
/// keeping its description; a new one is named from [names]. Every other rule passes through.
List<VpnDirectorRule> applyMerlinChanges(
  List<VpnDirectorRule> rules, {
  required Map<String, int?> changes,
  int? newDefaultIndex,
  required String subnet,
  Map<String, String> names = const {},
}) {
  final out = List.of(rules);
  changes.forEach((ip, index) => _applyDeviceChange(out, ip, index, names));
  if (newDefaultIndex != null && subnet.isNotEmpty) _applyDefaultChange(out, newDefaultIndex, subnet);
  return out;
}

/// One device's change in [out]: its own rule switched, or a new one named from [names].
void _applyDeviceChange(List<VpnDirectorRule> out, String ip, int? index, Map<String, String> names) {
  final at = out.indexWhere((r) => r.isDeviceRule && r.local == ip);
  final slot = slotForIndex(index);
  final iface = slot == null ? 'WAN' : wgIface(slot);
  if (at < 0) {
    if (index != null) {
      out.add(VpnDirectorRule.of(enabled: true, desc: vpnDirectorDesc(names[ip] ?? '', fallback: ip), local: ip, iface: iface));
    }
    return;
  }
  out[at] = index == null ? out[at].copyWith(enabled: false) : out[at].copyWith(enabled: true, iface: iface);
  _switchOffLaterRules(out, at, ip);
}

/// A second rule for the same device would act before or after the one at [at] by slot, not by
/// intent: switched off, so the device has the one the user chose.
void _switchOffLaterRules(List<VpnDirectorRule> out, int at, String ip) {
  for (var i = at + 1; i < out.length; i++) {
    if (out[i].isDeviceRule && out[i].local == ip) out[i] = out[i].copyWith(enabled: false);
  }
}

/// The whole-network rule in [out] moved to [index]'s slot, added if there's none, or switched off
/// for the internet.
void _applyDefaultChange(List<VpnDirectorRule> out, int index, String subnet) {
  final slot = slotForIndex(index);
  final at = out.indexWhere((r) => r.local == subnet && r.remote.isEmpty && r.wgSlot != null);
  if (slot == null) {
    if (at >= 0) out[at] = out[at].copyWith(enabled: false);
    return;
  }
  if (at >= 0) {
    out[at] = out[at].copyWith(enabled: true, iface: wgIface(slot));
  } else {
    out.add(VpnDirectorRule.of(enabled: true, desc: kDefaultRuleDesc, local: subnet, iface: wgIface(slot)));
  }
}

/// The devices pinned to a slot numbered above the default's. VPN Director numbers its rules by
/// slot, lowest first, so the whole-network rule on a lower slot always wins and such a pin would
/// be ignored without a word; DEVICES refuses it instead (ID-556). Empty when the default is the
/// internet, where every pin wins.
List<String> pinsAboveDefault(List<VpnDirectorRule> rules, String subnet) {
  final def = defaultRuleFor(rules, subnet)?.wgSlot;
  if (def == null) return const [];
  return [
    for (final r in rules)
      if (r.isDeviceRule && r.enabled && (r.wgSlot ?? 0) > def) r.local,
  ];
}

/// The priority of the app's `prohibit` rule for a device pinned to [slot]: the top of the slot's
/// own range in VPN Director's numbering (11010 + 200 x slot up), after every Merlin rule for that
/// slot and before every rule for any other, the whole-network default included. Merlin deletes
/// only its own `lookup` rules there, so it stays through DISABLE and every restart (measured
/// 2026-11-14: at 12300, behind a whole-network rule, it didn't hold; at 11409 it did).
int merlinGuardPriority(int slot) => 11209 + 200 * slot;

/// The rule that exempts the router's own address from a whole-network rule, so the router can
/// still answer its LAN while the default's tunnel is down (measured 2026-11-14).
const int kMerlinRouterExemptPriority = 9990;

/// What the kernel's rules ([ipRuleOutput], `ip rule show`) lack against what [rules] ask for: each
/// enabled device rule's `lookup` of its tunnel or `main`, the app's `prohibit` for each pinned to a
/// tunnel, and the whole-network rule for the default. Empty when they match (ID-332).
List<String> merlinRuleProblems(List<VpnDirectorRule> rules, String subnet, String ipRuleOutput) {
  final lines = ipRuleOutput.split('\n').map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
  bool has(String tail) => lines.any((l) => l.endsWith(tail));
  final problems = <String>[];
  for (final r in rules.where((r) => r.isDeviceRule && r.enabled)) {
    final slot = r.wgSlot;
    if (!has('from ${r.local} lookup ${slot == null ? 'main' : 'wgc$slot'}')) problems.add('${r.local} has no VPN Director rule');
    if (slot != null && !lines.contains('${merlinGuardPriority(slot)}: from ${r.local} prohibit')) {
      problems.add('${r.local} is not held to its tunnel');
    }
  }
  final def = defaultRuleFor(rules, subnet)?.wgSlot;
  if (def != null && !has('from $subnet lookup wgc$def')) problems.add('the default connection has no rule');
  return problems;
}

/// Whether `ip rule show` output [rules] holds the app's `prohibit` for [ip] pinned to [slot].
bool merlinGuardHeld(String rules, String ip, int slot) => rules
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
    .contains('${merlinGuardPriority(slot)}: from $ip prohibit');
