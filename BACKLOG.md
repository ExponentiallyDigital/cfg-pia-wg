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

When adding several items in one sitting, look up the highest existing ID once, then increment by one for each new item in that batch.

Once an ID is given, it does not change even if the item moves section (e.g. from Unconfirmed BUGs to a scheduled section once confirmed). Closed items retain their ID number.

---

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- ID-019 DOC: Update `README.md` screenshots. Assigned to Andrew, with its own commit.
- ID-020 DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app). Assigned to Andrew, with its own commit.
- ID-022 DOC: Update Play Store screenshots. Assigned to Andrew, with its own commit.
- ID-021 DOC: Update Play Store description. The text in `play-store/description.md` and `description_short.md` is done (2026-09-15); this closes when ID-045 first publishes it.
- ID-057 REL: **Andrew: publish the Play Store listing text with the Update Play listing workflow (ID-045), when the new text should be the public description.** A store listing belongs to the app, not to a track - there is no separate Internal Testing description - so a real run replaces the app's main `en-AU` short and full descriptions for everyone, production and every testing track, once Google's review approves the change. Run it with check only first. To choose when an approved change goes live, turn on Managed publishing in Play Console before the real run. The workflow can be started only from `main`, since GitHub runs a manually triggered workflow only from the default branch. Closes ID-021.

- ID-130 DOC: **unwrap the Markdown that predates the no-wrap rule.** CONTEXT line 44 says `.md` files carry one logical unit per line and no hard wrap at any column, because a reworded sentence in a wrapped paragraph re-flows every line after it and a one-word change reads as a ten-line diff. Counted 2026-09-20 with a fence-aware check: ARCHITECTURE about 78 wrapped paragraph lines (the intro, device assignment, the service queue, the retractions), CONTEXT 47, README 34 in sections older than build 454, CHANGELOG 1 in a closed release block. All of it predates the rule; everything written since is clean. Wanted: one commit that touches nothing but line endings, on a quiet day - doing it alongside real work would bury that work in the diff.
#### 1.1.2. FTR - future implementation

- ID-024 FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- ID-025 FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ID-122 FTR: **refresh the ACTIVE badge without being asked.** `fetchSlots` reads the interface list once, when a screen is entered or after an action, so a tunnel that drops a moment later keeps its badge until the next action or the next visit. Deferred 2026-09-19 as the largest of the ID-092 findings and the least valuable in practice: every action already refreshes, so the stale window only matters on a screen left open. Wanted when it is built: a re-read when the app returns to the foreground, and a modest timer while MANAGE or WATCHDOG is open, paused while an action runs and stopped on dispose. ID-124 belongs with it - the app now reports a stop that left the interface up, and a self-refreshing badge is what keeps the two in step afterwards.
  - Checked and NOT faults, so nobody re-investigates them: a WireGuard server interface is `wgs1` and `fetchSlots` matches `wgc(\d)` only, so a running server cannot badge a client slot; and a tunnel someone enables in the router's own web interface badges here too, which is the badge doing its job - it reports the router, not what this app did.
- ID-127 FTR: **install our own `curl` beside `jq` and `mailsend-go`, if ASUS ever tighten their wrapper further.** `/usr/sbin/curl` polices both its caller and its URLs: it refuses to run with `crond` in its process ancestry, and refuses any URL whose host is an IP literal, in both cases silently with exit 0 and a line in `/jffs/curllst` (ARCHITECTURE section 2, rows 6 and 7). Both are worked around today - the script detaches itself from cron, and every request uses a hostname URL with `--resolve` - so this is an escape hatch, not a plan. Andrew raised it 2026-09-19 and the mechanism already exists: `BinaryInstaller` installs checksummed per-architecture binaries into `/jffs/cfg-pia-wg` and `mailsend-go` is already several megabytes. What it costs is why it is parked: shipping our own TLS stack makes CVE tracking this project's job, puts a binary outside the dependency scanning that covers everything else, and asks a user to trust a great deal more than a JSON parser. Revisit if a firmware update breaks row 6 or row 7.

#### 1.1.3. Unconfirmed BUGs

