// The watchdog checks itself and reports what went wrong, run for real against a fake stock router
// (test/watchdog_harness.dart): ID-484 and ID-485.
//
// On 2026-10-29 an update left watchdog_wgc5.sh cut short at 7,940 of its 49 KB. Cron ran it every
// five minutes; it stopped at a syntax error before its first log line, its output went to
// /dev/null, and nothing said anything for a day. Each test here takes one of those silences away.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/fail_closed_guard.dart' show kGuardScript;
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_log_paging.dart';
import 'package:cfg_pia_wg/router_script_integrity.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart';

/// The script cut short where 2026-10-29's was: on a whole line, inside the kill switch's `if` block,
/// so the shell meets the end of the file in the middle of a command.
String cutShort(String s) => s.substring(0, s.indexOf('\n', s.indexOf(r'elif [ "$GUARDED" -ge')) + 1);

/// The script with its self-check taken out, for a control. Fails rather than quietly doing nothing
/// if the check's wording moves.
String noSelfCheck(String s) {
  const check = r'if [ "$RUNMODE" != "fault" ] && [ "$(tail -n 1 "$0"';
  if (!s.contains(check)) throw StateError('the self-check is not where this control looks for it');
  return s.replaceFirst(check, r'if false && [ "$(tail -n 1 "$0"');
}

