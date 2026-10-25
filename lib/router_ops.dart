// router_ops.dart - what starting, stopping and restarting a slot is on each firmware (ID-449).
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
// Stock support was added by branching at each point of difference, so the same two commands were
// written out at every start and stop, and two hardware bugs came from a branch that didn't match
// its twin's intent: `restart_vpnc` where `stop_vpnc` was needed, and a row index where a slot was.
// The firmware abstraction gathers each difference here, the two firmwares side by side, a slice at a
// time (.claude/plans/plan_firmware-abstraction.md): slice 1, start, stop and restart (ID-449); slice
// 2, reading the slots (ID-450); slice 3, keeping the watchdog's schedule over a reboot (ID-451); slice 4, what deleting a slot clears
// beyond its own keys (ID-452). The
// flows around them - NVRAM writes, verification, logging - stay
// where they are and call [routerOps].
//
// The commands are what each firmware was measured to need (ARCHITECTURE.md "Enable existing slot",
// "Stop/Disable"); test/unit/firmware_paths_test.dart fails if either firmware's are lost.

import 'firmware.dart';
import 'router_slot_service.dart';
import 'router_watchdog.dart';

/// What reading a slot finds that each firmware keeps in its own place.
typedef SlotState = ({String desc, bool killSwitch, bool enabled});

/// The calls that differ by firmware. Each takes the [RouterSlotService] of the action in hand, for
/// its connection, its logging and its service queue.
abstract class RouterOps {
  const RouterOps();

  /// Starts [slot]'s tunnel. [queued] puts Merlin's call through the router's service queue, as the
  /// watchdog's ENABLE has; stock's always is (RouterSlotService.runVpncService).
  Future<void> startSlot(RouterSlotService slots, int slot, {bool queued = false});

  /// Stops [slot]'s tunnel.
  Future<void> stopSlot(RouterSlotService slots, int slot);

  /// Restarts [slot]'s tunnel, so a running one picks up changed settings (EDIT's SAVE, ID-203).
  Future<void> restartSlot(RouterSlotService slots, int slot);

  /// Each slot's [SlotState], from a reader made once per read of the slots, since stock's are all in
  /// one list read once.
  Future<Future<SlotState> Function(int slot)> slotStateReader(RouterSlotService slots);

  /// The router's own encrypted-DNS servers, for CREATE and EDIT's overlap note (ID-005).
  Future<Set<String>> routerDotServers(RouterSlotService slots);

  /// How many tunnels the router lets run at once, or null for no cap.
  Future<int?> maxActiveSlots(RouterSlotService slots);

  /// Makes [slot]'s two cron entries, the check every [intervalMin] minutes and the log rotation,
  /// survive a reboot.
  Future<void> persistSchedule(RouterWatchdog wd, int slot, int intervalMin);

  /// Drops [slot]'s entries from where [persistSchedule] put them.
  Future<void> unpersistSchedule(RouterWatchdog wd, int slot);

  /// UNINSTALL: every slot's entries out of the firmware's own boot file, and what that did for the
  /// list UNINSTALL shows, or null when another step deals with it.
  Future<String?> removeAllSchedules(RouterWatchdog wd);

  /// Whether this router can keep a schedule over a reboot at all.
  Future<bool> bootPersistenceReady(RouterWatchdog wd);

  /// DELETE, after the slot's own wgcN_* keys: whatever else the firmware keeps for [slot].
  Future<void> clearProfile(RouterSlotService slots, int slot);

  /// DELETE's read-back: true when the firmware still lists [slot] as a profile.
  Future<bool> profileLeft(RouterSlotService slots, int slot);
}

/// Stock drives WireGuard through VPN Fusion: the profile is `vpnc_unit`, its row in
/// `vpnc_clientlist`, and the service is `restart_vpnc` or `stop_vpnc`. There is no start_vpnc, and
/// restart_vpnc for a stop leaves the interface up.
class StockOps extends RouterOps {
  const StockOps();

  @override
  Future<void> startSlot(RouterSlotService slots, int slot, {bool queued = false}) =>
      slots.runVpncService(slot, 'restart_vpnc', required: true);

  @override
  Future<void> stopSlot(RouterSlotService slots, int slot) => slots.runVpncService(slot, 'stop_vpnc');

