# Plan: script updates, the watchdog emails and the guard (build 588)

The detail behind work items about the scripts the app puts on the router: how they are updated, what their emails say, and the fixes that went in with the DNS work. The DNS items are in [plan_dns.md](plan_dns.md).

## Work item detail, moved from CHANGELOG (2026-11-22)

Moved verbatim from CHANGELOG.md on 2026-11-22: CHANGE-PROCESS.md section 3 keeps a work item to its first line and one `Closed` line, and these had grown into paragraphs. Nothing was cut. Read the CHANGELOG line for what was done and this for how and why.

### ID-650

```text
- ID-650 BUG: the watchdog sent a RECOVERED email five minutes after a SUCCESS one for the same outage, claiming "1 earlier attempt to rebuild it failed" when the attempt succeeded. Seen 2026-11-20 on Merlin 388.13 with build 586, the release customers have: at 23:21 the check found no handshake, rebuilt the tunnel, and sent SUCCESS; at 23:26 the next check passed, with a handshake 42 seconds old, and sent RECOVERED, with a down time measured from the rebuild. Cause, read in `lib/router_watchdog.dart`: the healthy-pass block added for ID-628 reads the attempt count in `/tmp/watchdog_backoff_<slot>` as "failed rebuilds on record", but only a healthy pass resets that file, and a rebuild that succeeds leaves it at 1, so the next healthy pass reports a failure that never happened. The script is shared, so stock is affected the same way. The same outage is two emails instead of one, after every successful rebuild, on every router running the build 586 watchdog.
  - DoD: after a rebuild succeeds, the next healthy pass sends nothing; a tunnel that mends itself after a FAILED alert still sends exactly one RECOVERED (ID-628's case); a test for each, on the script's state handling; WD-29 (ID-629) extended with the SUCCESS-then-healthy case and run on Merlin (stock's run is ID-655). Routers get the fix only when the watchdog is deployed again, so the release note says so.
  - Partly done 2026-11-22: built in `lib/router_watchdog.dart`: the FAILED alerts sent since the outage began are the third line of `/tmp/watchdog_backoff_<slot>` (`fails_get` and `fails_set`), counted in `abort()` and cleared by a SUCCESS as well as by a healthy check, and the first two lines, the attempts for the backoff ladder, are unchanged; a two-line file from an older script reads as no failed alerts. Four new tests in `test/unit/watchdog_recovered_email_test.dart`, run for real against the fake router, all four seen to fail on build 587's script and pass now: SUCCESS then a healthy check sends one email, a FAILED attempt is counted and the healthy check after it sends one RECOVERED, FAILED then SUCCESS then healthy sends no RECOVERED, and an old two-line file reads as none. WD-29 in TESTING.md has the SUCCESS-then-healthy case as a second part. Routers get the fix only when the watchdog is deployed again, so the release note says so. Remainder: ID-629, the hand run on Merlin (stock's run is ID-655).
```

### ID-629

```text
- ID-629 TST: continuing ID-650, which built the fix: WD-29, now with the SUCCESS-then-healthy case, on Merlin: a tunnel that mends itself after a FAILED alert sends one RECOVERED email (ID-628). Needs this release's watchdog deployed to the router, by SAVE & DEPLOY on each watchdog. Its stock run is ID-655, since the router is on Merlin for several days (Andrew, 2026-11-22).
  - DoD: WD-29 run by hand on Merlin, its result written in TESTING, and any failure a bug under its own ID.
  - Closed 2026-11-22: both parts run on a throwaway slot on Merlin 388.13, with Andrew's yes for the emails (SUCCESS 16:22, SUCCESS 16:31, SUCCESS 16:45, FAILED 16:54, RECOVERED 16:54, SUCCESS 16:55, SUCCESS 16:57, router time): one FAILED, then exactly one RECOVERED within a check of the cut being removed and nothing on the two checks after; the second part sent one SUCCESS and no RECOVERED. The slot has to have DNS that differs from the router's: a sharing slot that goes dead can't send its FAILED email, which is the old documented failure and is now written into WD-29. Its stock run is still ID-655.
```

### ID-634

```text
- ID-634 FTR: every email the watchdog script sends states the app version and build the script was deployed from, for example in the footer. The version is already stamped into each deployed script's header (see `summariseScriptVersions`), and slots are deployed separately, so an alert can come from a script a build or more behind the app. Today the email doesn't say which.
  - DoD: every email type the watchdog sends (failure, recovery and any other) carries the version and build, a test fails if one doesn't, and a slot deployed from an older build shows its own.
  - Closed 2026-11-22: most of it was there from build 554: the script's SUCCESS, FAILED, RECOVERED, deploy and fault emails each carry "Watchdog: wgcN:pia-region, deployed by cfg-pia-wg vX build N" from the version stamped into that slot's script, so a slot deployed from an older build shows its own. What was missing was a check, and the app's own test email, which said nothing about the build that sent it; it now reads ", sent by cfg-pia-wg vX build N" (`routerRows`' `sentBy`). `watchdog_email_version_test.dart` runs the script for real for each email type, for an older build's script beside the app's, and for a script that knew no version; a control that takes the stamp out is seen, so the checks can fail. The version is in the Watchdog row, not a footer: it is the one place every email already had it.
```

### ID-668

```text
- ID-668 BUG: installing a newer app didn't bring the Merlin guard up to date on a router with the guard and no watchdog script. The check at the first connection (ID-487) read the watchdog scripts and stock's `guard.sh` and never `merlin-guard.sh`; on Merlin the guard was refreshed only as a side effect of updating a watchdog script, or at the next slot or DEVICES change. The hold and the takeover of this build live in that script, so such a router would have kept the old one. Found 2026-11-22 when Andrew said an app update must update the guard and the watchdogs both.
  - DoD: on Merlin, with no watchdog script to update, an older guard is replaced at the first connection and logged in both logs; one that is already this build's, or none, is left alone; an unpaid version writes nothing; stock never looks.
  - Closed 2026-11-22: `refreshMerlinGuardIfInstalled` in `router_watchdog.dart`, called from `checkRouterScripts` when no watchdog script needs updating. It reads the installed script, and replaces it, and the hooks with it, only when one is there and differs from this build's; a router with no guard is not given one. Six tests in `router_script_integrity_test.dart`, and the one for an old guard fails with the change taken out.
```
