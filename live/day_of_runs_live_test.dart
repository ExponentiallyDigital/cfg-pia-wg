// live/day_of_runs_live_test.dart - TESTING LOG-9: a day of watchdog runs reports no script error
// (ID-485, ID-494). Reads only; changes nothing on the router.
//
//   $env:CFG_LIVE_PASS = Read-Host -MaskInput 'Router password'
//   $env:CFG_LIVE_ROUTER = '<router>:22'; $env:CFG_LIVE_USER = '<login>'
//   flutter test live/day_of_runs_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER and CFG_LIVE_PASS are
// set. Since build 554 every error a script writes is reported, so what the router's own commands write
// to stderr in normal running, never measured before, now shows: this measures it over a day. It reads
// each scheduled watchdog's own log, today's and yesterday's (`/tmp/watchdog_wgcN.log` and `.old`,
// rotated at midnight), whose lines carry the full date, so a day of runs is there however busy the
// router's log has been. It passes when every scheduled watchdog has run a script from build 554 on for
// at least 24 hours, with no "reported a script error" line among those runs bar the ones the tests
// leave on purpose (LOG-8's, check-claims' and the live runners'), and no error file left behind by a
// run that has finished. Too short a span is a FAIL that says when to run it again.
//
// With CFG_LIVE_GO=1 it runs the active version instead, Andrew's choice of 2026-11-01 (ID-485): the
// paths a quiet day never takes, run now. A forced rebuild of each scheduled watchdog's tunnel, each
// run detached as cron runs it (the peer taken off, as check-claims does, so the run rebuilds it), and
// a firewall restart, which runs the boot script's firewall-start path and the guard. Then each
// watchdog runs once more to report what those runs left. It passes when every rebuild succeeds and
// no script error is reported, by those runs or by any build 554 or later run in the watchdogs' logs,
// bar the tests' own. Each tunnel drops for a few seconds and makes one PIA login; with alerts on,
// each rebuild sends its usual "rebuilt" email.
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart' show kRouterAppDir;
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_script_integrity.dart' show kFirstBuildWithEndLine;
import 'package:cfg_pia_wg/router_slot_service.dart' show openSshClient;
import 'package:flutter_test/flutter_test.dart';

