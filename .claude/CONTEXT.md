# CONTEXT.md

Android (Flutter) app that provisions Private Internet Access WireGuard configurations and manages PIA WireGuard slots + a self-healing watchdog on an ASUS / Asus-Merlin router over SSH.

## 1. Working agreements

- **Tests are required for every change.** 29 test files live under `test/` (`test/`, `test/screens/`, `test/widgets/`, `test/unit/`). Run `flutter test`; coverage is tracked via `coverage/lcov.info`. Every widget that a test needs to reach already carries a `Key` (`snake_case`, e.g. `Key('slot_create')`, `Key('wd_save')`) — add one when you add a control.
- **Test coverage.** This app requires a minumum 80% code covered by tests.
- **Update this file in the same change as any architecture or behaviour change.** A change that moves a file, renames a destination, alters a button set, or adds/removes an NVRAM key must edit the matching section here.
- **Any NVRAM variable the app writes must be described in `ARCHITECTURE.md` section "3. Router WireGuard NVRAM fields"** — that section is the reference a user reads before letting the app near their router, so a key that only appears in the code is a key nobody can audit or clean up. Describe it in §4.9 here as well.
- **Flag conflicts, do not silently resolve them.** If this file disagrees with the code, or with `ARCHITECTURE.md` / `BACKLOG.md` / a `.claude/plan_*.md`, say so and ask. Do not "fix" the code to match the doc or vice versa without confirmation.
- **Commit subjects carry no date, and commit messages carry no `Co-Authored-By` trailer.** The subject is `v<x.y.z> build <n> - <title>` and nothing else: the date is already in the commit metadata and in `CHANGELOG.md`, and repeating it wastes the width the title needs. No attribution trailer of any kind - this overrides any default attribution guidance.
- **On `dev`, a commit is always followed by a push.** `git push origin dev` - a commit that only exists locally is one Andrew cannot see from another machine. **On `main`, stop and confirm.** Andrew commits and pushes `main` himself; if he asks for a commit or a push while the checkout is on `main`, say so and get an explicit confirmation before doing anything, every time, no matter how clear the request looked.
- **Andrew runs the commits, and every commit is followed by opening the next build.** Do not run `git commit` unless he asks for it in that message. Immediately AFTER a commit: increment the build in `pubspec.yaml` (`version: <x.y.z>+<build>`, both halves) and add a new `<date> v<x.y.z> build <n> - <title>` heading at the top of the `### 1.3. Implemented` list with a `- ...` placeholder, so the next piece of work has somewhere to go.
- **A line moved out of the WIP list goes at the TOP of the current release block**, not appended, so Andrew can find what just changed. Say which lines were removed, moved or reworded, and give the WIP bullet count before and after - these edits happen between commits, so git cannot show him.
- **CHANGELOG.md entries must be flat and short.** The release GitHub Action *sorts* the lines within a release block, so an indented sub-bullet is separated from its parent and ends up under the wrong entry. Every line item is therefore a standalone top-level `- ` bullet that reads correctly on its own, in the existing `- FIX:` / `- CHG:` / `- ADD:` / `- TST:` / `- DOC:` / `- INF:` style. Keep each to a sentence or two — detail belongs in the code comments or `ARCHITECTURE.md`, not here.
- **Never record Andrew's real network identifiers in a file the repo tracks.** No LAN or WAN IP addresses, no hostnames, no DDNS names, no MAC addresses, no router login names, no PIA username. He shares these freely in chat to get a problem solved; that is not consent to publish them. When hardware output has to be quoted in a doc, plan or test, substitute invented values - `my-router.asuscomm.com`, `192.168.1.20`-`192.168.1.25`, `AA:BB:CC:DD:EE:FF` - and say in the document that they are invented, so a later reader does not treat them as real and reinstate the originals. Verbatim session logs go under `.claude/testing/`, which is `.gitignore`d for exactly this reason. There are no exceptions: `kDefaultRouterIp` was one until build 410 and is now the ASUS factory address `192.168.50.1`, pinned by a test.
- **Stock is the primary firmware now, Merlin the secondary.** Decided 2026-09-06: the maintainer test router runs stock permanently, and Merlin is flashed only to check the app still works on it. That inverts the original order - stock support was added to a Merlin-first app - so a behaviour that has to be verified on hardware gets verified on stock first, and a stock/Merlin difference is a stock decision with a Merlin fallback rather than the reverse. It does not change the code: both branches are still supported and both are still tested.
- **Keep the stock boot-persistence mechanism low-key in user-facing text.** `README.md`, the Play listing, the in-app text and anything posted publicly describe the *requirement* (Download Master must be installed, then left alone) and the *consequence* (it will not work afterwards) - never the mechanism, and never that alternatives were evaluated and closed off. ASUS could remove the approach if it were drawn to their attention, and it is the only one that works on stock. The source is GPL and public, so this lowers the signal rather than concealing anything; that is still worth doing. Engineering rationale belongs in `ARCHITECTURE.md` and code comments, stated plainly but without advertising.
- **Hardware work gets a runsheet or a script, not prose instructions.** Anything Andrew has to do on the router is written as a numbered runsheet in `.claude/testing/` (gitignored) or as a script in `scripts/`, with a `RESULT:` line under each step to fill in. This has repeatedly turned vague reports into precise ones and is the main reason the device-assignment schema got settled in a day.
  - **No markdown tables in runsheets.** They render badly in VS Code even on a wide screen. Use vertical lists with one step per line.
  - **Be specific to the point of tedium.** Exact commands, exact expected output, exact preconditions. Room for improvisation is where bad data comes from.
  - Scripts should guard their own preconditions and refuse rather than produce a confidently wrong answer, print a short ANSWERS block rather than a log dump, and restore whatever they changed.
- **A single hardware observation is provisional until corroborated - label it that way in the docs.** During the 2026-09-06/07 device-assignment work, three findings were written into `ARCHITECTURE.md` or the plan as settled and had to be withdrawn within hours: a LAN outage blamed on the wrong service call, fail-closed behaviour generalised from `vpnc_default_wan` to per-device policy, and a three-way device classification built on a WebUI column that reclassified itself overnight. Each was one observation stated as a model.
  - Write what was **measured**, then the inference, and mark the inference as one. "Observed X on one network; the reading that fits is Y" is honest and still useful. "Y" alone is a claim that has to be retracted.
  - Prefer the authoritative source over the convenient one. `dhcp_staticlist` membership is a fact the firmware acts on; a WebUI display column is a rendering of something else.
  - Retract in place rather than quietly editing: leave enough that a reader knows the earlier claim existed and why it was wrong, so it is not rediscovered and re-adopted.
- **Writing the setting is not applying it - check the mechanism, not the list.** Device assignment wrote `vpnc_dev_policy_list` correctly, and the web interface, the ASUS app and this app all agreed. The traffic still left through the old tunnel, because stock never removes the old `ip rule` and both rules sit at priority 100, so insertion order decides. A whole day of testing read as “assignments do not work” when they did; one look at `ip rule show` ended it. When a change is written and has no effect, go to the layer that ENFORCES it. ARCHITECTURE.md "Stock leaves the old routing rule behind".
- **When the router disagrees with you, WATCH it rather than reason about it.** The technique that has settled every hard question in this project is the same one: snapshot the state, make the change through the reference implementation, diff. `probe-device-assignment.sh` found the assignment schema that way; an `nvram show` diff found `wgc_unit` in one line after five wrong theories; a once-a-second sampler found that the key is written AFTER `restart_default_wan` and not before, which no amount of thinking had produced.
  - **Reach for it early, not after the guesses run out.** The default-connection sequence took eleven probes on 2026-09-08, and the first eight were hypotheses. Each sounded reasonable and each was wrong, and every one cost Andrew a round trip on hardware at his own keyboard.
  - **Sample over time when a value will not stick.** A single before/after read says what changed; a loop printing the value once a second says WHEN, and lines up against `/tmp/syslog.log` to say what ran between. Ordering bugs are invisible to the first and obvious to the second.
  - **Diff whole namespaces, not the one key you suspect.** Filtering to what you already believe is involved is how `wgc_unit` stayed hidden - it was never in any command anyone had run.
  - **`notify_rc` only QUEUES, and the queue can WEDGE.** Anything issued straight after it races the service, so poll for the observable effect rather than sleeping. Worse: a service that never finishes leaves `rc_service` set, and from then on every event is discarded after a 15-second wait - `waitting "X" via ...` then `skip the event: Y`. Measured 2026-09-10: ninety minutes of that, four watchdog reconfigures acted on by nothing, and a `reboot` request discarded too, so a POWER CYCLE was the only recovery. `lib/router_service_queue.dart` clears a ghost marker (key set, pid gone) before every service call and waits for the key to clear after it. ARCHITECTURE.md "The router's service queue, and how it wedges".
- **One sighting of an interface is not "up".** The app called wgc1 enabled a second after `restart_vpnc` because it caught it mid-restart, then ran the deploy script against a tunnel going back down. Two consecutive sightings.
  - Say plainly which parts are measured and which are inferred, and when an inference is disproved, say that too. Six of mine were wrong in one evening; the record of what was ruled out is worth as much as the answer, because it stops the same ground being covered twice.
