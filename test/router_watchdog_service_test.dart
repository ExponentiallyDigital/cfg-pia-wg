// test/router_watchdog_service_test.dart - RouterWatchdog service tests over a fake SSH client.
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/router_watchdog.dart';

import 'watchdog_test_utils.dart';

WatchdogConfig cfg({int slot = 1, int interval = 5, bool email = false}) => WatchdogConfig(
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
  group('detection', () {
    test('isMerlinRouter true only when 3rd-party == merlin', () async {
      final merlin = RecordingSSHClient(responder: (c) => c.contains('3rd-party') ? 'merlin' : '');
      expect(await RouterWatchdog(merlin).isMerlinRouter(), isTrue);
      final stock = RecordingSSHClient(responder: (_) => 'asuswrt');
      expect(await RouterWatchdog(stock).isMerlinRouter(), isFalse);
    });

    test('isJqInstalled reflects which jq output', () async {
      expect(await RouterWatchdog(RecordingSSHClient(responder: (_) => '/opt/bin/jq')).isJqInstalled(), isTrue);
      expect(await RouterWatchdog(RecordingSSHClient(responder: (_) => '')).isJqInstalled(), isFalse);
    });
  });

  group('enableJffsScripts', () {
    test('no commit when already enabled', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '1' : '');
      await RouterWatchdog(c).enableJffsScripts();
      expect(c.ran('nvram set jffs2_scripts=1'), isFalse);
    });

    test('sets both flags and commits when not enabled', () async {
      final c = RecordingSSHClient(responder: (_) => '0');
      await RouterWatchdog(c).enableJffsScripts();
      expect(c.ran('nvram set jffs2_scripts=1'), isTrue);
      expect(c.ran('nvram set jffs2_on=1'), isTrue);
    });
  });

  group('deployWatchdogScripts', () {
    test('writes per-slot nvram, global PIA keys, the script and chmod, and logs to syslog', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).deployWatchdogScripts(cfg(slot: 1));
      expect(c.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
      expect(c.ran("nvram set wgc1_wd_secondary_ip='1.1.1.1'"), isTrue);
      expect(c.ran("nvram set pia_wg_cfga_user='p1234567'"), isTrue);
      expect(c.ran("nvram set pia_wg_cfga_password='secret'"), isTrue);
      expect(c.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isTrue);
      expect(c.ran('chmod +x /jffs/scripts/watchdog_wgc1.sh'), isTrue);
      expect(c.ran('logger -t pia-wg-cfga'), isTrue);
    });
  });

  group('startWatchdog', () {
    test('enables JFFS, deploys, adds both cron jobs and persists to services-start', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await RouterWatchdog(c).startWatchdog(cfg(slot: 1, interval: 5));
      expect(c.ran('nvram set jffs2_scripts=1'), isTrue);
      expect(c.ran('chmod +x /jffs/scripts/watchdog_wgc1.sh'), isTrue);
      expect(c.ran('cru a watchdog_wgc1 "*/5 * * * *"'), isTrue);
      expect(c.ran('cru a watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
      expect(c.ran('logger -t pia-wg-cfga'), isTrue);
    });
  });

  group('stopWatchdog', () {
    test('removes cron, script, services-start lines and all per-slot files, leaves JFFS', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).stopWatchdog(1);
      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('rm -f /jffs/scripts/watchdog_wgc1.sh'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
      expect(c.ran('/jffs/watchdog_wgc1.log'), isTrue);
      expect(c.ran('/jffs/watchdog_last_ping_success_wgc1'), isTrue);
      expect(c.ran('/jffs/watchdog_backoff_wgc1'), isTrue);
      expect(c.ran('logger -t pia-wg-cfga'), isTrue);
      // JFFS must NOT be disabled.
      expect(c.commands.any((cmd) => cmd.contains('jffs2_scripts=0') || cmd.contains('jffs2_on=0')), isFalse);
    });
  });

  group('getWatchdogStatus', () {
    test('enabled with a parsed last-ping timestamp', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('cru l')) return '1';
        if (cmd.contains('watchdog_last_ping_success_wgc1')) return '2026-06-19 14:30:00';
        return '';
      });
      final st = await RouterWatchdog(c).getWatchdogStatus(1);
      expect(st.isEnabled, isTrue);
      expect(st.lastSuccessfulPing, DateTime(2026, 6, 19, 14, 30, 0));
    });

    test('disabled with null last-ping', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('cru l') ? '0' : '');
      final st = await RouterWatchdog(c).getWatchdogStatus(1);
      expect(st.isEnabled, isFalse);
      expect(st.lastSuccessfulPing, isNull);
    });
  });

  test('getWatchdogLog returns cat output', () async {
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('watchdog_wgc1.log') ? 'line1\nline2' : '');
    expect(await RouterWatchdog(c).getWatchdogLog(1), 'line1\nline2');
  });

  test('loadConfig maps nvram keys to fields (per-slot + global PIA)', () async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('wgc1_wd_check_interval')) return '7';
      if (cmd.contains('wgc1_wd_primary_ip')) return '8.8.8.8';
      if (cmd.contains('wgc1_wd_secondary_ip')) return '1.1.1.1';
      if (cmd.contains('wgc1_wd_email_enabled')) return '1';
      if (cmd.contains('wgc1_wd_smtp_server')) return 'mail.x.com:465';
      if (cmd.contains('pia_wg_cfga_user')) return 'pu';
      if (cmd.contains('pia_wg_cfga_password')) return 'pp';
      return '';
    });
    final config = await RouterWatchdog(c).loadConfig(1);
    expect(config.cronIntervalMinutes, 7);
    expect(config.primaryIp, '8.8.8.8');
    expect(config.secondaryIp, '1.1.1.1');
    expect(config.emailAlertsEnabled, isTrue);
    expect(config.smtpServer, 'mail.x.com:465');
    expect(config.piaUsername, 'pu');
    expect(config.piaPassword, 'pp');
  });

  test('testEmail writes mail, sends via sendmail with "config test", cleans up, logs', () async {
    final c = RecordingSSHClient();
    await RouterWatchdog(c).testEmail(cfg(slot: 1, email: true));
    expect(c.ran("cat > '/tmp/mail.txt'"), isTrue);
    expect(c.ran('config test'), isTrue);
    expect(c.ran('/usr/sbin/sendmail'), isTrue);
    expect(c.ran('rm -f /tmp/mail.txt'), isTrue);
    expect(c.ran('logger -t pia-wg-cfga'), isTrue);
  });

  group('ping helpers', () {
    test('pingHostViaWan command shape and OK/FAIL parsing', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await RouterWatchdog(ok).pingHostViaWan('8.8.8.8'), isTrue);
      expect(ok.ran('ping -c 1 -W 2'), isTrue);
      final fail = RecordingSSHClient(responder: (_) => 'FAIL');
      expect(await RouterWatchdog(fail).pingHostViaWan('8.8.8.8'), isFalse);
    });

    test('pingHostViaVpn binds to the interface', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await RouterWatchdog(ok).pingHostViaVpn('8.8.8.8', 2), isTrue);
      expect(ok.ran('ping -I wgc2 -c 1 -W 2'), isTrue);
    });

    test('ping returns false when the SSH command throws', () async {
      final boom = RecordingSSHClient(throwOn: ['ping']);
      expect(await RouterWatchdog(boom).pingHostViaWan('8.8.8.8'), isFalse);
      expect(await RouterWatchdog(boom).pingHostViaVpn('8.8.8.8', 1), isFalse);
    });
  });

  test('a failing mutation logs an ERROR to syslog and the app log, then rethrows', () async {
    final c = RecordingSSHClient(throwOn: ['chmod']);
    final appLog = <String>[];
    final svc = RouterWatchdog(c, onLog: (m, {isError = false, isSuccess = false}) => appLog.add(m));
    await expectLater(svc.deployWatchdogScripts(cfg(slot: 1)), throwsA(isA<Exception>()));
    expect(c.commands.any((cmd) => cmd.contains('logger -t pia-wg-cfga') && cmd.contains('ERROR')), isTrue);
    expect(appLog.any((m) => m.contains('failed')), isTrue);
  });
}