import 'day_of_runs.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS'];

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  final active = env['CFG_LIVE_GO']?.trim() == '1';
  test('LOG-9: a day of watchdog runs, on a live router', () async {
    final failures = <String>[];
    final out = StringBuffer();
    void say(String l) {
      // ignore: avoid_print
      print(l);
      out.writeln(l);
    }

    void result(String id, bool pass, String why) {
      say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
      if (!pass) failures.add('$id: $why');
    }

    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    final client = await openSshClient(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!, hostKeys: keys);
    Future<String> sh(String cmd) async => (await runRouterCommand(client, cmd, allowFailure: true)).stdout.trim();
    try {
      final slots = [for (final m in RegExp(r'#watchdog_wgc([1-5])#').allMatches(await sh('cru l'))) int.parse(m.group(1)!)]..sort();
      final now = DateTime.tryParse((await sh("date '+%Y-%m-%dT%H:%M:%S'")).trim()) ?? DateTime.now();
      if (slots.isEmpty) result('LOG-9', false, 'no watchdog is scheduled');
      for (final s in slots) {
        final r = dayOfRuns(await sh('cat /tmp/watchdog_wgc$s.log.old /tmp/watchdog_wgc$s.log 2>/dev/null'));
        final span = r.first == null ? Duration.zero : now.difference(r.first!);
        final hours = (span.inMinutes / 60).toStringAsFixed(1);
        if (span < const Duration(hours: 24)) {
          final ready = r.first?.add(const Duration(hours: 24));
          result('LOG-9 wgc$s span', false,
              'only ${hours}h of runs from build $kFirstBuildWithEndLine on (${r.runs} runs since ${r.first ?? 'none'})'
              '${ready == null ? '' : '; run this again after $ready'}');
        } else {
          result('LOG-9 wgc$s span', true, '${hours}h of runs, ${r.runs} of them, from ${r.first} to ${r.last}');
        }
        result('LOG-9 wgc$s errors', r.errors.isEmpty,
            r.errors.isEmpty ? 'no script error reported in those runs' : '${r.errors.length} reported:\n  ${r.errors.join('\n  ')}');
      }
      // Error files left by runs that have finished: the next run should have taken each one.
      final left = await sh(r'for f in /tmp/watchdog_wgc*.err.* /tmp/cfg-pia-wg-guard.err.* /tmp/cfg-pia-wg-boot.err.*; do '
          r'[ -f "$f" ] || continue; p="${f##*.}"; kill -0 "$p" 2>/dev/null || echo "$f"; done');
      result('LOG-9 files', left.isEmpty, left.isEmpty ? 'no error file left by a finished run' : 'left: $left');
    } finally {
      client.close();
      final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
      final f = File('.claude/testing/${stamp}_live_log9.log');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(out.toString());
      say('Log: ${f.path}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, skip: missing.isNotEmpty ? 'set ${missing.join(', ')}' : (active ? 'CFG_LIVE_GO=1 runs the active version instead' : false));

  test('LOG-9 active: rebuilds and a firewall restart report no script error, on a live router', () async {
    final failures = <String>[];
    final out = StringBuffer();
    void say(String l) {
      // ignore: avoid_print
      print(l);
      out.writeln(l);
    }

    void result(String id, bool pass, String why) {
      say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
      if (!pass) failures.add('$id: $why');
    }

    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    final client = await openSshClient(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!, hostKeys: keys);
    Future<String> sh(String cmd) async => (await runRouterCommand(client, cmd, allowFailure: true)).stdout.trim();
    Future<void> waitGone(String pid, int seconds) async {
      var waited = 0;
      while (waited < seconds && (await sh('kill -0 $pid 2>/dev/null && echo running')) == 'running') {
        await Future.delayed(const Duration(seconds: 3));
        waited += 3;
      }
    }

    try {
      final slots = [for (final m in RegExp(r'#watchdog_wgc([1-5])#').allMatches(await sh('cru l'))) int.parse(m.group(1)!)]..sort();
      if (slots.isEmpty) {
        result('LOG-9', false, 'no watchdog is scheduled');
        return;
      }
      final mark = int.tryParse(await sh('wc -l < /tmp/syslog.log')) ?? 0;
      await sh('logger "**LOG-9 active START** live/day_of_runs_live_test.dart"');
      for (final s in slots) {
        final script = '$kRouterAppDir/watchdog_wgc$s.sh';
        final before = int.tryParse(await sh('wc -l < /tmp/watchdog_wgc$s.log 2>/dev/null || echo 0')) ?? 0;
        await sh(r"printf '0\n0\n' > /tmp/watchdog_backoff_wgc" '$s');
        await sh('wg set wgc$s peer "\$(nvram get wgc${s}_ppub)" remove');
        await Future.delayed(const Duration(seconds: 2));
        say('wgc$s: peer taken off; a detached run, as cron runs it, rebuilds it');
        final pid = await sh("/bin/sh '$script' detached </dev/null >/dev/null 2>&1 & echo \$!");
        await waitGone(pid, 360);
        final ran = await sh('tail -n +${before + 1} /tmp/watchdog_wgc$s.log');
        final ok = ran.contains('Reconfig SUCCESS');
        result('LOG-9 wgc$s rebuild', ok,
            ok ? 'rebuilt by a detached run' : 'no Reconfig SUCCESS: ${ran.split('\n').where((l) => l.contains('ERROR')).take(1).join()}');
        if (!ok) await sh("/bin/sh '$script' foreground >/dev/null 2>&1");
      }
      say("Firewall restart: the boot script's firewall-start path, then the guard");
      await sh('service restart_firewall');
      await Future.delayed(const Duration(seconds: 30));
      for (final s in slots) {
        await sh("/bin/sh '$kRouterAppDir/watchdog_wgc$s.sh' foreground >/dev/null 2>&1");
      }
      final logged = await sh('tail -n +${mark + 1} /tmp/syslog.log');
      final reported = [for (final l in logged.split('\n')) if (l.contains('reported a script error') && !deliberate(l)) l];
      result('LOG-9 active errors', reported.isEmpty,
          reported.isEmpty ? 'the rebuilds, the firewall restart and the guard reported no script error' : '${reported.length} reported:\n  ${reported.join('\n  ')}');
      for (final s in slots) {
        final r = dayOfRuns(await sh('cat /tmp/watchdog_wgc$s.log.old /tmp/watchdog_wgc$s.log 2>/dev/null'));
        result('LOG-9 wgc$s runs', r.errors.isEmpty,
            r.errors.isEmpty
                ? '${r.runs} runs from build $kFirstBuildWithEndLine on, since ${r.first}, reported no script error'
                : '${r.errors.length} reported:\n  ${r.errors.join('\n  ')}');
      }
      final left = await sh(r'for f in /tmp/watchdog_wgc*.err.* /tmp/cfg-pia-wg-guard.err.* /tmp/cfg-pia-wg-boot.err.*; do '
          r'[ -f "$f" ] || continue; p="${f##*.}"; kill -0 "$p" 2>/dev/null || echo "$f"; done');
      result('LOG-9 files', left.isEmpty, left.isEmpty ? 'no error file left by a finished run' : 'left: $left');
      for (final s in slots) {
        final age = int.tryParse(await sh(
                r'echo $(( $(date +%s) - $(wg show wgc' '$s' r" latest-handshakes | awk '{print $2}' | sort -n | tail -1) ))")) ??
            9999;
        result('LOG-9 wgc$s up', age < 180, 'wgc$s is answering again: handshake ${age}s ago');
      }
      await sh('logger "**LOG-9 active END** live/day_of_runs_live_test.dart"');
    } finally {
      client.close();
      final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
      final f = File('.claude/testing/${stamp}_live_log9_active.log');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(out.toString());
      say('Log: ${f.path}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, skip: missing.isNotEmpty ? 'set ${missing.join(', ')}' : (active ? false : 'set CFG_LIVE_GO=1 for the active version'));
}
