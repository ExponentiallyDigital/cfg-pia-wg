- CHG: rebuild test/reconfigure email. Two changes:

(1.) Create three new nvram settings:
  `cfg_pia_wg_sdate=yyyy-mm-dd` - stores the date the app was first used to deploy a WATCHDOG or send a test email.
  `cfg_pia_wg_reconfig_ok=N` - incremented every time a reconfigure event is sucessful, set this to 0 initially. (renamed from `cfg_pia_wg_wd-reconfig_ok`, see the second review below)
  `cfg_pia_wg_reconfig_fail=N` - incremented every time a reconfigure event fails, set this to 0 initially.
  Update the two utility scrips `scripts\showall.sh` & `scripts\clearall.sh` to show/delete these new nvram settings.
  Update `ARCHITECTURE.md` section "3. Router WireGuard NVRAM fields" with details of the fields you have added.
  Update CONTEXT.md to say that any nvram variables added to the app must be described in `ARCHITECTURE.md` section "3. Router WireGuard NVRAM fields".

(2.) update the email contents from:
(2.1)**ALERT/RECONFIGURE/SUCCESS/FAILED EMAIL**
Subject: cfg-pia-wg alert - `<event detail eg "FAILED (curl addKey request failed)">`
Watchdog wgcN reconfiguration: `<event detail eg "FAILED (curl addKey request failed)">`
Region: pia-regaion_name
Time: yyyy-mm-dd hh:mm:ss

(2.2)**TEST EMAIL**
Subject: watchdog config test
This is a test email from the cfg-pia-wg watchdog (slot wgc1).
WATCHDOG_EOF

(3) change them to:
(3.1)**ALERT/RECONFIGURE/SUCCESS/FAILED EMAIL**
Subject: cfg-pia-wg alert: SUCCESS | FAILURE
`<br>`
Router: `<router-dns-name>`<- if no DNS name is set, use the router's private (local) IP address.
Watchdog: wgcN:pia-region_name
Reconfiguration event: `<reason for success or failure, include any codes returned by addkey, curl and all diagnostic information that we have available from any command that the watchdog script ran or failed to run>`
Router timestamp: yyyy-mm-dd hh:mm:ss <-get the time from the router
Uptime: 15:11:29 up 19:21,  load average: 2.55, 2.39, 2.36 <- run `uptime`
`<br>`
Since first deployed on `cfg_pia_wg_sdate=yyyy-mm-dd (if empty, use today's date)`, there have been `cfg_pia_wg_reconfig_ok=N` sucessful reconfigure events, and `cfg_pia_wg_reconfig_fail=N` failed events.
`<br>`
Please consider adding a review via [the Play Store](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true), or in app if this app is helpful to you.
`<br>`
Thank you,
cfg-pia-wg by Exponentially Digital.
`<br>`

(3.2)**TEST EMAIL**
Subject: cfg-pia-wg alert: TEST email
`<br>`
Router: `<router-dns-name>`<- if no DNS name is set, use the router's private (local) IP address.
Watchdog: wgcN:pia-region_name <- if no watchdog has been saved set this to "region not yet set, configuration pending deployment"
Event: test email manually sent via the watchdog dialogue box
Router timestamp: yyyy-mm-dd hh:mm:ss `<- get the time from the router
`<br>`
Since first deployed on `cfg_pia_wg_sdate=yyyy-mm-dd`, there have been `cfg_pia_wg_reconfig_ok=N` sucessful reconfigure events, and `cfg_pia_wg_reconfig_fail=N` failed events.
`<br>`
Please consider adding a review via [the Play Store](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true)` or in app if this app is helpful to you.
`<br>`
Thank you,
cfg-pia-wg by Exponentially Digital.
`<br>`

Note: something to consider, as the app execs the watchdog at deployment then the first run will send an email alert as RECONFIGURE event with status SUCCESS which isn't correct is it **configured** it rather than **re-configured** it. Is there any way we can make (3.1) display "Reconfiguration event: watchdog deployed" and set the subject to "cfg-pia-wg alert: SUCCESS"?
---

## Addendum 2026-09-05 - decisions and layout mock-ups (awaiting sign-off on the layout)

### Decisions taken

1. **Plain text, no HTML.** Every `<br>` above becomes a real line feed. mailsend-go sends the
   `-file` body verbatim and the Merlin path already declares `Content-Type: text/plain`, so a `<br>`
   would render literally. The Play Store link becomes a bare URL, which every modern client makes
   clickable. Consequence: markdown link syntax `[the Play Store](...)` cannot be used either.
