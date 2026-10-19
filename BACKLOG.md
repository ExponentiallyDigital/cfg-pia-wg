# BACKLOG.md

- [Prefix codes](#prefix-codes)
- [IDs](#ids)
- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. FTR - future implementation](#112-ftr---future-implementation)
    - [1.1.3. Unconfirmed BUGs](#113-unconfirmed-bugs)
  - [1.2. Codebase cleanup](#12-codebase-cleanup)
  - [1.3. v1.0.0 iOS version](#13-v100-ios-version)
- [2. New work items](#2-new-work-items)

---

See [Process - BACKLOG and CHANGELOG management](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md#appendix-process---backlog-and-changelog-management)

## Prefix codes

Work items use the same prefixes as CHANGELOG.md, plus these backlog-only ones:

| Prefix | Meaning |
|---|---|
| OPS | Operational issue (hosting, external service, infrastructure) |
| FTR | Future feature, not yet scheduled to a release |

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

- ID-135 FTR: **DEVICES can clear offline devices from its list.** It stays clear of DHCP reservations. Pinning a device reserves its address in `dhcp_staticlist`, unpinning leaves the reservation, and the app never removes one (Andrew's decision, 2026-09-28, merged from ID-153). Removing one restarts the whole network, and can break a pin silently at a later lease renewal (ARCHITECTURE 6.3, 6.8.3). Anyone who wants to can do it in the web interface.
- ID-305 FTR: **move stock to `mailsend-go` v1.0.13 and add `-printCerts` to a failed send's diagnostics.** v1.0.13 (2026-09-29, upstream issue #76) prints the server's certificate while sending, not only with `-info`, and adds `-verbose`. `-verifyCert` already applied to sending in v1.0.12: its `sendMail` sets `InsecureSkipVerify: !VerifyCert`. So the alerts have been verifying the SMTP server's certificate all along, and this is diagnostics only. The upstream ChangeLog agrees there's "no need to update unless you need certificate details". The work: new pins and SHA-256s for both architectures in `binary_installer.dart` from the published checksums, recomputed on hardware; the archive member names; offering the update to routers that already have v1.0.12; and a run of TEST EMAIL and a deliberate failure on stock.
- ID-127 FTR: **ship our own `curl` beside `jq` and `mailsend-go`, if ASUS tighten their wrapper further.** Stock's `/usr/sbin/curl` silently refuses a caller with `crond` in its ancestry, and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7). Both are worked around: the script detaches from cron, and every request uses a hostname with `--resolve`. `BinaryInstaller` could ship one, but a TLS stack of our own makes its CVEs this project's job, sits outside the dependency scanning, and asks users to trust far more than a JSON parser. Revisit only if a firmware update breaks row 6 or 7. Raised 2026-09-19.
- ID-024 FTR: localise into French, Spanish and Latin American Spanish, then decide on more. Translate the Play listing by hand: Google's automatic translations break its character limits.
- ID-257 FTR: **pilot: manual tests as Flutter integration tests.** The real app, on the emulator, taps through a flow, checks the screen, and checks the real router over its own SSH connection. Start with groups that need no PIA login (SET, ROUTER LOG, ROUTER RESOLVER STATUS, ROUTER DNS ROUTING), and judge it before going further. Needs a router the test can reset to a known state, and credentials kept out of the repo. Stays by hand: anything physical, emails arriving, the password manager, Play installs and purchases. **Parked 2026-09-28, unrun (Andrew's decision):** the `integration_test` package puts `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile; locking them moved RevenueCat in the debug build and brought `junit` and `guava` findings into the OSV scan (ID-058). The plan is `.claude/plans/plan_integration-test-pilot.md`. To resume: lock the new libraries or exempt the debug build from locking, then follow the plan.
- ID-414 FTR: **clear the build's Kotlin Gradle plugin warning once `home_widget` and `workmanager_android` stop applying the plugin.** Split from ID-408 on 2026-10-16, Andrew's decision, because nothing in this repository can clear it. Every local build says `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): home_widget, workmanager_android` and that future Flutter versions will fail to build with such plugins. On 2026-10-16 both were already the latest on pub.dev (`home_widget` 0.10.0, `workmanager_android` 0.10.9 through `workmanager` 0.10.10), so the fix has to come from their authors. Check each new release of the two (ID-411's weekly upgrade will bring them), and before taking each new Flutter, check its release notes for the point where the warning becomes a failure: if that comes first, the choice is a fork of the plugin or holding Flutter back.
  - **Done when:** a local `flutter build apk` no longer prints the KGP warning.

#### 1.1.3. Unconfirmed BUGs

- ID-386 BUG?: **the small home screen widget cuts its summary line short at its own default size.** Seen 2026-10-13 on the emulator (Pixel 7 Pro, Android 17, Nova Launcher) while making ID-380's screenshot: dropped at 2×1, the size `widget_compact_info.xml` asks for (`targetCellWidth="2"`, `minWidth="110dp"`), it read "2 tunnels u…" for "2 tunnels up · 6 pinned"; widened by a cell, it fits. Not yet seen on a phone - Andrew's had been widened - and launchers size cells differently, so whether it needs a wider default, a shorter line, or nothing depends on more than this one launcher.

---

### 1.2. Codebase cleanup

Early thinking, with measurements: `.claude/plans/plan_firmware-abstraction.md`.

> [!IMPORTANT]
> Do not start the firmware abstraction until stock support has soaked in release. It touches every path stock support just landed on, and a regression here would be indistinguishable from a stock-support bug - the same reasoning that gave SSH connection reuse its own build number.

- Map codebase
  - By file and by function (done 2026-09-01, now in `CONTEXT.md`)
  - Identify redundant or duplicated code
- Optimise and simplify
  - nvram statements
  - Duplication of variables
  - Complexity reduction/reduce lines of code
    - audit large/long/complex source files
    - audit naming of source code files
- Abstract firmware from Manage and watchdog. Measured 2026-09-05: 27 `isStockFirmware` branches across six files, 21 of them in `router_slot_service.dart` (14) and `router_watchdog.dart` (7). Both stock bugs found this session were "the stock branch does not match the Merlin branch's intent".
  - Create functions to act on classes of activities
  - Split out to functions
  - Model on `buildWatchdogScript`, which already resolves firmware once and substitutes the differences (`__KILLSW__`, `__MAILHDR__`, `__MAILCMD__`) rather than branching at runtime
  - Take it in slices, each on its own build: start/stop first, then slot reading, then cron persistence, then delete
- Largest files, measured 2026-09-05: `router_watchdog.dart` 1,554 lines, `router_slot_service.dart` 842, `slot_modal.dart` 767. The email layout in `router_watchdog.dart` (`buildEmailBody`, `RouterEmailFacts`, the section constants) is self-contained and would move out with no behaviour change.
- ID-419 CHG: **the SonarCloud findings in the watchdog and the slot service - ID-041's step 6 - after the firmware abstraction.** Split from ID-041 2026-10-16, Andrew's decision. `uninstallFromRouter` 53, `deployWatchdog` 45 and `validate` 30 (`lib/router_watchdog.dart`), and `createConfigToSlot` 37, `fetchSlots` 30 and `enableSlot` 26 (`lib/router_slot_service.dart`), are full of stock-or-Merlin branches the abstraction would restructure anyway, so they're scored again after it and what's left is fixed then.

### 1.3. v1.0.0 iOS version

**Under way** since 2026-10-16, Andrew's decision. The items being built are in CHANGELOG 1.2; these wait on them or on Apple. Enrolling as an individual first (2026-10-19); an organisation later is optional (ID-421). Early thinking: `.claude/plans/plan_ios-port.md`.

- ID-426 REL: **Andrew enrols in the Apple Developer Program as an individual.** Andrew's decision, 2026-10-19: his legal name is already public as the Play Store seller.
  - At developer.apple.com/programs/enroll or in the Apple Developer app, with his Apple Account (legal name, two-factor on). US$99 a year, charged in Australian dollars. Apple may ask for photo ID.
  - **Done when:** the membership shows as active.
- ID-422 REL: **Andrew sets up the team in Xcode and App Store Connect.** Depends on ID-426.
  - Xcode: Settings > Accounts, sign in. Runner > Signing & Capabilities: the new team, "Automatically manage signing". Run once on each iPhone, so builds last a year instead of 7 days.
  - App Store Connect: Apps > + > New App, bundle ID `com.exponentiallydigital.cfgpiawg` (exact case), a name, language and SKU. This reserves the name and gives ID-417 its App Store link.
  - EU trader status (App Information > Digital Services Act): declare it, or leave the EU storefronts out.
  - **Done when:** signed builds run on all three iPhones, the app record exists, and the trader status is declared.
- ID-418 REL: **iOS releases: signing in CI, TestFlight, the App Store, release notes and the SBOM.** Depends on ID-405 and ID-422.
  - CI signs with an App Store Connect API key (App Manager role); its `.p8` file downloads once and lives only in GitHub secrets.
  - The first upload asks the export compliance question (the app uses SSH and HTTPS): answered with Andrew then.
  - The listing comes mostly from Play's. Decide whether to keep iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), which needs iPad screenshots.
  - Review notes: the reviewer has no ASUS router or PIA account, so a demo video and an explanation (guideline 2.1); that the app configures a router and offers no VPN itself (5.4); and the PIA name (5.2).
  - GPLv3 is fine while Andrew holds all the copyright (checked 2026-10-19: no GPL dependency, every commit his or a bot's). An outside contribution would need his permission to ship here.
  - **Done when:** a tagged release uploads a signed build to TestFlight, with App Store notes and an iOS SBOM.
- ID-424 ADD: **an iOS home screen widget like the Android one (ID-376).** Andrew's requirement, 2026-10-19; after ID-418, so it's built on a signed app that can reach TestFlight.
  - A WidgetKit extension in Swift, an App Group to share the status, and iOS's own background refresh (BGTaskScheduler), whose real frequency is measured on an iPhone before anything is promised. The key must be readable from the Keychain while the phone is locked. On iOS 17+ the refresh button runs an App Intent, so it may have to open the app.
  - Until then, ID-425 hides HOME SCREEN WIDGET KEY on iOS.
- ID-401 CHG: **RevenueCat on the App Store.** Needs the Paid Apps Agreement, banking and tax forms in App Store Connect first.
- ID-421 REL: **later, optional: move to an organisation membership, so the seller reads "Exponentially Digital".** Apple accepts only a legal entity that can sign contracts: "We do not accept DBAs, fictitious business names, trade names, or branches". A registered business name, as Exponentially Digital became with ASIC on 2026-10-19, isn't one, so this needs a company (a Pty Ltd, say), its D-U-N-S number, a public website and email on its domain, then a membership change through Apple support. The D-U-N-S number requested 2026-10-19 (Equifax up to 30 days; Apple's form up to 7) only helps here if it's for a company.
  - **Done when:** the App Store shows the organisation as the seller.
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
