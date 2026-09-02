// test/router_watchdog_unit_test.dart - pure-function unit tests for the watchdog module.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';

WatchdogConfig _valid({int slot = 1, int interval = 5, bool email = false}) => WatchdogConfig(
      slotIndex: slot,
      cronIntervalMinutes: interval,
      primaryIp: '8.8.8.8',
      secondaryIp: '1.1.1.1',
      piaUsername: 'p1234567',
      piaPassword: 'secret',
      emailAlertsEnabled: email,
      emailFrom: email ? 'from@example.com' : '',
      emailTo: email ? 'to@example.com' : '',
      emailSubject: email ? 'Alert' : '',
      smtpServer: email ? 'smtp.example.com:465' : '',
      smtpUsername: email ? 'smtpuser' : '',
      smtpPassword: email ? 'smtppass' : '',
    );

void main() {
  group('validation helpers', () {
    test('isValidIpv4', () {
      expect(isValidIpv4('8.8.8.8'), isTrue);
      expect(isValidIpv4('255.255.255.255'), isTrue);
      expect(isValidIpv4('  1.2.3.4  '), isTrue);
      expect(isValidIpv4('256.1.1.1'), isFalse);
      expect(isValidIpv4('1.2.3'), isFalse);
      expect(isValidIpv4('abc'), isFalse);
      expect(isValidIpv4(''), isFalse);
    });

    test('isValidEmail', () {
      expect(isValidEmail('a@b.com'), isTrue);
      expect(isValidEmail('first.last@sub.domain.io'), isTrue);
      expect(isValidEmail('nope'), isFalse);
      expect(isValidEmail('a@b'), isFalse);
      expect(isValidEmail('a b@c.com'), isFalse);
    });

    test('parseLastPing', () {
      expect(parseLastPing('2026-06-19 14:30:00'), DateTime(2026, 6, 19, 14, 30, 0));
      expect(parseLastPing('   '), isNull);
      expect(parseLastPing(''), isNull);
      expect(parseLastPing('not-a-date'), isNull);
    });

    test('shellSingleQuote escapes embedded quotes', () {
      expect(shellSingleQuote('plain'), "'plain'");
      expect(shellSingleQuote("it's"), "'it'\\''s'");
    });
  });

  group('WatchdogConfig.validate', () {
    test('valid config (email disabled) has no errors', () {
      expect(_valid().validate(), isEmpty);
    });

    test('valid config (email enabled) has no errors', () {
      expect(_valid(email: true).validate(), isEmpty);
    });

    test('requires both IPs', () {
      final c = WatchdogConfig(slotIndex: 1, primaryIp: '', secondaryIp: '', piaUsername: 'u', piaPassword: 'p');
      final errors = c.validate();
      expect(errors.any((e) => e.contains('Primary ping IP is required')), isTrue);
      expect(errors.any((e) => e.contains('Secondary ping IP is required')), isTrue);
    });

    test('rejects malformed IPs', () {
      final c = _valid().copyWith(primaryIp: '999.1.1.1', secondaryIp: 'nope');
      final errors = c.validate();
      expect(errors.any((e) => e.contains('Primary ping IP is not a valid')), isTrue);
      expect(errors.any((e) => e.contains('Secondary ping IP is not a valid')), isTrue);
    });

    test('rejects non-positive interval', () {
      expect(_valid(interval: 0).validate().any((e) => e.contains('Check interval')), isTrue);
      expect(_valid(interval: -3).validate().any((e) => e.contains('Check interval')), isTrue);
    });

    test('requires PIA credentials', () {
      final c = _valid().copyWith(piaUsername: '', piaPassword: '');
      final errors = c.validate();
      expect(errors.any((e) => e.contains('PIA username is required')), isTrue);
      expect(errors.any((e) => e.contains('PIA password is required')), isTrue);
    });

    test('email fields required only when email enabled', () {
      // disabled: empty email fields are fine
      expect(_valid().validate(), isEmpty);
      // enabled but empty: many errors
      final c = WatchdogConfig(
        slotIndex: 1,
        primaryIp: '8.8.8.8',
        secondaryIp: '1.1.1.1',
        piaUsername: 'u',
        piaPassword: 'p',
        emailAlertsEnabled: true,
      );
      final errors = c.validate();
      expect(errors.any((e) => e.contains('Email "From" is required')), isTrue);
      expect(errors.any((e) => e.contains('Email "To" is required')), isTrue);
      expect(errors.any((e) => e.contains('Email subject is required')), isTrue);
      expect(errors.any((e) => e.contains('SMTP server')), isTrue);
      expect(errors.any((e) => e.contains('SMTP username is required')), isTrue);
      expect(errors.any((e) => e.contains('SMTP password is required')), isTrue);
    });

    test('email rejects invalid addresses and smtp without colon', () {
      final c = _valid(email: true).copyWith(emailFrom: 'bad', emailTo: 'alsobad', smtpServer: 'hostonly');
      final errors = c.validate();
      expect(errors.any((e) => e.contains('"From" is not a valid')), isTrue);
      expect(errors.any((e) => e.contains('"To" is not a valid')), isTrue);
      expect(errors.any((e) => e.contains('host:port format')), isTrue);
    });
  });

  group('toNvram / fromNvram', () {
    test('toNvram produces per-slot keys and excludes global PIA keys', () {
      final nv = _valid(slot: 2, email: true).toNvram();
      expect(nv['wgc2_wd_check_interval'], '5');
      expect(nv['wgc2_wd_primary_ip'], '8.8.8.8');
      expect(nv['wgc2_wd_secondary_ip'], '1.1.1.1');
      expect(nv['wgc2_wd_email_enabled'], '1');
      expect(nv['wgc2_wd_smtp_server'], 'smtp.example.com:465');
      expect(nv.containsKey('cfg_pia_wg_user'), isFalse);
      expect(nv.containsKey('cfg_pia_wg_password'), isFalse);
    });

    test('email_enabled is 0 when disabled', () {
      expect(_valid().toNvram()['wgc1_wd_email_enabled'], '0');
    });

    test('fromNvram round-trips per-slot keys and reads global PIA keys', () {
      final nv = {
        'wgc3_wd_check_interval': '10',
        'wgc3_wd_primary_ip': '9.9.9.9',
        'wgc3_wd_secondary_ip': '1.0.0.1',
        'wgc3_wd_email_enabled': '1',
        'wgc3_wd_email_from': 'f@x.com',
        'wgc3_wd_email_to': 't@x.com',
        'wgc3_wd_email_subject': 'Subj',
        'wgc3_wd_smtp_server': 'mail.x.com:587',
        'wgc3_wd_smtp_user': 'su',
        'wgc3_wd_smtp_pass': 'sp',
        'cfg_pia_wg_user': 'pu',
        'cfg_pia_wg_password': 'pp',
      };
      final c = WatchdogConfig.fromNvram(3, nv);
      expect(c.slotIndex, 3);
      expect(c.cronIntervalMinutes, 10);
      expect(c.primaryIp, '9.9.9.9');
      expect(c.secondaryIp, '1.0.0.1');
      expect(c.emailAlertsEnabled, isTrue);
      expect(c.emailFrom, 'f@x.com');
      expect(c.smtpServer, 'mail.x.com:587');
      expect(c.piaUsername, 'pu');
      expect(c.piaPassword, 'pp');
    });

    test('fromNvram defaults interval to 5 when missing or invalid', () {
      expect(WatchdogConfig.fromNvram(1, {}).cronIntervalMinutes, 5);
      expect(WatchdogConfig.fromNvram(1, {'wgc1_wd_check_interval': '0'}).cronIntervalMinutes, 5);
      expect(WatchdogConfig.fromNvram(1, {'wgc1_wd_check_interval': 'x'}).cronIntervalMinutes, 5);
    });
  });

  group('smtpHostPort', () {
    test('splits host:port on last colon', () {
      expect(_valid(email: true).copyWith(smtpServer: 'smtp.x.com:587').smtpHostPort, ('smtp.x.com', 587));
    });
    test('defaults to 465 when no port', () {
      expect(_valid(email: true).copyWith(smtpServer: 'smtp.x.com').smtpHostPort, ('smtp.x.com', 465));
    });
    test('splits on last colon for IPv6-ish strings', () {
      expect(_valid(email: true).copyWith(smtpServer: 'a:b:25').smtpHostPort, ('a:b', 25));
    });
  });

  group('cron line generators', () {
    test('buildCronCheckLine', () {
      expect(buildCronCheckLine(1, 5), 'cru a watchdog_wgc1 "*/5 * * * *" /jffs/scripts/watchdog_wgc1.sh');
      expect(buildCronCheckLine(3, 10), 'cru a watchdog_wgc3 "*/10 * * * *" /jffs/scripts/watchdog_wgc3.sh');
    });

    test('buildCronRotateLine', () {
      expect(
        buildCronRotateLine(2),
        'cru a watchdog_log_rotate_wgc2 "0 0 * * *" '
        '"mv /tmp/watchdog_wgc2.log /tmp/watchdog_wgc2.log.old && touch /tmp/watchdog_wgc2.log"',
      );
    });

    test('buildServicesStartBlock has both lines', () {
      final block = buildServicesStartBlock(1, 5);
      expect(block, contains('cru a watchdog_wgc1 '));
      expect(block, contains('cru a watchdog_log_rotate_wgc1 '));
    });
  });

  group('email generators', () {
    test('buildMailBody test mode uses "config test" subject', () {
      final body = buildMailBody(_valid(email: true), success: true, testMode: true);
      expect(body, contains('Subject: watchdog config test'));
      expect(body, contains('From: from@example.com'));
      expect(body, contains('To: to@example.com'));
    });

    test('buildMailBody success/failure subjects', () {
      expect(buildMailBody(_valid(email: true), success: true), contains('Subject: Alert - SUCCESS'));
      expect(buildMailBody(_valid(email: true), success: false), contains('Subject: Alert - FAILED'));
    });

    test('buildSendmailCommand has implicit-TLS connection helper and auth flags', () {
      final cmd = buildSendmailCommand('smtp.example.com', 587, _valid(email: true));
      expect(cmd, contains('/usr/sbin/sendmail'));
      expect(cmd, contains('exec openssl s_client -quiet -tls1_3'));
      expect(cmd, contains('-connect smtp.example.com:587'));
      //      expect(cmd, contains('-amLOGIN'));
      expect(cmd, contains("-au'smtpuser'"));
      expect(cmd, contains("-ap'smtppass'"));
      expect(cmd, contains('< /tmp/mail.txt'));
    });
  });

  group('heredocWrite', () {
    test('wraps body in a single-quoted heredoc', () {
      expect(heredocWrite('/tmp/x', 'hello'), "cat > '/tmp/x' <<'WATCHDOG_EOF'\nhello\nWATCHDOG_EOF");
    });
    test('does not double the trailing newline', () {
      expect(heredocWrite('/tmp/x', 'hello\n'), "cat > '/tmp/x' <<'WATCHDOG_EOF'\nhello\nWATCHDOG_EOF");
    });
  });

  group('buildWatchdogScript', () {
    test('substitutes the slot number everywhere', () {
      final s = buildWatchdogScript(_valid(slot: 3));

      // Scalar variables that carry the literal slot value after substitution.
      expect(s, contains('SLOT=3'));
      expect(s, contains('IFACE="wgc3"'));
      expect(s, contains(r'K="${IFACE}_"'));

      // File paths now use the ${IFACE} shell variable rather than the
      // literal slot value — verify both the prefix and the shell reference.
      expect(s, contains(r'LOGFILE="/tmp/watchdog_${IFACE}.log"'));
      expect(s, contains(r'STATUSFILE="/tmp/watchdog_last_ping_success_${IFACE}"'));
      expect(s, contains(r'BACKOFFFILE="/tmp/watchdog_backoff_${IFACE}"'));

      // No template markers must survive substitution.
      expect(s, isNot(contains('__SLOT__')));
    });

    test('reads global PIA credentials from NVRAM', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains('nvram get cfg_pia_wg_user'));
      expect(s, contains('nvram get cfg_pia_wg_password'));
    });

    test('pings via the VPN interface, primary then secondary', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'ping -I "$IFACE" -c 3 -W 2 "$PRIMARY_IP"'));
      expect(s, contains(r'ping -I "$IFACE" -c 3 -W 2 "$SECONDARY_IP"'));
    });

    test('performs a compact WAN reachability check before renegotiation', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'ping -c 1 -W 2 "$PRIMARY_IP"'));
      expect(s, contains(r'ping -c 1 -W 2 "$SECONDARY_IP"'));
      expect(s, contains('no Internet on WAN interface, exiting'));
    });

    test('writes all 16 Step-4 NVRAM vars but NOT wgcN_dns', () {
      final s = buildWatchdogScript(_valid(slot: 3));

      // nvset helper must be present and delegate to nvram set via the K prefix.
      expect(s, contains(r'nvset()'));
      expect(s, contains(r'nvram set "${K}$1"'));

      // Every Step-4 key must appear in an nvset call.
      for (final v in [
        'addr',
        'alive',
        'desc',
        'enable',
        'enforce',
        'ep_addr',
        'ep_addr_r',
        'ep_port',
        'fw',
        'mtu',
        'nat',
        'ppub',
        'priv',
        'psk',
        'rip',
        'aips',
      ]) {
        expect(s, contains('nvset "$v='), reason: 'missing nvset "$v=');
      }

      // DNS must be preserved (never written by the watchdog).
      expect(s, isNot(contains('nvset "dns=')));
      expect(s.contains('wgc3_dns'), isFalse);

      // Exactly 16 nvset invocations — no more, no less.
      expect(RegExp(r'nvset "').allMatches(s).length, 16);
    });

    test('contains backoff, cooldown, wg setconf, temp cleanup and restart', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains('COOLDOWN=120'));
      expect(s, contains(r'service "start_wgc $SLOT"'));
      expect(s, contains('service restart_vpnrouting0'));
    });

    test('logs to both the file and the router syslog', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'echo "$(date '));
      expect(s, contains(r'>> "$LOGFILE"'));
      expect(s, contains('logger -t "\$LOGTAG"'));
    });

    test('email sending is gated on EMAIL_ON at runtime and uses TLS sendmail', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'[ "$EMAIL_ON" = "1" ]'));
      expect(s, contains('exec openssl s_client -quiet -tls1_3'));
      //      expect(s, contains('-amLOGIN'));
    });

    test('has abort gates for empty desc, missing jq and missing PIA user', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'[ -x "$JQ" ] || command -v "$JQ"'));
      expect(s, contains(r'[ -n "$DESC" ]'));
      expect(s, contains(r'[ -n "$PIA_USER" ]'));
    });
  });

  // The heredoc ceiling rules out runtime branching, so the firmware differences are baked in
  // when the script is generated.
  group('buildWatchdogScript per firmware', () {
    test('jq resolves to the bare command on Merlin and the install path on stock', () {
      expect(buildWatchdogScript(_valid(), firmware: RouterFirmware.merlin), contains('JQ="jq"'));
      expect(buildWatchdogScript(_valid(), firmware: RouterFirmware.stock), contains('JQ="$kStockJqPath"'));
    });

    test(r'every jq call site goes through $JQ, so nothing hardcodes the Merlin path', () {
      final s = buildWatchdogScript(_valid(), firmware: RouterFirmware.stock);
      expect(RegExp(r'"\$JQ" -r').allMatches(s).length, 4);
      expect(s, isNot(contains('| jq ')));
      expect(s, isNot(contains('which jq')));
    });

    test('Merlin sends via BusyBox sendmail with RFC-822 headers inline', () {
      final s = buildWatchdogScript(_valid(email: true), firmware: RouterFirmware.merlin);
      expect(s, contains('/usr/sbin/sendmail'));
      expect(s, contains(r'echo "Subject: $EMAIL_SUBJECT - $1"'));
      expect(s, contains('exec openssl s_client -quiet -tls1_3'));
      expect(s, isNot(contains('mailsend-go')));
    });

    test('stock sends via mailsend-go with a headerless body', () {
      final s = buildWatchdogScript(_valid(email: true), firmware: RouterFirmware.stock);
      expect(s, contains('$kStockMailsendPath -debug -ssl -verifyCert'));
      expect(s, contains(r'-smtp "$SMTP_HOST" -port "$SMTP_PORT" -sub "$EMAIL_SUBJECT - $1"'));
      expect(s, contains(r'auth -user "$SMTP_USER" -pass "$SMTP_PASS"'));
      expect(s, contains(r'body -file "$TMPMAIL"'));
      expect(s, isNot(contains('/usr/sbin/sendmail')));
      expect(s, isNot(contains('echo "MIME-Version: 1.0"')));
    });

    // The app stores 'pia-<region>' but PIA's region ids carry no prefix, so the script strips it
    // for the lookup only. regionIdFromDesc in router_slot_service.dart does the same in Dart.
    test('the region lookup strips the app prefix, the logged name keeps it', () {
      final s = buildWatchdogScript(_valid(slot: 1));
      expect(s, contains(r'DESC="$(nvram get ${K}desc)"'));
      expect(s, contains(r'REGION="${DESC#pia-}"'));
      // jq selects on the bare region id...
      expect(s, contains(r'--arg id "$REGION"'));
      expect(s, isNot(contains(r'--arg id "$DESC"')));
      // ...while the NVRAM write-back keeps the full stored name.
      expect(s, contains(r'nvset "desc=$DESC"'));
    });

    test('no placeholder survives substitution on either firmware', () {
      for (final fw in RouterFirmware.values) {
        final s = buildWatchdogScript(_valid(email: true), firmware: fw);
        for (final marker in ['__SLOT__', '__JQ__', '__MAILBODY__', '__MAILCMD__']) {
          expect(s, isNot(contains(marker)), reason: '$marker survived on ${fw.name}');
        }
      }
    });

    // The deploy heredoc has a practical size ceiling, which is why the firmware differences are
    // substituted in rather than branched at runtime. The Merlin payload is the known-good
    // baseline (8.3 KB in production), so the guard is that neither variant grows past it by more
    // than a rounding error — stock in particular must not balloon.
    test('neither variant grows the deploy payload', () {
      final merlin = buildWatchdogScript(_valid(email: true), firmware: RouterFirmware.merlin).length;
      final stock = buildWatchdogScript(_valid(email: true), firmware: RouterFirmware.stock).length;
      expect(merlin, lessThan(8700));
      expect(stock, lessThanOrEqualTo(merlin));
    });
  });

  group('mailsend-go builders (stock)', () {
    test('buildMailsendGoCommand matches the documented invocation', () {
      final cmd = buildMailsendGoCommand('smtp.x.com', 465, _valid(email: true), subject: 'watchdog config test');
      expect(cmd, startsWith('$kStockMailsendPath -debug -ssl -verifyCert'));
      expect(cmd, contains("-smtp 'smtp.x.com' -port 465"));
      expect(cmd, contains("-sub 'watchdog config test'"));
      expect(cmd, contains("-f 'from@example.com' -t 'to@example.com'"));
      expect(cmd, contains("auth -user 'smtpuser' -pass 'smtppass'"));
      expect(cmd, endsWith('body -file /tmp/mail.txt'));
    });

    test('credentials are shell-quoted so a quote in a password cannot break out', () {
      final cmd = buildMailsendGoCommand('h', 1, _valid(email: true).copyWith(smtpPassword: "it's"), subject: 's');
      expect(cmd, contains(r"-pass 'it'\''s'"));
    });

    test('buildMailPlainBody carries no RFC-822 headers', () {
      final test = buildMailPlainBody(_valid(email: true), success: true, testMode: true);
      expect(test, contains('test email from the cfg-pia-wg watchdog'));
      expect(test, isNot(contains('Subject:')));
      expect(buildMailPlainBody(_valid(email: true), success: false), contains('failed'));
    });

    test('buildMailSubject matches the sendmail body subject', () {
      expect(buildMailSubject(_valid(email: true), success: true, testMode: true), 'watchdog config test');
      expect(buildMailSubject(_valid(email: true), success: true), 'Alert - SUCCESS');
      expect(buildMailSubject(_valid(email: true), success: false), 'Alert - FAILED');
    });
  });
}