2. **Script size ceiling raised 10000 -> 24576 bytes** in `test/router_watchdog_unit_test.dart`.
   The old number was the dropbear `MAX_CMD_LEN` (9000) plus headroom; since the script is written
   through `heredocWriteCommands` in chunks, that limit no longer applies and the assertion is now
   only a "notice when it grows unexpectedly" tripwire. The rebuilt script measures ~15 KB, so 24576 leaves around 9 KB of padding.
3. **Token backoff comes after this change**, so during a sustained outage the failure counter still
   increments once per `COOLDOWN` (120 s). `nvram commit` writes flash, so the counters are
   committed **once per alert**, never once per check.
4. **First run reports a deploy, not a reconfigure** - see "Run mode" below.

### Run mode - answering the note at the end of the original plan

The app already execs the script itself at deploy time, so it can simply say so:

```sh
/jffs/cfg-pia-wg/watchdog_wgc1.sh deploy
```

The script captures the run mode on its **first line of executable code**, before `send_alert()` can
shadow `$1` with its own argument:

```sh
RUNMODE="${1:-cron}"      # `deploy` only when the app runs it by hand after writing it
```

Cron lines pass nothing and behave exactly as now. On a deploy run the event line reads
`watchdog deployed` and the subject still says `SUCCESS`, which is what was asked for.
`buildCronCheckLine` is unchanged, so a watchdog re-enabled from the app is a `cron` run, not a
`deploy` one.

### Where each field comes from

| Field | Source | Cost |
| --- | --- | --- |
| Router name | `nvram get ddns_hostname_x`, else `nvram get lan_hostname`, else `nvram get lan_ipaddr` | nvram |
| Router LAN IP | `nvram get lan_ipaddr` | nvram |
| Model / firmware | `nvram get productid`, `nvram get buildno`.`nvram get extendno` | nvram |
| App version | baked into the script as `APPVER=__APPVER__` at deploy time | none - **no new NVRAM key** |
| Router time + zone | `date '+%Y-%m-%d %H:%M:%S %Z'` | builtin |
| Uptime | `uptime` | builtin |
| Kill switch | `$ENFORCE` (already read at the top of the script) | none |
| Last known good / outage | `$STATUSFILE` contents | none |
| Attempt number | `$CNT` from `$BACKOFFFILE` | none |
| Check interval | `nvram get ${K}wd_check_interval` | nvram |
| New server + latency | `$BEST_CN`, `$BEST_IP`, `$SERVER_PORT`, `$BEST_RTT` | none |
| Log excerpt | `tail -10 "$LOGFILE"` | none |
| Counters + start date | the three new `cfg_pia_wg_*` keys | nvram |

Nothing here needs a network call, so no alert gets slower and no third party learns the router's
address. The public exit IP was considered and **rejected** for exactly that reason.

### Layout

Sectioned, upper-case headings, one `Label: value` per line, blank line between sections. Headings are not underlined and values are **not** space-padded into columns: Gmail on Android renders `text/plain` in a proportional font, where padded alignment goes ragged. Not wrapped (leave that up to the email cient).

#### A. First run after deployment

```
Subject: cfg-pia-wg alert: SUCCESS - wgc1:pia-aus_melbourne

Watchdog deployed and the tunnel is up.

WHAT HAPPENED
Event: watchdog deployed
Connected to: 45.134.140.101:1337 (handshake 12s ago)
Kill switch: ON - traffic is blocked if the tunnel drops
Interval: 5 minutes

ROUTER
Name: my-router.asuscomm.com (192.168.1.1)
Model: RT-AX88U, firmware 3.0.0.4.388_24762
Time: 2026-09-05 14:32:53 AEST
Uptime: 15:11:29 up 19:21, load average: 2.55, 2.39, 2.36
Watchdog: wgc1:pia-aus_melbourne, deployed by cfg-pia-wg v0.8.34 build 404

HISTORY
Since 2026-09-05 this router has recorded 0 successful and 0 failed reconfigurations.

If cfg-pia-wg is useful to you, please consider submitting a review by tapping on the home screen link or via https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true

Thank you,
cfg-pia-wg by Exponentially Digital
```