- Do not read `.claude/plan_*.md` as current state — they are historical design notes.
- **NVRAM records are numbered 0-based, and the word is "index", not "field".** Any NVRAM value holding more than one entry - `vpnc_clientlist`, `custom_clientlist`, `dhcp_staticlist` - is described as `index N`, counting from 0, matching the `VpncRecord` constants in `router_slot_service.dart`. Until 409 the ARCHITECTURE.md prose counted from 1 while its own schema table counted from 0, so "field 6" meant the active flag in one place and the state index in another - a mix-up that writes the active flag where the state index belongs and disables a tunnel while appearing to succeed. **Slot numbers are unaffected**: they are the firmware's own naming and stay `wgc1`..`wgc5`.
- **Do not line-wrap Markdown.** `.md` files - this one, `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `BACKLOG.md`, `TESTING.md`, `SECURITY.md`, everything under `.claude/` - carry one logical unit per line and no hard wrap at any column. Wrapping makes a diff of a reworded sentence touch every following line, and a hard-wrapped table row breaks the table outright. The 130-character line length is a **Dart** rule and applies to `lib/` and `test/` only. Fenced code blocks inside Markdown keep whatever line breaks the code itself needs.

### Conventions in force (observed, not aspirational)

| Area | What the codebase actually does |
| --- | --- |
| Lint | `package:flutter_lints/flutter.yaml` (`flutter_lints ^6.0.0`), **no custom rules enabled or disabled**. `analyzer.exclude` drops `build/`, `android/`, `ios/`, `web/`, desktop dirs. |
| Line length | 130 (`.vscode/settings.json` `dart.lineLength`, `.prettierrc` `printWidth`). Format on save via Dart-Code. **This file is exempt** - one logical unit per line, however long. Do not re-wrap it; a hard-wrapped table row breaks the table. |
| State management | No package. `SessionController extends ChangeNotifier`, published through the `SessionScope` `InheritedWidget`; subtrees that must repaint wrap `ListenableBuilder`. Screens are `StatefulWidget` + `setState` for local form state. **No Provider/Riverpod/Bloc — do not introduce one.** |
| Dependency injection | Constructor-injected nullable factories used purely as test seams: `PiaService? service`, `Future<SSHClient> Function(...)? testClientFactory`, `RouterSlotService Function(SSHClient)? slotServiceFactory`, `RouterWatchdog Function(SSHClient)? watchdogServiceFactory`, `SessionController? controller`, `PiaService({int probePort})`, `RouterSlotService(..., verifyPollInterval, verifyMaxAttempts)`. Follow this pattern instead of a service locator. |
| Error handling | Services `throw`; UI catches, strips `'Exception: '`, and routes through `AppErrors.system` (one at a time) or `AppErrors.inputs` (batched). Every error is also appended to the app log. Router mutations are additionally wrapped by `RouterWatchdog._guard`, which logs to the app log **and** the router syslog before rethrowing. Best-effort side calls (`_logRouter`, ping helpers) swallow with `catch (_)`. |
| Async + UI | Every `await` across a widget boundary is followed by a `mounted` check. Spinners are cleared **before** awaiting a modal (a spinner must never animate under a dialog) — see `SlotModal._runSlot`. |
| SSH lifetime | **One connection per app session**, shared by every action - `RouterSession` in `router_session.dart`, owned by `SessionController`. Opened lazily, reused, reconnected once on a transport failure, and closed by `wipeAll()` and by `AppLifecycleState.paused`. Until 406 it was a fresh `SSHClient` per action, closed in a `finally`; **an action must never call `close()` now** - it would pull the connection out from under the next one, and a source scan in `test/unit/router_session_test.dart` fails the build if one appears. |
| Licence header | Every `lib/` file opens with the GPL-v3 header block + `Copyright (C) 2026 Andrew Newbury.` Keep it on new files. |
| Colours | Never inline a hex colour in a screen; use the constants in `lib/app_colors.dart`. |

## 2. Snapshot

The app opens on a main menu (`MainMenuScreen`) offering four screens plus "Exit app"; a hamburger drawer rendered *above* the Navigator duplicates those and adds four more - **VPN device assignment**, **View router log**, **Settings** and **About**. Screen 1 generates a standalone PIA WireGuard config (region → credentials → `GENERATE CONFIG`) with a 60-second clipboard auto-clear and SHARE/SAVE. Screens 2 and 3 SSH into an ASUS router and then push a shared full-screen `wgc1..wgc5` slot list: *manage* mode does CREATE / ENABLE / EDIT / DISABLE / DELETE of WireGuard slots; *watchdog* mode does CREATE-EDIT / DELETE / VIEW ROUTER WATCHDOG LOG and deploys a router-side POSIX-sh watchdog that re-negotiates PIA on ping failure. **Both Merlin and stock ASUS firmware are supported** — the firmware is detected once per session on entry to either router screen and every router command branches on it (§4.13). Screen 4 shows the in-memory app log. The drawer-only screens pin individual LAN devices to a tunnel (stock only, §4.14), page through the router's syslog, and remove things - the router uninstall lives on SETTINGS. All credentials and generated config are volatile — held only in `SessionController` and wiped on every exit path — though PIA and SMTP credentials *are* written to router NVRAM in plaintext when a watchdog is deployed.

## 3. Architecture — `lib/` (44 files)

### Root

| File | Role |
| --- | --- |
| `main.dart` | 23 lines. `void main() => runApp(const PiaWgApp())`; re-exports `PiaWgApp` from `app_shell.dart`. |
| `firmware.dart` | `RouterFirmware` enum, the once-per-session detection flag (a library global — see §4.13), `classifyFirmwareTag()`, `jqCommand()`, and the stock paths (`kStockJqPath`, `kStockMailsendPath`, `kS50Path`, `kServicesStartPath`, `kReadmePrereqUrl`). |
| `s50_template.dart` | `kS50DownloadmasterTemplate` and `kS50AsusLighttpdTemplate` — verbatim LF copies of the two scripts in `./scripts/` (same mirroring pattern as `license_text.dart`) — plus `buildS50Script()` / `extractS50CruLines()`, which own the block between the REPLACEMENT markers. Tests fail if either copy drifts. |
| `app_shell.dart` | `PiaWgApp` (root `StatefulWidget`, `WidgetsBindingObserver`) owns the `SessionController`, `MaterialApp`, `buildAppTheme()`, and installs `AppChrome` via `MaterialApp.builder`. `DestinationObserver` (a `NavigatorObserver`) updates `controller.currentDestination` from its OWN list of page routes, **ignoring non-`PageRoute`s** so dialogs don't change drawer highlighting. It cannot read `previousRoute` on a pop: with a modal open under a pushed page, popping that page reports the dialog, and treating that as "no change" left the destination naming the page just left - the drawer then no-opped on that entry. `didChangeAppLifecycleState(resumed)` → `resyncOnResume()`. Disposes the controller only if it created it. |
| `session_controller.dart` | `AppDestination` enum (9 values), `LogEntry`, `SessionController extends ChangeNotifier`, `SessionScope extends InheritedWidget`, `kDefaultDns`. Holds all volatile state, the 1 Hz clipboard countdown, modal depth, `wipeAll()`. `SessionScope.updateShouldNotify` compares controller identity only, so it does **not** rebuild on every tick.  Also holds the device screen's STAGED assignments (`stagedAssignments`, `stagedDefaultIndex`, `clearStagedAssignments`), because `DeviceAssignmentScreen`'s State is rebuilt on every entry and a glance at the log used to discard them.|
| `app_colors.dart` | 13 `const Color` tokens: `kHighlight` teal `#00D4AA`, `kSecondary`, `kBg`, `kSurface`, `kField`, `kBorder`, `kText`, `kMuted`, `kHint`, `kError`, `kOnPrimary`, `kConfigBg`, `kWarn`. |
| `pia_service.dart` | PIA provisioning engine. `WgServer`/`Region`/`ProbeResult`/`RegResponse` models + `PiaService`. Uses `dart:io` `HttpClient` (10 s connect timeout), not `package:http`. |
| `router_session.dart` | `RouterSession implements SSHClient` - the shared router connection. `client()` opens on demand and coalesces concurrent opens; `run()` retries **once** after reconnecting when `isConnectionLost(e)`; `close()` is the session teardown. Implementing `SSHClient` rather than wrapping one is why nothing downstream changed: the services still take an `SSHClient` and the fakes still substitute for one. |
| `router_slot_service.dart` | `kSlotNvramKeys` (17 keys), `openSshClient()`, `SlotInfo`, `RouterSlots`, `RouterSlotService`: fetch/read/create/enable/disable/delete/write slot params, ping-target NVRAM, `pingViaSlot`. |
| `router_watchdog.dart` | The largest file in the app. Validation helpers, `WatchdogConfig`, `WatchdogStatus`, pure Bash-template builders, `RouterWatchdog` service, and `_kWatchdogScriptTemplate` (the router-side sh script, ~7 KB heredoc ceiling). |
| `watchdog_dialog.dart` | `WatchdogDialog` — the watchdog CREATE/EDIT form. Its `SAVE` validates, optionally picks a region, WAN-pings both targets (warn-only), then calls `deployWatchdog`. **This is the only path that brings a watchdog up.** |
| `build_info_service.dart` | `BuildInfo` model + `loadBuildInfo()` over `MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/build_info')`, method `getBuildInfo`. One of the app's **two** platform channels. Falls back to `BuildInfo.unknown()` on `MissingPluginException`/`PlatformException` so widget tests render. |
| `review_service.dart` | `openPlayStoreReview()` - opens the Play Store listing via `in_app_review`'s `openStoreListing()` (an ACTION_VIEW on the https URL, which the manifest `<queries>` already covers). Returns false when nothing could be opened, and the caller logs that. **Deliberately does NOT call `requestReview()`** - see §4.8.3. `debugReviewOverride` is the test seam: a method-channel mock is not enough, because the plugin branches on the host platform in Dart before the channel is reached. |
| `clipboard_service.dart` | `clearSystemClipboard()` over `MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/clipboard')`, method `clearClipboard` -> `ClipboardManager.clearPrimaryClip()` (API 28+). Falls back to writing `''` on `MissingPluginException`/`PlatformException`. A test reads `MainActivity.kt` so the names cannot drift. |
| `router_command.dart` | `runRouterCommand()` and `RouterCommandException`. The one place a router command is run: **writes throw, reads tolerate**. `SSHClient.run()` merges stderr into stdout and discards the exit code, so this uses `runWithResult()` and keeps them apart. |
| `router_service_queue.dart` | `RcServiceState`, `parseRcService`, `RouterServiceQueue`, `RouterServiceWedgedException`. Survives the router's own `notify_rc` queue: a service that never finishes leaves `rc_service` set and every later event is discarded after a 15-second wait. Clears a ghost marker (key set, pid gone) before a service call and waits for the key to clear after it. ARCHITECTURE.md "The router's service queue, and how it wedges". |
| `device_assignment.dart` | Pure layer for VPN Fusion device policy - no SSH. `DevicePolicy`, `parseDevicePolicyList` / `serialiseDevicePolicyList`, `setDevicePolicy`, `assignedIndexFor`, `staleRuleTables`, `LanDevice`, `buildDeviceList` and the four-source join. |
| `device_assignment_service.dart` | The I/O half: one marker-delimited read of eight sources, and an `apply()` that re-reads and refuses on conflict before writing anything. Owns the eleven-probe default-connection sequence and the stale `ip rule` sweep. |
| `router_log_paging.dart` | Pure paging arithmetic for the router log: which bytes of which file a page covers, the command that fetches it, and the partial-line trim. `/tmp/syslog.log` reaches 512 KB in a day and rotates rather than truncating. |
| `binary_installer.dart` | Downloads, verifies and installs `jq` and `mailsend-go` onto stock. Pinned versions and SHA-256 per architecture; refuses to install anything unverified; chowns to `0:0` because the archives carry their builder's uid. |
| `router_prefs.dart` | The ONLY thing the app writes to device storage: the remembered router address. No credential is ever persisted. Inert under `flutter test` unless a directory is injected. |
| `entitlement.dart` | `Entitlement.isUnlocked` - the seam RevenueCat will fill. Returns true today. |
| `license_text.dart` | 645 lines. `const String kLicenseText` — verbatim raw-string copy of `./LICENSE` (GPL v3). Regenerate by hand if `./LICENSE` changes. |

### `lib/screens/`

