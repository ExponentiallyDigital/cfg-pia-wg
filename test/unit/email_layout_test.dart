// test/unit/email_layout_test.dart - the alert and test emails share one layout.
//
// The rebuild in 404 replaced a three-line email ("Watchdog wgc1 reconfiguration: FAILED (...)")
// with a sectioned one that answers the questions a user actually has when the alert arrives: how
// long was I down, was my traffic exposed, what do I do now. Two things make that fragile, and
// these tests hold both. First, the body is written twice - in Dart for the test email, in shell
// for the deployed script - so the wording is generated from shared constants and asserted to
// match. Second, a value that is missing at runtime (no addKey on a deploy run, no status file
// after a reboot) must drop its row rather than print an empty one.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';

import '../watchdog_test_utils.dart';

WatchdogConfig _cfg({int slot = 1, String subject = 'cfg-pia-wg alert'}) => WatchdogConfig(
      slotIndex: slot,
      primaryIp: '9.9.9.9',
      secondaryIp: '1.1.1.1',
      emailAlertsEnabled: true,
      emailFrom: 'from@example.com',
      emailTo: 'to@example.com',
      emailSubject: subject,
      smtpServer: 'smtp.example.com:465',
      smtpUsername: 'su',
      smtpPassword: 'sp',
    );

/// The marker-prefixed reply [kEmailFactsCommand] produces, in field order.
String _factsReply({
  String ddns = '',
  String lanHost = 'RT-AX88U-1A2B',
  String lanIp = '192.168.1.1',
  String model = 'RT-AX88U',
  String firmware = '3.0.0.4.388_24762',
  String time = '2026-09-05 14:32:53 AEST',
  String uptime = '15:11:29 up 19:21, load average: 2.55, 2.39, 2.36',
  String sdate = '2026-09-01',
  String ok = '4',
  String fail = '1',
  String desc = 'pia-aus_melbourne',
  String interval = '5',
}) =>
    [ddns, lanHost, lanIp, model, firmware, time, uptime, sdate, ok, fail, desc, interval].map((f) => '|$f').join('\n');

