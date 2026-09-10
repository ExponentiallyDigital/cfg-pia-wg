// device_assignment_service.dart - reading and writing device-to-tunnel assignments over SSH.
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
// All the parsing lives in device_assignment.dart; this file is I/O and ordering.
//
// Stock firmware only - VPN Fusion is what device assignment is built on, and Merlin has no
// equivalent. The caller gates on firmware before constructing this.
import 'package:dartssh2/dartssh2.dart';

import 'device_assignment.dart';
import 'router_command.dart';
import 'router_slot_service.dart';
import 'router_watchdog.dart' show buildLoggerCommand, shellSingleQuote;

/// Everything the assignment screen needs, read in one round trip.
class AssignmentState {
  const AssignmentState({
    required this.devices,
    required this.policies,
    required this.profiles,
    required this.defaultIndex,
    required this.rawPolicyList,
    required this.rawClientlist,
  });

  final List<LanDevice> devices;
  final List<DevicePolicy> policies;

  /// Every `vpnc_clientlist` profile, WireGuard or not. The picker offers only the WireGuard ones,
  /// but the others must still be recognisable so a device pinned to one can be shown honestly
  /// rather than reported as unassigned.
  final List<VpncRecord> profiles;

  /// `vpnc_default_wan` - the index 6 of the default connection, or null for the plain internet.
  final int? defaultIndex;

  /// Kept verbatim for the stale-write check at apply time. See [DeviceAssignmentService.apply].
  final String rawPolicyList, rawClientlist;

  /// The profile a device is currently on, or null when it is on the default connection.
  VpncRecord? profileFor(LanDevice device) {
    final ip = device.ip;
    if (ip == null) return null;
    final idx = assignedIndexFor(policies, ip);
    if (idx == null) return null;
    for (final p in profiles) {
      if (p.vpncStateIndex == idx) return p;
    }
    return null;
  }
}

/// Thrown when the router's lists changed between the read and the apply.
///
/// The web interface rewrites the WHOLE of a list from the copy its page loaded, so an apply that
/// blindly wrote our version could silently undo a change made elsewhere in the meantime. README
/// section 6 records the same hazard in the other direction.
class AssignmentConflictException implements Exception {
  const AssignmentConflictException(this.what);
  final String what;

  @override
  String toString() => 'The router changed while you were editing ($what). '
      'Nothing was written, and your staged changes have been cleared. '
      'The list has been refreshed - make the change again if you still want it.';
}

class DeviceAssignmentService {
  DeviceAssignmentService(
    this.client, {
    this.onLog,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 40,
  });

  final SSHClient client;
  final void Function(String message, {bool isError, bool isSuccess})? onLog;

  /// How the default-connection sequence waits for each `service` call to finish. `notify_rc`
  /// QUEUES the call and returns immediately, so issuing the next step straight away races it -
  /// which is exactly what happened on hardware: all three calls landed inside two seconds and the
  /// key was zeroed after we had written it. Tests inject zero.
  final Duration pollInterval;
  final int maxPolls;

  // Reads are tolerant: a missing /tmp file or an unset key is an ordinary state, not a fault, and
  // the join is written to degrade on either. Writes go through the strict path and throw.
  Future<String> _read(String cmd) async =>
      (await runRouterCommand(client, cmd, allowFailure: true, onLog: onLog)).stdout;

  Future<String> _run(String cmd) async => (await runRouterCommand(client, cmd, onLog: onLog)).stdout;

  // One marker-delimited round trip rather than seven. A phone on wifi pays for every round trip,
  // and none of these reads depends on another.
  static const String _sep = '@@CFGPIAWG@@';

  Future<AssignmentState> read() async {
    onLog?.call('Reading device list...');
    // Written out rather than looped: an `eval "\$C"` loop is shorter, but a lower-case shell
    // variable in a command string is indistinguishable from the escaped-Dart-constant mistake
    // that no_escaped_constants_test.dart exists to catch. Eight named commands are also easier
    // to read than a loop over a list of them.
    final parts = (await _read('echo "$_sep"; nvram get vpnc_clientlist; '
            'echo "$_sep"; nvram get vpnc_dev_policy_list; '
            'echo "$_sep"; nvram get vpnc_default_wan; '
            'echo "$_sep"; nvram get dhcp_staticlist; '
            'echo "$_sep"; nvram get custom_clientlist; '
            'echo "$_sep"; nvram get cfg_device_list; '
            'echo "$_sep"; cat /jffs/nmp_cl_json.js 2>/dev/null; '
            'echo "$_sep"; cat /tmp/nmp_cache.js 2>/dev/null; '
            'echo "$_sep"'))
        .split(_sep);

    String at(int i) => i + 1 < parts.length ? parts[i + 1].trim() : '';

    final clientlist = at(0);
    final policyList = at(1);
    final devices = buildDeviceList(
      nmpClJson: at(6),
      nmpCache: at(7),
      customClientlist: at(4),
      dhcpStaticlist: at(3),
      cfgDeviceList: at(5),
    );
    onLog?.call('Found ${devices.length} devices.');

    return AssignmentState(
      devices: devices,
      policies: parseDevicePolicyList(policyList),
      profiles: parseVpncClientlist(clientlist),
      defaultIndex: int.tryParse(at(2)),
      rawPolicyList: policyList,
      rawClientlist: clientlist,
    );
  }

