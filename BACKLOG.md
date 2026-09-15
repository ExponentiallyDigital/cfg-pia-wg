# BACKLOG.md

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

Every prefixed work item gets an ID, with one exception: items in `## 2. New work items` stay ID-free while parked there. Claude Code assigns the ID only when moving an item into CHANGELOG's WIP, see that section for the workflow. This became mandatory alongside CHANGELOG's v0.8.78 build 448 release, and was backfilled across all existing prefixed items in this file at the same time. Unprefixed sub-bullets (e.g. under Codebase cleanup) stay ID-free too, since there's no prefix to attach an ID to.

IDs are shared with CHANGELOG.md: one number line across both files, so an ID always points to exactly one item no matter which file it lives in.

Format: `ID-NNN XXX:`, where `XXX` is the item's prefix code, placed at the start of the bullet before the prefix.

To assign a new ID, search **both** BACKLOG.md and CHANGELOG.md for the highest existing `ID-NNN` and use the next number.

When adding several items in one sitting, look up the highest existing ID once, then increment by one for each new item in that batch.

Once an ID is given, it does not change even if the item moves section (e.g. from Unconfirmed BUGs to a scheduled section once confirmed).

---

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- ID-017 DOC: **give each ARCHITECTURE section its own overview.** The document has one at the top, added in the build 430 rewrite, but the sections do not: most open with mechanism before saying what the thing is for or why a reader should care. `The router's service queue` was given one on 2026-09-12 and reads far better for it. Device assignment (section 6) and the SSH commands (section 4) are the two that need it most. Roughly fifteen minutes a section.
- ID-018 OPS: **website returns 403 to the assistant's page fetcher.** Not robots.txt - that is advisory and cannot return a status code - so it is a server, CDN or WAF rule, probably on user-agent. Two fetches of the privacy policy were refused, including one after the robots.txt update of 2026-09-12 that allows `ClaudeBot`, `anthropic-ai` and `Claude-Web`. For user-requested fetches the agent is `Claude-User`, which is not in that list. Blocks reading the published privacy policy to check it against the repo copy, and blocks learning house voice from the blog.
- ID-019 DOC: Update `README.md` screenshots. Assigned to Andrew, with its own commit.
- ID-020 DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app). Assigned to Andrew, with its own commit.
- ID-022 DOC: Update Play Store screenshots. Assigned to Andrew, with its own commit.
- ID-008 DOC: Update screenshots: create & upload phone and tablet screenshots x8 to GPS. Assigned to Andrew, with its own commit (moved from CHANGELOG WIP 2026-09-15).
- ID-061 DOC: **Claude Code: check every statement in the documentation against the code, and make the documentation match it.** The code is the reference: it works. Found 2026-09-15 while checking one table row in CONTEXT: the watchdog script path was wrong in two places, stock's script directory and cron cleanup were described the Merlin way, and ARCHITECTURE and CONTEXT said `restart_vpnc` clears `wgcN_enable`, which the working watchdog needs to stay `1` (ID-060). Each was written correctly once and went stale as the code moved, and a stale statement is one a later change can "fix" the code to match. Scope: the documents that describe the app as it is today - `.claude/CONTEXT.md`, `ARCHITECTURE.md`, `README.md`, `BUILDING.md`, `TESTING.md`, `CONTRIBUTING.md`, `SECURITY.md` and `play-store/README.md` - checking file and function names, paths, NVRAM keys, router commands and their order, per-firmware differences, button sets, test counts and measured figures. Out of scope: records of their time, which stay as written - CHANGELOG's implemented blocks, `.claude/plans/`, `.claude/bugs/` and `.claude/testing/`. Method: first a report of each mismatch, giving the document line, the code line and the proposed wording, for Andrew to review; then the agreed fixes, documentation only. Where the code rather than the document looks wrong, do not change either: list it for Andrew. A claim only the router can settle is listed as a hardware check, not guessed at.
- ID-068 DOC: **README section 5 disagrees with the app in three places.** SETTINGS (5.7) does not list MAX ACTIVE VPNS. The watchdog log button is called VIEW WATCHDOG LOG (5.3, and again in the email alerts section), where the app reads VIEW ROUTER WATCHDOG LOG. And About (5.8) says the watchdog script version is amber "when it is older than the copy in the app", where the app shows amber for any difference, newer included (`about_screen.dart`). Found 2026-09-15 during the TESTING.md review. Overlaps ID-020, Andrew's rewrite of section 5, and ID-061.

