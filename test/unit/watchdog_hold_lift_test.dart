// test/unit/watchdog_hold_lift_test.dart - a rebuild lifts the guard's hold on the router's DNS addresses, and puts it back
// (ID-653).
//
// On Merlin the guard refuses the router's lookups to a DNS address a slot shares with the router while that slot is down
// (ID-636). A rebuild by a watchdog with no DoH server of its own looks PIA's names up through the router's resolver, and the
// alert email does the same for the mail server, so the hold has to be lifted for the slot's addresses until the script ends,
// whichever way it ends, and not at all when the watchdog has a DoH server. This runs the functions the script carries in a
// shell against a fake guard that writes down what it was asked.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/merlin_guard.dart' show kMerlinGuardScriptPath;
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

WatchdogConfig _config({String dohUrl = '', String dohIp = ''}) => WatchdogConfig(
      slotIndex: 3,
      primaryIp: '8.8.8.8',
      secondaryIp: '1.1.1.1',
      piaUsername: 'p1234567',
      piaPassword: 'secret',
      emailAlertsEnabled: false,
      emailFrom: '',
      emailTo: '',
      emailSubject: '',
      smtpServer: '',
      smtpUsername: '',
      smtpPassword: '',
      dohUrl: dohUrl,
      dohIp: dohIp,
    );

