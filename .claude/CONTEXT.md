# CONTEXT.md

Android (Flutter) app that provisions Private Internet Access WireGuard configurations and manages PIA WireGuard slots + a self-healing watchdog on an ASUS / Asus-Merlin router over SSH.

## 1. Working agreements

- **Tests are required for every change.** 29 test files live under `test/` (`test/`, `test/screens/`, `test/widgets/`, `test/unit/`). Run `flutter test`; coverage is tracked via `coverage/lcov.info`. Every widget that a test needs to reach already carries a `Key` (`snake_case`, e.g. `Key('slot_create')`, `Key('wd_save')`) — add one when you add a control.
- **Test coverage.** This app requires a minumum 80% code covered by tests.
- **Update this file in the same change as any architecture or behaviour change.** A change that moves a file, renames a destination, alters a button set, or adds/removes an NVRAM key must edit the matching section here.
- **Flag conflicts, do not silently resolve them.** If this file disagrees with the code, or with `ARCHITECTURE.md` / `BACKLOG.md` / a `.claude/plan_*.md`, say so and ask. Do not "fix" the code to match the doc or vice versa without confirmation.
- **CHANGELOG.md entries must be flat and short.** The release GitHub Action *sorts* the lines within a release block, so an indented sub-bullet is separated from its parent and ends up under the wrong entry. Every line item is therefore a standalone top-level `- ` bullet that reads correctly on its own, in the existing `- FIX:` / `- CHG:` / `- ADD:` / `- TST:` / `- DOC:` / `- INF:` style. Keep each to a sentence or two — detail belongs in the code comments or `ARCHITECTURE.md`, not here.
- Do not read `.claude/plan_*.md` as current state — they are historical design notes.

### Conventions in force (observed, not aspirational)

| Area | What the codebase actually does |
| --- | --- |
| Lint | `package:flutter_lints/flutter.yaml` (`flutter_lints ^6.0.0`), **no custom rules enabled or disabled**. `analyzer.exclude` drops `build/`, `android/`, `ios/`, `web/`, desktop dirs. |
| Line length | 130 (`.vscode/settings.json` `dart.lineLength`, `.prettierrc` `printWidth`). Format on save via Dart-Code. **This file is exempt** - one logical unit per line, however long. Do not re-wrap it; a hard-wrapped table row breaks the table. |
| State management | No package. `SessionController extends ChangeNotifier`, published through the `SessionScope` `InheritedWidget`; subtrees that must repaint wrap `ListenableBuilder`. Screens are `StatefulWidget` + `setState` for local form state. **No Provider/Riverpod/Bloc — do not introduce one.** |
| Dependency injection | Constructor-injected nullable factories used purely as test seams: `PiaService? service`, `Future<SSHClient> Function(...)? testClientFactory`, `RouterSlotService Function(SSHClient)? slotServiceFactory`, `RouterWatchdog Function(SSHClient)? watchdogServiceFactory`, `SessionController? controller`, `PiaService({int probePort})`, `RouterSlotService(..., verifyPollInterval, verifyMaxAttempts)`. Follow this pattern instead of a service locator. |
| Error handling | Services `throw`; UI catches, strips `'Exception: '`, and routes through `AppErrors.system` (one at a time) or `AppErrors.inputs` (batched). Every error is also appended to the app log. Router mutations are additionally wrapped by `RouterWatchdog._guard`, which logs to the app log **and** the router syslog before rethrowing. Best-effort side calls (`_logRouter`, ping helpers) swallow with `catch (_)`. |
| Async + UI | Every `await` across a widget boundary is followed by a `mounted` check. Spinners are cleared **before** awaiting a modal (a spinner must never animate under a dialog) — see `slot_modal.dart:99-104`. |
| SSH lifetime | One short-lived `SSHClient` per action (`widget.connect()` → use → `client?.close()` in `finally`), so a dropped connection self-heals on the next action. |
| Licence header | Every `lib/` file opens with the GPL-v3 header block + `Copyright (C) 2026 Andrew Newbury.` Keep it on new files. |
| Colours | Never inline a hex colour in a screen; use the constants in `lib/app_colors.dart`. |

## 2. Snapshot

The app opens on a main menu (`MainMenuScreen`) offering four screens plus "Exit app"; a hamburger drawer rendered *above* the Navigator adds an **About** destination and duplicates the rest. Screen 1 generates a standalone PIA WireGuard config (region → credentials → `GENERATE CONFIG`) with a 60-second clipboard auto-clear and SHARE/SAVE. Screens 2 and 3 SSH into an ASUS router and drive a shared `wgc1..wgc5` slot modal: *manage* mode does CREATE / ENABLE / EDIT / DISABLE / DELETE of WireGuard slots; *watchdog* mode does CREATE-EDIT / DELETE / VIEW ROUTER WATCHDOG LOG and deploys a router-side POSIX-sh watchdog that re-negotiates PIA on ping failure. **Both Merlin and stock ASUS firmware are supported** — the firmware is detected once per session on entry to either router screen and every router command branches on it (§4.13). Screen 4 shows the in-memory app log. All credentials and generated config are volatile — held only in `SessionController` and wiped on every exit path — though PIA and SMTP credentials *are* written to router NVRAM in plaintext when a watchdog is deployed.