#### 1.1.2. FTR - future implementation

- ID-024 FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- ID-025 FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ID-026 ADD: deploy a script like `.\scripts\showall.sh` to `jffs/cfg-pia-wg` that creates diagnostic information, decide what to do about secrets in the file.
- ID-027 DOC: create a digrammatic representation of how RC and GPS interact from an accounts, API, and message flow state, add to TESTING.md.
- ID-001 FTR: **the router's own DNS follows the first tunnel, not the default connection** - firmware behaviour, recorded. All LAN devices lost internet while deploying a watchdog to wgc5 with five tunnels up, an outage not seen again. Traced 2026-09-14 on stock: a LAN device that asks the router - unassigned, or pinned to Internet - is answered by dnsmasq, which sends everything but the ISP's own domain to stubby at `127.0.1.1`, which uses DNS-over-TLS to the servers in the WebUI's WAN DNS Setting. The firmware adds `from all to <slot DNS> iif lo lookup <table>` for each running tunnel's DNS servers, so when those match the WebUI's servers (Quad9 on the test router) stubby's port 853 leaves through the lowest-numbered table's tunnel, whatever the default connection is - traffic the router creates never follows the default, whose rules match `iif br0` and `br1` only. **Reproduced** after a reboot with wgc1 the only tunnel: blocking TCP 853 out of wgc1 timed out lookups for a device pinned to Internet and for one following the default, while ping kept working for both; a device assigned to wgc1 still resolved, because the firmware sends its DNS to the slot's first server on port 53 through its own tunnel. The router's own programs - the watchdog's `mailsend-go` and `curl`, `nslookup` - are not on this path: `/etc/resolv.conf` lists the WAN's DNS first, and a test email went out while blocked, so the 2026-09-06 undelivered alert (`server misbehaving`) is unexplained again. The app must not change the user's DNS settings (CONTEXT), so its only response is information - see CHANGELOG ID-005. Runsheet in `.claude/testing/`.
- ID-011 CFG: set the router's default DNS to CloudFlare, so they are different to the Quad9 DNS addresses set for VPN tunnels,therefore avoiding the issue of router DNS traffic being forced into the first VPN tunnel. Try this, test and the review outcome. If this works, add a prominent note in README under prerequisites. If this is successful then implemeing this may remove the need for work items in section "1.1. Pending to do", or in BACKLOG. if this is unsuccessful then we will review next steps and how that affects items for release. Assigned to Andrew: router test on 2026-09-16, with its own commit (moved from CHANGELOG WIP 2026-09-15).

#### 1.1.3. Unconfirmed BUGs