The endpoint comes from `${K}ep_addr:${K}ep_port` and the age from `wg show latest-handshakes`,
because a deploy run that finds the tunnel already up never calls addKey - so `$BEST_CN` and
`$BEST_RTT` do not exist on that path. A deploy run that *did* have to reconfigure reports the
server name and latency exactly as mock-up B does.

A deploy where the tunnel could not be brought up sends the failure email, opening with
`Watchdog deployed but the tunnel could NOT be brought up.` under subject `FAILED`.

#### B. Reconfigure SUCCESS

Same shape; only the opening line and the first block differ.

```
Subject: cfg-pia-wg alert: SUCCESS - wgc1:pia-aus_melbourne

Connectivity was lost and the tunnel has been rebuilt.

WHAT HAPPENED
Event: reconfigured successfully on attempt 2
Tunnel was down for: 6m 12s (last seen good 2026-09-05 14:26:41 AEST)
Kill switch: ON - no traffic left the router while it was down
Reconnected to: melbourne408 (45.134.140.101:1337), 9 ms
Interval: 5 minutes

ROUTER
...as above...

HISTORY
Since 2026-09-01 this router has recorded 4 successful and 1 failed reconfigurations.

...review and sign-off as above...
```

#### C. Reconfigure FAILED

The event detail carries every code the failing command returned - it is the existing `abort`
string, unchanged, so nothing is lost. Two blocks appear **only** on failure: `WHAT TO DO` and
`ROUTER LOG`.

```
Subject: cfg-pia-wg alert: FAILED - wgc1:pia-aus_melbourne

Connectivity was lost and the tunnel could NOT be rebuilt.

WHAT HAPPENED
Event: failed to obtain PIA token (exit 0, HTTP 403, body 34B: {"error":"rate limit exceeded"})
Tunnel has been down for: 41m 09s (last seen good 2026-09-05 13:58:12 AEST)
Kill switch: not supported on this firmware - traffic is reaching the internet without the VPN
Attempt: 8 since the last success, retrying per schedule, 5 minutes

WHAT TO DO
1. Check your PIA username and password in the app, under WATCHDOG then CONFIGURE.
2. Open VIEW WATCHDOG LOG in the app for the full history.
3. PIA rate-limits repeated token requests; if the code above is 403, wait 30 minutes before intervening.
4. Is your PIA billing account active?

ROUTER
...as above...

HISTORY
...as above...

ROUTER LOG (last 10 lines)
2026-09-05 14:32:41 Checking wgc1 pia-aus_melbourne connectivity
2026-09-05 14:32:44 No handshake and both pings failed (9.9.9.9, 1.1.1.1)
2026-09-05 14:32:44 Connectivity lost; reconfiguring (attempt #8)
2026-09-05 14:32:44 WAN has internet connectivity
2026-09-05 14:32:44 Using cached CA cert
2026-09-05 14:32:45 Requesting PIA token for user p1234567
2026-09-05 14:32:46 ERROR: failed to obtain PIA token (exit 0, HTTP 403)

...review and sign-off as above...
```

Three variants of those lines:

- **Kill switch** has three states, not two: `ON`, `OFF - the kill switch is available but is not
  enabled` (Merlin, where it exists and the user turned it off), and the stock line above, since
  stock has no kill switch at all. Each also needs three **tenses**, because the same fact reads
  wrong in the wrong one - implemented as `KILLSW_UP` / `KILLSW_FIXED` / `KILLSW_DOWN`:
  - up (a deploy run, nothing wrong): `ON - traffic is blocked if the tunnel drops`
  - recovered (the outage is over): `ON - no traffic left the router while it was down`
  - still down (a failure): `ON - traffic is blocked while the tunnel is down`

  A failure takes the still-down wording whether or not the run was a deploy. Revisit the stock
  wording once in-app device assignment lands - a device assigned to a downed wgcN simply loses
  connectivity, which is a truer thing to tell the user than "traffic is reaching the internet".
- **Last seen good** is read from `$STATUSFILE`, which lives in `/tmp` and does not survive a reboot.
  With no file: `Tunnel has been down for: unknown (no successful check since the router last
  rebooted)`.
- **Interval** is not repeated in a failure email - the `Attempt:` line already carries it.

`ROUTER LOG` can contain the PIA username, as the excerpt above shows. It never contains the
password or the token: the script logs the token's *length* only. Noted so it stays a deliberate
choice.

#### D. Test email