## 3. Architecture — `lib/` (26 files)

### Root

| File | Role |
| --- | --- |
| `main.dart` | 23 lines. `void main() => runApp(const PiaWgApp())`; re-exports `PiaWgApp` from `app_shell.dart`. |
| `firmware.dart` | `RouterFirmware` enum, the once-per-session detection flag (a library global — see §4.13), `classifyFirmwareTag()`, `jqCommand()`, and the stock paths (`kStockJqPath`, `kStockMailsendPath`, `kS50Path`, `kServicesStartPath`, `kReadmePrereqUrl`). |
| `s50_template.dart` | `kS50DownloadmasterTemplate` — verbatim LF copy of `./scripts/S50downloadmaster-TEMPLATE.sh` (same mirroring pattern as `license_text.dart`) — plus `buildS50Script()` / `extractS50CruLines()`, which own the block between the REPLACEMENT markers. A test fails if the copy drifts. |
| `app_shell.dart` | `PiaWgApp` (root `StatefulWidget`, `WidgetsBindingObserver`) owns the `SessionController`, `MaterialApp`, `buildAppTheme()`, and installs `AppChrome` via `MaterialApp.builder`. `DestinationObserver` (a `NavigatorObserver`) updates `controller.currentDestination` from its OWN list of page routes, **ignoring non-`PageRoute`s** so dialogs don't change drawer highlighting. It cannot read `previousRoute` on a pop: with a modal open under a pushed page, popping that page reports the dialog, and treating that as "no change" left the destination naming the page just left - the drawer then no-opped on that entry. `didChangeAppLifecycleState(resumed)` → `resyncOnResume()`. Disposes the controller only if it created it. |
| `session_controller.dart` | `AppDestination` enum (6 values), `LogEntry`, `SessionController extends ChangeNotifier`, `SessionScope extends InheritedWidget`, `kDefaultDns`. Holds all volatile state, the 1 Hz clipboard countdown, modal depth, `wipeAll()`. `SessionScope.updateShouldNotify` compares controller identity only, so it does **not** rebuild on every tick. |
| `app_colors.dart` | 13 `const Color` tokens: `kHighlight` teal `#00D4AA`, `kSecondary`, `kBg`, `kSurface`, `kField`, `kBorder`, `kText`, `kMuted`, `kHint`, `kError`, `kOnPrimary`, `kConfigBg`, `kWarn`. |
| `pia_service.dart` | PIA provisioning engine. `WgServer`/`Region`/`ProbeResult`/`RegResponse` models + `PiaService`. Uses `dart:io` `HttpClient` (10 s connect timeout), not `package:http`. |
| `router_slot_service.dart` | `kSlotNvramKeys` (17 keys), `openSshClient()`, `SlotInfo`, `RouterSlots`, `RouterSlotService`: fetch/read/create/enable/disable/delete/write slot params, ping-target NVRAM, `pingViaSlot`. |
| `router_watchdog.dart` | 890 lines. Validation helpers, `WatchdogConfig`, `WatchdogStatus`, pure Bash-template builders, `RouterWatchdog` service, and `_kWatchdogScriptTemplate` (the router-side sh script, ~7 KB heredoc ceiling). |
| `watchdog_dialog.dart` | `WatchdogDialog` — the watchdog CREATE/EDIT form. Its `SAVE` validates, optionally picks a region, WAN-pings both targets (warn-only), then calls `deployWatchdog`. **This is the only path that brings a watchdog up.** |
| `build_info_service.dart` | `BuildInfo` model + `loadBuildInfo()` over `MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/build_info')`, method `getBuildInfo`. One of the app's **two** platform channels. Falls back to `BuildInfo.unknown()` on `MissingPluginException`/`PlatformException` so widget tests render. |
| `clipboard_service.dart` | `clearSystemClipboard()` over `MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/clipboard')`, method `clearClipboard` -> `ClipboardManager.clearPrimaryClip()` (API 28+). Falls back to writing `''` on `MissingPluginException`/`PlatformException`. A test reads `MainActivity.kt` so the names cannot drift. |
| `license_text.dart` | 645 lines. `const String kLicenseText` — verbatim raw-string copy of `./LICENSE` (GPL v3). Regenerate by hand if `./LICENSE` changes. |

### `lib/screens/`

