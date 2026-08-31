# Plan: rewrite `.claude/CONTEXT.md` from the actual code

## Context

`.claude/CONTEXT.md` is loaded at the start of every session and is used as the ground truth before
code changes. It has drifted: it omits the About screen, `app_colors.dart`, `build_info_service.dart`
and `license_text.dart` entirely, and it describes a watchdog button set (ENABLE / DISABLE / EDIT
"saved but not deployed") that does not exist in `lib/widgets/slot_modal.dart`. Acting on it today
would produce wrong changes.

This plan replaces it with a reference-style document derived only from the 24 Dart files under
[lib/](lib/), `pubspec.yaml`, `analysis_options.yaml`, `.vscode/settings.json`, and the `test/` file
listing (test contents not read, per instruction).

**Target path:** overwrite the existing `.claude/CONTEXT.md` (keeping its current uppercase name —
there is no lowercase `context.md`). Single file write; no code changes.

**Note on scope:** the request said 26 Dart files in `./lib`; there are **24**. There are 26
`*_test.dart` files under `test/`. All 24 lib files were read in full.

---

## Verification

1. `flutter analyze` — unchanged (doc-only change; sanity check the tree is clean).
2. Cross-check every file/line citation in the new doc resolves:
   `grep -n` the cited symbol at each `file:line` referenced in §5 and §3.
3. Confirm no code/test files were modified: `git status --porcelain` shows only `.claude/CONTEXT.md`.

---

## Proposed full contents of `.claude/CONTEXT.md`

````markdown
# CONTEXT.md

Android (Flutter) app that provisions Private Internet Access WireGuard configurations and manages
PIA WireGuard slots + a self-healing watchdog on an ASUS / Asus-Merlin router over SSH.

## 1. Working agreements

- **Tests are required for every change.** 26 test files live under `test/` (`test/`, `test/screens/`,
  `test/widgets/`, `test/unit/`). Run `flutter test`; coverage is tracked via `coverage/lcov.info`.
  Every widget that a test needs to reach already carries a `Key` (`snake_case`, e.g.
  `Key('slot_create')`, `Key('wd_save')`) — add one when you add a control.
- **Update this file in the same change as any architecture or behaviour change.** A PR that moves a
  file, renames a destination, changes a button set, or adds/removes an NVRAM key must edit the
  matching section here.
- **Flag conflicts, do not silently resolve them.** If this file disagrees with the code, or with
  `ARCHITECTURE.md` / `BACKLOG.md` / a `.claude/plan_*.md`, say so and ask. Do not "fix" the code to
  match the doc or vice versa without confirmation.
- Do not read `.claude/plan_*.md` as current state — they are historical design notes.

### Conventions in force (observed, not aspirational)

| Area | What the codebase actually does |
|---|---|
| Lint | `package:flutter_lints/flutter.yaml` (`flutter_lints ^6.0.0`), **no custom rules enabled or disabled**. `analyzer.exclude` drops `build/`, `android/`, `ios/`, `web/`, desktop dirs. |
| Line length | 130 (`.vscode/settings.json` `dart.lineLength`, `.prettierrc` `printWidth`). Format on save via Dart-Code. |
| State management | No package. `SessionController extends ChangeNotifier`, published through the `SessionScope` `InheritedWidget`; subtrees that must repaint wrap `ListenableBuilder`. Screens are `StatefulWidget` + `setState` for local form state. **No Provider/Riverpod/Bloc — do not introduce one.** |
| Dependency injection | Constructor-injected nullable factories used purely as test seams: `PiaService? service`, `Future<SSHClient> Function(...)? testClientFactory`, `RouterSlotService Function(SSHClient)? slotServiceFactory`, `RouterWatchdog Function(SSHClient)? watchdogServiceFactory`, `SessionController? controller`, `PiaService({int probePort})`, `RouterSlotService(..., verifyPollInterval, verifyMaxAttempts)`. Follow this pattern instead of a service locator. |
| Error handling | Services `throw`; UI catches, strips `'Exception: '`, and routes through `AppErrors.system` (one at a time) or `AppErrors.inputs` (batched). Every error is also appended to the app log. Router mutations are additionally wrapped by `RouterWatchdog._guard`, which logs to the app log **and** the router syslog before rethrowing. Best-effort side calls (`_logRouter`, ping helpers) swallow with `catch (_)`. |
| Async + UI | Every `await` across a widget boundary is followed by a `mounted` check. Spinners are cleared **before** awaiting a modal (a spinner must never animate under a dialog) — see `slot_modal.dart:99-104`. |
| SSH lifetime | One short-lived `SSHClient` per action (`widget.connect()` → use → `client?.close()` in `finally`), so a dropped connection self-heals on the next action. |
| Licence header | Every `lib/` file opens with the GPL-v3 header block + `Copyright (C) 2026 Andrew Newbury.` Keep it on new files. |
| Colours | Never inline a hex colour in a screen; use the constants in `lib/app_colors.dart`. |

