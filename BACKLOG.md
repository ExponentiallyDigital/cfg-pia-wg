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

- ID-021 DOC: Update Play Store description. The text in `play-store/description.md` and `description_short.md` is done (2026-09-15); this closes when ID-045 first publishes it.
- ID-057 REL: **Andrew: publish the Play Store listing text with the Update Play listing workflow (ID-045), when the new text should be the public description.** A store listing belongs to the app, not to a track - there is no separate Internal Testing description - so a real run replaces the app's main `en-AU` short and full descriptions for everyone, production and every testing track, once Google's review approves the change. Run it with check only first. To choose when an approved change goes live, turn on Managed publishing in Play Console before the real run. The workflow can be started only from `main`, since GitHub runs a manually triggered workflow only from the default branch. Closes ID-021.
- ID-130 DOC: **unwrap the Markdown that predates the no-wrap rule.** CONTEXT line 44 says `.md` files carry one logical unit per line and no hard wrap at any column, because a reworded sentence in a wrapped paragraph re-flows every line after it and a one-word change reads as a ten-line diff. Counted 2026-09-20 with a fence-aware check: ARCHITECTURE about 78 wrapped paragraph lines (the intro, device assignment, the service queue, the retractions), CONTEXT 47, README 34 in sections older than build 454, CHANGELOG 1 in a closed release block. All of it predates the rule; everything written since is clean. Wanted: one commit that touches nothing but line endings, on a quiet day - doing it alongside real work would bury that work in the diff.

#### 1.1.2. FTR - future implementation

- ID-024 FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- ID-143 FTR: add a feature to display the contents of /etc/resolv.conf. Put this in the OPTIONS menu.
- ID-135 FTR: add a feature to enable clearing offline devices from DEVICE ASSIGNMENT
- ID-025 FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ID-122 FTR: **refresh the ACTIVE badge without being asked.** `fetchSlots` reads the interface list once, when a screen is entered or after an action, so a tunnel that drops a moment later keeps its badge until the next action or the next visit. Deferred 2026-09-19 as the largest of the ID-092 findings and the least valuable in practice: every action already refreshes, so the stale window only matters on a screen left open. Wanted when it is built: a re-read when the app returns to the foreground, and a modest timer while MANAGE or WATCHDOG is open, paused while an action runs and stopped on dispose. ID-124 belongs with it - the app now reports a stop that left the interface up, and a self-refreshing badge is what keeps the two in step afterwards.
  - Checked and NOT faults, so nobody re-investigates them: a WireGuard server interface is `wgs1` and `fetchSlots` matches `wgc(\d)` only, so a running server cannot badge a client slot; and a tunnel someone enables in the router's own web interface badges here too, which is the badge doing its job - it reports the router, not what this app did.
