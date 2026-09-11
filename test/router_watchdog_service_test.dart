// test/router_watchdog_service_test.dart - RouterWatchdog service tests over a fake SSH client.
import 'package:dartssh2/dartssh2.dart';
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

/// A watchdog service whose interface-up poll does not wait on real time.
///
/// 409 made enableVpnSlot wait for `wgcN` to appear before the deploy runs the script - on a real
/// router `notify_rc` queues the service call, so the interface is not up when it returns. The
/// fakes here mostly never bring one up, so the production 2s x 5 would add half a minute to this
/// file alone.
RouterWatchdog _wd(SSHClient c, {void Function(String, {bool isError, bool isSuccess, bool isWarning})? onLog}) =>
    RouterWatchdog(c, onLog: onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: 3);

void main() {
  group('detection', () {
    test('isMerlinRouter true only when 3rd-party == merlin', () async {
      final merlin = RecordingSSHClient(responder: (c) => c.contains('3rd-party') ? 'merlin' : '');
      expect(await _wd(merlin).isMerlinRouter(), isTrue);
      final stock = RecordingSSHClient(responder: (_) => 'asuswrt');
      expect(await _wd(stock).isMerlinRouter(), isFalse);
    });

    test('isJqInstalled reflects which jq output', () async {
      expect(await _wd(RecordingSSHClient(responder: (_) => '/opt/bin/jq')).isJqInstalled(), isTrue);
      expect(await _wd(RecordingSSHClient(responder: (_) => '')).isJqInstalled(), isFalse);
    });

    test(r'isJqInstalled probes the install path on stock, not $PATH', () async {
      useStock();
      final present = RecordingSSHClient(responder: (_) => '1');
      expect(await _wd(present).isJqInstalled(), isTrue);
      expect(present.ran("[ -x '$kStockJqPath' ]"), isTrue);
      expect(present.ran('which jq'), isFalse);

      expect(await _wd(RecordingSSHClient(responder: (_) => '0')).isJqInstalled(), isFalse);
    });
  });

  group('enableJffsScripts', () {
    test('no commit when already enabled', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '1' : '');
      await _wd(c).enableJffsScripts();
      expect(c.ran('nvram set jffs2_scripts=1'), isFalse);
    });

    test('sets both flags and commits when not enabled', () async {
      final c = RecordingSSHClient(responder: (_) => '0');
      await _wd(c).enableJffsScripts();
      expect(c.ran('nvram set jffs2_scripts=1'), isTrue);
      expect(c.ran('nvram set jffs2_on=1'), isTrue);
    });
  });

  // Reported: with a watchdog active on stock, every button in both slot modals greyed out except
  // CREATE. fetchSlots reads the region name from vpnc_clientlist there, and the watchdog deploy
  // path only ever wrote wgcN_desc - so the slot read back as unconfigured.
  group('deployWatchdog writes the stock profile row', () {
    // A stock router that remembers what was written to vpnc_clientlist: the deploy reads the row
    // back to resolve vpnc_unit, so a fake that forgets would fail for the wrong reason.
    RecordingSSHClient stockClient() {
      var list = '';
      return RecordingSSHClient(responder: (cmd) {
        if (cmd.startsWith('nvram set vpnc_clientlist=')) {
          list = cmd.substring(cmd.indexOf('=') + 1).replaceAll("'", '');
          return '';
        }
        if (cmd.contains('nvram get vpnc_clientlist')) return list;
        if (cmd.contains('jffs2')) return '0';
        return '';
      });
    }

    test('adds the description to vpnc_clientlist on stock', () async {
      useStock();
      final c = stockClient();
      await _wd(c).deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne');

      final write = c.commands.firstWhere((cmd) => cmd.startsWith('nvram set vpnc_clientlist='), orElse: () => '');
      expect(write, isNotEmpty, reason: 'no clientlist row was written');
      expect(write, contains('pia-aus_melbourne'));
      expect(c.ran("nvram set wgc1_desc='pia-aus_melbourne'"), isTrue, reason: 'the per-slot key still gets it');
    });

    test('marks the profile active when the slot is enabled', () async {
      useStock();
      final c = stockClient();
      await _wd(c).enableVpnSlot(1);

      expect(c.commands.any((cmd) => cmd.startsWith('nvram set vpnc_clientlist=')), isTrue);
      // And it starts the tunnel the stock way, not Merlin's.
      expect(c.ran('service restart_vpnc'), isTrue);
      expect(c.ran('start_wgc'), isFalse);
    });

    test('stops a stock tunnel with stop_vpnc, not stop_wgc', () async {
      useStock();
      final c = stockClient();
      await _wd(c).deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne'); // creates the row
      c.commands.clear();
      await _wd(c).disableVpnSlot(1);

      expect(c.ran('service stop_vpnc'), isTrue);
      expect(c.ran('stop_wgc'), isFalse);
    });

    test('leaves vpnc_clientlist alone on Merlin, which has no such list', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await _wd(c).deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne');

      expect(c.commands.any((cmd) => cmd.contains('vpnc_clientlist')), isFalse);
      expect(c.ran("nvram set wgc1_desc='pia-aus_melbourne'"), isTrue);
    });
  });

  // Reported: every deploy died with "SSH connection closed" straight after the slot was enabled.
  // The script had grown to 9055 bytes as a single `cat > ... <<EOF` command, and dropbear refuses
  // an exec request over MAX_CMD_LEN (9000) - it does not truncate, it drops the connection.
  group('heredoc chunking', () {
    test('splits a long body into commands that stay well under dropbear s limit', () {
      final body = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
      final cmds = heredocWriteCommands('/tmp/big.sh', body);

      expect(cmds.length, greaterThan(1));
      for (final cmd in cmds) {
        expect(cmd.length, lessThan(kMaxSshCommandBytes), reason: 'one command must never reach the limit');
      }
      // First truncates, the rest append - otherwise each chunk would wipe the last.
      expect(cmds.first, startsWith("cat > '/tmp/big.sh'"));
      for (final cmd in cmds.skip(1)) {
        expect(cmd, startsWith("cat >> '/tmp/big.sh'"));
      }
    });

    test('the chunks reassemble into exactly the original body', () {
      final body = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
      final written = heredocWriteCommands('/tmp/big.sh', body)
          .map((cmd) => cmd.substring(cmd.indexOf('\n') + 1, cmd.length - "WATCHDOG_EOF\n".length))
          .join();
      expect(written, '$body\n');
    });

    test('a short body is still a single command', () {
      expect(heredocWriteCommands('/tmp/x', 'hello').length, 1);
    });

    test('the real watchdog script needs more than one chunk', () {
      final cmds = heredocWriteCommands('/tmp/w.sh', buildWatchdogScript(cfg(slot: 1)));
      expect(cmds.length, greaterThan(1), reason: 'it is ~9 KB - one command would exceed MAX_CMD_LEN');
    });
  });

  // Reported: cru entries existed, the UI said ACTIVE, and the script was not on the router at all.
  group('deploy verifies the script landed', () {
    test('throws when the file is missing or short, naming both sizes', () async {
      final c = RecordingSSHClient(
        responder: (cmd) => cmd.contains('wc -c') ? '12' : '', // a truncated write
      );
      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1)),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('12 bytes'))),
      );
      // And it stops there rather than scheduling a script that is not there.
      expect(c.ran('cru a watchdog_wgc1'), isFalse);
    });

    test('a good write is confirmed and the deploy carries on', () async {
      final c = RecordingSSHClient();
      await _wd(c).deployWatchdog(cfg(slot: 1));
      expect(c.ran('cru a watchdog_wgc1'), isTrue);
      expect(c.ran("wc -c < '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);
    });
  });

  // Every file the app puts on the router goes through the same writer, so neither can grow past
  // dropbear's limit unnoticed or be left half-written.
  test('the S50 boot script is written in chunks and verified too', () async {
    useStock();
    // Stock resolves vpnc_unit from the clientlist row, so the fake has to read back what it wrote.
    var list = '';
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.startsWith('nvram set vpnc_clientlist=')) {
        list = cmd.substring(cmd.indexOf('=') + 1).replaceAll("'", '');
        return '';
      }
      if (cmd.contains('nvram get vpnc_clientlist')) return list;
      return '';
    });
    await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

    final writes = c.commands.where((cmd) => cmd.contains("'$kS50Path' <<'WATCHDOG_EOF'")).toList();
    expect(writes, isNotEmpty);
    for (final w in writes) {
      expect(w.length, lessThan(kMaxSshCommandBytes));
    }
    expect(c.ran("wc -c < '$kS50Path'"), isTrue, reason: 'the write has to be proved, not assumed');
  });

  // The app takes over two init scripts the firmware already runs. Both have to be recoverable,
  // or a user cannot put their router back the way they found it - and the uninstall feature has
  // nothing to rename.
  group('boot scripts the app takes over', () {
    /// A stock router that answers the clientlist read-back and records everything.
    RecordingSSHClient stock() {
      var list = '';
      return RecordingSSHClient(responder: (cmd) {
        if (cmd.startsWith('nvram set vpnc_clientlist=')) {
          list = cmd.substring(cmd.indexOf('=') + 1).replaceAll("'", '');
          return '';
        }
        if (cmd.contains('nvram get vpnc_clientlist')) return list;
        return '';
      });
    }

    test('both originals are copied to .old before anything is written over them', () async {
      useStock();
      final c = stock();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      for (final path in [kS50Path, kS50LighttpdPath]) {
        final backup = c.commands.firstWhere((x) => x.contains("cp -p '$path'"), orElse: () => '');
        expect(backup, contains(originalScriptBackupPath(path)), reason: 'no backup taken of $path');
        // Guarded: an absent file has nothing to preserve, an existing .old must not be clobbered
        // by a second deploy, and the app's OWN copy must never be saved as though it were the
        // router's - if .old is missing by then the original is already gone, and a false backup
        // is worse than none.
        expect(backup, contains("[ -f '$path' ]"));
        expect(backup, contains("[ ! -f '${originalScriptBackupPath(path)}' ]"));
        expect(backup, contains('grep -q'));
        expect(c.commands.indexOf(backup), lessThan(c.commands.indexWhere((x) => x.contains("'$path' <<"))),
            reason: 'the backup has to precede the write');
      }
    });

    test('S50asuslighttpd is replaced by the stub, mode 700', () async {
      useStock();
      final c = stock();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      final write = c.commands.where((x) => x.contains("'$kS50LighttpdPath' <<")).join('\n');
      expect(write, contains('exit 0'));
      expect(write, contains('auto-generated by cfg-pia-wg'));
      expect(c.ran("chmod 700 '$kS50LighttpdPath'"), isTrue);
      expect(c.ran("wc -c < '$kS50LighttpdPath'"), isTrue, reason: 'the write has to be proved');
    });

    test('Merlin is left alone - it has services-start and neither of these scripts', () async {
      useMerlin();
      final c = stock();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.commands.any((x) => x.contains(kS50LighttpdPath)), isFalse);
      expect(c.commands.any((x) => x.contains('cp -p')), isFalse);
    });
  });

  // The app said "wgc1 enabled" one second after `service restart_vpnc`, because it caught the
  // interface during the restart - and then ran the deploy script against a tunnel on its way back
  // down. One sighting is not evidence.
  group('an interface has to STAY up', () {
    test('a single sighting that does not persist is not called up', () async {
      useMerlin();
      var reads = 0;
      // Up on the first look, gone on every look after it - a restart caught mid-flight.
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('ip -o link show up')) return (++reads == 1) ? 'wgc1' : 'wgs1 wgc5';
        return '';
      });
      await _wd(c).enableVpnSlot(1);

      expect(c.commands.where((x) => x.contains('logger')).join('\n'), contains('Enabled'));
      expect(reads, greaterThan(1), reason: 'it must look more than once');
    });

    test('two consecutive sightings are', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('ip -o link show up') ? 'wgc1' : '');
      await _wd(c).enableVpnSlot(1);
      expect(c.commands.where((x) => x.contains('ip -o link show up')).length, greaterThanOrEqualTo(2));
    });
  });

  group('log housekeeping and uninstall', () {
    // Truncated, not deleted: the script appends and never creates, so removing the file would
    // lose every line until the next reboot.
    test('clearing a watchdog log truncates the file rather than removing it', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).clearWatchdogLog(1);

      expect(c.commands.any((x) => x.contains('rm ') && x.contains('watchdog_wgc1.log')), isFalse);
      expect(c.commands.any((x) => x.contains('> /tmp/watchdog_wgc1.log')), isTrue);
      expect(c.commands.any((x) => x.contains('logger')), isTrue, reason: 'the router log records it');
    });

    test('uninstall restores what it can and reports what it did', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('.old') ? 'RESTORED' : 'REMOVED');
      final done = await _wd(c).uninstallFromRouter();

      expect(done, contains('Restored the original S50downloadmaster'));
      expect(done, contains('Restored the original S50asuslighttpd'));
      expect(done.last, contains(kRouterAppDir));
      // No full stops: the popup renders these as a list, and a sentence-ending stop on each line
      // reads as prose rather than as a set of outcomes.
      for (final line in done) {
        expect(line.endsWith('.'), isFalse, reason: line);
      }
    });

    // Reported 2026-09-10: run twice, the second run deleted the ROUTER'S OWN scripts. The first
    // restored them, and the second found a file it did not recognise and removed it.
    test('a script that is not ours is left alone', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('.old') ? 'NOTOURS' : 'ABSENT');
      final done = await _wd(c).uninstallFromRouter();

      expect(done.where((l) => l.contains('not ours')).length, 2);
      // The test is a header grep, and both replacement scripts carry the same one.
      final probes = c.commands.where((x) => x.contains('S50')).join('\n');
      expect(probes, contains("grep -q 'auto-generated by cfg-pia-wg'"));
    });

    test('uninstall removes the watchdog cron entries and every NVRAM key the app writes', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'cru l') {
          return '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#\n'
              '0 0 * * * mv /tmp/x /tmp/y #watchdog_log_rotate_wgc1#';
        }
        return 'REMOVED';
      });
      final done = await _wd(c).uninstallFromRouter();

      // A cru entry pointing at a deleted script fires forever and does nothing but log a failure.
      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(done, contains('Removed 2 watchdog schedule(s)'));

      final unset = c.commands.firstWhere((x) => x.contains('nvram unset'), orElse: () => '');
      for (final key in ['cfg_pia_wg_password', 'cfg_pia_wg_sdate', 'cfg_pia_wg_reconfig_ok', 'wgc1_wd_smtp_pass']) {
        expect(unset, contains('nvram unset $key'), reason: key);
      }
      // All five slots, not just the one with a watchdog on it.
      expect(unset, contains('nvram unset wgc5_wd_check_interval'));
      // The TUNNEL configuration is deliberately untouched - the user manages those in the WebUI.
      expect(unset, isNot(contains('nvram unset wgc1_priv')));
      expect(unset, isNot(contains('nvram unset wgc1_enable')));
    });

    // Restoring first means that if the directory removal fails, the boot scripts are already
    // back - the reverse order could leave a router with no init script AND the app's files on it.
    test('the boot scripts are restored BEFORE the directory is removed', () async {
      final c = RecordingSSHClient(responder: (_) => 'RESTORED');
      await _wd(c).uninstallFromRouter();

      expect(c.commands.indexWhere((x) => x.contains('S50asuslighttpd.old')),
          lessThan(c.commands.indexWhere((x) => x.contains('rm -rf'))));
    });

    // It removes the app, not the user's VPNs. The tunnels keep working and stay manageable from
    // the web interface, which is why no service is restarted and no wgcN_* key is touched.
    test('it leaves the tunnels alone', () async {
      final c = RecordingSSHClient(responder: (_) => 'REMOVED');
      await _wd(c).uninstallFromRouter();
      expect(c.commands.any((x) => x.startsWith('service ')), isFalse);
    });
  });

  group('deployWatchdog', () {
    test('enables JFFS, writes nvram, deploys the script and both cron entries', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));
      expect(c.ran('nvram set jffs2_scripts=1'), isTrue);
      expect(c.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
      expect(c.ran("nvram set wgc1_wd_secondary_ip='1.1.1.1'"), isTrue);
      expect(c.ran("nvram set cfg_pia_wg_user='p1234567'"), isTrue);
      expect(c.ran("nvram set cfg_pia_wg_password='secret'"), isTrue);
      expect(c.ran("cat > '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);
      expect(c.ran("chmod +x '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);
      expect(c.ran('cru a watchdog_wgc1 "*/5 * * * *"'), isTrue);
      expect(c.ran('cru a watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
      // `deploy`, so the first run reports itself as a deployment rather than a re-configuration.
      expect(c.commands.any((cmd) => cmd == '/jffs/cfg-pia-wg/watchdog_wgc1.sh deploy'), isTrue);
    });

    // Reported 2026-09-06: every deploy performed a full reconfigure - a PIA token and an addKey -
    // because `notify_rc` queues the service call and returns at once, so the script ran about a
    // second later and found no interface. MANAGE's enableSlot has always waited; this path did not.
    test('waits for the interface to come up before running the script', () async {
      var interfaces = '';
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return interfaces;
        // The router brings it up shortly after the service call, not during it.
        if (cmd.contains('restart_vpnc') || cmd.contains('start_wgc')) interfaces = 'wgc1';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      final polled = c.commands.lastIndexWhere((cmd) => cmd == 'ip -o link show up');
      final ran = c.commands.indexWhere((cmd) => cmd.endsWith('watchdog_wgc1.sh deploy'));
      expect(polled, isNot(-1), reason: 'the interface has to be checked at all');
      expect(ran, isNot(-1));
      expect(polled, lessThan(ran), reason: 'and checked BEFORE the script is exec-ed');
    });

    // The wait is bounded: a slot that never comes up must not hang the deploy, because the
    // script's own check will rebuild the tunnel - that is what it is for.
    test('a slot that never comes up still deploys, and says so', () async {
      final logs = <(String, bool)>[];
      final c = RecordingSSHClient(responder: (cmd) => cmd == 'ip -o link show up' ? 'wgs1' : '');
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add((m, isError)))
          .deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.commands.any((cmd) => cmd.endsWith('watchdog_wgc1.sh deploy')), isTrue);
      expect(logs.any((l) => l.$2 && l.$1.contains('has not come up yet')), isTrue);
    });

    test('enables the VPN slot before deploying the watchdog scripts', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));
      final enableIndex = c.commands.indexWhere((cmd) => cmd.contains('wgc1_enable=1'));
      final deployIndex = c.commands.indexWhere((cmd) => cmd.contains("cat > '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"));
      expect(enableIndex, isNot(-1));
      expect(deployIndex, isNot(-1));
      expect(enableIndex, lessThan(deployIndex));
    });

    // The completion line is the router-side record that the deploy finished, not just started.
    test('writes a completion message to the router syslog once deployed', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('jffs2') ? '0' : '');
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));
      expect(
        c.commands.any(
            (cmd) => cmd.contains('logger -t cfg-pia-wg') && cmd.contains('Watchdog deployed for wgc1 (check interval is 5m)')),
        isTrue,
      );
      // ...and it lands after the script has actually been written and run.
      final scriptIndex = c.commands.lastIndexWhere((cmd) => cmd == '/jffs/cfg-pia-wg/watchdog_wgc1.sh deploy');
      final doneIndex = c.commands.indexWhere((cmd) => cmd.contains('Watchdog deployed for wgc1'));
      expect(scriptIndex, isNot(-1));
      expect(scriptIndex, lessThan(doneIndex));
    });
  });

  group('enableVpnSlot', () {
    test('activates the underlying VPN slot and restarts vpn routing', () async {
      final c = RecordingSSHClient();
      await _wd(c).enableVpnSlot(1);
      expect(c.ran("nvram set wgc1_enable=1"), isTrue);
      expect(c.ran('service "start_wgc 1"; service restart_vpnrouting0'), isTrue);
    });
  });

  group('disableVpnSlot', () {
    test('clears the enable flag and stops the interface with the bare slot index', () async {
      final c = RecordingSSHClient();
      await _wd(c).disableVpnSlot(3);
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
            if (cmd.contains('ip -o link show up')) return 'wgc2';
            if (cmd.contains('cru l') && cmd.contains('watchdog_wgc2')) return '1';
            if (cmd.contains('nvram get wgc2_enable')) return '1';
            return '';
          },
        );

    test('deployWatchdog leaves an existing watchdog on another slot running', () async {
      final c = otherSlotActive();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.ran('cru d watchdog_wgc2'), isFalse);
      expect(c.ran('nvram set wgc2_enable=0'), isFalse);
      expect(c.ran('rm -f /jffs/cfg-pia-wg/watchdog_wgc2.sh'), isFalse);
      expect(c.ran('nvram set wgc1_enable=1'), isTrue, reason: 'its own slot still comes up');
    });

    test('deployWatchdog never unsets the shared PIA credentials', () async {
      final c = otherSlotActive();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
      expect(c.ran("nvram set cfg_pia_wg_user='p1234567'"), isTrue);
    });

    test('leaves idle slots alone', () async {
      final c = otherSlotActive();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));
      for (final idle in [3, 4, 5]) {
        expect(c.ran('nvram set wgc${idle}_enable=0'), isFalse);
        expect(c.ran('cru d watchdog_wgc$idle'), isFalse);
      }
    });
  });

  group('disableWatchdog / enableWatchdog', () {
    test('DISABLE removes only the cron entries and the boot persistence', () async {
      final c = RecordingSSHClient();
      await _wd(c).disableWatchdog(1);

      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue, reason: 'its boot lines go too');
      // Everything DELETE would remove has to survive: the settings, the script and the tunnel.
      expect(c.commands.any((cmd) => cmd.contains('nvram unset wgc1_wd_')), isFalse);
      expect(c.ran('rm -f /jffs/cfg-pia-wg/watchdog_wgc1.sh'), isFalse);
      expect(c.ran('nvram set wgc1_enable=0'), isFalse);
      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
    });

    test('ENABLE restores the schedule at the interval stored on the router', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc1_wd_check_interval') ? '15' : '');
      await _wd(c).enableWatchdog(1);

      expect(c.commands.any((cmd) => cmd.contains('cru a watchdog_wgc1') && cmd.contains('*/15')), isTrue);
      expect(c.ran('cru a watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('/jffs/scripts/services-start'), isTrue);
    });

    test('ENABLE refuses when no settings were stored', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await expectLater(_wd(c).enableWatchdog(1), throwsA(isA<Exception>()));
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
      await _wd(c).stopWatchdog(1);

      expect(c.ran('nvram unset cfg_pia_wg_user'), isFalse);
      expect(c.ran('nvram unset cfg_pia_wg_password'), isFalse);
      expect(c.ran('nvram unset wgc1_wd_check_interval'), isTrue, reason: 'its own settings still go');
    });

    test('clears the shared PIA credentials when it is the last watchdog', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).stopWatchdog(1);

      expect(c.ran('nvram unset cfg_pia_wg_user'), isTrue);
      expect(c.ran('nvram unset cfg_pia_wg_password'), isTrue);
    });

    test('removes cron, script, services-start lines and all per-slot files, leaves JFFS', () async {
      final c = RecordingSSHClient();
      await _wd(c).stopWatchdog(1);
      expect(c.ran('cru d watchdog_wgc1'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
      expect(c.ran('rm -f /jffs/cfg-pia-wg/watchdog_wgc1.sh'), isTrue);
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
      await _wd(c).stopWatchdog(1);
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
        if (cmd.contains('ip -o link show up')) return attempts++ > 0 ? 'wgc1' : '';
        return '';
      },
    );
    final ready = await _wd(c).waitForWatchdogReady(1, pollInterval: const Duration(milliseconds: 1), maxAttempts: 3);
    expect(ready, isTrue);
  });

  group('getWatchdogStatus', () {
    test('enabled with a parsed last-ping timestamp', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('cru l')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('ip -o link show up')) return 'wgc1';
          if (cmd.contains('watchdog_last_ping_success_wgc1')) return '2026-06-19 14:30:00';
          return '';
        },
      );
      final st = await _wd(c).getWatchdogStatus(1);
      expect(st.isEnabled, isTrue);
      expect(st.lastSuccessfulPing, DateTime(2026, 6, 19, 14, 30, 0));
    });

    test('disabled when the interface is not present even if the cron exists', () async {
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('cru l')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('ip -o link show up')) return '';
          return '';
        },
      );
      final st = await _wd(c).getWatchdogStatus(1);
      expect(st.isEnabled, isFalse);
    });

    // A stale script is invisible otherwise: the app updates from the store, the script only
    // changes on a deploy, and the 415 hardware test was run against a script two builds old
    // before anyone noticed. Both versions now go to the app log and the router syslog.
    test('reports the deployed script version, and says to redeploy when it is behind', () async {
      final saved = appVersionLabel;
      addTearDown(() => appVersionLabel = saved);
      appVersionLabel = 'v0.8.46 build 416';

      final logged = <String>[];
      final c = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('cru l')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('ip -o link show up')) return 'wgc1';
          if (cmd.contains("sed -n '2p'")) {
            return '# watchdog_wgc1.sh - auto-generated by cfg-pia-wg v0.8.44 build 414; *do* *not* edit.';
          }
          return '';
        },
      );
      final st = await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logged.add(m)).getWatchdogStatus(1);

      expect(st.scriptVersion, 'v0.8.44 build 414');
      expect(st.scriptIsCurrent, isFalse);
      expect(logged.join('\n'), contains('script v0.8.44 build 414, app v0.8.46 build 416 - redeploy'));
      // The same line reaches the router syslog, where it outlives the app session.
      expect(c.commands.join('\n'), contains('logger'));
      expect(c.commands.firstWhere((x) => x.contains('logger')), contains('v0.8.44 build 414'));
    });

    test('says nothing about versions when there is no watchdog to be stale', () async {
      final logged = <String>[];
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('cru l') ? '0' : '');
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logged.add(m)).getWatchdogStatus(1);
      expect(logged.join('\n'), isNot(contains('script')));
    });

    test('disabled with null last-ping', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('cru l') ? '0' : '');
      final st = await _wd(c).getWatchdogStatus(1);
      expect(st.isEnabled, isFalse);
      expect(st.lastSuccessfulPing, isNull);
    });
  });

  test('getWatchdogLog returns cat output', () async {
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('watchdog_wgc1.log') ? 'line1\nline2' : '');
    expect(await _wd(c).getWatchdogLog(1), 'line1\nline2');
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
    final config = await _wd(c).loadConfig(1);
    expect(config.cronIntervalMinutes, 7);
    expect(config.primaryIp, '8.8.8.8');
    expect(config.secondaryIp, '1.1.1.1');
    expect(config.emailAlertsEnabled, isTrue);
    expect(config.smtpServer, 'mail.x.com:465');
    expect(config.piaUsername, 'pu');
    expect(config.piaPassword, 'pp');
  });

  test('testEmail writes mail, sends via sendmail, cleans up, logs', () async {
    final c = RecordingSSHClient();
    await _wd(c).testEmail(cfg(slot: 1, email: true));
    expect(c.ran("cat > '/tmp/mail.txt'"), isTrue);
    expect(c.ran('TEST email'), isTrue, reason: 'the subject says what kind of mail this is');
    expect(c.ran('/usr/sbin/sendmail'), isTrue);
    expect(c.ran('rm -f /tmp/mail.txt'), isTrue);
    expect(c.ran('logger -t cfg-pia-wg'), isTrue);
  });

  // Every email opens with the counters seeded, so "Since <date>" is the day the user started
  // rather than the day of their first reconfigure - which may be months later, or never.
  test('testEmail seeds the lifetime counters and reads the router facts in one round trip', () async {
    final c = RecordingSSHClient();
    await _wd(c).testEmail(cfg(slot: 1, email: true));
    expect(c.ran('nvram set cfg_pia_wg_sdate='), isTrue);
    expect(c.ran('nvram set cfg_pia_wg_reconfig_ok=0'), isTrue);
    expect(c.ran('nvram set cfg_pia_wg_reconfig_fail=0'), isTrue);
    final facts = c.commands.where((cmd) => cmd.contains('nvram get productid')).toList();
    expect(facts, hasLength(1), reason: 'nine facts, one command');
    expect(facts.single, contains('uptime'));
    expect(facts.single, contains('wgc1_wd_check_interval'));
  });

  group('ping helpers', () {
    test('pingHostViaWan command shape and OK/FAIL parsing', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await _wd(ok).pingHostViaWan('8.8.8.8'), isTrue);
      expect(ok.ran('ping -c 1 -W 2'), isTrue);
      final fail = RecordingSSHClient(responder: (_) => 'FAIL');
      expect(await _wd(fail).pingHostViaWan('8.8.8.8'), isFalse);
    });

    test('pingHostViaVpn binds to the interface', () async {
      final ok = RecordingSSHClient(responder: (_) => 'OK');
      expect(await _wd(ok).pingHostViaVpn('8.8.8.8', 2), isTrue);
      expect(ok.ran('ping -I wgc2 -c 1 -W 2'), isTrue);
    });

    test('ping returns false when the SSH command throws', () async {
      final boom = RecordingSSHClient(throwOn: ['ping']);
      expect(await _wd(boom).pingHostViaWan('8.8.8.8'), isFalse);
      expect(await _wd(boom).pingHostViaVpn('8.8.8.8', 1), isFalse);
    });
  });

  // ── Stock firmware ────────────────────────────────────────────────────────────────
  group('stock deploy', () {
    // Stock answers '' to everything unless a test says otherwise; jffs2 reads are irrelevant
    // here. vpnc_clientlist has to read back what was written, though: the deploy resolves
    // vpnc_unit from that row before starting the tunnel.
    RecordingSSHClient stockRouter({String s50 = ''}) {
      var list = '';
      return RecordingSSHClient(responder: (cmd) {
        if (cmd.startsWith("cat '$kS50Path'")) return s50;
        if (cmd.startsWith('nvram set vpnc_clientlist=')) {
          list = cmd.substring(cmd.indexOf('=') + 1).replaceAll("'", '');
          return '';
        }
        if (cmd.contains('nvram get vpnc_clientlist')) return list;
        return '';
      });
    }

    test('creates the script directory instead of setting the Merlin JFFS flags', () async {
      useStock();
      final c = stockRouter();
      await _wd(c).enableJffsScripts();
      // The app's own directory, not Merlin's hook directory - that is where the script lives now.
      expect(c.ran("mkdir -p '/jffs/cfg-pia-wg'"), isTrue);
      expect(c.ran('mkdir -p /jffs/scripts'), isFalse);
      expect(c.ran('nvram set jffs2_scripts=1'), isFalse);
      expect(c.ran('nvram set jffs2_on=1'), isFalse);
    });

    test('persists cron via S50downloadmaster and runs it immediately', () async {
      useStock();
      final c = stockRouter();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

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
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), [buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      // The minimal template scaffolding must survive verbatim.
      expect(write, contains('#!/bin/sh'));
      expect(write, contains('BOOT_FLAG=/tmp/.dm_boot_delay_done'));
      expect(write, contains(r'[ "$1" = "start" ] || exit 0'));
    });

    test('redeploying replaces this slot\'s lines and keeps another slot\'s', () async {
      useStock();
      const otherSlot = 'cru a watchdog_wgc3 "*/9 * * * *" /jffs/cfg-pia-wg/watchdog_wgc3.sh';
      final existing = buildS50Script([otherSlot, buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      final c = stockRouter(s50: existing);
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 15));

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), [otherSlot, buildCronCheckLine(1, 15), buildCronRotateLine(1)]);
      expect(write, isNot(contains('*/5 * * * *')), reason: 'the stale interval must be gone');
    });

    test('the watchdog script points jq at the install path', () async {
      useStock();
      final c = stockRouter();
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      // The script is written in chunks, so the assertions run against the whole payload.
      final write = c.commands.where((cmd) => cmd.contains("/jffs/cfg-pia-wg/watchdog_wgc1.sh' <<")).join();
      expect(write, contains('JQ="$kStockJqPath"'));
      expect(write, contains(kStockMailsendPath));
      expect(write, isNot(contains('/usr/sbin/sendmail')));
    });
  });

  group('stock stopWatchdog', () {
    test('strips this slot from S50downloadmaster without shredding the template', () async {
      useStock();
      const otherSlot = 'cru a watchdog_wgc3 "*/9 * * * *" /jffs/cfg-pia-wg/watchdog_wgc3.sh';
      final existing = buildS50Script([otherSlot, buildCronCheckLine(1, 5), buildCronRotateLine(1)]);
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith("cat '$kS50Path'") ? existing : '');
      await _wd(c).stopWatchdog(1);

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
      await _wd(c).stopWatchdog(1);

      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '$kS50Path'"));
      expect(extractS50CruLines(write), isEmpty);
      expect(write, contains('#!/bin/sh'));
      // Removing a stock init script outright would be worse than emptying its block.
      expect(c.ran("rm -f '$kS50Path'"), isFalse);
    });

    test('still removes the cron jobs, script and tmp files', () async {
      useStock();
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).stopWatchdog(2);
      expect(c.ran('cru d watchdog_wgc2'), isTrue);
      expect(c.ran('cru d watchdog_log_rotate_wgc2'), isTrue);
      expect(c.ran('rm -f /jffs/cfg-pia-wg/watchdog_wgc2.sh'), isTrue);
      expect(c.ran('/tmp/watchdog_backoff_wgc2'), isTrue);
      expect(c.ran('nvram set wgc2_enable=0'), isTrue);
    });
  });

  group('stock testEmail', () {
    test('sends via mailsend-go with a headerless body', () async {
      useStock();
      final c = RecordingSSHClient();
      await _wd(c).testEmail(cfg(slot: 1, email: true));

      expect(c.ran("cat > '/tmp/mail.txt'"), isTrue);
      expect(c.ran('$kStockMailsendPath -ssl -verifyCert'), isTrue);
      expect(c.ran("-sub 'Alert: TEST email - wgc1'"), isTrue);
      expect(c.ran("auth -user 'smtpuser' -pass 'smtppass'"), isTrue);
      expect(c.ran('body -file /tmp/mail.txt'), isTrue);
      expect(c.ran('/usr/sbin/sendmail'), isFalse);
      // No RFC-822 headers in the body file — mailsend-go writes its own.
      final write = c.commands.firstWhere((cmd) => cmd.startsWith("cat > '/tmp/mail.txt'"));
      expect(write, isNot(contains('MIME-Version')));
      expect(c.ran('rm -f /tmp/mail.txt'), isTrue);
    });

    // The nc layer is gone: BusyBox on stock builds nc as `nc IPADDR PORT` with no options, so
    // `nc -w 5` failed on a usage error and declared every host unreachable - including one that
    // delivered mail seconds later. openssl answers the same question and says more.
    test('a failed send probes with openssl, never nc', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('EXITCODE') ? 'EXITCODE:1' : '');
      await _wd(c).testEmail(cfg(slot: 1, email: true));
      expect(c.ran('openssl s_client'), isTrue);
      expect(c.ran('nc -w'), isFalse, reason: 'this option does not exist on the router');
      expect(c.commands.any((cmd) => cmd.contains('logger') && cmd.contains('Email FAILED')), isTrue);
    });
  });

  test('a failing mutation logs an ERROR to syslog and the app log, then rethrows', () async {
    final c = RecordingSSHClient(throwOn: ['chmod']);
    final appLog = <String>[];
    final svc = _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => appLog.add(m));
    await expectLater(svc.deployWatchdog(cfg(slot: 1)), throwsA(isA<Exception>()));
    expect(c.commands.any((cmd) => cmd.contains('logger -t cfg-pia-wg') && cmd.contains('ERROR')), isTrue);
    expect(appLog.any((m) => m.contains('failed')), isTrue);
  });

  // Reported from a router: a failed test email put one TEAL line in the app log saying "see router
  // log for details", and nothing on screen. Everything the router reported has to reach the app
  // log, marked as an error, and the user has to be told without being sent to an SSH session.
  group('test email failure reporting', () {
    /// A router where the mailer exits non-zero and the probe cannot reach the SMTP host.
    RecordingSSHClient failingMailer() => RecordingSSHClient(
          responder: (cmd) {
            if (cmd.contains('mailsend-go') || cmd.contains('sendmail')) return 'EXITCODE:1';
            if (cmd.contains('wd_smtp_err')) return 'dial tcp: i/o timeout';
            if (cmd.contains('openssl s_client')) return 'connect: Connection refused|connect:errno=111';
            return '';
          },
        );

    test('returns false and reports every layer to the app log as an error', () async {
      useStock();
      final logs = <(String, bool)>[];
      final c = failingMailer();
      final ok = await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add((m, isError)))
          .testEmail(cfg(slot: 1, email: true));

      expect(ok, isFalse);
      final errors = logs.where((l) => l.$2).map((l) => l.$1).toList();
      expect(errors.any((m) => m.contains('Test email FAILED (exit 1)')), isTrue);
      expect(errors.any((m) => m.contains('dial tcp: i/o timeout')), isTrue, reason: 'the mailer said why');
      expect(errors.any((m) => m.contains('Connection refused')), isTrue, reason: 'and so did the probe');
      // The old behaviour: one line, not an error, pointing at the router log.
      expect(logs.any((l) => l.$1.contains('see router log')), isFalse);
      expect(logs.any((l) => !l.$2 && l.$1.toLowerCase().contains('failed')), isFalse,
          reason: 'a failure must never be logged as anything but an error');
    });

    test('a successful send returns true and says where it went', () async {
      useStock();
      final logs = <String>[];
      final c = RecordingSSHClient(responder: (_) => 'EXITCODE:0');
      final ok =
          await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m)).testEmail(cfg(slot: 1, email: true));

      expect(ok, isTrue);
      expect(logs.any((m) => m.contains('Test email sent to to@example.com')), isTrue);
      expect(c.ran('rm -f /tmp/mail.txt'), isTrue, reason: 'the body holds nothing secret, but tidy up anyway');
    });

    // One probe, always run. The old code gated the TLS handshake behind an nc check that could
    // not succeed on this router, so the useful diagnostic never ran on the firmware that needed it.
    test('the probe runs whatever the mailer said, and reaches the app log', () async {
      useStock();
      final logs = <String>[];
      final c = failingMailer();
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m)).testEmail(cfg(slot: 1, email: true));

      expect(c.ran('openssl s_client'), isTrue);
      expect(logs.any((m) => m.contains('probe smtp.example.com:465')), isTrue);
    });
  });
}