## 2. Snapshot

The app opens on a main menu (`MainMenuScreen`) offering four screens plus "Exit app"; a hamburger
drawer rendered *above* the Navigator adds an **About** destination and duplicates the rest. Screen 1
generates a standalone PIA WireGuard config (region → credentials → `GENERATE CONFIG`) with a 60-second
clipboard auto-clear and SHARE/SAVE. Screens 2 and 3 SSH into an ASUS router and drive a shared
`wgc1..wgc5` slot modal: *manage* mode does CREATE / ENABLE / EDIT / DISABLE / DELETE of WireGuard
slots; *watchdog* mode (Merlin firmware only) does CREATE-EDIT / DELETE / VIEW ROUTER WATCHDOG LOG and
deploys a router-side POSIX-sh watchdog that re-negotiates PIA on ping failure. Screen 4 shows the
in-memory app log. All credentials and generated config are volatile — held only in `SessionController`
and wiped on every exit path — though PIA and SMTP credentials *are* written to router NVRAM in
plaintext when a watchdog is deployed.

## 3. Architecture — `lib/` (24 files)

### Root

| File | Role |
|---|---|
| `main.dart` | 23 lines. `void main() => runApp(const PiaWgApp())`; re-exports `PiaWgApp` from `app_shell.dart`. |
| `app_shell.dart` | `PiaWgApp` (root `StatefulWidget`, `WidgetsBindingObserver`) owns the `SessionController`, `MaterialApp`, `buildAppTheme()`, and installs `AppChrome` via `MaterialApp.builder`. `DestinationObserver` (a `NavigatorObserver`) updates `controller.currentDestination`, **ignoring non-`PageRoute`s** so dialogs don't change drawer highlighting. `didChangeAppLifecycleState(resumed)` → `resyncOnResume()`. Disposes the controller only if it created it. |
| `session_controller.dart` | `AppDestination` enum (6 values), `LogEntry`, `SessionController extends ChangeNotifier`, `SessionScope extends InheritedWidget`, `kDefaultDns`. Holds all volatile state, the 1 Hz clipboard countdown, modal depth, `wipeAll()`. `SessionScope.updateShouldNotify` compares controller identity only, so it does **not** rebuild on every tick. |
| `app_colors.dart` | 13 `const Color` tokens: `kHighlight` teal `#00D4AA`, `kSecondary`, `kBg`, `kSurface`, `kField`, `kBorder`, `kText`, `kMuted`, `kHint`, `kError`, `kOnPrimary`, `kConfigBg`, `kWarn`. |
| `pia_service.dart` | PIA provisioning engine. `WgServer`/`Region`/`ProbeResult`/`RegResponse` models + `PiaService`. Uses `dart:io` `HttpClient` (10 s connect timeout), not `package:http`. |
| `router_slot_service.dart` | `kSlotNvramKeys` (17 keys), `openSshClient()`, `SlotInfo`, `RouterSlots`, `RouterSlotService`: fetch/read/create/enable/disable/delete/write slot params, ping-target NVRAM, `pingViaSlot`. |
| `router_watchdog.dart` | 890 lines. Validation helpers, `WatchdogConfig`, `WatchdogStatus`, pure Bash-template builders, `RouterWatchdog` service, and `_kWatchdogScriptTemplate` (the router-side sh script, ~7 KB heredoc ceiling). |
| `watchdog_dialog.dart` | `WatchdogDialog` — the watchdog CREATE/EDIT form. Its `SAVE` validates, optionally picks a region, WAN-pings both targets (warn-only), then calls `deployWatchdog`. **This is the only path that brings a watchdog up.** |
| `build_info_service.dart` | `BuildInfo` model + `loadBuildInfo()` over `MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/build_info')`, method `getBuildInfo`. The app's **only** platform channel. Falls back to `BuildInfo.unknown()` on `MissingPluginException`/`PlatformException` so widget tests render. |
| `license_text.dart` | 645 lines. `const String kLicenseText` — verbatim raw-string copy of `./LICENSE` (GPL v3). Regenerate by hand if `./LICENSE` changes. |