  /// Changes the default connection - the setting that decides where an unassigned device goes,
  /// and where an ASSIGNED device falls back to when its tunnel drops (ARCHITECTURE.md 3.3.6).
  ///
  /// Nothing about this sequence is guessable, and eleven probes on hardware were needed to find
  /// it. Every part of it is load-bearing:
  ///
  ///   1. `vpnc_unit` must name the TARGET's clientlist ROW, because that is the profile
  ///      `stop_vpnc` and `restart_vpnc` act on. Point it at the wrong row and the wrong tunnel is
  ///      restarted, the rule is never installed, and everything else looks like it worked.
  ///   2. `restart_default_wan` runs BEFORE the values are written. It tears the clients down and
  ///      resets `vpnc_default_wan` to 0 - which is why writing the key first always failed.
  ///   3. Only then are `vpnc_default_wan` (index 6) and `wgc_unit` (slot number) written. Three
  ///      different numbers name the same profile here; see ARCHITECTURE.md 4.2.
  ///   4. `restart_vpnc` starts the target, and THAT is what installs the pair of `ip rule`s at
  ///      priority 10000 - `from all iif br0 lookup <index 6>` and the same for br1.
  ///
  /// This is expensive: it stops and restarts tunnels, and takes about a minute. The caller must
  /// warn before calling it. Assigning a device costs nothing like this.
  Future<void> _setDefaultConnection(AssignmentState base, int index, {String from = '', String to = ''}) async {
    final row = base.profiles.indexWhere((p) => p.vpncStateIndex == index);
    final slot = row < 0 ? null : base.profiles[row].slot;

    // Named in both logs. The default connection decides where every unassigned device goes AND
    // where an assigned one falls back to when its tunnel drops, so a change to it explains an
    // outage days later - and until now the router log said nothing at all about it, while the app
    // log said only "default connection changed", which does not say from what or to what.
    final change = from.isEmpty || to.isEmpty ? '' : ' from $from to $to';
    onLog?.call('Changing the default connection$change - tunnels will restart...');
    await _read(buildLoggerCommand('default WAN connection set$change'));
    // Internet has no profile to restart, so only the teardown half applies.
    if (row >= 0) await _run('nvram set vpnc_unit=$row');

    await _run('service stop_vpnc');
    if (slot != null) await _awaitInterface('wgc$slot', up: false);

    // Waiting for this one is not optional. `restart_default_wan` resets the key to 0 as it runs,
    // so writing the values before it has finished means writing them into the path of the thing
    // that clears them.
    await _run('service restart_default_wan');
    await _awaitKeyCleared();

    if (index != 0 && slot != null) {
      await _run('nvram set vpnc_default_wan=$index');
      await _run('nvram set wgc_unit=$slot');
      await _run('nvram commit');
    }

    await _run('service restart_vpnc');
    if (slot != null) await _awaitInterface('wgc$slot', up: true);
    onLog?.call('Default connection set$change.', isSuccess: true);
  }

  /// Waits for [iface] to appear in, or vanish from, `wg show interfaces`.
  Future<void> _awaitInterface(String iface, {required bool up}) async {
    for (var i = 0; i < maxPolls; i++) {
      final present = (await _read(kUpInterfacesCommand)).contains(iface);
      if (present == up) return;
      await Future<void>.delayed(pollInterval);
    }
    // Not fatal: the caller verifies by re-reading, and a slot that is slow to come up is better
    // reported by the list than by an exception here.
    onLog?.call('$iface did not come ${up ? 'up' : 'down'} in time; continuing.', isError: true);
  }

  /// Waits for `restart_default_wan` to do its reset, which is the observable sign it has run.
  Future<void> _awaitKeyCleared() async {
    for (var i = 0; i < maxPolls; i++) {
      if ((await _read('nvram get vpnc_default_wan')).trim() == '0') return;
      await Future<void>.delayed(pollInterval);
    }
    onLog?.call('The router did not report the default connection being reset; continuing.', isError: true);
  }

