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

- ID-458 ADD: **a "Network" item on the main menu that shows the public IP address and provider of this device, and of each tunnel, using Cloudflare Radar.** Raised 2026-10-20 by Andrew. Cloudflare's assistant suggested an approach, which is recorded as given, and not yet checked, in `.claude/plans/plan_network-menu.md`: get the external IP (`https://1.1.1.1/cdn-cgi/trace` or ipify), then call Radar's `/radar/entities/ip` (location) and `/radar/entities/asns/ip` (provider) with a read-only API token. A follow-up answer, recorded in the same file, gives a way that needs no token and uses hostnames only: `https://ipinfo.io/json` returns both the IP and the provider (`org`, e.g. "AS12345 Example Provider"), and `https://cloudflare-dns.com/cdn-cgi/trace` gives the IP alone. The plan file's "Recommended design" section holds Claude's recommendation, not yet decided: the IP from the trace, sent from the phone and through each `wgcN` on the router; the provider from one Radar call on the phone, with the user's own token; PIA's region name instead of a town. A hand run on 2026-10-20 confirmed that one Radar call, `/radar/entities/ip`, returns the country and a readable provider name, so the second call isn't needed. The steps Andrew used to make the token are in the plan's "Getting a Radar token" section, for the setup instructions. It rules out ipinfo.io without a token, because its 1,000 requests a day are shared by everyone on the same IP, and a PIA exit IP has many users.
  - **To decide first:** Radar with a token, which every user would have to supply because one compiled into the app can be pulled out (its limit, 1,200 requests per 5 minutes per Cloudflare user, is ample at two requests per lookup, but each user needs a Cloudflare account), or ipinfo.io without one, once its rate limit and terms are read; how each tunnel's exit IP is read on the router, by a request sent out through `wgcN` to a hostname, since stock's curl refuses a URL whose host is an IP address (ID-127); and what the screen tells the user about sending the address to the lookup service.
  - **First probe:** a read-only paste block on stock showing whether `curl --interface wgcN` sends its request out through the tunnel, and not out through the ISP.
  - **Done when:** decided, the probe has been run, the chosen service's endpoints and terms are confirmed against its own documentation, and the build items are written with their own done-when.
  - **Decided, 2026-10-20 (Andrew):** the plan's recommended design: the IP and country from Cloudflare's trace, with no token; the provider from one Radar call, with a token each user supplies; PIA's region name, not a town.
  - **First probe, 2026-10-20:** neither of curl's ways of choosing a tunnel works on stock. `--interface wgcN` and `--interface <wgcN's address>` each printed nothing, for wgc1 and wgc5, the second the same way a ping from a tunnel's address leaves by the WAN (ID-396). Next: a second probe with the watchdog's own way through a tunnel (ID-078), a rule `to <address> iif lo lookup <table>` at priority 1000 for one request, checked with `ip route get` before the request is made.
  - **Second probe, 2026-10-20: it works.** With the rule in place, `ip route get` named the tunnel, and the trace answered through each one with an IP different from the WAN's and the country of the tunnel's region: wgc1 New Zealand, wgc5 Australia. The rules were gone afterwards. It waited for the watchdog's DNS probe lock first (ID-193), and the router build will too.
  - **Radar's licence, checked 2026-10-20:** Cloudflare's developer docs say data from the Radar API is under CC BY-NC 4.0, non-commercial, with exceptions by request on Radar's About page. This app is paid, so the decided design needs either Cloudflare's exception or another provider. IPinfo Lite, also one call per IP with a free token of the user's own, is CC BY-SA 4.0 by IPinfo's pages, commercial use allowed with attribution, unlimited, country and provider only. Left: Andrew's choice between the two; then the build items.
  - **Free tier, Andrew's decision, 2026-10-20:** NETWORK needs no unlock, as "looking is free" (the Play listing), and the exception request to Cloudflare says so. That includes each tunnel's lookup, though it briefly adds a routing rule on the router: the build makes NETWORK reachable without `Entitlement.isUnlocked`, with a test.
  - **Asked of Cloudflare, 2026-10-20:** Andrew is emailing Radar's contact for an exception to the CC BY-NC 4.0 licence. IPinfo Lite is the fallback if the answer is no or doesn't come.
  - **On hold, 2026-10-20, Andrew's decision:** moved from CHANGELOG WIP to BACKLOG so the iOS release comes first. Picked up again once Cloudflare answers the exception request, or with IPinfo Lite.
- ID-462 FTR: **sell the iOS app in France, once the French encryption declaration is accepted.** Split from ID-430 on 2026-10-20, Andrew's decision: France is left out of the first App Store release so the declaration can't delay it. Selling in France needs the declaration uploaded in App Store Connect (`app-store/export_compliance.md`), then `ITSAppUsesNonExemptEncryption` YES and Apple's `ITSEncryptionExportComplianceCode` in `Info.plist`.
  - **Done when:** the declaration is accepted, the two keys are set with a test, and App Store Connect lists France.
- ID-414 FTR: **waiting on upstream: clear the Kotlin Gradle plugin warning once `home_widget` and `workmanager_android` stop applying the plugin.** Split from ID-408 on 2026-10-16. Every build warns that future Flutter versions will fail with such plugins; on 2026-10-19 both were still the latest (`home_widget` 0.10.0, `workmanager` 0.10.10). Check each new release of the two, which ID-411's weekly upgrade brings, and each new Flutter's notes for when the warning becomes a failure: if that comes first, fork the plugin or hold Flutter back.
  - **Done when:** a local `flutter build apk` no longer prints the warning.
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

#### 1.1.3. Unconfirmed BUGs

 `<none>`

---

### 1.2. Codebase cleanup

The firmware abstraction, in slices, each on its own build and released on its own, with MAN, WD and DEV hand tests on stock and the MRL smoke test on Merlin before each release. It touches every path stock support landed on, so it starts after the release that carries ID-041 step 4. Plan: `.claude/plans/plan_firmware-abstraction.md`.

Sequenced into CHANGELOG 1.1 and 1.2 on 2026-10-20; nothing is left here.

Moved back from CHANGELOG 1.1 the same day, Andrew's decision: the iOS release and the NETWORK menu come first.

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
- ID-419 CHG: **the SonarCloud findings left in the watchdog and the slot service, after ID-452.** Split from ID-041 2026-10-16, Andrew's decision. On 2026-10-19: `uninstallFromRouter` 38, `deployWatchdog` 36, `validate` 30, `testEmail` 18 (`router_watchdog.dart`); `createConfigToSlot` 37, `fetchSlots` 30, `enableSlot` 22, `restartSlot` 19 (`router_slot_service.dart`).
  - **Done when:** SonarCloud shows none of the eight, each function only split, and the suite passes unchanged.

### 1.3. iOS version

**Under way** since 2026-10-16. In dependency order. GPLv3 is fine on the App Store while Andrew holds all the copyright, so an outside contribution needs his permission to ship there.

Sequenced into CHANGELOG 1.1 and 1.2 on 2026-10-20; nothing is left here.

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