- ID-129 BUG: **an alert email that could not be delivered, reported as `server misbehaving`.** Seen once, 2026-09-06: the watchdog had something to say and the mailer could not resolve the SMTP host. The phrase is Go's resolver saying the DNS server answered with a failure rather than an address. Recorded here because closing ID-001 would otherwise bury it: that item first suspected the router's own lookups riding a tunnel, then ruled it out - `/etc/resolv.conf` listed the WAN's servers first at the time - so the cause is open. Probably prevented rather than explained by ID-077, which resolves the SMTP host over encrypted DNS and hands the mailer an address, so it no longer looks anything up. If it recurs on build 455 or later, the watchdog log now says whether the private lookup worked, which is the first thing to read.

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
- ID-041 CHG: **analyse and fix the 35 issues reported by the [Sonar Cloud scan](https://sonarcloud.io/project/issues?id=ExponentiallyDigital_cfg-pia-wg&s=IMPACT_RANK&issueStatuses=OPEN%2CCONFIRMED)**, cognitive complexity first. Write a plan and have Andrew approve it before any code changes. On hold with the rest of this section: the changes are likely extensive, with a high blast radius (triaged 2026-09-15).
- ID-059 CHG: **remove `RouterWatchdog.waitForWatchdogReady`, which nothing in the app calls.** It polls `getWatchdogStatus` until the watchdog reports enabled. Its only caller is its own test, `waitForWatchdogReady resolves once the interface becomes present` in `test/router_watchdog_service_test.dart`, which goes with it. Found 2026-09-15 while checking what reads `wgcN_enable`; `.claude/plans/plan_watchdog-modal-changes.md` had already noted it as unused. Wait until a release with the current watchdog has soaked in, as with the rest of this section: the watchdog is working correctly and this is tidying, not a fix.

### 1.3. v1.0.0 iOS version

**Parked** - US$99/year Apple Developer Program against an unknown iOS user base. Early thinking, and what actually blocks it: `.claude/plans/plan_ios-port.md`.

- The router half ports for free: `dartssh2` is pure Dart, and the watchdog script runs on the router, which does not care what phone deployed it.
- The platform hardening does not. `FLAG_SECURE` has **no iOS equivalent** - screenshots cannot be blocked, only the task-switcher snapshot can be covered. `README.md` and `SECURITY.md` state that guarantee unconditionally today and would need to state it per-platform.
- The silent clipboard clear is an Android method channel (`ClipboardManager.clearPrimaryClip()`); iOS needs `UIPasteboard.general.items = []` or the 60-second auto-clear regresses to the system copy popup that 403 removed.
- Non-code costs: a Mac or hosted runner for signing, a materially stricter App Store review, and a release pipeline (`release.yml`, SBOM, Gradle lockfiles) that is Android-shaped throughout.
- Extend RevenueCat to use Apple Store.
- ID-029 DOC: phrase the hardening claims in `README.md` and `SECURITY.md` as "on Android" rather than absolutely, so an iOS build cannot quietly make them untrue.

---

## 2. New work items

Andrew adds new items here as he finds them, unsequenced, unprioritised, and often without an `ID-NNN` - items in this section may not have an ID until they're moved into CHANGELOG.

**Triage prompt for Claude Code:**

When asked to triage BACKLOG new work, work through it in this order:

1. **Check for duplicates.** For each item in this section, check whether it duplicates or overlaps with anything already in CHANGELOG's Pending, WIP, or Implemented history, or an existing BACKLOG item elsewhere in this file. Flag any overlap found rather than silently merging or dropping it.
2. **Add a unique ID to any work item below that does not already have one.** Assign each item its `ID-NNN`. Search both CHANGELOG.md and BACKLOG.md for the highest existing ID and increment from there.
2. **Sequence into batches.** Group the work items into logical implementation batches, following the same descending-importance ordering rule CHANGELOG already uses. Batches should reflect what makes sense to build and test together, not just priority order.
3. **Flag anything unclear.** Before moving anything, list any item where the requirement, scope, or expected behaviour needs clarification from Andrew. Wait for answers before proceeding on those specific items; the rest of the triage can continue.
4. **Move agreed items to WIP.** Once Andrew confirms the batching, move the agreed work items into CHANGELOG's `### 1.2. WIP` section. Take into account what's already in WIP, resequencing existing items if the combined set changes the intended build order. Remove moved items from this section.
5. **Do not start implementing.** Stop after the move and wait for Andrew to separately say to begin implementation.
6. **Reference work items in conversation.** When discussing work items, include the ID number and a very brief sentence that describes that item at the beginning of conversation.

---
