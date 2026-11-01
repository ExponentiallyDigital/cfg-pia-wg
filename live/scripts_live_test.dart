// live/scripts_live_test.dart - TESTING.md's ABT-6 to ABT-9, GRD-10 and LOG-8, run unattended against a
// real router (ID-492). The scripts that check themselves, and the app's check of them (ID-482 to ID-488).
//
//   $env:CFG_LIVE_PASS = Read-Host -MaskInput 'Router password'
//   $env:CFG_LIVE_ROUTER = '<router>:22'; $env:CFG_LIVE_USER = '<login>'; $env:CFG_LIVE_GO = '1'
//   flutter test live/scripts_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER and CFG_LIVE_PASS are
// set; without CFG_LIVE_GO=1 it checks the start state, prints the plan and changes nothing. It makes the
// router calls the app makes, through the app's own code, and runs the router's scripts as cron does,
// rather than waiting for cron. Each test puts back what it changed, whatever happens, and the run ends
// by checking every script on the router is whole. The on-screen half of each test (the snackbar, the
// red ABOUT row, the held back key, the widget) is covered by the widget tests in CI and stays a hand
// step in TESTING.md. With email alerts on, ABT-7, LOG-8 and GRD-10 send real alert emails: that is
// part of what they test. The log goes to .claude/testing/, which git ignores.
//
// Start state: stock firmware; wgc1's and wgc5's watchdogs deployed by build 554 or later, both tunnels
// answering; the fail-closed guard installed. About 4 minutes, most of it ABT-9's 60-second wait.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_script_integrity.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show openSshClient;
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/widget_status_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS'];
const _guard = '$kRouterAppDir/guard.sh';

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  test('the scripts on a live router', () async {
    final run = _ScriptsRun(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!,
        allowed: env['CFG_LIVE_GO']?.trim() == '1', only: (env['CFG_LIVE_ONLY'] ?? '').trim());
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

class _ScriptsRun {
  _ScriptsRun(this.router, this.user, this.pass, {required this.allowed, this.only = ''});

  final String router, user, pass;
  final bool allowed;

  /// CFG_LIVE_ONLY: a comma-separated list of the steps to run, such as `ID-485`; empty runs them all.
  final String only;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  late final SSHClient _client;
  bool _connected = false;

  /// The app log, as the app would write it, for the checks of what the app says.
  final List<(String, bool)> _appLog = [];

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    _log.writeln(line);
  }

  void _result(String id, bool pass, String why) {
    _say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
    if (!pass) failures.add('$id: $why');
  }

  void _onLog(String message, {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    _appLog.add((message, isError));
    _log.writeln('  app log${isError ? ' (red)' : ''}: $message');
  }

  Future<String> _sh(String cmd) async => (await runRouterCommand(_client, cmd, allowFailure: true)).stdout.trim();

  RouterWatchdog get _wd => RouterWatchdog(_client, onLog: _onLog);

  /// Where the router's log stands, so a check reads only what came after.
  Future<int> _mark() async => int.tryParse(await _sh('wc -l < /tmp/syslog.log')) ?? 0;
  Future<String> _since(int mark) => _sh('tail -n +${mark + 1} /tmp/syslog.log');

  Future<bool> _whole(String path, String name) async => (await _sh("tail -n 1 '$path'")) == scriptEndLine(name);
  Future<String> _header(String path) => _sh("sed -n 2p '$path'");
  Future<bool> _answering(int slot) async {
    final ages = parseHandshakeAgesForLive(await _sh('echo "\$(date +%s)"; wg show wgc$slot latest-handshakes 2>/dev/null'));
    return ages != null && ages < 180;
  }

  Future<bool> _alertsOn(int slot) async => await _sh('nvram get wgc${slot}_wd_email_enabled') == '1';

  /// Runs [path] as cron's detached copy would, but attached: `foreground`. Returns its exit status.
  Future<int> _runScript(String path, [String mode = 'foreground']) async =>
      int.tryParse((await _sh("/bin/sh '$path' $mode >/dev/null 2>&1; echo \$?")).split('\n').last) ?? -1;

  int _count(String text, String needle) => needle.allMatches(text).length;

  Future<void> go() async {
    _say('Connecting to $router as $user...');
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(router, user, pass, hostKeys: keys);
    _connected = true;
    final firmware = classifyFirmwareTag(await _sh('nvram get 3rd-party'));
    if (firmware != RouterFirmware.stock) {
      _result('START', false, 'this run is for stock firmware, and this router is ${firmware == null ? 'not supported' : 'Merlin'}');
      return;
    }
    setRouterFirmware(firmware!);

    // The version the router's scripts carry is the one the app would write: this checkout's code
    // stamped with it, so a replaced script is the same script.
    final w1 = watchdogScriptPath(1), w5 = watchdogScriptPath(5);
    final version = parseScriptVersion(await _header(w1));
    final start = <String, bool>{
      'wgc1 script whole, build 554 or later': (scriptBuild(version) ?? 0) >= kFirstBuildWithEndLine && await _whole(w1, 'watchdog_wgc1.sh'),
      'wgc5 script whole': await _whole(w5, 'watchdog_wgc5.sh'),
      'guard.sh whole': await _whole(_guard, 'guard.sh'),
      'wgc1 answering': await _answering(1),
      'wgc5 answering': await _answering(5),
    };
    for (final e in start.entries) {
      _say('START ${e.value ? 'ok  ' : 'NOT '} ${e.key}');
    }
    _say('Scripts at ${version ?? 'no version'}; alert emails: wgc1 ${await _alertsOn(1) ? 'on' : 'off'}, wgc5 ${await _alertsOn(5) ? 'on' : 'off'}.');
    if (start.values.contains(false)) {
      _result('START', false, 'the start state is not there: open the app and connect so it updates the scripts, and check both tunnels are up');
      return;
    }
    appVersionLabel = version!;
    if (!allowed) {
      _say('The plan, not run. Set CFG_LIVE_GO=1 to run it:');
      _say('  ABT-6  wgc1 made older, the app updates it; made newer, the app leaves it.');
      _say('  ABT-7  wgc1 cut to 7940 bytes, run twice: red line, one email; the app sees it; the widget sees it; the app replaces it.');
      _say('  LOG-8  an error left for wgc1, run twice: reported once, red; the app logs it.');
      _say('  ABT-8  an update of wgc1 that loses the router part-way: wgc1 unchanged, the failure written late.');
      _say('  ABT-9  wgc5 replaced while a run of it waits: the run finishes, no error.');
      _say('  GRD-10 guard.sh cut to 4000 bytes and run: red line, an email per guarded slot with alerts; the app sees it.');
      _say('  ID-485 three copies of wgc1, each failing for real at its start, part-way or at its end, run as cron runs it: three red lines.');
      return;
    }

    for (final (name, step) in [
      ('ABT-6', _abt6),
      ('ABT-7', _abt7),
      ('LOG-8', _log8),
      ('ABT-8', _abt8),
      ('ABT-9', _abt9),
      ('GRD-10', _grd10),
      ('ID-485', _id485),
    ]) {
      if (only.isNotEmpty && !only.split(',').map((x) => x.trim()).contains(name)) continue;
      _say('---- $name');
      final mark = await _mark();
      await _sh('logger "**$name START** live/scripts_live_test.dart"');
      try {
        await step();
      } catch (e) {
        _result(name, false, 'stopped: $e');
      }
      await _sh('logger "**$name END** live/scripts_live_test.dart"');
      _log.writeln('  router log:\n${(await _since(mark)).split('\n').map((l) => '    $l').join('\n')}');
    }

    // The end state: everything whole again.
    _say('---- END');
    final health = parseScriptHealth(await _sh(kScriptHealthCommand));
    _result('END', health.damaged.isEmpty && await _whole(w1, 'watchdog_wgc1.sh') && await _whole(w5, 'watchdog_wgc5.sh') && await _whole(_guard, 'guard.sh'),
        'every script on the router whole: ${health.all.map((s) => '${s.fileName} ${s.size}').join(', ')}');
  }

  /// Puts wgc1's script back as the app writes it.
  Future<void> _restore(int slot) async {
    await _wd.redeployScripts(only: {slot});
  }

  // ABT-6: the app updates an older script by itself, and never a newer one.
  Future<void> _abt6() async {
    final f = watchdogScriptPath(1);
    try {
      await _sh("sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v0.0.1 build 1;/' '$f'");
      final mark = await _mark();
      final r = await checkRouterScripts(_client, canUpdate: true, onLog: _onLog);
      _result('ABT-6 older', r.updated.contains('watchdog_wgc1.sh') && parseScriptVersion(await _header(f)) == appVersionLabel,
          'a build 1 script is replaced: updated ${r.updated}, now ${parseScriptVersion(await _header(f))}');
      final logged = await _since(mark);
      _result('ABT-6 logged', logged.contains('Watchdog script updated automatically to $appVersionLabel for wgc1'),
          'the router log says it was updated automatically');
      await _sh("sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v9.9.99 build 9999;/' '$f'");
      final r2 = await checkRouterScripts(_client, canUpdate: true, onLog: _onLog);
      _result('ABT-6 newer', !r2.updated.contains('watchdog_wgc1.sh') && (await _header(f)).contains('build 9999'),
          'a build 9999 script is left alone: updated ${r2.updated}');
    } finally {
      await _restore(1);
    }
  }

  // ABT-7: a script cut short where 2026-10-29's was.
  Future<void> _abt7() async {
    final f = watchdogScriptPath(1);
    const whole = '/tmp/cfgpia-live-wgc1.whole';
    final alerts = await _alertsOn(1);
    try {
      await _sh("cp '$f' $whole && dd if=$whole of='$f' bs=7940 count=1 2>/dev/null");
      _result('ABT-7 cut', await _sh("wc -c < '$f'") == '7940', 'wgc1 cut to 7940 bytes');
      final mark = await _mark();
      final rc1 = await _runScript(f);
      final rc2 = await _runScript(f);
      final logged = await _since(mark);
      _result('ABT-7 exit', rc1 == 1 && rc2 == 1, 'each run stops, exit 1: $rc1 and $rc2');
      final red = 'wgc1: ERROR: watchdog_wgc1.sh is damaged (7940 bytes, and its last line is missing), so this watchdog is not running.';
      _result('ABT-7 red', _count(logged, red) >= 2, 'each run logs it, red (${_count(logged, red)} lines)');
      _result('ABT-7 kept', (await _sh('cat /tmp/watchdog_lastfault_wgc1')).contains('is damaged'), 'kept for the app');
      if (alerts) {
        final sent = _count(logged, 'wgc1: Fault alert email sent');
        final failed = _count(logged, 'wgc1: Fault alert email FAILED');
        _result('ABT-7 email', sent + failed == 1 && sent == 1, 'one email, the second inside the backoff: sent $sent, failed $failed');
      } else {
        _say('ABT-7 email SKIP: wgc1 alerts are off');
      }
      _appLog.clear();
      final r = await checkRouterScripts(_client, canUpdate: false, onLog: _onLog);
      _result('ABT-7 app', r.unfixed.any((u) => u.startsWith('watchdog_wgc1.sh on the router is damaged (7940 bytes')) &&
          _appLog.any((l) => l.$2 && l.$1.startsWith('ERROR: watchdog_wgc1.sh on the router is damaged')),
          'the app finds it, red, and an unpaid app leaves it for the banner');
      final widget = await WidgetStatusService(_client).read();
      final row = widget.tunnels.where((t) => t.slot == 1);
      _result('ABT-7 widget', row.isNotEmpty && row.first.watchdogBroken, "the widget's read calls wgc1's watchdog broken");
      final fix = await checkRouterScripts(_client, canUpdate: true, onLog: _onLog);
      _result('ABT-7 replaced', fix.updated.contains('watchdog_wgc1.sh') && await _whole(f, 'watchdog_wgc1.sh'), 'a paid app replaces it');
      final after = await _mark();
      final rc3 = await _runScript(f);
      _result('ABT-7 quiet', rc3 == 0 && !(await _since(after)).contains('is damaged'), 'the next run is a normal one: exit $rc3');
    } finally {
      if (!await _whole(f, 'watchdog_wgc1.sh')) await _restore(1);
      await _sh('rm -f $whole');
    }
  }

  // LOG-8: an error a finished run left behind is reported, once, and reaches the app.
  Future<void> _log8() async {
    final f = watchdogScriptPath(1);
    const ef = '/tmp/watchdog_wgc1.err.4194999';
    final alerts = await _alertsOn(1);
    try {
      final mark = await _mark();
      await _sh("echo 'LOG-8 test error' > $ef");
      await _runScript(f);
      await _runScript(f);
      final logged = await _since(mark);
      const line = "wgc1: ERROR: This watchdog's last run reported a script error: [LOG-8 test error]";
      _result('LOG-8 red', _count(logged, line) == 1, 'reported once, red (${_count(logged, line)} lines)');
      _result('LOG-8 gone', (await _sh('[ -f $ef ] && echo left || echo gone')) == 'gone', 'its file is gone');
      if (alerts) {
        _result('LOG-8 email', _count(logged, 'wgc1: Fault alert email sent') == 1, 'one email');
      } else {
        _say('LOG-8 email SKIP: wgc1 alerts are off');
      }
      _appLog.clear();
      await checkRouterScripts(_client, canUpdate: false, onLog: _onLog, seenFaults: {});
      _result('LOG-8 app', _appLog.any((l) => l.$2 && l.$1.contains("wgc1's watchdog reported at") && l.$1.contains('[LOG-8 test error]')),
          'the app log has it, red');
    } finally {
      await _sh('rm -f $ef');
    }
  }

  // ABT-8: an update that loses the router part-way, as a phone's Wi-Fi going off does.
  Future<void> _abt8() async {
    final f = watchdogScriptPath(1);
    clearKeptRouterLog();
    try {
      await _sh("sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v0.0.1 build 1;/' '$f'");
      final dropping = _DroppingClient(_client);
      var threw = false;
      try {
        await RouterWatchdog(dropping, onLog: _onLog).redeployScripts(only: {1});
      } catch (_) {
        threw = true;
      }
      _result('ABT-8 failed', threw && dropping.dropped, 'the update failed when the router went away, after ${dropping.pieces} piece(s)');
      _result('ABT-8 unchanged', (await _header(f)).contains('build 1;') && await _whole(f, 'watchdog_wgc1.sh'),
          'wgc1 is still the older script, whole');
      _result('ABT-8 kept', keptRouterLogCount == 1, 'the failure is kept for the router log ($keptRouterLogCount line)');
      final mark = await _mark();
      await _wd.flushKeptRouterLog();
      final logged = await _since(mark);
      _result('ABT-8 late', logged.contains('ERROR during update of the watchdog scripts') && logged.contains('logged late'),
          'written at the next connection, with when it happened');
      final left = await _sh("ls '$f'.new.* 2>/dev/null | wc -l");
      _say('ABT-8 info: $left temporary file(s) left beside it, removed by the next write');
      await _restore(1);
      _result('ABT-8 retry', parseScriptVersion(await _header(f)) == appVersionLabel && await _sh("ls '$f'.new.* 2>/dev/null | wc -l") == '0',
          'the next update works, and nothing is left beside it');
    } finally {
      clearKeptRouterLog();
      await _restore(1);
    }
  }

  // ABT-9: wgc5 replaced while a run of it is part-way through. Its detached copy waits 60 s, by slot
  // (ID-227), before it reads the rest of the script; the script is replaced during that wait.
  Future<void> _abt9() async {
    final f = watchdogScriptPath(5);
    final inode = await _sh("ls -i '$f' | awk '{print \$1}'");
    final logBefore = int.tryParse(await _sh('wc -l < /tmp/watchdog_wgc5.log 2>/dev/null || echo 0')) ?? 0;
    final pid = await _sh("/bin/sh '$f' detached </dev/null >/dev/null 2>&1 & echo \$!");
    _say('ABT-9: run $pid started; replacing the script during its wait');
    await Future.delayed(const Duration(seconds: 15));
    await _restore(5);
    final replaced = await _sh("ls -i '$f' | awk '{print \$1}'");
    _result('ABT-9 replaced', replaced != inode && await _whole(f, 'watchdog_wgc5.sh'), 'a new file in place: inode $inode -> $replaced');
    var waited = 0;
    while (waited < 150 && (await _sh('kill -0 $pid 2>/dev/null && echo running')) == 'running') {
      await Future.delayed(const Duration(seconds: 5));
      waited += 5;
    }
    final ran = await _sh('tail -n +${logBefore + 1} /tmp/watchdog_wgc5.log');
    final err = await _sh('cat /tmp/watchdog_wgc5.err.$pid 2>/dev/null');
    _result('ABT-9 finished', ran.contains('Watchdog started for wgc5') && ran.contains('Router resolver') && err.isEmpty,
        'the run finished normally${err.isEmpty ? '' : ', but wrote: $err'}');
  }

  // ID-485's DoD on the router: a script made to fail at its start, part-way and at its end gives the
  // red line each time. Three copies of wgc1's script, each with a command that does not exist put in
  // one of those places, run detached as cron's copy runs, so its stderr is the captured kind; then
  // wgc1's own script, which reports what each left. wgc1's alerts are off meanwhile, and put back.
  Future<void> _id485() async {
    final f = watchdogScriptPath(1);
    final alerts = await _sh('nvram get wgc1_wd_email_enabled');
    final body = await _sh("cat '$f'");
    String at(String s, String marker, String add, {bool before = false}) {
      final i = s.indexOf(marker);
      if (i < 0) throw StateError('no "$marker" in wgc1\'s script');
      return before ? s.replaceRange(i, i, add) : s.replaceRange(i + marker.length, i + marker.length, add);
    }

    final success = body.indexOf('# Success: update status');
    // The healthy run's last step before it exits: the end of a normal run.
    const backoffReset = r'''printf '0\n0\n' > "$BACKOFFFILE"''' '\n';
    final places = <String, String>{
      'start': at(body, '  exec 2>>"/tmp/watchdog_wgc1.err.\$\$"\n', '  cfgpia_test_fail_start\n'),
      'part-way': at(body, 'log "Watchdog started for', 'cfgpia_test_fail_middle\n', before: true),
      'end': body.substring(0, success) + at(body.substring(success), backoffReset, '  cfgpia_test_fail_end\n'),
    };
    final names = {'start': 'cfgpia_test_fail_start', 'part-way': 'cfgpia_test_fail_middle', 'end': 'cfgpia_test_fail_end'};
    try {
      await _sh('nvram set wgc1_wd_email_enabled=0');
      for (final e in places.entries) {
        final copy = '/tmp/cfgpia-live-485-${e.key}.sh';
        await writeRouterFile(
            path: copy,
            body: e.value,
            what: 'test copy',
            mode: '+x',
            run: (cmd) async => (await runRouterCommand(_client, cmd)).stdout.trim(),
            read: _sh);
        final mark = await _mark();
        final pid = await _sh("/bin/sh $copy detached </dev/null >/dev/null 2>&1 & echo \$!");
        var waited = 0;
        while (waited < 120 && (await _sh('kill -0 $pid 2>/dev/null && echo running')) == 'running') {
          await Future.delayed(const Duration(seconds: 3));
          waited += 3;
        }
        await _runScript(f);
        final logged = await _since(mark);
        final line = logged.split('\n').firstWhere(
            (l) => l.contains("wgc1: ERROR: This watchdog's last run reported a script error: [") && l.contains(names[e.key]!),
            orElse: () => '');
        _result('ID-485 ${e.key}', line.isNotEmpty,
            line.isEmpty ? 'no red line for a run that failed ${e.key}' : 'a run that failed ${e.key} was reported, red: ${line.substring(line.indexOf('reported'))}');
        await _sh('rm -f $copy');
      }
    } finally {
      await _sh('nvram set wgc1_wd_email_enabled=$alerts');
      await _sh('rm -f /tmp/cfgpia-live-485-*.sh /tmp/watchdog_fault_wgc1');
    }
  }

  // GRD-10: a damaged guard says so, and each guarded slot with alerts on emails.
  Future<void> _grd10() async {
    const whole = '/tmp/cfgpia-live-guard.whole';
    final guarded = (await _sh(kGuardedSlotsShell)).split(RegExp(r'\s+')).where((s) => s.isNotEmpty).map(int.parse).toList();
    final emailers = [for (final s in guarded) if (await _alertsOn(s)) s];
    try {
      await _sh("cp '$_guard' $whole && dd if=$whole of='$_guard' bs=4000 count=1 2>/dev/null");
      final mark = await _mark();
      final rc = int.tryParse(await _sh("/bin/sh '$_guard' >/dev/null 2>&1; echo \$?")) ?? -1;
      final logged = await _since(mark);
      _result('GRD-10 exit', rc == 1, 'the cut guard stops, exit $rc');
      _result('GRD-10 red', logged.contains('ERROR: guard.sh is damaged (4000 bytes, and its last line is missing), so the fail-closed guard is not running.'),
          'it logs it, red');
      for (final s in emailers) {
        _result('GRD-10 wgc$s', logged.contains('wgc$s: Fault alert email sent'), "wgc$s's settings email it");
      }
      if (emailers.isEmpty) _say('GRD-10 email SKIP: no guarded slot ($guarded) has alerts on');
      _appLog.clear();
      final r = await checkRouterScripts(_client, canUpdate: false, onLog: _onLog);
      _result('GRD-10 app', r.unfixed.any((u) => u.startsWith('guard.sh on the router is damaged (4000 bytes')), 'the app finds it');
    } finally {
      await _sh("[ -f $whole ] && cp $whole '$_guard'; rm -f $whole");
      final back = await _sh("/bin/sh '$_guard' 2>/dev/null | grep -o 'guarded [0-9]* of [0-9]*'");
      final m = RegExp(r'guarded (\d+) of (\d+)').firstMatch(back);
      _result('GRD-10 back', m != null && m.group(1) == m.group(2) && await _whole(_guard, 'guard.sh'), 'the whole guard is back: $back');
    }
  }

  Future<void> close() async {
    if (_connected) _client.close();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_scripts.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }
}

/// The router's clock and a tunnel's newest handshake, as `date +%s` then `wg show ... latest-handshakes`
/// print them, as the handshake's age in seconds; null when it never had one.
int? parseHandshakeAgesForLive(String out) {
  final lines = out.split('\n');
  final now = int.tryParse(lines.first.trim());
  final newest = lines.skip(1).map((l) => int.tryParse(l.trim().split(RegExp(r'\s+')).last) ?? 0).fold(0, (a, b) => b > a ? b : a);
  return now == null || newest == 0 ? null : now - newest;
}

/// The router, until the third piece of a script write: then it is gone, as when the phone's Wi-Fi goes
/// off part-way through an update. Every command after that fails as a dropped connection does.
class _DroppingClient implements SSHClient {
  _DroppingClient(this._real);

  final SSHClient _real;
  int pieces = 0;
  bool dropped = false;

  void _maybeDrop(String command) {
    if (dropped) throw SSHStateError('Connection closed');
    if (command.startsWith('cat ') && command.contains('.new.')) {
      pieces++;
      if (pieces == 3) {
        dropped = true;
        throw SSHStateError('Connection closed');
      }
    }
  }

  @override
  Future<SSHRunResult> runWithResult(String command,
      {bool runInPty = false, bool stdout = true, bool stderr = true, Map<String, String>? environment}) async {
    _maybeDrop(command);
    return _real.runWithResult(command, runInPty: runInPty, stdout: stdout, stderr: stderr, environment: environment);
  }

  @override
  Future<Uint8List> run(String command,
      {Map<String, String>? environment, bool runInPty = false, bool stderr = true, bool stdout = true}) async {
    _maybeDrop(command);
    return _real.run(command, environment: environment, runInPty: runInPty, stderr: stderr, stdout: stdout);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
