# Plan: abstract the firmware split out of Manage and the watchdog

**Status:** DRAFT, not started. Early thinking only. Backlog item: `BACKLOG.md` section 1.3 "Codebase cleanup" -> "Abstract firmware from Manage and watchdog". Not current state — see `.claude/CONTEXT.md` for that.

## Why

Stock support was added by branching at each point of difference. That was the right way to get it working — every branch is a fact learned on hardware, and keeping them visible while learning them was the point — but the result is 27 `isStockFirmware` checks across six files:

| File | `isStockFirmware` sites |
| --- | ---: |
| `router_slot_service.dart` | 14 |
| `router_watchdog.dart` | 7 |
| `screens/slot_params_editor.dart` | 3 |
| `firmware.dart` | 1 |
| `watchdog_dialog.dart` | 1 |
| `widgets/router_slots_screen.dart` | 1 |

The two service files are also the two largest in `lib/` (1,554 and 842 lines). Every new router behaviour now costs two code paths and a mental check that both were updated, and the bugs this session produced — `restart_vpnc` where `stop_vpnc` was needed, `5 - slot` where a row index was needed — were both "the stock branch does not match the Merlin branch's intent".

## The shape that already works

`buildWatchdogScript` is a miniature of the answer. It does not branch at runtime; it resolves the firmware **once** and substitutes the differences into a template:

```dart
.replaceAll('__KILLSW__',  stock ? _kKillSwitchStock : _kKillSwitchMerlin)
.replaceAll('__MAILHDR__', stock ? _kMailHdrStock    : _kMailHdrMerlin)
.replaceAll('__MAILCMD__', stock ? _kMailCmdStock    : _kMailCmdMerlin)
```

Each pair sits side by side, so the two firmwares can be compared by eye, and a test asserts both variants carry what they must. That is the property to generalise: **differences adjacent and enumerable, not scattered through the flow.**

## Sketch

A `RouterOps` interface with two implementations, resolved once per session from the detected firmware, holding only the operations that genuinely differ:

```dart
abstract class RouterOps {
  Future<void> startSlot(int slot);          // start_wgc N   |  vpnc_unit + restart_vpnc
  Future<void> stopSlot(int slot);           // stop_wgc N    |  vpnc_unit + stop_vpnc
  Future<List<SlotInfo>> readSlots();        // wgcN_* keys   |  vpnc_clientlist
  Future<void> writeDesc(int slot, String desc);
  Future<void> persistCron(int slot, int intervalMin);  // services-start | S50downloadmaster
  List<String> get slotKeys;                 // 17 | 12, i.e. kMerlinOnlySlotKeys or not
  List<String> runtimeKeysToClear(int slot); // none | vpncN_* by clientlist index 6
}
```

Everything that does **not** differ — the reconfigure flow, the NVRAM writes, verification polling, the label cache, logging — stays where it is and takes a `RouterOps`.

## Sequencing — this is the important part

**Do not start until stock support has soaked in release.** This refactor touches every path stock support just landed on, and a regression introduced here would be indistinguishable from a stock-support bug. That is the same reasoning that gave the SSH connection reuse its own build number, and it applies with more force to a change this wide.

Suggested order, each on its own build:

1. `RouterOps` extracted for **start/stop only** — the smallest slice, and the one that has already produced two hardware bugs.
2. Slot reading (`fetchSlots` / `vpnc_clientlist`).
3. Cron persistence.
4. Delete and its runtime-key cleanup.

## Tests

The suite is the safety net here and it is a good one: 547 tests, 96%+ coverage, `useStock()` / `useMerlin()` already pin the firmware flag per test. The refactor should need **no test changes** at each step — if a step forces a test rewrite, the behaviour moved and that is the signal to stop and look.

Worth adding first: a test asserting that for every operation in `RouterOps`, both implementations are exercised. Otherwise a stock-only path can quietly lose Merlin coverage.

## Adjacent cleanup in the same backlog item

- `router_watchdog.dart` at 1,554 lines holds three separable things: the config model, the email layout, and the deployed script template. The email layout (`buildEmailBody`, `RouterEmailFacts`, the section constants) is self-contained and would move out cleanly with no behaviour change.
- `slot_modal.dart` at 767 lines carries manage mode and watchdog mode in one widget; they share the slot list and little else.

## 2026-10-25: moved to CHANGELOG 1.1

Andrew's order: after NETWORK (ID-458), this abstraction, then SonarCloud to zero (ID-419). BACKLOG's section as it was, moved here word for word when the items were made short:

#### BACKLOG 1.2. Codebase cleanup

The firmware abstraction, in slices, each on its own build and released on its own, with MAN, WD and DEV hand tests on stock and the MRL smoke test on Merlin before each release. It touches every path stock support landed on, so it starts after the release that carries ID-041 step 4. Plan: `.claude/plans/plan_firmware-abstraction.md`.

