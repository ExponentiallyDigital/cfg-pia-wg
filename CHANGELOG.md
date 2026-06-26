# Changelog

## "to do"

### Long term

- Release to Play Store, needs 12 **closed test** testers over 14 continuous days (keep installed, run min. once)
- New app to set up an Asus router in the most secure/private way possible
- Add patreon/paypal donation via app/GitHub
- Edit hosts from VPN client

### Short term

- update play store app name from `pia_wireguard_cfga` to `cfg_pia_wireguard`
- port `build.sh` functionality to `build.ps1`
- new UI: modals need to be resized with tablet/large screen
- confirm private datastore contains 0 sensitive data, examine output from

```bash
`C:\Users\andrew\AppData\Local\Android\sdk\platform-tools\adb.exe exec-out "run-as com.exponentiallydigital.cfg_pia_wireguard tar c ." > C:\Users\andrew\Desktop\app_dump.tar`
```

---

## Changes

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
- renamed `pia_wireguard_cfga` to `cfg_pia_wireguard` in all build scripts, tests, and settings files
- add `flutter analyse` to build scripts, actions, and docs
- updated quality_and_security.yml to use java 21 (was 17 in some places), this matches the local build envs. V25 breaks local dev tool chain.
- added version number to release assets created by `build.ps1` and `build.sh` (matches GitHub Actions release script)
- updated slot edit text
- renamed menu entry from "VPN watchdog management" -> "Watchdog WireGuard management"
- watchdog shell script, changed log message from "Checking wgc1 connectivity" to "Checking wgc1 aus_melbourne connectivity"
- updated text for overwrting watchdog config with a different region
- droped "standalone" from menu item name
- renamed modal screens from wireguard/watchdog "slots" to "configuration"
- hamburger menu "Close app" -> "Exit app"
- slot modal "(Empty Slot)" -> "<\empty slot>"
- change "CLOSE" button on each of the 4 option screens -> "HOME"

2026-06-24 version: 0.6.03

- no code changes, upadted extensive to do list

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
- found it, `stopWatchdog`, in `lib\router_watchdog.dart`: had commented out `await _run('service "stop_wgc wgc$slot"; service start_vpnrouting0');` now re-enabled that line (and it works again, no more multiple VPNs running concurently!)

> [!NOTE]
> If slot 1 was active and a watchdog was deployed to it, it remained active even if slot 5 was made active and a watchdog deployed to that slot, so we end up with multiple watchdogs, added to the `to do` list to note in the docs that the watchdog is only for one slot at a time. Who runs multiple VPNs on different slots? Maybe someone does, just like having more than one WG VPN active concurrently. Ping me if this is an issue!

- fix new sendmail commands causing errors: moved `-CAfile` and `-verify_return_error` back inside the openssl quoted string, replaced `timeout 10 openssl` with `openssl -timeout 10`

2026-06-20 version: 0.5.07

- fix CA cert check (wrong variable tested)
- fixed unit tests (testing on prior version's value)
- removed unnecessary `nvram commit` x2
- restart interface to flush routing on watchdog removal
- on failed write of currrent slot restart only that slot, not a full WG restart
- added warning to `scripts\build-optimisation.sh` header (caveat emptor)
- fix services-start permission is 777 on uninstall
- normalised router send email command: resequenced, added -verify_return_error, addec space after "H", removed -amLOGIN, removed test from messageID
- added 3 layer mail send failure: sendmail exit code, sendmail's stderr, and any detail from the underlying openssl handshake
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
- fix transient error, added sleep to final interface up comamnds in `/jffs/scripts/watchdog_wgcN.sh` script
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
- formating of license header in dart modules
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
- added playstore folder to version track submitted description
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