### `lib/screens/`

| File | Role |
|---|---|
| `main_menu_screen.dart` | 5 buttons + `* requires SSH connectivity` footnote + a PayPal/Patreon donation block. `PopScope(canPop: false)` routes the Android back key to `confirmAndExit`. |
| `standalone_config_screen.dart` | Region row / PIA username / password / DNS → `GENERATE CONFIG`; renders the generated config with COPY (+ countdown) and SHARE / SAVE. |
| `manage_router_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.manage, …)`. |
| `watchdog_management_screen.dart` | 47 lines — thin wrapper: `RouterSlotsScreen(mode: SlotModalMode.watchdog, …)`. |
| `log_screen.dart` | `ListenableBuilder` over the controller → `LogPanel` + `CLEAR LOG`. |
| `slot_params_editor.dart` | Modal editor for the 17 per-slot NVRAM values (spec 3.3). |
| `about_screen.dart` | Build provenance from `loadBuildInfo()`, 6 project links, an open-source `_LicensesDialog` (custom dark replacement for `showLicensePage`), and the full GPL text. |

### `lib/widgets/`

| File | Role |
|---|---|
| `app_scaffold.dart` | `AppChrome` (drawer host + static header, sits above the Navigator so the hamburger stays live under dialogs), `AppHeaderBar` (two-line title, author link, `v<version>` from `PackageInfo`), `AppScaffold` (scrollable padded body + optional `HOME` button; `fillViewport` for the menu). |
| `app_drawer.dart` | `screenForDestination()`, `navigateToDestination()` (no-op on current; **pushes**, growing the stack by design), `closeApp()`, `confirmAndExit()`, `AppDrawer`. |
| `slot_modal.dart` | 674 lines. `SlotModalMode` enum + `SlotModal` (slot list, badges, mode-dependent button set, all router actions) + `_PiaCredsDialog` + `_PingTargetsDialog`. |
| `router_slots_screen.dart` | Shared router-IP/SSH form + `CONNECT TO ROUTER` for both router screens; auto-reconnects when `routerConnected`; enforces the Merlin gate for watchdog mode; opens `SlotModal`. |
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
|---|---|---|---|---|
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
|---|---|
| `piaUsername`, `piaPassword`, `dns` | `dns` defaults to `kDefaultDns` = `'9.9.9.9, 149.112.112.112'`. |
| `routerIp`, `sshUsername`, `sshPassword` | Router form pre-fills `192.168.0.254` / `admin` on a fresh session. |
| `generatedConfig`, `generatedRegionId` | Survive navigation; wiped by `wipeAll`. |
| `log` (`List<LogEntry>`) | `[HH:MM:SS] msg`, flags `isError` / `isSuccess`. |
| `clipboardSeconds`, `_clipboardDeadline` | 60 s default (`clipboardTimeout`), 1 s tick; `resyncOnResume()` re-evaluates after background. |
| `modalDepth` / `modalsOpen` | `enterModal` / `exitModal`. |
| `currentDestination` | Plain field, set by `DestinationObserver`; no `notifyListeners`. |
| `routerConnected` | Set true after a successful connect; drives auto-reconnect on screen re-entry. |

