# BACKLOG.md

- [Prefix codes](#prefix-codes)
- [IDs](#ids)
- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. FTR - future implementation](#112-ftr---future-implementation)
    - [1.1.3. Unconfirmed BUGs](#113-unconfirmed-bugs)
  - [1.2. Codebase cleanup](#12-codebase-cleanup)
  - [1.3. iOS version](#13-ios-version)
- [2. New work items](#2-new-work-items)

---

See [Process - BACKLOG and CHANGELOG management](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md#appendix-process---backlog-and-changelog-management)

## Prefix codes

Work items use the same prefixes as CHANGELOG.md, plus these backlog-only ones:

| Prefix | Meaning                                                       |
| :----: | ------------------------------------------------------------- |
|  OPS   | Operational issue (hosting, external service, infrastructure) |
|  FTR   | Future feature, not yet scheduled to a release                |

See CHANGELOG.md for the full shared list (ADD, ARC, BLD, BUG, CFG, CHG, DEC, DELETE, DOC, FIX, GUI, INF, MOD, NOTE, REL, SEC, TST, UI).

## IDs

Every prefixed work item gets an ID, with one exception: items in `## 2. New work items` stay ID-free while parked there, however there may be ID numbers in that section if work items are moved there by Andrew or Claude. Claude Code usually assigns the ID only when moving an item into CHANGELOG's WIP, see that section for the workflow. This became mandatory alongside CHANGELOG's v0.8.78 build 448 release, and was backfilled across all existing prefixed items in this file at the same time. Unprefixed sub-bullets (e.g. under Codebase cleanup) may also stay ID-free too, since there's no prefix to attach an ID to.

IDs are shared with CHANGELOG.md: one number line across both files, so an ID always points to exactly one item no matter which file it lives in.

Format: `ID-NNN XXX:`, where `XXX` is the item's prefix code, placed at the start of the bullet before the prefix.

To assign a new ID, search **both** BACKLOG.md and CHANGELOG.md for the highest existing `ID-NNN` and use the next number.

Search again immediately before each new ID, even within a batch, and write the item into the file before using its number anywhere else.

Once an ID is given, it does not change even if the item moves section (e.g. from Unconfirmed BUGs to a scheduled section once confirmed). Closed items retain their ID number.

---

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

 `<none>`

#### 1.1.2. FTR - future implementation

- ID-135 DEC: **decide what "clear offline devices" in DEVICES should do.** Raised 2026-09-28 (merged from ID-153). Whatever it does, it leaves DHCP reservations alone: removing one restarts the whole network and can break a pin at a later lease renewal (ARCHITECTURE 6.3, 6.8.3), and the web interface can already do it.
  - **The choice:** hide offline devices in DEVICES on this phone only; or remove them from the router's own client list, as the web interface does.
  - **Done when:** decided, and the build item written with its own done-when.
- ID-305 FTR: **stock's mail sender moves to `mailsend-go` v1.0.13, so a failed send's diagnostics include the server's certificate (`-printCerts`).** Diagnostics only: v1.0.12 already verifies the certificate when sending (`InsecureSkipVerify: !VerifyCert`), and upstream says there's "no need to update unless you need certificate details" (issue #76).
  - **Work:** new pins and SHA-256s for both architectures in `binary_installer.dart`, from the published checksums and recomputed on hardware; the archive member names; offering the update to routers on v1.0.12.
  - **Done when:** on stock, TEST EMAIL sends with v1.0.13, and a deliberately failed send prints the certificate in the app log.
- ID-127 FTR: **contingency, not scheduled: ship our own `curl` if a firmware update breaks stock's two curl workarounds.** Stock's `/usr/sbin/curl` refuses a caller with `crond` in its ancestry and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7); the script detaches from cron and uses hostnames with `--resolve`. Our own curl would make its TLS CVEs this project's job, outside the dependency scanning. Raised 2026-09-19.
  - **Trigger:** a firmware update breaks row 6 or 7. Until then there is nothing to do.
- ID-024 FTR: **decide whether and when to localise the app, starting with French, Spanish and Latin American Spanish.** The groundwork and each language are ID-442 to ID-446.
  - **Done when:** decided, and those items sequenced or closed.
- ID-442 FTR: **the app's text moves into Flutter's localisation files, English only, nothing visibly changed.** Every on-screen string read through `AppLocalizations`.
  - **Done when:** no user-facing string literal is left in `lib/` outside the English file, a test fails if one is added, and the full suite passes.
- ID-443 FTR: **the app in French.** After ID-442.
  - **Done when:** a test runs every screen in French with no missing key, and a French speaker has read it.
- ID-444 FTR: **the app in Spanish (Spain).** After ID-442.
  - **Done when:** as ID-443, for `es`.
- ID-445 FTR: **the app in Latin American Spanish.** After ID-444.
  - **Done when:** as ID-443, for `es-419`.
- ID-446 FTR: **the Play listing in each language the app is in, translated by hand.** Google's automatic translations break the character limits.
  - **Done when:** the Update Play listing workflow publishes each, within Play's limits.
- ID-257 FTR: **parked 2026-09-28 (Andrew's decision): a pilot of hand tests as Flutter integration tests on the emulator, against a real router.** Start with SET, ROUTER LOG, ROUTER RESOLVER STATUS and ROUTER DNS ROUTING. It stopped because `integration_test` put `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile and brought new OSV findings (ID-058). Plan: `.claude/plans/plan_integration-test-pilot.md`.
  - **To resume:** lock the new libraries or exempt the debug build from locking.
  - **Done when:** the four groups run as integration tests against the router, and Andrew has judged whether to go further.
- ID-414 FTR: **waiting on upstream: clear the Kotlin Gradle plugin warning once `home_widget` and `workmanager_android` stop applying the plugin.** Split from ID-408 on 2026-10-16. Every build warns that future Flutter versions will fail with such plugins; on 2026-10-19 both were still the latest (`home_widget` 0.10.0, `workmanager` 0.10.10). Check each new release of the two, which ID-411's weekly upgrade brings, and each new Flutter's notes for when the warning becomes a failure: if that comes first, fork the plugin or hold Flutter back.
  - **Done when:** a local `flutter build apk` no longer prints the warning.

#### 1.1.3. Unconfirmed BUGs

- ID-386 BUG?: **unconfirmed: the small home screen widget may cut its summary line short at its default 2×1 size.** Seen 2026-10-13 on the emulator only (Pixel 7 Pro, Android 17, Nova Launcher): "2 tunnels u…" for "2 tunnels up · 6 pinned", fitting once widened a cell. Launchers size cells differently.
  - **Done when:** Andrew has added the small widget at its default size on his phone, and either it fits, or a fix - a wider default or a shorter line - is tested on that phone.

---

### 1.2. Codebase cleanup

The firmware abstraction, in slices, each on its own build and released on its own, with MAN, WD and DEV hand tests on stock and the MRL smoke test on Merlin before each release. It touches every path stock support landed on, so it starts after the release that carries ID-041 step 4. Plan: `.claude/plans/plan_firmware-abstraction.md`.

- ID-448 TST: **a test that every operation the firmware abstraction will hold runs on both firmwares**, so a stock-only path can't quietly lose its Merlin coverage. After the release carrying ID-041 step 4.
  - **Done when:** the test lists start, stop, slot reading, cron persistence and delete, finds each run under both `useStock()` and `useMerlin()`, and fails when one isn't.
- ID-449 ARC: **firmware abstraction, slice 1: starting and stopping a slot go through one `RouterOps`, resolved once per session.** After ID-448. The smallest slice, and the one that produced two hardware bugs (`restart_vpnc` for `stop_vpnc`, a row index for a slot).
  - **Done when:** no `isStockFirmware` branch is left in start or stop, the suite passes with no test changed, and MAN-3, MAN-8 and MRL pass on hardware.
- ID-450 ARC: **slice 2: reading the slots (`fetchSlots`, `vpnc_clientlist`).** After ID-449's release.
  - **Done when:** as ID-449, for reading, with MAN-15, MAN-16 and DEV-1 on hardware.
- ID-451 ARC: **slice 3: persisting the watchdog's schedule (services-start or `S50downloadmaster`).** After ID-450's release.
  - **Done when:** as ID-449, for persistence, with WD-9 and WD-17 on hardware.
- ID-452 ARC: **slice 4: deleting a slot and clearing its runtime keys.** After ID-451's release. Then ID-419.
  - **Done when:** as ID-449, for delete, with MAN-14 and the delete DEV tests on hardware.
- ID-453 MOD: **the slot modal's manage mode and watchdog mode become two widgets sharing the slot list.** They share little else. Independent of the slices.
  - **Done when:** each mode is its own widget, nothing a user sees changes, and the full suite passes unchanged.
- ID-419 CHG: **the SonarCloud findings left in the watchdog and the slot service, after ID-452.** Split from ID-041 2026-10-16, Andrew's decision. On 2026-10-19: `uninstallFromRouter` 38, `deployWatchdog` 36, `validate` 30, `testEmail` 18 (`router_watchdog.dart`); `createConfigToSlot` 37, `fetchSlots` 30, `enableSlot` 22, `restartSlot` 19 (`router_slot_service.dart`).
  - **Done when:** SonarCloud shows none of the eight, each function only split, and the suite passes unchanged.

### 1.3. iOS version

**Under way** since 2026-10-16. In dependency order. GPLv3 is fine on the App Store while Andrew holds all the copyright, so an outside contribution needs his permission to ship there.

- ID-426 REL: **enrol in the Apple Developer Program as an individual.** Decided 2026-10-19.
  - **Done when:** the membership is active.
- ID-422 REL: **sign builds with the new team on all three iPhones.** After ID-426.
  - **Done when:** a team-signed build runs on each iPhone.
- ID-427 REL: **create the App Store Connect app record, bundle ID `com.exponentiallydigital.cfgpiawg`.** After ID-426.
  - **Done when:** it exists, and its App Store link is sent to Claude for ID-417.
- ID-428 REL: **declare the EU trader status, or leave the EU storefronts out.** After ID-427.
  - **Done when:** App Store Connect shows it declared.
- ID-429 DEC: **decide whether to support iPad, which needs iPad screenshots and review.**
  - **Done when:** decided, and the Xcode project matches.
- ID-418 REL: **CI builds a signed iOS release, with an App Store Connect API key kept in GitHub secrets.** After ID-405 and ID-427.
  - **Done when:** a manual `release.yml` run produces a signed `.ipa`.
- ID-431 REL: **a release tag uploads the signed build to TestFlight.** After ID-418 and ID-430.
  - **Done when:** a tag puts an installable build in TestFlight.
- ID-432 REL: **App Store release notes come from CHANGELOG, like the Play note.** After ID-431.
  - **Done when:** a TestFlight build carries its CHANGELOG notes.
- ID-433 REL: **the release SBOM covers the iOS-only dependencies, such as the native SDKs plugins pull in on iOS.** After ID-418.
  - **Done when:** a release's SBOM lists them.
- ID-454 DOC: **App Store screenshots.** After ID-422 and ID-429.
  - **Done when:** the sizes Apple asks for are taken, from a signed build.
- ID-455 REL: **the listing entered in App Store Connect.** After ID-427, ID-434 and ID-454.
  - **Done when:** App Store Connect shows nothing missing for submission.
- ID-456 DOC: **a demo video for App Review**, showing the app working against a router, as the notes describe. After ID-422.
  - **Done when:** it's recorded and the notes link it.
- ID-436 REL: **the first App Store submission is approved.** After ID-431, ID-435, ID-455 and ID-456.
  - **Done when:** the app is on sale.
- ID-437 REL: **sign the Paid Apps Agreement and set up banking and tax.** After ID-426.
  - **Done when:** the agreement is active.
- ID-401 CHG: **RevenueCat on the App Store.** After ID-431 and ID-437.
  - **Done when:** a TestFlight purchase unlocks the app, and RESTORE PURCHASE finds it again.
- ID-441 BUG?: **unconfirmed: on iOS, nothing offered to save the PIA login.** Seen by Andrew 2026-10-19 in STD-1 on an iPhone, with KeePassium. iOS may offer to save an app's login only when the app declares its website as an Associated Domain (`webcredentials:`), which needs the paid team and a file on that website; no source found settles it.
  - **First:** on an iPhone, with a signed build (after ID-422), see whether iOS offers to save each of the three logins (PIA, router SSH, SMTP), with KeePassium and with iCloud Passwords.
  - **Done when:** that is recorded, and either it works or a fix, such as the Associated Domain, has been seen to work on an iPhone.
- ID-424 TST: **measure how often iOS lets the app refresh in the background, for an iOS widget like Android's (ID-376).** After ID-422.
  - **Done when:** a day's refresh times from an iPhone are recorded.
- ID-438 ADD: **an iOS home screen widget showing the last status the app read.** After ID-431.
  - **Done when:** it shows each tunnel's state as last read.
- ID-439 ADD: **the iOS widget refreshes itself in the background.** After ID-424 and ID-438.
  - **Done when:** it updates with the app closed.
- ID-440 REL: **get a D-U-N-S number from Dun & Bradstreet.**
  - **Done when:** the D-U-N-S number is issued.
- ID-421 REL: **move the Apple membership to the company, through Apple support.** After ID-440.
  - **Done when:** the App Store shows the company as the seller.
- ID-375 BLD: **either** replace this module or **post the following comment on flutter_launcher_icons pull request [#549](https://github.com/fluttercommunity/flutter_launcher_icons/pull/549), and retire `tool/launcher_icons.dart` once a release carries the fix.** Agreed 2026-10-09, Andrew's call, but not posted: the `gh` token here can't comment outside the organisation ("Resource not accessible by personal access token"). Post it from Andrew's own login, or after `gh auth refresh -s public_repo`. Once a flutter_launcher_icons release changes only `ASSETCATALOG_COMPILER_APPICON_NAME`, the wrapper (ID-374) can go, and `scripts/build.ps1`, `scripts/build.sh`, the quality and release workflows, BUILDING, CONTRIBUTING and the note in `pubspec.yaml` can run the tool directly again. The comment:

  ```markdown
  Still happening on 0.14.4, and not only with flavors or App Clips: plain `ios: true` triggers it too.

  With `ios: true` and no flavor, `createIcons` ends with `changeIosLauncherIcon('AppIcon', flavor)`, which sets every line containing `ASSETCATALOG` in the build configurations to the icon name. In our `ios/Runner.xcodeproj/project.pbxproj` (Flutter 3.47.5), two of the three

      ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;

  lines became

      ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;

  even though the icon set's name hadn't changed.

  This PR's one-line fix still works, but it no longer applies as is: the check has moved to around line 340 of `lib/ios.dart`. The equivalent there is `line.contains('ASSETCATALOG_COMPILER_APPICON_NAME')` in place of `line.contains('ASSETCATALOG')`.

  For now we run the tool through a small wrapper that puts the other lines back afterwards.
  ```
  - **Done when:** a `flutter_launcher_icons` release changes only `ASSETCATALOG_COMPILER_APPICON_NAME`, the comment having been posted, and the wrapper and its notes are gone. Checked 2026-10-19: 0.14.4 is still the latest, and PR #549 is open.
---

## 2. New work items

Andrew adds new items here as he finds them, unsequenced, unprioritised, and often without an `ID-NNN` - items in this section may not have an ID until they're moved into CHANGELOG.

**Triage prompt for Claude Code:**

When asked to triage BACKLOG new work, work through it in this order:

1. **Check for duplicates.** For each item in this section, check whether it duplicates or overlaps with anything already in CHANGELOG's Pending, WIP, or Implemented history, or an existing BACKLOG item elsewhere in this file. Flag any overlap found rather than silently merging or dropping it.
2. **Add a unique ID to any work item below that does not already have one.** Assign each item its `ID-NNN`. Search both CHANGELOG.md and BACKLOG.md for the highest existing ID and increment from there.
3. **Sequence into batches.** Group the work items into logical implementation batches, following the same descending-importance ordering rule CHANGELOG already uses. Batches should reflect what makes sense to build and test together, not just priority order.
4. **Flag anything unclear.** Before moving anything, list any item where the requirement, scope, or expected behaviour needs clarification from Andrew. Wait for answers before proceeding on those specific items; the rest of the triage can continue.
5. **Move agreed items to WIP.** Once Andrew confirms the batching, move the agreed work items into CHANGELOG's `### 1.2. WIP` section. Take into account what's already in WIP, resequencing existing items if the combined set changes the intended build order. Remove moved items from this section.
6. **Do not start implementing.** Stop after the move and wait for Andrew to separately say to begin implementation.
7. **Reference work items in conversation.** When discussing work items, include the ID number and a very brief sentence that describes that item at the beginning of conversation.

---

`<none>`
