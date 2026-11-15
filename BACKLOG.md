# BACKLOG.md

- [Prefix codes](#prefix-codes)
- [IDs](#ids)
- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. FTR - future implementation](#112-ftr---future-implementation)
    - [1.1.3. Unconfirmed BUGs](#113-unconfirmed-bugs)
  - [1.2. Codebase cleanup](#12-codebase-cleanup)
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

Work items here follow CHANGELOG.md's rule "Work items: less is better": what is to be done, at a high level, with `DoD:` and `Plan:` only when they earn their place, and no bold.

Once an ID is given, it does not change even if the item moves section (e.g. from Unconfirmed BUGs to a scheduled section once confirmed). Closed items retain their ID number.

---

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

 `<none>`

#### 1.1.2. FTR - future implementation

- ID-375 BLD: retire `tool/launcher_icons.dart` (ID-374) once a flutter_launcher_icons release changes only `ASSETCATALOG_COMPILER_APPICON_NAME`. The fix was proposed on [PR #549](https://github.com/fluttercommunity/flutter_launcher_icons/pull/549#issuecomment-6674977473), posted 2026-11-06.
  - DoD: such a release is out, and the wrapper and its notes in the build scripts, workflows, BUILDING, CONTRIBUTING and `pubspec.yaml` are gone.
- ID-462 FTR: sell the iOS app in France, once the French encryption declaration is accepted. Split from ID-430 on 2026-10-20, Andrew's decision: France is left out of the first App Store release so the declaration can't delay it. Selling in France needs the declaration uploaded in App Store Connect (`app-store/export_compliance.md`), then `ITSAppUsesNonExemptEncryption` YES and Apple's `ITSEncryptionExportComplianceCode` in `Info.plist`.
  - DoD: the declaration is accepted, the two keys are set with a test, and App Store Connect lists France.
- ID-024 FTR: decide whether and when to localise the app, starting with French, Spanish and Latin American Spanish. The groundwork and each language are ID-442 to ID-446.
  - DoD: decided, and those items sequenced or closed.
- ID-442 FTR: the app's text moves into Flutter's localisation files, English only, nothing visibly changed. Every on-screen string read through `AppLocalizations`.
  - DoD: no user-facing string literal is left in `lib/` outside the English file, a test fails if one is added, and the full suite passes.
- ID-443 FTR: the app in French. After ID-442.
  - DoD: a test runs every screen in French with no missing key, and a French speaker has read it.
- ID-444 FTR: the app in Spanish (Spain). After ID-442.
  - DoD: as ID-443, for `es`.
- ID-445 FTR: the app in Latin American Spanish. After ID-444.
  - DoD: as ID-443, for `es-419`.
- ID-446 FTR: the Play listing in each language the app is in, translated by hand. Google's automatic translations break the character limits.
  - DoD: the Update Play listing workflow publishes each, within Play's limits.
- ID-414 FTR: waiting on upstream: clear the Kotlin Gradle plugin warning once `home_widget` and `workmanager_android` stop applying the plugin. Split from ID-408 on 2026-10-16. Every build warns that future Flutter versions will fail with such plugins; on 2026-10-19 both were still the latest (`home_widget` 0.10.0, `workmanager` 0.10.10). Check each new release of the two, which ID-411's weekly upgrade brings, and each new Flutter's notes for when the warning becomes a failure: if that comes first, fork the plugin or hold Flutter back.
  - DoD: a local `flutter build apk` no longer prints the warning.
  - Plan: [plan_kgp-plugins.md](.claude/plans/plan_kgp-plugins.md)
  - Now: still the latest on 2026-11-15 (home_widget 0.10.0, workmanager_android 0.10.9), and the warning still prints with Gradle 9.9.1 and the Android Gradle plugin 9.5.1.
- ID-257 FTR: parked 2026-09-28 (Andrew's decision): a pilot of hand tests as Flutter integration tests on the emulator, against a real router. Start with SET, ROUTER LOG, ROUTER RESOLVER STATUS and ROUTER DNS ROUTING. It stopped because `integration_test` put `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile and brought new OSV findings (ID-058). Plan: `.claude/plans/plan_integration-test-pilot.md`.
  - To resume: lock the new libraries or exempt the debug build from locking.
  - DoD: the four groups run as integration tests against the router, and Andrew has judged whether to go further.
- ID-305 FTR: stock's mail sender moves to `mailsend-go` v1.0.13, so a failed send's diagnostics include the server's certificate (`-printCerts`). Diagnostics only: v1.0.12 already verifies the certificate when sending (`InsecureSkipVerify: !VerifyCert`), and upstream says there's "no need to update unless you need certificate details" (issue #76).
  - Work: new pins and SHA-256s for both architectures in `binary_installer.dart`, from the published checksums and recomputed on hardware; the archive member names; offering the update to routers on v1.0.12.
  - DoD: on stock, TEST EMAIL sends with v1.0.13, and a deliberately failed send prints the certificate in the app log.
- ID-127 FTR: contingency, not scheduled: ship our own `curl` if a firmware update breaks stock's two curl workarounds. Stock's `/usr/sbin/curl` refuses a caller with `crond` in its ancestry and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7); the script detaches from cron and uses hostnames with `--resolve`. Our own curl would make its TLS CVEs this project's job, outside the dependency scanning. Raised 2026-09-19.
  - Trigger: a firmware update breaks row 6 or 7. Until then there is nothing to do.
- ID-594 FTR: choose what carries the router's own DNS, on stock and Merlin: the firmware's choice, a named slot, or the internet connection. Today it's a side effect of which slot lists the router's own DNS servers as its DNS servers (the first to start on Merlin, the highest-numbered on stock). The design is a rule at priority 1010 for each of the router's DNS server addresses, into the chosen slot's table or a table holding only the WAN's default route, put back by the guard; it falls through to the firmware's choice when that slot is down. Raised 2026-11-15, and rewritten the same day: it first chose between slots sharing DNS servers, which the day's measurements showed matters only when the router's own DNS is among them.
  - First: Andrew decides whether to build it. His router's DNS already goes through wgc5 with no new code, by giving wgc5 the router's own DNS servers and keeping them off every other slot and watchdog.
  - DoD: on each firmware, through a reboot, `ip route get` shows the chosen route for each of the router's DNS servers, and `check-claims.sh` fails with the rule deleted by hand.
  - Plan: [plan_router-dns-slot.md](.claude/plans/plan_router-dns-slot.md)
  - Now: the rule measured on 388.13_0, 2026-11-15, one run: at 1010 it moved the router's route to 9.9.9.9 from wgc1 to wgc5, and to the WAN through a table of its own. Not yet seen through a reboot or with the slot stopped.
- ID-596 FTR: on Merlin, a BY RULE view in DEVICES that lists every VPN Director rule in the order VPN Director acts on them, and can switch any WireGuard or WAN rule on or off, or delete it, through DEVICES' apply path so the guard runs after every change. OpenVPN rules are listed, read-only. Raised 2026-11-15, after "wanpin" and "vd2" could only be switched off in the web UI. The UI is an agreed concept, still to be discussed.
  - DoD: on Merlin, a rule switched off or deleted in the app is gone from `ip rule` with the guard's `prohibit` for it, `check-claims.sh` fails with it put back by hand, and README and the store screenshots are checked.
  - Plan: [plan_vpn-director-rules.md](.claude/plans/plan_vpn-director-rules.md)
- ID-597 FTR: on Merlin, add and edit WireGuard and WAN rules in DEVICES' BY RULE view, ranges and remote addresses included; never OpenVPN. After ID-596. First, the guard's hold for a range sent to a tunnel is measured on the router, and Andrew decides whether a pinned device's remote address to the internet is refused or warned.
  - DoD: a range sent to a tunnel fails closed with the tunnel stopped, through a reboot, and `check-claims.sh` fails with the guard's rule for it deleted by hand.
  - Plan: [plan_vpn-director-rules.md](.claude/plans/plan_vpn-director-rules.md)
- ID-600 FTR: status for each slot from `wg show`, on stock and Merlin: the age of the latest handshake, data received and sent, and the endpoint, beside the watchdog's rebuilds from its log. The app already reads handshake ages (`kHandshakeAgesCommand`, DEVICES' tunnel health). Shown on NETWORK, beside each tunnel's public address (Andrew, 2026-11-15). Raised 2026-11-15.
  - Plan: [plan_network-tunnel-status.md](.claude/plans/plan_network-tunnel-status.md)
- ID-604 FTR: a speed test for each tunnel on NETWORK, on stock and Merlin: the router downloads and uploads a fixed amount through each tunnel in turn, and the card shows Mbit/s each way with the time it was taken. First, Andrew decides the server: Cloudflare's free endpoints, which see only the tunnel's PIA address, or no outside party, showing only the current rate from `wg show`'s byte counts. Then a test on stock to see whether the server can be reached below 128.0.0.0. Raised 2026-11-15.
  - Plan: [plan_network-tunnel-status.md](.claude/plans/plan_network-tunnel-status.md)

- ID-613 TST: the hand tests for build 581's fixes that weren't run, on stock and on the watchdog form. Stock: ID-609 (a slot DNS change in WATCHDOG restarts the slot and its devices use the new servers, WD-DNS), ID-610 (ROUTER DNS ROUTING's sentence for slot DNS servers the router's own DNS doesn't use), ID-612 (the watchdog form refuses Quad9 where stock's curl 7.84 may also lack HTTP/2, WD-DOH) and ID-606's DEVICES label for a profile deleted in the web interface. Merlin: WD-DNS through the app's screens, which build 581 covers with automated tests and the router-side measurement only. Raised 2026-11-16, the release run having only a Merlin router.
  - DoD: WD-DNS and WD-DOH run by hand on stock and on Merlin, ID-610's sentence read on stock, each result written in TESTING, and any failure a bug under its own ID.

#### 1.1.3. Unconfirmed BUGs

`<none>`

---

### 1.2. Codebase cleanup

`<none>`

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