- ID-448 TST: a test that every operation the firmware abstraction will hold runs on both firmwares, so a stock-only path can't quietly lose its Merlin coverage. After the release carrying ID-041 step 4.
  - DoD: the test lists start, stop, slot reading, cron persistence and delete, finds each run under both `useStock()` and `useMerlin()`, and fails when one isn't.
- ID-449 ARC: firmware abstraction, slice 1: starting and stopping a slot go through one `RouterOps`, resolved once per session. After ID-448. The smallest slice, and the one that produced two hardware bugs (`restart_vpnc` for `stop_vpnc`, a row index for a slot).
  - DoD: no `isStockFirmware` branch is left in start or stop, the suite passes with no test changed, and MAN-3, MAN-8 and MRL pass on hardware.
- ID-450 ARC: slice 2: reading the slots (`fetchSlots`, `vpnc_clientlist`). After ID-449's release.
  - DoD: as ID-449, for reading, with MAN-15, MAN-16 and DEV-1 on hardware.
- ID-451 ARC: slice 3: persisting the watchdog's schedule (services-start or `S50downloadmaster`). After ID-450's release.
  - DoD: as ID-449, for persistence, with WD-9 and WD-17 on hardware.
- ID-452 ARC: slice 4: deleting a slot and clearing its runtime keys. After ID-451's release. Then ID-419.
  - DoD: as ID-449, for delete, with MAN-14 and the delete DEV tests on hardware.
- ID-419 CHG: the SonarCloud findings left in the watchdog and the slot service, after ID-452. Split from ID-041 2026-10-16, Andrew's decision. On 2026-10-19: `uninstallFromRouter` 38, `deployWatchdog` 36, `validate` 30, `testEmail` 18 (`router_watchdog.dart`); `createConfigToSlot` 37, `fetchSlots` 30, `enableSlot` 22, `restartSlot` 19 (`router_slot_service.dart`).
  - DoD: SonarCloud shows none of the eight, each function only split, and the suite passes unchanged.

## 2026-10-25: ID-448, the both-firmwares test

- `test/unit/firmware_paths_test.dart` runs each of the five operations the abstraction will hold under `useStock()` and `useMerlin()`, against one fake router (wgc5 with its `vpnc_clientlist` profile, tunnels up once switched on, pings answering, a watchdog interval stored), and checks each sends its own firmware's command and not the other's:

| Operation | Through | Stock sends | Merlin sends |
| --- | --- | --- | --- |
| start a slot | `RouterSlotService.enableSlot` | `restart_vpnc` (with `vpnc_unit`) | `service "start_wgc N"` |
| stop a slot | `disableSlot` | `stop_vpnc` | `service "stop_wgc N"` |
| read the slots | `fetchSlots` | `nvram get vpnc_clientlist` | `nvram get wgcN_enforce` (only Merlin has a kill switch) |
| persist the schedule | `RouterWatchdog.enableWatchdog` | `S50downloadmaster` | `services-start` |
| delete a slot | `deleteSlot` | `nvram unset vpncN_*` (the profile's runtime keys) | `service "stop_wgc N"` |

- Seen to fail: with `enableSlot`'s stock branch taken out, "start a slot on stock" failed; with Merlin's kill-switch read taken out of `fetchSlots`, "read the slots on Merlin" failed.
- For ID-449 on: each slice's DoD names hand tests (MAN-3, MAN-8, MRL and others). Andrew wants no hand tests (2026-10-25), so those become `[live]` runs like `live/network_live_test.dart` before each slice is released; MRL needs a Merlin router, which is a question for Andrew.
- Andrew, 2026-10-25: no Merlin router, and swapping firmware takes several hours, so not unless absolutely necessary. Each slice's Merlin side rests on `firmware_paths_test.dart` and the suite passing with no test changed; stock's on a `live/` run on Andrew's router, changing the router only with `CFG_LIVE_GO=1`, as `devices_live_test.dart` does. The slices' DoDs in CHANGELOG 1.1 now say so, in place of MAN, WD, DEV and MRL hand tests.

## 2026-10-25: ID-449, slice 1: start, stop and restart

- `lib/router_ops.dart`: `RouterOps` with `startSlot`, `stopSlot` and `restartSlot`, `StockOps` and `MerlinOps` side by side, and `routerOps()`, the one place these ask which firmware it is (detected once per session, when the app connects). Each call takes the `RouterSlotService` of the action in hand, for its connection, logging and service queue; the slot service gained a public `run` for it.
- Moved to it: `enableSlot`'s start, `_revertEnable`'s stop, EDIT's restart, `disableSlot`'s and `deleteSlot`'s stops (router_slot_service.dart), and the watchdog's ENABLE start and DISABLE stop (router_watchdog.dart). Restart joined start and stop: it is the same pair of commands, and EDIT's SAVE is where the plan's "start/stop" bug class would bite next.
- One difference kept, not smoothed over: the watchdog's Merlin start went through the router's service queue and MANAGE's didn't, so `startSlot` takes `queued`, and only the watchdog sets it. Making MANAGE's queued too would be a behaviour change, for its own item if wanted.
- Left alone: the watchdog's shell script, whose start and stop are already substituted from a template, and `device_assignment_service.dart`, which is stock only.
- No `isStockFirmware` is left in any start, stop or restart. The suite passed unchanged (2054, 3 skipped), `firmware_paths_test.dart` included.
- `live/slots_live_test.dart`: DISABLE then ENABLE on `CFG_LIVE_SLOT`, as MANAGE does them, pausing and resuming a scheduled watchdog; only with `CFG_LIVE_GO=1`. Left: Andrew's run on stock.
- Live runs on stock, Andrew, 2026-10-25, wgc1 (pia-nz, watchdog scheduled): the first failed SLT-2 on a bug of the runner's own, an up check that split `ip -o link show up` on spaces and never matched `wgc1:`, which also made SLT-1's second half hollow (DISABLE's own read-back still said down). Fixed to match `wgcN:`; the second run passed SLT-1 to SLT-3. ID-449 closed.

## 2026-10-25: slices 2 to 4 and the SonarCloud findings, together (ID-450, ID-451, ID-452, ID-419)

Andrew asked for all four at once, uninterrupted, in place of a release per slice. Each slice was checked with the suite and `firmware_paths_test.dart` before the next began; no existing test changed.

- Slice 2, reading (ID-450): `RouterOps.slotStateReader` (each slot's name, kill switch and switched-on flag: stock from `vpnc_clientlist` read once, with the `wgcN_desc` fallback; Merlin from `wgcN_desc`, `wgcN_enforce` and `wgcN_enable`), `routerDotServers` (stock's `dnspriv_rulelist`, Merlin none) and `maxActiveSlots` (stock's `vpnc_max_conn`, Merlin no cap). `fetchSlots` has no firmware branch, and its handshake bookkeeping moved to `_answeringSlots`. The slot service gained public `read` and `readVpncBySlot` for them.
- Slice 3, the schedule over a reboot (ID-451): `persistSchedule` and `unpersistSchedule` (stock's `S50downloadmaster`, Merlin's `services-start`), `removeAllSchedules` (UNINSTALL; stock's is the S50 restore, so null) and `bootPersistenceReady` (stock needs `/opt/etc/init.d`; Merlin always). `RouterWatchdog` gained `run`, `read`, `backupOriginalS50`, `writeS50` and `writeLighttpdStub` for them.
- Slice 4, delete (ID-452): `clearProfile` (stock: release pinned devices and the default connection naming the profile's index 6, unset its `vpncN_*` runtime keys, drop its row; Merlin nothing) and `profileLeft` (the read-back). The slot service gained `releaseProfileIndex` and `removeProfileRow`.
- ID-419: a cognitive complexity measure written for this (Dart's analyzer, SonarSource's rules, `??` not counted) gave exactly SonarCloud's figures for the eight at 54907ed: 38, 37, 36, 30, 30, 22, 19, 18. After the slices, `fetchSlots` was already under 15. Split, each only split: `restartSlot` (`_restartTook`, `_awaitHandshakeSince`), `enableSlot` (`_awaitInterfaceUp`, `_awaitHandshake`), `createConfigToSlot` (`_slotValuesFor`, `_stopBeforeReplacing`, `_backupSlot`, `_restoreAfterFailedCreate`, `_clearHalfWrittenSlot`), `testEmail` (`_diagnoseFailedEmail`), `validate` (`_checkErrors`, `_loginErrors`, `_emailErrors`), `deployWatchdog` (`_deploySteps`, `_undoFailedDeploy`, `_reportDeploy`, with `_DeployProgress` carrying how far it got) and `uninstallFromRouter` (one method per step, in the same order). Nothing in lib/ measures over 15 now.
- A slip caught on the way: splitting `deployWatchdog` by text replacement renamed `scheduled` inside the sentence "Its watchdog stays scheduled and will try again", and `$progress.didNothing` inside two messages. Both were fixed before any run, but no test held the first sentence, so one was added (a set-up slot whose deploy fails after scheduling) and seen to fail with the slip put back.
- Suite: 2055 passed, 3 skipped, 95.9%.
- `live/abstraction_live_test.dart`: RDS-1 reads the slots and checks them against the router's own lists; with `CFG_LIVE_GO=1`, SCH-1 and SCH-2 pause and resume a watchdog and count its boot lines; with `CFG_LIVE_PIA_USER` and `CFG_LIVE_PIA_PASS` as well, DEL-1 and DEL-2 create a throwaway configuration in an empty slot and delete it, then check no key, no row and no runtime keys are left. No tunnel that is up is touched.
- Live run on stock, Andrew, 2026-10-25, `live/abstraction_live_test.dart`: RDS-1, SCH-1, SCH-2, DEL-1 and DEL-2 all PASS (wgc1 paused and resumed; a throwaway wgc2 in Melbourne created and deleted, nothing left). ID-450, ID-451 and ID-452 closed. ID-419 waits on SonarCloud's own reading.