void main() {
  final shell = findShell();
  late Directory dir;
  late String guard;
  late String calls;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wd_hold_lift_');
    guard = '${dir.path}/merlin-guard.sh';
    calls = '${dir.path}/calls';
    // The fake guard writes down its arguments, and fails when asked to.
    File(guard).writeAsStringSync('#!/bin/sh\necho "\$*" >> "${shPath(calls)}"\n[ -z "\$GUARD_FAIL" ] || exit 1\n');
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', guard]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The two functions and the trap, as the Merlin script carries them, pointed at the fake guard.
  String block({String? script}) {
    final text = script ?? buildWatchdogScript(_config(), firmware: RouterFirmware.merlin);
    final m = RegExp(r'^HOLDLIFTED=""[\s\S]*?^trap .*EXIT$', multiLine: true).firstMatch(text);
    expect(m, isNotNull, reason: 'the script has the hold functions and the trap');
    return m!.group(0)!.replaceAll(kMerlinGuardScriptPath, shPath(guard));
  }

  List<String> guardCalls() => File(calls).existsSync() ? File(calls).readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];

  /// Runs [steps] after the block, with [vars] set; the exit code and what the script logged.
  Future<(int, String)> run(String steps, {String vars = 'DOHURL=""', String? script}) async {
    final r = await runSh(shell!, [
      '-c',
      'SLOT=3; $vars; ERRNOW=${shPath('${dir.path}/err')}; log() { echo "LOG: \$*"; }; K=wgc3_; nvram() { echo "1.1.1.2, 1.0.0.2"; }; iptables() { [ -z "\$HELD" ] || echo "-A OUTPUT -d 1.1.1.2/32 ! -o wgc+ -j DROP"; }; service() { echo "SERVICE: \$*" >> ${shPath('${dir.path}/svc')}; }\n${block(script: script)}\n$steps',
    ]);
    final svc = File('${dir.path}/svc');
    return (r.exitCode, '${r.stdout}${r.stderr}${svc.existsSync() ? svc.readAsStringSync() : ''}');
  }

  test('no DoH server: the rebuild lifts the hold for its own slot, and puts it back when the script ends', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\n[ -n "\$HOLDLIFTED" ] && echo "lifted"\nhold_back\n[ -z "\$HOLDLIFTED" ] && echo "back"');
    expect(code, 0, reason: out);
    expect(guardCalls(), ['lift 3', 'restore']);
    expect(out, allOf(contains('lifted'), contains('back')));
    expect(out, contains("LOG: No DoH server of its own: the router's DNS hold is lifted for this rebuild"));
    expect(out, contains("LOG: The router's DNS hold is back"));
  }, skip: shell == null ? _noShell : null);

  test('with a DoH server of its own the hold stays on: the rebuild does not use the resolver', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\nhold_back', vars: 'DOHURL="https://dns.example/dns-query"');
    expect(code, 0, reason: out);
    expect(guardCalls(), isEmpty);
    expect(out, isNot(contains('lifted')));
  }, skip: shell == null ? _noShell : null);

  test('the hold is put back on any exit: the trap runs it, after the script ended in the middle of a rebuild', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\nexit 3');
    expect(code, 3, reason: out);
    expect(guardCalls(), ['lift 3', 'restore'], reason: 'an abort, which sends its FAILED email first, still ends with the hold back');
  }, skip: shell == null ? _noShell : null);

  test('a rebuild whose hold was lifted restarts the resolver once the tunnel is up, so the alert email can find its mail server', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\nresolver_fresh\nhold_back', vars: 'DOHURL=""; HELD=1');
    expect(code, 0, reason: out);
    expect(out, contains('SERVICE: restart_stubby'));
    expect(out, contains("LOG: Restarted the router's encrypted resolver"));
  }, skip: shell == null ? _noShell : null);

  test('a rebuild that lifted nothing of its own, because the slot does not share the router DNS, leaves the resolver alone', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\nresolver_fresh\nhold_back');
    expect(code, 0, reason: out);
    expect(guardCalls(), ['lift 3', 'restore'], reason: 'the lift is still asked for and put back');
    expect(out, isNot(contains('SERVICE:')));
  }, skip: shell == null ? _noShell : null);

  test('a rebuild that never lifted the hold leaves the resolver alone', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_lift\nresolver_fresh', vars: 'DOHURL="https://dns.example/dns-query"');
    expect(code, 0, reason: out);
    expect(out, isNot(contains('SERVICE:')));
  }, skip: shell == null ? _noShell : null);

  test('nothing lifted, nothing restored: a run that never rebuilt asks the guard for nothing', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('hold_back\nexit 0');
    expect(code, 0, reason: out);
    expect(guardCalls(), isEmpty);
  }, skip: shell == null ? _noShell : null);

  test('where there is no guard (stock) both are no-ops and the script goes on', () async {
    if (shell == null) return markTestSkipped(_noShell);
    File(guard).deleteSync();
    final (code, out) = await run('hold_lift\nhold_back\necho "went on"');
    expect(code, 0, reason: out);
    expect(out, contains('went on'));
    expect(out, isNot(contains('lifted')));
  }, skip: shell == null ? _noShell : null);

  test('a guard that refuses the lift leaves nothing to put back, so the run does not claim one', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final (code, out) = await run('GUARD_FAIL=1 hold_lift\nhold_back\necho "after"');
    expect(code, 0, reason: out);
    expect(guardCalls(), ['lift 3'], reason: 'it asked once and was refused');
    expect(out, isNot(contains('is lifted')));
  }, skip: shell == null ? _noShell : null);

  group('where the script does it', () {
    final merlin = buildWatchdogScript(_config(), firmware: RouterFirmware.merlin);

    test('the lift comes before the first lookup of a name, and the restore is the exit trap, which follows the alert email', () {
      final lift = merlin.indexOf('\nhold_lift\n');
      final firstLookup = merlin.indexOf('lookup "\$CAHOST" 443');
      expect(lift, greaterThan(0));
      expect(firstLookup, greaterThan(lift), reason: 'PIA\'s names are looked up through the resolver after it');
      expect(merlin, contains("trap 'hold_back; [ -s \"\$ERRNOW\" ] || rm -f \"\$ERRNOW\"' EXIT"));
      expect(merlin, isNot(contains('__MGUARD__')));
      expect(merlin, contains('"$kMerlinGuardScriptPath" lift "\$SLOT"'));
    });

    test('the resolver is restarted after the handshake and before the success is logged, which is before the email', () {
      final handshake = merlin.indexOf('no handshake in 20s)"');
      final fresh = merlin.indexOf('\nresolver_fresh\n');
      final success = merlin.indexOf('Reconfig SUCCESS');
      expect(handshake, greaterThan(0));
      expect(fresh, greaterThan(handshake));
      expect(success, greaterThan(fresh));
    });

    test('stock carries the same no-op functions, and never finds the guard', () {
      final stock = buildWatchdogScript(_config(), firmware: RouterFirmware.stock);
      expect(stock, contains('hold_lift() {'));
      expect(stock, contains('[ -x "$kMerlinGuardScriptPath" ] || return 0'));
    });
  });
}