  @override
  Future<void> restartSlot(RouterSlotService slots, int slot) => slots.runVpncService(slot, 'restart_vpnc', required: true);

  /// The region name and the switched-on flag are in vpnc_clientlist, not per-slot keys. The name falls
  /// back to wgcN_desc when the row is missing or blank: a watchdog deployed before the deploy path wrote
  /// the row left the slot looking empty, greying out every button that needs a name. DELETE unsets
  /// wgcN_desc with the row, so this can't bring a deleted slot back. Stock has no kill switch
  /// (ARCHITECTURE.md "Field reference"), so its badge never lights.
  @override
  Future<Future<SlotState> Function(int slot)> slotStateReader(RouterSlotService slots) async {
    final vpnc = await slots.readVpncBySlot();
    return (slot) async {
      var desc = vpnc[slot]?.desc ?? '';
      if (desc.trim().isEmpty) desc = await slots.read('nvram get wgc${slot}_desc');
      return (desc: desc, killSwitch: false, enabled: vpnc[slot]?.active ?? false);
    };
  }

  /// `dnspriv_rulelist`; a read that fails means no note.
  @override
  Future<Set<String>> routerDotServers(RouterSlotService slots) async {
    try {
      return parseDotServerList(await slots.read(kDotServerListCommand));
    } catch (_) {
      return {};
    }
  }

  /// `vpnc_max_conn`, as the router holds it, so a user who changed it gets what they set.
  @override
  Future<int?> maxActiveSlots(RouterSlotService slots) => slots.readMaxActiveVpns();

  /// Stock has no services-start, so the app owns the replacement block of an init script the firmware
  /// already runs at boot and on a firewall restart, `S50downloadmaster`, keeping the original once.
  @override
  Future<void> persistSchedule(RouterWatchdog wd, int slot, int intervalMin) async {
    await wd.backupOriginalS50();
    await wd.writeS50(slot, extra: [buildCronCheckLine(slot, intervalMin), buildCronRotateLine(slot)]);
    await wd.writeLighttpdStub();
    // Install the entries now rather than waiting for the next boot.
    await wd.run("'$kS50Path' start");
  }

  @override
  Future<void> unpersistSchedule(RouterWatchdog wd, int slot) async {
    await wd.writeS50(slot);
    await wd.run("chmod 700 '$kS50Path'");
  }

  /// The S50 script itself is restored with the other init scripts, earlier in UNINSTALL.
  @override
  Future<String?> removeAllSchedules(RouterWatchdog wd) async => null;

  /// The init directory the S50 script lives in comes from Download Master. Without it, a watchdog is
  /// not durable, and which way that fails depends on the router: with no `/opt/etc/init.d` the write
  /// fails with a byte count that reads like a full filesystem; with the directory but no working
  /// Download Master, the write succeeds and nothing runs it at the next boot. Checking first turns both
  /// into one sentence the user can act on.
  @override
  Future<bool> bootPersistenceReady(RouterWatchdog wd) async => (await wd.run("[ -d '$kStockBootDir' ] && echo 1 || echo 0")) == '1';

  /// The profile's runtime keys, vpncN_*, N being the profile's index 6, not the slot number (wgc1
  /// left vpnc9_* behind), resolved while its row is still there; then the row. First, what names
  /// that index: a device pinned to it keeps naming it for ever, since stock never lets one go, and
  /// ends up on whatever region is created in that slot next, a pin the web interface can't show
  /// (measured 2026-09-11); and the default connection, if it is this profile.
  @override
  Future<void> clearProfile(RouterSlotService slots, int slot) async {
    final stateIdx = vpncStateIndexForSlot(parseVpncClientlist(await slots.read('nvram get vpnc_clientlist')), slot);
    await slots.releaseProfileIndex(stateIdx, slot);
    for (final key in kVpncRuntimeKeys) {
      await slots.read('nvram unset vpnc${stateIdx}_$key');
    }
    await slots.removeProfileRow(slot);
  }

  /// The row the web interface lists.
  @override
  Future<bool> profileLeft(RouterSlotService slots, int slot) async => (await slots.readVpncBySlot()).containsKey(slot);
}

/// Merlin has a service per slot, `start_wgc N` and `stop_wgc N`, and its VPN routing service is
/// restarted or started after, so policy rules follow the tunnel.
class MerlinOps extends RouterOps {
  const MerlinOps();

