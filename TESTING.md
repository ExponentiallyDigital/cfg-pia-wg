# Notes on testing pia-wireguard-cfga

## Testing email send from SSH

If the watchdog feature is used, pia-wireguard-cfga employs the below commands to send emails. If you are having issues with sending email alerts you can test locally via SSH with the following examples.

As a fully blown `sendmail` is not available, pia-wireguard-cfga uses the built-in BusyBox `sendmail` applet paired with `openssl s_client` to establish a secure email connection. Email is sent with TLS 1.3 encryption, a verified CA bundle is used to ensure that the endpoint is actually who it should be, and enforces strict cryptographic handshake failures.

This ensures that emails are sent without exposing account credentials to eavesdropping or man-in-the-middle attacks.

### Construct the command line

Replace `sender@example.com`, `recipient@example.com`, and `APP_PASSWORD` in the below:

```bash
sendmail -v \
    -H "exec openssl s_client -quiet -tls1_3 -connect smtp.gmail.com:465 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error" \
    -au"sender@example.com" -ap"APP_PASSWORD" \
    -f"sender@example.com" recipient@example.com \
    < /tmp/test-email.txt
```

> [!CAUTION]
>
> **APP PASSWORD**: the above example exposes your app password to bash history, `ps`, and process lists. These are cleared at reboot though. Remember, this is **only** for testing purposes. A more secure approach uses input stuffing from a file eg. one-time setup with `nano /tmp/.smtp-pass` enter your password then save the file, secure the file with `chmod 600 /tmp/.smtp-pass` the `sendmail` command line would then be modified with `-ap$(cat /tmp/.smtp-pass)`.

### Construct the test email

Replace `sender@example.com`, ` Sender Name`, `Recipient Name`, and `recipient@example.com` in the below:

```bash
cat << EOF > /tmp/test-email.txt
From: Sender Name <sender@example.com>
To: Recipient Name <recipient@example.com>
Subject: Test Email from Command Line - $(date '+%Y-%m-%d %H:%M:%S')
Date: $(date -R)
Message-ID: <$(date +%s).test@$(hostname)>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: 7bit

Hello,

This is a test email created via command line.

✓ Created at: $(date '+%Y-%m-%d %H:%M:%S')
✓ Host: $(hostname)
✓ Purpose: Testing email delivery

Best regards,
Command Line Tester

---
Test Email • $(date '+%Y-%m-%d %H:%M:%S')
EOF
```

> [!NOTE]
>
> **Message-ID**: Google will likely silently non-deliver the test email if you reuse the same test message without updating the `Message-ID:` by recreating `/tmp/test-email.txt`.

> [!TIP]
>
> **EOF**: using `EOF` without single quotes allows variable expansion, typically you would use `'EOF'` but we need the `date` and `hostnames` expanded, which is why we use `cat << EOF >`.

### How the Commands Work

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
sendmail: send:'Message-ID: <1781920718.test@arcgate>'
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

### Certificate information

If you want to verify certificate use (and it's a _lot_ of information), use

```bash
openssl s_client -connect smtp.gmail.com:465 -tls1_3 \
    -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error \
    -showcerts < /dev/null
```

## Testing the watchdog feature

When you invoke `PUSH TO ROUTER` and if your roiuter is using Merlin firmware a new button appears

files deployed to your router:

- /jffs/scripts/services-start
- /jffs/scripts/watchdog_wgcN.sh
- /jffs/watchdog_backoff_wgcN
- /jffs/watchdog_last_ping_success_wgcN

Created on the router:

- /jffs/watchdog_wgcN.log

LOG -> /jffs/watchdog_wgcN.log and the router syslog

admin0909@arcgate:/tmp/home/root# cru l
_/1 _ \* \* _ check_wgc_ep #WGC_CHK_EP#
admin0909@arcgate:/tmp/home/root# crontab -l
_/1 \* \* \* \* check_wgc_ep #WGC_CHK_EP#
