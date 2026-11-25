# BACKLOG.md

Always read and follow [CHANGE-PROCESS.md](CHANGE-PROCESS.md) before changing this file.

- [1. Current Release - planned work](#1-current-release---planned-work)
- [2. Next Release - planned work](#2-next-release---planned-work)
- [3. Backlog](#3-backlog)
  - [3.1. Unconfirmed BUGs](#31-unconfirmed-bugs)
  - [3.2. FTR - future implementation](#32-ftr---future-implementation)
- [4. New work items](#4-new-work-items)

---

## 1. Current Release - planned work

- ID-726 TST: failback to a working first WAN with the phone as the second: pinned devices still leak nothing and each tunnel handshakes again without a manual restart. Raised 2026-11-25, as the remainder of ID-723.
  - Now: it waits for the NBN service to return, since the first WAN has no connection to fail back to; GRD-7 and `check-claims.sh quick` are the checks.
  - DoD: GRD-7 run from a pinned device across the failback shows no answer from a WAN address, and `check-claims.sh quick` has no FAIL afterwards.
- ID-596 ADD: on Merlin, a BY RULE view in DEVICES that lists every VPN Director rule in the order VPN Director acts on them and can switch, rename or delete any WireGuard or WAN rule through DEVICES' apply path, with OpenVPN rules listed read-only. Raised 2026-11-15.
  - Now: the UI is an agreed concept, and its implementation is agreed first, from mock-ups.
  - DoD: on Merlin, a rule switched off or deleted in the app is gone from `ip rule` with the guard's `prohibit` for it, `check-claims.sh` fails with it put back by hand, and README and the store screenshots are checked.
  - Plan: [plan_vpn-director-rules.md](.claude/plans/plan_vpn-director-rules.md)
- ID-597 ADD: on Merlin, add and edit WireGuard and WAN rules in DEVICES' BY RULE view, ranges and remote addresses included; never OpenVPN. After ID-596.
  - Now: first, the guard's hold for a range sent to a tunnel is measured on the router, and Andrew decides whether a pinned device's remote address to the internet is refused or warned.
  - DoD: a range sent to a tunnel fails closed with the tunnel stopped, through a reboot, and `check-claims.sh` fails with the guard's rule for it deleted by hand.
  - Plan: [plan_vpn-director-rules.md](.claude/plans/plan_vpn-director-rules.md)
- ID-594 ADD: choose what carries the router's own DNS, on stock and Merlin: the firmware's choice, a named slot, or the internet connection. Raised 2026-11-15.
  - Now: moved to Next Release on 2026-11-22 as a decision for Andrew, whether to build it, with the router's lookups refused when the chosen slot is down (ID-636's hold).
  - DoD: on each firmware, through a reboot, `ip route get` shows the chosen route for each of the router's DNS servers, and `check-claims.sh` fails with the rule deleted by hand.
  - Plan: [plan_router-dns-slot.md](.claude/plans/plan_router-dns-slot.md)
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
- ID-689 TST: see the watcher of ID-630 re-run a job that never got a macOS runner, once, and leave a real failure alone. Raised 2026-11-23, as the remainder of ID-685.
  - Now: it can't be provoked, so this waits for GitHub to leave a job without a runner, on `main`, where the watcher runs.
  - DoD: a run's job cancelled with "was not acquired by Runner" is re-run once by `rerun_unacquired.yml` and passes or fails on its own merits, seen in the Actions list.
  - Plan: [plan_rearchitect-cicd.md](.claude/plans/plan_rearchitect-cicd.md)

---

## 2. Next Release - planned work

- ID-305 CHG: stock's mail sender moves to `mailsend-go` v1.0.13, so a failed send's diagnostics include the server's certificate (`-printCerts`). Diagnostics only: v1.0.12 already verifies the certificate when sending (`InsecureSkipVerify: !VerifyCert`), and upstream says there's "no need to update unless you need certificate details" (issue #76).
  - Work: new pins and SHA-256s for both architectures in `binary_installer.dart`, from the published checksums and recomputed on hardware; the archive member names; offering the update to routers on v1.0.12.
  - DoD: on stock, TEST EMAIL sends with v1.0.13, and a deliberately failed send prints the certificate in the app log.
- ID-714 BLD: Claude reads SonarCloud's new issues straight after every commit, so what it would flag is fixed before the release commit and not first found on the pull request. Raised 2026-11-25 by Andrew, after build 592's seven issues (three over the complexity limit, four missing `const`) were found only on PR #91 and cost build 593.
  - Now: for Andrew to choose. SonarCloud reads only pushed code, so either a local `sonar-scanner` run (which needs the project's token on this machine, where it is only in GitHub secrets), or a hook that after each push of `dev` reads that branch's new issues from SonarCloud's API, which needs no token for reading, as the pull request's count already showed.
  - DoD: after each commit the new issues are in the reply or fixed, with no commit left unread, and a test of the hook, or of the step in CLAUDE.md, fails when it is skipped.
- ID-719 TST: finish branch coverage (ID-718): see whether SonarCloud accepts branch data, and set a branch target for the safety-critical files only. Raised 2026-11-25, as the remainder of ID-718.
  - Now: for the first, the CI steps of ID-718 must run once on a pull request (the report, its artifact and the summary), and then a throwaway run gives SonarCloud the unstripped file, to see whether its parser takes records on lines with no line record. For the second, branch coverage of `fail_closed_guard.dart`, `merlin_guard.dart`, `router_watchdog.dart` and `device_assignment.dart` is read from the report, and a target is chosen for the ones where an untaken branch is a real gap.
  - DoD: the CI report is seen to work, SonarCloud's answer to branch data is recorded here and, if it takes it, the job passes it the full file; and the guard and watchdog files have a branch figure each in README or BUILDING.md, with a test or a CI check that fails below it.

Work items for the **next** release (requires Merlin to be swapped out for STOCK firmware):

- ID-711 TST: see NETWORK's Router box (ID-706) show the right WAN address, DDNS name, name, domain and LAN address on a stock router. Raised 2026-11-25, as the remainder of ID-706, built and checked on Merlin only.
  - DoD: on stock, TESTING.md NET-7 passes, with `nvram get` of `wan0_ipaddr`, `ddns_enable_x`, `ddns_hostname_x`, `lan_hostname`, `lan_domain` and `lan_ipaddr` matching the box, or each key that differs is fixed and re-run.
- ID-712 TST: see NETWORK's tunnel status (ID-600) and TEST SPEED (ID-604) work on a stock router. Raised 2026-11-25, as the remainder of ID-696, which passed on Merlin only.
  - Now: unproven on stock are the watchdog's restart lines (`Restarting wgcN through VPN Fusion` and `No vpnc_clientlist row`), the rule at priority 1004 with `ip route get` aiming the test through the tunnel's table, 104.16.0.1 (below 128.0.0.0) answering through it, the tunnel's byte counters under `/sys/class/net`, and the router's shell and curl taking the loop and `--data-binary @-`.
  - DoD: TESTING.md NET-5, NET-6 and NET-7 pass on stock, `ip rule show` has nothing at priority 1004 afterwards, or each failure is fixed and re-run.
  - Plan: [plan_network-tunnel-status.md](.claude/plans/plan_network-tunnel-status.md)
- ID-578 SEC: rerun GRD-7 on stock with `check-reboot.sh` as fixed on 2026-11-14, the next time the router is on stock. Until then counted any answer but the WAN address read before the reboot as the tunnel, and the router's WAN address can change at a reboot (it did on Merlin that day), so a leak through the new address would have passed. README 5.4.1's "no leak across three restarts in a row" rests on those passes; the earlier runs that found leaks (4 of 6) are unaffected.
  - DoD: three passes on stock with the fixed check, or README 5.4.1 corrected to what it finds.
- ID-588 TST: WGT-2 on stock, the next time the router is on stock (with ID-578): an answering tunnel's widget row names the devices pinned to it (ID-587). The line is built the same way as on Merlin, where MRL-15 passed.
  - DoD: WGT-2 passed on stock, its row naming a pinned device.
- ID-613 TST: the hand tests for build 581's fixes that weren't run, on stock and on the watchdog form. Stock: ID-609 (a slot DNS change in WATCHDOG restarts the slot and its devices use the new servers, WD-DNS), ID-610 (ROUTER DNS ROUTING's sentence for slot DNS servers the router's own DNS doesn't use), ID-612 (the watchdog form refuses Quad9 where stock's curl 7.84 may also lack HTTP/2, WD-DOH) and ID-606's DEVICES label for a profile deleted in the web interface. Merlin: WD-DNS through the app's screens, which build 581 covers with automated tests and the router-side measurement only. Raised 2026-11-16, the release run having only a Merlin router.
  - DoD: WD-DNS and WD-DOH run by hand on stock and on Merlin, ID-610's sentence read on stock, each result written in TESTING, and any failure a bug under its own ID.
- ID-639 TST: the next time the router is on stock, re-measure the stock statements in ROUTER-DNS.md sections 2 to 6 and README 5.2.2 (with ID-578, ID-588, ID-613 and ID-655), which date from September 2026 and are the only ones not checked since Merlin's DNS was measured on 2026-11-20. Claude runs it over SSH from a run sheet written beforehand with each step's expected result first, when Andrew has swapped the router to stock and given permission for that session (his instruction, 2026-11-22), in one session: (1) devices that aren't pinned, with a tunnel as the default, with the router's DNS Server setting, the DoT list and the slots' DNS all different; (2) the router's own lookups when the slot holding a shared address stops, which September's record says move to the next-highest slot; (3) ID-594's rule through a reboot and with the slot stopped; (4) the highest-numbered slot carrying a shared address, and DNS-over-TLS switched off; (5) the ROUTER DNS ROUTING and ROUTER RESOLVER STATUS screens read on stock with each default.
  - DoD: each statement confirmed or corrected in those files, with the date and the firmware version, and ARCHITECTURE.md 2 row 8 checked.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
- ID-655 TST: WD-29 on stock, continuing ID-629: a tunnel that mends itself after a FAILED alert sends one RECOVERED email (ID-628), and the SUCCESS-then-healthy case of ID-650 sends nothing. Run by Claude in the stock session with ID-639, with this release's watchdog deployed.
  - DoD: WD-29 run on stock, its result written in TESTING, and any failure a bug under its own ID.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)

---

## 3. Backlog

### 3.1. Unconfirmed BUGs

`<none>`

### 3.2. FTR - future implementation

- ID-695 FTR: `scripts/app_store_connect.py` gains a read-only `age-rating` command that prints every age rating question Apple's API returns with its current answer, and marks each one the script doesn't answer. Raised 2026-11-24, after two new questions (Shared Location, and Dating and Relationships) had to be found from a listing run's warning.
  - DoD: the command lists every attribute of the declaration, flags those outside `AGE_NONE`, `AGE_NO` and `AGE_NOT_ASKED`, sends nothing, and has a test on a recorded declaration.
- ID-631 BLD: build and upload the iOS app with the iOS 27 SDK before April 2027, when Apple stops accepting uploads built with an older one (App Store Connect warned on 2026-11-19 about build 586, built with the iOS 26.5 SDK, ITMS-90725). Both iOS jobs run on `macos-latest`, which carries Xcode 26.x only; GitHub's `xcode-27` runner label carries Xcode 27 and the iOS 27 SDK. Run the pull request's simulator build on `xcode-27` first, to see that the pinned Flutter builds with it and how long the job queues, then move the signed iOS release job.
  - DoD: a TestFlight upload built with the iOS 27 SDK, and no ITMS-90725 email for it.
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
- ID-127 FTR: contingency, not scheduled: ship our own `curl` if a firmware update breaks stock's two curl workarounds. Stock's `/usr/sbin/curl` refuses a caller with `crond` in its ancestry and any URL whose host is an IP address (ARCHITECTURE 2, rows 6 and 7); the script detaches from cron and uses hostnames with `--resolve`. Our own curl would make its TLS CVEs this project's job, outside the dependency scanning. Raised 2026-09-19.
  - Trigger: a firmware update breaks row 6 or 7. Until then there is nothing to do.
- ID-621 FTR: not finalised, to be put to users before it is built: a DNS mode in SETTINGS, so that bare local hostnames (`nas`, `printer`) resolve on every device while external names go through a slot. A device pinned to a slot with its own DNS has every lookup redirected to that server, so the router's names stop resolving on it, and nothing in the app says so (measured on Merlin 388.13, 2026-11-17). The proposal is three modes (per slot as today, one path for all, one path with device exceptions such as a family filter) and a ranked list of further options, with questions for r/WireGuard and the Merlin forum.
  - DoD: the unmeasured parts measured (what the router's own lookups do while their slot is down; stock firmware), users asked, the modes decided and split into items.
  - Plan: [plan_dns-modes.md](.claude/plans/plan_dns-modes.md)
- ID-375 BLD: retire `tool/launcher_icons.dart` (ID-374) once a flutter_launcher_icons release changes only `ASSETCATALOG_COMPILER_APPICON_NAME`. The fix was proposed on [PR #549](https://github.com/fluttercommunity/flutter_launcher_icons/pull/549#issuecomment-6674977473), posted 2026-11-06.
  - DoD: such a release is out, and the wrapper and its notes in the build scripts, workflows, BUILDING, CONTRIBUTING and `pubspec.yaml` are gone.
- ID-462 REL: sell the iOS app in France, once the French encryption declaration is accepted. Split from ID-430 on 2026-10-20, Andrew's decision: France is left out of the first App Store release so the declaration can't delay it. Selling in France needs the declaration uploaded in App Store Connect (`app-store/export_compliance.md`), then `ITSAppUsesNonExemptEncryption` YES and Apple's `ITSEncryptionExportComplianceCode` in `Info.plist`.
  - DoD: the declaration is accepted, the two keys are set with a test, and App Store Connect lists France.
- ID-257 TST: parked 2026-09-28 (Andrew's decision): a pilot of hand tests as Flutter integration tests on the emulator, against a real router. Start with SET, ROUTER LOG, ROUTER RESOLVER STATUS and ROUTER DNS ROUTING. It stopped because `integration_test` put `androidx.test`, `junit` and `guava` into the debug build, which broke the Gradle lockfile and brought new OSV findings (ID-058). Plan: `.claude/plans/plan_integration-test-pilot.md`.
  - To resume: lock the new libraries or exempt the debug build from locking.
  - DoD: the four groups run as integration tests against the router, and Andrew has judged whether to go further.

---

## 4. New work items

Andrew adds new items here as he finds them, unsequenced, unprioritised, and often without an `ID-NNN`. They are triaged by the steps in [CHANGE-PROCESS.md section 5](CHANGE-PROCESS.md#5-triage).
