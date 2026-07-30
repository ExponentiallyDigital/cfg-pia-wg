# CHANGELOG.md

- [1. Backlog](#1-backlog)
- [2. Changes](#2-changes)

## 1. Backlog

- DOC: update to note that screenshotting isn't disabled.
- FIX: if a watchdog slot is disabled, when you click "ENABLE", you are prompted for ping targets & PIA credentials without a dialogue box to enter them. Workaround: use EDIT to enter PIA creds (ping targets are already supplied) or delete/disable then re-create/enable the watchdog. See below.
- FIX: if you ENABLE a watchdog you are prompted to edit it first as it can't find the primary and secondary ping targets. See above.
- ADD: If you deploy a VPN via the watchdog the check interval isn't written to the router log - write a router log message via function enableVpnSlot.
- ADD: Parse changelog entries by matching against the pushed tag, and insert as release text.
- DOC: describe how to test a reconfigure event - v0.6.20+ uses ping targets to check if a reconfigure can occur, ie do we have WAN Internet connectivity? If ping targets are set to TEST-NET-1, TEST-NET-2, or TEST-NET-3 you get "no Internet on WAN interface, exiting" from the shell script in `_kWatchdogScriptTemplate`. A working manual test scenario is: remove a slot's config via the Web UI, apply that, then enter a valid region name as the slot description and apply that, or the reconfigure won't occur. Add a warning about that to README.md as well as TESTING.md: leaving 'ghost' watchdogs. "Deleting a slot via the Web UI can leave a watchdog running that can't connect to anything as it has no region name as a title: "ERROR: wgc4_desc is empty". Fix by adding a valid region name eg "au_adelaide-pf" to that slot in the Web UI (only that field is needed) which enables the VPN to be reloaded at the next `cronIntervalMinutes`, then remove the watchdog via the app.
- DOC: Fix display of TIP, WARNING, and IMPORTANT in README.md after pandoc converts the file.
- DOC: Only for GitHub display, fix centering of images in examples for Main menu, Standalone config generation, Router slot management. Centers perfectly in README.html.
- DOC: Only for GitHub dispaly, fix centering titles under images for Supply credentials and DNS, Ping targets, Editing a slot, Watchdog management, Configuring a watchdog, App log, Hamburger Menu. Centers perfectly in README.html.
- DOC: Add to README the PIA url to check if you are on their network.
- DOC: Add note that PIA sometimes takes regions offline for maintenance so you might be expecting to have a POP in Perth but online tools may show you coming from Adelaide.
- DOC: Add practical workflows to achieve specific outcomes.
- ADD: Note that services like https://www.privateinternetaccess.com/what-is-my-ip, https://ipaddress.my/?lang=en_US, https://2ip.io/, and https://www.showmyip.com/ may cache your loaction in the browser. To be absolutley sure, close your browser rather than just refreshing the page.
- UI: When switching back and forth to/from the app to copy/paste details into email alert config, the modal became reduced in size, could still enter and edit fields. Cosmetic, fixed by switching to another app then back again.
- CHG: watchdog email alert `SMTP username field` is finicky when pasting from the clipboard - increase size of input field/get smaller fingers?
- CHG: no message is written to the router log if you edit and save the watchdog's `cronIntervalMinutes` - the cron job is updated, cosmetic.
- CHG: remove 'WATCHDOG_EOF' text from test email:
         This is a test email from the cfg-pia-wg watchdog (slot wgcX).
         WATCHDOG_EOF
- CHG: rebuild test/reconfigure email: router DNS name, date and time, why it was sent (test/reconfigure), the region, and cronIntervalMinutes.
- CHG: When you save an edited watchdog, you are always prompted for the region. Update the prompt to say that this will set the current VPN to this region, AFTER hitting SAVE you are asked "Overwrite wgc1? This will set this watchdog to the newly chosen region". Add the region name so it becomes "Overwrite wgc1 - au_melbourne? This will set the watchdog to region au_melbourne."
- CHG when you disable/delete a slot, add to the router log the region that slot was previously using eg.
        Disabled wgc1 -> Disabled wgc1 (was region_abc)
        Deleted wgc1 configuration -> Deleted wgc1 configuration (was region_abc)
- DOC: disabling a slot in WIREGUARD CONFIGURATION disables any watchdog and VPN on that slot; disabling a slot in WATCHDOG CONFIGURATION disables any a VPN on that slot and its watchdog - workaround, don't use disable.
- FIX: "home" button is not in green text with a green button border, after activating any of the four main menu items - Manage and Watchdog screens have a modal on top so that's actually correct (for those two use cases only).
- CHG: remove DISABLE & ENABLE functions from watchdog menu modal screen.
- REL: Create a GitHub actions release and verify build data in the new "About" screen.
- REL: Deploy to 'production' on Google Play Store

---

## 2. Changes

2026-07-29 v0.6.28 build 358

- REL: release.yaml already calls quality_and_security.yml directly via workflow_call whenever a tag is pushed, quality_and_security.yml should not listen for tag pushes directly.

2026-07-29 v0.6.27 build 357, sync build

- REL: current GitHub pipeline runs on commit and tag. Reorganise to run quality_and_security.yml on every commit, and on release, run quality_and_security.yml then release.yaml using shared build artifacts so we don't rebuild the app multiple times in the same workflow run.

2026-07-29 v0.6.26 build 356, sync build

- FIX: build artifact naming in release.yml

2026-07-29 v0.6.25 build 355

- FIX: updated quality_and_security.yml to grant permissions required by the reusable workflow
- FIX: prevented release.yml from skipping checks on manual runs.

2026-07-28 v0.6.24 build 354 (pre Google Play Store release)

- FIX: **every url_launcher link in the app was dead** (About screen links, and the header bar's "Exponentially Digital" and version/GitHub links, which last worked in v0.6.21) with `PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.canLaunchUrl")`. Not a url_launcher fault: `android/app/gradle.lockfile` pinned `kotlinx-coroutines-android` to 1.8.1 on the runtime classpaths, but share_plus 13.3.0 declares 1.11.0 and compiles `Dispatchers.IO.limitedParallelism(1)` against it, emitting a call to the `limitedParallelism$default(..., int, String, ...)` bridge whose `name` parameter only exists in coroutines 1.10+. STRICT dependency locking silently downgraded the runtime dependency, so `SharePlusPlugin.onAttachedToEngine` threw `NoSuchMethodError` on startup. Because that is an `Error` and not an `Exception`, `GeneratedPluginRegistrant.registerWith`'s per-plugin `catch (Exception e)` did not catch it: registration aborted at plugin 4 of 5 and `url_launcher_android` was never registered. `package_info_plus` is plugin 3 and registered before the throw, which is why the header still showed a version string and made this look link-specific rather than global. SHARE was broken by the same fault. Fixed by regenerating the lockfiles (`gradlew -p android :dependencies :app:dependencies --write-locks`), which moves the four coroutines artifacts to 1.11.0 on the runtime/lint classpaths - a 4-line lockfile change, nothing else altered. Verified on-device: plugin registration is clean and all eight links open in the browser.
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
- BUG: unable to reporduce (setting to done): if router stops accepting commands (hung web UI, ASUS Android app, and SSH) but is still routing, and an SSH socket times out creating a watchdog, you are incorrectly told that the slot had been created. Occurred once when router web GUI, ASUS app, and SSH access failed, a router process had died but there was no way to access and check. Probably a router firmware bug, power cycling fixed it, nothing useful in router log though. Retained for completeness.
- ADD: TOCs to ARCHITECTURE, BUILDING, CHANGELOG, CONTRIBUTING, README, SECURITY, and TESTING.
- DOC: Added **About** menu screen to README.
- REL: safety committ save ahead of testing GitHub build with new pipelines

2026-07-28 v0.6.23 build 353

- FIX: update-shas.sh/ps1 were writing two spaces after the SHA eg. "...890  # v1.01"
- CHG: updated SHAs
- FIX: update all minor version dependencies & release publock on jini 1.0.0; test if 1.0.2 fixes the Gradle bug exposed by 1.0.1 - OK
- FIX: when saving a new watchdog, scan for other watchdogs and delete them before the new watchdog is activated: eg. deploying a watchdog to slot 5 does not disable an active VPN on slot 1, so you end up with two VPNs running at the same time - apply same logic from 'Manage Router PIA WG Cfg' to disable any other active VPN slots. `RouterWatchdog.deactivateOtherSlots` now sweeps wgc1-5 on both `saveWatchdogConfig` and `startWatchdog`, stopping any other watchdog and disabling its interface. The sweep runs *before* the new config's NVRAM write because `stopWatchdog` unsets the global `cfg-pia-wg_*` credentials.
- ADD: `RouterWatchdog.disableVpnSlot`, mirroring `RouterSlotService.disableSlot` - clears `wgcN_enable`, commits, then stops the interface.
- FIX: `stopWatchdog` issued `service "stop_wgc wgcN"` where the service expects the bare slot index (`stop_wgc N`, per ARCHITECTURE.md), so watchdog DISABLE never actually brought the tunnel down and left an unsupervised VPN running. It now delegates to `disableVpnSlot`, which also clears `wgcN_enable` so the slot cannot return on the next `start_vpnrouting0` or reboot.
- FIX: `probeLatency reports failed probe with progress callback` failed intermittently in the full suite (errno 10048). `probeLatency` dialled a hard-coded port 1337, so faking a responding server meant binding that one global port; three test files need it and `flutter test` runs test files in parallel workers, so they collided.
- ADD: `PiaService.probePort` (default `PiaService.defaultProbePort` = 1337), injectable via `PiaService({probePort})`. Tests now bind an ephemeral port (0) and pass it back in, removing the contention at source rather than serialising the binds behind retry loops. pia_service_test.dart and standalone_config_screen_test.dart were converted and their retry loops deleted; unit/main_unit_test.dart still binds the default port because it drives the real `PiaWgApp` shell, which constructs `StandaloneConfigScreen` itself (app_drawer.dart) and so offers no injection seam - harmless, as it is now the only file binding it.

2026-07-28 v0.6.22 build 352

- FIX: resequenced release.yaml to only run after quality_and_security.yaml sucessfully completes
- CHG: re-enabled FLAG_SECURE to disable in-app screenshots, hides screen display from taskswitcher (was disabled during closed testing to allow screenshots)
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
- CHG: router watchdog shell script does not ping secondary target if primary is sucessful
- FIX: updating the watchdog timeout in the UI did not update a pre-existing cron schedule
- FIX: if you created a VPN via the watchdog interface, it was showing as enabled when it was not. Removed reminder to set it to active; when saving, the watchdog script is deployed and runs immediately.

2026-07-20 v0.6.19 build 349

- updated GitHub action SHAs to latest versions
- updated tests test\screens\standalone_config_screen_test.dart and test\screens\standalone_config_screen_test.dart to run in parallel
- added update-shas.sh, a direct conversion of the update-shas.ps1 script
- build.ps1/.sh scripts now run update-shas.ps1/.sh ahead of building to ensure these are always up-to-date

2026-07-06 v0.6.18 build 348

- set minSdk = 24 (Android 24, Android 7.0 Nougat) in android\app\build.gradle.kts
- source code grammer and spelling (non functional changes)
- reverted internal name space to "com.exponentiallydigital.pia_wireguard_cfga" in MainActivity.kt, proguard-rules.pro, build.gradle.kts, and settings.gradle.kts. This was part of the rename several commits ago but I found taht thjis would have forced a complete restart of the Google Play closed test.
- upadted actions/setup-java SHA to latest version
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

- released: complete UI overhaul + self healing watchdog function
- fix deployemny yamls

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
