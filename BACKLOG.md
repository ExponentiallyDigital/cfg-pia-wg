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
- ID-229 FTR: pinch to zoom in the log windows: ROUTER LOG, APP LOG and the watchdog log.
- ID-127 FTR: **ship our own `curl` beside `jq` and `mailsend-go`, if ASUS tighten their wrapper further.** Stock's `/usr/sbin/curl` silently refuses a caller with `crond` in its ancestry, and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7). Both are worked around: the script detaches from cron, and every request uses a hostname with `--resolve`. `BinaryInstaller` could ship one, but a TLS stack of our own makes its CVEs this project's job, sits outside the dependency scanning, and asks users to trust far more than a JSON parser. Revisit only if a firmware update breaks row 6 or 7. Raised 2026-09-19.
- ID-024 FTR: localise into French, Spanish and Latin American Spanish, then decide on more. Translate the Play listing by hand: Google's automatic translations break its character limits.
- ID-257 FTR: **pilot: hand tests as Flutter integration tests.** The real app, on the emulator, taps through a flow, checks the screen, and checks the real router over its own SSH connection. Start with groups that need no PIA login (SET, ROUTER LOG, ROUTER RESOLVER STATUS, ROUTER DNS ROUTING), and judge it before going further. Needs a router the test can reset to a known state, and credentials kept out of the repo. Stays by hand: anything physical, emails arriving, the password manager, Play installs and purchases. **Parked 2026-09-28, unrun (Andrew's decision):** the `integration_test` package puts `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile; locking them moved RevenueCat in the debug build and brought `junit` and `guava` findings into the OSV scan (ID-058). The plan is `.claude/plans/plan_integration-test-pilot.md`. To resume: lock the new libraries or exempt the debug build from locking, then follow the plan.

#### 1.1.3. Unconfirmed BUGs

- ID-291 BUG?: **the SSH connection dropped after two minutes in the background.** EXT-4 expects it to last 5 minutes; the app log shows a drop and reconnect at 2, and the router one more login. Find out whether Android or the router closed it, then fix the grace period or the test. EXT-5 wasn't run: the router drops idle SSH connections quickly. Andrew can live with it.
- ID-302 BUG?: **a device moved in the web interface is unguarded while it moves.** GRD-5, 2026-09-29: the web interface stops the tunnels to move a device, and part way through (17:49:33 to 17:51:01) the router had DESKTOP pinned to nothing. `guard.sh` follows `vpnc_dev_policy_list` on every watchdog run, so it rightly took DESKTOP's guard away, and wgc5's watchdog put it back once the move was done. Whether traffic leaked isn't known: nothing was pinging from DESKTOP. README says to move devices in DEVICES (ID-294, Andrew's decision). After the release: measure it, then consider keeping a device's old block until its new pin appears.
- ID-129 BUG: **an alert email failed with `server misbehaving`, cause unknown.** Seen once, 2026-09-06: the mailer's own lookup of the SMTP host failed, which is Go's resolver reporting that the DNS server answered with an error. ID-001 ruled out the router's lookups going through a tunnel. Probably prevented by ID-077, which resolves the SMTP host over encrypted DNS and hands the mailer an address. If it recurs on build 455 or later, read the watchdog log's private lookup line first.
- ID-219 BUG?: **the router lost its settings across a reboot during the guard run sheet, cause unknown.** 2026-09-24, build 461, stock. At 10:53:09 an APPLY committed `vpnc_dev_policy_list`; at 10:53:30 the app rebooted the router, and that boot logged the first `jffs2: check_node_data: wrong data CRC` error. Afterwards the WireGuard server's and both clients' settings were gone (`wgc1_ppub` empty at 10:56:22), the watchdogs read empty regions, DESKTOP had no internet (the guard, correctly), and the web interface offered first-time setup. Andrew restored his saved configuration. Nothing the app ran writes those settings, and earlier reboots with no recent commit were clean, so the suspect is a flash fault coinciding with a commit and a reboot: one case, not proven. From 10:26 `restart_vpnc_dev_policy` had also stopped writing its priority-100 rules, probably an early symptom. Since the restore: /jffs 6% used, no CRC errors. Parked by Andrew; not reproduced on purpose. If it recurs, before restarting anything: the ID-195 capture, plus `dmesg | grep -i jffs2`, `nvram get wgc1_desc`, and copies of `/tmp/syslog.log` and `/jffs/syslog.log`.
- ID-195 BUG?: **an outage on 2026-09-23 is unexplained: a phone and the media centre had no internet with both tunnels up.** Both watchdogs were content, and the web interface showed both tunnels up. `restart_net_and_phy` (22:13:48) didn't fix it; a reboot (22:17:24) did. The candidates: the router's resolver (dnsmasq was restarted, stubby wasn't; the reboot restarted both), and, for the media centre alone, the 5 GHz radio flapping on DFS channel 52. Pinning 5 GHz to a non-DFS channel costs nothing and rules the second out. Next time, before restarting anything:
  - from a LAN device: `ping 1.1.1.1`, `nslookup google.com`, `nslookup google.com 9.9.9.9`. If the address works, the first lookup fails and the second works, it's the router's resolver, not the tunnels.
  - on the router: `ip rule show; ip route show table main; ip route show table 5; ip route show table 9; nvram get vpnc_default_wan; nvram get vpnc_unit; nvram get vpnc_dev_policy_list; cat /tmp/resolv.dnsmasq; ps | grep -E 'stubby|dnsmasq'; nslookup google.com 127.0.0.1; wg show interfaces`

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
- ID-041 CHG: **fix the 35 issues in the [Sonar Cloud scan](https://sonarcloud.io/project/issues?id=ExponentiallyDigital_cfg-pia-wg&s=IMPACT_RANK&issueStatuses=OPEN%2CCONFIRMED), cognitive complexity first.** A plan, approved by Andrew, before any code. On hold with the rest of this section: the changes are likely extensive, with a high blast radius (triaged 2026-09-15).
- ID-059 CHG: **remove `RouterWatchdog.waitForWatchdogReady`, which nothing calls.** Its only caller is its own test in `test/router_watchdog_service_test.dart`, which goes with it. Tidying, not a fix: wait until the current watchdog has soaked in a release. Found 2026-09-15.

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
