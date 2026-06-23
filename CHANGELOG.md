# Changelog

## "to do"

### Long term

- Release to Play Store - +12 testers for **closed test** over 14 continuous days
- New app to set up an Asus router in the most secure/private way possible
- Add patreon/paypal donation via app/GitHub

### Short term

- update and pin java version used in actions scripts to match development environments (v22) - tried 25, breaks local dev env tool chain
- in `build.ps1` and `build.sh`, add the version number to the aab filename (like action script does)
- port `build.sh` functionality to `build.ps1` (rich error handling & stats)
- add `flutter analyse` to build scripts and docs
- create app process flow chart, add to `ARCHITECTURE.md`
- create watchdog documentation:
  - how-to with screenshots
  - when manually adding VPNs via the Asus web GUI, the watchdog function requires the VPN description match the PIA region name eg `aus_melbourne`
  - watchdog is only ever active on one interface at a time
  - requires outbound ICMP over VPN
  - reconfigure in ~7 seconds
  - logfile rotated at midnight, it does not persist across reboots
  - to reduce on router log data, only the current and previous log are ever retained before a reboot

### Fixes for new UI

#### Manage Router

- enable button does not disable any preexisting interface
- disabling/deleting should also disable any active watchdog on that interface
- deleteing a slot should display the description of thats lot
- enable, connectivityc heck fails
- editing a slot instead of saying "Enabled (enable) 1" just say YES
- editing a slot remove text "(enforce)" and "(fw)"
- after displaying "WIREGUARD SLOTS" modal, whne you sleect close should take you to home menu, not back to router login <- change it from a modal to a full screen (same for the watchdog modal, make that full screen too)
- kill switch is always enabled by default when you craete a slot
- only shows if one slot is active at a time, but I have two active in web UI
- with wgc1=melb and active with watchdog, attempt to enable wgc5 as perth, ping fails (this should disable the currently active slot and switch this slot to active, perhaps the kilswitch is getting in the way?) instead both slots might try to be active at the same time:
  [23:27:34] Enabling wgc5...
  [23:27:35] Verifying wgc5 interface comes up...
  [23:27:37] Check 1/30: wgc5 is active
  [23:27:47] Reverting wgc5 to disabled...
  [23:27:49] Reading router configuration...
  [23:27:50] Successfully retrieved router config.
  [23:27:50] Connectivity check failed via wgc5 (primary 8.8.8.8 FAIL, secondary 1.1.1.1 FAIL). Slot left disabled.
- add icmp ping test start & results to router syslog when doing an ENABLE on an existing interface with another already active, insetad only app has any logging

#### Watchdog

- Rename menu entry from "VPN watchdog management" -> "Watchdog WireGuard management"
- delete and edit should not show for empty slots
- shouldn't be able to deploy say perth as a watchdog to a slot that already has melbd as a config, they need to match
- when saving a watchdog on a slot which has an existing rregion config, change "The current slot configuration will be overwrritten when you choose a new region" -> "This will set this watchdog to the XYZ region." wher XYZ is the chosen region, you then get the rregion dialogue box...so you could end up with a watchdog configured for region X with a slot config for region Y?
- modify the router log entry to add thge region name the slot watchdog is configured for eg " Deployed watchdog script for wgc1, aus_melbourne"
- with the shell script, change the log message from "Checking wgc1 connectivity" to "Checking wgc1, aus_melbourne connectivity"
- should the edit button allow you to choose a new region? if so that must set the slot description to match

#### UI

- Set defaults for router ip and username
- home menu app name is split "Configure PIA" new line "Wireguard", timer next to version number, on all screens, when a modal opens the header changes and the timer disappears and the app name is now correctly shown on one line, make the version number always show in topm right corrner, when title is one line it in in middle of header window
- timer should only show if creds are in memory, not always
- warn before pressing back exits app
- prefill router IP and username suggestions
- main menu needs to show how to us ethe hamburger menu
- hamburger menu button at the top is "MENU", rename to "HOME" that should take you to the main (home) menu
- need a visual ID which of part of the app you are in, eg "router login" screen could be anything
  - Manage router, after login says "WIREGUARD SLOTS" -> "MANAGE ROUTER - SLOTS"
  - Watchdog, after login says "WATCHDOG SLOTS" -> "WATCHDOG - SLOTS"
- make the active UI screen highlighted in the hamburger menu
- make each menu option a different colour on main menu and match that to hamburger, and match that to the title of the slot screen eg yellow "WATCHDOG" default green " SLOTS"
- 10m timer should show on app title bar at all times, it does not display when modals are shown
- change "CLOSE" button on each of the 4 option screens -> "HOME"
- if hamburger menu is showing, back button should take you back to the current screen, instead it take the modal winndow back that is showing behind the hamburger menu
- hamburger menu "Close app" -> "Exit app"
- don't display the "connect to router" screen is there is an existing ssh connection to the router, reuse it.

---

## Changes

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