`wipeAll({reason})` clears all six credential fields, config, `routerConnected`, and the clipboard,
then logs. Injectable seams: `clipboardTimeout`, `tickInterval`, `clipboardWriter`.

### 4.3 Standalone generation — `PiaService`

| Step | Detail |
|---|---|
| `fetchRegions` | GET `https://serverlist.piaservers.net/vpninfo/servers/v6`; parses only the **first line** (up to `\n`); keeps regions with ≥1 `wg` server; sorted by id. |
| `probeLatency` | Concurrent `Socket.connect(ip, probePort, timeout: 2s)`. `defaultProbePort = 1337`; `probePort` is injectable so parallel test workers don't collide on the port. Failures sort last. |
| `getToken` | POST `https://www.privateinternetaccess.com/gtoken/generateToken`, HTTP Basic. Non-200 → extracts `message`/`error` from a JSON body. Throws a **`String`** (`'Auth error: …'`), not an `Exception`. |
| `generateWgKeypair` | 32 `Random.secure()` bytes, X25519 clamped (`[0] &= 248`, `[31] &= 127`, `[31] \|= 64`), base64. |
| `registerKey` | Downloads the PIA CA (`pia-foss/manual-connections/master/ca.rsa.4096.crt`), builds a `SecurityContext(withTrustedRoots: false)` pinned to it, sets `Host: <cn>`, GETs `https://<ip>:1337/addKey?pt=&pubkey=`. `badCertificateCallback` only accepts `CN=<server.cn>` (fires because the URL uses the IP). |
| `buildConfig` | `MTU = 1420`, `PersistentKeepalive = 25`, `AllowedIPs = 0.0.0.0/0`, address `/32`. |
| `generateConfig` | regions → probe → best responder → token → keypair → register → build. Empty DNS falls back to Quad9. |

UI (`standalone_config_screen.dart`): `GENERATE CONFIG` is enabled only when region + username +
password are non-empty (DNS optional). PIA creds/DNS mirror into the session on every keystroke.
COPY → `copyToClipboard` + snackbar + countdown. SHARE writes `pia-<region>.conf` into
`getTemporaryDirectory()`, shares it, then deletes it in `finally`.

### 4.4 Slot modal button matrix (`slot_modal.dart:520-551`)

`hasDesc` = `wgcN_desc` non-empty; `enabled` = `wgcN_enable == 1`; `wdActive` = cron entry present.

| Mode | Key | Label | Enabled when |
|---|---|---|---|
| manage | `slot_create` | CREATE | a slot is selected |
| manage | `slot_enable` | ENABLE | `hasDesc && !enabled` |
| manage | `slot_edit` | EDIT | `hasDesc` |
| manage | `slot_disable` | DISABLE | `hasDesc` |
| manage | `slot_delete` | DELETE | `hasDesc` |
| watchdog | `slot_edit` | **CREATE/EDIT** | a slot is selected (works on an **empty** slot) |
| watchdog | `slot_delete` | DELETE | `hasDesc` |
| watchdog | `slot_view_log` | VIEW ROUTER WATCHDOG LOG | `hasDesc && wdActive` |

**There is no ENABLE or DISABLE button in watchdog mode.** All buttons are disabled while `_processing`.

Row badges: `● ACTIVE` (`activeSlot`), `⚑ KILL SWITCH` (`enforce==1`, amber), `◆ WATCHDOG ACTIVE`,
`✉ EMAIL ALERTING` (only alongside WATCHDOG ACTIVE).

### 4.5 Manage-mode action semantics