  @override
  Future<void> startSlot(RouterSlotService slots, int slot, {bool queued = false}) async {
    const name = 'start_wgc';
    final command = 'service "start_wgc $slot"; service restart_vpnrouting0';
    if (!queued) {
      await slots.run(command);
      return;
    }
    final queue = slots.serviceQueue;
    await queue.clearIfStale();
    final skips = await queue.skipCount();
    await slots.run(command);
    await queue.awaitIdle();
    await queue.checkNotSkipped(skips, name);
  }

  @override
  Future<void> stopSlot(RouterSlotService slots, int slot) => slots.run('service "stop_wgc $slot"; service start_vpnrouting0');

  @override
  Future<void> restartSlot(RouterSlotService slots, int slot) =>
      slots.run('service "stop_wgc $slot"; sleep 2; service "start_wgc $slot"; service restart_vpnrouting0');

  /// Each slot's own keys: wgcN_desc, wgcN_enforce (the kill switch) and wgcN_enable.
  @override
  Future<Future<SlotState> Function(int slot)> slotStateReader(RouterSlotService slots) async => (slot) async {
        final desc = await slots.read('nvram get wgc${slot}_desc');
        final killSwitch = (await slots.read('nvram get wgc${slot}_enforce')) == '1';
        final enabled = (await slots.read('nvram get wgc${slot}_enable')) == '1';
        return (desc: desc, killSwitch: killSwitch, enabled: enabled);
      };

  /// Merlin has no `dnspriv_rulelist`.
  @override
  Future<Set<String>> routerDotServers(RouterSlotService slots) async => {};

  /// Merlin has no `vpnc_max_conn`, and no cap.
  @override
  Future<int?> maxActiveSlots(RouterSlotService slots) async => null;

  /// Merlin's own boot hook, `services-start`, two lines per slot appended to it.
  @override
  Future<void> persistSchedule(RouterWatchdog wd, int slot, int intervalMin) async {
    const path = kServicesStartPath;
    await wd.run("[ -f '$path' ] || { echo '#!/bin/sh' > '$path'; chmod +x '$path'; }");
    await wd.run(
      "grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' > '$path.tmp' 2>/dev/null; "
      "mv '$path.tmp' '$path'",
    );
    await wd.run("printf '%s\\n' ${shellSingleQuote(buildCronCheckLine(slot, intervalMin))} >> '$path'");
    await wd.run("printf '%s\\n' ${shellSingleQuote(buildCronRotateLine(slot))} >> '$path'");
    await wd.run("chmod +x '$path'");
  }

  @override
  Future<void> unpersistSchedule(RouterWatchdog wd, int slot) async {
    const path = kServicesStartPath;
    await wd.run(
      "[ -f '$path' ] && grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' "
      "> '$path.tmp' && mv '$path.tmp' '$path' && chmod 700 '$path'",
    );
  }

  @override
  Future<String?> removeAllSchedules(RouterWatchdog wd) async {
    const path = kServicesStartPath;
    final lines = int.tryParse(
        (await wd.read("grep -cE 'watchdog_(log_rotate_)?wgc[1-9] ' '$path' 2>/dev/null || true")).trim().split('\n').first);
    if (lines == null || lines <= 0) return 'No watchdog lines in $path to remove';
    await wd.read("grep -vE 'watchdog_(log_rotate_)?wgc[1-9] ' '$path' > '$path.tmp'; mv '$path.tmp' '$path' && chmod 700 '$path'");
    return 'Removed the watchdog lines from $path';
  }

  /// Merlin has `services-start` and needs nothing more.
  @override
  Future<bool> bootPersistenceReady(RouterWatchdog wd) async => true;

  /// A Merlin slot is its wgcN_* keys and nothing else.
  @override
  Future<void> clearProfile(RouterSlotService slots, int slot) async {}

  @override
  Future<bool> profileLeft(RouterSlotService slots, int slot) async => false;
}

/// The session's firmware's calls. The one place start, stop and restart ask which firmware this is:
/// it is detected once per session, when the app connects (firmware.dart).
RouterOps routerOps() => isStockFirmware ? const StockOps() : const MerlinOps();