| File | Role |
| --- | --- |
| `main_menu_screen.dart` | 5 buttons + `* requires SSH connectivity` footnote + a "(?) how to use this app" link (`Key('menu_help')`, `kHelpUrl` -> README section 5), then above the PayPal/Patreon donation block a "(*) add a Play Store app review" link (`Key('menu_review')` -> `review_service.dart`), separated from it by a `spacer` so the ask does not read as a third way to pay. `PopScope(canPop: false)` routes the Android back key to `confirmAndExit`. |
| `standalone_config_screen.dart` | Region row / PIA username / password / DNS → `GENERATE CONFIG`; renders the generated config under a `GENERATED CONFIG: pia-<region>` heading (`Key('generated_config_label')`, same stem as the shared `pia-<region>.conf`) with COPY (+ countdown) and SHARE / SAVE. |
| `manage_router_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.manage, …)`. |
| `watchdog_management_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.watchdog, …)`. |
| `log_screen.dart` | `ListenableBuilder` over the controller → `LogPanel` + `CLEAR LOG`. |
| `slot_params_editor.dart` | Modal editor for the 17 per-slot NVRAM values (spec 3.3). |
| `settings_screen.dart` | Everything that REMOVES something: the router uninstall, DEL PIA CERT, FORGET ROUTER IP. Drawer only. |
| `router_log_screen.dart` | `/tmp/syslog.log`, newest 32 KB first, paging backwards on demand and continuing into the rotated file. COPY / REFRESH / HOME. |
| `about_screen.dart` | Build info is ONE `Text.rich` with `\n` between rows, not a widget per row — `SelectionArea` joins separate widgets with no separator, so a row-per-widget layout copies as one run-on line. `COPY BUILD INFO` (`Key('about_copy_build_info')`) and `CREATE GITHUB ISSUE` (`Key('about_create_issue')`) share a `Wrap`. The latter opens `bugReportUrl()`: `<repo>/issues/new` with `title` and `body` prefilled, reproducing the headings of `.github/ISSUE_TEMPLATE/bug_report.md` (GitHub honours a template **or** a `body`, never both) and filling Environment with `asPlainText` plus the detected firmware. A test fails if the template's headings drift. `DEL PIA CERT` (`Key('about_del_pia_cert')`) confirms, then SSHes in and runs `RouterWatchdog.deleteCachedPiaCert()`. With no router credentials in the session it asks for them inline via `_SshCredsDialog` (`about_ssh_continue` / `about_ssh_cancel`) and writes them back to the session; ABOUT is reachable without ever visiting a router screen. Takes a `testClientFactory` like the router screens. All three buttons take their own line at phone width - CREATE GITHUB ISSUE alone is 282px of a ~320px body - which is what the `Wrap` is for. COPY writes `_BuildInfoBlock.asPlainText` via `SessionController.copyToClipboard(armAutoClear: false)` - not a secret, so it arms no countdown and stands down one an earlier config copy left running. This is the screen's only `SessionScope` dependency. Whole body wrapped in one `SelectionArea` (drag or Select all copies build info + links + licence together), so its children are plain `Text`, not `SelectableText`. Build provenance from `loadBuildInfo()`, 6 project links, an open-source `_LicensesDialog` (custom dark replacement for `showLicensePage`) whose entries go through `groupLicensesByPackage` — one heading per package, not per `LicenseEntry`, since the registry emits an entry per licence text naming every package it covers, and the full GPL text. The dialog keeps notices as `LicenseParagraph` lists and renders each through `_LicenceParagraph` (`centeredIndent` ⇒ centred + bold, else `16.0 * indent` padding), and carries its own `SelectionArea` — the screen's region does not reach into a dialog route. Hard line breaks inside a notice are already gone before we see it (`LicenseEntryWithLineBreaks` joins a paragraph's lines with a space), so expat's ASCII art reads as run-on text here exactly as it does in Flutter's own licence page. |

### `lib/widgets/`