| Action | Behaviour |
|---|---|
| CREATE | Overwrite confirm if `!isEmpty` → region picker → `_PiaCredsDialog` → `generateConfig` → `createConfigToSlot`. Backs up the 17 existing keys first and restores them on failure. Writes `enable=0`, `enforce=0`, `fw=1`, `nat=1`, `psk=""`, `rip=""`, `ep_addr_r=""`. Ends with an info dialog telling the user to press ENABLE. |
| ENABLE | Reads `wgcN_wd_primary_ip` / `_secondary_ip`; if either is blank, prompts (`_PingTargetsDialog`, defaults `8.8.8.8` / `1.1.1.1`) and writes them. Then stops any *other* enabled slot (and its watchdog) and calls `enableSlot`. |
| `enableSlot` | `enable=1` → commit → `service "start_wgc N"; service restart_vpnrouting0` → polls `wg show interfaces` up to `verifyMaxAttempts` (30) × `verifyPollInterval` (2 s) → pings **both** targets via `-I wgcN -c 1 -W 5`. **Both must pass**; any failure reverts to `enable=0` and throws. |
| EDIT | `readSlotParams` → `SlotParamsEditor` → `writeSlotParams` (values shell-single-quoted). |
| DISABLE | `stopWatchdog` if `wdActive`, then `enable=0` + commit + `service "stop_wgc N"; service start_vpnrouting0`. |
| DELETE | Confirm (destructive) → `stopWatchdog` if `wdActive` → `enable=0`, stop service, `nvram unset` all 17 keys **plus** `wd_primary_ip` / `wd_secondary_ip`, commit. |

All mutating router actions also emit `logger -t cfg-pia-wg '<msg>'` to the router syslog (best-effort).

### 4.6 Slot parameter editor (`slot_params_editor.dart`)

- Editable text (10): `addr`, `alive`, `desc`, `dns`, `ep_addr`, `ep_port`, `mtu`, `ppub`, `priv` (obscured, `ObscuredField`), `aips`.
- Editable switches (3): `enforce` (Kill switch), `fw` (Inbound firewall), `nat`.
- Read-only display (4): `enable`, `ep_addr_r`, `psk`, `rip`.
- Blank NVRAM pre-fills from `_kEditableDefaults`: `alive=25`, `dns=9.9.9.9, 149.112.112.112`, `ep_port=1337`, `mtu=1420`, `aips=0.0.0.0/0`.
- SAVE (`Key('slot_params_save')`) is disabled until **all 10** text fields are non-empty.

### 4.7 Watchdog

**Preconditions.** Merlin firmware (`nvram get 3rd-party == 'merlin'`) — enforced at
`router_slots_screen.dart:132-134`, error `'The VPN watchdog requires Merlin firmware on your router.'`
And `jq` (`which jq`, `router_watchdog.dart:332`): if absent, the dialog shows a red banner and SAVE
is disabled. Both checks have a `// DISABLED MERLIN` comment marking how to bypass them.

**`WatchdogDialog` fields:** check interval (min, default 5), primary IP (8.8.8.8), secondary IP
(1.1.1.1), PIA username/password (pre-filled from session, mirrored back on every exit path via
`_rememberPiaCreds`), and — behind the `Enable email alerts` switch — From, To, Subject
(`cfg-pia-wg alert`), SMTP server `host:port`, SMTP username/password, plus `TEST EMAIL`.

**`WatchdogConfig.validate()`** returns human-readable strings: interval > 0; both IPs required and
valid IPv4; PIA username + password required; when email is on — From/To valid addresses, subject,
`host:port` SMTP server, SMTP username + password.

**SAVE flow (`watchdog_dialog.dart:219-262`):** jq gate → `validate()` → if not currently enabled,
confirm-overwrite (when the slot is non-empty) then force a region pick → WAN-ping both targets
(`pingHostViaWan`, warn-only, "The settings will still be saved.") → `deployWatchdog(cfg, desc)` →
if the slot was empty, `enableVpnSlot` → pop.