void main() {
  group('buildEmailBody', () {
    String body({List<String> whatToDo = const [], String? log}) => buildEmailBody(
          opening: 'Connectivity was lost and the tunnel has been rebuilt.',
          whatHappened: const ['Event: reconfigured successfully on attempt 2', 'Interval: 5 minutes'],
          router: const ['Name: r (192.168.1.1)', 'Time: 2026-09-05 14:32:53 AEST'],
          history: 'Since 2026-09-01 this router has recorded 4 successful and 1 failed reconfigurations.',
          whatToDo: whatToDo,
          routerLog: log,
        );

    test('sections run answer, action, evidence - and the failure-only ones stay out of a success', () {
      final s = body();
      expect(s.indexOf(kSectionWhatHappened), lessThan(s.indexOf(kSectionRouter)));
      expect(s.indexOf(kSectionRouter), lessThan(s.indexOf(kSectionHistory)));
      expect(s.indexOf(kSectionHistory), lessThan(s.indexOf(kEmailReviewLine)));
      expect(s, isNot(contains(kSectionWhatToDo)));
      expect(s, isNot(contains(kSectionRouterLog)));
    });

    test('a failure carries what to do and the evidence, in that order', () {
      final s = body(whatToDo: kEmailWhatToDo, log: '14:32:46 ERROR: failed to obtain PIA token\n');
      expect(s.indexOf(kSectionWhatHappened), lessThan(s.indexOf(kSectionWhatToDo)));
      expect(s.indexOf(kSectionWhatToDo), lessThan(s.indexOf(kSectionRouter)));
      expect(s.indexOf(kSectionHistory), lessThan(s.indexOf(kSectionRouterLog)));
      expect(s.indexOf(kSectionRouterLog), lessThan(s.indexOf(kEmailReviewLine)));
      expect(s, contains('4. Is your PIA billing account active?'));
    });

    test('every section is separated by a blank line', () {
      for (final heading in [kSectionRouter, kSectionHistory]) {
        expect(body(), contains('\n\n$heading\n'), reason: '$heading needs air above it');
      }
    });

    // The plan called for real line feeds: mailsend-go sends the file verbatim and the Merlin path
    // declares text/plain, so <br> and markdown links would reach the reader as literal characters.
    test('plain text only - no markup, and the store link is a bare URL', () {
      final s = body(whatToDo: kEmailWhatToDo);
      expect(s, isNot(contains('<br>')));
      expect(s, isNot(contains('](')));
      expect(s, contains(kPlayStoreUrl));
      expect(s.trimRight(), endsWith(kEmailSignOff.last));
    });

    test('an empty row is dropped rather than printed as a dangling label', () {
      final s = buildEmailBody(
        opening: 'o',
        whatHappened: const ['Event: x', '', 'Kill switch: ON'],
        router: const ['Name: r', ''],
        history: 'h',
      );
      expect(s, isNot(contains('\n\n\nKill switch')));
      expect(s, contains('Event: x\nKill switch: ON'));
    });
  });

  group('RouterEmailFacts', () {
    test('parses the marker-prefixed reply and prefers a DDNS name over the LAN hostname', () {
      final f = RouterEmailFacts.parse(_factsReply(ddns: 'my-router.asuscomm.com'));
      expect(f.name, 'my-router.asuscomm.com');
      expect(f.uptime, contains('load average'));
      expect(f.routerRows(1), contains('Name: my-router.asuscomm.com (192.168.1.1)'));
    });

    test('falls back hostname then LAN IP, and never prints "ip (ip)"', () {
      expect(RouterEmailFacts.parse(_factsReply()).name, 'RT-AX88U-1A2B');
      final bare = RouterEmailFacts.parse(_factsReply(lanHost: ''));
      expect(bare.name, '192.168.1.1');
      expect(bare.routerRows(1).first, 'Name: 192.168.1.1');
    });

    test('a slot with no region says so instead of showing an empty colon', () {
      final f = RouterEmailFacts.parse(_factsReply(desc: ''));
      expect(f.routerRows(2).last, 'Watchdog: region not yet set, configuration pending deployment');
      expect(RouterEmailFacts.parse(_factsReply()).routerRows(2).last, 'Watchdog: wgc2:pia-aus_melbourne');
    });

    // Read from NVRAM, never from the dialog being typed into, so an email cannot claim a schedule
    // that is not actually running.
    test('the interval row names the schedule, or says there is not one yet', () {
      expect(RouterEmailFacts.parse(_factsReply()).intervalRow, 'Interval: 5 minutes');
      expect(RouterEmailFacts.parse(_factsReply(interval: '')).intervalRow, kIntervalNotSet);
    });

    test('missing counters read as zero, not as blanks in a sentence', () {
      final f = RouterEmailFacts.parse(_factsReply(ok: '', fail: '', sdate: ''));
      expect(f.historyLine, 'Since today this router has recorded 0 successful and 0 failed reconfigurations.');
    });

    test('a short reply leaves the rest empty rather than throwing', () {
      final f = RouterEmailFacts.parse('|a\n|b');
      expect(f.name, 'a');
      expect(f.uptime, isEmpty);
      expect(f.routerRows(1), isNotEmpty);
    });
  });

  // The status file gained an epoch so the router can work out how long the tunnel was down; the
  // app reads the same file for the modal's "last successful ping".
  group('parseLastPing', () {
    test('reads the stamp that follows the epoch', () {
      expect(parseLastPing('1757046401 2026-09-05 14:26:41'), DateTime(2026, 9, 5, 14, 26, 41));
    });

    test('still reads a file written by an older build', () {
      expect(parseLastPing('2026-09-05 14:26:41'), DateTime(2026, 9, 5, 14, 26, 41));
    });

    test('empty or unparseable is null, not a crash', () {
      expect(parseLastPing(''), isNull);
      expect(parseLastPing('never'), isNull);
    });
  });

  group('the deployed script writes the same email', () {
    String script(RouterFirmware fw) => buildWatchdogScript(_cfg(), firmware: fw);

    // The anti-drift check. The script's wording is generated from the same constants
    // buildEmailBody uses, so a change to one cannot silently leave the other behind.
    test('headings, steps, review ask and sign-off come from the shared constants', () {
      for (final fw in RouterFirmware.values) {
        final s = script(fw);
        for (final heading in [kSectionWhatHappened, kSectionWhatToDo, kSectionRouter, kSectionHistory]) {
          expect(s, contains(heading), reason: '$fw is missing $heading');
        }
        expect(s, contains(kSectionRouterLog));
        for (final step in kEmailWhatToDo) {
          expect(s, contains(step), reason: '$fw is missing a WHAT TO DO step');
        }
        expect(s, contains(kPlayStoreUrl));
        for (final line in kEmailSignOff) {
          expect(s, contains(line));
        }
      }
    });

    test('the run mode is read before send_alert can shadow it', () {
      final s = script(RouterFirmware.merlin);
      expect(s, contains(r'RUNMODE="${1:-cron}"'));
      expect(s.indexOf(r'RUNMODE="${1:-cron}"'), lessThan(s.indexOf('send_alert() {')),
          reason: 'send_alert takes its own \$1, so the script argument has to be captured first');
    });

    test('a deploy run emails even when it finds the tunnel already up', () {
      final s = script(RouterFirmware.merlin);
      expect(s, contains('send_alert SUCCESS "watchdog deployed"'));
      // ...from NVRAM, because no addKey ran on that path.
      expect(s, contains(r'CONNVALUE="$(nvram get ${K}ep_addr):$(nvram get ${K}ep_port)$HSDESC"'));
      expect(s, contains('Watchdog deployed and the tunnel is up.'));
      expect(s, contains('Watchdog deployed but the tunnel could NOT be brought up.'));
    });

    test('a cron run says re-built, not deployed', () {
      final s = script(RouterFirmware.merlin);
      expect(s, contains('Connectivity was lost and the tunnel has been rebuilt.'));
      expect(s, contains('Connectivity was lost and the tunnel could NOT be rebuilt.'));
      expect(s, contains(r'send_alert SUCCESS "reconfigured successfully on attempt $CNT"'));
    });

    test('both counters are bumped on an outcome, and only on an outcome', () {
      final s = script(RouterFirmware.merlin);
      expect(s, contains('bump cfg_pia_wg_reconfig_ok'));
      expect(s, contains('bump cfg_pia_wg_reconfig_fail'));
      expect('bump cfg_pia_wg'.allMatches(s).length, 2, reason: 'a deploy that fixed nothing is neither');
      expect(s, contains('nvram commit'));
    });

    test('the kill switch has three states, and stock never claims to have one', () {
      final merlin = script(RouterFirmware.merlin);
      expect(merlin, contains('ON - traffic is blocked if the tunnel drops'));
      expect(merlin, contains('ON - no traffic left the router while it was down'));
      expect(merlin, contains('OFF - the kill switch is available but is not enabled'));

      final stock = script(RouterFirmware.stock);
      expect(stock, contains('not supported on this firmware'));
      expect(stock, isNot(contains('OFF - the kill switch is available')));
    });

    // The same fact reads wrong in the wrong tense: a failure alert saying "no traffic left the
    // router while it was down" describes an outage that has not finished.
    test('each state has a tense for up, recovered and still-down', () {
      for (final fw in RouterFirmware.values) {
        final s = script(fw);
        for (final v in ['KILLSW_UP=', 'KILLSW_FIXED=', 'KILLSW_DOWN=']) {
          expect(s, contains(v), reason: '\$fw is missing \$v');
        }
      }
      expect(script(RouterFirmware.merlin), contains('ON - traffic is blocked while the tunnel is down'));
      expect(script(RouterFirmware.stock), contains('traffic is reaching the internet without the VPN'));
      // A failure picks the still-down wording whether or not this run was a deploy.
      expect(script(RouterFirmware.merlin), contains('''if [ "\$STATUS" != "SUCCESS" ]; then
    KILLSW="\$KILLSW_DOWN"'''));
    });

    test('the status file leads with an epoch so an outage can be measured', () {
      final s = script(RouterFirmware.merlin);
      expect(s, contains(r'''date '+%s %Y-%m-%d %H:%M:%S' > "$STATUSFILE"'''));
      expect(s, isNot(contains(r'''date '+%Y-%m-%d %H:%M:%S' > "$STATUSFILE"''')));
      // Measured before the file is re-stamped, or the outage always reads zero.
      expect(s.indexOf(r'DOWNFOR="$(down_for)"'), lessThan(s.lastIndexOf(r'> "$STATUSFILE"')));
    });

    test('a missing status file says so rather than inventing a duration', () {
      expect(script(RouterFirmware.merlin), contains('unknown (no successful check since the router last rebooted)'));
    });

    test('a failure names the attempt and the schedule instead of a made-up retry time', () {
      expect(script(RouterFirmware.merlin),
          contains(r'ATTEMPTV="${CNT:-1} since the last success, retrying per schedule, $INTERVAL minutes"'));
    });

    test('the app version is stamped in when known and left out when not', () {
      expect(script(RouterFirmware.merlin), contains('APPVER=""'));
      appVersionLabel = 'v0.8.34 build 404';
      addTearDown(() => appVersionLabel = '');
      expect(buildWatchdogScript(_cfg(), firmware: RouterFirmware.merlin), contains('APPVER="v0.8.34 build 404"'));
    });
  });

  group('subject and headers', () {
    test('the slot and region are in the subject, so a mail client can thread by VPN', () {
      expect(buildMailSubject(_cfg(), status: 'FAILED', desc: 'pia-aus_melbourne'),
          'cfg-pia-wg alert: FAILED - wgc1:pia-aus_melbourne');
    });

    test('the user keeps their own prefix', () {
      expect(buildMailSubject(_cfg(subject: 'HOME VPN'), status: 'SUCCESS', desc: 'pia-x'),
          'HOME VPN: SUCCESS - wgc1:pia-x');
    });

    test('the Merlin script builds the same subject the app does', () {
      useMerlin();
      expect(buildWatchdogScript(_cfg(), firmware: RouterFirmware.merlin),
          contains(r'echo "Subject: $EMAIL_SUBJECT: $STATUS - $IFACE:$DESC"'));
    });
  });
}
