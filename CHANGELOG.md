# 1. CHANGELOG.md

- [1. Changes](#1-changes)
  - [1.1. Pending](#11-pending)
    - [WATCHDOG issues](#watchdog-issues)
  - [1.2. Implemented - chronological change history](#12-implemented---chronological-change-history)

---

## 1. Changes

### 1.1. Pending

See [BACKLOG.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/BACKLOG.md) for complete list.

- DOC: Add note to use data from About screen when creating an issue on GitHub, add to ISSUE_TEMPLATEs.
- DOC: add to `README.md` how to get and install `jq` and `sendmail-go` on stock firmware, plus how to install & cfg Download Master and use the replacement script.
- DOC: once stock firmware version operating, remove references to Merlin firmware requirement in Play Store description, README.md, and ARCHITECTURE.md.
- REL: update version to 0.9 branch when first releasing stock support.

#### WATCHDOG issues

- GUI: Make Manage and Watchdog deletion prompt messages consistent.
- GUI: Watchdog, when creating on a slot which has an existing WG config, make the prompt more intelligible.
- GUI: Watchdog, when creating one, show the name of any pre-existing region that will be overwritten.
- CHG: rebuild test/reconfigure email: router DNS name, date and time, why it was sent (test/reconfigure), the region, and cronIntervalMinutes; add lifetime number of reconfigure events (write start date and update total count to NVRAM).
- CHG: Remove 'WATCHDOG_EOF' text from test email:
         This is a test email from the cfg-pia-wg watchdog (slot wgcX).
         WATCHDOG_EOF
- CHG: On disable, log lines are repeated (and needs the region name per above)
        cfg-pia-wg: Disabled wgc1
        cfg-pia-wg: Watchdog disabled for wgc1
        cfg-pia-wg: Disabled wgc1
- CHG: on stock add test for DownloadMaster installed, on first run rename `router:/opt/etc/init.d/S50downloadmaster` and `router:/opt/etc/init.d/S50asuslighttpd` to .old.
- CHG: on Merlin w app, deleting a watchdog also deletes the underlying WG slot - modify to only delete the cron job and retain the underlying VPN slot config

---

### 1.2. Implemented - chronological change history

WIP:

  1. E2E test all MANAGE functions
  2. move watchdog scripts from /jffs/scripts to /jffs/cfg-pia-wg
  3. where will we put the watchdog log file?
  4. check we now store all cfg-pia files in out own jffs directory
  5. E2E test all WATCHDOG functions
  6. fix addkey error
  7. check watchdog script size
  8. add updated icon!

2026-09-04 v0.8.31 build 401 - WIP stock support for Watchdog function

- FIX: the watchdog's PIA re-negotiation always failed at addKey with curl exit 35. `--tlsv1.3` sets a MINIMUM version and PIA's addKey endpoint on :1337 does not offer 1.3, so the connection was refused before the request went out; the floor is now 1.2, which still negotiates 1.3 where the server supports it (the token and server-list hosts always did). This is the "ongoing since v0.8.17" addKey error.
- FIX: the curl error reached the log mangled - "u (35) eo1409442Eib...". BusyBox `tr` has no character classes, so `tr -d "[:cntrl:]"` deleted every literal c, n, t, r and l from the message. It now takes the first line and cuts it.
- FIX: deploying a watchdog on an empty slot enabled it twice - `deployWatchdog` brings the slot up, and the dialog then did it again, bouncing the tunnel the deploy's immediate script run had just established (two `service restart_vpnc` calls on stock). The dialog's second enable is gone; the immediate script run stays, so a failure still lands in the router log at deploy time rather than at the next cron tick.
- GUI: the watchdog CREATE/EDIT heading names the region - "WATCHDOG - wgc5:pia-aus_perth" - matching the EDIT modal and the log lines.
- CHG: `FLAG_SECURE` is now skipped for DEBUG builds so the app can be screenshotted on a device while testing. Release builds always set it; a test fails if that changes or if the release escape hatch (`allowScreenCaptureInRelease`) is left switched on.
- FIX: opening the keyboard on a form dialog left only its buttons on screen, over "BOTTOM OVERFLOWED BY 38 PIXELS". An `AlertDialog` puts its content in a `Flexible`, and inside the app chrome - where the Scaffold has already taken the keyboard's height off the body - that Flexible collapses to zero height and the fields spill out of the card. The SSH credentials, PIA credentials and ping-target dialogs are now built on the scrolling `Dialog` structure `SlotParamsEditor` uses (new `_FormDialog`).
- FIX: every dialog subtracted the keyboard's height TWICE, collapsing to a sliver. `AppChrome`'s `MediaQuery.removePadding` (added in 399 for the header) was handed the AppChrome context, which re-injected the outer MediaQuery below the Scaffold and undid the Scaffold's own `removeViewInsets`. It now takes the context from inside the body via a `Builder`.
- INF: the same dialog pumped on its own lays out correctly, which is why the first test written for this passed against the broken code. The regression tests now drive the whole app.
- FIX: the DEL PIA CERT credentials form opened empty. It now starts from the same defaults as the router screens (`kDefaultRouterIp` / `kDefaultSshUsername`, hoisted out of `router_slots_screen.dart` so the two cannot drift), with any session value taking precedence.
- FIX: on stock, a slot with a watchdog read back as unconfigured, greying out every button in both slot modals except CREATE / CREATE-EDIT - VIEW ROUTER WATCHDOG LOG included. `fetchSlots` takes the region name from `vpnc_clientlist` there, and the watchdog deploy path only ever wrote `wgcN_desc`. It now writes the profile row too, and marks it active when it enables the slot.
- FIX: `fetchSlots` on stock falls back to `wgcN_desc` when a slot has no `vpnc_clientlist` row, so a watchdog deployed by an earlier build stops showing as "<empty slot>" with every button greyed out. Enabling such a slot also repairs the row, description included.
- FIX: on stock the watchdog started and stopped tunnels the Merlin way (`service start_wgc` / `stop_wgc`), which does nothing there. `enableVpnSlot` / `disableVpnSlot` now use VPN Fusion - `nvram set vpnc_unit=<row>` then `service restart_vpnc` / `stop_vpnc` - the same calls MANAGE makes, via a now-public `RouterSlotService.runVpncService`.
- CHG: form dialogs take their height from the incoming constraints instead of capping it at the screen size, so the card fits the space the keyboard leaves and scrolls inside it.
- TST: +12 tests (424 -> 436), coverage 96.3%. One asserts the slot is enabled exactly once per deploy. The keyboard regression tests drive the whole app; a test fails if `FLAG_SECURE` stops covering release builds, and the stock fakes now read `vpnc_clientlist` back so a missing row cannot pass unnoticed.

2026-09-03 v0.8.30 build 400 - WIP stock support for Watchdog function

- CHG: watchdogs are no longer mutually exclusive. Deploying one used to tear down every other slot (`deactivateOtherSlots`, now gone); two can run side by side, capped by the same `vpnc_max_conn` gate MANAGE's ENABLE uses - CREATE/EDIT checks it before opening the dialog rather than after it is filled in.
- FIX: VIEW ROUTER WATCHDOG LOG was greyed out for a disabled watchdog. `/tmp/watchdog_wgcN.log` outlives the schedule, and the run that prompted the DISABLE is exactly the one worth reading, so it now needs the watchdog to be configured, not scheduled.
- CHG: an addKey failure in the router script logged only "curl addKey request failed". It now reports curl's exit code and message (35 TLS, 60 CA, 22 HTTP, 7 connect), which is what a stock router failing here needs to say.
- FIX: the router script rewrote `wgcN_enforce=1` on every successful re-negotiation, so a slot created with the kill switch OFF came back ON once the watchdog fired. It now reads the current value before the config write and puts it back; empty - which is always the case on stock, where there is no kill switch - means off.
- ADD: `⏸ WATCHDOG PAUSED` badge in the slot modal for a watchdog whose settings are on the router but whose schedule has been removed - muted grey, since nothing is running. Without it a paused watchdog looked like one that was never configured.
- ADD: watchdog ENABLE / DISABLE buttons, acting on the cron schedule rather than the tunnel. DISABLE drops the two `cru` entries and their boot persistence, keeping the settings, the script and the running VPN; ENABLE puts the schedule back at the interval stored in `wgcN_wd_check_interval`. ENABLE lights up only for a slot with settings and no schedule.
- FIX: DELETE unset the GLOBAL `cfg_pia_wg_user` / `cfg_pia_wg_password` unconditionally, which with two watchdogs would leave the survivor unable to authenticate with PIA. They are now cleared only by the last watchdog standing.
- CHG: the router's cached PIA CA moved from `/jffs/pia_ca.rsa.4096.crt` to `/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt` (`kPiaCaCertPath`, built from the renamed `kRouterAppDir`). The watchdog script now `mkdir -p`s that directory before downloading - it exists on stock, where the user installs jq into it, but not necessarily on Merlin. An old copy at the previous path is simply ignored.
- ADD: `DEL PIA CERT` button on the ABOUT screen, after CREATE GITHUB ISSUE. Confirms, then deletes the cached certificate over SSH, reporting whether one was there. With no router credentials in the session it asks for them inline (prefilled from whatever is there, and kept for later screens) rather than sending the user to a router screen.
- CHG: the clipboard is now emptied through `ClipboardManager.clearPrimaryClip()` on the host instead of by copying an empty string, so exiting the app and the 60s countdown no longer flash Android's "copied" popup at a user who copied nothing. New `clipboard_service.dart` + channel; API 24..27 has no `clearPrimaryClip()`, so MainActivity reports an error and Dart falls back to the old write.
- DOC: dropped the two README notes explaining the "copied" popup on exit and at timer expiry.
- FIX: clearing the DNS field left it blank on re-entry while a generate still quietly used the Quad9 defaults. The field is refilled with `kDefaultDns` on entry and again just before generating, so what it shows is what the config gets. It can still be cleared to retype.
- GUI: the generated config heading now names its region - "GENERATED CONFIG: pia-aus_melbourne" - matching the `pia-<region>.conf` that SHARE / SAVE writes. No region known, no suffix.
- TST: +36 tests (388 -> 424), coverage 96.2%. The deploy-payload ceiling moved 8700 -> 9000 bytes: the CA `mkdir` and the kill-switch read-back cost a line each. `pia_service_test` pins the service's own blank-DNS fallback to `kDefaultDns`, and a new test reads `MainActivity.kt` so the clipboard channel name and method cannot drift from Dart's.

2026-09-03 v0.8.29 build 399 - WIP stock support for Watchdog function

- ADD: an app-wide `AnnotatedRegion<SystemUiOverlayStyle>` (`kSystemOverlayStyle`) making both system bars transparent with light icons, re-applied every frame. `MaterialApp` already pushes light icons for a dark theme, but leaves an opaque black navigation bar that shows against `kBg` on Android 14 and below.
- ADD: main menu carries a "(?) How to use this app" link opening README section 5, "Using the app".
- CHG: dropped the main menu's "Select from the above and/or use the top left (menu icon) menu." hint; the SSH footnote and the help link below it are now centred.
- CHG: the header bar's `kSurface` now runs behind the status bar instead of leaving a `kBg` strip above it. The single `SafeArea` around the whole chrome became two: the header insets its own content, the navigator takes the bottom and the landscape cutouts.
- FIX: "Open source: licenses" screen, bleeding through the About screen between the app header and the "<-" back button at the top of the "Open source: licenses" screen.
- FIX: COPY BUILD INFO had the same gap from the other side - it bypassed the controller, so a countdown left running by a config copy still wiped the build info. It now goes through `copyToClipboard(armAutoClear: false)`, which needs `AboutScreen` to sit under a `SessionScope` (it always does in the app).
- FIX: copying a watchdog log armed the 60s clipboard auto-clear, so the conf screen counted down over it and then wiped it. `copyToClipboard` takes `armAutoClear`; a non-secret copy arms nothing and stands down any countdown left by an earlier config copy.
- FIX: the licences screen opened with a band of the About screen showing between the app header and its back arrow. `showDialog` wraps its child in a `SafeArea`, so the status bar inset still sitting in the navigator's `MediaQuery` was applied a second time below a header that had already cleared it; the navigator subtree now gets `MediaQuery.removePadding(removeTop: true)`.
- INF: Google Play's edge-to-edge notice needs no `enableEdgeToEdge()` call. `flutter.targetSdkVersion` is already 36, where Android forces edge-to-edge with no opt-out, and Flutter enables it on every Android version regardless. Nothing in the manifest or either `styles.xml` sets `statusBarColor`, `navigationBarColor` or the opt-out flag.
- TST: edge-to-edge tested on  on Android 15: gesture and 3-button navigation, landscape with a cutout, the keyboard over the SSH and PIA password fields, the drawer, and each dialog.
- TST: +12 tests (376 -> 388), coverage 96.1%. Simulated status/navigation bar insets pin the header background at y=0, its content and the drawer below the status bar, the HOME button above the navigation bar, and the licences dialog flush under the header.

2026-09-03 v0.8.28 build 398 - WIP stock support for Manage function only

- FIX: text copied from the app LOG screen pasted as one run-on line. The log is now one `Text.rich` with the line breaks inside it, not a widget per entry - `SelectionArea` joins separate widgets with no separator. Entry icons became `WidgetSpan`s and add nothing to the copy.
- GUI: ABOUT screen - removed the "Architecture" and "GitHub source code repository" links. Remaining order: ReadMe, Change log, Security policy, Privacy policy.
- GUI: enable selecting and copying to the system clipboard, text in the build info section of the ABOUT screen. The whole screen is now one `SelectionArea`, so a drag or long-press "Select all" spans the build info, the links and the licence text.
- CHG: ABOUT screen body widgets are plain `Text` rather than `SelectableText` - a `SelectableText` nested in a `SelectionArea` keeps its own private selection and the region skips it. The licences dialog gets its own `SelectionArea` - a region does not reach into a dialog's route.
- FIX: pasting a selection ran the build info rows together ("...releaseCommit hash: ..."). SelectionArea joins the text of separate widgets with no separator, so the rows are now one `Text.rich` with the line breaks inside it.
- ADD: CREATE GITHUB ISSUE button on the ABOUT screen, beside COPY BUILD INFO. Opens `/issues/new` with the title and every section of `bug_report.md` prefilled, the Environment block carrying the same text COPY BUILD INFO produces plus the detected router firmware. The two buttons share a `Wrap` so they fall to a second line on a narrow phone rather than overflowing.
- INF: GitHub applies an issue template OR a `body` parameter, never both, so `bugReportUrl` reproduces the template's headings. A test fails if `.github/ISSUE_TEMPLATE/bug_report.md` gains or renames one.
- DOC: `.github/ISSUE_TEMPLATE/feature_request.md` now names the app.
- DOC: rewrote `.github/ISSUE_TEMPLATE/bug_report.md`. Environment now asks for COPY BUILD INFO output plus router model and firmware version, matching what the app prefills; section headings unchanged, so the drift test still passes.
- ADD: COPY BUILD INFO button on the ABOUT screen, writing the same newline-separated text straight to the clipboard. Not via `SessionController.copyToClipboard`, which arms the 60s auto-clear meant for credentials.
- FIX: the "Open source: licenses" screen repeated packages - `accessibility` appeared 16 times. `LicenseRegistry` yields one entry per licence TEXT, each naming every package it covers, so rendering entries directly repeats a package once per distinct notice. New `groupLicensesByPackage` inverts that: one heading per package, sorted, with its notices underneath, matching Flutter's own licence page. Byte-identical texts collapse; ones differing only by year do not.
- FIX: licence notices are rendered paragraph by paragraph, keeping Flutter's indent and centred-header layout, instead of being flattened into one block.
- INF: expat's ASCII art still reads as run-on text. `LicenseEntryWithLineBreaks` joins hard line breaks with a space before any of our code sees it; Flutter's own licence page shows it identically.
- TST: +24 tests (352 -> 376), coverage 95.8%; `about_screen.dart` reaches 100%. The old licences-dialog test reimplemented the dialog inline and asserted only that an AppBar existed, so it could never have caught this; replaced with one that opens the real dialog against a seeded LicenseRegistry. Cover the link order, ARCHITECTURE.md being gone, the selection region, no nested `SelectableText`, the line breaks surviving a copy, and the COPY button.

2026-09-03 v0.8.27 build 397 - WIP stock support for Manage function only

- FIX: update "HOME" button grey -> teal in slot modal, and the screen HOME button in `app_scaffold.dart` (text and border) to match.
- FIX: DELETE left `wgcN_enable` behind. It was already being unset, but `stop_vpnc` returns as soon as `notify_rc` queues it, so the firmware rewrote the key afterwards. DELETE now waits for the slot to leave `wg show interfaces` first, bounded by `verifyPollInterval` / `verifyMaxAttempts`.
- FIX: DELETE now also unsets `vpncN_dut_disc` / `vpncN_sbstate_t` / `vpncN_state_t` (`kVpncRuntimeKeys`), stock only - Merlin does not use VPN Fusion.
- FIX: runtime keys are indexed by `vpnc_clientlist` field 7, not the slot number - wgc1 leaves `vpnc9_*`. New `vpncStateIndexForSlot`, read from the record before it is removed, falling back to `10 - slot`. The earlier slot-number reading came from wgc5, where both are 5.
- INF: one profile carries three indexes - slot number, clientlist row (`vpnc_unit`), and field 7. See ARCHITECTURE.md 4.2.
- INF: `vpncN_dns` also survives a stop; deliberately left out of the sweep.
- FIX: ACTIVE badge stayed on a slot after DISABLE until the modal was reopened. The modal did refresh; `disableSlot` just returned before the tunnel was down, so the refresh read a stale `wg show interfaces`. It now settles first, as DELETE does. `_revertEnable` too.
- CHG: DISABLE is greyed once a MANAGE slot is down; it stays live if the interface is up even when the enable flag reads 0, so a running tunnel is never stranded behind a greyed button.
- TST: +25 tests (327 -> 352), coverage 93.8%. Includes regressions for the reported cases: deleting wgc1 clears `vpnc9_*` not `vpnc1_*`, and the ACTIVE badge clears after DISABLE without reopening the modal.

2026-09-02 v0.8.26 build 396 - WIP stock support for Manage function only

- GUI: append all router and app log messages to include the description (region name), eg "Enabling wgc1..." -> "Enabling wgc1:pia-aus_melbourne...". New `slotLabel` / `fetchSlotLabel` in `router_slot_service.dart`; the description is read from `vpnc_clientlist` field 0 on stock and `wgcN_desc` on Merlin, cached per service instance so it costs one extra nvram read per action however many lines mention it. Best-effort: a failed lookup degrades to the bare `wgcN` rather than breaking the action or masking its error. Raw router output echoed into the log (`wg show interfaces: wgc1`) is left verbatim.
- GUI: alter EDIT dialogue box heading to show the slot:description eg wgc1:pia-aus_melbourne. The description is passed in from `fetchSlots` rather than read from the nvram map, because on stock a WebUI-created slot has no `wgcN_desc` mirror to read.
- GUI: preface slot descriptions with "pia-" to avoid confusion with other VPNs on the router. Applied by one helper (`slotDescFor`) at both write sites - MANAGE create and the watchdog dialog's region pick - so the two cannot disagree on naming. Idempotent, so re-saving an existing slot never yields "pia-pia-".
- FIX: that prefix would have broken the watchdog. `wgcN_desc` doubles as the PIA region id for the router script's `select(.id==$id)` lookup, so the script now derives `REGION="${DESC#pia-}"` and looks up on that, while its logs and its NVRAM write-back keep the full stored name. Tolerates descriptions written before the prefix existed. Payload grew 8376 -> 8496 bytes (Merlin), 8206 (stock).
- TST: +16 tests (311 -> 327), coverage 93.8%. Covers prefix add/strip round-tripping, label formatting and both firmware lookups, the best-effort fallback, the enable/disable/delete log lines, the EDIT heading, and the script's region strip.

2026-09-02 v0.8.25 build 395 - WIP stock support for Manage function only

- CHG: MANAGE slots now run concurrently. `_enableManage` no longer disables every other slot first - the "one active at a time" sweep is gone from both firmwares. Hardware step 7 (enable wgc5 while wgc1 is up) failed because that sweep was doing exactly what it was written to do; the sweep, not the badge, was the thing to change.
- ADD: concurrency gate. Stock caps simultaneous tunnels, so ENABLE counts the other interfaces that are up and refuses beyond the cap with a "VPN limit reached" dialog naming the ASUS limit and asking the user to disable a slot. No router writes happen when it refuses. Merlin has no cap key, so it is never gated.
- ADD: `RouterSlots.maxActiveSlots` (`int?`, null = unlimited) read from `nvram get vpnc_max_conn`, falling back to `kDefaultStockMaxActiveSlots` (2) when missing or unparseable - follows the router's own setting rather than hardcoding 2.
- TST: +8 tests (303 -> 311). Two tests that encoded the old one-active rule were inverted; new cases cover the cap at 2, refusal of the third, a non-default cap, the target slot not counting against itself, and Merlin being uncapped.
- DOC: `.claude/CONTEXT.md` 4.4 / 4.5 / 4.13 updated for concurrent slots and the cap.

2026-09-02 v0.8.24 build 394 - WIP stock support for Manage function only

- FIX: stock disable never stopped the tunnel. `disableSlot`, `_revertEnable` and `deleteSlot` issued `service restart_vpnc`, which clears `wgcN_enable` and `vpnc_clientlist` field 6 - so the WebUI reads "disconnected" - while leaving the interface up in `wg show interfaces`. Now `service stop_vpnc` per `ARCHITECTURE.md` 4.2.3. This is the root cause of "wgc5 shows ACTIVE with no tunnel running": the badge was telling the truth.
- FIX: `vpnc_unit` is the 0-based **row index** of the slot's record in `vpnc_clientlist`, not `5 - slot`. The WebUI can only create profiles in slot order 5,4,3,2,1, so on any list it built the two agree - which is how the wrong rule went unnoticed. The app lets the user pick any slot: with rows `[slot 5, slot 1]` the old rule asked for unit 4, a row that does not exist, and wgc1 never came up. Measured against the WebUI (rows `[slot5, slot1]` -> it writes `vpnc_unit=1`). New pure helper `vpncUnitForSlot`; all four stock service calls now route through `RouterSlotService._runVpncService`.
- FIX: `RouterSlots.activeSlot` (`int?`) is now `activeSlots` (`Set<int>`), built from `allMatches` rather than `firstMatch` of `wgc(\d)` in `wg show interfaces`. `firstMatch` badged whichever interface `wg` happened to print first - the "ACTIVE flag is incorrect (slot 3 not 1)" symptom. NB manage ENABLE still enforces one active slot at a time, so this is groundwork for the planned two-concurrent-slot support rather than a visible change today.
- FIX: manage ENABLE now sweeps other slots on `enabled || activeSlots.contains(n)`. The flag alone missed a tunnel that was still up while its flag already read 0.
- CHG: `enableSlot` commits NVRAM **before** the service call, matching the other three paths, so the service can never read a half-written slot.
- CHG: replaced the temporary `DEBUG:` log lines with permanent, readable ones naming the resolved unit and its row.
- ADD: enabling a slot with no `vpnc_clientlist` profile now fails with an actionable message instead of silently poking a non-existent unit; stopping such a slot is a no-op.
- TST: +17 tests (286 -> 303), all passing; coverage 93.7%. Covers both `stop_vpnc` vs `restart_vpnc`, the row-index derivation including the out-of-order case that reproduces this bug, multi-interface `activeSlots`, and the ENABLE sweep.
- DOC: `ARCHITECTURE.md` 4.2 / 4.2.2 / 4.2.3 corrected - `vpnc_unit` diagram, ordering constraints, and a warning that `restart_vpnc` does not stop a tunnel. `.claude/CONTEXT.md` 4.4 / 4.5 / 4.13 updated.

2026-09-02 v0.8.23 build 393 - WIP stock support for Manage function only

- FIX: updated enable and disable with correct stock calls, set `vpnc_unit` then calling `service restart_vpnc`.
- FIX: reverted 391 "enabling a slot in manage fails with attempt to start incorrect device number", restored `upsertVpncRecord` & `removeVpncRecord` (Claude).
- FIX: reverted 392 `router_slot_service_test.dart`: `upsert appends a new record when the slot has none` and `disableSlot clears the vpnc active flag`.
- CHG: set source in `vpnc_clientlist` to cfg-pia-wg, and password (field 5) to password
- FIX: sets `vpnc_clientlist` fields 10 (tunnel) and 11 (wan_idx) to 0 to match creating via WebUI.
- FIX: now removes `ep_addr_r` on slot delete.
- CHG: updated `scripts\read-vpnc_clientlist.sh` displayed field names.
- FIX: updated `test\router_slot_service_test.dart` to account for vpnc_client list fields being set (4 - password, 9 - tunnel, and 10 - wan_idx).
- CHG: updated ARCHITECTURE.md field schema & worked example to be zero based (to match code) and updated field contents to match code.
- ADD: slot enable DEBUG print showing `vpnc_unit` and `wg show interfaces`. Also added logrouter to match applog "Enabling wgc$slot...".
- REL: all tests passing.

2026-09-01 v0.8.22 build 392 - WIP stock support for Manage function only

- FIX: `router_slot_service_test.dart` - 2x vpnc_clientlist parsing, 1x stock slot mutations disableSlot; caused by buiuld 391 change to serialisation of vpnc_clientlist.
- DOC: extensive updates to `ARCHITECTURE.md` describing stock flows, commands, parameters, and settings.
- REL: all tests passing.

2026-08-31 v0.8.21 build 391 - WIP stock support for Manage function only

- TST: accepted 70% coverage on about_screen: 27 lines are in private implementation details `_LicensesDialog`, `_LicensesDialogState` build methods and `_launch()` method with URL launcher calls. Hard to test because GestureRecognizers inside TextSpans cannot be tapped in widget tests and URL launcher requires platform channel mocking that conflicts with tap simulation.
- CHG: altered verifyMaxAttempts to 5 (10s), was 30 (60s) then 15 (30)s; how many times to try to connect on this interface before pronouncing it dead.
- FIX: Updated `lib\router_slot_service.dart` as stock requires a different stop command to Merlin; updated in `disableSlot` and `_revertEnable` (now using `service stop_vpnc` instead of `service "stop_wgc $slot"; service restart_vpnrouting0` - retained Merlin behaviour).
- FIX: enabling a slot in manage fails with attempt to start incorrect device number.
- FIX: reverted `enableSlot` check `isStockFirmware` - to be retested.

2026-08-31 v0.8.20 build 390 - WIP stock support for Manage function only

- REL: updated shell scripts to LF from CRLF.
- REL: moved plans to own folder.
- CHG: added a conditional `sleep 10` to `S50downloadmaster.sh` - only runs once at boot. This fixes a blocking issue: something inside the boot process which I can't see expects a delay before the DM script completes, if there's no delay the boot process goes into a blocking state (but ONLY if a VPN is set to activate on boot). The original `S50` scripts had several `sleep` statements, so this is a matching hack, unclean and unwelcome, but this fixes it :/
- TST: update unit tests to match new template file and the changes to tunnel verification (from v0.8.18 build 388); all tests now passing.
- TST: updated tests to increase coverage of lib\screens\about_screen.dart.

2026-08-31 v0.8.19 build 389 - WIP stock support for Manage function only

- DOC: reorganised files, moved `.\scripts\S50*` to `.\.watchdog-implementation`
- REL: set LF as default with `.gitattributes`

2026-08-30 v0.8.18 build 388 - WIP stock support for Manage function only

- CHG: updated `scripts\read-vpnc_clientlist.sh` to read from nvram, field names shown too.
- CHG: updated comment in `scripts\S50downloadmaster.sh` header - this is only a test script, used to mimic Download Master running, setting its env variables, posting a log message every 5 minutes, and exiting with a 0. Router fails to load at boot (blocking behaviour) unless this script execs and exits with a 0.
- CHG: updated `enableSlot` in `router_slot_service.dart` - Merlin uses per vpn start commands `start_wgc 5; restart_vpnrouting`, WebUI uses whole of vpn restart with `service restart_vpnc`.
- CHG: `pingViaSlot` in `router_slot_service.dart` - stock ping does not honour pinging by interface name, must use IP address instead.
- INF: deleting a slot when on stock leaves behind **all** nvram keys, cfg-pia-wg removes them (as it should!).
- INF: `wgcN_desc` is set on stock as the watchdog needs somewhere easily accessible to get the slot name from, otherwise we'd need to implement parsing nvram's `vpnc_clientlist` in the router deployed script (which is getting close to the heredoc size limit).
- CHG: v0.1.1 `S50downloadmaster-TEMPLATE` & , removed `sleep 10` was nice to have correct router log timestamps but this script gets called often by the router and was unnecessarily slowing exec down.
- INF: if S50downloadmaster-TEMPLATE has 0 sleep, router blocked if a VPN is set active, try sleep 3, try 5, try 9 OK!. Polling `nvram get success_start_service=1` with a 1s interval fails as it is likely set after kernel init completes. The issue is that the script execs in the boot process and stalls other services if there is no delay after it runs.
- FIX: `scripts\S50downloadmaster.stock.sh` had mangled lines, re-extracted. Created `scripts\S50downloadmaster.stock-logging.sh` to log sleep functions in original script.
- ADD: added `scripts\S50asuslighttpd*` for testing: use that instead of DM?

2026-08-28 v0.8.17 build 387

- CHG: implemement stock support.
- CHG: updated get-pins.sh to point to new install location `/jffs/cfg-pia-wg`.
- CHG: on stock implement stock firmware slot naming with NVRAM variable `vpnc_clientlist`
- CHG: on stock add watchdog (wd) script and tie to `cru` entry, convert wd script to use `/jffs/bin/mailsend-go` and `/jffs/bin/jq` (store binaries on `opt`?).
- CHG: Convert to use `sendmail-go` (**no** mta on stock firmware)
- CHG: install replacement `S50downloadmaster.sh`.

2026-08-29 v0.8.16 build 386

- CHG: pre-implemement stock support.
- FIX: version and build number.

2026-08-29 v0.8.15 build 385

- CHG: updated `.claude\plan_add_stock_support.md` - added services-start workaround to prompt.
- CHG: removed DISABLED MERLIN placeholders from code.

2026-08-29 v0.8.14 build 384

- ADD: added `S50downloadmaster.stock.sh` to the repo, this is the original stock firmware script + added a "properly" formatted version, my eyes were bleeding re-reading the stock script!
- CHG: set `sleep 10` (seconds) in `S50downloadmaster.sh`, 60 caused issues with blocking as this script runs whenever the firewall is restarted, 0 also caused issues, and 10 is a compromise. Try 5, but might not work well on lower powered processors.
- DOC: added `.claude\plan_add_stock_support.md`.
- DOC: extensive updates to `ARCHITECTURE.md` to account for the nvram differences between Merlin and stock.
- DOC: updated `.claude\context.md`, a complete rewrite.
- DOC: updated `BUILDING.md` with name of new `scripts\pin-actions-latest.sh`.
- DOC: updates to README.md on enabling support for Stock firmware.
- GUI: changed wording of exit app confirmation screen to "Exit cfg-pia-wg?"
- NOTE: having more than two concurrent WireGuard slots is not supported on stock firmware but can be overridden by `nvram set vpnc_max_conn=X; nvram commit` - enabling 5 causes issues at boot (no VPNs connect).
- REL: added .gitignore exclusion for `./gradle` folder
- REL: ported `build.ps1` to `build.sh` (bash version wasn't in sync with the PowerShell version).

2026-08-28 v0.8.13 build 383

- DOC: generated new `CONTEXT.md`
- DOC: add .claude plans for context creation.
- ADD: `./scripts/get-latest-tag.sh` - gets the latest tag from GitHub, used to confirm latest tags for specific GitHub actions, e.g. kevin-david/promote-play-release

2026-08-19 v0.8.12 build 382

- CHG: optimised scripts/S50downloadmaster.sh, fixed DEBUG bug.
- REL: set workflow permissions, add 5m timeout, limit concurrency, and validate inputs in `promote.yml`

2026-08-19 v0.8.11 build 381

- Solved: (but not implemented) we now have a way to run the watchdog script on stock firmware.
- Solved: (but not implemented) we now have tools to replace `jq` and `sendmail` on stock firmware.
- Solved: (but not implemented) can now support all app functionality on stock firmware, including watchdogs, and email alerts.
- CHG: added `scripts\S50downloadmaster.sh` - example of how to add a cron job to run the watchdog script every 5 minutes, triggered by installing Download Master. This is a workaround for stock firmware which has no boot hook. Curently just prints a msg to the router log every 5 minutes.
- CHG: added `scripts\extract-with-context.ps1` to extract a section of a router log file with 1 lines before and after the match "cfg-pia-wg_cru", used for checking `S50downloadmaster` is running correctly.
- REL: material_color_utilities maintainers have fixed the issue with their package resolving to different versions on Windows/Linux.

2026-08-17 v0.8.10 build 380

- REL: updated pubspec.lock

2026-08-17 v0.8.09 build 379

- REL: updated pubspec.lock to reflect latest dependency versions

2026-08-17 v0.8.08 build 378

- REL: merged dev to main

2026-08-17 v0.8.07 build 377 (dev)

- REL: upgraded W11 from Flutter 3.44.8 to 3.47.0 (Dart 3.13.0 DevTools 2.60.0) with `flutter upgrade --force`
- REL: updated Flutter dependencies with `flutter pub upgrade --major-versions`
- REL: fix `pubspec.lock`
- REL: added `analysis_options.yaml` exclusions

2026-08-17 v0.8.06 build 376 (dev)

- REL: updated dependency dartssh2 3.0.2 (was 2.22.5).
- TST: fix 'RecordingSSHClient.close' ('void Function()') isn't a valid override of 'SSHClient.close'.
- CHG: fix double declaration of '_licencesRecognizer'.
- GUI: fix About open source license font size, format now consistent with other text in the screen.
- GUI: reformatted License screen to match the About screen, added scrollable text, and added a back button to return to the About screen.
- GUI: enable About screen text selection and copy to the clipboard (only one line at a time :/).

2026-08-16 v0.8.05 build 375 (dev)

- REL: codeql-action updated

2026-08-13 v0.8.04 build 374 (dev)

- CHG: refactor About screen.

2026-08-13 v0.8.03 build 373 (not released, exploring conversion to stock firmware target)

- CHG: Added "// DISABLED MERLIN" with comments to remove gating check for watchdog function on stock & use downloaded jq, not implemented, just a placeholder for now, still requires Merlin to function.
- CHG: Watchdog script now using `uname -n` instead of `hostname`, as `hostname` not in stock firmware.
- CHG: Added "Open source licences" display to ABOUT screen (was supposed to be in 372 but got missed, reimplemented in 373).

2026-08-10 v0.7.12 build 372

- CHG: CLOSED - not relicensing under GPLv2/MIT/Apache.
- DOC: CLOSED - no longer converting to html - Fix display of TIP, WARNING, and IMPORTANT in README.md after pandoc converts the file to HTML.
- DOC: minor edits to README, fixed URLs.
- GUI: Changed colour of region name from GREY to WHITE in WG Config and Watchdog modals.
- GUI: Hamburger menu item spacing normalised by reducing text (configuration -> config).
- REL: Activated Payment Account in **Google Play Console**.
- REL: Add sbom metadata and license info.
- REL: Added `scripts\get-bins.sh` script - downloads latest `jq` and `sendmail-go` binaries and installs to `/jffs/bin` (for testing with stock firmware).
- REL: Added `scripts\mailsend-go_test.sh` script - sends a test email alert using `sendmail-go` (for testing with stock firmware).
- REL: Added `THIRD-PARTY-NOTICES.md`.
- REL: Added dart_pubspec_licenses for SBOM attestation.
- REL: Converted `update-shas.ps1` to `./scripts/pin-actions-latest.ps1`, updated reference in `build.ps1`.
- TST: Reinstall stock ASUS router firmware - found replacements for `jq` and `sendmail` (`mailsend-go`), see see github.com/jqlang/jq/releases and github.com/muquit/mailsend-go.

2026-08-06 v0.7.11 build 371

- DOC: Add README note on tools to check your exit node
- DOC: Add README note that PIA sometimes takes regions offline for maintenance
- DOC: Added README note on "Watchdog shortcut"
- DOC: Fix broken centering of images and headings
- DOC: README format change to bullets
- DOC: Rewrote README.md section 1-3, added data from an indicative test comparing OpenVN throughput with WireGuard, added "why use wireguard" heading.
- REL: Built and tested OpenWRT under Hyper-V as a potential future port to support TP-Link routers (which have no user accessible SSH or dropbear), deferred.

2026-08-05 v0.7.10 build 370

- REL: sequenced backlog
- REL: renamed promote.yml job name from "Promote Release to Production" to "Promote release"

2026-08-05 v0.7.09 build 369

- REL: `promote.yml` now uses kevin-david/promote-play-release
- REL: Renamed update-shas.sh to ./scripts/pin-actions-latest.sh, updated reference in build.sh

2026-08-05 v0.7.08 build 368

- REL: `release.yml` now uses `pubspec.yaml` to parse current build and release.
- REL: `release.yaml`, discards AAB after sucessful upload to PS
- REL: Updated `./scripts/update-shas.sh` to stop using API returned "latest" SHA version (setup java's tag was touched today returning v1.4.5 instead of v5.7.0!), now pulls all versions, sorts, and picks highest release.
- REL: automated update of PS "what's new" with release notes -> "See github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md for changes since last release".

2026-08-05 v0.7.07 build 367

- REL: Updated `release.yal` push aab to PS via API.
- REL: Parse changelog entries by matching against the pushed tag, sort by type and insert as GH release text.
- REL: Added `promote.yml`, promotes PS aab from `internal` track to `production` (configurable under manual workflow run condition).
- TST: Added `test/release/release-notes.sh` to test new automated GH release notes, run from repo root.
- DOC: Split out backlog from `CHANGELOG.md` to `BACKLOG.md`.
- REL: Updated scripts/update-shas.sh
- REL: Added URL redirect from exponentiallydigital.com/cfg-pia-wg/changelog to github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md
- DOC: Added "GB" to "...8, 16, 32, 64 RAM configuations..." in BUILDING.md

2026-08-03 v0.7.06 build 366

- REL: Upgraded Flutter to 3.44.8 from 3.44.5 with `flutter upgrade --force`
- REL: Buildchain updated with `flutter pub upgrade --major-versions` & `.\android\gradlew -p android :dependencies :app:dependencies --write-locks`

2026-08-03 v0.7.05 build 365

- CHG: updated SHAs.
- CHG: updated `android\app\build.gradle.kts` to `base.archivesName.set("cfg_pia_wg") // this sets the name of the .AAB output file`.
- CHG: removed postscript from in app LICENSE display.
- DOC: updated CHANGELOG format.
- DOC: added how to upgrade dependency versions in BUILDING.md "4.1.2. When to regenerate lockfiles"
- REL: updated dependencies: `dartssh2` 2.22.5 & `jni` 1.0.3
- REL: tagged for release.

2026-08-03 v0.7.04 build 364

- REL: renamed app from *cfg_pia_wireguard* -> *cfg_pia_wg* (must use underscores, *cannot* use hyphens)
  1. update `pubspec.yaml` -> name: cfg_pia_wg
  2. search and replace in .dart files -> "import 'package:cfg_pia_wg/"
  3. update `android/settings.gradle.kts` -> rootProject.name = "cfg_pia_wg"
  4. check tests run and app compiles
  5. update `.github\workflows\release.yml` -> mv build/app/outputs/bundle/release/cfg_pia_wg-release.aab
  6. update `scripts\build.ps1`
     1. $TARGET_APK = "build/cfg_pia_wg-v${VERSION}_release.apk"
     2. $APK_RELEASE = "build/cfg_pia_wg-v${VERSION}_release.apk"
     3. $AAB_RELEASE = "build/app/outputs/bundle/release/cfg_pia_wg-release.aab"
  7. update `scripts\build.sh`
     1. TARGET_APK="build/cfg_pia_wg-v${VERSION}_release.apk"
     2. APK_RELEASE="build/cfg_pia_wg-v${VERSION}_release.apk"
     3. AAB_RELEASE="build/app/outputs/bundle/release/cfg_pia_wg-release.aab"
  8. save and exit VS Code, check tests run and app compiles with .\scripts\build all
  9. check app builds on GitHub dev branch
- FIX: can't paste into password fields, and can't "q"uit debug running in any screen showing password fields, also causing screen `D/EGL_emulation(24795): app_time_stats: avg=499.58ms min=498.77ms max=500.27ms count=3` count to increment; **revert build 363 changes** to `lib\widgets\common_fields.dart` and `lib\watchdog_dialog.dart`. Tested and now operating corectly: can "q"uit debugger, no incrementing count and can paste.

2026-08-03 v0.7.03 build 363

- FIX: Disabled ability to copy a password when the field is revealed. (didn't check could paste which is now broken when testing build 364, **reverted changes** in build 364)

2026-08-03 v0.7.02 build 362

- DOC: Update readme with the new name of command line tool - `cfg-pia-wg`.
- FIX: Updated `pubspec.yaml` - app name was showing incorrectly in launchers, updated from "Configure PIA WireGuard" to "cfg-pia-wg".
- DOC: Spellcheck ARCHITECTURE, CHANGELOG, and README.md.
- DOC: Replace ipv4.icanhazip.com in architecture.md, now using ping targets.
- DOC: Add to README.md that screenshots are disabled.
- DOC: Update security.md hotlink for reporting an issue, fix US spellings, remove Inactivity session self-destruct.
- CHG: Router IP address, 192.168.1.1 by default (matches SVG examples) and retained when entered.
- DOC: Add copies of all Claude plans to repo.
- GUI: Display the quad 9 default DNS addresses next to the Cloudflare ones in generate.
- GUI: suggested DNS address help text is truncated.
- BLD: Added warning to understand what the build optimisation script does **before** use.
- DOC: clarified README.md reason for `JFFS` partition enablement for storage of the watchdog script and settings between reboots.
- REL: Drop debug and release builds from Actions workflows, update README.md to account for this
- DOC: added TOC and section numbering to TESTING.md
- ARC: per TESTING.md, the architecture only deploys `/jffs/scripts/services-start` and `/jffs/scripts/watchdog_wgcN.sh` to NVRAM. Other files are written to volatile storage: `/tmp/watchdog_wgcN.log`, `/tmp/watchdog_last_ping_success_wgcN`, and `/tmp/watchdog_backoff_wgcN`. This reduces NVRAM write wear. The watchdog log is not persistent and is rotated at midnight to reduce volatile storage.
- DOC: added note to test that VPN is active after a firmware update (JFFS may be recreated by flashing process).
- GUI: enlarge WireGuard Configuration prompt for PIA credentials so that you can see the example DNS addresses, display is truncated.
- DOC: Update privacy.html to note that URLs in About screen go to locations on the Internet.
- INF: log message "kernel: jffs2: warning: (27325) jffs2_sum_write_data: Summary too big (-32 data, -877 pad) in eraseblock at 00280000", only seen once. No activity from app or script around that time. Checked deployed artifact sizes: 8,346 bytes (watchdog script), 205 bytes (services-start), 2,719 bytes (pia_ca.rsa.4096.crt), 181 bytes (cron entries) -> 11,451 bytes total used by app (typical). Web searches show that this can be ignored: created during NVRAM housekeeping. Likely occured as a result of extensive app testing.
- ARC: check all non critical data written to tmp not JFFS

2026-07-30 v0.7.01 build 361

- REL: Deploy to 'production' on Google Play Store
- CHG: add updated watchdog modal screenshot to Play Store
- REL: Create a GitHub actions release and verify build data in the new "About" screen.
- CHG: removed Watchdog DISABLE and ENABLE menu options + services, rolled capability to CREATE/EDIT.
- CHG: renamed watchdog "EDIT" button to "CREATE/EDIT".
- CHG: PIA username/password now cached while the app is running, no need to keep entering it (this matches the router username/pwd caching).
- CHG: updated text displayed when editing a watchdog slot.
- GUI: app name had reverted from yesterday's backed out changes -> cfg-pia-wg.
- DOC: updated app name in README.
- GUI: updated text when deleting a watchdog.
- CHG: updated watchdog modal screenshot in docs.
- DOC: updated Watchdog functionality changes.
- CHG: no message is written to the router log if you edit and save the watchdog's `cronIntervalMinutes` - the cron job is updated, cosmetic.
- DOC: updated `(FLAG_SECURE)` entry in README.
- DOC: updated Privacy Policy noting in-app links to the app's source code & documentation.

2026-07-29 v0.6.28 build 358

- REL: release.yaml already calls quality_and_security.yml directly via workflow_call whenever a tag is pushed, quality_and_security.yml should not listen for tag pushes directly.

2026-07-29 v0.6.27 build 357, sync build

- REL: current GitHub pipeline runs on commit and tag. Reorganise to run quality_and_security.yml on every commit, and on release, run quality_and_security.yml then release.yaml using shared build artifacts so we don't rebuild the app multiple times in the same workflow run.

2026-07-29 v0.6.26 build 356, sync build

- FIX: build artifact naming in release.yml

2026-07-29 v0.6.25 build 355

- FIX: updated quality_and_security.yml to grant permissions required by the reusable workflow
- FIX: prevented release.yml from skipping checks on manual runs.

2026-07-28 v0.6.24 build 354 (pre–Google Play Store release)

- FIX: every url_launcher link in the app was dead (About screen links, and the header bar's "Exponentially Digital" and version/GitHub links, which last worked in v0.6.21) with `PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.canLaunchUrl")`. Not a url_launcher fault: `android/app/gradle.lockfile` pinned `kotlinx-coroutines-android` to 1.8.1 on the runtime classpaths, but share_plus 13.3.0 declares 1.11.0 and compiles `Dispatchers.IO.limitedParallelism(1)` against it, emitting a call to the `limitedParallelism$default(..., int, String, ...)` bridge whose `name` parameter only exists in coroutines 1.10+. STRICT dependency locking silently downgraded the runtime dependency, so `SharePlusPlugin.onAttachedToEngine` threw `NoSuchMethodError` on startup. Because that is an `Error` and not an `Exception`, `GeneratedPluginRegistrant.registerWith`'s per-plugin `catch (Exception e)` did not catch it: registration aborted at plugin 4 of 5 and `url_launcher_android` was never registered. `package_info_plus` is plugin 3 and registered before the throw, which is why the header still showed a version string and made this look link-specific rather than global. SHARE was broken by the same fault. Fixed by regenerating the lockfiles (`gradlew -p android :dependencies :app:dependencies --write-locks`), which moves the four coroutines artifacts to 1.11.0 on the runtime/lint classpaths - a 4-line lockfile change, nothing else altered. Verified on-device: plugin registration is clean and all eight links open in the browser.
- CHG: rebranded to "cfg-pia-wg": updated all text, icons, and diagrams.
- ADD: added to repo a local copy of the .\play-store\privacy.html file.
- ADD: "About" menu option to the hamburger menu, directly below "View app log". New `AppDestination.about` + `lib/screens/about_screen.dart`, so the drawer tile, route name, selected-state highlight and no-op-on-current behaviour all come from the existing generated-tile machinery. Shows build provenance, tappable links to the repo/README/changelog/architecture/security/privacy documents, and the full GPL v3 text. The security policy link uses `/blob/main/SECURITY.md` - the bare `/SECURITY.md` form 404s.
- ADD: `android/app/build.gradle.kts` now enables `buildFeatures { buildConfig = true }` (AGP 8+ defaults it off and AGP 9 dropped the `android.defaults.buildfeatures.buildconfig` escape hatch, so `BuildConfig` was not being generated at all) and injects `BUILD_TIMESTAMP`, `GIT_COMMIT_HASH`, `GIT_COMMIT_DATE`, `GIT_BRANCH`, `CI_RUNNER_ID`, `COMPILE_SDK` and `KOTLIN_VERSION`. git runs via `providers.exec` (a raw `ProcessBuilder` is a configuration-cache violation) as `git -C <android/>`, and every failure path - git off `PATH`, no `.git` in a source tarball - degrades to "unknown" rather than failing the build. `gitBranch` prefers `GITHUB_REF_NAME` and rejects a literal "HEAD" from the git fallback, because a tag push leaves actions/checkout in detached HEAD where `rev-parse --abbrev-ref` returns "HEAD" and never the tag. `javaStringLiteral()` escapes each value: `buildConfigField` emits its third argument verbatim into `BuildConfig.java`, so a branch named `foo"bar` would otherwise produce uncompilable generated Java. `kotlinVersion` comes from `getKotlinPluginVersion()`; the Kotlin plugin is deliberately *not* added to the app's `plugins {}` block, as Flutter's Gradle plugin already applies it and declaring it again makes Flutter log an AGP-9 migration warning at error level on every build. No new dependencies, so the STRICT lockfiles are untouched.
- ADD: `MainActivity.kt` gained the app's first `MethodChannel` (`...:/build_info` -> `getBuildInfo`), returning a flat `Map<String, String>` of the `BuildConfig` values plus the device-side facts: install source (`getInstallSourceInfo` on API 30+, legacy `getInstallerPackageName` below, mapped to friendly labels), `Build.SUPPORTED_ABIS[0]`, OS version + API level, and versionName/versionCode from `PackageManager`. Deprecation suppressions are scoped to one-line helpers rather than blanketing callers. `super.configureFlutterEngine` is called first - that is where the generated plugin registrant runs, and skipping it silently breaks path_provider, share_plus, url_launcher and package_info_plus.
- ADD: `lib/build_info_service.dart`. `loadBuildInfo` catches `MissingPluginException` and `PlatformException` and returns `BuildInfo.unknown()`; this is load-bearing rather than defensive, since `flutter test` registers no native side and every full-app widget test takes that path. `BuildInfo.fromMap` defaults each missing key individually so a partial reply degrades one row at a time.
- ADD: `lib/license_text.dart` - `./LICENSE` verbatim as a raw-string constant, generated at development time rather than loaded at runtime or registered as a pubspec asset, so the About screen has no I/O path and cannot display a licence differing from the repo's. Regenerate it if `./LICENSE` ever changes.
- CHG: accepted build-speed trade-off for exact provenance: `BUILD_TIMESTAMP` is wall-clock at Gradle configuration time, so `GenerateBuildConfig` is never up to date and every build recompiles and repackages the app module (with `org.gradle.caching=true` this also leaves single-use cache entries). `GIT_COMMIT_DATE` is delivered alongside it as a reproducible cross-check. Note that if `org.gradle.configuration-cache` is ever enabled the timestamp would be frozen into the cache entry and silently go stale.
- TST: `test/screens/about_screen_test.dart` covers the populated screen, all six links, the embedded licence, and three degradation paths (`MissingPluginException`, `PlatformException`, partial host reply). `main_menu_screen_test.dart` gained a case asserting the About tile sits below the log tile and that the screen renders with no channel mocked at all.
- FIX: Restructured logic in calls to `startWatchdog` from `saveWatchdogConfig` & `deployWatchdogScripts` - cosmetic, causes double log entry.
- CHG: Updated Play Store screenshots & short/long description
- FIX: PIA username and password are not cached in device RAM if entered via lib\watchdog_dialog.dart.
- UI: In generate `PIA WireGuard config` modal, add text to say which region the currently displayed config is for, add this next to the GENERATED CONFIG header
- ADD: When editing a watchdog, display what the current region is in the modal, and allow changing this via the region selection screen, can then drop call to region selection which fires on save.
- BUG: from a blank slate when creating a watchdog from scratch, with no underlying VPN created on the slot, causes NVRAM to not be correctly updated and slot status to display incorrectly.
- BUG: unable to reproduce (setting to done): if router stops accepting commands (hung web UI, ASUS Android app, and SSH) but is still routing, and an SSH socket times out creating a watchdog, you are incorrectly told that the slot had been created. Occurred once when router web GUI, ASUS app, and SSH access failed, a router process had died but there was no way to access and check. Probably a router firmware bug, power cycling fixed it, nothing useful in router log though. Retained for completeness.
- ADD: TOCs to ARCHITECTURE, BUILDING, CHANGELOG, CONTRIBUTING, README, SECURITY, and TESTING.
- DOC: Added **About** menu screen to README.
- REL: safety commit save ahead of testing GitHub build with new pipelines

2026-07-28 v0.6.23 build 353

- FIX: update-shas.sh/ps1 were writing two spaces after the SHA e.g. "...890  # v1.01"
- CHG: updated SHAs
- FIX: update all minor version dependencies & release publock on jini 1.0.0; test if 1.0.2 fixes the Gradle bug exposed by 1.0.1 - OK
- FIX: when saving a new watchdog, scan for other watchdogs and delete them before the new watchdog is activated: e.g. deploying a watchdog to slot 5 does not disable an active VPN on slot 1, so you end up with two VPNs running at the same time - apply same logic from 'Manage Router PIA WG Cfg' to disable any other active VPN slots. `RouterWatchdog.deactivateOtherSlots` now sweeps wgc1-5 on both `saveWatchdogConfig` and `startWatchdog`, stopping any other watchdog and disabling its interface. The sweep runs *before* the new config's NVRAM write because `stopWatchdog` unsets the global `cfg-pia-wg_*` credentials.
- ADD: `RouterWatchdog.disableVpnSlot`, mirroring `RouterSlotService.disableSlot` - clears `wgcN_enable`, commits, then stops the interface.
- FIX: `stopWatchdog` issued `service "stop_wgc wgcN"` where the service expects the bare slot index (`stop_wgc N`, per ARCHITECTURE.md), so watchdog DISABLE never actually brought the tunnel down and left an unsupervised VPN running. It now delegates to `disableVpnSlot`, which also clears `wgcN_enable` so the slot cannot return on the next `start_vpnrouting0` or reboot.
- FIX: `probeLatency reports failed probe with progress callback` failed intermittently in the full suite (errno 10048). `probeLatency` dialled a hard-coded port 1337, so faking a responding server meant binding that one global port; three test files need it and `flutter test` runs test files in parallel workers, so they collided.
- ADD: `PiaService.probePort` (default `PiaService.defaultProbePort` = 1337), injectable via `PiaService({probePort})`. Tests now bind an ephemeral port (0) and pass it back in, removing the contention at source rather than serialising the binds behind retry loops. pia_service_test.dart and standalone_config_screen_test.dart were converted and their retry loops deleted; unit/main_unit_test.dart still binds the default port because it drives the real `PiaWgApp` shell, which constructs `StandaloneConfigScreen` itself (app_drawer.dart) and so offers no injection seam - harmless, as it is now the only file binding it.

2026-07-28 v0.6.22 build 352

- FIX: sequenced release.yaml to only run after quality_and_security.yaml successfully completes
- CHG: re-enabled FLAG_SECURE to disable in-app screenshots, hides screen display from task switcher (was disabled during closed testing to allow screenshots), set in `android\app\src\main\kotlin\com\exponentiallydigital\pia_wireguard_cfga\MainActivity.kt`.
- DOC: updated Play Store descriptions
- TST: end-to-end manual retest of the entire app

2026-07-27 v0.6.21 build 351

- Google Play Store release candidate (not deployed)
- ADD: update-shas.ps1 now uses a 24-hour cache
- ADD: update-shas.ps1 added `-ForceRefresh` switch
- FIX: update-shas.ps1 trailing comments

2026-07-20 v0.6.20 build 350

- ADD: added updating of dependencies to build.ps1/.sh (NB major versions are **not** upgraded automatically)
- ADD: allow copy/paste from router log
- ADD: COPY button to the router log display screen
- MOD: optimised, and reduced size of kWatchdogScriptTemplate by 123 chars
- ADD: watchdog shell script now checks for Internet access before attempting repair
- CHG: router watchdog shell script does not ping secondary target if primary is successful
- FIX: updating the watchdog timeout in the UI did not update a pre-existing cron schedule
- FIX: if you created a VPN via the watchdog interface, it was showing as enabled when it was not. Removed reminder to set it to active; when saving, the watchdog script is deployed and runs immediately.

2026-07-20 v0.6.19 build 349

- updated GitHub action SHAs to latest versions
- updated tests test\screens\standalone_config_screen_test.dart and test\screens\standalone_config_screen_test.dart to run in parallel
- added update-shas.sh, a direct conversion of the update-shas.ps1 script
- build.ps1/.sh scripts now run update-shas.ps1/.sh ahead of building to ensure these are always up-to-date

2026-07-06 v0.6.18 build 348

- set minSdk = 24 (Android 24, Android 7.0 Nougat) in android\app\build.gradle.kts
- source code grammar and spelling (non-functional changes)
- reverted internal name space to "com.exponentiallydigital.pia_wireguard_cfga" in MainActivity.kt, proguard-rules.pro, build.gradle.kts, and settings.gradle.kts. This was part of the rename several commits ago but I found that this would have forced a complete restart of the Google Play closed test.
- updated actions/setup-java SHA to latest version
- updated dependency locks with "cd android; ./gradlew dependencies --write-locks"
- updated BUILDING.md to note how to upgrade flutter packages to their latest compatible build

2026-07-06 v0.6.17 build 347

- temporary change to allow screenshots to be taken (to allow Android testers to prove that they have the app installed and are testing it - "SwapTest - 12 Testers")

2026-06-29 version 0.6.16+346

- updated GitHub actions dependency versions

2026-06-29 version 0.6.15+345

- modified readme formatting, added build chain details, normalised brand name convention

2026-06-25 version: 0.6.14 build 344

- after auditing the router's file system, it was found that `/usr/sbin/curl` writes a command line history to `/jffs/curllst` with file permissions 666 (!), this log file is also rotated and my exist as `/jffs/curllst.1`. There appears to be no way to stop this file being generated/used, so the bash script empties the file after every `curl` execution ;)

2026-06-25 version: 0.6.13 build 343

- added indicator to slot display if email alerting is enabled
- line-by-line port of `build.sh` to `build.ps1`

2026-06-25 version: 0.6.12 build 342

- added patreon/paypal donation buttons

2026-06-25 version: 0.6.11 build 340

- no functional changes
- modified modals to use 100% of vertical screen (was pixel based)
- updated human visible play store app name from `pia_wireguard_cfga` to `cfg_pia_wireguard`, internal name retained (v painful if change in G Store)
- confirmed private app datastore contains 0 sensitive data, examined output from

```bash
`C:\Users\andrew\AppData\Local\Android\sdk\platform-tools\adb.exe exec-out "run-as com.exponentiallydigital.pia_wireguard_cfga tar c ." > C:\Users\andrew\Desktop\app_dump.tar`
```

2026-06-25 version: 0.6.10 build 340

- no functional changes
- changed internal build name back to "com.exponentiallydigital.pia_wireguard_cfga" from "com.exponentiallydigital.cfg-pia-wg". Google does not allow a project name change, doing so would require an entirely new app store listing :/
- added 512x512 icon for Play Store

2026-06-26 version: 0.6.09 build 339

- released: complete UI overhaul + self-healing watchdog function
- fix deployment yamls

2026-06-26 version: 0.6.08 build 338

- merge development to main

2026-06-26 version: 0.6.07 build 336

- FIX disposed-controller crash when the app prompts for PIA username/password and DNS during router slot creation (only occurs if PIA username/pwd not cached in RAM).

2026-06-25 version: 0.6.06 build 334

- updated build SHAs
- added field descriptions to kSlotNvramKeys
- extensive updates to README, SECURITY, and TESTING documentation, added new app screenshots
- renamed nvram variable from `pia_wg_cfga` to `cfg-pia-wg`
- FIX deleting a managed slot does not unset: `wgcN_wd_primary_ip` and `wgcN_wd_secondary_ip`

2026-06-25 version: 0.6.05 build 334

- Manage router
  - Only one interface active at a time — ENABLE first disables any other active interface (and its watchdog); ENABLE is greyed when the selected slot is already enabled.
  - DISABLE and DELETE also stop the slot's watchdog; DELETE's confirmation shows the slot description.
  - CREATE now writes wgcN_enforce=0 (kill switch off).
  - CREATE / ENABLE / DISABLE / DELETE and the ENABLE ping-check are logged to the router syslog (cfg-pia-wg), not just the app log.
- Watchdog management
  - ENABLE and DELETE are greyed for an empty slot; only one watchdog active at a time (ENABLE stops any other active watchdog first).
  - DELETE confirmation reads exactly "This will also delete and disable the underlying region."
  - Configuring a watchdog on an empty slot pops a "remember to ENABLE" reminder (matching CREATE).
  - deployWatchdogScripts logs the region too (e.g. "Deployed watchdog script for wgc5, aus_melbourne"). EDIT prefills PIA credentials (already wired; verified).
- Slot editor / modal
  - The read-only row now shows "Enabled YES/NO". The modal's HOME button returns to the main menu (not the router login).
- UI / shell
  - The 10-minute inactivity timer, countdown, and global activity listener are removed entirely (clipboard 60-second auto-clear kept).
  - Router screens default to 192.168.0.254 / admin; once connected, re-entering a router screen auto-reconnects and opens its modal.
  - Every exit path (back key, menu "Exit app", drawer "Exit app") now confirms before wiping + exiting.
  - Main menu shows a green hint with an inline hamburger icon; the drawer "HOME" entry is grey and navigates to the menu; the active destination shows green (fixed: the tiles' explicit text colour had been overriding selectedColor, and the route observer now ignores dialog routes so the active item stays green while a modal is open).

2026-06-25 version: 0.6.04

- change from `pia-wg-cfga` to `cfg-pia-wg` as router log prefix
- renamed `pia_wireguard_cfga` to `cfg-pia-wg` in all build scripts, tests, and settings files
- add `flutter analyse` to build scripts, actions, and docs
- updated quality_and_security.yml to use java 21 (was 17 in some places), this matches the local build envs. V25 breaks local dev tool chain.
- added version number to release assets created by `build.ps1` and `build.sh` (matches GitHub Actions release script)
- updated slot edit text
- renamed menu entry from "VPN watchdog management" -> "Watchdog WireGuard management"
- watchdog shell script, changed log message from "Checking wgc1 connectivity" to "Checking wgc1 aus_melbourne connectivity"
- updated text for overwriting watchdog config with a different region
- dropped "standalone" from menu item name
- renamed modal screens from WireGuard/watchdog "slots" to "configuration"
- hamburger menu "Close app" -> "Exit app"
- slot modal "(Empty Slot)" -> "<\empty slot>"
- change "CLOSE" button on each of the 4 option screens -> "HOME"

2026-06-24 version: 0.6.03

- no code changes, updated extensive to do list

2026-06-23 version: 0.6.02

- no code changes, extensive to do list generated
- added actual prompt used to ui_reorganisation.md
- rebuilt icons
- changed build.sh to use bash shell (doesn't execute under WSL, check why!)

2026-06-23 version: 0.6.01

- FIX local env issues (commit not sent correctly, VSC issue)

2026-06-22 version: 0.6.00

- implemented `.claude\ui_reorganisation.md` to fundamentally rebuild the user interface.

2026-06-23 version: 0.5.14

- further updated `.claude\ui_reorganisation.md`, this fundamentally rebuilds the user interface.

2026-06-22 version: 0.5.13

- significantly updated `.claude\ui_reorganisation.md`

2026-06-22 version: 0.5.12

- removed unused variable in test\router_push_sheet_test.dart
- updated assets to match rebranding

2026-06-22 version: 0.5.11

- Rebranded and renamed from `pia-wireguard-cfga` "PIA WireGuard Config" to `cfg-pia-wg` "Configure PIA WireGuard"

2026-06-22 version: 0.5.10

- moved `watchdog_wgc$slot.log`, `watchdog_last_ping_success_wgc$slot` and `watchdog_backoff_wgc$slot` files from `/jffs` to `/tmp` to reduce NVRAM writes
- renamed email alerts from "PIA Watchdog Alert" to "cfg-pia-wg"
- fix script deployment (heredoc limit reached) by optimising and reducing package size
- updated alert email subject
- updated watchdog connectivity testing logging text
- updated tests to match new `watchdog_wgc__SLOT__.sh`
- fixed test not returning `Successfully retrieved router config.`
- added WIP `ui_reorganisation.md`

2026-06-21 version: 0.5.09

- fix removed unused `commitCount` test variable
- fix test `Step 1: pushToRouter Error Recovery experiences a CRITICAL Failure`, `FakeSSHClient` wasn't reaching the catch block
- fix test `Step 1: pushToRouter triggers Error Recovery and restores backups successfully` self-resetting flag that crashes the first command of the write phase to trigger the recovery loop, then immediately disables itself so the subsequent rollback actions can succeed

2026-06-21 version: 0.5.08

- ??? pushing to wgc5 (perth) did not disable wgc1 (Melb), due to a change I made...where was that!
- found it, `stopWatchdog`, in `lib\router_watchdog.dart`: had commented out `await _run('service "stop_wgc wgc$slot"; service start_vpnrouting0');` now re-enabled that line (and it works again, no more multiple VPNs running concurrently!)

> [!NOTE]
> If slot 1 was active and a watchdog was deployed to it, it remained active even if slot 5 was made active and a watchdog deployed to that slot, so we end up with multiple watchdogs, added to the `to do` list to note in the docs that the watchdog is only for one slot at a time. Who runs multiple VPNs on different slots? Maybe someone does, just like having more than one WG VPN active concurrently. Ping me if this is an issue!

- fix new sendmail commands causing errors: moved `-CAfile` and `-verify_return_error` back inside the OpenSSL quoted string, replaced `timeout 10 openssl` with `openssl -timeout 10`

2026-06-20 version: 0.5.07

- fix CA cert check (wrong variable tested)
- fixed unit tests (testing on prior version's value)
- removed unnecessary `nvram commit` x2
- restart interface to flush routing on watchdog removal
- on failed write of current slot restart only that slot, not a full WG restart
- added warning to `scripts\build-optimisation.sh` header (caveat emptor)
- fix services-start permission is 777 on uninstall
- normalised router send email command: re-sequenced, added -verify_return_error, added space after "H", removed -amLOGIN, removed test from messageID
- added 3-layer mail send failure: sendmail exit code, sendmail's stderr, and any detail from the underlying openssl handshake
- added same error checking to test email send function invoked by the UI through `buildSendmailCommand` and `testEmail`
- updated test email header and body generation per RFC-822, now matches shell script
- renamed "DEPLOY WATCHDOG" to "WATCHDOG CONFIG" because you can set/unset from there not just deploy
- fixed tests to match current code

> [!NOTE]
>
> - **ADD** removal of `wgcN_ep_addr_r` & `wgcN_rrip` (explicit delete in `_pushToRouter` at service stop)
> - Potential Merlin bug discovered: these are left set to prior values if the slot is set to `default` in the GUI

2026-06-20 version: 0.5.06

- extra router logging added to `` script
- cache PIA CACERT
- added `--fail` to curl
- added check that CA cert is valid
- optimised `/jffs/scripts/watchdog_wgcN.sh` `sed` and `jq` calls
- replace multiple `curl` commands with `$CURL` to assist with code maintenance

2026-06-20 version: 0.5.05

- fix, added encoding of PUB and PVT keys with `/jffs/scripts/watchdog_wgcN.sh` script curl
- fix transient error, added sleep to final interface up commands in `/jffs/scripts/watchdog_wgcN.sh` script
- fix transient error, removed unnecessary `wg setconf "$IFACE" "$TMPCONF"` from `/jffs/scripts/watchdog_wgcN.sh`

2026-06-20 version: 0.5.04

- change "WATCHDOG.." to "DEPLOY WATCHDOG"
- NVRAM now cleared when watchdog disabled (wgcN + PIA creds)
- `command` doesn't exist on busybox, replaced with `which`

2026-06-20 version: 0.5.03

- added message ID to email template
- rename "clear creds & cfg" rendering off screen -> "CLEAR ALL", updated tests & projects docs to match
- fix local IP address (added `--interface $wgc$slot`)

2026-06-20 version: 0.5.02

- added TESTING.md, covers manual email testing

2026-06-20 version: 0.5.01

- implemented a feature to automatically maintain a persistent WireGuard VPN on the router

2026-06-19 version: 0.5.00

- refined watchdog.md
- version bump ahead of watchdog implementation

2026-06-19 version: 0.4.35

- updated watchdog.md

2026-06-19 version: 0.4.35+325

- fix typo in lib\router_push.dart array for the 'psk'
- formatting of license header in dart modules
- updated context.md
- added watchdog.md, requirements and spec for setting up the new watchdog feature

2026-06-16 version: 0.4.34+324

- employed AI MOE to update scripts/build-optimisation.sh (which was a terrible outcome, build performance dropped!)
- finally started using a develop branch (about time!) :)

2026-06-15 version: 0.4.34+324

- FIX environment error in scripts/build-optimisation.sh, wrong units used, attempted a 2PB RAM allocation (!)

2026-06-15 version: 0.4.33+323

- updates to setting up an automated script for the build environment

2026-06-15 version: 0.4.32+32

- updates to setting up an automated script for the build environment

2026-06-14 v0.4.32 build 322

- split out build info to separate file
- moved additional scripts to own folder
- added build environment optimisation script
- added play store folder to version track submitted description
- moved documentation sections from README to ARCHITECTURE.md, BUILDING.md, and CHANGELOG.md

2026-06-13 to 2026-05-31

- add how to install `fcr` for HTML coverage report
- feature/router-push merge to main & release
- add README badge(s) for automated pipeline security & quality tests
- refactored \_pushToRouter(), FIX WAN IP address determination
- fix table display on README
- add push to router steps & screenshots
- added extensive build environment setup and config notes to README
- added flow chart to readme
- updated permission use (clarified)
- add feature "push cfg to router"
- increase automated tests to >90% of the codebase
- added timestamps to LOG
- update java version to 21(17)in release and code scan yaml
- update screenshots for phone, 7" and 10" tablets showing clipboard clearing
- rebuild release output files (drop zip, include 3 versions)
- include software BOM (bill of materials) in release artifacts
- add how to privately report a security vulnerability (enabled in GitHub)
- create SECURITY.md
- enable dependabot
- implement local PS1 app to replace tags with SHAs
- add SBOM as a release artifact (Syft)
- fixup html intermediary file name (caused resultant doc title issue)
- renamed `$ADDON` to `$RELEASE` in release.yaml (was carried over from WoW addon packaging)
- split release.yaml into code scan and actual release
- automated security/quality analysis: Flutter analyse, SonarCube, Google OSV dependency scan, Mobile security scanning (MobSF), Dependabot dependency management, and CodeQL analysis.
- clear the clipboard after 60 seconds if conf copied there
- review Actions CI pipeline - add Flutter analyse, rename pipeline