**`deployWatchdog` order (`router_watchdog.dart:373-392`) — order is load-bearing:**
1. `enableJffsScripts` (`jffs2_scripts=1`, `jffs2_on=1`)
2. `deactivateOtherSlots(keepSlot)` — **must precede step 3**, because `stopWatchdog` unsets the
   *global* `cfg_pia_wg_user` / `cfg_pia_wg_password`
3. `_writeWatchdogNvram` (per-slot `wgcN_wd_*` + global PIA creds + optional `wgcN_desc`) + commit
4. `enableVpnSlot`
5. heredoc-write `/jffs/scripts/watchdog_wgcN.sh` (30 s timeout) + `chmod +x`
6. `cru a watchdog_wgcN "*/M * * * *" …` and `cru a watchdog_log_rotate_wgcN "0 0 * * *" …`
7. `_ensureServicesStart` — recreate `/jffs/scripts/services-start` if absent, strip prior entries for
   this slot, append both `cru` lines
8. run the script once immediately

**`stopWatchdog`:** `cru d` both jobs, `rm` the script, strip the `services-start` lines (`chmod 700`),
`rm` `/tmp/watchdog_wgcN.log{,.old}`, `/tmp/watchdog_last_ping_success_wgcN`, `/tmp/watchdog_backoff_wgcN`,
`nvram unset` all 10 `wgcN_wd_*` keys **and the global PIA creds**, commit, then `_disableVpnSlot`.
JFFS is left enabled.

**`getWatchdogStatus`:** enabled ⇔ cron entry **and** `wgcN_enable==1` **and** `wgcN` in
`wg show interfaces`. `lastSuccessfulPing` parsed from `/tmp/watchdog_last_ping_success_wgcN`.

**`testEmail`:** writes `/tmp/mail.txt`, runs BusyBox `sendmail -H "exec openssl s_client -quiet
-tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -connect host:port"`. On
non-zero exit it runs three diagnostic layers (sendmail stderr → `nc` TCP reachability → `openssl
s_client` TLS probe) and writes each to the **router syslog**; the app only says
"Test email failed - see router log for details." SMTP port defaults to **465** when unparseable.

### 4.8 Router-side script `_kWatchdogScriptTemplate` (POSIX sh, `__SLOT__` is the only placeholder)

| Aspect | Value |
|---|---|
| Paths | `/jffs/scripts/watchdog_wgcN.sh`, log `/tmp/watchdog_wgcN.log`, status `/tmp/watchdog_last_ping_success_wgcN`, backoff `/tmp/watchdog_backoff_wgcN`, CA cache `/jffs/pia_ca.rsa.4096.crt` |
| Health check | `ping -I wgcN -c 3 -W 2` primary, **else** secondary — **either** passing is success (contrast: app ENABLE requires **both**) |
| Backoff | `COOLDOWN=120` s between reconfiguration attempts; counter+timestamp in the backoff file, reset to `0\n0` on success |
| Preflight | `wgcN_desc` non-empty, `jq` present, PIA user set, and WAN reachability of either target (no internet → exit 0, no alert) |
| Re-negotiation | curl the CA (cached) → token via `jq -r '.token'` → server list filtered by `.regions[] \| select(.id==$DESC)` → ping-based latency sweep → `wg genkey`/`wg pubkey` → `curl --cacert --resolve <cn>:1337:<ip> …/addKey` → write 16 `wgcN_*` keys → `nvram commit` → `stop_wgc`/`sleep 2`/`start_wgc`/`restart_vpnrouting0`/`sleep 3` → verify `ifconfig wgcN` |
| Kill switch on re-negotiation | the script writes **`enforce=1`** (app CREATE writes `enforce=0`) |
| Curl hygiene | `echo -n > /jffs/curllst` after every curl — `/usr/sbin/curl` logs every command line to that world-readable file |
| Alerts | `send_alert SUCCESS` / `FAILED (<reason>)` when `wgcN_wd_email_enabled=1`; same 3-layer SMTP diagnostics as `testEmail` |
| Size | ~7 KB heredoc ceiling — keep additions small |

### 4.9 NVRAM variables

