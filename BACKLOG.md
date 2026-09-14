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
- ID-019 DOC: Update `README.md` screenshots.
- ID-020 DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app).
- ID-021 DOC: Update Play Store description.
- ID-022 DOC: Update Play Store screenshots.
- ID-023 REL: Update version to 0.9 branch when first releasing stock support (and see the backlog item on performance profiling when sent to GPS alpha track).

#### 1.1.2. FTR - future implementation

- ID-024 FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- ID-025 FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ID-026 ADD: deploy a script like `.\scripts\showall.sh` to `jffs/cfg-pia-wg` that creates diagnostic information, decide what to do about secrets in the file.
- ID-027 DOC: create a digrammatic representation of how RC and GPS interact from an accounts, API, and message flow state, add to TESTING.md.
- ID-001 FTR: **the router's own DNS follows the first tunnel, not the default connection** - firmware behaviour, recorded. All LAN devices lost internet while deploying a watchdog to wgc5 with five tunnels up, an outage not seen again. Traced 2026-09-14 on stock: a LAN device that asks the router - unassigned, or pinned to Internet - is answered by dnsmasq, which sends everything but the ISP's own domain to stubby at `127.0.1.1`, which uses DNS-over-TLS to the servers in the WebUI's WAN DNS Setting. The firmware adds `from all to <slot DNS> iif lo lookup <table>` for each running tunnel's DNS servers, so when those match the WebUI's servers (Quad9 on the test router) stubby's port 853 leaves through the lowest-numbered table's tunnel, whatever the default connection is - traffic the router creates never follows the default, whose rules match `iif br0` and `br1` only. **Reproduced** after a reboot with wgc1 the only tunnel: blocking TCP 853 out of wgc1 timed out lookups for a device pinned to Internet and for one following the default, while ping kept working for both; a device assigned to wgc1 still resolved, because the firmware sends its DNS to the slot's first server on port 53 through its own tunnel. The router's own programs - the watchdog's `mailsend-go` and `curl`, `nslookup` - are not on this path: `/etc/resolv.conf` lists the WAN's DNS first, and a test email went out while blocked, so the 2026-09-06 undelivered alert (`server misbehaving`) is unexplained again. The app must not change the user's DNS settings (CONTEXT), so its only response is information - see CHANGELOG ID-005. Runsheet in `.claude/testing/`.

#### 1.1.3. Unconfirmed BUGs

- ID-002: an AiMesh node appeared in device assignment as an unassignable device; no longer appears in a live list.
- ID-003: copying several selected router log lines lost the line feeds; retested and they were kept.

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

### 1.3. v1.0.0 iOS version

**Parked** - US$99/year Apple Developer Program against an unknown iOS user base. Early thinking, and what actually blocks it: `.claude/plans/plan_ios-port.md`.

- The router half ports for free: `dartssh2` is pure Dart, and the watchdog script runs on the router, which does not care what phone deployed it.
- The platform hardening does not. `FLAG_SECURE` has **no iOS equivalent** - screenshots cannot be blocked, only the task-switcher snapshot can be covered. `README.md` and `SECURITY.md` state that guarantee unconditionally today and would need to state it per-platform.
- The silent clipboard clear is an Android method channel (`ClipboardManager.clearPrimaryClip()`); iOS needs `UIPasteboard.general.items = []` or the 60-second auto-clear regresses to the system copy popup that 403 removed.
- Non-code costs: a Mac or hosted runner for signing, a materially stricter App Store review, and a release pipeline (`release.yml`, SBOM, Gradle lockfiles) that is Android-shaped throughout.

**Worth doing whether or not iOS ever happens:**

- ID-028 FIX: `openPlayStoreReview()` fails **silently** on iOS today - `openStoreListing()` needs an `appStoreId` there and throws without one, which the catch swallows into a `false`. Latent now, on a platform we do not ship to, but it is still a silent catch.
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

- CHG: ABOUT screen - add spacing after the "watchdog history" line, the COPY BUILD INFO and CREATE GITHUB ISSUE buttons are too close to the text.
- CHG: ABOUT screen - centre the two buttons COPY BUILD INFO and CREATE GITHUB ISSUE
- FIX: SETTINGS screen - selecting any option on this page that requires a login to the router does not reuse router credentials after they have been entered in any login popup in this screen. I went to MANAGE, supplied credentials then went back to ABOUT and now MAX ACTIVE VPNS does not prompt me for router credentials. Also, check that every option in this menu writes a message to the application and router log when it is applied or used successfully or unsuccessfully. Currently no app log events are written after you charge any option in this screen after having entered credentials, after supplying valid credentials they are not used and no login occurs unless the login state has already been cached from outside this screen. I tested using set max VPN, set the value, left the screen, re-entering the option I was asked to login again. Settings screen isn't storing caching credentials but is consuming them if they exist.
- FIX: SETTINGS screen - if you tap on restore purchase, no message is written to the app log.
- TST: SETTINGS screen - does uninstall leave anything behind?
- CHG: ABOUT screen - add a confirmation popup when FORGET ROUTER IP is selected.
- FIX: ABOUT screen - router firmware version is shown twice in the GitHub issue template created after tapping on CREATE GITHUB ISSUE, do not include the second occurrence.
- ADD: SETTINGS screen - when REBOOT ROUTER has been selected and the popup accepted, create a popup that displays a counter showing a progress count from 0% to 100%, the counter will use seconds as the unit, so 1%=1 second through to 100 seconds. In that popup do not display any buttons but allow the popup to be navigated away from with the back button.
- TST: restore purchase button appears on the SETTINGS menu in a GPS build.
- REL: fix required for /.github/workflows/release.yml. When the actions workflow ran, having added a new tag, all changelog entries between https://github.com/ExponentiallyDigital/cfg-pia-wg/releases/tag/v0.8.74 and https://github.com/ExponentiallyDigital/cfg-pia-wg/releases/tag/v0.8.77 did not appear in the release comments.
- REL: add automation for updating the Google Play Store (GPS) app description. Create a new manually run workflow. The new description must be taken from ./play-store/description.md. Add a gate that fails and stops upload to GPS if the character count is 4000 or more characters, make the failure message specific and state why the workflow failed to run with how many characters are in the file and by how many it exceeds the maximum value. GitHub actions  script./.GitHub/workflows/promote.yml uses  `kevin-david/promote-play-release`, but other options may apply.
- CHG: ON HOLD - analyse and fix 35 issues reported by [Sonar Cloud scan](https://sonarcloud.io/project/issues?id=ExponentiallyDigital_cfg-pia-wg&s=IMPACT_RANK&issueStatuses=OPEN%2CCONFIRMED), focus specifically on the cognitive difficulty issues first, create a plan for what to do then have that plan specifically approved by Andrew before proceeding to implement the proposed code changes.
- FIX: watchdog deployment - when a watchdog is deployed on an empty slot the router log contains "Sep 15 02:35:17 cfg-pia-wg: wgc1: No handshake and both pings failed (8.8.8.8, 1.1.1.1)" despite successfully deploying the watchdog. 
- ADD: WATCHDOG deployment, if a user has already deployed a watchdog with email alerts enabled, prefill the field data for "from", "to", "SMTP server:port" , "SMTP username" , and "SMTP password". If the user has not created a watchdog in this session and a watchdog exists, prefill the fields with values from NVRAM. If multiple watchdogs already exist and there are no cached credentials , read the NVRAM values ftom the lowest numbered slot.
- ADD: watchdog email alert - test email subject line does not contain the region name. the deployed email does. Add the region name to the subject line, like we have for the delay and failure emails.

---

Claude: ignore from this line to the end of this file. 
