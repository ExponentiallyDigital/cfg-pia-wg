# Notes on testing cfg-pia-wg

- [1. Testing email send from SSH](#1-testing-email-send-from-ssh)
  - [1.1. Construct the command line](#11-construct-the-command-line)
  - [1.2. Construct the test email](#12-construct-the-test-email)
  - [1.3. How the Commands Work](#13-how-the-commands-work)
  - [1.4. Certificate information](#14-certificate-information)
- [2. Testing the watchdog feature](#2-testing-the-watchdog-feature)
  - [2.1. Checks](#21-checks)
    - [2.1.1. Invalidate the registration (the important one)](#211-invalidate-the-registration-the-important-one)
    - [2.1.2. What does NOT work: moving the endpoint](#212-what-does-not-work-moving-the-endpoint)
    - [2.1.3. Peer removed (the fast one)](#213-peer-removed-the-fast-one)
    - [2.1.4. Interface down](#214-interface-down)
    - [2.1.5. What a healthy check looks like](#215-what-a-healthy-check-looks-like)
    - [2.1.6. Backoff](#216-backoff)
    - [2.1.7. What no longer works](#217-what-no-longer-works)
- [3. Examining nvram settings](#3-examining-nvram-settings)
- [4. Full end-end-to-end manual test](#4-full-end-end-to-end-manual-test)

## 1. Testing email send from SSH

If the watchdog feature is used, cfg-pia-wg employs the below commands to send emails. If you are having issues with sending email alerts you can test locally via SSH with the following examples.

As a fully blown `sendmail` is not available, cfg-pia-wg uses the built-in BusyBox `sendmail` applet paired with `openssl s_client` to establish a secure email connection. Email is sent with TLS 1.3 encryption, a verified CA bundle is used to ensure that the endpoint is actually who it should be, and enforces strict cryptographic handshake failures.

This ensures that emails are sent without exposing account credentials to eavesdropping or man-in-the-middle attacks.

### 1.1. Construct the command line

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

### 1.2. Construct the test email

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

### 1.3. How the Commands Work

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

### 1.4. Certificate information

If you want to verify certificate use (and it's a _lot_ of information), use

```bash
openssl s_client -connect smtp.gmail.com:465 -tls1_3 \
    -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error \
    -showcerts < /dev/null
```

---

## 2. Testing the watchdog feature

Manual router tests:

### 2.1. Checks

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

5. Check `/tmp/watchdog_backoff_wgcN`

Force a reconfiguration by supplying invalid ping targets, then check that the file is created.

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

So a good test breaks the **crypto or the peer**, leaves the interface up, and touches neither the WAN nor NVRAM. Two things that look like good tests are not: disabling the interface in the WebUI exercises only the "interface down or absent" path and disturbs routing, and moving the peer's endpoint is undone within seconds by WireGuard's endpoint roaming (13.1.1).

> [!IMPORTANT]
> The clock runs from the **last handshake**, not from when you broke the tunnel. `wg show wgcN latest-handshakes` tells you exactly where you are; the watchdog reacts at the first check where that age exceeds 300 s, so worst case is 300 s **plus** one check interval. A check logging `Handshake 264s ago` after you broke it is the window working, not a failure - wait for the next one. Removing the peer (13.2) skips the wait entirely.

> [!CAUTION]
> Any LAN client policy-routed through the slot loses internet for the duration of the test - the tunnel really is dead. That is confirmation the test worked, but do not run it on a slot something depends on.

> [!WARNING]
> PIA rate-limits token requests. Since 405 the watchdog backs off on consecutive failures - 2, 4, 8, 16, 30, 60 minutes, capped at 90 - which is what keeps a broken tunnel from provoking it, but two failing watchdogs still climb their ladders independently. If `failed to obtain PIA token` starts appearing, stop and wait 15-30 minutes; the log carries the HTTP status, so `HTTP 403` confirms throttling rather than a fault. Test one slot at a time, and prefer a 5 m check interval over 1 m for reconfigure tests.

#### 2.1.1. Invalidate the registration (the important one)

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

#### 2.1.2. What does NOT work: moving the endpoint

```bash
# looks right, does nothing - do not use
wg set wgc1 peer "$(nvram get wgc1_ppub)" endpoint 203.0.113.1:1337
```

`wg` accepts it and shows the new endpoint, then puts the real one back within seconds and no reconfigure ever happens. That is **endpoint roaming**, a WireGuard feature: a peer's endpoint is updated automatically whenever an authenticated packet arrives from a different source address. The PIA server is still sending, so the endpoint follows it home. Anything that leaves the keys intact will be undone the same way.

#### 2.1.3. Peer removed (the fast one)

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

#### 2.1.4. Interface down

The one the WebUI gives you. Detected immediately - no 300 s wait, because the script tests `ifconfig` before the handshake:

```bash
ifconfig wgc1 down
```

```text
2026-09-04 16:45:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 16:45:00 Interface wgc1 is down or absent
2026-09-04 16:45:00 Connectivity lost; reconfiguring (attempt #1)
```

#### 2.1.5. What a healthy check looks like

For contrast - this is every minute on a working tunnel, and no reconfigure should follow:

```text
2026-09-04 15:48:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 15:48:00 Handshake 60s ago
```

#### 2.1.6. Backoff

The wait before the next reconfigure attempt grows with each **consecutive failed attempt** and resets the moment one succeeds:

| Consecutive failures | 1 | 2 | 3 | 4 | 5 | 6 | 7+ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Wait | 2 min | 4 min | 8 min | 16 min | 30 min | 60 min | 90 min (cap) |

A check that arrives inside the wait is turned away and says so:

```text
2026-09-04 16:41:00 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-04 16:41:00 Backing off after 3 failed attempts: 45s of 480s elapsed
```

Check `/tmp/watchdog_backoff_wgc1` is created and holds the attempt count and timestamp. The count rises **only when an attempt is actually made** - a run the backoff turned away must leave it alone, or the ladder would climb faster on a 1 m interval than on a 5 m one. To watch a rung without waiting for it, write the count by hand and re-run the script:

```bash
printf '%s\n%s\n' 5 "$(( $(date +%s) - 5 ))" > /tmp/watchdog_backoff_wgc1
/jffs/cfg-pia-wg/watchdog_wgc1.sh          # expect "Backing off after 5 failed attempts: 5s of 1800s elapsed"
```

#### 2.1.7. What no longer works

> [!WARNING]
> Setting the ping targets to unroutable addresses does **not** force a reconfigure. Those addresses are also the WAN reachability check, so the script concludes the router has no internet and exits 0 without alerting. Per [RFC 5737](https://www.iana.org/go/rfc5737), `192.0.2.0/24`, `198.51.100.0/24` and `203.0.113.0/24` never respond, which is what makes them tempting here - but see 13.1.1 for why pointing the tunnel at one does not work either.

```bash
# DO NOT use this to force a reconfigure - the script sees "no Internet" and exits
nvram set wgc1_wd_primary_ip=192.0.2.1; nvram set wgc1_wd_secondary_ip=198.51.100.1

# valid entries
nvram set wgc1_wd_primary_ip=8.8.8.8; nvram set wgc1_wd_secondary_ip=1.1.1.1
```

14. Apply a new config to a blank slot
    <br>
15. Overwrite an existing slot with a different region's config
    <br>
16. Overwrite an existing slot with the same region's config
    <br>
17. check all NVRAM settings are cleared on script & watchdog disable

```bash
nvram show | grep pia_wg | sort
nvram show | grep qgc | sort
```

18. Files deployed to router

Check these get created/cleaned up

```bash
/jffs/scripts/services-start              # Merlin boot persistence
/opt/etc/init.d/S50downloadmaster         # stock boot persistence (replacement block only)
/jffs/cfg-pia-wg/watchdog_wgcN.sh
/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt      # cached PIA CA, shared by all slots
/tmp/watchdog_wgcN.log
/tmp/watchdog_last_ping_success_wgcN
/tmp/watchdog_backoff_wgcN
```

Where `N` is the slot number

---

## 3. Examining nvram settings

I've used the below to examine WG on ASUS routers.

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

 ---

## 4. Full end-end-to-end manual test

  1. Clear all configs & nvram, reboot router
  2. Home screen
     1. all five buttons navigate; HOME and the back key return here - stock OK
     2. "how to use this app" opens the README section - stock OK
     3. "add a Play Store app review" opens the Play listing - stock OK
     4. PAYPAL and PATREON open - stock OK
  3. About
     1. COPY BUILD INFO - no clipboard countdown starts - stock OK
     2. licences screen opens and does not bleed through the header - stock OK
     3. DEL PIA CERT - credential prompt prefills IP and username, keyboard does not obscure it - stock OK
     4. CREATE GITHUB ISSUE opens - stock OK
  4. Standalone (generate)
     1. create a config and apply manually
     2. heading reads "GENERATED CONFIG: pia-region_name"
     3. clear the DNS field, leave the screen, return - Quad9 defaults are back
     4. COPY - 60s countdown, then the clipboard empties with no "cleared" popup
     5. SHARE and SAVE
  5. Manage
     1. create wgc1-5
     2. enable wgc1 & 5
     3. edit wgcN
     4. ACTIVE badge on every slot whose interface is up, not just one
     5. DISABLE leaves `wg show interfaces` empty
     6. stock: a third concurrent enable is refused with the VPN-limit dialog
     7. DELETE prompt names the VPN being deleted
  6. Watchdog
     1. Create wgc1 & wgc5 - check test email
     2. Disable wgc5, create wgc4, enable wgc4 - check nvram and tunnel up
     3. force a reconfigure with, check email alerting
        1. `wg set wgc1 peer "$(nvram get wgc1_ppub)" remove`
        2. `/jffs/cfg-pia-wg/watchdog_wgc1.sh`
     4. Check emails
        1. deploy email says "watchdog deployed", subject SUCCESS, sent even though nothing was wrong
        2. reconfigure email: outage duration, kill-switch line, new server and latency
        3. failure email: WHAT TO DO, attempt count, last 10 router-log lines
        4. HISTORY counters climb; `cfg_pia_wg_sdate` is set once and not rewritten
        5. subject threads by slot: `cfg-pia-wg alert: SUCCESS - wgc1:pia-<region>`
     5. DISABLE shows the PAUSED badge; ENABLE restores the same interval
     6. keyboard does not obscure the configure dialog's fields
     7. backoff: leave it failing and watch the log - "Backing off after N failed attempts", waits growing 2, 4, 8, 16, 30, 60, 90 min
  7. App log
     1. one connection exists per session
     2. router log: one `dropbear ... Password auth succeeded` per app session, not per button press
     3. COPY the log - no countdown armed, and paste keeps its line breaks
     4. drop the connection mid-session (reboot the router, or `service restart_vpnc`) - app logs "connection dropped; reconnecting" and the action still completes
  8. Credentials and exit
     1. password manager fills PIA, SSH and SMTP logins (clear the field first - Android only offers on an empty one)
     2. Exit app and the back key both prompt, then wipe credentials and clipboard
     3. release build: screenshots blocked, task switcher obscured
  9. Firmware coverage
     1. repeat 5-7 on the other firmware (stock / Merlin)