- ID-002: an AiMesh node appeared in device assignment as an unassignable device; no longer appears in a live list.
- ID-003: copying several selected router log lines lost the line feeds; retested and they were kept.
- ID-063 BUG: **a watchdog rebuild is reported as a success when the interface comes up, whether or not the server ever answers.** After restarting the slot the script's only test is `ip -o link show up` (the `did not come up after reconfiguration` check in `_kWatchdogScriptTemplate`, `lib/router_watchdog.dart`). It then logs `Reconfig SUCCESS`, counts `cfg_pia_wg_reconfig_ok` and emails SUCCESS. A rebuild whose new server never completes a handshake reads as recovered until the next check fails again. Found by reading the code on 2026-09-15 during the TESTING.md review; not yet seen on hardware. Until it is fixed, a manual recovery test has to confirm the next check logs `Handshake Ns ago`.
- ID-064 BUG: **a WAN outage climbs the watchdog's backoff ladder without making a single attempt.** The script writes the backoff counter (`CNT=$((CNT + 1))`) before the WAN check, which then exits with `no Internet on WAN interface, exiting.` and no alert. Every check during a long WAN outage logs a red `Connectivity lost; reconfiguring (attempt #N)` and adds a rung, so when the WAN comes back, a tunnel that does not recover by itself can wait up to 90 minutes for its first real attempt. Found by reading the code on 2026-09-15; not yet seen on hardware.
- ID-065 BUG: **removing the last scheduled watchdog takes the PIA credentials a paused watchdog still needs.** `stopWatchdog` keeps `cfg_pia_wg_user` and `cfg_pia_wg_password` only when `_otherWatchdogsRemain` finds another slot's cron entry, and a paused watchdog has none. ENABLE on the paused slot restores the schedule but not the credentials, so its next reconfigure aborts with `PIA username is not set`. Found by reading the code on 2026-09-15; not yet seen on hardware.
- ID-066 BUG: **MANAGE DELETE on a slot whose watchdog is paused leaves that watchdog on the router, SMTP password included.** `_deleteManage` calls `stopWatchdog` only when the watchdog is active. `deleteSlot` then unsets the slot's own keys and `wgcN_wd_primary_ip` / `wgcN_wd_secondary_ip`, and nothing else: `wgcN_wd_check_interval`, the email and SMTP keys (`wgcN_wd_smtp_pass` among them) and `/jffs/cfg-pia-wg/watchdog_wgcN.sh` all stay. WATCHDOG DELETE always calls `stopWatchdog`, so only MANAGE is affected. Found by reading the code on 2026-09-15.
- ID-067 BUG: **the TEST EMAIL failure message sends the user to a screen that does not exist.** It reads "Open View app log for what the router reported." (`lib/watchdog_dialog.dart`); the screen is called APP LOG. Found by reading the code on 2026-09-15.
- ID-070 BUG: **prove whether `service stop_wgc N` and `start_wgc N` do anything on stock.** CONTEXT's stock table said the Merlin commands are inert on stock; it is now flagged as unproven. The app's own enable and disable use VPN Fusion's `restart_vpnc` / `stop_vpnc` on stock, but the watchdog script's reconfigure (the "Restart interface" block of `_kWatchdogScriptTemplate`, `lib/router_watchdog.dart`) still calls `stop_wgc`, `start_wgc` and `restart_vpnrouting0` on both firmwares. The one stock log of it, 2026-09-10, shows `notify_rc start_wgc 1`, then `Interface wgc1 is up` and `Reconfig SUCCESS`, but it was taken while the router's service queue was stuck, and ID-063 means "interface up" proves little on its own. If the commands are inert, a stock reconfigure writes new keys to NVRAM that never reach the running interface. How to settle it on stock: break a watched slot with the private-key swap in TESTING.md, let the watchdog reconfigure, then confirm `wg show wgcN` lists the NEW peer key from `nvram get wgcN_ppub` and the next check logs `Handshake Ns ago`. Opened 2026-09-15.

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

**Worth doing whether or not iOS ever happens:**

- ID-029 DOC: phrase the hardening claims in `README.md` and `SECURITY.md` as "on Android" rather than absolutely, so an iOS build cannot quietly make them untrue.

---

## 2. New work items

Andrew adds new items here as he finds them, unsequenced, unprioritised, and without an `ID-NNN` - items in this section stay ID-free until they're moved into CHANGELOG.

**Triage prompt for Claude Code:**

When asked to triage BACKLOG new work, work through it in this order:

1. **Check for duplicates.** For each item in this section, check whether it duplicates or overlaps with anything already in CHANGELOG's Pending, WIP, or Implemented history, or an existing BACKLOG item elsewhere in this file. Flag any overlap found rather than silently merging or dropping it.
2. **Sequence into batches.** Group the remaining items into logical implementation batches, following the same descending-importance ordering rule CHANGELOG already uses. Batches should reflect what makes sense to build and test together, not just priority order.
3. **Flag anything unclear.** Before moving anything, list any item where the requirement, scope, or expected behaviour needs clarification from Andrew. Wait for answers before proceeding on those specific items; the rest of the triage can continue.
4. **Move agreed items to WIP.** Once Andrew confirms the batching, assign each item its `ID-NNN` (search both CHANGELOG.md and BACKLOG.md for the highest existing ID and increment from there) and move it into CHANGELOG's `### 1.2. WIP`. Take into account what's already in WIP, resequencing existing items if the combined set changes the intended build order. Remove moved items from this section.
5. **Do not start implementing.** Stop after the move and wait for Andrew to separately say to begin implementation.

---

- TST: SETTINGS screen - does uninstall leave anything behind? Andrew tests this by hand; it stays in BACKLOG and is not scheduled for a build (triaged 2026-09-15).

---

Claude: ignore from this line to the end of this file. 
