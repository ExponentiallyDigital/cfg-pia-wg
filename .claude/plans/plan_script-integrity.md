# Plan: scripts on the router can't be left broken, and a broken one is never silent (ID-482 to ID-491)

Where each item stands is its `Now:` line in CHANGELOG.md or BACKLOG.md, not here. This file holds the reasoning and the design.

## End state

A script the app puts on the router is either the old one, whole, or the new one, whole. If one is damaged anyway, or fails while it runs, it shows as a red ERROR in the router log and the app log, by email when that slot's alerts are on, and on screen. In paid versions the app keeps the scripts up to date by itself.

## What happened, 2026-10-29

- Andrew updated the watchdog scripts from ABOUT, on build 553, from his phone. One SSH login at 15:08:10. wgc1's update finished and logged "Watchdog script updated to v0.8.183 build 553 for wgc1:pia-nz" at 15:08:22. wgc5's did not.
- `watchdog_wgc5.sh` was left at 7,940 bytes, where wgc1's is 48,994, ending on a line boundary (`else`). The write sends pieces of up to 4,000 bytes, the first replacing the file (`>`) and the rest adding to it (`>>`) (`heredocWriteCommands`, `lib/router_watchdog.dart`). So the first two of about 13 pieces landed, and the third failed. No second login followed, so the connection dropped or the write timed out. Why is unknown: there is no app log from that day.
- The app's size check (`_writeFile`) then threw, but the damaged file was already the live one, and nothing put the old one back.
- The error never reached the router log. `redeployScripts` is the one router-changing action not wrapped in `_guard`. `_guard` would have sent it over the same connection anyway, and swallows the failure when that connection is gone. ABOUT drops the error, on screen and in the app log, if the screen was left first (`if (!mounted) return;`, `lib/screens/about_screen.dart`).
- Cron ran the cut-short script every 5 minutes. The cron copy re-starts itself detached with all output sent to `/dev/null`. The detached copy stops at a syntax error in the unfinished `if` block, before the "Watchdog started" line. Nothing reached the router log after 15:06:00.
- ABOUT's version check reads only line 2, which was intact, so it showed build 553 and offered no UPDATE.
- Found on 2026-10-30, when Andrew saw wgc5 down. The router log is in Andrew's report of 2026-10-30.
- A side note for ID-482: the shell reads a script as it runs it, so writing over a live script during a rebuild could also break that run. A rename leaves the running copy whole.

## Design

### ID-482: write beside, check, rename