/// A process id no process has: above Linux's largest.
const int kGonePid = 4194999;

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) h = WatchdogHarness.create(shell: shell)!;
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  group('the script ends with the line it checks for (ID-484)', () {
    test('a watchdog script', () {
      final s = buildWatchdogScript(
          const WatchdogConfig(slotIndex: 3, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
          firmware: RouterFirmware.stock);
      expect(s.endsWith('exit 0\n# end of watchdog_wgc3.sh\n'), isTrue);
      expect(s, contains('SELFEND="# end of watchdog_wgc3.sh"'));
      expect(lastLineOf(s), scriptEndLine('watchdog_wgc3.sh'));
    });
  });

  group('a damaged watchdog script (ID-484)', () {
    test('logs a red ERROR, keeps it for the app, and does nothing else', () async {
      final r = await h.run(edit: cutShort);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      final line = h.syslog.firstWhere((l) => l.contains('is damaged'), orElse: () => '');
      expect(line, startsWith('wgc1: ERROR: watchdog_wgc1.sh is damaged ('));
      expect(line, contains('so this watchdog is not running'));
      expect(isRouterLogError('Oct 29 15:10:00 cfg-pia-wg: $line'), isTrue, reason: 'red in the app\'s router log');
      expect(h.log.any((l) => l.startsWith('ERROR: watchdog_wgc1.sh is damaged')), isTrue);
      expect(h.tmp('watchdog_lastfault_wgc1').readAsStringSync(), contains('is damaged'));
      expect(h.log.any((l) => l.startsWith('Watchdog started')), isFalse);
    }, skip: skip);

    test('control: with the check taken out, the same cut-short script is as silent as on 2026-10-29', () async {
      await h.run(edit: (s) => cutShort(noSelfCheck(s)));
      expect(h.syslog.any((l) => l.contains('ERROR')), isFalse, reason: 'the test can tell the check from its absence');
      expect(h.log.any((l) => l.contains('is damaged')), isFalse);
    }, skip: skip);

    test('a cut as early as the 2026-10-29 one is still logged: the check is in the first 7,940 bytes', () async {
      final s = buildWatchdogScript(
          const WatchdogConfig(slotIndex: 5, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
          firmware: RouterFirmware.stock);
      expect(s.indexOf('# -- Faults:'), lessThan(7940), reason: 'the logging half of the check sits above it');
      // And the email half, on both firmwares: a cut that size gets the email too (measured 2026-11-01:
      // the block ended at 6,547 bytes on stock and 6,852 on Merlin).
      for (final fw in [RouterFirmware.stock, RouterFirmware.merlin]) {
        final f = buildWatchdogScript(
            const WatchdogConfig(slotIndex: 5, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
            firmware: fw);
        expect(utf8.encode(f.substring(0, f.indexOf('# The slots whose devices the guard protects'))).length, lessThan(7940),
            reason: '$fw');
      }
      // Cut on the line just past the check, before any of the fault code.
      await h.run(edit: (t) => t.substring(0, t.indexOf('# -- Faults:')));
      expect(h.syslog.any((l) => l.startsWith('wgc1: ERROR: watchdog_wgc1.sh is damaged (')), isTrue, reason: h.syslog.join('\n'));
    }, skip: skip);

    test('control: the whole script says nothing of the kind', () async {
      final r = await h.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(h.syslog.any((l) => l.contains('ERROR')), isFalse, reason: h.syslog.join('\n'));
      expect(h.log.any((l) => l.startsWith('Watchdog started')), isTrue);
    }, skip: skip);

    test('emails with alerts on, then waits out the backoff ladder before the next', () async {
      h.captureMail();
      await h.run(edit: cutShort);
      expect(h.mails, hasLength(1));
      expect(h.mails.first, contains('Event: watchdog_wgc1.sh is damaged'));
      expect(h.mails.first, contains('WHAT TO DO'));
      await h.run(edit: cutShort);
      expect(h.mails, hasLength(1), reason: 'the second, at once, is inside the first rung');
      expect(h.syslog.where((l) => l.contains('is damaged')), hasLength(2), reason: 'but logged every run');
      h.tmp('watchdog_fault_wgc1').writeAsStringSync('1\n${now() - 130}\n');
      await h.run(edit: cutShort);
      expect(h.mails, hasLength(2), reason: '130 s is past the first rung, 120 s');
      expect(h.tmp('watchdog_fault_wgc1').readAsLinesSync().first, '2');
    }, skip: skip);

    test('no email with alerts off', () async {
      h.captureMail();
      h.set('wgc1_wd_email_enabled', '0');
      await h.run(edit: cutShort);
      expect(h.mails, isEmpty);
      expect(h.syslog.any((l) => l.contains('is damaged')), isTrue);
    }, skip: skip);
  });

  group('errors a run left behind (ID-485)', () {
    const syntax = 'watchdog_wgc1.sh: line 812: syntax error: unexpected end of file';

    test("a finished run's errors are reported once, red, and emailed", () async {
      h.captureMail();
      h.tmp('watchdog_wgc1.err.$kGonePid').writeAsStringSync('$syntax\n');
      final r = await h.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final line = h.syslog.firstWhere((l) => l.contains('script error'), orElse: () => '');
      expect(line, "wgc1: ERROR: This watchdog's last run reported a script error: [$syntax]");
      expect(isRouterLogError('Oct 29 15:10:00 cfg-pia-wg: $line'), isTrue);
      expect(h.mails, hasLength(1));
      expect(h.mails.first, contains(syntax));
      expect(h.tmpFiles.where((f) => f.startsWith('watchdog_wgc1.err.')), isEmpty);
      await h.run();
      expect(h.syslog.where((l) => l.contains('script error')), hasLength(1), reason: 'reported once');
      expect(h.tmp('watchdog_fault_wgc1').existsSync(), isFalse, reason: 'a clean run resets the email ladder');
    }, skip: skip);

    // End to end: a detached run, as cron's copy is, that really stops on a syntax error. The
    // self-check is taken out so the shell, not the check, is what meets the cut.
    String brokenRun(String s) => cutShort(noSelfCheck(s));

    test("a detached run's own syntax error is kept, and the next run reports it", () async {
      await h.run(mode: 'detached', edit: brokenRun);
      final kept = h.tmpFiles.where((f) => f.startsWith('watchdog_wgc1.err.')).toList();
      expect(kept, hasLength(1));
      expect(h.tmp(kept.single).readAsStringSync(), isNotEmpty);
      await h.run();
      expect(h.syslog.any((l) => l.startsWith("wgc1: ERROR: This watchdog's last run reported a script error: [")), isTrue,
          reason: h.syslog.join('\n'));
    }, skip: skip);

    test('control: without the redirect, the same error is lost, as it was', () async {
      await h.run(
          mode: 'detached',
          // The detached copy's redirect, the first of the two; the harness has already moved /tmp.
          edit: (s) => brokenRun(s.replaceFirst(RegExp(r'  exec 2>>"[^"]*/watchdog_wgc1\.err\.\$\$"'), '  :')));
      expect(h.tmpFiles.where((f) => f.startsWith('watchdog_wgc1.err.')), isEmpty);
    }, skip: skip);

    test('a run still going is left alone', () async {
      // A real process, so `kill -0` finds it.
      final p = await startSh(shell!, ['-c', r'echo $$; exec sleep 20']);
      final pid = (await p.stdout.transform(const SystemEncoding().decoder).first).trim();
      try {
        h.tmp('watchdog_wgc1.err.$pid').writeAsStringSync('$syntax\n');
        await h.run();
        expect(h.syslog.any((l) => l.contains('script error')), isFalse);
        expect(h.tmp('watchdog_wgc1.err.$pid').existsSync(), isTrue);
      } finally {
        p.kill();
      }
    }, skip: Platform.isWindows && !usesWsl ? 'Git Bash and the test see different process ids' : skip);

    test("the guard's and the boot script's are claimed, and emailed by each guarded slot", () async {
      h.captureMail();
      // A device pinned to wgc1's tunnel, whose table is 9 in the clientlist.
      h.set('vpnc_dev_policy_list', '<1>192.168.1.50>>9');
      h.tmp('cfg-pia-wg-guard.err.$kGonePid').writeAsStringSync('RTNETLINK answers: Operation not permitted\n');
      h.tmp('cfg-pia-wg-boot.err.$kGonePid').writeAsStringSync('S50downloadmaster: line 3: oops\n');
      await h.run();
      expect(h.syslog, contains('wgc1: ERROR: The fail-closed guard reported a script error: [RTNETLINK answers: Operation not permitted]'));
      expect(h.syslog, contains('wgc1: ERROR: The boot script reported a script error: [S50downloadmaster: line 3: oops]'));
      expect(h.mails, hasLength(1), reason: 'the second inside the backoff');
      expect(h.tmpFiles.where((f) => f.contains('.err.')), isEmpty);
    }, skip: skip);

    test('a healthy deploy, a rebuild and a detached run leave no error behind', () async {
      for (final mode in ['deploy', 'detached']) {
        final r = await h.run(mode: mode);
        expect(r.exitCode, 0, reason: '$mode: ${r.stdout}${r.stderr}');
      }
      h.tunnelDown();
      await h.run(mode: 'deploy');
      final left = h.tmpFiles.where((f) => f.contains('.err.')).toList();
      expect(left, isEmpty, reason: [for (final f in left) h.tmp(f).readAsStringSync()].join('\n'));
    }, skip: skip);
  });

  // ID-547: an awk that exits at its first match closes the pipe while the writer may still be
  // writing. Where SIGPIPE is ignored, the writer then prints "write error: Broken pipe", a detached
  // run keeps that in its .err file, and the next run reports it as a script error. Reading to the
  // end of the input instead takes the race away.
  test('no awk reading a pipe stops before the end of it (ID-547)', () {
    bool earlyExit(String line) =>
        RegExp(r'\|\s*awk\b.*\bexit\b').hasMatch(line) && !RegExp(r'END\s*\{\s*exit').hasMatch(line);
    for (final fw in [RouterFirmware.stock, RouterFirmware.merlin]) {
      final s = buildWatchdogScript(
          const WatchdogConfig(slotIndex: 1, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
          firmware: fw);
      expect(s.split('\n').where(earlyExit), isEmpty, reason: '$fw watchdog');
    }
    expect(kGuardScript.split('\n').where(earlyExit), isEmpty, reason: 'guard');
  });

  test("check-claims' control edits a line the script really has (ID-485)", () {
    final claims = File('scripts/check-claims.sh').readAsStringSync();
    expect(claims, contains(r"sed 's#^for EF in /tmp/watchdog_#for EF in /nonexistent/watchdog_#'"));
    final s = buildWatchdogScript(
        const WatchdogConfig(slotIndex: 1, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'),
        firmware: RouterFirmware.stock);
    expect(s.split('\n').where((l) => l.startsWith('for EF in /tmp/watchdog_')), hasLength(1),
        reason: 'or the control would take nothing out, and pass for the wrong reason');
  });

  group('fault mode: another script reporting through this slot (ID-484)', () {
    test('emails the sentence and does nothing else', () async {
      h.captureMail();
      final r = await h.run(mode: 'fault', args: ['guard.sh is damaged (900 bytes, and its last line is missing)']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(h.mails, hasLength(1));
      expect(h.mails.first, contains('Event: guard.sh is damaged (900 bytes'));
      expect(h.log, isEmpty, reason: 'no check was run');
      expect(h.syslog, ['wgc1: Fault alert email sent']);
    }, skip: skip);
  });
}
