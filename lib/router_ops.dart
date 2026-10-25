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
// time (.claude/plans/plan_firmware-abstraction.md). This is slice 1: start, stop and restart. The
// flows around them - NVRAM writes, verification, logging - stay where they are and call [routerOps].
//
// The commands are what each firmware was measured to need (ARCHITECTURE.md "Enable existing slot",
// "Stop/Disable"); test/unit/firmware_paths_test.dart fails if either firmware's are lost.

import 'firmware.dart';
import 'router_slot_service.dart';

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
}

/// The session's firmware's calls. The one place start, stop and restart ask which firmware this is:
/// it is detected once per session, when the app connects (firmware.dart).
RouterOps routerOps() => isStockFirmware ? const StockOps() : const MerlinOps();
