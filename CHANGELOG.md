# CHANGELOG.md

- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. GUI - changes to the user interface](#112-gui---changes-to-the-user-interface)
    - [1.1.3. CHG - functional code changes](#113-chg---functional-code-changes)
    - [1.1.4. FIX - bug fixes](#114-fix---bug-fixes)
    - [1.1.5. FTR - future implementation](#115-ftr---future-implementation)
    - [1.1.6. TST - testing changes](#116-tst---testing-changes)
    - [1.1.7. REL - release process changes](#117-rel---release-process-changes)
  - [1.2. v0.8.xx freemium](#12-v08xx-freemium)
    - [1.2.1. Accounts \& Play Console setup](#121-accounts--play-console-setup)
    - [1.2.2. RevenueCat dashboard setup](#122-revenuecat-dashboard-setup)
    - [1.2.3. Codebase integration](#123-codebase-integration)
    - [1.2.4. Security \& router diagnostics](#124-security--router-diagnostics)
    - [1.2.5. Sandbox testing \& QA](#125-sandbox-testing--qa)
    - [1.2.6. Documentation and publicity](#126-documentation-and-publicity)
    - [1.2.7. Launch \& post-launch](#127-launch--post-launch)
- [2. Changes](#2-changes)
  - [2.1. Pending - things next in line for implementation](#21-pending---things-next-in-line-for-implementation)
  - [2.2. Implemented - chronological change history](#22-implemented---chronological-change-history)

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- DOC: describe how to test a reconfigure event - v0.6.20+ uses ping targets to check if a reconfigure can occur, i.e. do we have WAN Internet connectivity? If ping targets are set to TEST-NET-1, TEST-NET-2, or TEST-NET-3 you get "no Internet on WAN interface, exiting" from the shell script in `_kWatchdogScriptTemplate`. A working manual test scenario is: remove a slot's config via the Web UI, apply that, then enter a valid region name as the slot description and apply that, or the reconfigure won't occur. Add a warning about that to README.md as well as TESTING.md: leaving 'ghost' watchdogs. "Deleting a slot via the Web UI can leave a watchdog running that can't connect to anything as it has no region name as a title: "ERROR: wgc4_desc is empty". Fix by adding a valid region name e.g. "au_adelaide-pf" to that slot in the Web UI (only that field is needed) which enables the VPN to be reloaded at the next `cronIntervalMinutes`, then remove the watchdog via the app.
- DOC: Fix display of TIP, WARNING, and IMPORTANT in README.md after pandoc converts the file.
- DOC: Only for GitHub display, fix centring of images in examples for Main menu, Standalone config generation, Router slot management. Centres perfectly in README.html.
- DOC: Only for GitHub display, fix centring titles under images for Supply credentials and DNS, Ping targets, Editing a slot, Watchdog management, Configuring a watchdog, App log, Hamburger Menu. Centres perfectly in README.html.
- DOC: Add note that PIA sometimes takes regions offline for maintenance so you might be expecting to have a POP in Perth but online tools may show you coming from Adelaide.
- DOC: Add practical workflows to achieve specific outcomes.
- DOC: Add text about how to check your POP, but note that services like https://www.privateinternetaccess.com/what-is-my-ip, https://ipaddress.my/?lang=en_US, https://2ip.io/, and https://www.showmyip.com/ may cache your location in the browser (they sometimes return a stale POP if used multiple times). To be absolutely sure, close your browser rather than just refreshing the page.
- DOC: Note that you can create and apply a VPN slot by adding a watchdog in one step. If you do that the watchdog will immediately run and see that the VPN is not active and tell you that it failed to do a ping over the tunnel so it is reconfiguring the slot as though a periodic PIA renewal of the registration was needed. If you already have a VPN running on that slot the immediate deployment of the script will see the slot is active and the ICMP over the WG interface succeeds.
- DOC: add to TESTING.md: `wgcX_rip` is updated by the Web GUI via an unknown method (review Asus_WRT src), router log shows no `service` script(s) were were run to display this in the web GUI. It is not the public IP address (which is served from a pool to external sites), it is the router's IP address on PIA's infrastructure (?) and always differs from `wgc1_ep_addr` and `wgcX_ep_addr_r` (except PIA's webiste shows the public IP address as `wgc1_ep_addr*` vs other sites which showed `wgcX_rip` as the public ip address).

#### 1.1.2. GUI - changes to the user interface

- GUI: When switching back and forth to/from the app to copy/paste details into email alert config, the modal became reduced in size, could still enter and edit fields. Cosmetic, fixed by switching to another app then back again.
- GUI: Change colour of region name from GREY to WHITE in WG Config and Watchdog modals.
- GUI: App log has no carriage return/line feed when copied to clipboard. Text copied from Watchdog log has line terminators, as does the Router Config conf file.
- GUI: Can't copy/paste text from About screen.
- GUI: Add text next to the "GENERATED CONFIG" with the region name the config is for.
- GUI: Make Manage and Watchdog deletion prompt msg consistent.
- GUI: Change info prompt after slot created "remember to enable it via the enable button".
- GUI: Watchdog, when creating on a slot which has an config, make the prompt more intelligible, also show the name of the pre-existing region that will be overwritten.

#### 1.1.3. CHG - functional code changes

- CHG: Watchdog email alert `SMTP username field` is finicky when pasting from the clipboard - increase size of input field/get smaller fingers?
- CHG: Remove 'WATCHDOG_EOF' text from test email:
         This is a test email from the cfg-pia-wg watchdog (slot wgcX).
         WATCHDOG_EOF
- CHG: rebuild test/reconfigure email: router DNS name, date and time, why it was sent (test/reconfigure), the region, and cronIntervalMinutes.
- CHG when you enable/disable/delete a slot, add to the router log the region that slot was previously using e.g.
        Enabled wgc1 -> 01 cfg-pia-wg: Enabled wgc1 (region-name)
        Disabled wgc1 -> Disabled wgc1 (region-name)
        Deleted wgc1 configuration -> Deleted wgc1 configuration (region-name)
- CHG: On disable, log lines are repeated (and needs the region name per above)
        cfg-pia-wg: Disabled wgc1
        cfg-pia-wg: Watchdog disabled for wgc1
        cfg-pia-wg: Disabled wgc1
- CHG: If a Conf slot is already disabled, grey out the DISABLE button (only gets logged once to router log though vs above).
- CHG: Creating writes the region name to router log, deleting/disabling does not, review code path for
        Deleted wgc1 configuration
        Created wgc1 configuration (aus_melbourne)
- CHG: Replace app exit and config clipboard copy timer expiration behaviours with clearPrimaryClip(), and remove the two associated comments in README.md.

#### 1.1.4. FIX - bug fixes

- FIX: "home" button is not in green text with a green button border, after activating any of the four main menu items - Manage and Watchdog screens have a modal on top so that's actually correct (for those two situations only).
- FIX: If editing an existing watchdog slot, at save you are asked if you want to overwrite, but if you create a watchdog on an empty slot you aren't prompted.
- FIX: When viewing the router watchdog log, if you COPY the log and then enter the conf menu it will detect that and start the clear timer as it only knows that something from this app placed data in the clipboard.
- FIX: In generate, if you delete DNS entries then go to another screen then re-enter generate, the default DNS addresses are not displayed but are still used when generating a new conf file. Add a check that if that field is ever blank, then the quad 9 defaults are inserted.

#### 1.1.5. FTR - future implementation

- FTR: Consider adding back an idle app timeout of of XX minutes, if timer expires clear all credentials. This would defuse the ability to reveal passwords and copy/paste if app is left idle. Consider calling session destruction through exit path but don't actually exit when timer expires. Had originally implemented this in **pre 0.6.05 build 334**, was set to 10m.
- FTR: enable creation of a GitHub issue from ABOUT screen, open on GitHub with build info of running app.

#### 1.1.6. TST - testing changes

- TST: reiew opportunities to increase code base testing, examnine `ftr` report form functions with low coverage

#### 1.1.7. REL - release process changes

- REL: Parse changelog entries by matching against the pushed tag, and insert as release text, sort by type and insert under a type heading.

### 1.2. v0.8.xx freemium

- CHG: freemium version, move Watchdog function to once-off lifetime paid function. Implementation plan:

  #### 1.2.1. Accounts & Play Console setup

  - **Google Merchant account:** Activate Payment Account in **Google Play Console**.
  - **In-app product creation:** Create a **Non-consumable** in-app product (e.g., `cfg-pia-wg_pro_unlock`) set to US$x.yy.
  - **Play Store compliance:** Complete **Data safety form** to reflect RevenueCat, and add to Privacy Policy.

  #### 1.2.2. RevenueCat dashboard setup

  - **Link accounts:** Connect Google Play Console credentials to RevenueCat via service account keys.
  - **Configure entitlements:** Create an **Entitlement** named `pro_feature` and map to `cfg-pia-wg_pro_unlock`.

  #### 1.2.3. Codebase integration

  - **Flutter dependencies:** Add `purchases_flutter` and `flutter_secure_storage` to `pubspec.yaml`.
  - **Billing service singleton:** Implement RevenueCat initialisation, real-time entitlement status updates, purchase triggers, and purchase restoration.
  - **Paywall UI modal:** Build a `PaywallBottomSheet` highlighting watchdog's zero-touch automation, PIA key renewal fix, and lifetime access model.
  - **PayPal/Patreon:** remove links from main app screen.

  #### 1.2.4. Security & router diagnostics

  - **Pre-flight diagnostic:** Verify SSH connectivity and JFFS script execution readiness *before* displaying unlock feature to prevent purchases on incompatible setups.

  #### 1.2.5. Sandbox testing & QA

  - **Licence testing:** Add developer Gmail under *Google Play Console -> Licence testing*.
  - **Internal test track:** Build and upload `flutter build appbundle` (`.aab`) to the Internal Testing track.
  - **Sandbox verification:** Run `flutter run` on device to test:
  - **E2E test:** Generate and Manage execute freely; watchdog invokes unlock feature.
  - **Purchase flow:** complete test transaction via Google’s *"Test card, always approves"*.
  - **Declined card handling:** Test error handling using *"Test card, always declines"*.
  - **Restoration flow:** test "Restore Purchases" button.
  - **Offline access:** disconnect internet and verify cached local entitlements allow watchdog to execute.

  #### 1.2.6. Documentation and publicity

  - **Update screenshots:** create & upload phone and tablet screenshots x8.
  - **Trademark protection:** add to README that app name, logos, and branding are reserved trademarks.
  - **Transparency:** explain in README that pre-built convenience binaries are available via the Google Play Store to defray development costs and support ongoing app updates.
  - **Publicise**: update Play Store description. Post to SNB and Reddit (r/AsuswrtMerlin, r/PrivateInternetAccess, r/WireGuard).

  #### 1.2.7. Launch & post-launch

  - **Changelog:** Add to v0.8.00 changelog, explain why watchdog is monetised.
  - **Store optimisation (ASO):** include high-intent keywords: *Asuswrt-Merlin, PIA WireGuard token auto-renew, Asus router VPN, NVRAM SSH scripts*.
  - **Reconfigure review prompt:** add link to reconfigure email seeking an app review (add an NVRAM timestamp when watchdog first deployed and increment an NVRAM counter when a reconfigure occurs).

---

## 2. Changes

### 2.1. Pending - things next in line for implementation

- DOC: Add note to use data from About screen when creating an issue on GitHub, add to ISSUE_TEMPLATEs.
- TST: Reinstall stock ASUS router firmware and check Manage and Watchdog operate; remove references to Merlin firmware requirement in Play Store description, README.md, and ARCHITECTURE.md. Remove Merlin environment check function.

### 2.2. Implemented - chronological change history

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
- CHG: re-enabled FLAG_SECURE to disable in-app screenshots, hides screen display from task switcher (was disabled during closed testing to allow screenshots)
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