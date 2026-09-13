# BACKLOG.md

- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. FTR - future implementation](#112-ftr---future-implementation)
    - [1.1.3. Unconfirmed BUGs](#113-unconfirmed-bugs)
  - [1.2. v0.9.xx freemium](#12-v09xx-freemium)
  - [1.3. Codebase cleanup](#13-codebase-cleanup)
  - [1.4. v1.0.0 iOS version](#14-v100-ios-version)

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- DOC: **give each ARCHITECTURE section its own overview.** The document has one at the top, added in the build 430 rewrite, but the sections do not: most open with mechanism before saying what the thing is for or why a reader should care. `The router's service queue` was given one on 2026-09-12 and reads far better for it. Device assignment (section 6) and the SSH commands (section 4) are the two that need it most. Roughly fifteen minutes a section.
- OPS: **website returns 403 to the assistant's page fetcher.** Not robots.txt - that is advisory and cannot return a status code - so it is a server, CDN or WAF rule, probably on user-agent. Two fetches of the privacy policy were refused, including one after the robots.txt update of 2026-09-12 that allows `ClaudeBot`, `anthropic-ai` and `Claude-Web`. For user-requested fetches the agent is `Claude-User`, which is not in that list. Blocks reading the published privacy policy to check it against the repo copy, and blocks learning house voice from the blog.
- DOC: Update `README.md` screenshots.
- DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app).
- DOC: Update Play Store description.
- DOC: Update Play Store screenshots.
- REL: Update version to 0.9 branch when first releasing stock support (and see the backlog item on performance profiling when sent to GPS alpha track).

#### 1.1.2. FTR - future implementation

- FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- FTR: **show where a pinned device is ACTUALLY exiting when its slot is down.** Measured on hardware 2026-09-13: disabling a slot leaves the `vpnc_dev_policy_list` record intact and the router removes the `ip rule`, so the device falls through to the default connection and keeps working. Correct behaviour, but the assignment screen still names the pinned slot, which is true of the configuration and false of the traffic. Proposal: when the pinned slot is not active, mute the slot label and append where it really goes, resolved rather than assumed - the default connection if that is up, otherwise the plain internet, two hops at most. The picker value must NOT change: the pin is intact and re-enabling the slot restores it. The default-connection panel needs the same treatment when the default itself is down.
- FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ADD: deploy a script like `.\scripts\showall.sh` to `jffs/cfg-pia-wg` that creates diagnostic information, decide what to do about secrets in the file
- FIX: **the watchdog passes a tunnel that handshakes but cannot resolve names.** Measured on hardware 2026-09-13/14: devices pinned to `wgc4` got no answer from 9.9.9.9 on UDP 53 or TCP 853 (conntrack `[UNREPLIED]`), while ping to 9.9.9.9 and HTTPS and DNS over HTTPS to 1.1.1.1 worked through the same tunnel. The server was `us_alabama`. It seemed to recur after `wgc4` was recreated on `aus_perth`, but the WireGuard peer key and tunnel address were unchanged - the recreate never reached the running tunnel (see the CREATE entry below) - so both runs were Alabama. The same Quad9 redirect worked on `wgc3` (`france`), and every slot's firewall rules, allowed IPs, DNS and MTU were identical, so nothing points at the slot. Confirmed 2026-09-14: after `wgc4` was deleted and recreated on `aus_perth` (new peer key, exit shown as Perth), a device pinned to it resolved names through the same Quad9 redirect. Devices pinned to it had no name resolution, and the watchdog logged a recent handshake every five minutes and never moved it to another server. Needs a probe that exercises the slot's own DNS servers through the tunnel. The design is open: on stock the router's own traffic is not routed into `wgcN` (`to <dns> iif lo lookup <table>` matches the lowest table first), which is why `ping -I` was abandoned.
- FIX: **CREATE over an enabled slot leaves the OLD tunnel running under the NEW label.** Measured on hardware 2026-09-14: overwriting an active `wgc4` (`us_alabama`) with `aus_perth` wrote the new NVRAM and description, but nothing restarted the interface - `wg show` still named the Alabama peer key and the tunnel kept its old address. The app, the WebUI and the assignment screen all said `aus_perth` while traffic left through Alabama, and the dialog told the user to ENABLE a slot that was already up. Agreed fix: when CREATE overwrites an enabled slot, stop the tunnel first (`stop_vpnc`, as DISABLE does), write the new configuration, and leave the slot disabled so "Remember to ENABLE it" is true. The overwrite confirmation should say the tunnel will be stopped and that devices assigned to the slot use the default connection until it is enabled. A watchdog on the slot stands down by itself on `wgcN_enable=0`. Merlin needs the same check.
- FIX: **deploying a watchdog to a slot that is already up still runs `restart_vpnc`.** `deployWatchdog` always calls `enableVpnSlot`, which rebuilds VPN routing for every tunnel. Skip the enable when the interface is already up.
- FTR: **a pinned device's DNS has no fallback.** Stock redirects a pinned device's port 53 queries, UDP only, to the slot's FIRST DNS server (`VPN_FUSION` DNAT); the second is never used, so one unreachable resolver means no DNS at all for that device. Consider documenting it by the DNS field, or defaulting to resolvers the tunnel can always reach.
- FTR: **check the target tunnel before assigning a device to it.** At APPLY on the device assignment screen, and when changing the default connection, check each slot a change moves devices onto: is its interface in `ip -o link show up`, and is its latest handshake under about 3 minutes old (WireGuard re-handshakes every 2 minutes on a live tunnel; watchdog logs show ages up to 111s). Warn rather than block, with a confirm that names the problem: a slot that is not up means the device uses the default connection until the slot is enabled, which is legitimate; a slot that is up with a stale handshake means the device may have no internet. The default connection needs it most, since it moves every unassigned device. A handshake is not proof of a working path - the `us_alabama` server handshook normally while not reaching Quad9 - so this catches "not running" and "server not answering", not every failure. Pairs with the entry on showing where a pinned device is actually exiting.

#### 1.1.3. Unconfirmed BUGs

- AN-2026-09-13_001: all LAN devices lost internet while deploying a watchdog to wgc5 with five tunnels up; not reproduced. Candidate cause, routing measured 2026-09-14: the router's own queries to the tunnel DNS servers do not use the WAN - `from all to 9.9.9.9 iif lo lookup 5` sends them to table 5, and `ip route get 9.9.9.9` answers `dev wgc5`. Devices on the default connection resolve through the router, so every one of them depends on `wgc5`'s server reaching Quad9. A `wgc5` that is up but not passing traffic - mid-restart during a watchdog deploy, or a server like the `us_alabama` one - would leave them all without names while IP still works. A DISABLED `wgc5` fails over cleanly: measured 2026-09-14, disabling it moved `ip route get 9.9.9.9` to `dev wgc4` (table 6, the next rule), and re-enabling moved it back - so the danger is only a tunnel that is up but not passing traffic, whose route stays in place and keeps winning. Not yet reproduced.
- AN-2026-09-13_002: an AiMesh node appeared in device assignment as an unassignable device; no longer appears in a live list.
- AN-2026-09-13_003: copying several selected router log lines lost the line feeds; retested and they were kept.

---

### 1.2. v0.9.xx freemium

**Moved out on 2026-09-12.** The implementation, including the product decision and the price still
to be set, is in [`.claude/plans/plan_revenuecat-implementation.md`](.claude/plans/plan_revenuecat-implementation.md).
The release chores that used to sit here - documentation, publicity, launch and store optimisation -
are in the CHANGELOG pending list, because they happen at release time rather than during the build.

---

### 1.3. Codebase cleanup

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

### 1.4. v1.0.0 iOS version

**Parked** - US$99/year Apple Developer Program against an unknown iOS user base. Early thinking, and what actually blocks it: `.claude/plans/plan_ios-port.md`.

- The router half ports for free: `dartssh2` is pure Dart, and the watchdog script runs on the router, which does not care what phone deployed it.
- The platform hardening does not. `FLAG_SECURE` has **no iOS equivalent** - screenshots cannot be blocked, only the task-switcher snapshot can be covered. `README.md` and `SECURITY.md` state that guarantee unconditionally today and would need to state it per-platform.
- The silent clipboard clear is an Android method channel (`ClipboardManager.clearPrimaryClip()`); iOS needs `UIPasteboard.general.items = []` or the 60-second auto-clear regresses to the system copy popup that 403 removed.
- Non-code costs: a Mac or hosted runner for signing, a materially stricter App Store review, and a release pipeline (`release.yml`, SBOM, Gradle lockfiles) that is Android-shaped throughout.

**Worth doing whether or not iOS ever happens:**

- FIX: `openPlayStoreReview()` fails **silently** on iOS today - `openStoreListing()` needs an `appStoreId` there and throws without one, which the catch swallows into a `false`. Latent now, on a platform we do not ship to, but it is still a silent catch.
- DOC: phrase the hardening claims in `README.md` and `SECURITY.md` as "on Android" rather than absolutely, so an iOS build cannot quietly make them untrue.

---