| File | Role |
| --- | --- |
| `main_menu_screen.dart` | 5 buttons + `* requires SSH connectivity` footnote + a "(?) How to use this app" link (`Key('menu_help')`, `kHelpUrl` -> README section 5) + a PayPal/Patreon donation block. `PopScope(canPop: false)` routes the Android back key to `confirmAndExit`. |
| `standalone_config_screen.dart` | Region row / PIA username / password / DNS → `GENERATE CONFIG`; renders the generated config under a `GENERATED CONFIG: pia-<region>` heading (`Key('generated_config_label')`, same stem as the shared `pia-<region>.conf`) with COPY (+ countdown) and SHARE / SAVE. |
| `manage_router_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.manage, …)`. |
| `watchdog_management_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.watchdog, …)`. |
| `log_screen.dart` | `ListenableBuilder` over the controller → `LogPanel` + `CLEAR LOG`. |
| `slot_params_editor.dart` | Modal editor for the 17 per-slot NVRAM values (spec 3.3). |
| `about_screen.dart` | Build info is ONE `Text.rich` with `\n` between rows, not a widget per row — `SelectionArea` joins separate widgets with no separator, so a row-per-widget layout copies as one run-on line. `COPY BUILD INFO` (`Key('about_copy_build_info')`) and `CREATE GITHUB ISSUE` (`Key('about_create_issue')`) share a `Wrap`. The latter opens `bugReportUrl()`: `<repo>/issues/new` with `title` and `body` prefilled, reproducing the headings of `.github/ISSUE_TEMPLATE/bug_report.md` (GitHub honours a template **or** a `body`, never both) and filling Environment with `asPlainText` plus the detected firmware. A test fails if the template's headings drift. `DEL PIA CERT` (`Key('about_del_pia_cert')`) confirms, then SSHes in and runs `RouterWatchdog.deleteCachedPiaCert()`. With no router credentials in the session it asks for them inline via `_SshCredsDialog` (`about_ssh_continue` / `about_ssh_cancel`) and writes them back to the session; ABOUT is reachable without ever visiting a router screen. Takes a `testClientFactory` like the router screens. All three buttons take their own line at phone width - CREATE GITHUB ISSUE alone is 282px of a ~320px body - which is what the `Wrap` is for. COPY writes `_BuildInfoBlock.asPlainText` via `SessionController.copyToClipboard(armAutoClear: false)` - not a secret, so it arms no countdown and stands down one an earlier config copy left running. This is the screen's only `SessionScope` dependency. Whole body wrapped in one `SelectionArea` (drag or Select all copies build info + links + licence together), so its children are plain `Text`, not `SelectableText`. Build provenance from `loadBuildInfo()`, 6 project links, an open-source `_LicensesDialog` (custom dark replacement for `showLicensePage`) whose entries go through `groupLicensesByPackage` — one heading per package, not per `LicenseEntry`, since the registry emits an entry per licence text naming every package it covers, and the full GPL text. The dialog keeps notices as `LicenseParagraph` lists and renders each through `_LicenceParagraph` (`centeredIndent` ⇒ centred + bold, else `16.0 * indent` padding), and carries its own `SelectionArea` — the screen's region does not reach into a dialog route. Hard line breaks inside a notice are already gone before we see it (`LicenseEntryWithLineBreaks` joins a paragraph's lines with a space), so expat's ASCII art reads as run-on text here exactly as it does in Flutter's own licence page. |

### `lib/widgets/`

