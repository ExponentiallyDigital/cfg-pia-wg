# Notes on testing cfg-pia-wg

- [1. Before you start](#before-you-start)
- [2. When something looks broken, check these first](#when-something-looks-broken-check-these-first)
- [3. Home screen](#home-screen)
- [4. Standalone (generate)](#standalone-generate)
- [5. Manage](#manage)
- [6. Watchdog](#watchdog)
  - [6.1. Checks](#checks)
    - [6.1.1. Invalidate the registration (the important one)](#invalidate-the-registration-the-important-one)
    - [6.1.2. What does NOT work: moving the endpoint](#what-does-not-work-moving-the-endpoint)
    - [6.1.3. Peer removed (the fast one)](#peer-removed-the-fast-one)
    - [6.1.4. Interface down](#interface-down)
    - [6.1.5. What a healthy check looks like](#what-a-healthy-check-looks-like)
    - [6.1.6. Backoff](#backoff)
    - [6.1.7. Walking the whole backoff ladder in two minutes, with no PIA traffic](#walking-the-whole-backoff-ladder-in-two-minutes-)
  - [6.2. Applying a config, and what it should leave behind](#applying-a-config-and-what-it-should-leave-behin)
  - [6.3. Files deployed to the router](#files-deployed-to-the-router)
  - [6.4. Testing email send by hand](#testing-email-send-from-ssh)
    - [6.4.1. Construct the command line](#construct-the-command-line)
    - [6.4.2. Construct the test email](#construct-the-test-email)
    - [6.4.3. How the Commands Work](#how-the-commands-work)
    - [6.4.4. Certificate information](#certificate-information)
- [7. Device assignment](#device-assignment)
- [8. App log](#app-log)
- [9. Router log](#router-log)
- [10. Settings](#settings)
- [11. About](#about)
- [12. Credentials and exit](#credentials-and-exit)
- [13. Firmware coverage](#firmware-coverage)
- [14. Examining nvram settings](#examining-nvram-settings)

## 1. <a name='before-you-start'></a>Before you start

Clear all configs and NVRAM, then reboot the router.

---

## 2. <a name='when-something-looks-broken-check-these-first'></a>When something looks broken, check these first

Each of these presents as a different fault from the one it is, and none of them is guessable. Check
them before spending time anywhere else.

**`rc_service: skip the event:` in `/tmp/syslog.log`.** The router is silently discarding every
service call it is given, and has been since some earlier one hung without finishing. Nothing works
after that - not the app, not the web interface, not `reboot`. **Only a power cycle clears it.**
The app now detects and clears the stale marker before deploying, but if you see this line while
testing by hand, stop: nothing you observe afterwards means anything. Detail in
[ARCHITECTURE.md, The router's service queue and how it wedges](ARCHITECTURE.md#the-routers-service-queue-and-how-it-wedges).

**A token fetch that exits 0 with no HTTP status, no body and nothing on stderr.** Stock's
`/usr/sbin/curl` walks its own process ancestry and refuses to run when `crond` appears in the chain.
It does not fail, it does nothing, which is far harder to spot. Confirm it by looking for
`Invalid caller(crond)` in `/jffs/curllst`. Detail in
[ARCHITECTURE.md, `curl` refuses to run from cron](ARCHITECTURE.md#curl-refuses-to-run-from-cron).

> [!CAUTION]
> `/jffs/curllst` is world-readable, survives reboots, and records **full command lines including
> `-u user:password`**. Redact it before pasting it anywhere, including into a bug report.

**A device assignment that is written correctly and has no effect.** Check `ip rule show` before
anything else. Stock never removes a device's previous rule when it is reassigned, so both rules sit
at priority 100 and the older one matches first. The record in `vpnc_dev_policy_list` will look
perfect the whole time. Detail in
[ARCHITECTURE.md, Stock leaves the old routing rule behind](ARCHITECTURE.md#stock-leaves-the-old-routing-rule-behind-measure).

---

## 3. <a name='home-screen'></a>Home screen

- all five buttons navigate; HOME and the back key return here
- "how to use this app" opens the README section
- "add a Play Store app review" opens the Play listing
- PAYPAL and PATREON open

---

## 4. <a name='standalone-generate'></a>Standalone (generate)

- create a config and apply manually
- heading reads "GENERATED CONFIG: pia-region_name"
- clear the DNS field, leave the screen, return - Quad9 defaults are back
- COPY - 60s countdown, then the clipboard empties with no "cleared" popup
- SHARE and SAVE

---

## 5. <a name='manage'></a>Manage

- create wgc1-5
- enable wgc1 & 5
- edit wgcN
- ACTIVE badge on every slot whose interface is up, not just one
- DISABLE leaves `wg show interfaces` empty
- stock: a third concurrent enable is refused with the VPN-limit dialog
- DELETE prompt names the VPN being deleted

Applying configs:

- Apply a new config to a blank slot
- Overwrite an existing slot with a different region's config
- Overwrite an existing slot with the same region's config

---

## 6. <a name='watchdog'></a>Watchdog

- Create wgc1 & wgc5 - check test email
- Disable wgc5, create wgc4, enable wgc4 - check nvram and tunnel up
- force a reconfigure, then check the email alerting
  1. `wg set wgc1 peer "$(nvram get wgc1_ppub)" remove`
  2. `/jffs/cfg-pia-wg/watchdog_wgc1.sh`
- Check emails
  1. deploy email says "watchdog deployed", subject SUCCESS, sent even though nothing was wrong
  2. reconfigure email: outage duration, kill-switch line, new server and latency
  3. failure email: WHAT TO DO, attempt count, last 10 router-log lines
  4. HISTORY counters climb; `cfg_pia_wg_sdate` is set once and not rewritten
  5. subject threads by slot: `cfg-pia-wg alert: SUCCESS - wgc1:pia-<region>`
- DISABLE shows the PAUSED badge; ENABLE restores the same interval
- keyboard does not obscure the configure dialog's fields
- backoff: leave it failing and watch the log - "Backing off after N failed attempts", waits growing 2, 4, 8, 16, 30, 60, 90 min

### 6.1. <a name='checks'></a>Checks

1. check that boot persistence contains the two cru lines (5m watchdog)

On Merlin that is `/jffs/scripts/services-start`; on stock the app owns the replacement block of `/opt/etc/init.d/S50downloadmaster` instead, between the `REPLACEMENT START` / `REPLACEMENT END` markers.

```bash
#!/bin/sh
cru a watchdog_wgc1 "*/5 * * * *" /jffs/cfg-pia-wg/watchdog_wgc1.sh
cru a watchdog_log_rotate_wgc1 "0 0 * * *" "mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old && touch /tmp/watchdog_wgc1.log"
```

2. check cron and cru are updated in realtime, test 1m and 10m

```bash
user@host:/tmp/home/root# crontab -l
*/1 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#
0 0 * * * mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old && touch /tmp/watchdog_wgc1.log #watchdog_log_rotate_wgc1#

user@host:/tmp/home/root# cru l
*/1 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#
0 0 * * * mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old && touch /tmp/watchdog_wgc1.log #watchdog_log_rotate_wgc1#
```

3. Is the deployed watchdog script correct?

Compare a post processed instance of `const String _kWatchdogScriptTemplate` in `lib\router_watchdog.dart` with `/jffs/cfg-pia-wg/watchdog_wgcN.sh`

4. check NVRAM is set correctly

```bash
user@host:/tmp/home/root# nvram show | grep wgc1
wgc1_wd_check_interval=1
wgc1_wd_email_enabled=0
wgc1_wd_email_from=
wgc1_wd_email_subject=cfg-pia-wg watchdog alert
wgc1_wd_email_to=
wgc1_wd_primary_ip=8.8.8.8
wgc1_wd_secondary_ip=1.1.1.1
wgc1_wd_smtp_pass=
wgc1_wd_smtp_server=
wgc1_wd_smtp_user=
```

```bash
user@host:/tmp/home/root# nvram show | grep cfg-pia-wg
cfg-pia-wg_password=REDACTED
cfg-pia-wg_user=REDACTED
```

6. Check `/tmp/watchdog_last_ping_success_wgcN`

Check that this file is created when a ping succeeds.

7. Check logs are generated

Check `/tmp/watchdog_wgcN.log` is generated

8. Check router syslog entries are created

Conduct, deploy, delete, reconfigure actions. Ensure these are logged to syslog.

9. Update `check interval` from 1 to 100 ensure NVRAM written, `cron` and `crontab` updated

10. Check cleanup ocurs when `DISABLE`/`DELETE` selected in UI

- cron jobs removed, check with `crontab -l` and `cru l`
- `/jffs/scripts/services-start` should only contain `#!/bin/sh`
- add a comment to `/jffs/scripts/services-start`, start watchdog and remove watchdog, comment should persist
- all files deleted

11. File permissions

Check `/jffs/scripts/services-start` permission is 777 `-rwxrwxrwx`
Check `/jffs/cfg-pia-wg/watchdog_wgcN.sh` permission is 777 `-rwxrwxrwx`

12. Reboot and check that cron and crontab are correct
    <br>
13. Force a reconfigure to occur

The watchdog decides a tunnel is alive from its **WireGuard handshake**: `wg show wgcN latest-handshakes` reduced to its newest peer, healthy if under 300 seconds old. A ping bound to the interface is only a fallback, because on stock the router's own traffic is not policy-routed into `wgcN` and `ping -I` fails on a perfectly healthy tunnel.

So a good test breaks the **crypto or the peer**, leaves the interface up, and touches neither the WAN nor NVRAM. Two things that look like good tests are not: disabling the interface in the WebUI exercises only the "interface down or absent" path and disturbs routing, and moving the peer's endpoint is undone within seconds by WireGuard's endpoint roaming - see [What does NOT work: moving the endpoint](#what-does-not-work-moving-the-endpoint).

> [!IMPORTANT]
> The clock runs from the **last handshake**, not from when you broke the tunnel. `wg show wgcN latest-handshakes` tells you exactly where you are; the watchdog reacts at the first check where that age exceeds 300 s, so worst case is 300 s **plus** one check interval. A check logging `Handshake 264s ago` after you broke it is the window working, not a failure - wait for the next one. Removing the peer - see [Peer removed (the fast one)](#peer-removed-the-fast-one) - skips the wait entirely.

> [!CAUTION]
> Any LAN client policy-routed through the slot loses internet for the duration of the test - the tunnel really is dead. That is confirmation the test worked, but do not run it on a slot something depends on.

> [!WARNING]
> PIA rate-limits token requests. Since 405 the watchdog backs off on consecutive failures - 2, 4, 8, 16, 30, 60 minutes, capped at 90 - which is what keeps a broken tunnel from provoking it, but two failing watchdogs still climb their ladders independently. If `failed to obtain PIA token` starts appearing, stop and wait 15-30 minutes; the log carries the HTTP status, so `HTTP 403` confirms throttling rather than a fault. Test one slot at a time, and prefer a 5 m check interval over 1 m for reconfigure tests.

#### 6.1.1. <a name='invalidate-the-registration-the-important-one'></a>Invalidate the registration (the important one)

The truest simulation of a PIA registration that has silently died: the interface stays up and keeps sending, the server no longer recognises us, and no handshake ever completes. Replace the interface's private key with a fresh one the server has never seen:

```bash
wg genkey > /tmp/breakit
wg set wgc1 private-key /tmp/breakit
rm -f /tmp/breakit

wg show wgc1 latest-handshakes    # stops advancing from here
```

Nothing can undo this from the far end - the server cannot authenticate a key it was never given - so the tunnel stays dead until the watchdog re-registers.

Expected in `/tmp/watchdog_wgc1.log` once the handshake passes 300 s:

```text
2026-09-04 16:40:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 16:40:08 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-04 16:40:08 Connectivity lost; reconfiguring (attempt #1)
2026-09-04 16:40:08 WAN has internet connectivity
2026-09-04 16:40:09 Requesting PIA token for user pNNNNNNN
2026-09-04 16:40:09 PIA token obtained (len=124)
...
2026-09-04 16:40:15 Reconfig SUCCESS: region pia-aus_melbourne via 45.130.141.215:1337
```

Recovery needs no cleanup: the re-negotiation generates a new keypair, registers it, rewrites `wgc1_*` in NVRAM and restarts the slot.

#### 6.1.2. <a name='what-does-not-work-moving-the-endpoint'></a>What does NOT work: moving the endpoint

```bash
# looks right, does nothing - do not use
wg set wgc1 peer "$(nvram get wgc1_ppub)" endpoint 203.0.113.1:1337
```

`wg` accepts it and shows the new endpoint, then puts the real one back within seconds and no reconfigure ever happens. That is **endpoint roaming**, a WireGuard feature: a peer's endpoint is updated automatically whenever an authenticated packet arrives from a different source address. The PIA server is still sending, so the endpoint follows it home. Anything that leaves the keys intact will be undone the same way.

#### 6.1.3. <a name='peer-removed-the-fast-one'></a>Peer removed (the fast one)

Blunter, immune to roaming - there is no peer left for an inbound packet to update - and **detected at the very next check with no 300 s wait**, because removing the peer removes its handshake record too: `latest-handshakes` returns nothing, so the age test fails immediately.

Do not wait for cron: run the script by hand straight after, and the check interval stops mattering.

```bash
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
wg show wgc1                     # no peer listed
/jffs/cfg-pia-wg/watchdog_wgc1.sh
```

Verified on 2026-09-04 with a 5 m interval, reconfigured immediately:

```text
18:49:13 Checking wgc1 pia-aus_melbourne connectivity
18:49:13 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
18:49:13 Connectivity lost; reconfiguring (attempt #1)
18:49:14 PIA token obtained (len=124)
18:49:14 Selected server 45.130.141.159 (Server-12444-0a) for region pia-aus_melbourne
18:49:20 Interface wgc1 is up
18:49:20 Reconfig SUCCESS: region pia-aus_melbourne via 45.130.141.159:1337
18:50:00 Handshake 44s ago
```

Confirm the recovery, not just the log: `wg show wgc1` should list a peer again with a **different**
public key from the one you removed, and the next scheduled check should read `Handshake Ns ago`.

Running it again inside the backoff window gives `Backing off after N failed attempts: Xs of Ys elapsed` - that is the guard working, not a fault.

#### 6.1.4. <a name='interface-down'></a>Interface down

The one the WebUI gives you. Detected immediately - no 300 s wait, because the script tests `ifconfig` before the handshake:

```bash
ifconfig wgc1 down
```

```text
2026-09-04 16:45:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 16:45:00 Interface wgc1 is down or absent
2026-09-04 16:45:00 Connectivity lost; reconfiguring (attempt #1)
```

The reconfigure that follows rewrites the peer and restarts the interface, so the tunnel comes back on its own. If it does not, and the log stops at the token request, check that the deployed script carries a version marker of v0.8.46 build 416 or later - earlier scripts could not fetch a PIA token from cron at all (ARCHITECTURE.md "curl refuses to run from cron"). Clearing `/tmp/watchdog_backoff_wgc1` makes the next tick run in full rather than backing off.

#### 6.1.5. <a name='what-a-healthy-check-looks-like'></a>What a healthy check looks like

A working tunnel with an active watchdog will show:

```text
2026-09-04 15:48:00 Checking wgcN pia-region_name connectivity
2026-09-04 15:48:00 Handshake 60s ago
```

#### 6.1.6. <a name='backoff'></a>Backoff

The wait before the next reconfigure attempt grows with each **consecutive failed attempt** and resets the moment one succeeds:

| Consecutive failures |     1 |     2 |     3 |      4 |      5 |      6 |           7+ |
| -------------------- | ----: | ----: | ----: | -----: | -----: | -----: | -----------: |
| Wait                 | 2 min | 4 min | 8 min | 16 min | 30 min | 60 min | 90 min (cap) |

A check that arrives inside the wait is turned away and says so:

```text
2026-09-04 16:41:00 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-04 16:41:00 Backing off after 3 failed attempts: 45s of 480s elapsed
```

Check `/tmp/watchdog_backoff_wgc1` is created and holds the attempt count and timestamp. The count rises **only when an attempt is actually made** - a run the backoff turned away must leave it alone, or the ladder would climb faster on a 1 m interval than on a 5 m one.

#### 6.1.7. <a name='walking-the-whole-backoff-ladder-in-two-minutes-'></a>Walking the whole backoff ladder in two minutes, with no PIA traffic

**Why not just let it fail for four hours.** Reaching the 90-minute rung honestly means seven consecutive *failed reconfigures*, each of which asks PIA for a token. That is exactly the behaviour that got the account refused with HTTP 403 on 2026-09-04, and it would take most of a day. The test below reaches every rung in about two minutes and asks PIA for nothing at all.

**Why it is safe.** The backoff gate sits **after** the connectivity check and **before** the first PIA call. A run the gate turns away logs one line and exits, so pre-loading the counter exercises the real arithmetic in the real deployed script without a single token request.

**Why the watchdog must be PAUSED first.** Otherwise `cru` fires its own checks during the test. A scheduled run that arrives when the wait *has* elapsed would perform a genuine reconfigure - PIA traffic, a new key, and a reset counter part-way through the loop. Pausing removes the cron entries and leaves the script and settings in place, so only your manual runs execute.

**Why the timestamp is `now`.** The gate compares `now - LAST` against the rung's wait. Writing `$(date +%s)` as `LAST` guarantees roughly zero elapsed, so every rung is inside its window and every run is turned away - which is the state being tested.

**Why the check must be failing.** A healthy tunnel exits at the handshake check and never reaches the backoff block at all.

Set up so nothing else can interfere:

1. In the app, **DISABLE** the watchdog on the slot you are testing. It shows PAUSED, the `cru` entries go, and the script and settings stay - so only your manual runs execute and no scheduled check can surprise you.
2. Make the check fail. Either DISABLE the slot in MANAGE, so the interface goes away entirely, or remove the peer:

   ```bash
   wg set wgc5 peer "$(nvram get wgc5_ppub)" remove
   ```

Then run `scripts/test-backoff.sh` on the router (copy it across with `scp`). It re-checks both preconditions and refuses rather than misleading you, walks every rung, checks the two properties below, cleans up after itself, and exits non-zero on any failure:

```bash
./test-backoff.sh 5        # slot number; defaults to 5
```

Each iteration pre-loads the counter with a timestamp of *now*, so the wait cannot have elapsed and the script must turn the run away. The same loop by hand, if you would rather:

```bash
for n in 1 2 3 4 5 6 7 12; do
    printf '%s\n%s\n' "$n" "$(date +%s)" > /tmp/watchdog_backoff_wgc5
    /jffs/cfg-pia-wg/watchdog_wgc5.sh >/dev/null 2>&1
    echo "CNT=$n -> $(grep 'Backing off' /tmp/watchdog_wgc5.log | tail -1)"
done
```

Expected, in order: **120, 240, 480, 960, 1800, 3600, 5400, 5400** seconds. Verified on stock (RT-AX88U, build 409, 2026-09-06):

```text
CNT=1  -> Backing off after 1 failed attempts: 1s of 120s elapsed
CNT=2  -> Backing off after 2 failed attempts: 0s of 240s elapsed
CNT=3  -> Backing off after 3 failed attempts: 0s of 480s elapsed
CNT=4  -> Backing off after 4 failed attempts: 0s of 960s elapsed
CNT=5  -> Backing off after 5 failed attempts: 0s of 1800s elapsed
CNT=6  -> Backing off after 6 failed attempts: 0s of 3600s elapsed
CNT=7  -> Backing off after 7 failed attempts: 0s of 5400s elapsed
CNT=12 -> Backing off after 12 failed attempts: 0s of 5400s elapsed
```

Two things to confirm while you are there, because they are the properties most easily broken by a later change:

- `grep -c 'Requesting PIA token' /tmp/watchdog_wgc5.log` does not change across the loop. If it does, the gate has moved to *after* the first PIA call and a broken tunnel is once again hammering PIA on every check.
- `head -1 /tmp/watchdog_backoff_wgc5` still reads `12` afterwards. A turned-away run must not increment the counter - if it does, the ladder climbs at a rate that depends on the check interval, so a 1 m watchdog escalates five times faster than a 5 m one.

Clean up, then re-enable the watchdog in the app:

```bash
rm -f /tmp/watchdog_backoff_wgc5
```

### 6.2. <a name='applying-a-config-and-what-it-should-leave-behin'></a>Applying a config, and what it should leave behind

- check all NVRAM settings are cleared on script & watchdog disable

```bash
nvram show | grep pia_wg | sort
nvram show | grep qgc | sort
```

### 6.3. <a name='files-deployed-to-the-router'></a>Files deployed to the router

On both firmwares:

```text
/jffs/cfg-pia-wg/                         # everything the app owns lives here
/jffs/cfg-pia-wg/watchdog_wgcN.sh         # one per watched slot
/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt      # cached PIA CA, shared by all slots
/tmp/watchdog_wgcN.log                    # and .log.old after the nightly rotate
/tmp/watchdog_last_ping_success_wgcN
/tmp/watchdog_backoff_wgcN
```

Stock also gets, because it has no `/jffs/scripts` hooks:

```text
/jffs/cfg-pia-wg/jq                       # installed by the app
/jffs/cfg-pia-wg/mailsend-go              # installed by the app, only if email is enabled
/opt/etc/init.d/S50downloadmaster         # boot persistence, replacement block only
/opt/etc/init.d/S50asuslighttpd           # a stub that returns immediately
```

Merlin instead uses `/jffs/scripts/services-start` for boot persistence.

Three things to check on those two init scripts, because all three are recent:

- each carries `# <name> - auto-generated by cfg-pia-wg; *do* *not* edit.` as its **second line**
- where one replaced a real script, the original is beside it with a `.old` suffix
- the watchdog script carries a version line, and the About screen reports it

Where `N` is the slot number.

**What an uninstall leaves behind.** SETTINGS -> UNINSTALL removes everything above, every
`cfg_pia_wg_*` and `wgcN_wd_*` NVRAM key, and every `cru` entry it created. It does **not** touch the
tunnels: `wgcN_*` keys, the profiles and `vpnc_clientlist` are the user's, not the app's, and DELETE
on the Manage screen is what removes those. Device assignments and the default connection are left
alone for the same reason.

### 6.4. <a name='testing-email-send-from-ssh'></a>Testing email send by hand

**Use the TEST EMAIL button first.** The watchdog dialog sends a real message through the settings on
screen and reports what the server said, which is faster than anything below and tests the same path
the watchdog will use. What follows is for when that button fails and you need to see why.

**The two firmwares send mail differently, and only one of them is documented below.**

| Firmware | Sends with | Comes from |
| --- | --- | --- |
| Merlin | BusyBox `sendmail` wrapped in `openssl s_client` for implicit TLS | built in |
| Stock | `mailsend-go`, `-ssl -verifyCert` | installed by the app into `/jffs/cfg-pia-wg` |

BusyBox `sendmail` is not viable on stock, which is why the second exists. The hand-testing recipe
below is the **Merlin** one. The stock equivalent is a single command:

```bash
/jffs/cfg-pia-wg/mailsend-go -ssl -verifyCert \
    -smtp smtp.gmail.com -port 465 -sub "test from the router" \
    -f "sender@example.com" -t "recipient@example.com" \
    auth -user "sender@example.com" -pass "APP_PASSWORD" \
    body -file /tmp/test-email.txt
```

`mailsend-go` builds its own RFC-822 headers from those flags, so the body file it takes is the
message text alone - no `From:`, `To:` or `Subject:` lines, and no blank separator line. That is the
one difference that will catch you out if you copy the Merlin body below.

Both routes use TLS with a verified CA bundle and fail the handshake rather than falling back, so an
alert never leaves the router with the credentials exposed.

#### 6.4.1. <a name='construct-the-command-line'></a>Construct the command line

Replace `sender@example.com`, `recipient@example.com`, and `APP_PASSWORD` in the below:

```bash
sendmail -v \
    -H "exec openssl s_client -quiet -tls1_3 -connect smtp.gmail.com:465 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error" \
    -au"sender@example.com" -ap"APP_PASSWORD" \
    -f"sender@example.com" recipient@example.com \
    < /tmp/test-email.txt
```

> [!CAUTION]
> **APP PASSWORD**: the above example exposes your app password to bash history, `ps`, and process lists. These are cleared at reboot though. Remember, this is **only** for testing purposes. A more secure approach uses input stuffing from a file eg. one-time setup with `nano /tmp/.smtp-pass` enter your password then save the file, secure the file with `chmod 600 /tmp/.smtp-pass` the `sendmail` command line would then be modified with `-ap$(cat /tmp/.smtp-pass)`.

#### 6.4.2. <a name='construct-the-test-email'></a>Construct the test email

Replace `sender@example.com`, `Sender Name`, `Recipient Name`, and `recipient@example.com` in the below:

```bash
cat << EOF > /tmp/test-email.txt
From: Sender Name <sender@example.com>
To: Recipient Name <recipient@example.com>
Subject: Test Email from Command Line - $(date '+%Y-%m-%d %H:%M:%S')
Date: $(date -R)
Message-ID: <$(date +%s).test@$(uname -n)>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: 7bit

Hello,

This is a test email created via command line.

✓ Created at: $(date '+%Y-%m-%d %H:%M:%S')
✓ Host: $(uname -n)
✓ Purpose: Testing email delivery

Best regards,
Command Line Tester

---
Test Email • $(date '+%Y-%m-%d %H:%M:%S')
EOF
```

> [!NOTE]
> **Message-ID**: Google may silently **not** deliver the test email if you reuse the same test message without updating the `Message-ID:` by recreating `/tmp/test-email.txt`.
> [!TIP]
> **EOF**: Using `EOF` without single quotes allows variable expansion. Typically you would use `'EOF'`, but we need the `date` and `hostnames` expanded, which is why we use `cat << EOF >`.

#### 6.4.3. <a name='how-the-commands-work'></a>How the Commands Work

The first command constructs a valid, raw RFC-compliant email body inside a temporary file (/tmp/test-email.txt) using dynamic variables to inject an accurate timestamp, a globally unique Message-ID, and local hostname metadata. The second command executes sendmail in verbose mode (-v), using a custom network handler string (-H) to launch OpenSSL instead of a standard socket connection. The OpenSSL utility wraps the session in TLS 1.3 encryption, cross-references Gmail's public certificates against the router's trusted system authorities (-CAfile), and immediately kills the transmission (-verify_return_error) if any intermediate certificate is missing or invalid. Once a secure channel is verified, sendmail submits the authentication flags (-au and -ap), passes the envelope routing details, and pipes the payload text directly into the authenticated SMTP session.

When executed, you should see something like this from your SSH session:

```bash
sendmail: send:'NOOP'
depth=2 C = US, O = Google Trust Services LLC, CN = GTS Root R1
verify return:1
depth=1 C = US, O = Google Trust Services, CN = WR2
verify return:1
depth=0 CN = smtp.gmail.com
verify return:1
sendmail: recv:'220 smtp.gmail.com ESMTP a-very-long-session-id-string - gsmtp'
sendmail: recv:'250 2.0.0 OK a-very-long-session-id-string - gsmtp'
sendmail: send:'EHLO sending-server'
sendmail: recv:'250-smtp.gmail.com at your service, [192.0.2.1]'
sendmail: recv:'250-SIZE 35882577'
sendmail: recv:'250-8BITMIME'
sendmail: recv:'250-AUTH LOGIN PLAIN XOAUTH2 PLAIN-CLIENTTOKEN OAUTHBEARER XOAUTH'
sendmail: recv:'250-ENHANCEDSTATUSCODES'
sendmail: recv:'250-PIPELINING'
sendmail: recv:'250-CHUNKING'
sendmail: recv:'250 SMTPUTF8'
sendmail: send:'AUTH LOGIN'
sendmail: recv:'334 VXNlcm5hbWU6'
sendmail: send:''                   <- username is not echoed to the screen
sendmail: recv:'334 UGFzc3dvcmQ6'
sendmail: send:''                   <- password is not echoed to the screen
sendmail: recv:'235 2.7.0 Accepted'
sendmail: send:'MAIL FROM:<sender@example.com>'
sendmail: recv:'250 2.1.0 OK a-very-long-session-id-string - gsmtp'
sendmail: send:'RCPT TO:<recipient@example.com>'
sendmail: recv:'250 2.1.5 OK a-very-long-session-id-string - gsmtp'
sendmail: send:'DATA'
sendmail: recv:'354 Go ahead a-very-long-session-id-string - gsmtp'
sendmail: send:'From: Sender Name <sender@example.com>'
sendmail: send:'To: Recipient Name <recipient@example.com>'
sendmail: send:'Subject: Test Email from Command Line - 2026-06-20 11:58:38'
sendmail: send:'Date: Sat, 20 Jun 2026 11:58:38 +1000'
sendmail: send:'Message-ID: <1781920718.test@host>'
sendmail: send:'MIME-Version: 1.0'
sendmail: send:'Content-Type: text/plain; charset=utf-8'
sendmail: send:'Content-Transfer-Encoding: 7bit'
sendmail: send:''
sendmail: send:'Hello,'
sendmail: send:''
sendmail: send:'This is a test email created via command line.'
sendmail: send:''
sendmail: send:'✓ Created at: 2026-06-20 11:58:38'
sendmail: send:'✓ Host: sending-server'
sendmail: send:'✓ Purpose: Testing email delivery'
sendmail: send:''
sendmail: send:'Best regards,'
sendmail: send:'Command Line Tester'
sendmail: send:''
sendmail: send:'---'
sendmail: send:'Test Email • 2026-06-20 11:58:38'
sendmail: send:'.'
sendmail: recv:'250 2.0.0 OK  1781920757 a-very-long-session-id-string - gsmtp'
sendmail: send:'QUIT'
read:errno=0
sendmail: recv:'221 2.0.0 closing connection a-very-long-session-id-string - gsmtp'
```

#### 6.4.4. <a name='certificate-information'></a>Certificate information

If you want to verify certificate use (and it's a _lot_ of information), use

```bash
openssl s_client -connect smtp.gmail.com:465 -tls1_3 \
    -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error \
    -showcerts < /dev/null
```

---

---

## 7. <a name='device-assignment'></a>Device assignment

Stock only. Merlin routes per device through VPN Director and the app does not offer this screen there.

> [!CAUTION]
> **The default-connection test drops every tunnel on the router for about a minute.** Changing the
> default runs `restart_default_wan`, which stops every WireGuard client, applies the change, then
> starts them again. Anything using any tunnel loses its connection for the duration, and a watchdog
> on an affected slot will see a real outage and may reconfigure. Do not run that part on a router
> anyone is relying on. **Assigning a device does none of this** and is safe to test at any time.

The list:

- every LAN device appears, offline ones dimmed and sorted last
- a device with no DHCP reservation carries a `DHCP` tag; one with a locally-administered address carries `random MAC`
- a device with no known address shows "connect this device once to assign it" and no picker
- the router itself, any AiMesh node, and guest-network devices never appear at all

Assigning:

- pick a slot for one device - the row marks itself changed, and APPLY and DISCARD CHANGES appear
- DISCARD CHANGES puts every row back and writes nothing to the router
- APPLY lists each change as `from -> to` and asks before doing anything
- afterwards `nvram get vpnc_dev_policy_list` holds `1><ip>>><index6>>` for that device, where the last number is the profile's **index 6**, not its slot
- `ip rule show` holds exactly **one** rule for that address at priority 100
- the app writes a line to the router's syslog for each reassignment - `tail /tmp/syslog.log` should name the device and where it moved

Reassigning, which is where this feature breaks:

- move the same device to a different slot, APPLY, then run `ip rule show` again
- there must still be exactly ONE rule for that address. Two means the app's stale-rule cleanup did not run, and the older rule will win silently
- the device's own traffic is the real test: check its public address from the device itself, not from the router - the router's own traffic is not policy-routed into the tunnel

Reservations:

- assign a device that has no reservation. `nvram get dhcp_staticlist` gains `<MAC>IP>>` and **nothing on the LAN drops** - the app applies the change with `restart_dnsmasq` and `restart_vpnc_dev_policy`, not the web interface's heavier call
- unassign it again. The policy record goes; the reservation stays. That is the firmware, and the app deliberately does not remove it

The default connection - read the warning above first:

- note what is up: `wg show interfaces`
- set the default to a tunnel and APPLY. Every tunnel stops and restarts
- `nvram get vpnc_default_wan` reads that profile's **index 6**. `0` means plain internet
- `ip rule show` gains a pair at priority 10000
- an **unassigned** device now leaves through that tunnel. Check from the device
- set it back to Internet and confirm the pair goes and unassigned traffic returns to the WAN

---

## 8. <a name='app-log'></a>App log

- one connection exists per session
- router log: one `dropbear ... Password auth succeeded` per app session, not per button press
- COPY the log - no countdown armed, and paste keeps its line breaks
- drop the connection mid-session (reboot the router, or `service restart_vpnc`) - app logs "connection dropped; reconnecting" and the action still completes

---

## 9. <a name='router-log'></a>Router log

- opens on the newest 32 KB of `/tmp/syslog.log`, scrolled to the bottom
- scrolling to the top loads the previous 32 KB and **keeps your place** - the text you were reading must not jump
- a partial first line is trimmed, so no page ever starts mid-word
- reaching the start of `syslog.log` continues into the rotated `syslog.log-1` if the router has one, and says so
- COPY takes everything loaded, not just the visible page, and no clipboard countdown is armed
- REFRESH returns to the newest page
- text selects across page boundaries in one run
- HOME leaves

---

## 10. <a name='settings'></a>Settings

- UNINSTALL asks twice, and the second prompt says what it is about to do
- afterwards, on the router:

```bash
ls -l /opt/etc/init.d/S50downloadmaster /opt/etc/init.d/S50asuslighttpd   # restored, or gone
cru l                                    # no watchdog entries
nvram show | grep cfg_pia_wg             # nothing
nvram show | grep -E 'wgc[1-9]_wd_'      # nothing
ls /jffs/cfg-pia-wg                       # gone
wg show interfaces                        # UNCHANGED - the tunnels are not ours to remove
```

- **run UNINSTALL a second time on the same router.** It must report that each script is not ours
  and delete nothing. A second run that removes the router's own `S50downloadmaster` is the 425 bug
  and the reason both scripts now carry an `auto-generated by cfg-pia-wg` header line
- DEL PIA CERT removes the cached PIA CA and the next reconfigure fetches it again
- FORGET ROUTER IP clears the saved address, and the next connect screen opens empty

---

## 11. <a name='about'></a>About

- COPY BUILD INFO - no clipboard countdown starts
- licences screen opens and does not bleed through the header
- DEL PIA CERT - credential prompt prefills IP and username, keyboard does not obscure it
- CREATE GITHUB ISSUE opens
- the deployed watchdog script version is shown, and is flagged when it is older than the app's copy
- the history line reads `Since <yyyy-mm-dd>: X successful & Y unsuccessful reconfigures`

---

## 12. <a name='credentials-and-exit'></a>Credentials and exit

- password manager fills PIA, SSH and SMTP logins (clear the field first - Android only offers on an empty one)
- Exit app and the back key both prompt, then wipe credentials and clipboard
- release build: screenshots blocked, task switcher obscured

---

## 13. <a name='firmware-coverage'></a>Firmware coverage

Repeat [Manage](#manage), [Watchdog](#watchdog) and [App log](#app-log) on the other firmware.

Two sections do not apply on Merlin at all: [Device assignment](#device-assignment) needs VPN
Fusion, and the parts of [Files deployed to the router](#files-deployed-to-the-router) about the
init scripts and the installed binaries are stock-only. Merlin has `/jffs/scripts/services-start`
and ships `jq` already.

---

## 14. <a name='examining-nvram-settings'></a>Examining nvram settings

I've used the below to examine WG on ASUS routers.

What the fields **mean** is in
[ARCHITECTURE.md, Router WireGuard NVRAM fields](ARCHITECTURE.md#router-wireguard-nvram-fields);
this section is only how to look at them. Two things about stock catch people out while testing,
and both are worth reading before you start interpreting output:

- **One profile is named by three different numbers** - its slot, its row in `vpnc_clientlist` (`vpnc_unit`), and its index 6. Which one a key wants depends on the key. `vpnc_default_wan` and `vpnc_dev_policy_list` both want index 6, so a value of `9` is perfectly normal on a five-slot router. See [The three numbers that name one profile](ARCHITECTURE.md#the-three-numbers-that-name-one-profile).
- **`nvram get` after a `service` call proves nothing.** `notify_rc` queues and returns immediately, so the value you read may be from before the call finished. Poll for the effect - the interface appearing in `wg show interfaces`, the key changing - rather than reading once.

Your best source of information is the system log with `tail -f /tmp/syslog.log`. This shows calls to the `service` command wrapper with commands like `service restart_vpnc`. `service` command parameters are not user accessible files.

- Manipulate/see WG configs:

    ```bash
    wg                  # get/set WG settings
    wg show interfaces  # show WG device interface names
    ```

- Poll and display active WG interfaces (substitute `usleep 500000` for `sleep 1` for half-second logging; syslogd can't show microseconds):

    ```bash
    i=1; while [ $i -le 60 ]; do echo "$(date +%H:%M:%S) - $(wg show interfaces)"; sleep 1; i=$((i+1)); done
    ```

- as above but for `vpnc_unit` whose content changes depending on which slot is being targetted:

    ```bash
    i=1; while [ $i -le 9999 ]; do echo "$(date +%H:%M:%S) - $(nvram get vpnc_unit)"; usleep 500000; i=$((i+1)); done
    ```

- Show all commands run when a VPN comes up/down or is created/deleted, half second resolution:

    ```bash
    i=1; while [ $i -le 30000 ]; do echo "$(date +%H:%M:%S) - $(ps | grep -E "vpnc|vpn|openvpn|wg" | grep -v grep | head -5)"; usleep 200000; i=$((i+1)); done
    ```

    > [!WARNING]
    > Very small `usleep` values may crash syslogd and/or your router.

- Display the contents of `vpnc_clientlist`:

    ```bash
    nvram get vpnc_clientlist | tr "<" "\n"
    ```

- Show the contents of all WG slot settings stored in nvram:

    ```bash
    nvram show | grep -E "wgc[1-9]_" | sort
    ```

- Clear all wgc5 values (the first WG VPN slot created in the WebUI is always named #5):

    ```bash
    for v in wgc5_addr wgc5_aips wgc5_alive wgc5_dns wgc5_enable wgc5_ep_addr wgc5_ep_addr_r wgc5_ep_port wgc5_mtu wgc5_nat wgc5_ppub wgc5_priv wgc5_psk; do nvram unset "$v"; done; nvram commit
    ```

- Show `vpnc_` (where N is 5-9) for WireGuard:

    ```bash
    nvram show | grep -E "vpnc([1-9]|1[0-6])_" | sort
    ```

- Show `vpnc_`, this includes `vpnc_unit` (the unit being acted on) and `vpnc_max_conn` the maximum number of concurrent VPNs:

    ```bash
    nvram show | grep -E "vpnc_" | sort
    ```

- Show the app's **global** settings - the PIA credentials the watchdog re-authenticates with, and the lifetime counters reported in the HISTORY section of every alert email:

    ```bash
    nvram show | grep -i cfg_pia | sort
    ```

    ```text
    cfg_pia_wg_password=...
    cfg_pia_wg_reconfig_fail=1     # lifetime failed reconfigures, all slots
    cfg_pia_wg_reconfig_ok=4       # lifetime successful reconfigures, all slots
    cfg_pia_wg_sdate=2026-09-01    # the day the app first configured this router
    cfg_pia_wg_user=...
    ```

    The three `sdate` / `reconfig_*` keys are seeded together by whichever of a watchdog deploy or a test email happens first, and committed once per alert rather than once per check - `nvram commit` writes flash.

- Two helper scripts do the above wholesale, and are the fastest way to start a clean test run:

    ```bash
    ./showall.sh    # every wgcN_, vpncN_, vpnc_ and cfg_pia_wg_ key, plus wg interfaces and cru
    ./clearall.sh   # unset all of them, including the counters, and commit
    ```

    Both live in `scripts/` in the repository; copy them to the router with `scp`.
