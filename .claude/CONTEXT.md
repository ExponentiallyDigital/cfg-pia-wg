# CONTEXT.md

This app runs on an Android phone/tablet and provisions a WireGuard VPN configuration for the
Private Internet Access (PIA) service, and manages PIA WireGuard slots + a self-healing watchdog on
an ASUS / Asus-Merlin router over SSH.

## User interface (reorganised, main-menu driven)

The app opens on a **main menu** with five options. Each (except "Close app") opens its own screen
(not a modal). Every screen shares a static two-line header, a hamburger menu (top-left) for fast
navigation between destinations, and an inactivity countdown (top-right, hidden while a modal is open).

1. **Generate standalone PIA WireGuard configuration** — region selection, PIA username/password and
   DNS, then GENERATE CONFIG (enabled only once the required fields are filled). The generated config
   is shown read-only with COPY (60-second clipboard auto-clear) and SHARE / SAVE.
2. **Manage router PIA WireGuard configuration\*** — SSH login, then a parameterised slot modal for
   wgc1–5 with CREATE (generate + write to NVRAM, left disabled), ENABLE (with a per-slot connectivity
   check that reverts on failure), EDIT (all WireGuard slot parameters), DISABLE and DELETE.
3. **VPN watchdog management\*** — SSH login (Merlin only), then the slot modal with ENABLE (deploy the
   watchdog script + cron), EDIT (watchdog parameters + region, saved but not deployed), DISABLE,
   DELETE and VIEW WATCHDOG LOG.
4. **View app log** — scrollable in-memory application log with CLEAR LOG.
5. **Close app** — wipes all credentials, config and the clipboard, then exits.

\* requires SSH connectivity to an Asus router.

After 10 minutes of inactivity (or on Close app / back-exit from the main menu) all credentials, the
generated config and the clipboard are wiped from memory and the user is returned to the main menu.
Errors are shown in modal dialogs: input-validation errors batched into one dialog, system/SSH errors
one at a time. **No SSH or PIA credentials, and no generated configuration, are ever written to device
storage** — they live only in volatile memory.

## Architecture (`lib/`)

- `main.dart` — entry point; re-exports and runs `PiaWgApp`.
- `app_shell.dart` — `PiaWgApp` root: owns the `SessionController`, the `MaterialApp`, the global chrome
  (`AppChrome` via `MaterialApp.builder`), navigation, the idle-wipe wiring and lifecycle resync.
- `session_controller.dart` — `SessionController` (`ChangeNotifier`): shared volatile state
  (credentials, generated config, application log), the inactivity + clipboard timers, modal tracking,
  and `wipeAll`. Exposed via the `SessionScope` inherited widget. `AppDestination` enum lives here.
- `screens/` — `main_menu_screen`, `standalone_config_screen`, `manage_router_screen`,
  `watchdog_management_screen`, `log_screen`, `slot_params_editor` (the §3.3 slot-parameter editor).
- `widgets/` — `app_scaffold` (chrome: static header, hamburger, countdown, per-screen CLOSE),
  `app_drawer`, `slot_modal` (parameterised by manage/watchdog mode), `router_slots_screen` (shared
  SSH-login + connect for both router screens), `region_picker_sheet`, `common_fields`,
  `error_presenter`.
- `pia_service.dart` — PIA provisioning engine (unchanged): server discovery, latency probes, token,
  X25519 keypair, CA-pinned key registration, config assembly (see ARCHITECTURE.md).
- `router_slot_service.dart` — SSH slot operations: fetch slots, create (write, disabled), enable
  (connectivity-checked, revert-on-failure), disable, delete, read/write slot parameters.
- `router_watchdog.dart` — watchdog deploy/enable/disable, NVRAM save, status, log, email test, and the
  router-side Bash watchdog script template (~7 KB heredoc limit). Heredoc writes have a 30s timeout.
- `watchdog_dialog.dart` — the watchdog EDIT form (saves parameters + region to NVRAM; the slot modal's
  ENABLE performs the deploy).

## Functional flow (standalone generate)

Enter region, PIA username/password and DNS → GENERATE CONFIG → config assembled → optionally COPY
(60s clipboard clear) or SHARE / SAVE.

Router-side flows are driven from the Manage-router and VPN-watchdog screens over SSH; see the screen
descriptions above and `ARCHITECTURE.md` for the underlying provisioning steps.