- ID-127 FTR: **install our own `curl` beside `jq` and `mailsend-go`, if ASUS ever tighten their wrapper further.** `/usr/sbin/curl` polices both its caller and its URLs: it refuses to run with `crond` in its process ancestry, and refuses any URL whose host is an IP literal, in both cases silently with exit 0 and a line in `/jffs/curllst` (ARCHITECTURE section 2, rows 6 and 7). Both are worked around today - the script detaches itself from cron, and every request uses a hostname URL with `--resolve` - so this is an escape hatch, not a plan. Andrew raised it 2026-09-19 and the mechanism already exists: `BinaryInstaller` installs checksummed per-architecture binaries into `/jffs/cfg-pia-wg` and `mailsend-go` is already several megabytes. What it costs is why it is parked: shipping our own TLS stack makes CVE tracking this project's job, puts a binary outside the dependency scanning that covers everything else, and asks a user to trust a great deal more than a JSON parser. Revisit if a firmware update breaks row 6 or row 7.
- ID-153 ADD: feature to remove static DHCP entries
- ID-172 ADD: to the WATCHDOG LOG screen, a "REFRESH" command that refreshes the screen.
- ID-174 ADD: a feature to disable a device's Internet access in DEVICE ASSIGNMENT (parental feature). This will consist of an ENABLE/DSIABLE function against that device, by matching against MAC address and device name. Need to consider how to manage MAC address randomisation (Android/IPHONE etc) and/or how to manage devices which have "cryptic" or no device name. When disabled, that device loses all Internet connectivity (but retains LAN connectivity) until toggled to ENABLE.

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
3. **Sequence into batches.** Group the work items into logical implementation batches, following the same descending-importance ordering rule CHANGELOG already uses. Batches should reflect what makes sense to build and test together, not just priority order.
4. **Flag anything unclear.** Before moving anything, list any item where the requirement, scope, or expected behaviour needs clarification from Andrew. Wait for answers before proceeding on those specific items; the rest of the triage can continue.
5. **Move agreed items to WIP.** Once Andrew confirms the batching, move the agreed work items into CHANGELOG's `### 1.2. WIP` section. Take into account what's already in WIP, resequencing existing items if the combined set changes the intended build order. Remove moved items from this section.
6. **Do not start implementing.** Stop after the move and wait for Andrew to separately say to begin implementation.
7. **Reference work items in conversation.** When discussing work items, include the ID number and a very brief sentence that describes that item at the beginning of conversation.

---

