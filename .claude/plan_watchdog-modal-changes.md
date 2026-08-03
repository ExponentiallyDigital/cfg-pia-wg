# Watchdog modal: collapse ENABLE/DISABLE into a single CREATE/EDIT action

## Context

The `WATCHDOG CONFIGURATION` modal currently offers ENABLE, EDIT, DISABLE, DELETE and
VIEW ROUTER WATCHDOG LOG. ENABLE and EDIT have converged: `RouterWatchdog.saveWatchdogConfig`
(the EDIT-save path) already sweeps other slots, enables the VPN slot, deploys the script,
installs both cron jobs, persists to `services-start` and runs the script — i.e. everything
`startWatchdog` (ENABLE) did. Keeping both is redundant and lets the user reach a half-configured
state by pressing ENABLE before EDIT.

Outcome: one button, `CREATE/EDIT`, that both creates and updates a watchdog and deploys it.
DISABLE goes away (teardown remains available via DELETE, and via the manage screen's DISABLE,
which stops the slot's watchdog as part of disabling the interface). Alongside this, PIA
credentials become genuinely session-retained so the user does not retype them each time a
dialog needing them is opened.

Note on scope: the buttons are **not** in [router_watchdog.dart](lib/router_watchdog.dart) — that
file is a pure model/service layer with no Flutter import. The buttons live in
[slot_modal.dart](lib/widgets/slot_modal.dart); `router_watchdog.dart` holds the processing behind
them. Only the **watchdog** button set changes; the `WIREGUARD CONFIGURATION` (manage) set keeps
CREATE / ENABLE / EDIT / DISABLE / DELETE untouched.

## Requirements as understood

1. Watchdog modal only: rename `EDIT` → `CREATE/EDIT`.
2. Remove the watchdog `DISABLE` button and its processing.
3. Remove the watchdog `ENABLE` button and its processing.
4. Write a message to the **router syslog** when the deploy finishes.
5. Rename `saveWatchdogConfig` to a name reflecting what it now does → **`deployWatchdog`**.
6. PIA username/password retained in memory for the session (mirroring how `sshUsername` /
   `sshPassword` are retained in `SessionController` and prefilled), and prefilled into PIA
   credential fields that are not already populated.
7. Update tests. Do **not** touch project documentation markdown (`ARCHITECTURE.md`,
   `CHANGELOG.md`, `.claude/*.md` etc.).

---

## 1. `lib/widgets/slot_modal.dart`

**Buttons** — [`_buttons()`](lib/widgets/slot_modal.dart#L583-L589), watchdog branch becomes:

```dart
// Watchdog mode: CREATE/EDIT creates-or-updates and deploys; DELETE requires a non-empty slot.
return [
  btn('slot_edit', 'CREATE/EDIT', info != null ? _editWatchdog : null),
  btn('slot_delete', 'DELETE', hasDesc ? _deleteWatchdog : null),
  btn('slot_view_log', 'VIEW ROUTER WATCHDOG LOG', (hasDesc && wdActive) ? _viewWatchdogLog : null),
];
```

Keep the `slot_edit` widget key (tests and muscle memory both rely on it) and keep the existing
`info != null` gate — `WatchdogDialog` already handles the empty-slot *create* flow via
`slotIsEmpty` (region pick + `enableVpnSlot`), which is exactly what "CREATE" means here.
`enabled` stays (still used by the manage branch); `wdActive` stays (VIEW LOG gate).

**Delete:**
- `_enableWatchdog` ([L304-330](lib/widgets/slot_modal.dart#L304-L330)) — including its two
  "…via EDIT first" `AppErrors` messages and its `loadConfig`/`copyWith`/`validate` pre-flight.
- `_disableWatchdog` ([L332](lib/widgets/slot_modal.dart#L332)).
- `_runWatchdog` ([L107-122](lib/widgets/slot_modal.dart#L107-L122)) — **becomes dead** once both
  handlers go (only those two called it; `_deleteWatchdog` and `_viewWatchdogLog` use their own
  inline `try/finally`). Dart's `unused_element` lint will flag it otherwise.

**Keep:** `_wdSvc`, and every remaining `stopWatchdog` call site
([L235](lib/widgets/slot_modal.dart#L235), [L255](lib/widgets/slot_modal.dart#L255),
[L298](lib/widgets/slot_modal.dart#L298), [L363](lib/widgets/slot_modal.dart#L363)).

**Header comment** [L16-18](lib/widgets/slot_modal.dart#L16-L18) — update the watchdog line to
`watchdog -> CREATE/EDIT, DELETE, VIEW ROUTER WATCHDOG LOG`.

## 2. `lib/router_watchdog.dart`

**Rename** `saveWatchdogConfig` → `deployWatchdog` ([L365](lib/router_watchdog.dart#L365)), change
its `_guard('save', …)` label to `_guard('deploy', …)`, and rewrite the doc comment above it —
it currently says "EDIT-save", and must now describe the single create-or-update-and-deploy path.
Keep the existing ordering comment about `deactivateOtherSlots` running before
`_writeWatchdogNvram` (that constraint is unchanged and non-obvious).

**Add the completion syslog line** at the end of the body, after the script run:

```dart
await _logRouter(
  'Watchdog deployed for wgc${config.slotIndex} (every ${config.cronIntervalMinutes}m)',
);
```

Reuse the existing private `_logRouter` helper ([L313](lib/router_watchdog.dart#L313)) — it already
does `logger -t cfg-pia-wg` with `shellSingleQuote` escaping. This restores the message
`startWatchdog` used to emit.

**Delete:**
- `startWatchdog` ([L400-414](lib/router_watchdog.dart#L400-L414)) — sole caller was the removed
  `_enableWatchdog`.
- `deployWatchdogScripts` ([L384-398](lib/router_watchdog.dart#L384-L398)) — sole caller was
  `startWatchdog`. `deployWatchdog` performs its own heredoc write / chmod / script run inline.

**Keep** (all still reachable): `stopWatchdog` (DELETE, manage DISABLE, manage ENABLE sweep,
`deactivateOtherSlots`), `enableVpnSlot` (`deployWatchdog` + the empty-slot create path in
`WatchdogDialog`), `disableVpnSlot`, `deactivateOtherSlots`, `_writeWatchdogNvram`, `loadConfig`,
`getWatchdogStatus`, `getWatchdogLog`, `testEmail`, the ping helpers.

Also fix the now-stale comment on `_writeWatchdogNvram`
([L345](lib/router_watchdog.dart#L345)) — it says "Shared by deploy (ENABLE) and the EDIT save
path"; there is now one caller. Leave the `deactivateOtherSlots` comment referencing
"the manage ENABLE path in slot_modal.dart" — that path still exists.

`waitForWatchdogReady` is already unreferenced in `lib/` today (pre-existing, not ENABLE-related).
Leave it alone — out of scope.

## 3. PIA credential retention — `lib/watchdog_dialog.dart`

The gap: `WatchdogDialog` *reads* `_c.piaUsername`/`_c.piaPassword` (passed in from
[slot_modal.dart:343-344](lib/widgets/slot_modal.dart#L343-L344)) and prefills its `wd_pia_user` /
`wd_pia_pass` fields, but **never writes back**. Anything the user types there is lost when the
dialog closes, so the next dialog opens empty. Compare the SSH pattern in
[router_slots_screen.dart:67-71 / 95-97](lib/widgets/router_slots_screen.dart#L67-L71), and the
PIA round-trip that `standalone_config_screen.dart` and `_PiaCredsDialog` already do.

Add a one-line private helper and call it from two places:

```dart
// Mirror the PIA credentials back into the session so every other screen/dialog that needs them
// pre-fills, matching how the SSH credentials are retained (session_controller.dart).
void _rememberPiaCreds() {
  final user = _piaUserCtrl.text.trim();
  final pass = _piaPassCtrl.text;
  if (user.isNotEmpty) _c.piaUsername = user;
  if (pass.isNotEmpty) _c.piaPassword = pass;
}
```

- Call at the end of `_applyConfig` ([L141-154](lib/watchdog_dialog.dart#L141-L154)) — captures
  creds recovered from NVRAM (`cfg_pia_wg_user` / `cfg_pia_wg_password`) so a user who never typed
  them still gets them everywhere.
- Call in `dispose()` ([L88](lib/watchdog_dialog.dart#L88)) — captures typed creds on *any* exit
  (SAVE, CLOSE, or barrier dismiss), which is what "retained in memory" requires. Guarding on
  non-empty means CLOSE never blanks a previously-known credential.

Non-empty guards keep this consistent with the existing session semantics: creds are only ever
cleared by `SessionController.wipeAll` (Exit app / back-out from the main menu). Nothing is
persisted to device storage — `wipeAll` already resets both fields
([session_controller.dart:169-170](lib/session_controller.dart#L169-L170)), so the retention stays
in-memory-only as documented at the top of that file.

Consumers then pick the values up with no further change: `_PiaCredsDialog`
([slot_modal.dart:426-427](lib/widgets/slot_modal.dart#L426-L427)),
`standalone_config_screen.dart:59-60`, and `WatchdogDialog` itself on reopen.

**Stale comments to fix** in this file, now that EDIT is the only deploy trigger:
[L16-18](lib/watchdog_dialog.dart#L16-L18) ("SAVES … but does NOT deploy — the slot modal's ENABLE
deploys the script + cron") and [L201](lib/watchdog_dialog.dart#L201) ("ENABLE (in the slot modal)
deploys"). Update the `svc.saveWatchdogConfig(cfg, desc: newDesc)` call at
[L236](lib/watchdog_dialog.dart#L236) to `svc.deployWatchdog(...)`.

## 4. Tests

### `test/router_watchdog_service_test.dart`
- Rename the `saveWatchdogConfig` group and its three tests' call sites to `deployWatchdog`
  (groups at [L68](test/router_watchdog_service_test.dart#L68), plus
  [L187](test/router_watchdog_service_test.dart#L187) and
  [L212](test/router_watchdog_service_test.dart#L212) in the one-active-at-a-time group).
- Delete the `deployWatchdogScripts` group ([L53-66](test/router_watchdog_service_test.dart#L53-L66)) —
  its NVRAM / global-PIA-key / heredoc / chmod / syslog assertions are already covered by the
  `deployWatchdog` group.
- Delete the `startWatchdog` group ([L92-103](test/router_watchdog_service_test.dart#L92-L103)) and
  the `startWatchdog tears down the other slot…` test
  ([L199-208](test/router_watchdog_service_test.dart#L199-L208)) — the equivalent
  `deployWatchdog` assertions already exist alongside them. Fold the JFFS assertion
  (`nvram set jffs2_scripts=1`) into the `deployWatchdog` group so JFFS-enable coverage is not lost.
- Re-point the `_guard` error-path test at
  [L361-368](test/router_watchdog_service_test.dart#L361-L368) from `deployWatchdogScripts` to
  `deployWatchdog` (it throws on `chmod`, which `deployWatchdog` also runs).
- Add one assertion to the `deployWatchdog` group for the new completion syslog line, e.g.
  `expect(c.ran('logger -t cfg-pia-wg'), isTrue)` plus a check that a recorded command contains
  `Watchdog deployed for wgc1`.

### `test/widgets/slot_modal_test.dart`
- `button enablement follows watchdog-active state` ([L302](test/widgets/slot_modal_test.dart#L302)) —
  drop the `slot_enable` / `slot_disable` expectations
  ([L318-319](test/widgets/slot_modal_test.dart#L318-L319),
  [L325-326](test/widgets/slot_modal_test.dart#L325-L326)); keep the `slot_view_log` ones, and add
  `expect(_btn(tester, 'slot_edit').onPressed, isNotNull)` for both rows.
- Delete `DISABLE runs stopWatchdog and takes the tunnel down with it`
  ([L363-383](test/widgets/slot_modal_test.dart#L363-L383)). That behaviour stays covered by
  `stopWatchdog` service tests ([L240](test/router_watchdog_service_test.dart#L240)) and by the
  manage-mode DISABLE test.
- `EDIT opens the watchdog dialog` ([L431](test/widgets/slot_modal_test.dart#L431)) — retitle to
  `CREATE/EDIT opens the watchdog dialog`; the tap is by key so it still works. Add
  `expect(find.text('CREATE/EDIT'), findsOneWidget)` and
  `expect(find.text('ENABLE'), findsNothing)` / `expect(find.text('DISABLE'), findsNothing)` as the
  regression guard for this change.
- `watchdog ENABLE and DELETE are greyed for an empty slot`
  ([L561](test/widgets/slot_modal_test.dart#L561)) — retitle to cover DELETE only, drop the
  `slot_enable` assertion, and add `expect(_btn(tester, 'slot_edit').onPressed, isNotNull)`
  (CREATE/EDIT must be live on an empty slot — that's the CREATE half).
- Delete `watchdog ENABLE stops any other active watchdog and disables its interface`
  ([L576-616](test/widgets/slot_modal_test.dart#L576-L616)). **Coverage note:** the
  one-active-at-a-time rule now reaches the watchdog screen only through
  `deployWatchdog` → `deactivateOtherSlots`, which is already asserted at the service level
  ([L187-197](test/router_watchdog_service_test.dart#L187-L197) and the whole
  `deactivateOtherSlots` group). Driving it through the widget would need the dialog's region
  picker, so the service-level test is the right home.
- Manage-mode tests ([L91-299](test/widgets/slot_modal_test.dart#L91-L299),
  [L475-541](test/widgets/slot_modal_test.dart#L475-L541)) are untouched — that button set does not
  change. `expect(find.text('EDIT wgc1'), …)` at
  [L283](test/widgets/slot_modal_test.dart#L283) is the params-editor title, not a button.

### `test/watchdog_dialog_test.dart`
- Existing tests keep passing (the rename is internal; `find.text('DISABLE') → findsNothing` at
  [L63](test/watchdog_dialog_test.dart#L63) is still true).
- Add a test asserting retention: mount with `piaUser: ''`/`piaPass: ''`, type into `wd_pia_user`
  and `wd_pia_pass`, unmount via `tester.pumpWidget(const SizedBox())`, then expect
  `c.piaUsername` / `c.piaPassword` to hold the typed values.
- Add a test asserting NVRAM-sourced creds land in the session: responder returns
  `p7654321` for `nvram get cfg_pia_wg_user`, mount with empty `piaUser`, settle, expect
  `c.piaUsername == 'p7654321'`.

---

## Verification

1. `flutter analyze` — must be clean. This is the check that catches a missed dead private method
   (`_runWatchdog`) or a leftover `saveWatchdogConfig` / `startWatchdog` reference.
2. `flutter test` — full suite green. Specifically
   `flutter test test/widgets/slot_modal_test.dart test/watchdog_dialog_test.dart test/router_watchdog_service_test.dart`
   while iterating.
3. Run the app (`flutter run -d windows`, or via the `/run` skill): Main menu → **Watchdog
   WireGuard management** → connect → the modal must show exactly **CREATE/EDIT**, **DELETE**,
   **VIEW ROUTER WATCHDOG LOG**, with no ENABLE or DISABLE. Confirm the manage screen
   (**Manage router PIA WireGuard configuration**) still shows CREATE / ENABLE / EDIT / DISABLE /
   DELETE.
4. PIA retention, in one session: open watchdog CREATE/EDIT on a slot with no stored creds, type a
   PIA username/password, press CLOSE, reopen — the fields must be prefilled. Then go to the
   manage screen's CREATE and confirm its PIA credentials dialog is prefilled too.
5. Against a real Merlin router (or by reading the recorded commands in the widget tests): after a
   successful CREATE/EDIT save, the router syslog must contain
   `cfg-pia-wg … Watchdog deployed for wgcN (every Nm)`. Visible on the router via
   `logread | grep cfg-pia-wg`.

## Explicitly out of scope

- `ARCHITECTURE.md`, `CHANGELOG.md`, `.claude/watchdog.md`, `.claude/ui_reorganisation.md` and any
  other markdown — several describe the old ENABLE/DISABLE watchdog flow and will be stale after
  this change, but you asked that documentation not be updated.
- The manage-mode button set, `_PingTargetsDialog`, and its `ENABLE` confirm button.
- `waitForWatchdogReady` (already unused before this change).
