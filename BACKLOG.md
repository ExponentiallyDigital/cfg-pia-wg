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

- ID-376 FTR: **an Android home-screen widget showing each tunnel's state, where it exits, and the guard, so the app is useful every day, not only when something is set up.** Andrew's idea, 2026-10-09: a watchdog, once set up, is rarely touched again, and a widget is seen daily. Mock-up: [cfg-pia-wg home screen widget](https://claude.ai/artifact/SU6ha7UoqcczLr1d2f6oLn) (private canvas).
  - **What it shows:** a 4×2 widget with a header (the app icon and an overall badge: teal "Protected", amber "1 tunnel down", grey "Not checked"), then one row per WireGuard tunnel: where it exits ("Melbourne, Australia"), the slot, up or down, the devices pinned to it, and the last handshake. A tunnel that is down says how long, whether its watchdog is rebuilding it, and which devices the guard is keeping offline, by the names DEVICES shows. The footer says when the router was last checked, beside a refresh button. A 2×1 size gives the badge and one line. The app's own colours (teal `#00D4AA`, amber `#EF9F27`, `#1A1D23`), and status told by shape and words as well as colour.
  - **The catch: it can't check the router on its own as the app stands.** `lib/router_prefs.dart` says the app must never store a router username or password, so a background refresh has nothing to log in with. Without one, the widget shows what the app last read, greyed when it's old ("Not reached for 3 h · tap to check"), and tapping opens the app to check.
  - **A way round it, to measure first:** a separate SSH key the app makes, kept in Android's Keystore, that the router accepts for one read-only status command only, through a `command="…"` restriction on its authorized-keys entry. Dropbear supports that in general; whether stock ASUS keeps the option in `sshd_authkeys` and enforces it isn't known, nor Merlin's. If it holds, the widget refreshes on Android's schedule (WorkManager, 15 minutes at the shortest) with no password stored, and a stolen phone can read the status and nothing else. That also needs a decision from Andrew: it's the first credential the app would keep.
  - **Then build:** the status read in one round trip (tunnels up, handshake ages, pins, guard rules, watchdog state, much of it what DEVICES and MANAGE already read), a widget layout per size, the refresh button, and the tap into the app; stock and Merlin both.
- ID-135 FTR: **DEVICES can clear offline devices from its list.** It stays clear of DHCP reservations. Pinning a device reserves its address in `dhcp_staticlist`, unpinning leaves the reservation, and the app never removes one (Andrew's decision, 2026-09-28, merged from ID-153). Removing one restarts the whole network, and can break a pin silently at a later lease renewal (ARCHITECTURE 6.3, 6.8.3). Anyone who wants to can do it in the web interface.
- ID-305 FTR: **move stock to `mailsend-go` v1.0.13 and add `-printCerts` to a failed send's diagnostics.** v1.0.13 (2026-09-29, upstream issue #76) prints the server's certificate while sending, not only with `-info`, and adds `-verbose`. `-verifyCert` already applied to sending in v1.0.12: its `sendMail` sets `InsecureSkipVerify: !VerifyCert`. So the alerts have been verifying the SMTP server's certificate all along, and this is diagnostics only. The upstream ChangeLog agrees there's "no need to update unless you need certificate details". The work: new pins and SHA-256s for both architectures in `binary_installer.dart` from the published checksums, recomputed on hardware; the archive member names; offering the update to routers that already have v1.0.12; and a run of TEST EMAIL and a deliberate failure on stock.
- ID-325 FTR: **check the PIA server list's signature, in the app and the watchdog (claims audit #19), with the key from PIA's own desktop client.** Deferred 2026-09-30 because no authoritative key was known; that blocker is gone (2026-10-09). Ready to build once the decision at the end is made.
  - **Today:** both fetch `https://serverlist.piaservers.net/vpninfo/servers/v6`, keep the first line (the JSON) and discard the signature block after it (`PiaService.fetchRegions` in `lib/pia_service.dart`; the watchdog's `head -1 "$TMPSRVRAW"` in `lib/router_watchdog.dart`). Only each server's `ip` and `cn` are used.
  - **Exposure, low:** addKey already runs TLS for the listed `cn` at the listed `ip` trusting only PIA's CA (ID-309), and the WireGuard key comes from that authenticated reply, so a forged list can't take the token or put a non-PIA server in the tunnel. It can: list real PIA servers from another country under the chosen region, the real exposure, since traffic then leaves from a country nobody chose; stop rebuilds with an empty or broken list, which fails closed under the guard; or list a relay that forwards to a real server, which sees only encrypted traffic. Forging it needs a mis-issued public certificate and a place on the network path, or a compromise of PIA's server-list hosting. The phone trusts system CAs only (`network_security_config.xml` adds none), the router its own store. DNS spoofing alone isn't enough.
  - **The key and method, from `pia-foss/desktop`** (GPL-3.0, like this app; last change 2026-05-26): `Environment::defaultRegionsListPublicKey` in `daemon/src/environment.cpp`, a 2048-bit RSA key in PEM, used for `serverlist.piaservers.net`; checked by `verifySignature` in `common/src/openssl.cpp`, SHA-256 with RSA through OpenSSL's `EVP_DigestVerify`. The client also loads an override key from a file (`loadRegionsListPublicKey`), so PIA has allowed for changing it.
  - **Build:** first read `common/src/jsonrefresher.cpp` for exactly which bytes are signed and how the signature is encoded. Then a unit test that checks a real downloaded list against the key, so a wrong reading fails a test rather than every rebuild, and one that a list with a byte changed is refused. Watchdog: the key in the script, `openssl dgst -sha256 -verify` on the router (the script already uses `openssl`), before the list is used. App: Dart has no RSA check built in, so a pure-Dart cryptography package or a small hand-written PKCS#1 v1.5 check, either way weighed as a new dependency. A check that breaks the protected path, a tampered list refused on the router, goes in `scripts/check-claims.sh`, per CHANGELOG's rule for protection claims.
  - **Decision for Andrew, before building: when a list fails the check, refuse it or warn and carry on.** Refusing stops a forged list, but a PIA key change would stop every rebuild until the app is updated, with pinned devices held offline by the guard meanwhile. Warning keeps rebuilds working and lets a forged list through, logged. Claude's lean, 2026-10-09: refuse, with an error saying plainly that the list failed PIA's signature check.
  - **Cheaper, independent of the key:** warn in both logs when the chosen server's `cn` doesn't fit the chosen region. It catches the wrong-country case on its own. A separate item if wanted.
- ID-229 FTR: pinch to zoom in the log windows: ROUTER LOG, APP LOG and the watchdog log.
- ID-127 FTR: **ship our own `curl` beside `jq` and `mailsend-go`, if ASUS tighten their wrapper further.** Stock's `/usr/sbin/curl` silently refuses a caller with `crond` in its ancestry, and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7). Both are worked around: the script detaches from cron, and every request uses a hostname with `--resolve`. `BinaryInstaller` could ship one, but a TLS stack of our own makes its CVEs this project's job, sits outside the dependency scanning, and asks users to trust far more than a JSON parser. Revisit only if a firmware update breaks row 6 or 7. Raised 2026-09-19.
- ID-024 FTR: localise into French, Spanish and Latin American Spanish, then decide on more. Translate the Play listing by hand: Google's automatic translations break its character limits.
- ID-257 FTR: **pilot: manual tests as Flutter integration tests.** The real app, on the emulator, taps through a flow, checks the screen, and checks the real router over its own SSH connection. Start with groups that need no PIA login (SET, ROUTER LOG, ROUTER RESOLVER STATUS, ROUTER DNS ROUTING), and judge it before going further. Needs a router the test can reset to a known state, and credentials kept out of the repo. Stays by hand: anything physical, emails arriving, the password manager, Play installs and purchases. **Parked 2026-09-28, unrun (Andrew's decision):** the `integration_test` package puts `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile; locking them moved RevenueCat in the debug build and brought `junit` and `guava` findings into the OSV scan (ID-058). The plan is `.claude/plans/plan_integration-test-pilot.md`. To resume: lock the new libraries or exempt the debug build from locking, then follow the plan.

#### 1.1.3. Unconfirmed BUGs

- ID-302 BUG?: **a device moved in the web interface is probably unguarded while it moves, and probably still is since build 491; not yet measured.** README 5.4.1 says so and points to DEVICES, which moves devices without stopping anything (ID-294, Andrew's decision).
  - **Seen, GRD-5, 2026-09-29:** the web interface won't move a device while its tunnels run, so you stop them, move it, apply and start them again. Part way through, 17:49:33 to 17:51:01, the router had DESKTOP pinned to nothing. The guard follows `vpnc_dev_policy_list`, so it rightly took DESKTOP's guard away, and put it back once the move was done. Whether traffic leaked isn't known: nothing was pinging from DESKTOP.
  - **Since build 491 (ID-364), reviewed 2026-10-09, unmeasured:** the cause is unchanged. The guard still follows the list, and should: a device deliberately unpinned must lose its block. The list passes through "unpinned" while the tunnels are stopped, and the guard can't tell that from a real unpin. What changed is timing: the guard used to see it at the next minute, and now about 10 seconds after the router's next event, so it probably drops the guard sooner and restores it sooner. If the web interface writes that in-between list without raising an event, the guard may never see it. Likely it does raise one, since a VPN Fusion apply is a `restart_vpnc_dev_policy` (the hook is called once for it, measured 2026-10-03), but that's inference. If the guard does run in the gap, both layers go: rules 90 and 91, and the device's Network Services Filter entries, through `lw_sync`. With its tunnels stopped, the device then follows the default connection, and straight out if that's the internet connection or a stopped tunnel.
  - **Next, measure it:** `scripts/guard-watch.sh` started from cron, a ping running on the device, and the device moved in the web interface. That shows whether the guard is dropped, for how long, and whether any reply comes back by the WAN.
  - **If it leaks:** the earlier idea, keeping a device's old block until its new pin appears, must not also block a device someone deliberately unpinned, or set to follow the default.

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
- ID-041 CHG: **fix the [Sonar Cloud scan](https://sonarcloud.io/project/issues?id=ExponentiallyDigital_cfg-pia-wg&s=IMPACT_RANK&issueStatuses=OPEN%2CCONFIRMED)'s findings, now 88, in six batches from safest to riskiest.** Triaged 2026-09-15 at 35 and put on hold with the rest of this section; analysed again 2026-10-09. A plan, approved by Andrew, before any code: this is that plan, waiting on his three decisions at the end.
  - **Where it stands, 2026-10-09:** 88 open, 50 of them newer than the triage, mostly the rewrite's new code. All code smells; none a bug or a vulnerability. CI's SonarCloud check passes, since the quality gate judges new code only. Cognitive complexity (S3776, limit 15): 38 functions, 571 points over. Nested ternaries (S3358): 29. Duplicated literals (S1192): 14. Too many parameters (S107): 2. Missing `const` (S7112, S3962): 5. Re-read the list with `https://sonarcloud.io/api/issues/search?componentKeys=ExponentiallyDigital_cfg-pia-wg&resolved=false&ps=500` before starting; it moves with every build.
  - **The worst functions:**
    - DEVICES: `_apply` 84, `_tunnelWarnings` 32 (`lib/widgets/device_assignment_screen.dart`), and `DeviceAssignmentService.apply` 31 with 13 parameters: APPLY, the most production-critical path.
    - Router DNS: `buildDnsRouting` 67 and `dnsReportText` 55 (`lib/router_dns.dart`), both pure functions, so their output can be pinned by tests before anything changes.
    - Watchdog and slots: `uninstallFromRouter` 53, `deployWatchdog` 45, `validate` 30 (`lib/router_watchdog.dart`); `createConfigToSlot` 37, `fetchSlots` 30, `enableSlot` 26 (`lib/router_slot_service.dart`). Full of stock-or-Merlin branches the firmware abstraction above would restructure anyway.
    - Screens and dialogs: `_slotList` 46, `_buttons` 36, `_enableManage` 28 (`lib/widgets/slot_modal.dart`); `_save` 36, `_dohPicker` 26 (`lib/watchdog_dialog.dart`); `_onConnect` 35 (`lib/widgets/router_slots_screen.dart`); `_secureStartup` and `_maxActiveVpns` 30 each (`lib/screens/settings_screen.dart`); `slotParamErrors` 28 (`lib/input_checks.dart`).
  - **The duplicated strings, judged:** `"Exception: "`, 24 times across four screens, is real duplication, the same error-tidying code copied around, and one shared helper fixes all four findings. The DNS file paths (`/etc/dnsmasq.conf`, `/tmp/resolv.dnsmasq`, `/etc/resolv.conf`) are shared facts that belong in constants, as does the DEVICES label `"Default connection"`. The router commands (`nvram commit` 24 times over three files, `nvram get vpnc_clientlist`, `nvram get vpnc_max_conn`, `date +%s`) arguably read better written out than as constants, and could instead be marked "won't fix" in SonarCloud with that reason.
  - **The plan, one build per step:**
    1. The quick, safe batch, about 20 issues: the five `const` fixes, the error-tidying helper, the DNS path and label constants, and the router commands as Andrew decides.
    2. Router DNS's two pure functions: tests that pin their output first, then split them, changing nothing they produce. Two of the four worst.
    3. The 29 nested ternaries, mechanical; the 8 in the watchdog script builder checked against the generated script text.
    4. DEVICES' APPLY: `_apply`, `_tunnelWarnings` and `apply`, its 13 parameters into one request object. Pieces moved into functions of their own and nothing else changed; the tests that pin APPLY's exact order, "THE DEFAULT CONNECTION SEQUENCE IS EXACT" among them, are the safety net.
    5. The screens and dialogs, one file per build.
    6. The watchdog and slot service functions: left to the firmware abstraction, and scored again after it.
  - **For every step:** behaviour pinned by a test before the change, functions only split, never reworked, the full suite, and the SonarCloud count read again afterwards.
  - **Decisions for Andrew:** start now, or keep holding (steps 1 to 3 carry little risk; 4 onward touch paths real users depend on); the router commands, constants or "won't fix" with a reason; and whether step 6 waits for the firmware abstraction.
- ID-355 TST: **faster fake router commands for the script tests.** Each stand-in (`nvram`, `ip`, `iptables`, `service`, `logger`, `curl`) is a separate script, so every `nvram get` in a test starts a new shell, and Git Bash on Windows starts processes slowly: the script tests are about 90% of the suite's time. Splitting them into 13 files in build 490 took the suite from about 5 minutes to 3m 45s; this is the rest of the gain. The router scripts themselves don't change.

### 1.3. v1.0.0 iOS version

**Parked** - US$99/year Apple Developer Program against an unknown iOS user base. Early thinking, and what actually blocks it: `.claude/plans/plan_ios-port.md`.

- The router half ports for free: `dartssh2` is pure Dart, and the watchdog script runs on the router, which does not care what phone deployed it.
- The platform hardening does not. `FLAG_SECURE` has **no iOS equivalent** - screenshots cannot be blocked, only the task-switcher snapshot can be covered. `README.md` and `SECURITY.md` state that guarantee unconditionally today and would need to state it per-platform.
- The silent clipboard clear is an Android method channel (`ClipboardManager.clearPrimaryClip()`); iOS needs `UIPasteboard.general.items = []` or the 60-second auto-clear regresses to the system copy popup that 403 removed.
- Non-code costs: a Mac or hosted runner for signing, a materially stricter App Store review, and a release pipeline (`release.yml`, SBOM, Gradle lockfiles) that is Android-shaped throughout.
- Extend RevenueCat to use Apple Store.
- ID-029 DOC: phrase the hardening claims in `README.md` and `SECURITY.md` as "on Android" rather than absolutely, so an iOS build cannot quietly make them untrue.
- ID-375 BLD: **post the agreed comment on flutter_launcher_icons pull request [#549](https://github.com/fluttercommunity/flutter_launcher_icons/pull/549), and retire `tool/launcher_icons.dart` once a release carries the fix.** Agreed 2026-10-09, Andrew's call, but not posted: the `gh` token here can't comment outside the organisation ("Resource not accessible by personal access token"). Post it from Andrew's own login, or after `gh auth refresh -s public_repo`. Once a flutter_launcher_icons release changes only `ASSETCATALOG_COMPILER_APPICON_NAME`, the wrapper (ID-374) can go, and `scripts/build.ps1`, `scripts/build.sh`, the quality and release workflows, BUILDING, CONTRIBUTING and the note in `pubspec.yaml` can run the tool directly again. The comment:

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