- ID-138 DOC: create a vertical mermaid diagram that shows the workflows used by the BACKLOG and CHANGELOG processes, the funnels through which work items arrive, are triaged and implemented. Include all sub processes. Add to the end of ARCHITECTURE as an appendix titled "Process - BACKLOG and CHANGELOG management"
- ID-142 REL: update release push script title to include build number (so I can easily see what got puhsed from the actions workflow list)
- ID-144 FIX: with wgc1 and 5 enabled, both using Quad 9 and the router using 1.1.1.2 and 1.0.0.2 (DoT also set to CloudFlare), when Quad9 is selected you see "This address is also used for DNS on this router, so the watchdog own lookups would travel through this tunnel…". Yet the router isn't set to use Quad9, another tunnel is but not the router. This needs rethinking: either the conditional display logic is wrong (if I choose Google, which no tunnels or the router use, then this message goes away), or we need to state that this is for any other tunnels that use the same DNS address.
- ID-145 DOC: add a note to WATCHDOG section of README: if you enable email alerting and the "from" and "to" are the same email addresses, some providers (eg Gmail) may not show an email in your inbox - explain why this is, and check it actually still applies.
- ID-146 DOC: note in README/GPS description that an important feature of release +454 is enabling all Watchdog functions (PIA key registration, email alerts & `<is there anything else that goes out in the clear otherwise?>`) to use encrypted DNS for lookups - this means that `<insert benefit statement(s) here>`.
- ID-147 CHG: recheck the value of MAX VPNs when a slot or watchdog's CREATE button is selected, seems to cache the maxc vpns value until the screen is entered then returned to.
- ID-148 DOC: add to README how the app is designed to save rekeying fields, eg password manager support, watchdog details are offered for reuse once filled in.
- ID-149 DOC: add to benefits - visual styling and colourisation of log entries.
- ID-150 FIX: when a slot is deleted `wgcN_wd_doh_ip` and `wgcN_wd_doh_url` are not removed.
- ID-151 TST: add `logger **TEST XXX-n STARTED**` to all manual tests in TESTING.md so we can easily reconcile what was tested with what the router log contains. Also add `logger **TEST XXX-n ENDED**`. See `.claude\testing\2026-09-19_e2e.md` for examples of how I used this, it made  it much easier to see what was happening.
- ID-152 CHG: include the last 12 lines of router log in a failed watchdog email. Currently we show the last 10 lines which misses the new "SMTP host resolved privately to..." and the "cfg-pia-wg: wgc1: Alert email sent (FAILED)" log messages. I also noticed that when running test BRK-5 that my "logger" command was not shown in the email:
```
2026-09-20 22:35:01 Handshake 110s ago
2026-09-20 22:39:10 Watchdog started for wgc1 [script v0.8.88 build 458]
2026-09-20 22:39:10 Checking wgc1 pia-nz connectivity
2026-09-20 22:39:10 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-20 22:39:10 WAN has internet connectivity
2026-09-20 22:39:10 Connectivity lost; reconfiguring (attempt #1) [script v0.8.88 build 458]
2026-09-20 22:39:10 Using cached CA cert
2026-09-20 22:39:10 Name lookups encrypted via dns.quad9.net (9.9.9.9)
2026-09-20 22:39:10 Requesting PIA token for user p123456789
2026-09-20 22:39:11 ERROR: PIA rejected the username and password stored on this router (HTTP 403). The PIA username is the one PIA issued for the VPN, not an email address and not the router login. Fix it in the app: WATCHDOG, CREATE/EDIT, SAVE & DEPLOY.
```
This was what was actually recorded in the router log:
```
Sep 20 22:35:01 cfg-pia-wg: wgc1: Handshake 110s ago
Sep 20 22:39:10 router-admin: **TEST BRK-5 RUN-1 STARTED**
Sep 20 22:39:10 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.88 build 458]
Sep 20 22:39:10 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 20 22:39:10 cfg-pia-wg: wgc1: No handshake and both pings failed (8.8.8.8, 1.1.1.1)
Sep 20 22:39:10 cfg-pia-wg: wgc1: WAN has internet connectivity
Sep 20 22:39:10 cfg-pia-wg: wgc1: Connectivity lost; reconfiguring (attempt #1) [script v0.8.88 build 458]
Sep 20 22:39:10 cfg-pia-wg: wgc1: Using cached CA cert
Sep 20 22:39:10 cfg-pia-wg: wgc1: Name lookups encrypted via dns.quad9.net (9.9.9.9)
Sep 20 22:39:10 cfg-pia-wg: wgc1: Requesting PIA token for user p123456789
Sep 20 22:39:11 cfg-pia-wg: wgc1: ERROR: PIA rejected the username and password stored on this router (HTTP 403). The PIA username is the one PIA issued for the VPN, not an email address and not the router login. Fix it in the app: WATCHDOG, CREATE/EDIT, SAVE & DEPLOY.
```
- ID-154 FIX: after devices are assigned to the Internet, because the wgc that they were pinned to is deleted, device names are correctly shown in the DEVICE ASSIGNMENT screen but not in app log. See .claude\testing\2026-09-19_e2e.md test "**DEV-15** Delete a VPN with devices on it".
- ID-155 FIX: (see ID-180) credentials not cached when ABOUT screen "login to router to retrieve" is selected. On ROUTER LOG if cancel is selected screen opens and shows "no log read yet" instead of returning to the HOME screen (or wherever the user entered from). Check the whole codebase to ensure that once successfully logged in, then credentials are cached in memory.
- ID-156 FIX: if the hamburger menu is entered from the HOME screen, then the HOME entry is not shown with a different background colour. In other screen when the hamburger menu is showing say ROUTER LOG, then the background for that entry is showing in a different colour, which is correct.
- ID-157 CHG: on ABOUT screen, if the installed script is a greater build number than the installed app, in the example below make the text "v0.8.87 build 457" appear in red and retain the text "v0.8.88 build 458" in amber and retain the button UPDATE WATCHDOG VERSION (this situation occurred when using a Play Store installed version)
```
cfg-pia-wg: v0.8.87 build 457
Watchdog script: v0.8.88 build 458
```
- ID-158 FIX: in the WATCHDOG LOG, when a watchdog is first deployed, there is inconsistent colorisation of messages and the colours do not match the colour style of the ROUTER LOG screen which shows watchdog message in lavender. Do not colourise the "Not connected yet: no handshake, and no answer from 8.8.8.8 or 1.1.1.1" in red - this isn't an error on a first deploy, so colourise that line in lavender. Use a consistent colour scheme that matches that used by ROUTER LOG.
- ID-159 FIX: (afterwards I found that this statement was wrong, as not all watchdogs were using Quad 9, I didn't record which slots were using what DNS, but I think wgc5 was using CloudFlare - investigate but don't guarantee that I got who was using what DSN correct, apart from the router which is definitely using Cloudflare) with the router using CloudFlare for DNS and DoT, the default connection set to wgc5, Quad9 used by wgc5, wgc3 and wgc1, then messages are sometimes logged that a name lookup could not be done through a tunnel and a message logged that "cfg-pia-wg: wgc1: wgc1: no answer from 9.9.9.9; one more and it counts as broken" (also notice how the log messages contains "wgc1: wgc1") yet the tunnel appears to be OK. Router log excerpt:
```
Sep 21 07:10:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:10:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:10:00 cfg-pia-wg: wgc1: Handshake 89s ago
Sep 21 07:10:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:10:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:10:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:10:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:10:00 cfg-pia-wg: wgc5: Handshake 80s ago
Sep 21 07:10:00 cfg-pia-wg: wgc3: Handshake 113s ago
Sep 21 07:10:06 cfg-pia-wg: wgc1: wgc1: no answer from 9.9.9.9; one more and it counts as broken
Sep 21 07:15:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:15:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:15:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:15:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:15:00 cfg-pia-wg: wgc5: Handshake 12s ago
Sep 21 07:15:00 cfg-pia-wg: wgc1: Handshake 14s ago
Sep 21 07:15:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:15:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:15:00 cfg-pia-wg: wgc3: Handshake 39s ago
Sep 21 07:15:06 cfg-pia-wg: wgc1: wgc1: no answer from 9.9.9.9; one more and it counts as broken
Sep 21 07:19:56 dropbear[1633]: Password auth succeeded for 'router-admin' from 192.168.1.20:55708
Sep 21 07:20:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:20:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:20:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:20:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:20:00 cfg-pia-wg: wgc3: Handshake 88s ago
Sep 21 07:20:00 cfg-pia-wg: wgc5: Handshake 71s ago
Sep 21 07:20:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:20:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:20:00 cfg-pia-wg: wgc1: Handshake 64s ago
Sep 21 07:25:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:25:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:25:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:25:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:25:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:25:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:25:00 cfg-pia-wg: wgc3: Handshake 14s ago
Sep 21 07:25:00 cfg-pia-wg: wgc5: Handshake 114s ago
Sep 21 07:25:00 cfg-pia-wg: wgc1: Handshake 114s ago
Sep 21 07:25:00 cfg-pia-wg: wgc5: Could not aim a lookup at 9.9.9.9 through wgc5; skipping the name check
Sep 21 07:25:00 cfg-pia-wg: wgc1: Could not aim a lookup at 9.9.9.9 through wgc1; skipping the name check
Sep 21 07:26:24 dropbear[3104]: Password auth succeeded for 'router-admin' from 192.168.1.20:48244
Sep 21 07:30:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:30:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:30:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:30:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:30:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:30:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:30:00 cfg-pia-wg: wgc3: Handshake 64s ago
Sep 21 07:30:00 cfg-pia-wg: wgc5: Handshake 10s ago
Sep 21 07:30:00 cfg-pia-wg: wgc1: Handshake 37s ago
Sep 21 07:30:00 cfg-pia-wg: wgc1: Could not aim a lookup at 9.9.9.9 through wgc1; skipping the name check
Sep 21 07:35:00 cfg-pia-wg: wgc3: Watchdog started for wgc3 [script v0.8.87 build 457]
Sep 21 07:35:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.87 build 457]
Sep 21 07:35:00 cfg-pia-wg: wgc3: Checking wgc3 pia-au_brisbane-pf connectivity
Sep 21 07:35:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 21 07:35:00 cfg-pia-wg: wgc3: Handshake 114s ago
Sep 21 07:35:00 cfg-pia-wg: wgc5: Handshake 60s ago
Sep 21 07:35:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.87 build 457]
Sep 21 07:35:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 21 07:35:00 cfg-pia-wg: wgc1: Handshake 86s ago
```
- ID-160 CHG: offset watchdog cru entries so that they start at different seconds intervals. If you have multiple watchdogs running then the sequence of messages displayed in the router log is hard to see, with watchdog messages from different watchdogs intermixed chronologically. For example, start wgc5 at 00s, wgc4 at 10s, wgc4 at 20s, wgc4 at 30s, and wgc5 at 40s. This could be done through a sleep command in the watchdog scripts.
- ID-161 FIX: a watchdog log message that contains "Could not aim a lookup at 9.9.9.9 through wgc1; skipping the name check" should appear as an error in red(?). Discuss this with me first, as I'm unsure why this occurs as the tunnel appears ok.
- ID-162 DOC: note that ASUS WebUi > USB Application > Download Master, may not appear after/when cfg-pia-wg is using that hook for persistence.
- ID-163 DOC: why do devices use only the first DNS server when two are specified, eg in MANAGE > EDIT
- FIX: after unable to save a watchdog, the edit dialogue remains on screen, after selecting CANCEL, the WATCHDOG CONFIGURATION screen shows the watchdog is paused.
- ID-164 FIX: This message "This address is also used for DNS on this router, so the watchdog's own lookups would travel through this tunnel - the one it exists to repair. Choose an address nothing else uses." shows when the router is set to use CF and selected Quad 9 for wgc1 - wgc5 is also set to Quad9. Was expecting to not see that unless I chose CF as the DNS.
- ID-165 FIX: in DEVICE MANAGEMENT, a device is showing up as online when it has been switched off for > 48 hours. Check the code path that reads the ASUS list of devices; in the ASUS WebApp, that device is correctly showing as offline.
- ID-166 GUI: assets\Icon\app_icon_legacy.png isn't being displayed as the app splash screen when the app loads; either `assets\Icon\app_icon_legacy.png` or `assets\Icon\app_icon_foreground.png` are being used instead.
- ID-167 FIX: after a failed deploy due to the script being unable to land on the router, and followed by manually updating the script via the ABOUT menu, no deployment email was sent/received (test email was successfully received).
- ID-168 GUI: the slot edit modal's VIEW ROUTER WATCHDOG's grey text makes it look like the item can't be selected, instead use the same colour as ROUTER LOG on the main menu, or a more muted version but in the same lavender colour space.
- ID-169 BUG?: is the DNS probe working correctly? Received "Sep 19 09:30:06 cfg-pia-wg: wgc1: wgc1: no answer from 9.9.9.9; one more and it counts as broken" (FIX the repeating log text "wgc1: wgc1:"). Do we need additional logging from the DNS probe in the router log? Context from the router log:
Sep 19 09:30:00 cfg-pia-wg: wgc1: Handshake 10s ago
Sep 19 09:30:01 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.88 build 458]
Sep 19 09:30:01 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 19 09:30:01 cfg-pia-wg: wgc5: Handshake 98s ago
Sep 19 09:30:06 cfg-pia-wg: wgc1: wgc1: no answer from 9.9.9.9; one more and it counts as broken
Sep 19 09:31:02 dropbear[16643]: Password auth succeeded for 'router-admin' from 192.168.1.20:59476
Sep 19 09:34:30 dropbear[17492]: Password auth succeeded for 'router-admin' from 192.168.1.21:45064
Sep 19 09:34:53 cfg-pia-wg: Laptop: default - wgc5:pia-aus_melbourne -> wgc5:pia-aus_melbourne reassigned
Sep 19 09:34:53 rc_service: service 17649:notify_rc restart_dnsmasq
Sep 19 09:34:53 rc_service: service 17659:notify_rc restart_vpnc_dev_policy
Sep 19 09:35:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.88 build 458]
Sep 19 09:35:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.88 build 458]
Sep 19 09:35:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity
Sep 19 09:35:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity
Sep 19 09:35:00 cfg-pia-wg: wgc5: Handshake 36s ago
Sep 19 09:35:00 cfg-pia-wg: wgc1: Handshake 69s ago
- ID-170 GUI: the new WATCHDOG EDIT slot modal doesn't empty the "watchdog's own encrypted DNS", instead the fields retain the last drop down selected when "Something else" is selected.
- ID-173 GUI: MANAGE badges a slot ACTIVE whenever its interface is up and handshaking, and never looks at whether VPN Fusion has the profile enabled. The two can disagree - ID-172 is one way to get there, and the row then reads `ACTIVE` while ENABLE is also offered, which is the contradiction that gave the bug away. Wanted: keep ACTIVE meaning up and answering, and add a warning when the interface is up while `vpnc_clientlist` says the profile is off - something like "running outside VPN Fusion; it will not come back after a restart". Discuss the wording first.
- ID-174 FIX: `_revertEnable` throws away the result of `_awaitInterfaceDown` (`lib/router_slot_service.dart`), so an ENABLE that fails its checks and then fails to stop the tunnel still tells the user the slot was left disabled. `disableSlot` returns that same result and the caller reports it (ID-124); the revert path should say it too. Found while diagnosing ID-172; not observed in the field yet, so it is here rather than in the release.
- ID-175 FIX: ./scripts/clearall.sh must set `vpnc_max_conn=2` to match stock. Must also remove `wgcN_wd_doh_ip` and `wgcN_wd_doh_url`
- ID-176 REL: fix warning in `Quality & security` actions script: "CodeQL (java-kotlin) Cannot build an overlay database because build-mode is set to "manual" instead of "none". Falling back to creating a normal full database instead."
- ID-177 DOC: say in README how much testing is behind a release. It sits well beside the "Professional-grade build chain" bullet in the security and quality list, where SonarQube is already named for coverage. Wanted: the number of automated tests (1185 as at build 458) and the number of manual end-to-end tests (152 in TESTING.md, of which 13 need a build distributed by Play), the target of at least 80% line coverage that CONTRIBUTING and CONTEXT both set, and an invitation to read the live figure rather than a number that will rot - the Coverage badge at the top of README already links to SonarCloud, which said 93.6% when this was written. Both counts are one command each: `flutter test` prints the automated total, and the manual one is `grep -cE '^\*\*[A-Z]{2,3}-[0-9]+\*\* ' TESTING.md`. Note in the text that the manual run sheet is public, so a reader can see exactly what is tested by hand.
- ID-178 REL: update workflow run title to include the build number: "Promote - internal to alpha" becomes "Promote build 488 - internal to alpha"; also set the default when promoting to not target internal to production, target internal to alpha, tyhen beta, then at teh bottom of the loist have production and make it stand out with "** PRODUCTION **".
- ID-179 REL: fix worklo run warning raised by promote.yml "Promote Google Play Track Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: kevin-david/promote-play-release@d1ed59ca4fd7456b9d8cae062a3684e93b412425. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/".
- ID-180 FIX: credentials are not auto filled/saved if you use the links in ABOUT to login to the router and they're not cached there either, see ID-155.
- ID-181 DOC: check for lines that don't remder in Mermnain diagrams, eg ARCHITECURE section 7.3 hasa mermain diagram with a partially visible text fragment that's cut off when rendered on screen "abort - bump the failure counter, send the failure alert".
- ID-182 GUI: anywhere in a user facing dialogue box or popup that we say that only the first DNS server is used needs to be removed. Why? It's not correct technically. eg on watchdog edit modal under the "DNS Servers" field it states that "Devices assigned to this VPN use only the first serverr...".