| File | Role |
| --- | --- |
| `app_scaffold.dart` | `AppChrome` (drawer host + static header, sits above the Navigator so the hamburger stays live under dialogs; carries the app-wide `AnnotatedRegion<SystemUiOverlayStyle>`), `kSystemOverlayStyle`, `AppHeaderBar` (two-line title, author link, `v<version>` from `PackageInfo`), `AppScaffold` (scrollable padded body + optional `HOME` button, teal text and border to match the slot modal's; `fillViewport` for the menu). |
| `app_drawer.dart` | `screenForDestination()`, `navigateToDestination()` (no-op on current; **pushes**, growing the stack by design), `closeApp()`, `confirmAndExit()`, `AppDrawer`. |
| `slot_modal.dart` | 674 lines. `SlotModalMode` enum + `SlotModal` (slot list, badges, mode-dependent button set, all router actions) + `_PiaCredsDialog` + `_PingTargetsDialog`. |
| `router_slots_screen.dart` | Shared router-IP/SSH form + `CONNECT TO ROUTER` for both router screens; auto-reconnects when `routerConnected`; runs the firmware gate (§4.13) before `fetchSlots`; opens `SlotModal`. `_FirmwareGate` carries the outcome so a dialog is only awaited after the connect spinner clears. |
| `firmware_notice.dart` | `showFirmwareNotice` + the two wrappers `showMissingBinariesNotice` / `showUnsupportedFirmwareNotice`. A dismissible warning whose README link is a tappable `TextSpan` (`AppErrors` renders plain text and cannot carry a link). Keys `firmware_notice`, `firmware_notice_link`, `firmware_notice_ok`. |
| `common_fields.dart` | `RegionRow`, `PiaUsernameField`, `DnsField`, `ObscuredField`, `PiaPasswordField`, `RouterIpField`, `SshUsernameField`, `SshPasswordField`, `ClearButton`, `IconActionButton`, `SlotBadge`, `LogPanel`. |
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
```

## 4. Feature reference

### 4.1 Navigation & destinations

| `AppDestination` | `routeName` | `title` | On main menu? | In drawer? |
| --- | --- | --- | --- | --- |
| `menu` | `main_menu` | Main menu | — (is the menu) | yes, as **HOME** |
| `standalone` | `standalone` | Generate PIA WireGuard config | yes | yes |
| `manageRouter` | `manage_router` | Manage PIA WireGuard config | yes (`*` suffix) | yes |
| `watchdog` | `watchdog` | Watchdog WireGuard management | yes (`*` suffix) | yes |
| `log` | `log` | View app log | yes | yes |
| `about` | `about` | About | **no** | yes |

- Menu also has `Exit app` (`Key('menu_close_app')`); drawer also has `Exit app` (`Key('drawer_close_app')`).
- Navigation **pushes** (`app_drawer.dart:51-57`) — the stack grows deliberately so back can retrace.
- Active destination is `kHighlight` (teal) via `ListTile.selectedColor`.
- `SlotModal`'s HOME does `popUntil((r) => r.isFirst)`; `AppScaffold`'s HOME pushes a fresh menu.
- Exit paths (back key on menu, menu button, drawer entry) → `confirmAndExit` → `wipeAll` → `SystemNavigator.pop()`.

### 4.2 Session state (`SessionController`)

| Field | Notes |
| --- | --- |
| `piaUsername`, `piaPassword`, `dns` | `dns` defaults to `kDefaultDns` = `'9.9.9.9, 149.112.112.112'`. |
| `routerIp`, `sshUsername`, `sshPassword` | Router form pre-fills `192.168.0.254` / `admin` on a fresh session. |
| `generatedConfig`, `generatedRegionId` | Survive navigation; wiped by `wipeAll`. |
| `log` (`List<LogEntry>`) | `[HH:MM:SS] msg`, flags `isError` / `isSuccess`. |
| `clipboardSeconds`, `_clipboardDeadline` | 60 s default (`clipboardTimeout`), 1 s tick; `resyncOnResume()` re-evaluates after background. |
| `modalDepth` / `modalsOpen` | `enterModal` / `exitModal`. |
| `currentDestination` | Plain field, set by `DestinationObserver`; no `notifyListeners`. |
| `routerConnected` | Set true after a successful connect; drives auto-reconnect on screen re-entry. |

`wipeAll({reason})` clears all six credential fields, config, `routerConnected`, and the clipboard, then logs. Injectable seams: `clipboardTimeout`, `tickInterval`, `clipboardWriter`.

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

### 4.4 Slot modal button matrix (`slot_modal.dart:520-551`)

`hasDesc` = `wgcN_desc` non-empty; `enabled` = `wgcN_enable == 1` (vpnc_clientlist field 6 on stock); `wdActive` = cron entry present. DISABLE also accepts an interface that is up while the flag reads 0 — the two can disagree, and gating on the flag alone would strand a running tunnel behind a greyed button.

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

**Slot naming.** Every app-log and router-syslog line names a slot as `wgcN:<description>` via `slotLabel` / `fetchSlotLabel` (`router_slot_service.dart`), so a message says *which* VPN it is about. The description comes from `vpnc_clientlist` field 0 on stock (a WebUI-created profile has no `wgcN_desc` mirror) and from `wgcN_desc` on Merlin. Both services cache it per instance, so it costs one extra read per action however many lines mention it, and the lookup is best-effort - a failure degrades to the bare `wgcN` rather than breaking the action being logged. Raw router output echoed into the log (`wg show interfaces: wgc1`) is left verbatim. The EDIT modal heading uses the same label (`EDIT wgc1:pia-aus_melbourne`).

**Slots run concurrently.** Manage ENABLE used to disable every other slot first ("one active at a time"); it no longer does. Stock caps how many may run at once - `RouterSlots.maxActiveSlots`, read from `nvram get vpnc_max_conn` and falling back to `kDefaultStockMaxActiveSlots` (2) when the key is missing or unparseable. Merlin has no such key, so `maxActiveSlots` is null there and nothing is capped. `SlotModal._enableManage` counts the *other* interfaces that are up and, when that reaches the cap, shows a "VPN limit reached" dialog naming the ASUS limit and asking the user to disable a slot - it makes no router writes in that case. The same check (`SlotModal._withinVpnLimit`) gates watchdog CREATE/EDIT, which brings a tunnel up as a side effect; it runs **before** the dialog opens so the user is not made to fill it in for nothing. Watchdogs are no longer mutually exclusive - `deactivateOtherSlots` is gone.

`RouterSlots.activeSlots` is a **`Set<int>`** built from *all* matches of `wgc(\d)` in `wg show interfaces` — more than one tunnel can be up at once (stock `vpnc_max_conn`), and the previous `firstMatch` silently badged an arbitrary one of them. It is independent of `SlotInfo.enabled` (the NVRAM / `vpnc_clientlist` flag): the badge means *the interface is up*, the flag means *it is configured on*. They can legitimately disagree while an action is in flight.

### 4.5 Manage-mode action semantics

| Action | Behaviour |
| --- | --- |
| CREATE | Overwrite confirm if `!isEmpty` → region picker → `_PiaCredsDialog` → `generateConfig` → `createConfigToSlot`. Backs up the 17 existing keys first and restores them on failure. Writes `enable=0`, `enforce=0`, `fw=1`, `nat=1`, `psk=""`, `rip=""`, `ep_addr_r=""`. Ends with an info dialog telling the user to press ENABLE. |
| ENABLE | Reads `wgcN_wd_primary_ip` / `_secondary_ip`; if either is blank, prompts (`_PingTargetsDialog`, defaults `8.8.8.8` / `1.1.1.1`) and writes them. Applies the concurrency gate (below), then calls `enableSlot`. **Other slots are left running** - it no longer tears anything down. |
| `enableSlot` | `enable=1` → commit → `service "start_wgc N"; service restart_vpnrouting0` → polls `wg show interfaces` up to `verifyMaxAttempts` (30) × `verifyPollInterval` (2 s) → pings **both** targets via `-I wgcN -c 1 -W 5`. **Both must pass**; any failure reverts to `enable=0` and throws. |
| EDIT | `readSlotParams` → `SlotParamsEditor` → `writeSlotParams` (values shell-single-quoted). |
| DISABLE | `stopWatchdog` if `wdActive`, then `enable=0` + commit + the firmware's stop, then **waits for the interface to leave `wg show interfaces`** before returning. The wait is what keeps the ACTIVE badge honest: `_runSlot` refreshes as soon as this returns, and the stop is queued through `notify_rc`, so without it the refresh reads a tunnel that is still up. Same for `_revertEnable`. |
| DELETE | Confirm (destructive) → `stopWatchdog` if `wdActive` → `enable=0`, stop service, **wait for the interface to leave `wg show interfaces`** (bounded by `verifyPollInterval`/`verifyMaxAttempts`), then `nvram unset` all 17 keys **plus** `wd_primary_ip` / `wd_secondary_ip`, plus `kVpncRuntimeKeys` on stock, then commit. Those runtime keys are indexed by the profile's **clientlist field 7**, not the slot — wgc1 leaves `vpnc9_*` — so `vpncStateIndexForSlot` resolves it from the record while it is still present, falling back to `10 - slot`. The wait is load-bearing: the stop is queued through `notify_rc` and returns immediately, so unsetting straight away lets the firmware re-create `wgcN_enable` behind it. If the interface never goes, the keys are cleared anyway and a warning is logged. |

All mutating router actions also emit `logger -t cfg-pia-wg '<msg>'` to the router syslog (best-effort).

### 4.6 Slot parameter editor (`slot_params_editor.dart`)

- Editable text (10): `addr`, `alive`, `desc`, `dns`, `ep_addr`, `ep_port`, `mtu`, `ppub`, `priv` (obscured, `ObscuredField`), `aips`.
- Editable switches (3): `enforce` (Kill switch), `fw` (Inbound firewall), `nat`.
- Read-only display (4): `enable`, `ep_addr_r`, `psk`, `rip`.
- Blank NVRAM pre-fills from `_kEditableDefaults`: `alive=25`, `dns=9.9.9.9, 149.112.112.112`, `ep_port=1337`, `mtu=1420`, `aips=0.0.0.0/0`.
- SAVE (`Key('slot_params_save')`) is disabled until **all 10** text fields are non-empty.

### 4.7 Watchdog

**Preconditions.** The watchdog runs on **both** firmwares. The old Merlin-only gate in `router_slots_screen.dart` is gone, replaced by the firmware gate in §4.13. `jq` is still required: `isJqInstalled()` checks `which jq` on Merlin and `[ -x /jffs/cfg-pia-wg/jq ]` on stock; if absent the dialog shows a red banner naming the expected path and SAVE is disabled.

**`WatchdogDialog` fields:** check interval (min, default 5), primary IP (8.8.8.8), secondary IP (1.1.1.1), PIA username/password (pre-filled from session, mirrored back on every exit path via `_rememberPiaCreds`), and — behind the `Enable email alerts` switch — From, To, Subject (`cfg-pia-wg alert`), SMTP server `host:port`, SMTP username/password, plus `TEST EMAIL`.

**`WatchdogConfig.validate()`** returns human-readable strings: interval > 0; both IPs required and valid IPv4; PIA username + password required; when email is on — From/To valid addresses, subject, `host:port` SMTP server, SMTP username + password.

**SAVE flow (`watchdog_dialog.dart:219-262`):** jq gate → `validate()` → if not currently enabled, confirm-overwrite (when the slot is non-empty) then force a region pick → WAN-ping both targets (`pingHostViaWan`, warn-only, "The settings will still be saved.") → `deployWatchdog(cfg, desc)` → if the slot was empty, `enableVpnSlot` → pop.

**`deployWatchdog` order (`router_watchdog.dart:373-392`) — order is load-bearing:**
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

**`testEmail`:** writes `/tmp/mail.txt`, runs BusyBox `sendmail -H "exec openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -connect host:port"`. On non-zero exit it runs three diagnostic layers (sendmail stderr → `nc` TCP reachability → `openssl s_client` TLS probe) and writes each to the **router syslog**; the app only says "Test email failed - see router log for details." SMTP port defaults to **465** when unparseable.

### 4.8 Router-side script `_kWatchdogScriptTemplate` (POSIX sh, `__SLOT__` is the only placeholder)

| Aspect | Value |
| --- | --- |
| Paths | `/jffs/cfg-pia-wg/watchdog_wgcN.sh` (`watchdogScriptPath`; moved off `/jffs/scripts` in 402, which is Merlin's hook directory and still holds `services-start`), log `/tmp/watchdog_wgcN.log`, status `/tmp/watchdog_last_ping_success_wgcN`, backoff `/tmp/watchdog_backoff_wgcN`, CA cache `/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt` (`kPiaCaCertPath`; the script `mkdir -p`s the directory before downloading, since Merlin has no reason to have created it) |
| Health check | `ping -I wgcN -c 3 -W 2` primary, **else** secondary — **either** passing is success (contrast: app ENABLE requires **both**) |
| Backoff | `COOLDOWN=120` s between reconfiguration attempts; counter+timestamp in the backoff file, reset to `0\n0` on success |
| Preflight | `wgcN_desc` non-empty, `jq` present, PIA user set, and WAN reachability of either target (no internet → exit 0, no alert) |
| Liveness | `wg show wgcN latest-handshakes` reduced to its max, healthy if under 300s old; `ping -I wgcN` only as a fallback. **`ping -I` is not a liveness test on stock** - the router's own traffic is not routed into wgcN, so it fails on a healthy tunnel and the watchdog re-registered with PIA every cooldown until PIA refused tokens. |
| Re-negotiation | curl the CA (cached) → token via `jq -r '.token'` → server list filtered by `.regions[] \| select(.id==$DESC)` → ping-based latency sweep → `wg genkey`/`wg pubkey` → `curl --cacert --resolve <cn>:1337:<ip> …/addKey` → write 16 `wgcN_*` keys → `nvram commit` → `stop_wgc`/`sleep 2`/`start_wgc`/`restart_vpnrouting0`/`sleep 3` → verify `ifconfig wgcN` |
| Kill switch on re-negotiation | **preserved**: the script reads `wgcN_enforce` into `$ENFORCE` at the top and writes that value back, defaulting to 0 when the key is unset (always, on stock). It used to write `enforce=1` flat, so a slot created kill-switch-off came back on once the watchdog fired. |
| PIA token request | Uses `$CURLB` (no `--fail`) so an error body survives to be logged, with the status from `-w '%{http_code}'`; the body goes to `$TMPTOK` and is removed as soon as it is parsed. A 403 here is PIA refusing the request, not a script fault - it has been seen after sustained re-registration. |
| TLS floor | `--tlsv1.2` in `$CURL`. It is a MINIMUM, not a pin. `--tlsv1.3` made every addKey call fail with curl exit 35: PIA's addKey endpoint on :1337 does not offer 1.3, though the token and server-list hosts do. |
| Error text | BusyBox `tr` has no character classes - `tr -d "[:cntrl:]"` deletes literal c/n/t/r/l/[/]/: instead. Sanitise with `head -n 1 ... | cut -c1-160`. |
| Curl hygiene | `echo -n > /jffs/curllst` after every curl — `/usr/sbin/curl` logs every command line to that world-readable file |
| Alerts | `send_alert SUCCESS` / `FAILED (<reason>)` when `wgcN_wd_email_enabled=1`; same 3-layer SMTP diagnostics as `testEmail` |
| Size | The deploy writes the script in ~4 KB chunks (`heredocWriteCommands`: `cat >` then `cat >>`), because **dropbear refuses an exec request over `MAX_CMD_LEN` = 9000 bytes** and drops the connection - which it did at 9055, mid-deploy, after the slot was already enabled. Never send the script as one command. `router_watchdog_unit_test.dart` still caps the script at 9500 bytes, now for JFFS space and reviewability rather than SSH. |
| Write verification | `_writeScript` compares `wc -c` against the expected byte count and throws. Without it a failed write left cru entries pointing at a script that did not exist, and the app called that ACTIVE. |

### 4.9 NVRAM variables

**Per-slot WireGuard (`kSlotNvramKeys`, `router_slot_service.dart:28-46`) — `wgcN_` prefix, N = 1..5:**

| Key | Meaning | User-editable |
| --- | --- | --- |
| `addr` | local tunnel IP, CIDR | yes |
| `alive` | persistent keepalive (25) | yes |
| `desc` | **`pia-` + PIA region id** (e.g. `pia-aus_melbourne`). The prefix marks the VPN as this app's among any others on the router; the router script strips it (`${DESC#pia-}` -> `REGION`) before its `select(.id==$id)` lookup, so the bare id must still be a real PIA region. `slotDescFor` / `regionIdFromDesc` are the Dart side. | yes |
| `dns` | DNS servers | yes |
| `enable` | 1/0 interface enabled | no (ENABLE/DISABLE only) |
| `enforce` | 1/0 kill switch | yes |
| `ep_addr` | peer endpoint FQDN/IP | yes |
| `ep_addr_r` | resolved endpoint IP | no |
| `ep_port` | endpoint port (1337) | yes |
| `fw` | 1/0 inbound firewall | yes |
| `mtu` | MTU (1420) | yes |
| `nat` | 1/0 NAT | yes |
| `ppub` | server public key | yes |
| `priv` | client private key (obscured field) | yes |
| `psk` | preshared key — unused by PIA | no |
| `rip` | router public IP | no |
| `aips` | allowed IPs (`0.0.0.0/0`) | yes |

**Per-slot watchdog (`WatchdogConfig.toNvram`) — `wgcN_wd_` prefix:** `check_interval`, `primary_ip`, `secondary_ip`, `email_enabled`, `email_from`, `email_to`, `email_subject`, `smtp_server`, `smtp_user`, `smtp_pass`.

`wd_primary_ip` / `wd_secondary_ip` are **shared**: written by `RouterSlotService.writeWatchdogPingTargets` during manage-ENABLE, read by both the ENABLE check and the router script, and unset by both `deleteSlot` and `stopWatchdog`.

**Global (not slot-scoped):** `cfg_pia_wg_user`, `cfg_pia_wg_password` — plaintext PIA credentials shared by every slot's watchdog. Also read: `3rd-party` (firmware detection), `jffs2_scripts`, `jffs2_on` (Merlin only), `vpnc_clientlist` (stock only).

**Stock `vpnc_clientlist`** (see ARCHITECTURE.md 2.3.2 for the full schema). Stock exposes only 12 of the 17 `wgcN_` keys; the region name and the active flag live instead in one delimited string of up to five profiles — records separated by `<` (no leading delimiter), fields by `>`. The app owns exactly two fields and copies every other one through untouched:

| Field | Meaning | App behaviour |
| --- | --- | --- |
| 1 | description | written — the PIA region id |
| 2 | protocol | `WireGuard` on a record the app creates |
| 3 | slot number | how a record is matched to `wgcN_` |
| 6 | active state | written by ENABLE / DISABLE / CREATE |
| 7 | iptables ID — also indexes the profile's `vpncN_*` runtime keys (`9` -> `vpnc9_state_t`) | `10 - slot` on a record the app creates; **preserved** on an existing one |
| 12 | fixed | `Web` on a record the app creates |
| 4, 5, 8, 9, 10, 11 | unknown / ignored | left empty when creating; preserved when updating |

Modelled by `VpncRecord` + `parseVpncClientlist` / `serialiseVpncClientlist` / `buildVpncRecord` / `upsertVpncRecord` / `removeVpncRecord` in `router_slot_service.dart` (all pure).

**`wgcN_desc` on stock** is not a real firmware field. The app writes it anyway as a key of its own, mirroring `vpnc_clientlist` field 1, because the router-side watchdog script needs the region name from a bare `nvram get` — the same practice already used for the invented `wgcN_wd_*` keys. Both copies are kept in step by `createConfigToSlot` and `writeSlotParams`.

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

Use `_FormDialog` (`slot_modal.dart`) or the same structure by hand - `Dialog` > `ConstrainedBox(maxWidth: 480)` > `SingleChildScrollView` > `Padding` > `Column`, with the buttons as the last row of the scrolling column. **Width only**: the height must come from the incoming constraints, since inside the chrome the Scaffold has already taken the keyboard off the body and any cap computed from the screen height is too big. `SlotParamsEditor` and `WatchdogDialog` already do this.

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
| Credentials on the device | Volatile only — `SessionController` fields, wiped by `wipeAll` on every exit path. No `SharedPreferences`, no file persistence. |
| Generated config on the device | In memory, **except** SHARE, which writes `pia-<region>.conf` to the temp dir and deletes it in a `finally`. |
| Credentials on the router | PIA username/password go to router NVRAM in **plaintext** (`cfg_pia_wg_user`/`_password`) whenever a watchdog is deployed; SMTP password likewise (`wgcN_wd_smtp_pass`). Removed by `stopWatchdog`. |
| Screen capture | `FLAG_SECURE` in `MainActivity.onCreate` blocks screenshots, screen recording and the Recent Apps preview - **release builds only**. A DEBUG build skips it so the app can be captured on a device while testing, and `allowScreenCaptureInRelease` is a manual escape hatch for capturing a release build. `test/unit/clipboard_service_test.dart` fails if the gate widens or the hatch is left on. |
| TLS | PIA `addKey` is CA-pinned (`withTrustedRoots: false`) with a CN check; SMTP uses `openssl s_client -tls1_3 -verify_return_error`. |
| Shell injection | All interpolated user values go through `shellSingleQuote` — **except** `createConfigToSlot`, which uses `"…"` double quotes for the parsed-config values (`router_slot_service.dart:177-193`). |

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
| Region + active state | `wgcN_desc`, `wgcN_enable` | `vpnc_clientlist` fields 1 and 6 (plus the `wgcN_desc` mirror and `wgcN_enable`) |
| Per-slot keys written | all 17 | 13 — `enforce`, `fw`, `ep_addr_r`, `rip` skipped (`kMerlinOnlySlotKeys`) |
| Region name read from | `wgcN_desc` | `vpnc_clientlist` field 0, falling back to `wgcN_desc` when the row is missing — so ANY path that creates or renames a slot must call `RouterSlotService.writeVpncProfile`, the watchdog deploy included. Without the fallback a slot missing its row reads as unconfigured and the modal greys out every button that needs a description. `_setVpncActive` carries the description too, so enabling repairs a nameless row. |
| Enable verification | interface present, then a WireGuard handshake, then ping (fatal) | interface present, then a WireGuard handshake (the gate); the ping is logged only - it pings from the tunnel's source address but routes over the WAN, so it answers OK for a tunnel the peer never answered |
| Watchdog ACTIVE means | cron entry **and** `[ -s <script> ]` (paths come from `watchdogScriptPath` in `firmware.dart` - never build a router command with `\$kSomething`, the shell expands it to nothing and a test now fails on it), in both `fetchSlots` and `getWatchdogStatus` - never the NVRAM settings, which survive a DISABLE and a failed deploy alike |
| Watchdog start / stop of the tunnel | `service start_wgc N` / `stop_wgc N` | `nvram set vpnc_unit=<row>` + `service restart_vpnc` / `stop_vpnc` (`RouterSlotService.runVpncService`) — the same calls MANAGE makes. The Merlin commands are inert on stock. |
| Kill-switch badge / editor controls | shown | hidden (no `enforce` field) |
| `jq` | `which jq` | `/jffs/cfg-pia-wg/jq` |
| Mail transport | BusyBox `sendmail` + `openssl s_client` | `mailsend-go` (credentials on the command line — accepted risk) |
| Script directory | `jffs2_scripts=1` / `jffs2_on=1` | `mkdir -p /jffs/scripts` |
| Cron persistence | append to `/jffs/scripts/services-start` | rewrite the REPLACEMENT block of `/opt/etc/init.d/S50downloadmaster`, then run it with `start` |
| Enable a slot | `service "start_wgc N"; service restart_vpnrouting0` | set `vpnc_unit`, then `service restart_vpnc` (there is no `start_vpnc`) |
| Disable / delete / revert | `service "stop_wgc N"; service start_vpnrouting0` | set `vpnc_unit`, then `service **stop_vpnc**` |
| Concurrent tunnels | unlimited (no cap key exists) | capped by `vpnc_max_conn` (default 2); the third ENABLE is refused with a dialog |
| Watchdog script path | identical on both (`/jffs/scripts/watchdog_wgcN.sh`) | |

**`vpnc_unit` is the 0-based ROW INDEX of the slot's record in `vpnc_clientlist`** — see `vpncUnitForSlot` in `router_slot_service.dart` and ARCHITECTURE.md §4.2. It is *not* `5 - slot`: the WebUI can only create profiles in slot order 5,4,3,2,1, so on any list it built the two happen to agree, but the app lets the user pick any slot. All four stock service calls go through `RouterSlotService._runVpncService`, which resolves the row and throws an actionable error on enable when the slot has no profile (a stop is a silent no-op instead). **Ordering is load-bearing:** resolve the unit *after* the upsert that may append the row (enable) and *before* the removal that drops it (delete).

**`restart_vpnc` does not stop a tunnel.** It clears `wgcN_enable` and `vpnc_clientlist` field 6 — so the WebUI reports "disconnected" — while the interface stays up in `wg show interfaces`. Stock disable/delete/revert must use `stop_vpnc` (ARCHITECTURE.md §4.2.3).

**S50downloadmaster** is a stock init script the firmware already runs at boot and on a firewall restart; stock has no `services-start` and bare `cru` entries do not survive a power cycle, so the app hijacks it. Only the region between the two REPLACEMENT markers is ever rewritten, and it accumulates one check + one rotate line **per watchdog** (one today, several later). `stopWatchdog` rebuilds the file with that slot's lines dropped rather than `grep -v`-ing them out, so the stock scaffolding survives; the file itself is never deleted.

**Watchdog script generation.** The deploy heredoc has a practical size ceiling (~8.3 KB in production), so the script carries **no runtime firmware branching**. `buildWatchdogScript` resolves four placeholders at build time: `__SLOT__`, `__JQ__` (into a `JQ=` variable every call site reads), `__MAILBODY__` and `__MAILCMD__`. A unit test asserts no placeholder survives on either firmware and that the stock variant is no larger than the Merlin one.

**Tests.** The detection flag is a library global, so any suite touching router code must reset it — use `useMerlin()` / `useStock()` / `resetRouterFirmware()` from `test/watchdog_test_utils.dart`. A leaked flag produces confusing cross-file failures under parallel workers.

Note: ignore all .claude\plan_*.md files, they are historical and not part of the current codebase. This .claude\CONTEXT.md file is the authoritative source for doc-vs-code discrepancies.
