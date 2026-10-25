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


