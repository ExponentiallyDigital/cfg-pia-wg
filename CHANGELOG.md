# Changelog

## "to do"

- Release to Play Store - +12 testers for **closed test** over 14 continuous days
- Powershell build script to add version to aab (like action script does) + port build.sh functionality to ps1 (rich error handling & stats)
- ...
- Button to enable watchdog should not be able to be pressed unless a slot has been selected, it is greyed out and deosn't become lit until a slot is selected but it can still be pressed and activates the new feature
- no error shown on screen if hit _test email_ without filling in all details, error is generated to the app log but you can't see it, needs to be visible on screen, it returns lots of info but you won't see it behind the current window
- as above but for _ping targets_: user not notified that ping targets can't be reached, does log to app's log but not visible, should open a dialogue box warning the user
- add a note that when manually adding VPNs, the description needs to match the PIA region name eg `aus_melbourne`
- on selecting `WATCHDOG CONFIG`, if no slot is active, it should enable the interface (reuse existing code by calling that function)
- don't exit `PUSH TO ROUTER` when a config is written and a slot made active, we might want to setup the watchdog
- if slot 1 is active and a watchdog is deployed to it, it remains active even if slot 5 is made active and a watchdog deployed to that slot, so we end up with multiple watchdogs, notre in the docs that watchdog is only for one slot at a time (who runs multiple VPNs on different slots? Maybe someone does...but it's an edge case, just like having more than one WG VPN active concurrently. I'm sure someone does this but I don't.)
- note in docs that watchdog is only ever active on one interface at a time...but that's not how it currently works, needs fixing
- make it clear that the log in the WATCHDOG screen is from the wgcN log on the router
- view log should be names "LOAD/GET LOG", as it's not updated in real time, if it becomes realy big there will be a lot of scrolling needed...maybe show in reverse order, currently shows oldest to newest, could log file fill NVRAM? Store it on volatile partition? There are 288 five minute intervals in 24 hours.
- pushing to wgc5 (perth) did not disable wgc1 (Melb), due to a change I made...where was that!

---

## Changes

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
- added same error checking to test email send function invoked by the UI through `buildSendmailCommand` and ` testEmail`
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