  /// Removes the policy routing rules stock leaves behind when a device's assignment changes.
  ///
  /// Without this the whole feature is cosmetic: measured 2026-09-10, a device moved from wgc1 to
  /// wgc5 kept BOTH rules at priority 100, the older one matched first, and its traffic carried on
  /// leaving through wgc1 while every list on the router said wgc5. See [staleRuleTables] for the
  /// evidence and for why none of the service calls clear it.
  ///
  /// Deleting the rules directly is the light fix. `restart_net_and_phy` also works - it is what
  /// the web interface reaches for - but it bounces every switch port and re-leases the WAN, which
  /// drops every wireless client on the network. That is far too much for moving one device.
  ///
  /// Runs AFTER `restart_vpnc_dev_policy`, so it sweeps up whatever that call left in place, and
  /// repeats while it still finds something: the service is queued by `notify_rc`, so the first
  /// read can land before it has finished installing the new rule.
  Future<void> _clearStaleRules(Map<String, int?> changes) async {
    for (var pass = 0; pass < 3; pass++) {
      final rules = await _read(kIpRuleCommand);
      final deletions = <String>[];
      changes.forEach((ip, index) {
        for (final table in staleRuleTables(rules, ip: ip, keepIndex: index)) {
          deletions.add('ip rule del from $ip lookup $table');
        }
      });
      if (deletions.isEmpty) return;
      onLog?.call('Clearing ${deletions.length} stale routing rule(s)...');
      // Tolerant: a rule that has already gone between the read and the delete is the outcome we
      // wanted, not a failure worth stopping an apply for.
      for (final cmd in deletions) {
        await _read(cmd);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Applies staged changes in one pass.
  ///
  /// [changes] maps a device IP to the profile index 6 it should route through, or null to send it
  /// back to the default connection. [newDefaultIndex] rewrites `vpnc_default_wan` when given.
  ///
  /// Reservations: a device with no DHCP reservation gets one written here, because the policy
  /// record is keyed by IP and an unpinned address will eventually move. Measured 2026-09-08 -
  /// writing the reservation ourselves and calling only the light service pair applies the change
  /// with nothing bouncing, so the app never takes the whole-network restart the web interface
  /// does for the same job. Reservations are never removed again on unassign: removing one is as
  /// disruptive as adding one, and the device keeps the address anyway, so the breakage would
  /// arrive silently at some later renewal.
  Future<void> apply({
    required AssignmentState base,
    required Map<String, int?> changes,
    required Map<String, String> reservationsToCreate,
    int? newDefaultIndex,
    List<String> changeDescriptions = const [],
    String defaultFrom = '',
    String defaultTo = '',
  }) async {
    if (changes.isEmpty && newDefaultIndex == null) return;

    // The stale-write check. Re-read and compare BEFORE touching anything, so a conflict costs
    // nothing and the user is told rather than quietly overwritten.
    onLog?.call('Checking the router has not changed...');
    if ((await _read('nvram get vpnc_dev_policy_list')).trim() != base.rawPolicyList) {
      throw const AssignmentConflictException('device assignments were changed elsewhere');
    }
    if ((await _read('nvram get vpnc_clientlist')).trim() != base.rawClientlist) {
      throw const AssignmentConflictException('the VPN profile list was changed elsewhere');
    }

    if (reservationsToCreate.isNotEmpty) {
      final current = await _read('nvram get dhcp_staticlist');
      var list = current.trim();
      for (final entry in reservationsToCreate.entries) {
        if (parseDhcpStaticlist(list).containsKey(entry.key.toUpperCase())) continue;
        list = '$list<${entry.key.toUpperCase()}>${entry.value}>>';
      }
      onLog?.call('Creating ${reservationsToCreate.length} DHCP reservation(s)...');
      await _run('nvram set dhcp_staticlist=${shellSingleQuote(list)}');
    }

    // Only when something actually moved. A default-connection change on its own has no business
    // rewriting the policy list, and rewriting it would put our copy over anything that arrived
    // between the read and here.
    if (changes.isNotEmpty) {
      var policies = base.policies;
      changes.forEach((ip, index) => policies = setDevicePolicy(policies, ip: ip, vpncIndex: index));
      await _run('nvram set vpnc_dev_policy_list=${shellSingleQuote(serialiseDevicePolicyList(policies))}');
      await _run('nvram commit');

      // The light pair, per ARCHITECTURE.md 3.3. `restart_net_and_phy` - what the web interface
      // uses for the same job - bounces every switch port and re-leases the WAN, and is not needed.
      // What is being applied, by name, one per line. "Applying..." told the reader nothing, and
      // the app log is the only record of an assignment once the screen has moved on.
      onLog?.call('Applying ${changes.length} device change${changes.length == 1 ? '' : 's'}:');
      for (final d in changeDescriptions) {
        onLog?.call('  $d');
      }
      await _run('service restart_dnsmasq');
      await _run('service restart_vpnc_dev_policy');
      await _clearStaleRules(changes);
    }
    if (newDefaultIndex != null) {
      await _setDefaultConnection(base, newDefaultIndex, from: defaultFrom, to: defaultTo);
    }
    onLog?.call('Device assignments applied.', isSuccess: true);
  }
}