| File | Role |
| --- | --- |
| `app_scaffold.dart` | `AppChrome` (drawer host + static header, sits above the Navigator so the hamburger stays live under dialogs; carries the app-wide `AnnotatedRegion<SystemUiOverlayStyle>`), `kSystemOverlayStyle`, `AppHeaderBar` (two-line title, author link, `v<version>` from `PackageInfo`), `AppScaffold` (a `Material` - not a `ColoredBox`, or a `ListTile` below it finds the chrome's Material with an opaque box in between and Flutter asserts the splash is invisible - wrapping a scrollable padded body plus an optional pinned `HOME` button; `showClose: false` for a screen with its own buttons; `fillViewport` for the menu). |
| `app_drawer.dart` | `screenForDestination()`, `navigateToDestination()` (no-op on current; **pushes**, growing the stack by design), `closeApp()`, `confirmAndExit()`, `AppDrawer`. |
| `slot_modal.dart` | `SlotModalMode` enum + `SlotModal` (slot list, badges, mode-dependent button set, all router actions) + `_PiaCredsDialog` + `_PingTargetsDialog`. Despite the file name it is a full-screen page since 418, wrapping `AppScaffold` in a `Stack` so the processing overlay covers HOME as well. |
| `router_slots_screen.dart` | Shared router-IP/SSH form + `CONNECT TO ROUTER` for both router screens; auto-reconnects when `routerConnected`; runs the firmware gate (§4.13) before `fetchSlots`; pushes `SlotModal` as a page. `_FirmwareGate` carries the outcome so a dialog is only awaited after the connect spinner clears. |
| `firmware_notice.dart` | `showFirmwareNotice` + the two wrappers `showMissingBinariesNotice` / `showUnsupportedFirmwareNotice`. A dismissible warning whose README link is a tappable `TextSpan` (`AppErrors` renders plain text and cannot carry a link). Keys `firmware_notice`, `firmware_notice_link`, `firmware_notice_ok`. |
| `device_assignment_screen.dart` | The assignment screen: default-connection panel, device list, per-device picker, staged changes (held on the session), and the apply confirmation. |
| `install_binaries_dialog.dart` | The offer to install the missing stock helper binaries, and its progress. |
| `ssh_creds_dialog.dart` | The router login prompt used AWAY from the router screens - ABOUT, SETTINGS and the router log are all reachable without ever visiting one. |
| `log_buttons.dart` | `LogButtonRow` / `LogButton` - the three bordered equal-width buttons both log screens carry. The deliberate exception to full-width HOME. |
| `common_fields.dart` | `RegionRow`, `PiaUsernameField`, `DnsField`, `ObscuredField`, `PiaPasswordField`, `RouterIpField`, `SshUsernameField`, `SshPasswordField`, `ClearButton`, `IconActionButton`, `SlotBadge`, `LogPanel`. The credential fields carry `autofillHints` (`username` / `password`); `ObscuredField` takes them as a parameter so both password fields can pass their own. Non-secrets (`RouterIpField`, `DnsField`) deliberately carry none - Android treats an absent hint list as "autofill disabled", which is what we want there. |
| `error_presenter.dart` | `AppErrors.system` / `AppErrors.inputs` + `_ErrorDialog`. Static `_token`/`_openErrorNav` let a newer error dismiss an older one. |
| `region_picker_sheet.dart` | `RegionPickerSheet` — filterable `DraggableScrollableSheet` region list, shared by standalone / CREATE / watchdog EDIT. |

### Call graph (routers)

```
RouterSlotsScreen ──connect()──> SSHClient ──> RouterSlotService.fetchSlots()
        └─> SlotModal(mode)
              ├─ manage:   _create → PiaService.generateConfig → createConfigToSlot
              │            _enableManage → [stopWatchdog/disableSlot others] → enableSlot
              │            _editManage  → readSlotParams → SlotParamsEditor → writeSlotParams
              │            _disableManage / _deleteManage (both stopWatchdog first)
              └─ watchdog: _editWatchdog → WatchdogDialog → RouterWatchdog.deployWatchdog
                           _deleteWatchdog → stopWatchdog + deleteSlot
                           _viewWatchdogLog → getWatchdogLog

DeviceAssignmentScreen ──connect()──> SSHClient ──> DeviceAssignmentService.read()   (one read, 8 sources)
        ├─ staged on SessionController (survives a trip to the log and back)
        └─ APPLY → .apply() → re-read, refuse on conflict
                              → dhcp_staticlist → vpnc_dev_policy_list → commit
                              → restart_dnsmasq + restart_vpnc_dev_policy → clear stale ip rules
                              → [default connection, if changed: the eleven-probe sequence]

RouterLogScreen  ──> router_log_paging.dart (pure) ──> tail -c … | head -c …
SettingsScreen   ──> RouterWatchdog.uninstallFromRouter() / deleteCachedPiaCert()
```

## 4. Feature reference

### 4.1 Navigation & destinations

| `AppDestination` | `routeName` | `title` | On main menu? | In drawer? |
| --- | --- | --- | --- | --- |
| `menu` | `main_menu` | Main menu | — (is the menu) | yes, as **HOME** |
| `standalone` | `standalone` | Generate PIA WireGuard config | yes | yes |
| `manageRouter` | `manage_router` | Manage PIA WireGuard config | yes (`*` suffix) | yes |
| `watchdog` | `watchdog` | Watchdog WireGuard management | yes (`*` suffix) | yes |
| `deviceAssignment` | `device_assignment` | VPN device assignment | **no** | yes |
| `routerLog` | `router_log` | View router log | **no** | yes |
| `log` | `log` | View app log | yes | yes |
| `settings` | `settings` | Settings | **no** | yes |
| `about` | `about` | About | **no** | yes |

- **SETTINGS and View router log are drawer-only.** An uninstall is not something to offer on the way in, and the router log is a diagnostic detour rather than a destination anyone sets out for. `SettingsScreen` holds everything that REMOVES something - the router uninstall, DEL PIA CERT and FORGET ROUTER IP, the last two are there rather than on ABOUT, which is a page people open to read.
- Menu also has `Exit app` (`Key('menu_close_app')`); drawer also has `Exit app` (`Key('drawer_close_app')`).
- Navigation **pushes** (`navigateToDestination`) — the stack grows deliberately so back can retrace.
- Active destination is `kHighlight` (teal) via `ListTile.selectedColor`.
- **`RouterSlotsScreen` IS the slot list once it has connected - it does not push one.** The connect form and the list are two states of one screen, the way the device assignment screen works, so the back button leaves for the menu instead of returning to a spent login form. Neither navigates at all, so there is no extra route to name, to observe, or to go back to. `SlotModal` still pushes `WatchdogDialog` as a page, with `settings.name` set to the watchdog destination so `DestinationObserver` keeps the drawer highlighting it - an unrecognised name silently resets that to the menu.
- Neither calls `enterModal`/`exitModal`: `modalDepth` says something is stacked OVER a screen, and these are screens.
- **A router screen that will reconnect on its own NEVER renders its login form.** All three set an `_autoConnecting` flag synchronously in `didChangeDependencies`, so the first frame shows `ReconnectingBody` instead; the flag clears in the same `finally` that clears the connect spinner, which is the point at which a failure means the form is genuinely needed. Rendering the form during a reconnect asks for credentials the app already holds and offers fields that are about to be replaced.
- **HOUSE STYLE: one control, one size, on every screen.** `HOME` is full width and pinned at the bottom EVERYWHERE, including on screens whose body is capped by `maxContentWidth` - the cap is for content, not for chrome. A control that changes size between screens reads as an accident even when each screen looks fine on its own.
  - The two LOG screens are the deliberate exception: they carry a row of three bordered buttons (`COPY REFRESH HOME` on the router log, `COPY CLEAR CLOSE` on the watchdog log), so no single button can be full width there. Do not "fix" that back.
- **Screens that were 480-wide cards pass `AppScaffold(maxContentWidth: kFormMaxWidth)`.** Without it a slot row on a tablet sits alone at the far left of a very wide line. The cap covers the HOME button too, or it runs the full width under a narrower column. A phone is narrower than the cap and is unaffected.
- Every HOME is `AppScaffold`'s: pinned at the bottom, full width, outside the scroll view, pushing a fresh menu. No screen builds its own.
- Exit paths (back key on menu, menu button, drawer entry) → `confirmAndExit` → `wipeAll` → `SystemNavigator.pop()`.

### 4.2 Session state (`SessionController`)

| Field | Notes |
| --- | --- |
| `piaUsername`, `piaPassword`, `dns` | `dns` defaults to `kDefaultDns` = `'9.9.9.9, 149.112.112.112'`. |
| `routerIp`, `sshUsername`, `sshPassword` | Volatile. The form prefills via `routerIpPrefill`: session value, then `rememberedRouterIp`, then `kDefaultRouterIp` (`192.168.50.1`, the ASUS factory address) / `admin`. |
| `rememberedRouterIp` | **The only value the app writes to device storage.** Loaded once at startup by `loadRememberedRouterIp()`, written by `rememberRouterIp()` after a connect SUCCEEDS, deleted by `forgetRouterIp()`. NOT cleared by `wipeAll` - see 4.2.1. |
| `generatedConfig`, `generatedRegionId` | Survive navigation; wiped by `wipeAll`. |
| `log` (`List<LogEntry>`) | `[HH:MM:SS] msg`, flags `isError` / `isSuccess`. |
| `clipboardSeconds`, `_clipboardDeadline` | 60 s default (`clipboardTimeout`), 1 s tick; `resyncOnResume()` re-evaluates after background. |
| `modalDepth` / `modalsOpen` | `enterModal` / `exitModal`. |
| `currentDestination` | Plain field, set by `DestinationObserver`; no `notifyListeners`. |
| `routerConnected` | Set true after a successful connect; drives auto-reconnect on screen re-entry. |
| `canReuseRouterSession` | True when the session holds a live connection AND the three fields to rebuild it. The three router screens render `ReconnectingBody` instead of their login form when it is true - "three non-empty fields" was the wrong test, because opening MANAGE writes the factory-default address into the session. |
| `stagedAssignments`, `stagedDefaultIndex` | The device screen's unsaved picks, held here rather than in its `State` because that State is rebuilt on every entry. `clearStagedAssignments` after a successful apply. |

`wipeAll({reason})` clears all six credential fields, config, `routerConnected`, and the clipboard, then logs. It deliberately leaves `rememberedRouterIp` alone. Injectable seams: `clipboardTimeout`, `tickInterval`, `clipboardWriter`, `routerPrefs`.

#### 4.2.1 The remembered router address (`router_prefs.dart`)

The app is otherwise zero-persistence, so this is the one departure and it is kept deliberately narrow. `RouterPrefs` writes a single line - the router LAN address - to `router.txt` under `getApplicationSupportDirectory()`. Rules, all of them enforced by `test/unit/router_prefs_test.dart`:

- **Only the address.** No username, no password, nothing else, ever. A source scan of `router_prefs.dart` fails the build if the file gains a second write or mentions a credential, because a password there would survive `wipeAll`, survive an app close, and sit in plain text.
- **Only after a proven connect.** `rememberRouterIp` is called from `router_slots_screen._onConnect` and `about_screen._deletePiaCert`, both after the SSH work succeeded. Same rule as `TextInput.finishAutofillContext()` - never persist an unproven value.
- **Validated in both directions.** `^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$`. The file is hand-editable on a rooted device and its contents reach an SSH connect, so a rejected value is dropped on read as well as on write.
- **Survives `wipeAll`, clearable by the user.** SETTINGS -> FORGET ROUTER IP, greyed out when there is nothing stored - which is also the only way a user can see that anything IS stored.
- **Off-device backup is disabled.** `android:allowBackup="false"` in the manifest, so it never reaches Google Drive.
- **Inert under `flutter test`.** The default store checks `FLUTTER_TEST`: the path_provider channel has no handler in a test binding and the reply never arrives, so an `await` on it hangs - which surfaces as a connect spinner that never clears and a bare `pumpAndSettle timed out`. A test that wants storage passes `directory`. **Widget tests cannot use a real directory at all** - a `testWidgets` body runs under fake async, which never completes real file I/O; use an in-memory `RouterPrefs` subclass, as `about_screen_test.dart` does.

### 4.3 Standalone generation — `PiaService`

| Step | Detail |
| --- | --- |
| `fetchRegions` | GET `https://serverlist.piaservers.net/vpninfo/servers/v6`; parses only the **first line** (up to `\n`); keeps regions with ≥1 `wg` server; sorted by id. |
| `probeLatency` | Concurrent `Socket.connect(ip, probePort, timeout: 2s)`. `defaultProbePort = 1337`; `probePort` is injectable so parallel test workers don't collide on the port. Failures sort last. |
| `getToken` | POST `https://www.privateinternetaccess.com/gtoken/generateToken`, HTTP Basic. Non-200 → extracts `message`/`error` from a JSON body. Throws a **`String`** (`'Auth error: …'`), not an `Exception`. |
| `generateWgKeypair` | 32 `Random.secure()` bytes, X25519 clamped (`[0] &= 248`, `[31] &= 127`, `[31] \|= 64`), base64. |
| `registerKey` | Downloads the PIA CA (`pia-foss/manual-connections/master/ca.rsa.4096.crt`), builds a `SecurityContext(withTrustedRoots: false)` pinned to it, sets `Host: <cn>`, GETs `https://<ip>:1337/addKey?pt=&pubkey=`. `badCertificateCallback` only accepts `CN=<server.cn>` (fires because the URL uses the IP). |
| `buildConfig` | `MTU = 1420`, `PersistentKeepalive = 25`, `AllowedIPs = 0.0.0.0/0`, address `/32`. |
| `generateConfig` | regions → probe → best responder → token → keypair → register → build. Empty DNS falls back to Quad9. |

UI (`standalone_config_screen.dart`): `GENERATE CONFIG` is enabled only when region + username + password are non-empty (DNS optional). PIA creds/DNS mirror into the session on every keystroke. A blank DNS field is refilled with `kDefaultDns` on entry and again at the start of `_generate` (`_restoreDefaultDns`) - not per keystroke, so it can still be cleared to retype. `PiaService` keeps its own Quad9 fallback for an empty `dns`, but the screen should never reach it; a test pins the two to the same constant. COPY → `copyToClipboard` + snackbar + countdown. SHARE writes `pia-<region>.conf` into `getTemporaryDirectory()`, shares it, then deletes it in `finally`.

### 4.4 Slot modal button matrix (`SlotModal._buttons`)

`hasDesc` = `wgcN_desc` non-empty; `enabled` = `wgcN_enable == 1` (vpnc_clientlist index 5 on stock); `wdActive` = cron entry present. DISABLE also accepts an interface that is up while the flag reads 0 — the two can disagree, and gating on the flag alone would strand a running tunnel behind a greyed button.

| Mode | Key | Label | Enabled when |
| --- | --- | --- | --- |
| manage | `slot_create` | CREATE | a slot is selected |
| manage | `slot_enable` | ENABLE | `hasDesc && !enabled` |
| manage | `slot_edit` | EDIT | `hasDesc` |
| manage | `slot_disable` | DISABLE | `hasDesc && (enabled \|\| activeSlots.contains(n))` |
| manage | `slot_delete` | DELETE | `hasDesc` |
| watchdog | `slot_edit` | **CREATE/EDIT** | a slot is selected (works on an **empty** slot) |
| watchdog | `slot_delete` | DELETE | `hasDesc` |
| watchdog | `slot_view_log` | VIEW ROUTER WATCHDOG LOG | `hasDesc && wdActive` |

**There is no ENABLE or DISABLE button in watchdog mode.** All buttons are disabled while `_processing`.

Row badges: `● ACTIVE` (`activeSlots.contains(n)`), `⚑ KILL SWITCH` (`enforce==1`, amber), `◆ WATCHDOG ACTIVE` (`watchdogActive` - a cron entry exists), `⏸ WATCHDOG PAUSED` (`watchdogConfigured && !watchdogActive` on a non-empty slot: DISABLE removed the schedule and kept the settings; muted grey, since nothing is running), `✉ EMAIL ALERTING` (only alongside WATCHDOG ACTIVE). The two watchdog badges are mutually exclusive.

**Slot naming.** Every app-log and router-syslog line names a slot as `wgcN:<description>` via `slotLabel` / `fetchSlotLabel` (`router_slot_service.dart`), so a message says *which* VPN it is about. The description comes from `vpnc_clientlist` index 0 on stock (a WebUI-created profile has no `wgcN_desc` mirror) and from `wgcN_desc` on Merlin. Both services cache it per instance, so it costs one extra read per action however many lines mention it, and the lookup is best-effort - a failure degrades to the bare `wgcN` rather than breaking the action being logged. Raw router output echoed into the log (`wg show interfaces: wgc1`) is left verbatim. The EDIT modal heading uses the same label (`EDIT wgc1:pia-aus_melbourne`).

**Slots run concurrently**, and nothing in the app tears down a slot to bring another up. Stock caps how many may run at once - `RouterSlots.maxActiveSlots`, read from `nvram get vpnc_max_conn` and falling back to `kDefaultStockMaxActiveSlots` (2) when the key is missing or unparseable. Merlin has no such key, so `maxActiveSlots` is null there and nothing is capped. `SlotModal._enableManage` counts the *other* interfaces that are up and, when that reaches the cap, shows a "VPN limit reached" dialog naming the ASUS limit and asking the user to disable a slot - it makes no router writes in that case. The same check (`SlotModal._withinVpnLimit`) gates watchdog CREATE/EDIT, which brings a tunnel up as a side effect; it runs **before** the dialog opens so the user is not made to fill it in for nothing.

`RouterSlots.activeSlots` is a **`Set<int>`** built from *all* matches of `wgc(\d)` in `wg show interfaces` — more than one tunnel can be up at once (stock `vpnc_max_conn`), and the previous `firstMatch` silently badged an arbitrary one of them. It is independent of `SlotInfo.enabled` (the NVRAM / `vpnc_clientlist` flag): the badge means *the interface is up*, the flag means *it is configured on*. They can legitimately disagree while an action is in flight.

### 4.5 Manage-mode action semantics

| Action | Behaviour |
| --- | --- |
| CREATE | Overwrite confirm if `!isEmpty` → region picker → `_PiaCredsDialog` → `generateConfig` → `createConfigToSlot`. Backs up the 17 existing keys first and restores them on failure. Writes `enable=0`, `enforce=0`, `fw=1`, `nat=1`, `psk=""`, `rip=""`, `ep_addr_r=""`. Ends with an info dialog telling the user to press ENABLE. |
| ENABLE | Reads `wgcN_wd_primary_ip` / `_secondary_ip`; if either is blank, prompts (`_PingTargetsDialog`, defaults `8.8.8.8` / `1.1.1.1`) and writes them. Applies the concurrency gate (below), then calls `enableSlot`. **Other slots are left running.** |
| `enableSlot` | `enable=1` → commit → `service "start_wgc N"; service restart_vpnrouting0` → polls `wg show interfaces` up to `verifyMaxAttempts` (30) × `verifyPollInterval` (2 s) → pings **both** targets via `-I wgcN -c 1 -W 5`. **Both must pass**; any failure reverts to `enable=0` and throws. |
| EDIT | `readSlotParams` → `SlotParamsEditor` → `writeSlotParams` (values shell-single-quoted). |
| DISABLE | `stopWatchdog` if `wdActive`, then `enable=0` + commit + the firmware's stop, then **waits for the interface to leave `wg show interfaces`** before returning. The wait is what keeps the ACTIVE badge honest: `_runSlot` refreshes as soon as this returns, and the stop is queued through `notify_rc`, so without it the refresh reads a tunnel that is still up. Same for `_revertEnable`. |
| DELETE | Confirm (destructive) → `stopWatchdog` if `wdActive` → `enable=0`, stop service, **wait for the interface to leave `wg show interfaces`** (bounded by `verifyPollInterval`/`verifyMaxAttempts`), then `nvram unset` all 17 keys **plus** `wd_primary_ip` / `wd_secondary_ip`, plus `kVpncRuntimeKeys` on stock, then commit. Those runtime keys are indexed by the profile's **clientlist index 6**, not the slot — wgc1 leaves `vpnc9_*` — so `vpncStateIndexForSlot` resolves it from the record while it is still present, falling back to `10 - slot`. The wait is load-bearing: the stop is queued through `notify_rc` and returns immediately, so unsetting straight away lets the firmware re-create `wgcN_enable` behind it. If the interface never goes, the keys are cleared anyway and a warning is logged. |

All mutating router actions also emit `logger -t cfg-pia-wg '<msg>'` to the router syslog (best-effort).

### 4.6 Slot parameter editor (`slot_params_editor.dart`)

- Editable text (10): `addr`, `alive`, `desc`, `dns`, `ep_addr`, `ep_port`, `mtu`, `ppub`, `priv` (obscured, `ObscuredField`), `aips`.
- Editable switches (3): `enforce` (Kill switch), `fw` (Inbound firewall), `nat`.
- Read-only display (4): `enable`, `ep_addr_r`, `psk`, `rip`.
- Blank NVRAM pre-fills from `_kEditableDefaults`: `alive=25`, `dns=9.9.9.9, 149.112.112.112`, `ep_port=1337`, `mtu=1420`, `aips=0.0.0.0/0`.
- SAVE (`Key('slot_params_save')`) is disabled until **all 10** text fields are non-empty.

### 4.7 Watchdog

**Preconditions.** The watchdog runs on **both** firmwares; the firmware gate in §4.13 is what decides which path a command takes. `jq` is still required: `isJqInstalled()` checks `which jq` on Merlin and `[ -x /jffs/cfg-pia-wg/jq ]` on stock; if absent the dialog shows a red banner naming the expected path and SAVE is disabled.

**`WatchdogDialog` fields:** check interval (min, default 5), primary IP (8.8.8.8), secondary IP (1.1.1.1), PIA username/password (pre-filled from session, mirrored back on every exit path via `_rememberPiaCreds`), and — behind the `Enable email alerts` switch — From, To, Subject (`cfg-pia-wg alert`), SMTP server `host:port`, SMTP username/password, plus `TEST EMAIL`.

**`WatchdogConfig.validate()`** returns human-readable strings: interval > 0; both IPs required and valid IPv4; PIA username + password required; when email is on — From/To valid addresses, subject, `host:port` SMTP server, SMTP username + password.

**SAVE flow (`WatchdogDialog._save`):** jq gate → `validate()` → if not currently enabled, confirm-overwrite (when the slot is non-empty) then force a region pick → WAN-ping both targets (`pingHostViaWan`, warn-only, "The settings will still be saved.") → `deployWatchdog(cfg, desc)` → if the slot was empty, `enableVpnSlot` → pop.

**`RouterWatchdog.deployWatchdog` — the order is load-bearing:**
1. `enableJffsScripts` (`jffs2_scripts=1`, `jffs2_on=1`)
2. `_writeWatchdogNvram` (per-slot `wgcN_wd_*` + global PIA creds + optional `wgcN_desc`) + commit
3. `enableVpnSlot`
4. heredoc-write `/jffs/scripts/watchdog_wgcN.sh` (30 s timeout) + `chmod +x`
5. `cru a watchdog_wgcN "*/M * * * *" …` and `cru a watchdog_log_rotate_wgcN "0 0 * * *" …`
6. `_ensureServicesStart` — recreate `/jffs/scripts/services-start` if absent, strip prior entries for this slot, append both `cru` lines
7. run the script once immediately — deliberate: a failure lands in the router log now instead of at the next cron tick. The dialog must NOT enable the slot again afterwards; step 3 already did, and a second enable bounces the tunnel this run just established.

**`stopWatchdog`:** `cru d` both jobs, `rm` the script, strip the `services-start` lines (`chmod 700`), `rm` `/tmp/watchdog_wgcN.log{,.old}`, `/tmp/watchdog_last_ping_success_wgcN`, `/tmp/watchdog_backoff_wgcN`, `nvram unset` all 10 `wgcN_wd_*` keys, commit, then `_disableVpnSlot`. JFFS is left enabled. The **global** `cfg_pia_wg_user` / `cfg_pia_wg_password` are unset **only when no other slot still has a watchdog cron entry** (`_otherWatchdogsRemain`) — with concurrent watchdogs, clearing them early leaves the survivor unable to authenticate with PIA at its next renegotiation.

**`disableWatchdog` vs `stopWatchdog`:** DISABLE is schedule-only — `cru d` both jobs and drop the boot-persistence lines (`_removeCronPersistence`, shared with `stopWatchdog`); the script, the `wgcN_wd_*` settings and the running tunnel all stay. `enableWatchdog` puts the schedule back, reading the interval from `wgcN_wd_check_interval` on the router rather than taking it as an argument, and throwing if nothing is stored. `SlotInfo.watchdogConfigured` (that key being non-empty) is what lights the watchdog ENABLE button; `watchdogActive` (the cron entry) lights DISABLE.

**`getWatchdogStatus`:** enabled ⇔ cron entry **and** `wgcN_enable==1` **and** `wgcN` in `wg show interfaces`. `lastSuccessfulPing` parsed from `/tmp/watchdog_last_ping_success_wgcN`.

**BusyBox has no `comm`, no `diff` and no `seq`** - both confirmed 2026-09-08, `-sh: comm: not found`. To compare two sorted lists use `grep -vxF -f b.txt a.txt` in both directions; to count, use `i=0; while [ $i -lt N ]; do ...; i=$((i+1)); done` rather than a `seq` loop; for an NVRAM list, split records with `tr '<' '
'` first so the comparison is per record rather than per line. Add it to the list of things that are simply absent on this shell alongside `command -v` and `find -type f`. **BusyBox syslogd truncates a long `logger` message.** `_logRouter` goes through `buildLoggerCommand`, which splits at `kSyslogChunkChars` (200) into `(n/total)`-prefixed parts joined with `;` - one SSH call, nothing lost. Never hand `logger` an unbounded diagnostic. **BusyBox `nc` on stock takes no options** - it is `nc IPADDR PORT` and nothing else, so `nc -w 5 host port` exits on a usage error. Never use it as a reachability probe; `openssl s_client -connect` is the portable answer and reports why it failed. **`testEmail`:** returns `Future<bool>` (true = the mailer exited 0) and sends every diagnostic to the app log as well as the router syslog, marked `isError`. The dialog raises a dismissible warning on false. Never tell the user to go and read the router log - they are holding a phone. Writes `/tmp/mail.txt`, runs BusyBox `sendmail -H "exec openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -connect host:port"` on Merlin and `mailsend-go` on stock. On non-zero exit it reports two diagnostic layers - the mailer's stderr (`tail -20`, the error is the *last* thing said) and an `openssl s_client` probe - to **both** logs. SMTP port defaults to **465** when unparseable.

### 4.8 Router-side script `_kWatchdogScriptTemplate` (POSIX sh, `__SLOT__` is the only placeholder)

| Aspect | Value |
| --- | --- |
| Paths | `/jffs/cfg-pia-wg/watchdog_wgcN.sh` (`watchdogScriptPath`; deliberately NOT `/jffs/scripts`, which is Merlin's own hook directory and still holds `services-start`), log `/tmp/watchdog_wgcN.log`, status `/tmp/watchdog_last_ping_success_wgcN`, backoff `/tmp/watchdog_backoff_wgcN`, CA cache `/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt` (`kPiaCaCertPath`; the script `mkdir -p`s the directory before downloading, since Merlin has no reason to have created it) |
| Health check | `ping -I wgcN -c 3 -W 2` primary, **else** secondary — **either** passing is success (contrast: app ENABLE requires **both**) |
| Backoff | `backoff_for()` - a ladder of 120, 240, 480, 960, 1800, 3600 s, capped at **5400 s (90 min)**, generated from `kBackoffLadder` by `buildBackoffCase()` so the shell and `backoffSeconds()` cannot drift. Counter+timestamp in the backoff file, reset to `0\n0` on success. **The counter counts attempts actually made, not checks that found a fault** - it used to increment on runs the cooldown turned away, which made the growth rate depend on the check interval (a 1-minute watchdog escalated twice as fast as a 2-minute one). A run inside the wait logs `Backing off after N failed attempts` and exits, because a long silent gap otherwise reads as a stopped watchdog. |
| Preflight | `wgcN_desc` non-empty, `jq` present, PIA user set, and WAN reachability of either target (no internet → exit 0, no alert) |
| Liveness | `wg show wgcN latest-handshakes` reduced to its max, healthy if under 300s old; `ping -I wgcN` only as a fallback. **`ping -I` is not a liveness test on stock** - the router's own traffic is not routed into wgcN, so it fails on a healthy tunnel and the watchdog re-registered with PIA every cooldown until PIA refused tokens. |
| Re-negotiation | curl the CA (cached) → token via `jq -r '.token'` → server list filtered by `.regions[] \| select(.id==$DESC)` → ping-based latency sweep → `wg genkey`/`wg pubkey` → `curl --cacert --resolve <cn>:1337:<ip> …/addKey` → write 16 `wgcN_*` keys → `nvram commit` → `stop_wgc`/`sleep 2`/`start_wgc`/`restart_vpnrouting0`/`sleep 3` → verify `ifconfig wgcN` |
| Kill switch on re-negotiation | **preserved**: the script reads `wgcN_enforce` into `$ENFORCE` at the top and writes that value back, defaulting to 0 when the key is unset (always, on stock). It used to write `enforce=1` flat, so a slot created kill-switch-off came back on once the watchdog fired. |
| PIA token request | Uses `$CURLB` (no `--fail`) so an error body survives to be logged, with the status from `-w '%{http_code}'`; the body goes to `$TMPTOK` and is removed as soon as it is parsed. A 403 here is PIA refusing the request, not a script fault - it has been seen after sustained re-registration. |
| TLS floor | `--tlsv1.2` in `$CURL`. It is a MINIMUM, not a pin. `--tlsv1.3` made every addKey call fail with curl exit 35: PIA's addKey endpoint on :1337 does not offer 1.3, though the token and server-list hosts do. |
| Error text | BusyBox `tr` has no character classes - `tr -d "[:cntrl:]"` deletes literal c/n/t/r/l/[/]/: instead. Sanitise with `head -n 1 ... | cut -c1-160`. |
| Curl from cron | **ASUS's curl refuses to run with `crond` in its live process ancestry**: exit 0, no status, no body, no stderr, `Invalid caller(crond)` in `/jffs/curllst`. A cron run therefore re-execs itself detached and waits for `PPid` 1 before doing anything. `deploy` runs over SSH are not detached. Measured 2026-09-09; ARCHITECTURE.md "curl refuses to run from cron". |
| Curl hygiene | `echo -n > /jffs/curllst` after every curl and in `abort()` — `/usr/sbin/curl` logs every command line, including the token request's `-u user:password`, to that world-readable file |
| Version drift | The app updates from the store; the deployed script only changes on a deploy. Every run logs `Watchdog started for wgcN [script <ver>]`, and `getWatchdogStatus` logs the deployed version beside `appVersionLabel` to both the app log and syslog, adding “redeploy the watchdog to update it” on a mismatch. An UNKNOWN version is not a mismatch. |
| Alerts | `send_alert <SUCCESS\|FAILED> <event detail>` when `wgcN_wd_email_enabled=1`; same SMTP diagnostics as `testEmail` |
| Size | The deploy writes the script in ~4 KB chunks (`heredocWriteCommands`: `cat >` then `cat >>`), because **dropbear refuses an exec request over `MAX_CMD_LEN` = 9000 bytes** and drops the connection - which it did at 9055, mid-deploy, after the slot was already enabled. Never send the script as one command. `router_watchdog_unit_test.dart` caps BOTH firmware variants at 26 KB (raised 9500 -> 24576 -> 26624), for JFFS space and reviewability rather than SSH. It used to require stock to be no larger than Merlin; that stopped holding in 420, when stock gained three branches of kill-switch wording Merlin has no need of. |
| Write verification | `_writeScript` compares `wc -c` against the expected byte count and throws. Without it a failed write left cru entries pointing at a script that did not exist, and the app called that ACTIVE. |

**Why a ladder.** PIA answers **HTTP 403** after sustained re-registration and clears on its own after tens of minutes; retrying every 120 s indefinitely is what provokes and prolongs it, and with two watchdogs that was a request a minute between them. A single failure - the common case - is exactly as responsive as it was before. The cap is a ceiling, not a starting point for tuning upward: a genuinely broken tunnel does take longer to recover once it has failed repeatedly, and that is the trade being made.

The failure email's `Attempt:` row names whichever of the backoff and the next cron tick comes later (`NEXTWAIT` vs `TICK`), so it never promises a retry sooner than one can happen.

### 4.8.1 Alert and test email layout

**One layout, two languages.** Alert bodies are written in shell by the deployed script; the test email is written in Dart by `testEmail`. Everything both must agree on lives in constants in `router_watchdog.dart` - `kSectionWhatHappened` / `kSectionWhatToDo` / `kSectionRouter` / `kSectionHistory` / `kSectionRouterLog`, `kEmailWhatToDo`, `kEmailReviewLine`, `kEmailSignOff`, `kPlayStoreUrl` - and the script's copy is generated from them by `_echoBlock`, so the two cannot drift. `test/unit/email_layout_test.dart` asserts it.

Section order is the answer first, the action second, the evidence last: `WHAT HAPPENED`, `WHAT TO DO` (failures only), `ROUTER`, `HISTORY`, `ROUTER LOG (last 10 lines)` (failures only), then the review ask and sign-off. **Plain text only** - mailsend-go sends the file verbatim and the Merlin path declares `text/plain`, so `<br>` or a markdown link reaches the reader literally. Lines are left unwrapped for the client to fold, and values are never space-padded into columns because Gmail on Android renders `text/plain` in a proportional font.

A row whose value is empty is **dropped**, never printed as a dangling label - `row()` in the script, the `.where((r) => r.isNotEmpty)` filter in `buildEmailBody`.

Subject: `<wgcN_wd_email_subject>: <SUCCESS|FAILED|TEST email> - wgcN:<region>`. The user's own subject stays the prefix (default `cfg-pia-wg alert`), so anyone who changed it keeps their mail rules; the slot and region are appended so a client threads by VPN.

**The deploy waits for the interface.** `enableVpnSlot` issues its service call through `notify_rc`, which queues and returns at once - so the interface is not up when it returns. The deploy used to exec the script about a second later, find "Interface wgcN is down or absent" and perform a full reconfigure, costing a PIA token and an `addKey` on **every** deploy. `RouterWatchdog._awaitInterfaceUp` now polls first (`verifyPollInterval` x `verifyMaxAttempts`, injectable), and a slot that never comes up still deploys - the script rebuilds the tunnel, which is what it is for.

**Run mode.** `deployWatchdog` runs the script as `<path> deploy`; cron passes nothing. The script reads `RUNMODE="${1:-cron}"` **at the top**, because `send_alert()` shadows `$1` with its own argument. A deploy run reports itself as a deployment rather than a re-configuration, and emails **even when it finds the tunnel already healthy** - that email is the user's proof that alerting works. On that path no addKey ran, so the endpoint comes from `wgcN_ep_addr`/`_ep_port` and there is no server name or latency to report.

**A deploy is not a reconfigure.** `bump()` returns early when `RUNMODE=deploy`, so neither `cfg_pia_wg_reconfig_ok` nor `_fail` counts a deployment - they used to climb every time a watchdog was saved. The email says `Event: watchdog deployed` whichever path the run took, and omits the outage and attempt rows.

**Times carry a numeric offset (`%z`), never a zone name.** Cron inherits `TZ` from init - `/etc/TZ` on ASUS, a POSIX string like `UTC-10DST,...` that literally names the zone "UTC" while offsetting +10 - so cron-fired alerts labelled a correct local time as UTC. A dropbear login shell sets no `TZ` and falls back to `/etc/localtime`, which is why manual runs looked right. Do not "fix" this by exporting `TZ` from nvram: it is the same string.

**Undeliverable alerts are counted, not resent.** `/tmp/watchdog_unsent_wgcN` holds a count and a timestamp; the next email that gets through reports them and clears it. An alert about lost connectivity is the one most likely to be undeliverable - a downed default tunnel takes DNS with it.

**Kill switch has three states, not two:** ON, `OFF - the kill switch is available but is not enabled` (Merlin), and `none on this firmware` (stock, which has none). Baked per firmware as `KILLSW_UP` / `KILLSW_FIXED` / `KILLSW_DOWN` - three tenses, because the same fact reads wrong in the wrong one: the tunnel is up on a deploy run, was down on a recovery, and is still down on a failure. A failure takes the still-down wording whether or not the run was a deploy.

**Stock does not assert a leak (420).** It used to say `traffic is reaching the internet without the VPN` whatever the router's state, which is wrong two thirds of the time: a device pinned to a dropped tunnel falls through to the DEFAULT CONNECTION, and that is either this same slot (its devices have NO internet - fail-closed), another tunnel (still on a VPN, and the email names it), or the plain internet (the only actual leak). The script reads `vpnc_default_wan` plus its own index 6 from `vpnc_clientlist` and picks one of three, so nine sentences in total. Do not collapse them back: a warning that cries wolf twice for every time it is right is one people learn to ignore.

**Outage duration** comes from `$STATUSFILE`, which now leads with an epoch (`date '+%s %Y-%m-%d %H:%M:%S'`) so `down_for()` can subtract. It is measured **before** the file is re-stamped, or every outage reads zero. The file lives in `/tmp`, so after a reboot there is nothing to subtract from and the email says `unknown (no successful check since the router last rebooted)` rather than inventing a duration. `parseLastPing` skips the epoch prefix and still reads a file written by an older build.

The `ROUTER LOG` excerpt can contain the **PIA username** (`Requesting PIA token for user ...`). It never contains the password or the token - the script logs the token's *length*. A deliberate choice, since these emails traverse the user's own mail provider.

### 4.8.2 The shared SSH connection

Every action used to open its own connection: socket, handshake, password auth, a few commands, close. That is a `dropbear[NNNN]: Password auth succeeded` line in the router log per button press, and a handshake's latency before anything visibly happens. `RouterSession` holds one connection for the life of the session instead.

**The property that had to be replaced.** A fresh client per action meant a dropped connection self-healed, because the next action simply connected again. That was real, and reuse throws it away unless it is put back deliberately - so `RouterSession.run` reconnects once and retries when `isConnectionLost(e)`. Without that we would have traded dropbear noise for intermittent action failures, which is a worse bug and a harder one to see. `service restart_vpnc` and `restart_firewall` can take the session down mid-action, so this path runs in normal use, not just in disasters.

**What is NOT retried.** Only transport failures - `SSHStateError`, `SSHAuthAbortError`, and messages containing closed / connection reset / broken pipe / socketexception. `client.run` returns a failing command's output rather than throwing, so a throw is nearly always transport-level, but "nearly" is the point: re-running `nvram set` or a heredoc append because of an error we did not understand is worse than the original failure. A retried chunked append would double the file, which `_writeScript`'s byte-count check catches and reports.

**Liveness is not `isClosed`.** It only goes true after a clean close, so a connection the router silently dropped still reports itself open - and the test fakes route it through `noSuchMethod`, where it throws. A failed command is the honest test, which is what the retry is for.

**Credentials key the session.** `SessionController.routerSession` rebuilds it whenever router IP, SSH username or password change; reusing a connection authenticated as someone else, or to a different box, would silently ignore what the user just typed.

**Teardown.** `wipeAll()` closes it, so every existing exit path already tears it down, and `AppLifecycleState.paused` closes it too - an authenticated session held open behind a locked screen is a wider exposure than credentials sitting in memory. The next action reconnects.

### 4.8.3 The Play Store review link

The home-screen link opens the **store listing**, not Play's in-app rating card. 406 shipped `InAppReview.requestReview()` and 407 took it out: Play alone decides whether to draw that card, it is quota-limited per user, it never appears on a build Play did not install, and the API reports success either way - the plugin's own code says "the API does not indicate whether the user reviewed or if the dialog was shown". Debug and release both did nothing visible, and no fallback could fire because `isAvailable()` was true. Google's guidance is not to put that flow behind a button at all. `requestReview` would be right for an *unprompted* ask - after a successful watchdog deploy, say - and `review_service.dart` is where it would go back.

The whole line is the tap target (a `GestureDetector` with `HitTestBehavior.opaque` and 8px of vertical padding), not just the underlined glyphs: a `TextSpan` recogniser fires on nothing else, and 12px of centred text is a small thing to hit.

**Test the tap, not the recogniser.** The tests that shipped with the broken link called `recognizer.onTap!()` directly, which bypasses hit-testing entirely - they would have passed against a link nobody could reach. `test/screens/main_menu_screen_test.dart` now uses `tester.tap`, including one tap deliberately off to the side of the centred text.

### 4.9 NVRAM variables

**Per-slot WireGuard (`kSlotNvramKeys` in `router_slot_service.dart`) - `wgcN_` prefix, N = 1..5:**

```text
addr  alive  desc  dns  enable  enforce  ep_addr  ep_addr_r  ep_port
fw  mtu  nat  ppub  priv  psk  rip  aips
```

What each one means to the firmware is in
[ARCHITECTURE.md, Field reference](../ARCHITECTURE.md#field-reference), which is the authority and
the version a user reads. Only what the APP does with them belongs here:

- **Four are read-only** in `SlotParamsEditor`: `enable` (ENABLE and DISABLE own it), `ep_addr_r` and `rip` (the firmware fills them in) and `psk` (PIA does not use one). Ten text fields and three switches are editable, and SAVE stays disabled until all ten text fields are non-empty.
- **`desc` is `pia-` + the PIA region id** (`pia-aus_melbourne`). The prefix is what marks a VPN as this app's among any others on the router, and the watchdog re-reads the region from it on every reconfigure - so a slot renamed by hand can no longer be rebuilt.
- **Three are Merlin-only** (`kMerlinOnlySlotKeys`): `enforce`, `fw`, `rip`. Writing them on stock creates keys nothing reads, and DELETE does not clean them up.

**Per-slot watchdog (`WatchdogConfig.toNvram`) — `wgcN_wd_` prefix:** `check_interval`, `primary_ip`, `secondary_ip`, `email_enabled`, `email_from`, `email_to`, `email_subject`, `smtp_server`, `smtp_user`, `smtp_pass`.

`wd_primary_ip` / `wd_secondary_ip` are **shared**: written by `RouterSlotService.writeWatchdogPingTargets` during manage-ENABLE, read by both the ENABLE check and the router script, and unset by both `deleteSlot` and `stopWatchdog`.

**Global (not slot-scoped):** `cfg_pia_wg_user`, `cfg_pia_wg_password` — plaintext PIA credentials shared by every slot's watchdog. `cfg_pia_wg_sdate` (`yyyy-mm-dd` the app first configured this router), `cfg_pia_wg_reconfig_ok` and `cfg_pia_wg_reconfig_fail` — lifetime re-configuration counters across all slots, reported in the HISTORY section of every alert email. The three are seeded together by whichever of a watchdog deploy or a test email happens first (`kSeedCountersCommand`) and incremented by the router script's `bump()`, which commits once per alert — never per check, because `nvram commit` writes flash. Also read: `3rd-party` (firmware detection), `jffs2_scripts`, `jffs2_on` (Merlin only), `vpnc_clientlist` (stock only), and for email bodies `ddns_hostname_x`, `lan_hostname`, `lan_ipaddr`, `productid`, `buildno`, `extendno`.

**Stock `vpnc_clientlist`.** The schema, the field numbering and the three different numbers that
name one profile are in
[ARCHITECTURE.md, Stock `vpnc_clientlist`](../ARCHITECTURE.md#stock-vpnc-clientlist). What the app
writes into a record it creates: the region id at field 1, `WireGuard` at field 2, the slot number
at field 3, the active state at field 6 (ENABLE / DISABLE / CREATE all write it), `10 - slot` at
field 7 and `Web` at field 12. **Fields 4, 5 and 8-11 are left empty when creating and preserved
byte-for-byte when updating** - the app must never assume it knows what a field it does not
understand is for. Field 7 is the number the `vpncN_*` runtime keys are indexed by, so wgc1 leaves
`vpnc9_*` behind.

Modelled by `VpncRecord` + `parseVpncClientlist` / `serialiseVpncClientlist` / `buildVpncRecord` / `upsertVpncRecord` / `removeVpncRecord` in `router_slot_service.dart` (all pure).

**`wgcN_desc` on stock** is not a real firmware field. The app writes it anyway as a key of its own, mirroring `vpnc_clientlist` index 0, because the router-side watchdog script needs the region name from a bare `nvram get` — the same practice already used for the invented `wgcN_wd_*` keys. Both copies are kept in step by `createConfigToSlot` and `writeSlotParams`.

### 4.10 About screen & build info

`loadBuildInfo()` returns 13 fields; `_BuildInfoBlock` renders the version/build line plus 9 rows: Built by (`installer` + `buildTimestamp`), Build type, Commit hash, Git branch/tag, Build runner ID, CPU Architecture (ABI), Target Android version, Compile SDK, Kotlin. **`commitDate` is parsed but never displayed.** Any field the host omits shows `unknown`; while the channel is in flight every value shows `...`.

Values come from `android/app/build.gradle.kts` (`buildConfigField` for `BUILD_TIMESTAMP`, `GIT_COMMIT_HASH`, `GIT_COMMIT_DATE`, `GIT_BRANCH`, `CI_RUNNER_ID`, `COMPILE_SDK`, `KOTLIN_VERSION`) plus device-side facts added by `android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt`.

Links, in order: ReadMe, Change log, Security policy, Privacy policy, plus an `Open source: licenses` link opening `_LicensesDialog` (dark-themed `LicenseRegistry` list).

### 4.10a Edge-to-edge (Android 15+)

- `flutter.targetSdkVersion` is **36**. Android forces edge-to-edge from SDK 35 and gives no opt-out at 36; Flutter enables it on every Android version anyway (`SystemUiMode.edgeToEdge` is the framework default). So there is nothing to call in `MainActivity` - `enableEdgeToEdge()` would be redundant - and nothing in the manifest or either `styles.xml` sets `statusBarColor` / `navigationBarColor` / `windowOptOutEdgeToEdgeEnforcement`.
- Insets are the layout's job. `AppChrome` uses **two** `SafeArea`s, not one: the header (`AppHeaderBar`) draws `kSurface` to the top of the window and insets its own content, and `MediaQuery.removePadding(removeTop: true)` + `SafeArea(top: false)` around the navigator takes the bottom edge and landscape cutouts. Do not collapse them back into one - that puts a `kBg` strip above the header. **The `removeTop` is load-bearing**: `showDialog` wraps its child in a `SafeArea` (`useSafeArea` defaults true), so a top padding left in the navigator's `MediaQuery` insets a second time and a full-screen dialog opens a status-bar-height band below the header, with the screen behind showing through. `AppDrawer` has its own `SafeArea`; Material's `SnackBar` brings `SafeArea(top: false)` itself.
- `kSystemOverlayStyle` (an `AnnotatedRegion` above the `Scaffold`) makes both bars transparent with light icons. `MaterialApp` already pushes `SystemUiOverlayStyle.light` for a dark theme (material/app.dart `_themeBuilder`), so the icons are not the point - the transparency is, and the region re-applies every frame where MaterialApp's call is one-shot. `systemNavigationBarContrastEnforced` is left at its default on purpose.
- `RenderView._updateSystemChrome` samples the annotation at the centre of each bar, so a full-screen region wins over an `AppBar` inside a dialog.
- `test/widgets/edge_to_edge_test.dart` drives this with `tester.view.padding` / `viewPadding` (`FakeViewPadding`). Three of its cases pass against the old single-`SafeArea` layout too - they are regression guards, not proofs.

### 4.10b Dialogs that contain fields

**A LONG form belongs on a page, not in a dialog.** `WatchdogDialog` shipped the same bug twice - 409 and again in 412 - with SAVE and its spinner below a fold that would not scroll, because a shrink-wrapping `SingleChildScrollView` inside an unbounded card has no overflow to scroll and no arithmetic makes it. It is now an `AppScaffold` page, where the scroll view sits in an `Expanded` and therefore has a bounded viewport by construction. Reach for a page whenever the form is longer than a few fields.

For a SHORT form that is genuinely a detour, use `_FormDialog` (`slot_modal.dart`) or the same structure by hand - `Dialog` > `ConstrainedBox(maxWidth: 480)` > `SingleChildScrollView` > `Padding` > `Column`, with the buttons as the last row of the scrolling column. **Width only**: the height must come from the incoming constraints, since inside the chrome the Scaffold has already taken the keyboard off the body and any cap computed from the screen height is too big. `SlotParamsEditor` still does this.

The chrome's header takes ~104 logical px off the top, so with a keyboard up a dialog only gets `screen - header - keyboard` (on a 731-tall phone with a 436 keyboard that is ~166 px). It scrolls; that is the space there is while the header stays above dialogs.

**Never `AlertDialog` for a form.** It puts `content` in a `Flexible`; inside the app chrome the Scaffold has already removed the keyboard's height from the body (`removeViewInsets`) and shrunk it, and there that Flexible resolves to zero height - the fields paint outside the card and overflow, leaving only the actions row visible. `scrollable: true` does not help; the scroll view collapses the same way. A keyboard test that pumps the dialog on its own will NOT catch this: it lays out correctly when the route sits outside the resizing Scaffold. Drive the whole app (`test/widgets/edge_to_edge_test.dart`).

### 4.11 Errors, logging, clipboard

- `AppErrors.inputs(list)` — one dialog titled *"Please correct the following"* with bullets; no-op on empty.
- `AppErrors.system(msg)` — title *"Error"*; a new error pops any error dialog already open.
- Both log every message with `isError: true` first, and bracket the dialog with `enterModal`/`exitModal`.
- `LogPanel` colours: success → white + check icon, error → `kError` + error icon, otherwise `kHighlight` + info icon. Empty log renders `Ready.`
- `LogPanel` renders the whole log as ONE `Text.rich` inside a `SelectionArea`, entries separated by `' '`, icons as `WidgetSpan`s. Never a widget per entry: `SelectionArea` joins separate widgets' text with no separator, so that layout copies as one run-on line. Same trap as the About screen's build info block; a placeholder splits the paragraph into selectable fragments but adds no character to the copy.
- Clipboard: `copyToClipboard` arms a 60 s deadline; the 1 Hz tick clears it and logs `Clipboard auto cleared.` Clearing goes through `clipboard_service.dart` -> `ClipboardManager.clearPrimaryClip()` on the host, NOT a write of `''`: Android shows its clipboard preview for any copy, so the old clear flashed a "copied" popup on exit and at expiry. The write is kept as the fallback for API 24..27 (no `clearPrimaryClip()`) and for tests with no handler. `_defaultClipboardWriter` routes an empty write to it, so the injected-writer seam every test uses is unchanged. The deadline is for SECRETS only - pass `armAutoClear: false` for anything else (the watchdog log's COPY does), which both skips arming and stands down a deadline left by an earlier secret copy, since that secret has just been replaced on the clipboard.

### 4.12 Security posture (as implemented)

| Claim | Reality |
| --- | --- |
| Credentials on the device | Volatile only — `SessionController` fields, wiped by `wipeAll` on every exit path. No `SharedPreferences`, no secure storage, no database. |
| Non-credentials on the device | Exactly one: the router LAN address, in `router.txt` under the app support directory, written only after a connect succeeds and clearable via ABOUT -> FORGET ROUTER IP. See 4.2.1. Nothing else is persisted, and a test enforces that. |
| Generated config on the device | In memory, **except** SHARE, which writes `pia-<region>.conf` to the temp dir and deletes it in a `finally`. |
| Credentials on the router | PIA username/password go to router NVRAM in **plaintext** (`cfg_pia_wg_user`/`_password`) whenever a watchdog is deployed; SMTP password likewise (`wgcN_wd_smtp_pass`). Removed by `stopWatchdog`. |
| Password managers | Every credential field declares `autofillHints`, and each login is its own `AutofillGroup` - PIA, router SSH, SMTP - so a provider cannot conflate them or save one mixed entry. Groups use `onDisposeAction: cancel`; `TextInput.finishAutofillContext()` is called ONLY after a successful generate or connect, so a save prompt appears only for credentials that have been proven. `FLAG_SECURE` does not block the autofill overlay (verified on a Pixel with KeePass, which also switches cleanly between several entries saved against the app's package id). Android only suggests for an EMPTY field, so the `admin` default in the SSH username field suppresses its prompt until cleared - documented in README 5.2, not changed. Autofill needs API 26; `minSdk` is 24, so a 24/25 device just types as before. |
| Screen capture | `FLAG_SECURE` in `MainActivity.onCreate` blocks screenshots, screen recording and the Recent Apps preview - **release builds only**. A DEBUG build skips it so the app can be captured on a device while testing, and `allowScreenCaptureInRelease` is a manual escape hatch for capturing a release build. `test/unit/clipboard_service_test.dart` fails if the gate widens or the hatch is left on. |
| TLS | PIA `addKey` is CA-pinned (`withTrustedRoots: false`) with a CN check; SMTP uses `openssl s_client -tls1_3 -verify_return_error`. |
| Shell injection | All interpolated user values go through `shellSingleQuote` — **except** `createConfigToSlot`, which uses `"…"` double quotes for the parsed-config values (`createConfigToSlot`). |

### 4.13 Firmware detection & the stock branch

**Interim design, deliberately.** Every difference is an `if (isStockFirmware) … else …` inside the existing classes. There is no `FirmwareService` / `RouterCommandStrategy` abstraction yet — that is a later release. `lib/firmware.dart` is the seam to delete when it lands.

**Detection** runs on entry to either router screen (`RouterSlotsScreen._checkFirmware`), once per app session — the answer is cached in a library global, not on `SessionController`, because `RouterSlotService` and `RouterWatchdog` have no controller. It must precede `fetchSlots`, whose reads differ per firmware.

| `nvram get 3rd-party` | Verdict |
| --- | --- |
| contains `merlin` (any case) | Merlin |
| empty (the key does not exist on stock) | stock |
| any other value | unsupported → `showUnsupportedFirmwareNotice`, flag left **unset** |
| non-zero exit / SSH error / 5 s timeout | `AppErrors.system`, flag left **unset** (next entry retries) |

**Stock precondition:** `jq` must exist at `/jffs/cfg-pia-wg/jq`; the watchdog screen additionally requires `/jffs/cfg-pia-wg/mailsend-go` (manage mode never sends email). Missing binaries → `showMissingBinariesNotice`, back to the connect screen.

**What differs on stock:**

| Concern | Merlin | Stock |
| --- | --- | --- |
| Region + active state | `wgcN_desc`, `wgcN_enable` | `vpnc_clientlist` indexes 0 and 5 (plus the `wgcN_desc` mirror and `wgcN_enable`) |
| Per-slot keys written | all 17 | 13 — `enforce`, `fw`, `ep_addr_r`, `rip` skipped (`kMerlinOnlySlotKeys`) |
| Region name read from | `wgcN_desc` | `vpnc_clientlist` index 0, falling back to `wgcN_desc` when the row is missing — so ANY path that creates or renames a slot must call `RouterSlotService.writeVpncProfile`, the watchdog deploy included. Without the fallback a slot missing its row reads as unconfigured and the modal greys out every button that needs a description. `_setVpncActive` carries the description too, so enabling repairs a nameless row. |
| Enable verification | interface present, then a WireGuard handshake, then ping (fatal) | interface present, then a WireGuard handshake (the gate); the ping is logged only - it pings from the tunnel's source address but routes over the WAN, so it answers OK for a tunnel the peer never answered |
| Watchdog ACTIVE means | cron entry **and** `[ -s <script> ]` (paths come from `watchdogScriptPath` in `firmware.dart` - never build a router command with `\$kSomething`, the shell expands it to nothing and a test now fails on it), in both `fetchSlots` and `getWatchdogStatus` - never the NVRAM settings, which survive a DISABLE and a failed deploy alike |
| Watchdog start / stop of the tunnel | `service start_wgc N` / `stop_wgc N` | `nvram set vpnc_unit=<row>` + `service restart_vpnc` / `stop_vpnc` (`RouterSlotService.runVpncService`) — the same calls MANAGE makes. The Merlin commands are inert on stock. |
| Kill-switch badge / editor controls | shown | hidden (no `enforce` field) |
| `jq` | `which jq` | `/jffs/cfg-pia-wg/jq` |
| Mail transport | BusyBox `sendmail` + `openssl s_client` | `mailsend-go` (credentials on the command line — accepted risk) |
| Script directory | `jffs2_scripts=1` / `jffs2_on=1` | `mkdir -p /jffs/scripts` |
| Cron persistence | append to `/jffs/scripts/services-start` | rewrite the REPLACEMENT block of `/opt/etc/init.d/S50downloadmaster`, then run it with `start`; also stub out `S50asuslighttpd` |
| Enable a slot | `service "start_wgc N"; service restart_vpnrouting0` | set `vpnc_unit`, then `service restart_vpnc` (there is no `start_vpnc`) |
| Disable / delete / revert | `service "stop_wgc N"; service start_vpnrouting0` | set `vpnc_unit`, then `service **stop_vpnc**` |
| Concurrent tunnels | unlimited (no cap key exists) | capped by `vpnc_max_conn` (default 2); the third ENABLE is refused with a dialog |
| Watchdog script path | identical on both (`/jffs/scripts/watchdog_wgcN.sh`) | |

**`vpnc_unit` is the 0-based ROW INDEX of the slot's record in `vpnc_clientlist`** — see `vpncUnitForSlot` in `router_slot_service.dart` and ARCHITECTURE.md "Stock". It is *not* `5 - slot`: the WebUI can only create profiles in slot order 5,4,3,2,1, so on any list it built the two happen to agree, but the app lets the user pick any slot. All four stock service calls go through `RouterSlotService._runVpncService`, which resolves the row and throws an actionable error on enable when the slot has no profile (a stop is a silent no-op instead). **Ordering is load-bearing:** resolve the unit *after* the upsert that may append the row (enable) and *before* the removal that drops it (delete).

**`restart_vpnc` does not stop a tunnel.** It clears `wgcN_enable` and `vpnc_clientlist` index 5 — so the WebUI reports "disconnected" — while the interface stays up in `wg show interfaces`. Stock disable/delete/revert must use `stop_vpnc` (ARCHITECTURE.md "Stop/Disable").

**S50asuslighttpd** is the sibling init script, run by the same triggers and again on **every VPN up or down**. Its `sleep` calls stall the boot outright when the router starts with a VPN enabled, and nothing in it is wanted, so a deploy replaces it with a stub that exits 0 immediately. **Both scripts are copied to `<path>.old` first**, guarded so the backup is only ever taken of the ORIGINAL: the file must exist, `.old` must not, and the file must not already contain the app's own marker. Best-effort - a failed copy does not fail the deploy. ARCHITECTURE.md "The second init script".

**S50downloadmaster** is a stock init script the firmware already runs at boot and on a firewall restart; stock has no `services-start` and bare `cru` entries do not survive a power cycle, so the app hijacks it. Only the region between the two REPLACEMENT markers is ever rewritten, and it accumulates one check + one rotate line **per watchdog** (one today, several later). `stopWatchdog` rebuilds the file with that slot's lines dropped rather than `grep -v`-ing them out, so the stock scaffolding survives; the file itself is never deleted.

**Watchdog script generation.** The deploy heredoc has a practical size ceiling (~8.3 KB in production), so the script carries **no runtime firmware branching**. `buildWatchdogScript` resolves four placeholders at build time: `__SLOT__`, `__JQ__` (into a `JQ=` variable every call site reads), `__MAILBODY__` and `__MAILCMD__`. A unit test asserts no placeholder survives on either firmware and that the stock variant is no larger than the Merlin one.

**Tests.** The detection flag is a library global, so any suite touching router code must reset it — use `useMerlin()` / `useStock()` / `resetRouterFirmware()` from `test/watchdog_test_utils.dart`. A leaked flag produces confusing cross-file failures under parallel workers.

Note: ignore all .claude\plan_*.md files, they are historical and not part of the current codebase. This .claude\CONTEXT.md file is the authoritative source for doc-vs-code discrepancies.

### 4.14 Device assignment (stock only)

Three files, split the way the rest of the app is: `device_assignment.dart` is pure and has no SSH in
it, `device_assignment_service.dart` does the I/O, `widgets/device_assignment_screen.dart` is the
screen. **Merlin routes per device through VPN Director, which this app does not drive**, so the
screen detects the firmware itself on entry and refuses with an explanation. It detects rather than
trusts: `routerFirmware` defaults to Merlin until something probes it, and reaching this screen
first told a stock user their router was Merlin.

**One read, eight sources.** `DeviceAssignmentService.read()` sends a single marker-separated command
and splits the reply: `vpnc_clientlist`, `vpnc_dev_policy_list`, `vpnc_default_wan`,
`dhcp_staticlist`, `custom_clientlist`, `cfg_device_list`, `/jffs/nmp_cl_json.js`,
`/tmp/nmp_cache.js`. No source is complete on its own - liveness comes only from `nmp_cl_json.js`,
addresses only from `nmp_cache.js` or `dhcp_staticlist`, the user's own name for a device only from
`custom_clientlist`, and the router and its mesh nodes are identified only by `cfg_device_list`.
`buildDeviceList` is the join. Written out as eight named commands rather than a loop, because a
lower-case shell variable in a Dart string is indistinguishable from the escaped-constant mistake
`no_escaped_constants_test.dart` exists to catch.

**A record is keyed by IP, so a device with no known address cannot be assigned at all.**
`LanDevice.assignable` is false for it and the row says so instead of offering a picker.

**Read the index, never mere presence.** `assignedIndexFor` returns null for a record whose index is
`0` - that device is on the default connection, not on a VPN. `AssignmentState.profiles` holds every
`vpnc_clientlist` profile, WireGuard or not, so a device pinned to an OpenVPN profile can be shown
honestly rather than reported as unassigned and silently reassigned on the next write.

**Changes are STAGED on the session, not in the State.** `stagedAssignments` / `stagedDefaultIndex`
live on `SessionController` because the screen's `State` is rebuilt on every entry - a glance at the
log used to discard everything the user had picked. `clearStagedAssignments` runs after a successful
apply.

**`apply()` re-reads and refuses on conflict.** The router's own web interface rewrites the WHOLE of
a list from the copy its page loaded, so `AssignmentState.rawPolicyList` / `rawClientlist` are kept
verbatim and compared before anything is written; a mismatch throws `AssignmentConflictException`
rather than overwriting a change made elsewhere.

**The write order matters, and so does the cleanup.** Reservations first (an assignment is keyed on
an address, so the address has to be pinned), then the policy list, then `nvram commit`, then the
LIGHT pair - `restart_dnsmasq` and `restart_vpnc_dev_policy`. The web interface uses
`restart_net_and_phy` for the same job, which bounces every switch port and re-leases the WAN; the
app never needs it. Then `_clearStaleRules`: **stock never removes a device's previous `ip rule`**,
both sit at priority 100 and the older one wins, so an assignment that was written perfectly has no
effect. `staleRuleTables` finds them and the service deletes them by hand.

**Changing the default connection is the expensive one**, and it is a separate step at the end.
`_setDefaultConnection` runs the measured sequence, waits on the interface and on the NVRAM key
rather than sleeping, and the screen warns first: every tunnel on the router stops and restarts.

Each reassignment is also written to the router's own syslog with `buildLoggerCommand`. The app log
dies with the app; a line explaining a device's traffic weeks later has to survive somewhere.

Full firmware detail, including the schema of both lists and the three numbers that name one profile:
[ARCHITECTURE.md, Device assignment (stock)](../ARCHITECTURE.md#device-assignment-stock).