**Per-slot WireGuard (`kSlotNvramKeys`, `router_slot_service.dart:28-46`) — `wgcN_` prefix, N = 1..5:**

| Key | Meaning | User-editable |
|---|---|---|
| `addr` | local tunnel IP, CIDR | yes |
| `alive` | persistent keepalive (25) | yes |
| `desc` | **PIA region id** — must match a real PIA region or the watchdog cannot re-negotiate | yes |
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

**Per-slot watchdog (`WatchdogConfig.toNvram`) — `wgcN_wd_` prefix:**
`check_interval`, `primary_ip`, `secondary_ip`, `email_enabled`, `email_from`, `email_to`,
`email_subject`, `smtp_server`, `smtp_user`, `smtp_pass`.

`wd_primary_ip` / `wd_secondary_ip` are **shared**: written by `RouterSlotService.writeWatchdogPingTargets`
during manage-ENABLE, read by both the ENABLE check and the router script, and unset by both
`deleteSlot` and `stopWatchdog`.

**Global (not slot-scoped):** `cfg_pia_wg_user`, `cfg_pia_wg_password` — plaintext PIA credentials
shared by every slot's watchdog. Also read: `3rd-party` (Merlin detection), `jffs2_scripts`, `jffs2_on`.

### 4.10 About screen & build info

`loadBuildInfo()` returns 13 fields; `_BuildInfoBlock` renders the version/build line plus 9 rows:
Built by (`installer` + `buildTimestamp`), Build type, Commit hash, Git branch/tag, Build runner ID,
CPU Architecture (ABI), Target Android version, Compile SDK, Kotlin. **`commitDate` is parsed but
never displayed.** Any field the host omits shows `unknown`; while the channel is in flight every
value shows `...`.

Values come from `android/app/build.gradle.kts` (`buildConfigField` for `BUILD_TIMESTAMP`,
`GIT_COMMIT_HASH`, `GIT_COMMIT_DATE`, `GIT_BRANCH`, `CI_RUNNER_ID`, `COMPILE_SDK`, `KOTLIN_VERSION`)
plus device-side facts added by
`android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt`.

Links: repo, ReadMe, Change log, Architecture, Security policy, Privacy policy, plus an
`Open source: licenses` link opening `_LicensesDialog` (dark-themed `LicenseRegistry` list).

### 4.11 Errors, logging, clipboard

- `AppErrors.inputs(list)` — one dialog titled *"Please correct the following"* with bullets; no-op on empty.
- `AppErrors.system(msg)` — title *"Error"*; a new error pops any error dialog already open.
- Both log every message with `isError: true` first, and bracket the dialog with `enterModal`/`exitModal`.
- `LogPanel` colours: success → white + check icon, error → `kError` + error icon, otherwise `kHighlight` + info icon. Empty log renders `Ready.`
- Clipboard: `copyToClipboard` arms a 60 s deadline; the 1 Hz tick clears it and logs `Clipboard auto cleared.`

### 4.12 Security posture (as implemented)

| Claim | Reality |
|---|---|
| Credentials on the device | Volatile only — `SessionController` fields, wiped by `wipeAll` on every exit path. No `SharedPreferences`, no file persistence. |
| Generated config on the device | In memory, **except** SHARE, which writes `pia-<region>.conf` to the temp dir and deletes it in a `finally`. |
| Credentials on the router | PIA username/password go to router NVRAM in **plaintext** (`cfg_pia_wg_user`/`_password`) whenever a watchdog is deployed; SMTP password likewise (`wgcN_wd_smtp_pass`). Removed by `stopWatchdog`. |
| TLS | PIA `addKey` is CA-pinned (`withTrustedRoots: false`) with a CN check; SMTP uses `openssl s_client -tls1_3 -verify_return_error`. |
| Shell injection | All interpolated user values go through `shellSingleQuote` — **except** `createConfigToSlot`, which uses `"…"` double quotes for the parsed-config values (`router_slot_service.dart:177-193`). |

