// widget_status.dart - what the home-screen widget shows, as pure data (ID-376).
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
// No SSH in this file, same discipline as device_assignment.dart: parse and decide here, so the
// shape the widget shows can be tested without a router, and WidgetStatusService (widget_status_
// service.dart) is left with nothing but I/O. Stock only - the widget's first slice covers the
// firmware device assignment already runs on; Merlin's own kill switch has no `vpnc_dev_policy_
// list` to read pins from, and is a later slice.

import 'device_assignment.dart';
import 'router_slot_service.dart' show VpncRecord, parseHandshakeAges, parseVpncClientlist, kAnsweringWithinSeconds;

/// One tunnel's row in the widget.
class WidgetTunnelInfo {
  const WidgetTunnelInfo({
    required this.slot,
    required this.region,
    required this.up,
    this.handshakeAgeSeconds,
    this.pinnedDeviceNames = const [],
  });

  final int slot;

  /// The PIA region name, `wgcN_desc` by way of `vpnc_clientlist` (ID-376 reuses what MANAGE
  /// already reads; `VpncRecord.desc` in router_slot_service.dart).
  final String region;

  /// Whether the interface is up, from `ip -o link show up` - present, not necessarily answering.
  final bool up;

  /// Seconds since the newest handshake, or null when the interface has never had one. A tunnel
  /// that is [up] but has no recent handshake is still down in the sense the widget cares about:
  /// nothing is flowing through it.
  final int? handshakeAgeSeconds;

  /// Devices pinned to this slot, by the name DEVICES shows (ID-376's "by the names DEVICES
  /// shows").
  final List<String> pinnedDeviceNames;

  /// Up, and recently enough for [kAnsweringWithinSeconds] - the same bar ENABLE and the watchdog
  /// use, so the widget never calls a tunnel healthy that they would not.
  bool get answering => up && handshakeAgeSeconds != null && handshakeAgeSeconds! <= kAnsweringWithinSeconds;
}

/// The widget's overall badge (BACKLOG ID-376 "What it shows").
enum WidgetBadge {
  /// Every configured tunnel is answering.
  protected,

  /// At least one configured tunnel is not answering.
  tunnelDown,

  /// No tunnel is configured at all - nothing to report either way.
  notChecked,
}

/// Everything the widget draws, from one round trip ([WidgetStatusService.read]).
class WidgetStatus {
  const WidgetStatus({
    required this.tunnels,
    this.guardedOfflineDeviceNames = const [],
    required this.checkedAt,
  });

  final List<WidgetTunnelInfo> tunnels;

  /// Names of devices pinned to a tunnel that is not answering - the guard is holding them
  /// offline rather than letting them follow the default connection. Reused for the amber row's
  /// "TABLET kept offline by the guard" line in the mock-up.
  final List<String> guardedOfflineDeviceNames;

  /// When this was read, the phone's clock - [checkedAt] is never sent to the router, only used
  /// to show the widget's own age once the read is this old (ID-376 "greyed when it's old").
  final DateTime checkedAt;

  WidgetBadge get badge {
    if (tunnels.isEmpty) return WidgetBadge.notChecked;
    return tunnels.every((t) => t.answering) ? WidgetBadge.protected : WidgetBadge.tunnelDown;
  }
}

/// Builds [WidgetStatus] from the router's own output - no SSH, no clock but the one passed in.
///
/// [vpncClientlist]: `nvram get vpnc_clientlist`, for each slot's region name and its state index
/// (the field a device's pin actually names - `VpncRecord.vpncStateIndex`, router_slot_service.dart).
/// [devicePolicyList]: `nvram get vpnc_dev_policy_list`, for which device is pinned where.
/// [upInterfaces]: `kUpInterfacesCommand`'s output (`ip -o link show up`, router_slot_service.dart).
/// [handshakeAgesRaw]: `kHandshakeAgesCommand`'s output, the router's own clock included.
/// [devices]: from [buildDeviceList], for showing a pin by name rather than by bare address.
WidgetStatus buildWidgetStatus({
  required String vpncClientlist,
  required String devicePolicyList,
  required String upInterfaces,
  required String handshakeAgesRaw,
  required List<LanDevice> devices,
  required DateTime checkedAt,
}) {
  final profiles = parseVpncClientlist(vpncClientlist);
  final ages = parseHandshakeAges(handshakeAgesRaw);
  final pinnedBySlot = _pinnedBySlot(profiles, parseDevicePolicyList(devicePolicyList), devices);

  final tunnels = [
    for (final p in profiles)
      if (p.slot != null && p.desc.trim().isNotEmpty)
        WidgetTunnelInfo(
          slot: p.slot!,
          region: p.desc,
          up: upInterfaces.contains('wgc${p.slot}'),
          handshakeAgeSeconds: ages[p.slot],
          pinnedDeviceNames: List.unmodifiable(pinnedBySlot[p.slot] ?? const []),
        ),
  ];

  final offline = <String>[
    for (final t in tunnels)
      if (!t.answering) ...t.pinnedDeviceNames,
  ];

  return WidgetStatus(tunnels: tunnels, guardedOfflineDeviceNames: offline, checkedAt: checkedAt);
}

/// The devices pinned to each slot, by the names DEVICES shows.
///
/// A pin names a profile by its vpncStateIndex (ARCHITECTURE's "iptables ID"), not by slot number
/// directly - the same indirection DeviceAssignmentService already resolves for DEVICES.
Map<int, List<String>> _pinnedBySlot(List<VpncRecord> profiles, List<DevicePolicy> policies, List<LanDevice> devices) {
  final slotByStateIndex = {
    for (final p in profiles)
      if (p.slot != null && p.vpncStateIndex != null) p.vpncStateIndex!: p.slot!,
  };
  final nameByIp = {for (final d in devices) if ((d.ip ?? '').isNotEmpty) d.ip!: d.displayName};
  final pinnedBySlot = <int, List<String>>{};
  for (final policy in policies) {
    if (!policy.isAssigned) continue; // unpinned, or pinned to the plain internet - not a tunnel row
    final slot = slotByStateIndex[policy.vpncIndex];
    if (slot == null) continue;
    pinnedBySlot.putIfAbsent(slot, () => []).add(nameByIp[policy.ip] ?? policy.ip);
  }
  return pinnedBySlot;
}
