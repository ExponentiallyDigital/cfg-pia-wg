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

- ID-135 FTR: add a feature to enable clearing offline devices from DEVICE ASSIGNMENT
  - Merged in 2026-09-28, from ID-153 ("feature to remove static DHCP entries"): pinning a device reserves its address in `dhcp_staticlist`, and unpinning leaves the reservation behind; neither the router nor the app removes it (ARCHITECTURE 6.8.3). **Andrew's decision: the app does not delete reservations.** People can use the web interface if they want to. Removing one there restarts the whole network (it dropped a 5 GHz laptop's remote-desktop session), and a device keeps its address until a later renewal, so a removal can break a pin silently days later (ARCHITECTURE 6.3). Whatever this item becomes, it stays clear of reservations.
- ID-229 FTR: add pinch to zoom when displaying log files (router, app, watchdogs).
- ID-127 FTR: **install our own `curl` beside `jq` and `mailsend-go`, if ASUS ever tighten their wrapper further.** `/usr/sbin/curl` polices both its caller and its URLs: it refuses to run with `crond` in its process ancestry, and refuses any URL whose host is an IP literal, in both cases silently with exit 0 and a line in `/jffs/curllst` (ARCHITECTURE section 2, rows 6 and 7). Both are worked around today - the script detaches itself from cron, and every request uses a hostname URL with `--resolve` - so this is an escape hatch, not a plan. Andrew raised it 2026-09-19 and the mechanism already exists: `BinaryInstaller` installs checksummed per-architecture binaries into `/jffs/cfg-pia-wg` and `mailsend-go` is already several megabytes. What it costs is why it is parked: shipping our own TLS stack makes CVE tracking this project's job, puts a binary outside the dependency scanning that covers everything else, and asks a user to trust a great deal more than a JSON parser. Revisit if a firmware update breaks row 6 or row 7.
- ID-024 FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- ID-257 FTR: **pilot: hand tests run as Flutter integration tests.** The real app, on the emulator, against the real router: the test taps through a flow, checks the screen, and checks the router over its own SSH connection. Pilot on groups that need no PIA login: SET, ROUTER LOG, ROUTER RESOLVER STATUS and ROUTER DNS ROUTING. Judge it before going further. Needs a router the test can put in a known state, and credentials kept out of the repo. What stays by hand: anything physical, emails arriving, the password manager, Play installs and purchases. **Parked 2026-09-28 (Andrew's decision), before it was run:** the pilot is written and kept in `.claude/plans/plan_integration-test-pilot.md`, outside the build. The `integration_test` package puts `androidx.test`, `junit` and `guava` into the debug build, so the strict Gradle lockfile broke `flutter run` and CI's debug build; locking them also moved RevenueCat in the debug build and brought `junit` and `guava` findings into the OSV scan (ID-058). Revisit after the release: lock the new libraries or exempt the debug configurations from locking, then follow the plan's steps.

#### 1.1.3. Unconfirmed BUGs

- ID-129 BUG: **an alert email that could not be delivered, reported as `server misbehaving`.** Seen once, 2026-09-06: the watchdog had something to say and the mailer could not resolve the SMTP host. The phrase is Go's resolver saying the DNS server answered with a failure rather than an address. Recorded here because closing ID-001 would otherwise bury it: that item first suspected the router's own lookups riding a tunnel, then ruled it out - `/etc/resolv.conf` listed the WAN's servers first at the time - so the cause is open. Probably prevented rather than explained by ID-077, which resolves the SMTP host over encrypted DNS and hands the mailer an address, so it no longer looks anything up. If it recurs on build 455 or later, the watchdog log now says whether the private lookup worked, which is the first thing to read.
- ID-219 BUG?: **the router lost its settings during the guard runsheet, cause not yet known.** 2026-09-24, build 461, stock firmware. Sequence from the syslog: 10:53:09 an APPLY wrote `vpnc_dev_policy_list` and committed; 10:53:30 the app rebooted the router; during that boot the kernel logged `jffs2: check_node_data: wrong data CRC in data node` - the first CRC error in the log (the `Summary too big` warnings appear on every boot and are not new). 10:55:20 tunnels, guard and firmware rules all present; 10:56:22 `nvram get wgc1_ppub` returned nothing; 10:56:32 the watchdog read an empty region and empty check targets for wgc1 (`Checking wgc1  connectivity`, pings `(, )`), and wgc5 the same at 11:00. DESKTOP, pinned to wgc1, had no internet - the guard doing its job once the tunnel had no configuration. After a reboot with `guard.sh` deleted there were no guard rules and DESKTOP was still offline, and the web interface then offered the first-time setup wizard; Andrew restored his saved router configuration. Nothing the app ran that session removes a VPN setting: the guard only reads NVRAM, APPLY writes one key and commits, UPDATE WATCHDOG VERSION writes files. Not ruled out: the app's writes to /jffs and its reboots coinciding with a flash fault. The loss happened ACROSS the 10:53 reboot, not while the router was running: at 10:44:40 `wg show interfaces` listed `wgc1 wgc5 wgs1`, and at 10:55:20, straight after that boot, `wgc1 wgc5` - the WireGuard server's settings were already gone. The only NVRAM commit shortly before it was that APPLY, 21 seconds earlier; the reboots at 10:18 and 10:43, with no recent commit, were clean. One case, so suggestive and not proven. After Andrew restored his saved configuration the router is clean: /jffs 6% used, no CRC errors in `dmesg`, the file-backed settings under /jffs/nvram present, `wgc1_desc` back. One more piece that may belong to it: earlier that morning, from 10:26, `restart_vpnc_dev_policy` stopped writing the firmware's per-device tunnel rules at priority 100, even when asked by hand with no guard rules present; on the same router after the reset and reload, it wrote them straight after every APPLY, as it did on 2026-09-21. So that was probably an early symptom of the same fault rather than how the firmware behaves. Parked 2026-09-24 by Andrew: not reproduced on purpose. If it happens again, before restarting anything: from a LAN device `ping 1.1.1.1`, `nslookup google.com`, `nslookup google.com 9.9.9.9`; on the router the ID-195 capture list (`ip rule show`, the main and tunnel tables, `vpnc_default_wan`, `vpnc_unit`, `vpnc_dev_policy_list`, `/tmp/resolv.dnsmasq`, NAT POSTROUTING, `wg show interfaces`, the slot and router DNS keys, the `iif lo` rules, `ps | grep -E 'stubby|dnsmasq'`, `nslookup google.com 127.0.0.1`), plus for this item `dmesg | grep -i jffs2`, `nvram get wgc1_desc`, and a copy of `/tmp/syslog.log` and `/jffs/syslog.log` before any reboot.
- ID-195 BUG?: the 2026-09-23 21:52 outage is unexplained and needs a state capture next time. Known: phone and media centre had no internet while both tunnels were up, both watchdogs were content and the WebUI showed two tunnels up with the default where expected. `restart_net_and_phy` at 22:13:48 rebuilt every ip rule and restarted both tunnels and did NOT fix it; the reboot at 22:17:24 did. That clears stale routing rules (ID-183 territory) and the tunnels themselves. Candidate one, the router's resolver: dnsmasq was restarted at 22:13:52 but stubby was not, and the reboot restarted both. Today's check shows both slots on Quad9 only, so the ID-164 path (router DoT sent through a tunnel by an `iif lo` rule) is not it. Candidate two, the 5 GHz radio, for the media centre alone: it sat on DFS channel 52 all day, flapping between 80 and 160 MHz; the media centre first appeared on Wi-Fi 18 seconds after acsd left 52 for 44 at 22:12:06, fell to 2.4 GHz when `restart_net_and_phy` put the radio on 64 (DFS again), and stayed on 5 GHz all night once the reboot landed on 40. That does not explain the phone. Next time, BEFORE restarting anything: from a LAN device `ping 1.1.1.1`, `nslookup google.com`, `nslookup google.com 9.9.9.9` (address works, first lookup fails, second works = router resolver, tunnels innocent); on the router `ip rule show; ip route show table main; ip route show table 5; ip route show table 9; nvram get vpnc_default_wan; nvram get vpnc_unit; nvram get vpnc_dev_policy_list; cat /tmp/resolv.dnsmasq; ps | grep -E 'stubby|dnsmasq'; nslookup google.com 127.0.0.1; wg show interfaces`. Meanwhile, pinning 5 GHz to a non-DFS channel costs nothing and removes candidate two.

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
- ID-260 BLD: `flutter_launcher_icons` makes no iOS icons: none could be found after a build (release-candidate run, PRE-5). Set its iOS options, or make them another way, when the iOS port starts.

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
