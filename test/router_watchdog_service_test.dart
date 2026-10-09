// test/router_watchdog_service_test.dart - RouterWatchdog service tests over a fake SSH client.
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show kMaxActiveVpnsPreviousKey;
import 'package:cfg_pia_wg/fail_closed_guard.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/s50_template.dart';

import 'watchdog_harness.dart' show findShell;
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
/// An empty stock slot whose VPN profile row appears once the deploy writes it, so a deploy gets
/// past ENABLE and fails where the test says it does. Without the row it failed at ENABLE, before
/// the schedule, and a test asserted a "will try again" that was not true (ID-196).
String Function(String) _emptySlotGainingRow() {
  var written = false;
  return (cmd) {
    if (cmd.startsWith('nvram set vpnc_clientlist=')) written = true;
    if (cmd == 'nvram get vpnc_clientlist' && written) return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
    if (cmd == 'ip -o link show up' && written) return 'wgc1';
    return cmd.contains('jffs2') ? '0' : '';
  };
}

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
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            allOf(contains('has 12 of the'), contains('cut short')))),
      );
      // And it stops there rather than scheduling a script that is not there.
      expect(c.ran('cru a watchdog_wgc1'), isFalse);
    });

    // ID-136, as it happened on hardware 2026-09-20: the router reported MORE bytes than were sent,
    // and the message blamed free space on a router with 55 MB spare. A long file is a different
    // fault from a short one and must not be described as one.
    test('a file that comes back LONGER says so, and does not blame free space', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wc -c') ? '999999' : '');
      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1)),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            allOf(contains('arrived twice'), isNot(contains('free space'))))),
      );
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

      expect(c.commands.any((x) => RegExp(r'rm [^;]*watchdog_wgc1\.log($|[\s;])').hasMatch(x)), isFalse,
          reason: 'the live log is truncated, never removed');
      expect(c.ran('rm -f /tmp/watchdog_wgc1.log.old'), isTrue,
          reason: "yesterday's rotated copy goes too, because the viewer shows it");
      expect(c.commands.any((x) => x.contains('> /tmp/watchdog_wgc1.log')), isTrue);
      expect(c.commands.any((x) => x.contains('logger')), isTrue, reason: 'the router log records it');
    });

    // ID-213. Left behind, the rules would keep every pinned device off the internet whenever its
    // tunnel is down, with no app left to say why - so they go first, while the script is there.
    test('uninstall removes the fail-closed guard first', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      final done = await _wd(c).uninstallFromRouter();
      final clear = c.commands.indexWhere((x) => x.contains("'$kGuardScriptPath' clear"));
      expect(clear, isNonNegative);
      expect(clear, lessThan(c.commands.indexWhere((x) => x.contains('rm -rf'))));
      expect(done, contains('Removed the fail-closed guard rules'));
    });

    // ID-330: each step was counted BEFORE it ran and never after, so a step that did nothing still
    // said "Removed". Now each is counted again, and what is left is named.
    test('uninstall says what it could not remove, counted after each step', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains("grep -cE '^(8[89]|9[01]):'")) return '4';
        if (cmd.contains("cru l | grep -cE")) return '1';
        if (cmd.contains("nvram show 2>/dev/null | grep -cE")) return '2';
        return '';
      });
      final done = await _wd(c).uninstallFromRouter();
      expect(done, contains('4 fail-closed guard rule(s) could not be removed: check `ip rule show` on the router'));
      expect(done, contains('1 schedule(s) could not be removed: check `cru l` on the router'));
      expect(done, contains('2 app setting(s) could not be removed from NVRAM'));
      expect(done.where((l) => l.startsWith('Removed the fail-closed guard rules')), isEmpty);
    });

    // Builds 480 to 490 ran the guard every minute from cron. Build 491 takes that out (ID-364), but a
    // router the app has not reached since can still have it, and uninstall must not leave it running.
    test('uninstall stops every schedule, the guard\'s old one included, before anything else', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd == 'cru l'
          ? '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#\n'
              '* * * * * /jffs/cfg-pia-wg/guard.sh #$kLegacyGuardCronTag#'
          : '');
      await _wd(c).uninstallFromRouter();
      final guardCron = c.commands.indexOf('cru d $kLegacyGuardCronTag');
      expect(guardCron, isNonNegative);
      expect(c.commands.indexOf('cru d watchdog_wgc1'), isNonNegative);
      expect(guardCron, lessThan(c.commands.indexWhere((x) => x.contains("'$kGuardScriptPath' clear"))));
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

    // ID-065: the credentials are shared by every watchdog on the router, and a PAUSED one has no
    // cron entry - so asking `cru` alone deleted them out from under it, and its next reconfigure
    // aborted with "PIA username is not set". More likely since ID-095 made pausing normal.
    test('a paused watchdog on another slot keeps the shared PIA credentials', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('cru l')) return ''; // nothing scheduled anywhere
        // The probe is one shell line that echoes 1 per configured slot; wgc5 is paused, not gone.
        if (cmd.contains('wgc5_wd_check_interval')) return '1';
        return '';
      });
      await _wd(c).stopWatchdog(1);

      expect(c.commands.any((x) => x.contains('nvram unset cfg_pia_wg_user')), isFalse);
      expect(c.commands.any((x) => x.contains('nvram unset cfg_pia_wg_password')), isFalse);
    });

    test('the last watchdog of all still takes the credentials with it', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).stopWatchdog(1);

      expect(c.commands.any((x) => x.contains('nvram unset cfg_pia_wg_user')), isTrue);
      expect(c.commands.any((x) => x.contains('nvram unset cfg_pia_wg_password')), isTrue);
    });

    // ID-098: raising the VPN cap is a change the app makes to a router-wide setting, so an
    // uninstall puts it back - and only when the app is what moved it.
    test('uninstall puts the VPN cap back to what the app found', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains(kMaxActiveVpnsPreviousKey) ? '2' : 'ABSENT');
      final done = await _wd(c).uninstallFromRouter();

      expect(c.ran('nvram set vpnc_max_conn=2'), isTrue);
      expect(done, contains('Put the maximum active VPNs back to 2'));
    });

    test('uninstall leaves a cap the app never raised alone', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      final done = await _wd(c).uninstallFromRouter();

      expect(c.commands.any((x) => x.contains('nvram set vpnc_max_conn')), isFalse);
      expect(done, contains('Left the maximum active VPNs alone - the app never changed it'));
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

      // The Network Services Filter's own clean-up (ID-348) unsets its keys too; this is the list.
      final unset = c.commands.firstWhere((x) => x.contains('nvram unset cfg_pia_wg_user'), orElse: () => '');
      for (final key in ['cfg_pia_wg_password', 'cfg_pia_wg_sdate', 'cfg_pia_wg_reconfig_ok', 'wgc1_wd_smtp_pass']) {
        expect(unset, contains('nvram unset $key'), reason: key);
      }
      // All five slots, not just the one with a watchdog on it.
      expect(unset, contains('nvram unset wgc5_wd_check_interval'));
      // The TUNNEL configuration is deliberately untouched - the user manages those in the WebUI.
      expect(unset, isNot(contains('nvram unset wgc1_priv')));
      expect(unset, isNot(contains('nvram unset wgc1_enable')));
    });

    // ID-348: the app's entries in the router's Network Services Filter go too, run directly in case
    // guard.sh is missing, and BEFORE the app's keys that say which entries are its own are unset.
    test('uninstall takes the app\'s entries out of the Network Services Filter before unsetting its keys', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get cfg_pia_wg_lwlist' ? '192.0.2.20/TCP' : '');
      final done = await _wd(c).uninstallFromRouter();
      final clear = c.commands.indexOf(kFilterClearCommand);
      expect(clear, greaterThan(-1));
      expect(clear, lessThan(c.commands.indexWhere((x) => x.contains('nvram unset cfg_pia_wg_user'))));
      expect(kFilterClearCommand.split('\n').where((l) => l.trimLeft().startsWith('#')), isEmpty,
          reason: 'comments are not sent over SSH');
      expect(done.any((l) => l.contains('Network Services Filter')), isTrue);
    });

    // Restoring first means that if the directory removal fails, the boot scripts are already
    // back - the reverse order could leave a router with no init script AND the app's files on it.
    test('the boot scripts are restored BEFORE the directory is removed', () async {
      final c = RecordingSSHClient(responder: (_) => 'RESTORED');
      await _wd(c).uninstallFromRouter();

      expect(c.commands.indexWhere((x) => x.contains('S50asuslighttpd.old')),
          lessThan(c.commands.indexWhere((x) => x.contains('rm -rf'))));
    });

    // ID-303: on Merlin the next boot's schedule lives in services-start, and nothing took it out,
    // so the boot after an uninstall scheduled scripts that were no longer there.
    test('on Merlin it removes the watchdog lines from services-start', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith('grep -cE') ? '4' : '');
      final done = await _wd(c).uninstallFromRouter();
      expect(c.commands.any((x) => x.startsWith("grep -vE 'watchdog_(log_rotate_)?wgc[1-9] ' '$kServicesStartPath'")),
          isTrue);
      expect(done, contains('Removed the watchdog lines from $kServicesStartPath'));
      // Every line the app ever writes there is caught by the pattern, and nothing else.
      final pattern = RegExp(r'watchdog_(log_rotate_)?wgc[1-9] ');
      for (final line in buildServicesStartBlock(3, 5).trim().split('\n')) {
        expect(pattern.hasMatch(line), isTrue, reason: line);
      }
      expect(pattern.hasMatch('cru a my_own_job "0 3 * * *" /jffs/scripts/backup.sh'), isFalse);
    });

    test('on Merlin with nothing in services-start it says so', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith('grep -cE') ? '0' : '');
      final done = await _wd(c).uninstallFromRouter();
      expect(c.commands.any((x) => x.startsWith('grep -vE')), isFalse);
      expect(done, contains('No watchdog lines in $kServicesStartPath to remove'));
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

    // Measured 2026-09-13: creating a watchdog on a wgc4 that was already up ran `restart_vpnc`,
    // which on stock rebuilds VPN routing for every tunnel.
    // ID-126: a slot built from the watchdog form used to get no DNS at all. Measured on hardware
    // 2026-09-19: with no `wgcN_dns` the firmware adds no VPN_FUSION redirect, so a device pinned to
    // that slot sent its traffic through the tunnel and its name lookups out over the WAN.
    test('the deploy writes the slot DNS the form supplied', () async {
      useStock();
      // A slot that already exists and keeps its region, so the deploy takes its simplest path.
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_melbourne';
        if (cmd.contains('vpnc_clientlist')) return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(
        cfg(slot: 1, interval: 5).copyWith(slotDns: '9.9.9.9, 149.112.112.112'),
        desc: 'aus_melbourne',
      );

      expect(c.commands.any((x) => x.contains("nvram set wgc1_dns='9.9.9.9, 149.112.112.112'")), isTrue);
    });

    test('an empty DNS leaves whatever the slot already has alone', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_melbourne';
        if (cmd.contains('vpnc_clientlist')) return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne');

      expect(c.commands.any((x) => x.contains('nvram set wgc1_dns')), isFalse,
          reason: 'a slot built in MANAGE keeps its own choice');
    });

    test('the form reads back the slot DNS that is really there', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc1_dns') ? '1.1.1.1, 1.0.0.1' : '');
      final loaded = await _wd(c).loadConfig(1);

      expect(loaded.slotDns, '1.1.1.1, 1.0.0.1');
    });

    // ID-121 / ID-096: a deploy that fails part way used to leave a slot the app read as configured
    // while the router's web interface showed nothing - keys written, profile row added, slot
    // enabled, and then an abort. It now puts the slot back and says which.
    //
    // And its watchdog goes with it (2026-10-01). The schedule used to stay, because on 2026-09-17
    // a scheduled check finished a failed build; but that slot still had its description, and the
    // clean-up here deletes it, so on an empty slot the retry had no region and could never work.
    test('a failed deploy clears a slot that started empty, and its watchdog with it', () async {
      useStock();
      final c = RecordingSSHClient(responder: _emptySlotGainingRow());
      // The script's own run is the step that fails, exactly as an aborted deploy does.
      c.failExactly['${watchdogScriptPath(1)} deploy'] = 'ERROR: PIA rejected the username and password';

      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'),
        throwsA(predicate((e) =>
            e.toString().contains('cleared back to empty') &&
            e.toString().contains('No watchdog was set up') &&
            !e.toString().contains('try again'))),
      );

      expect(c.commands.any((x) => x.startsWith('nvram unset wgc1_priv')), isTrue, reason: 'the keys go');
      final run = c.commands.indexOf('${watchdogScriptPath(1)} deploy');
      expect(run, greaterThan(-1), reason: 'it failed at the run, not before');
      final after = c.commands.skip(run).toList();
      expect(after, contains('cru d watchdog_wgc1'));
      expect(after, contains('cru d watchdog_log_rotate_wgc1'));
      expect(after.any((x) => x.startsWith('rm -f ${watchdogScriptPath(1)}')), isTrue, reason: 'the script goes');
      expect(after.any((x) => x.startsWith("cat > '$kS50Path'")), isTrue, reason: 'the boot hook is rewritten without it');
      expect(after, contains('nvram unset wgc1_wd_check_interval'), reason: 'no settings: the slot was empty');
      expect(after, contains('nvram unset cfg_pia_wg_password'), reason: 'no other watchdog had a login there');
      // The deploy enabled the slot, so its interface is up. It is stopped while its profile row is
      // still there, because the stop finds the slot by its row; clearing first left the interface
      // running with nothing behind it (2026-10-01).
      final stop = after.indexOf('service stop_vpnc');
      expect(stop, greaterThan(-1), reason: 'the interface the deploy brought up is stopped');
      expect(after.take(stop), contains('nvram set vpnc_unit=0'), reason: 'aimed at its row');
      expect(stop, lessThan(after.indexWhere((x) => x.startsWith('nvram set vpnc_clientlist='))),
          reason: 'before the row goes');
    });

    test('a failed deploy onto an empty slot puts back the PIA login other watchdogs were using', () async {
      useStock();
      final base = _emptySlotGainingRow();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'nvram get cfg_pia_wg_user') return 'p1111111';
        if (cmd == 'nvram get cfg_pia_wg_password') return 'the-old-one';
        return base(cmd);
      });
      c.failExactly['${watchdogScriptPath(1)} deploy'] = 'ERROR: PIA rejected the username and password';

      await expectLater(_wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'), throwsA(anything));

      final run = c.commands.indexOf('${watchdogScriptPath(1)} deploy');
      final after = c.commands.skip(run).toList();
      expect(after, contains("nvram set cfg_pia_wg_user='p1111111'"));
      expect(after, contains("nvram set cfg_pia_wg_password='the-old-one'"));
    });

    // 2026-10-01: "router command failed (exit 1): /jffs/cfg-pia-wg/watchdog_wgc3.sh deploy" said
    // nothing the user could act on. The run's own ERROR line does.
    test("a failed first run names the run's own error, not the command", () async {
      useStock();
      final base = _emptySlotGainingRow();
      final c = RecordingSSHClient(responder: (cmd) => cmd.startsWith("grep 'ERROR: ' /tmp/watchdog_wgc1.log")
          ? "PIA's login service isn't answering (no answer in 15 s). This is usually at PIA's end; the watchdog will try again."
          : base(cmd));
      c.failExactly['${watchdogScriptPath(1)} deploy'] = '';

      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'),
        throwsA(predicate((e) =>
            e.toString().contains("The watchdog's first run failed: PIA's login service isn't answering (no answer in 15 s).") &&
            !e.toString().contains('router command failed') &&
            !e.toString().contains('will try again'))),
      );
      expect(c.commands.where((x) => x.contains('ERROR during') && x.contains('Exception:')), isEmpty,
          reason: "ROUTER LOG gets the sentence without Dart's prefix");
    });

    // ID-196: a save that failed before its schedule was written left the new watchdog settings on
    // the router with no cron entry - which is PAUSED - under an error saying it "stays scheduled".
    test('a first save that fails before it is scheduled leaves no watchdog, and says so', () async {
      useStock();
      final c = RecordingSSHClient(responder: _emptySlotGainingRow());
      c.failWith["cat > '${watchdogScriptPath(1)}'"] = 'cat: write error: No space left on device';

      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'),
        throwsA(predicate((e) =>
            e.toString().contains('No space left') &&
            e.toString().contains('No watchdog was set up') &&
            !e.toString().contains('stays scheduled'))),
      );
      expect(c.ran('nvram unset wgc1_wd_check_interval'), isTrue, reason: 'no settings without a schedule: that reads as PAUSED');
      expect(c.commands.any((x) => x.contains('cru a watchdog_wgc1')), isFalse);
    });

    test('an edit that fails before it is scheduled puts the previous watchdog settings back', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'nvram get wgc1_wd_check_interval') return '10';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_melbourne';
        if (cmd.contains('nvram get vpnc_clientlist')) return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      c.failWith["cat > '${watchdogScriptPath(1)}'"] = 'cat: write error: No space left on device';

      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'),
        throwsA(predicate((e) => e.toString().contains('No space left') && e.toString().contains('previous settings were put back'))),
      );
      final restored = c.commands.lastIndexWhere((x) => x.startsWith('nvram set wgc1_wd_check_interval='));
      expect(c.commands[restored], "nvram set wgc1_wd_check_interval='10'", reason: 'the old interval, not the new 5');
    });

    test('a failed deploy restores a slot that already held a configuration', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-us_east';
        if (cmd.contains('nvram get wgc1_priv')) return 'OLDKEY';
        if (cmd.contains('nvram get vpnc_clientlist')) return 'pia-us_east>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      c.failExactly['${watchdogScriptPath(1)} deploy'] = 'ERROR: the PIA server never answered';

      await expectLater(
        _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne'),
        throwsA(predicate((e) => e.toString().contains('was left as it was') && e.toString().contains('try again in 5 minutes'))),
      );

      expect(c.commands.any((x) => x.contains("nvram set wgc1_priv='OLDKEY'")), isTrue,
          reason: 'the old configuration is put back');
      expect(c.commands.any((x) => x.contains('nvram set vpnc_clientlist=')), isTrue);
      // A slot with a tunnel to go back to keeps its watchdog, and the retry that rescued the build
      // on 2026-09-17; and the PIA login its retry will use.
      final after = c.commands.skip(c.commands.indexOf('${watchdogScriptPath(1)} deploy')).toList();
      expect(after, isNot(contains('cru d watchdog_wgc1')));
      expect(after.any((x) => x.startsWith('nvram unset cfg_pia_wg_') || x.startsWith('nvram set cfg_pia_wg_')), isFalse);
    });

    test('a slot that is already up, keeping its region, is not restarted', () async {
      useStock();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_melbourne';
        if (cmd.contains('nvram get vpnc_clientlist')) return 'pia-aus_melbourne>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne');

      // Exact commands, as the Merlin case below: since ID-070 the uploaded script mentions
      // restart_vpnc itself, so a substring match now finds the file rather than the action.
      expect(c.commands.any((cmd) => cmd.startsWith('nvram set vpnc_unit')), isFalse);
      expect(c.commands.contains('service restart_vpnc'), isFalse);
      expect(c.ran('nvram set wgc1_enable=1'), isTrue, reason: 'the flags are still written');
      expect(c.commands.any((cmd) => cmd.endsWith('watchdog_wgc1.sh deploy')), isTrue);
      expect(c.commands.where((cmd) => cmd.contains('logger')).join('\n'), contains('already up'));
    });

    test('Merlin skips the restart too, including when the form passes no region', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return 'wgc1';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5));

      // Exact commands: the watchdog script uploaded by the same deploy mentions start_wgc itself.
      expect(c.commands.contains('service "start_wgc 1"; service restart_vpnrouting0'), isFalse);
    });

    // The CREATE fault again, on the watchdog form (found 2026-09-14): a region change wrote only the new
    // name, and the deploy run left the old server's tunnel alone because its handshake was recent. A
    // region change is a rebuild: stop the tunnel, blank the old server, and let the deploy run build it.
    test('a region change on a running slot stops it and clears the old server before anything else', () async {
      useMerlin();
      var stopped = false;
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'service "stop_wgc 1"; service start_vpnrouting0') stopped = true;
        if (cmd == 'ip -o link show up') return stopped ? '' : 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_perth';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne');

      final stop = c.commands.indexOf('service "stop_wgc 1"; service start_vpnrouting0');
      final blank = c.commands.indexOf("nvram set wgc1_ppub=''");
      final name = c.commands.indexOf("nvram set wgc1_desc='pia-aus_melbourne'");
      final run = c.commands.indexWhere((cmd) => cmd.endsWith('watchdog_wgc1.sh deploy'));
      expect(stop, isNot(-1), reason: 'the running tunnel is stopped');
      expect(blank, greaterThan(stop), reason: 'then the old server is blanked');
      expect(c.ran("nvram set wgc1_priv=''"), isTrue);
      expect(c.ran("nvram set wgc1_ep_addr=''"), isTrue);
      expect(name, greaterThan(blank));
      expect(run, greaterThan(name), reason: 'and the deploy run builds the new one');
      expect(c.ran('nvram set wgc1_enable=1'), isTrue);
    });

    test('a region change on a slot that is not running clears the old server without a stop', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_perth';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne');

      expect(c.commands.contains('service "stop_wgc 1"; service start_vpnrouting0'), isFalse);
      final blank = c.commands.indexOf("nvram set wgc1_ppub=''");
      final start = c.commands.indexOf('service "start_wgc 1"; service restart_vpnrouting0');
      expect(blank, isNot(-1));
      expect(start, greaterThan(blank), reason: 'the enable cannot bring back a server it no longer has');
    });

    test('on stock the stop is stop_vpnc, and the restart that follows has no old server to reload', () async {
      useStock();
      var stopped = false;
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'service stop_vpnc') stopped = true;
        if (cmd == 'ip -o link show up') return stopped ? '' : 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-us_alabama';
        if (cmd.contains('nvram get vpnc_clientlist')) return 'pia-us_alabama>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_perth');

      final stop = c.commands.indexOf('service stop_vpnc');
      final blank = c.commands.indexOf("nvram set wgc1_ppub=''");
      final restart = c.commands.indexOf('service restart_vpnc');
      expect(stop, isNot(-1));
      expect(blank, greaterThan(stop));
      expect(restart, greaterThan(blank));
    });

    // ID-224: WD-6 on 2026-09-26 logged "wgc1:pia-aus_perth is vpnc_clientlist row 1; ... restart_vpnc"
    // and then "wgc1:pia-nz enabled" in the same region change: a name remembered from before it.
    test('a region change names the slot by its new region once the new name is written', () async {
      useStock();
      var stopped = false;
      var renamed = false;
      final timeline = <String>[];
      final c = RecordingSSHClient(responder: (cmd) {
        timeline.add('CMD $cmd');
        if (cmd == 'service stop_vpnc') stopped = true;
        if (cmd.startsWith("nvram set wgc1_desc='pia-aus_perth'")) renamed = true;
        if (cmd == 'ip -o link show up') return stopped ? '' : 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return renamed ? 'pia-aus_perth' : 'pia-us_alabama';
        if (cmd.contains('nvram get vpnc_clientlist')) {
          return '${renamed ? 'pia-aus_perth' : 'pia-us_alabama'}>WireGuard>1>>pw>1>9>>>0>0>cfg-pia-wg';
        }
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => timeline.add('LOG $m'))
          .deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_perth');

      final named = timeline.indexWhere((e) => e.startsWith("CMD nvram set wgc1_desc='pia-aus_perth'"));
      expect(named, isNot(-1));
      final after = timeline.skip(named).where((e) => e.startsWith('LOG ') && e.contains('wgc1')).toList();
      expect(after, isNotEmpty);
      expect(after.where((e) => e.contains('pia-us_alabama')), isEmpty, reason: 'no line after the rename uses the old name');
    });

    test('an unchanged region clears nothing', () async {
      useMerlin();
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd == 'ip -o link show up') return 'wgc1';
        if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_melbourne';
        return cmd.contains('jffs2') ? '0' : '';
      });
      await _wd(c).deployWatchdog(cfg(slot: 1, interval: 5), desc: 'aus_melbourne');

      expect(c.ran("nvram set wgc1_ppub=''"), isFalse);
      expect(c.commands.contains('service "stop_wgc 1"; service start_vpnrouting0'), isFalse);
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

    // ID-150: DELETE kept its own list of keys, and missed the two DoH ones 454 added.
    test('removes every per-slot watchdog key, the DoH pair included', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).stopWatchdog(1);
      for (final field in kWatchdogSlotNvramFields) {
        expect(c.ran('nvram unset wgc1_$field'), isTrue, reason: 'wgc1_$field was left behind');
      }
      expect(kWatchdogSlotNvramFields, containsAll(['wd_doh_ip', 'wd_doh_url']));
    });

    // ID-247: the command asking whether another watchdog is configured exited 1 whenever the last
    // slot it tested had none - the answer, not a failure - and was logged as "router command failed".
    test('asking whether another watchdog is configured exits 0 whatever the answer', () async {
      final shell = findShell();
      if (shell == null) return markTestSkipped('no POSIX shell to run the command in');
      final c = RecordingSSHClient(responder: (_) => '');
      await _wd(c).stopWatchdog(1);
      final probe = c.commands.firstWhere((cmd) => cmd.contains('_wd_check_interval)" ] && echo 1'));

      // wgc2 has a watchdog and wgc5, the last slot tested, has none: the case that failed.
      final r = await Process.run(
          shell, ['-c', 'nvram() { [ "\$2" = wgc2_wd_check_interval ] && echo 5; }; $probe']);
      expect(r.exitCode, 0, reason: probe);
      expect('${r.stdout}'.trim(), '1');
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

  test("getWatchdogLog reads yesterday's rotated copy first, and tolerates either being absent", () async {
    final c = RecordingSSHClient(responder: (_) => '');
    await _wd(c).getWatchdogLog(1);
    final cmd = c.commands.singleWhere((x) => x.contains('watchdog_wgc1.log'));
    expect(cmd, contains("if [ -f '/tmp/watchdog_wgc1.log.old' ]"));
    expect(cmd, contains("if [ -f '/tmp/watchdog_wgc1.log' ]"));
    expect(cmd.indexOf("'/tmp/watchdog_wgc1.log.old'"), lessThan(cmd.lastIndexOf("'/tmp/watchdog_wgc1.log'")),
        reason: 'oldest first, so the text reads in time order');
  });

  group('redeploying the watchdog script', () {
    // Answers the post-write size check from what was actually written, whatever else it is asked.
    RecordingSSHClient router({String firmwareTag = '', String deployed = '5'}) {
      late final RecordingSSHClient c;
      c = RecordingSSHClient(responder: (cmd) {
        final size = RegExp(r"wc -c < '([^']+)'").firstMatch(cmd);
        if (size != null) return '${c.files[size.group(1)]?.length ?? 0}';
        if (cmd.contains('3rd-party')) return firmwareTag;
        if (cmd.contains('] && echo')) return deployed;
        return '';
      });
      return c;
    }

    // ID-190: the app log gave a path and a size, the router log the version.
    test('the app log and the router log say the same thing, version included', () async {
      appVersionLabel = 'v0.8.94 build 464';
      addTearDown(() => appVersionLabel = '');
      final logs = <String>[];
      final c = router(deployed: '5');
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m)).redeployScripts();
      expect(logs, contains('Watchdog script updated to v0.8.94 build 464 for wgc5.'));
      expect(c.commands.any((x) => x.startsWith('logger') && x.contains('Watchdog script updated to v0.8.94 build 464 for wgc5')), isTrue);
    });

    test('rewrites only the scripts already on the router, and touches nothing else', () async {
      final c = router(deployed: '5');
      expect(await _wd(c).redeployScripts(), [5]);
      expect(c.ran("wc -c < '/jffs/cfg-pia-wg/watchdog_wgc5.sh'"), isTrue, reason: 'written, and the write proved');
      expect(c.ran("wc -c < '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isFalse, reason: 'no script there, so none put there');
      // The one schedule change allowed is taking out the guard's old every-minute entry, which builds
      // 480 to 490 kept whenever a device was pinned (ID-364) - never a watchdog's, and nothing added.
      expect(
          c.commands.any((x) =>
              x.startsWith('cru a') ||
              (x.startsWith('cru ') && !x.contains(kLegacyGuardCronTag)) ||
              x.startsWith('service ') ||
              x.startsWith('nvram set')),
          isFalse,
          reason: 'no schedule, tunnel or setting changes');
    });

    test('refuses a firmware it does not support rather than guessing which script to write', () async {
      await expectLater(_wd(router(firmwareTag: 'something-else')).redeployScripts(), throwsException);
    });

    test('finds nothing to do when no script is deployed', () async {
      expect(await _wd(router(deployed: '')).redeployScripts(), isEmpty);
    });

    // A router updated from before 460 has no guard and a boot hook that does not call one. This is
    // the update the user is prompted for, so it brings both.
    test('on stock it also puts the fail-closed guard in place', () async {
      useStock();
      final c = router(deployed: '5');
      await _wd(c).redeployScripts();
      expect(c.commands, contains("'$kGuardScriptPath'"));
    });

    test('and rewrites a boot hook the app wrote, keeping its schedule', () async {
      useStock();
      late final RecordingSSHClient c;
      final old = buildS50Script(['cru a watchdog_wgc5 "*/5 * * * *" /jffs/cfg-pia-wg/watchdog_wgc5.sh'])
          .replaceAll(RegExp(r'\n  # Put the fail-closed guard back.*\n.*guard\.sh.*'), '');
      c = RecordingSSHClient(responder: (cmd) {
        final size = RegExp(r"wc -c < '([^']+)'").firstMatch(cmd);
        if (size != null) return '${c.files[size.group(1)]?.length ?? 0}';
        if (cmd.contains('] && echo')) return '5';
        if (cmd == "cat '$kS50Path' 2>/dev/null") return old;
        return '';
      });
      await _wd(c).redeployScripts();
      final written = c.files[kS50Path]?.toString() ?? '';
      expect(written, contains(kGuardScriptPath));
      expect(extractS50CruLines(written), ['cru a watchdog_wgc5 "*/5 * * * *" /jffs/cfg-pia-wg/watchdog_wgc5.sh']);
    });

    test("leaves a boot script that is not the app's alone", () async {
      useStock();
      late final RecordingSSHClient c;
      c = RecordingSSHClient(responder: (cmd) {
        final size = RegExp(r"wc -c < '([^']+)'").firstMatch(cmd);
        if (size != null) return '${c.files[size.group(1)]?.length ?? 0}';
        if (cmd.contains('] && echo')) return '5';
        if (cmd == "cat '$kS50Path' 2>/dev/null") return '#!/bin/sh\n# the real Download Master\n';
        return '';
      });
      await _wd(c).redeployScripts();
      expect(c.files.containsKey(kS50Path), isFalse);
    });
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

  // ID-049: the region on the form, which the router does not carry until the first deploy - the subject used
  // to say only "wgc1" and the body "region not yet set" while the form already named it.
  test('testEmail names the region it is given, in the subject and the Watchdog row', () async {
    final c = RecordingSSHClient();
    await _wd(c).testEmail(cfg(slot: 1, email: true), desc: 'pia-aus_perth');
    expect(c.ran('TEST email - wgc1:pia-aus_perth'), isTrue);
    expect(c.ran('Watchdog: wgc1:pia-aus_perth'), isTrue);
    expect(c.ran('region not yet set'), isFalse);
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

  // ID-300: a deploy whose alert email failed said so only in the router's log.
  group("the deploy's alert email", () {
    const failed = '2026-01-01 10:00:05 Email FAILED (mailer exit=1) stderr=[ERROR: 535 5.7.8 Username and Password '
        'not accepted. For more information, go to|5.7.8  https://support.example.com/mail - gsmtp||]\n'
        '2026-01-01 10:00:05 Email diag: resolv.conf [192.0.2.53 ] via eth0; smtp.example.com resolves to [...]';

    test("the reason is the mailer's own first line, without its 'for more information'", () {
      expect(deployEmailFailure(failed), '535 5.7.8 Username and Password not accepted.');
      expect(deployEmailFailure('2026-01-01 10:00:05 Email FAILED (mailer exit=1) stderr=[none]'),
          'the mail server gave no reason');
      expect(deployEmailFailure('2026-01-01 10:00:05 Alert email sent (SUCCESS)'), isNull);
      expect(deployEmailFailure(''), isNull);
    });

    RecordingSSHClient router(String runLog) {
      final slot = _emptySlotGainingRow();
      return RecordingSSHClient(responder: (cmd) {
        if (cmd.startsWith('wc -l < /tmp/watchdog_wgc1.log')) return '12';
        if (cmd.startsWith('tail -n +13 /tmp/watchdog_wgc1.log')) return runLog;
        return slot(cmd);
      });
    }

    test("a failed one is returned, and said in the app log, and only this run's lines are read", () async {
      useStock();
      final logs = <String>[];
      final c = router(failed);
      final problem = await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m))
          .deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne');
      expect(problem, '535 5.7.8 Username and Password not accepted.');
      expect(logs.last, "The deploy's alert email could not be sent: 535 5.7.8 Username and Password not accepted.");
      expect(c.ran('tail -n +13 /tmp/watchdog_wgc1.log'), isTrue, reason: "lines written before the run are not this deploy's");
    });

    test('a sent one returns nothing', () async {
      useStock();
      expect(await _wd(router('2026-01-01 10:00:05 Alert email sent (SUCCESS)')).deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne'),
          isNull);
    });

    // ID-328: a run that decided not to send at all was reported as no email problem.
    test('an email the run never sent is a problem too, with its reason', () {
      expect(
          deployEmailFailure('2026-01-01 10:00:05 Email not sent: the SMTP server setting is not a plain host:port. '
              'Fix it on the WATCHDOG form and SAVE & DEPLOY'),
          startsWith('the SMTP server setting is not a plain host:port'));
      expect(deployEmailFailure('2026-01-01 10:00:05 Email enabled but SMTP server is not configured'),
          'no SMTP server is set on the WATCHDOG form');
    });
  });

  // ID-327: both of these runs exit 0, and the app said "Watchdog deployed" after either.
  group('a deploy run that did nothing', () {
    test('is recognised from its log', () {
      expect(deployDidNothing('x no Internet on WAN interface, exiting.'), contains('no internet on the WAN'));
      expect(deployDidNothing('x Backing off after 3 failed attempts: 10s of 600s elapsed'), contains('backing off'));
      expect(deployDidNothing('x Handshake 20s ago\nx Alert email sent (SUCCESS)'), isNull);
    });

    RecordingSSHClient router(String runLog) {
      final slot = _emptySlotGainingRow();
      return RecordingSSHClient(responder: (cmd) {
        if (cmd.startsWith('wc -l < /tmp/watchdog_wgc1.log')) return '12';
        if (cmd.startsWith('tail -n +13 /tmp/watchdog_wgc1.log')) return runLog;
        return slot(cmd);
      });
    }

    test('is reported as scheduled but not proved, never as "deployed"', () async {
      useStock();
      final logs = <String>[];
      final c = router('2026-01-01 10:00:05 no Internet on WAN interface, exiting.');
      await _wd(c, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m))
          .deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne');
      expect(logs.where((l) => l.startsWith('Watchdog deployed')), isEmpty);
      expect(logs.last, contains('is scheduled, but its first run found no internet on the WAN'));
    });

    test('a deploy clears a backoff left by earlier failures first, so it is not the reason', () async {
      useStock();
      final c = router('2026-01-01 10:00:05 Alert email sent (SUCCESS)');
      await _wd(c).deployWatchdog(cfg(slot: 1), desc: 'aus_melbourne');
      final clear = c.commands.indexOf('rm -f /tmp/watchdog_backoff_wgc1');
      expect(clear, greaterThanOrEqualTo(0));
      expect(clear, lessThan(c.commands.indexWhere((x) => x.endsWith('watchdog_wgc1.sh deploy'))));
    });
  });
}