- One write function for every file: the pieces go to `<path>.new.<unique>`. The size and the last line are checked, then the file mode is set, then `mv` puts it over `<path>`. A rename on the same filesystem is atomic.
- The unique suffix means two phones writing at once can't mix their pieces. A leftover from a failed write is cleared by the next write to that path, and UNINSTALL takes the folder.
- Used by `_writeFile`, `FailClosedGuard.install` and the boot script write (`lib/fail_closed_guard.dart`). The other heredoc writes (the widget's key upload, `/tmp/mail.txt`) are checked too, and changed where a half-written file could matter.

### ID-483: the update reports itself

- `redeployScripts` goes through `_guard`. Success is logged in both logs, as it already is; failure is too, red.
- If the router log line can't be sent, one fresh connection is tried. Failing that, the line is kept and written at the next connection, with the time it happened.
- ABOUT logs and shows the result whether or not it is still open. Leaving it is blocked while the update runs (`PopScope`).

### ID-484: the script checks itself

- A fixed last line, e.g. `# end of watchdog_wgc5.sh`, after `exit 0`. Ending in a comment does not change what the script does.
- The check sits in the first lines, before the cron re-start, so it runs even on a cut-short file. A missing end line logs `ERROR: watchdog_wgc5.sh is damaged (7940 bytes), so this watchdog is not running. Update the watchdog script in ABOUT.`
- Router log lines are red only when they carry the app's tag and contain "error" or "failed" (`isRouterLogError`, `lib/router_log_paging.dart`). A test runs every new message through that function, and is seen to fail with the word taken out.
- The email uses that slot's own NVRAM mail settings and a small mail function at the top of the script, since `send_alert` lies past where a damaged file may end. It is spaced by the ladder `backoff_for` uses (120 s doubling to 5,400 s), with its own state file in `/tmp`.

### ID-485: every script error is captured

- The detached run's errors go to a file in `/tmp`, not `/dev/null`. The next run reports what it finds as a red ERROR, emails as ID-484 does, and clears it.
- The cron re-start is load-bearing (ARCHITECTURE 7.8: ASUS's curl refuses to run with crond in its ancestry). Sending errors to a file must not put anything back into that ancestry, so it is measured on hardware before it is relied on.
- The same goes for `guard.sh` and the boot script.

### ID-486: the app checks what is on the router

- In one read: each deployed script's version line and last line, and each watchdog cron entry against its script file.
- Damaged, or a cron entry with no script: red in both logs, red in ABOUT, and ABOUT offers UPDATE. Today it offers UPDATE only for a version difference (`_scriptStale`).

### ID-487: automatic updates

- At the first connection to a router in a session, paid versions only. Any watchdog script or `guard.sh` that is older than the app, or damaged, is rewritten through ID-482's write. The boot script is refreshed as `redeployScripts` does now. Each update is logged in both logs, and a snackbar says the scripts were updated.
- Only older is replaced, never newer: two phones on different builds would otherwise rewrite each other's scripts at every connection. A script with no version, from before build 415, counts as older.
- `guard.sh` gets a version line. Today it is compared by its whole text, which can't tell older from newer.
- A banner shows only what the app couldn't fix: a failed update, or a damaged script it couldn't replace.

### ID-488: the widget

- First, see what the widget's restricted login can run (its `command=` read, `lib/widget_status_service.dart`). If it can't read the scripts, the app's own check (ID-486) has to leave a marker the widget can read.

## Settled while building, 2026-11-01

- The watchdog's self-check comes in two halves. The log line comes first, right after the identity lines, at about 2.4 KB. The email and the fault record come after the fault functions they need, done by 6,547 bytes on stock and 6,852 on Merlin. A cut the size of 2026-10-29's (7,940) gets all of it, and a test holds both below 7,940. A cut between 2.4 KB and the end of that block logs but can't email. A cut before 2.4 KB is caught only by the app (ID-486) and by `check-claims.sh` `WHOLE-`.
- The error files are named by the process id of the run that writes them, so the next run can tell a finished run (`kill -0` fails) from one still going. The guard's and the boot script's are claimed by a rename, so two watchdogs never report the same one.
- On Merlin there is no guard or boot script, so the guarded-slots read is left out of its script altogether. A test on Merlin had caught the stock-only `vpnc_clientlist` read in its script.
- The guard harness's `ip` stand-in wrote "cannot open .../state/up" to stderr on every run. The guard now keeps stderr, so that showed up at once. The harness now starts with an empty file. On a router, what the real commands write to stderr in normal runs is unmeasured: TESTING LOG-9 measures it over a day.
- The widget's read grew by about 165 characters, so its key's line on the router is about 915 characters, where it was about 750 (ID-467 is about that length).
- `RecordingSSHClient` answers `tail -n 1` and models `mv -f`, so the service tests follow a write to the temporary file and into place.

## Decisions (ID-489)

Andrew, 2026-10-31:

- Updates are automatic, in paid versions only, because they write to the router. No banner for unpaid versions: there were no paying customers until recently.
- Never update to an older version. Damaged scripts are replaced the same way. The banner is only for what the app couldn't fix. ABOUT's check stays.
- A damaged or failing script emails only when that slot's own email alerts are on, spaced by the watchdog's backoff ladder, not once a day.
- A watchdog checking on the others is parked (ID-490): each slot can have its own email settings, so one slot reporting another's fault needs a decision on whose settings it uses.
- Every release's What's New says how the scripts get the release (ID-491).
- `guard.sh` isn't a slot, so a damaged `guard.sh` emails through each slot with alerts on whose devices it guards, each by its own settings.

## How a fault like this reaches you

| Item | What | Router log | App log | On screen | Email | 29 Oct |
| --- | --- | :-: | :-: | :-: | :-: | --- |
| ID-482 | Write beside, check, rename | | | | | prevents it |
| ID-483 | The update reports itself | ✓ | ✓ | ✓ | | the failed write |
| ID-484 | The script checks itself | ✓ | next connection (ID-486) | | ✓ | the cut-short script, every 5 minutes |
| ID-485 | Every script error captured | ✓ | next connection (ID-486) | | ✓ | the syntax error |
| ID-486 | The app checks the router | ✓ | ✓ | ✓ | | at the next connection |
| ID-487 | Automatic updates | ✓ | ✓ | banner if it fails | | replaced at the next connection |
| ID-488 | The widget | | | widget | | without opening the app |
| ID-490 | Watchdogs check each other (BACKLOG) | ✓ | | | ✓ | from wgc1 |