```
Subject: cfg-pia-wg alert: TEST email - wgc1:pia-aus_melbourne

This is a test email from cfg-pia-wg. Your SMTP settings work; watchdog alerts will reach this address.

WHAT HAPPENED
Event: test email sent by hand from the watchdog configuration screen
Interval: 5 minutes

ROUTER
Name: my-router.asuscomm.com (192.168.1.1)
Model: RT-AX88U, firmware 3.0.0.4.388_24762
Time: 2026-09-05 14:32:53 AEST
Uptime: 15:11:29 up 19:21, load average: 2.55, 2.39, 2.36
Watchdog: wgc1:pia-aus_melbourne

HISTORY
Since 2026-09-05 this router has recorded 0 successful and 0 failed reconfigurations.

...review and sign-off as above...
```

When no watchdog has been saved yet the `Watchdog:` line reads `region not yet set, configuration
pending deployment` and the interval line reads `Interval: not set, watchdog has yet to be saved and
deployed.` - the interval is read from NVRAM, never from the unsaved dialog, so the email can never
state a schedule that is not actually running.

### Decided alongside the layout - first review

1. **The configurable subject field becomes dead.** `wgcN_wd_email_subject` is set in the watchdog
   dialog and currently forms the subject as `<your subject> - SUCCESS`. A fixed `cfg-pia-wg alert:`
   prefix discards it. Suggested: keep the field as the prefix and default it to `cfg-pia-wg alert`,
   which gives `cfg-pia-wg alert: SUCCESS - wgc1:pia-aus_melbourne` out of the box while still
   honouring a user who set something else. The alternative is to remove the field from the dialog.
   AGREED.
2. **`FAILED` vs `FAILURE`.** The plan above says `SUCCESS | FAILURE`; the script, the app log and
   the router log all say `FAILED`. The mock-ups use `FAILED` for consistency - say if you prefer
   `FAILURE` and it changes everywhere.
   USE FAILED.

### Implementation notes

- **One layout, two languages.** Alert bodies are written by the shell script; the test email body
  is written by Dart. To stop them drifting, the Dart builder emits the shell that goes into the
  script template, and a test asserts both produce the same section headings in the same order.
- **One SSH round trip for the test email.** The app needs hostname, LAN IP, model, firmware, date,
  uptime and three counters - fetch them in a single command with a delimiter, not nine `_run` calls.
- **Counters are written by the script** on a reconfigure outcome, and seeded (`sdate` plus both
  counters at 0) by whichever of watchdog deploy or test email happens first.
- Update README.md to include the email alerting function described in this plan and include example emails with made up information.

### Decided alongside the layout - second review

1. **The home-screen review link does not exist yet.** The email text points at it, so it must.
   Adding it is now the WIP item immediately after this one, landing in the same build - see
   CHANGELOG `### 1.2. WIP`, "new button on the home screen invoking the in_app_review". The email
   wording stands as written.
2. **Counter names are `cfg_pia_wg_reconfig_ok` and `cfg_pia_wg_reconfig_fail`** - symmetric, no
   hyphen. This supersedes `cfg_pia_wg_wd-reconfig_ok` in section (1.) above. `cfg_pia_wg_sdate` is
   unchanged.
3. **A deploy run always sends an email**, including when it finds the tunnel already healthy and
   returns at the early `exit 0`. It doubles as proof that alerting works, which is most of the
   point of sending it. No server name and no latency on that path - see mock-up A.
4. **The alert flood during a sustained outage is left alone here.** Every `abort` emails and the
   cooldown is 120 s, so a long outage sends many near-identical alerts. That is pre-existing, and
   the next-but-one WIP item ("back off when PIA refuses a token request": 2, 4, 8, 16, cap 30 min)
   is what fixes it. This branch is DEV and has one user.
5. **Kill switch: three states**, and the stock wording gets revisited after in-app device
   assignment - see the note under mock-up C.
6. **`retrying per schedule, X minutes`**, X read from `${K}wd_check_interval`.
7. **Missing `$STATUSFILE` reads "unknown (no successful check since the router last rebooted)".**
8. **A failed deploy opens with `Watchdog deployed but the tunnel could NOT be brought up.`**
   under subject `FAILED`.
9. **The interval row is labelled `Interval:` in every email** rather than `Checks:`, so the
   not-set sentence and the normal case share a label. On a failure email the row is dropped, since
   the `Attempt:` line already states the schedule.
