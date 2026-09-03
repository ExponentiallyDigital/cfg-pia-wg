// test/router_watchdog_service_test.dart - RouterWatchdog service tests over a fake SSH client.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/s50_template.dart';

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

    test(r'isJqInstalled probes the install path on stock, not $PATH', () async {
      useStock();
      final present = RecordingSSHClient(responder: (_) => '1');
      expect(await RouterWatchdog(present).isJqInstalled(), isTrue);
      expect(present.ran("[ -x '$kStockJqPath' ]"), isTrue);
      expect(present.ran('which jq'), isFalse);

      expect(await RouterWatchdog(RecordingSSHClient(responder: (_) => '0')).isJqInstalled(), isFalse);
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

  group('deployWatchdog', () {
    test('enables JFFS, writes nvram, deploys the script and both cron entries', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));
      expect(c.ran('nvram set jffs2_scripts=1'), isTrue);
      expect(c.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
      expect(c.ran("nvram set wgc1_wd_secondary_ip='1.1.1.1'"), isTrue);
      expect(c.ran("nvram set cfg_pia_wg_user='p1234567'"), isTrue);
      expect(c.ran("nvram set cfg_pia_wg_password='secret'"), isTrue);
      expect(c.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isTrue);
      expect(c.ran('chmod +x /jffs/scripts/watchdog_wgc1.sh'), isTrue);
      expect(c.ran('cru a watchdog_wgc1 "*/5 * * * *"'), isTrue);
      expect(c.ran('cru a watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
      expect(c.commands.any((cmd) => cmd == '/jffs/scripts/watchdog_wgc1.sh'), isTrue);
    });

    test('enables the VPN slot before deploying the watchdog scripts', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));
      final enableIndex = c.commands.indexWhere((cmd) => cmd.contains('wgc1_enable=1'));
      final deployIndex = c.commands.indexWhere((cmd) => cmd.contains("cat > '/jffs/scripts/watchdog_wgc1.sh'"));
      expect(enableIndex, isNot(-1));
      expect(deployIndex, isNot(-1));
      expect(enableIndex, lessThan(deployIndex));
    });

    // The completion line is the router-side record that the deploy finished, not just started.
    test('writes a completion message to the router syslog once deployed', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));
      expect(
        c.commands.any(
            (cmd) => cmd.contains('logger -t cfg-pia-wg') && cmd.contains('Watchdog deployed for wgc1 (check interval is 5m)')),
        isTrue,
      );
      // ...and it lands after the script has actually been written and run.
      final scriptIndex = c.commands.lastIndexWhere((cmd) => cmd == '/jffs/scripts/watchdog_wgc1.sh');
      final doneIndex = c.commands.indexWhere((cmd) => cmd.contains('Watchdog deployed for wgc1'));
      expect(scriptIndex, isNot(-1));
      expect(scriptIndex, lessThan(doneIndex));
    });
  });

  group('enableVpnSlot', () {
    test('activates the underlying VPN slot and restarts vpn routing', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).enableVpnSlot(1);
      expect(c.ran("nvram set wgc1_enable=1"), isTrue);
      expect(c.ran('service "start_wgc 1"; service restart_vpnrouting0'), isTrue);
    });
  });

  group('disableVpnSlot', () {
    test('clears the enable flag and stops the interface with the bare slot index', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).disableVpnSlot(3);
      expect(c.ran('nvram set wgc3_enable=0'), isTrue);
      expect(c.ran('service "stop_wgc 3"; service start_vpnrouting0'), isTrue);
    });
  });

  // Watchdogs used to be mutually exclusive: deploying one tore down every other slot. Two may
  // now run at once, so the deploy path must leave the others exactly as it found them - the cap
  // is a firmware limit, enforced by the UI before it gets this far.
  group('concurrent watchdogs on the deploy path', () {
    // Slot 2 already has a live watchdog and a running interface.
    RecordingSSHClient otherSlotActive() => RecordingSSHClient(
          responder: (cmd) {
            if (cmd.contains('jffs2')) return '0';
            if (cmd.contains('wg show interfaces')) return 'wgc2';
            if (cmd.contains('cru l') && cmd.contains('watchdog_wgc2')) return '1';
            if (cmd.contains('nvram get wgc2_enable')) return '1';
            return '';
          },
        );

    test('deployWatchdog leaves an existing watchdog on another slot running', () async {
      final c = otherSlotActive();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.ran('cru d watchdog_wgc2'), isFalse);
      expect(c.ran('nvram set wgc2_enable=0'), isFalse);
      expect(c.ran('rm -f /jffs/scripts/watchdog_wgc2.sh'), isFalse);
      expect(c.ran('nvram set wgc1_enable=1'), isTrue, reason: 'its own slot still comes up');
    });

    test('deployWatchdog never unsets the shared PIA credentials', () async {
      final c = otherSlotActive();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
      expect(c.ran("nvram set cfg_pia_wg_user='p1234567'"), isTrue);
    });

    test('leaves idle slots alone', () async {
      final c = otherSlotActive();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));
      for (final idle in [3, 4, 5]) {
        expect(c.ran('nvram set wgc${idle}_enable=0'), isFalse);
        expect(c.ran('cru d watchdog_wgc$idle'), isFalse);
      }
    });
  });

  group('disableWatchdog / enableWatchdog', () {
    test('DISABLE removes only the cron entries and the boot persistence', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).disableWatchdog(1);

      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue, reason: 'its boot lines go too');
      // Everything DELETE would remove has to survive: the settings, the script and the tunnel.
      expect(c.commands.any((cmd) => cmd.contains('nvram unset wgc1_wd_')), isFalse);
      expect(c.ran('rm -f /jffs/scripts/watchdog_wgc1.sh'), isFalse);
      expect(c.ran('nvram set wgc1_enable=0'), isFalse);
      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
    });

    test('ENABLE restores the schedule at the interval stored on the router', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc1_wd_check_interval') ? '15' : '');
      await RouterWatchdog(c).enableWatchdog(1);

      expect(c.commands.any((cmd) => cmd.contains('cru a watchdog_wgc1') && cmd.contains('*/15')), isTrue);
      expect(c.ran('cru a watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
    });

    test('ENABLE refuses when no settings were stored', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await expectLater(RouterWatchdog(c).enableWatchdog(1), throwsA(isA<Exception>()));
      expect(c.commands.any((cmd) => cmd.startsWith('cru a')), isFalse);
    });
  });

  group('stopWatchdog', () {
    // cfg_pia_wg_user / cfg_pia_wg_password are GLOBAL, shared by every watchdog script. Now that
    // two can run at once, clearing them while another is still scheduled would leave that one
    // unable to authenticate with PIA at its next renegotiation.
    test('keeps the shared PIA credentials while another watchdog is still scheduled', () async {
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('cru l') && cmd.contains('watchdog_wgc5') ? '1' : '',
      );
      await RouterWatchdog(c).stopWatchdog(1);

      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
      expect(c.ran('nvram unset cfg_pia_wg_password'), isFalse);
      expect(c.ran('nvram unset wgc1_wd_check_interval'), isTrue, reason: 'its own settings still go');
    });

    test('clears the shared PIA credentials when it is the last watchdog', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await RouterWatchdog(c).stopWatchdog(1);

      expect(c.ran('nvram unset cfg_pia_wg_user'), isTrue);
      expect(c.ran('nvram unset cfg_pia_wg_password'), isTrue);
    });

    test('removes cron, script, services-start lines and all per-slot files, leaves JFFS', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).stopWatchdog(1);
      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('rm -f /jffs/scripts/watchdog_wgc1.sh'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
      expect(c.ran('/tmp/watchdog_wgc1.log'), isTrue);
      expect(c.ran('/tmp/watchdog_last_ping_success_wgc1'), isTrue);
      expect(c.ran('/tmp/watchdog_backoff_wgc1'), isTrue);
      expect(c.ran('logger -t cfg-pia-wg'), isTrue);
      // JFFS must NOT be disabled.
      expect(c.commands.any((cmd) => cmd.contains('jffs2_scripts=0') || cmd.contains('jffs2_on=0')), isFalse);
    });

    test('brings the tunnel down with the bare slot index and clears the enable flag', () async {
      final c = RecordingSSHClient();
      await RouterWatchdog(c).stopWatchdog(1);
      expect(c.ran('nvram set wgc1_enable=0'), isTrue);
      expect(c.ran('service "stop_wgc 1"; service start_vpnrouting0'), isTrue);
      // The old form targeted "stop_wgc wgc1", which the service silently ignored.
      expect(c.ran('stop_wgc wgc1'), isFalse);
    });
  });

  test('waitForWatchdogReady resolves once the interface becomes present', () async {
    var attempts = 0;
    final c = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('cru l')) return '1';
        if (cmd.contains('nvram get wgc1_enable')) return '1';
        if (cmd.contains('wg show interfaces')) return attempts++ > 0 ? 'wgc1' : '';
        return '';
      },
    );
    final ready = await RouterWatchdog(c).waitForWatchdogReady(1, pollInterval: const Duration(milliseconds: 1), maxAttempts: 3);
    expect(ready, isTrue);
  });

  group('getWatchdogStatus', () {
    test('enabled with a parsed last-ping timestamp', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('cru l')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('watchdog_last_ping_success_wgc1')) return '2026-06-19 14:30:00';
          return '';
        },
      );
      final st = await RouterWatchdog(c).getWatchdogStatus(1);
      expect(st.isEnabled, isTrue);
      expect(st.lastSuccessfulPing, DateTime(2026, 6, 19, 14, 30, 0));
    });

    test('disabled when the interface is not present even if the cron exists', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('cru l')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('wg show interfaces')) return '';
          return '';
        },
      );
      final st = await RouterWatchdog(c).getWatchdogStatus(1);
      expect(st.isEnabled, isFalse);
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
    final c = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('wgc1_wd_check_interval')) return '7';
        if (cmd.contains('wgc1_wd_primary_ip')) return '8.8.8.8';
        if (cmd.contains('wgc1_wd_secondary_ip')) return '1.1.1.1';
        if (cmd.contains('wgc1_wd_email_enabled')) return '1';
        if (cmd.contains('wgc1_wd_smtp_server')) return 'mail.x.com:465';
        if (cmd.contains('cfg_pia_wg_user')) return 'pu';
        if (cmd.contains('cfg_pia_wg_password')) return 'pp';
        return '';
      },
    );
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
    expect(c.ran('logger -t cfg-pia-wg'), isTrue);
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

  // ── Stock firmware ────────────────────────────────────────────────────────────────
  group('stock deploy', () {
    // Stock answers '' to everything unless a test says otherwise; jffs2 reads are irrelevant here.
    RecordingSSHClient stockRouter({String s50 = ''}) => RecordingSSHClient(
          responder: (cmd) => cmd.startsWith("cat '$kS50Path'") ? s50 : '',
        );

    test('creates the script directory instead of setting the Merlin JFFS flags', () async {
      useStock();
      final c = stockRouter();
      await RouterWatchdog(c).enableJffsScripts();
      expect(c.ran('mkdir -p /jffs/scripts'), isTrue);
      expect(c.ran('nvram set jffs2_scripts=1'), isFalse);
      expect(c.ran('nvram set jffs2_on=1'), isFalse);
    });

    test('persists cron via S50downloadmaster and runs it immediately', () async {
      useStock();
      final c = stockRouter();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.ran("cat > '$kS50Path'"), isTrue);
      expect(c.ran("chmod +x '$kS50Path'"), isTrue);
      // Installs the entries now rather than waiting for the next boot.
      expect(c.ran("'$kS50Path' start"), isTrue);
      // Merlin's persistence file is never touched.
      expect(c.ran(kServicesStartPath), isFalse);
    });

    test('the deployed script carries both cru lines inside the replacement block', () async {
      useStock();
      final c = stockRouter();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), [buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      // The minimal template scaffolding must survive verbatim.
      expect(write, contains('#!/bin/sh'));
      expect(write, contains('BOOT_FLAG=/tmp/.dm_boot_delay_done'));
      expect(write, contains(r'[ "$1" = "start" ] || exit 0'));
    });

    test('redeploying replaces this slot\'s lines and keeps another slot\'s', () async {
      useStock();
      const otherSlot = 'cru a watchdog_wgc3 "*/9 * * * *" /jffs/scripts/watchdog_wgc3.sh';
      final existing = buildS50Script([otherSlot, buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      final c = stockRouter(s50: existing);
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 15));

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), [otherSlot, buildCronCheckLine(1, 15), buildCronRotateLine(1)]);
      expect(write, isNot(contains('*/5 * * * *')), reason: 'the stale interval must be gone');
    });

    test('the watchdog script points jq at the install path', () async {
      useStock();
      final c = stockRouter();
      await RouterWatchdog(c).deployWatchdog(cfg(slot: 1, interval: 5));

      final write = c.commands.firstWhere((cmd) => cmd.contains("cat > '/jffs/scripts/watchdog_wgc1.sh'"));
      expect(write, contains('JQ="$kStockJqPath"'));
      expect(write, contains(kStockMailsendPath));
      expect(write, isNot(contains('/usr/sbin/sendmail')));
    });
  });

  group('stock stopWatchdog', () {
    test('strips this slot from S50downloadmaster without shredding the template', () async {
      useStock();
      const otherSlot = 'cru a watchdog_wgc3 "*/9 * * * *" /jffs/scripts/watchdog_wgc3.sh';
      final existing = buildS50Script([otherSlot, buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith("cat '$kS50Path'") ? existing : '');
      await RouterWatchdog(c).stopWatchdog(1);

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), [otherSlot]);
      expect(write, contains('#!/bin/sh'));
      expect(write, contains('BOOT_FLAG=/tmp/.dm_boot_delay_done'));
      expect(c.ran("chmod 700 '$kS50Path'"), isTrue);
      expect(c.ran(kServicesStartPath), isFalse);
    });

    test('leaves the hijacked script in place with an empty block when nothing remains', () async {
      useStock();
      final existing = buildS50Script([buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith("cat '$kS50Path'") ? existing : '');
      await RouterWatchdog(c).stopWatchdog(1);

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), isEmpty);
      expect(write, contains('#!/bin/sh'));
      // Removing a stock init script outright would be worse than emptying its block.
      expect(c.ran("rm -f '$kS50Path'"), isFalse);
    });

    test('still removes the cron jobs, script and tmp files', () async {
      useStock();
      final c = RecordingSSHClient(responder: (_) => '');
      await RouterWatchdog(c).stopWatchdog(2);
      expect(c.ran('cru d watchdog_wgc2'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc2'), isTrue);
      expect(c.ran('rm -f /jffs/scripts/watchdog_wgc2.sh'), isTrue);
      expect(c.ran('/tmp/watchdog_backoff_wgc2'), isTrue);
      expect(c.ran('nvram set wgc2_enable=0'), isTrue);
    });
  });

  group('stock testEmail', () {
    test('sends via mailsend-go with a headerless body', () async {
      useStock();
      final c = RecordingSSHClient();
      await RouterWatchdog(c).testEmail(cfg(slot: 1, email: true));

      expect(c.ran("cat > '/tmp/mail.txt'"), isTrue);
      expect(c.ran('$kStockMailsendPath -debug -ssl -verifyCert'), isTrue);
      expect(c.ran("-sub 'watchdog config test'"), isTrue);
      expect(c.ran("auth -user 'smtpuser' -pass 'smtppass'"), isTrue);
      expect(c.ran('body -file /tmp/mail.txt'), isTrue);
      expect(c.ran('/usr/sbin/sendmail'), isFalse);
      // No RFC-822 headers in the body file — mailsend-go writes its own.
      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '/tmp/mail.txt'"));
      expect(write, isNot(contains('MIME-Version')));
      expect(c.ran('rm -f /tmp/mail.txt'), isTrue);
    });

    test('a failed send still runs the TCP and TLS diagnostics', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('EXITCODE') ? 'EXITCODE:1' : '');
      await RouterWatchdog(c).testEmail(cfg(slot: 1, email: true));
      expect(c.ran('nc -w 5 smtp.example.com 465'), isTrue);
      expect(c.commands.any((cmd) => cmd.contains('logger') && cmd.contains('Email FAILED')), isTrue);
    });
  });

  test('a failing mutation logs an ERROR to syslog and the app log, then rethrows', () async {
    final c = RecordingSSHClient(throwOn: ['chmod']);
    final appLog = <String>[];
    final svc = RouterWatchdog(c, onLog: (m, {isError = false, isSuccess = false}) => appLog.add(m));
    await expectLater(svc.deployWatchdog(cfg(slot: 1)), throwsA(isA<Exception>()));
    expect(c.commands.any((cmd) => cmd.contains('logger -t cfg-pia-wg') && cmd.contains('ERROR')), isTrue);
    expect(appLog.any((m) => m.contains('failed')), isTrue);
  });
}