## 5. Doc-vs-code discrepancies (previous CONTEXT.md)

| # | The old doc said | The code actually does | Where |
|---|---|---|---|
| 1 | Watchdog screen has **ENABLE, EDIT, DISABLE, DELETE, VIEW WATCHDOG LOG** | Watchdog mode has exactly **three** buttons: `CREATE/EDIT`, `DELETE`, `VIEW ROUTER WATCHDOG LOG`. No ENABLE, no DISABLE. | `slot_modal.dart:546-550` |
| 2 | Watchdog EDIT saves parameters "**but not deployed**"; "the slot modal's ENABLE performs the deploy" | `WatchdogDialog._save` deploys directly — `deployWatchdog` writes NVRAM, the script, both cron jobs, `services-start`, and runs the script. There is no separate deploy step. | `watchdog_dialog.dart:253`, `router_watchdog.dart:373-392` |
| 3 | "ENABLE/DELETE require a non-empty slot" | `CREATE/EDIT` is deliberately live on an **empty** slot; `DELETE` needs `hasDesc`; `VIEW LOG` needs `hasDesc && wdActive`. | `slot_modal.dart:544-550` |
| 4 | No mention of an **About** screen | `AppDestination.about` is a full destination in the drawer with `screens/about_screen.dart` (299 lines) + `build_info_service.dart` + `license_text.dart`. | `session_controller.dart:37`, `app_drawer.dart:45-46,101` |
| 5 | Architecture list omits four files | `app_colors.dart`, `build_info_service.dart`, `license_text.dart`, `screens/about_screen.dart` are all absent from the old map. | `lib/` |
| 6 | "The app opens on a main menu with five options" (nothing else) | The menu also renders a **PayPal / Patreon donation block** and a hamburger hint line. | `main_menu_screen.dart:96-154` |
| 7 | "**No** generated configuration is ever written to device storage" | SHARE / SAVE writes `pia-<region>.conf` to `getTemporaryDirectory()` before sharing (deleted in `finally`, but it does hit disk). | `standalone_config_screen.dart:152-166` |
| 8 | "No SSH or PIA credentials … ever written to device storage" | True for the **device**; but PIA credentials and the SMTP password are written to **router NVRAM in plaintext** on every watchdog deploy. | `router_watchdog.dart:358-359`, `:135-146` |
| 9 | Router ENABLE described only as "a per-slot connectivity check" | The app requires **both** ping targets to pass (else revert); the router-side script treats **either** target passing as healthy. Deliberate asymmetry, easy to "fix" wrongly. | `router_slot_service.dart:241-250` vs `router_watchdog.dart:736-745` |
| 10 | No mention of a `jq` precondition | The watchdog dialog blocks SAVE and shows a red banner when `which jq` is empty. | `watchdog_dialog.dart:150-153, 220-222, 330-334` |
| 11 | Doc positions `router_watchdog.dart` as "deploy/enable/disable" only | It also owns `deactivateOtherSlots`, which enforces one-active-slot across `wgc1..5` **inside** deploy, and whose ordering constraint (before the NVRAM write) is a real footgun. | `router_watchdog.dart:370-375, 424-442` |
| 12 | Doc mentions no idle timeout, but `standalone_config_screen.dart:18` claims "the global **10-minute idle wipe**" | **No idle timer exists.** `SessionController` has only the clipboard countdown; the sole wipe trigger is `confirmAndExit`. The code comment is stale, not the doc. | `session_controller.dart:124-183` |
| 13 | "five options. Each (except Exit app) opens its own screen" — implies the drawer mirrors the menu | The drawer has **six** entries (HOME + 5 destinations incl. About) + Exit app; the menu has four destinations + Exit app. | `app_drawer.dart:96-102` |
| 14 | Doc says CREATE sets "kill-switch off" (correct) but says nothing about the script | The router script re-writes `enforce=1` on every successful re-negotiation, so a slot created kill-switch-off ends up kill-switch-on once the watchdog fires. | `router_watchdog.dart:855` |
````
