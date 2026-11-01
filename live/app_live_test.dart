// live/app_live_test.dart - the app's own half of ID-483 and ID-488, on the Android emulator, driven
// by adb with nobody tapping (ID-494): TESTING ABT-8's phone steps, and the widget's line in ABT-7,
// with GENERATE's first refresh (ID-493).
//
//   $env:CFG_LIVE_PASS = Read-Host -MaskInput 'Router password'
//   $env:CFG_LIVE_ROUTER = '<router>:22'; $env:CFG_LIVE_USER = '<login>'; $env:CFG_LIVE_GO = '1'
//   flutter test live/app_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER and CFG_LIVE_PASS
// are set; without CFG_LIVE_GO=1 it checks the start state and changes nothing. The PC reaches the
// router over SSH for setting up and checking; the app does the rest, on the emulator, tapped by adb
// from what `uiautomator` reads off the screen. CFG_LIVE_ADB_DEVICE picks the emulator (default
// emulator-5554).
//
// Start state: a debug build of this app running on the emulator (`flutter run`), connected to the
// router this run of the app (open MANAGE once), and already past its own check of the scripts, so it
// replaces nothing by itself; wgc1's and wgc5's watchdogs deployed by build 554 or later; a widget
// key not needed, GENERATE makes one. It sets airplane mode on the emulator for a minute in ABT-8,
// and switches wgc1's alert emails off while wgc1 is damaged, so cron sends none; both are put back.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_script_integrity.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show openSshClient;
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS'];
const _package = 'com.exponentiallydigital.pia_wireguard_cfga';

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  test('the app on the emulator, against a live router', () async {
    final run = _AppRun(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!,
        _Adb(env['CFG_LIVE_ADB_DEVICE']?.trim().isNotEmpty == true ? env['CFG_LIVE_ADB_DEVICE']!.trim() : 'emulator-5554'),
        allowed: env['CFG_LIVE_GO']?.trim() == '1');
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

/// One thing on the screen, as `uiautomator dump` reports it.
class _Node {
  _Node(this.label, this.x, this.y);
  final String label;
  final int x, y;
  @override
  String toString() => label.length > 80 ? '${label.substring(0, 80)}...' : label;
}

String _unescape(String s) => s
    .replaceAll('&#10;', '\n')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// The emulator, through adb.
class _Adb {
  _Adb(this.device);
  final String device;

  Future<String> sh(String cmd) async {
    // UTF-8, not the system's code page: on Windows that turned the widget's "·" into "├é┬╖", and a
    // check of the widget's text failed on the decoding, not the app (2026-11-01).
    final r = await Process.run('adb', ['-s', device, 'shell', cmd], stdoutEncoding: utf8, stderrEncoding: utf8);
    return '${r.stdout}';
  }

  /// Everything on the screen with a label. A dump can fail while something animates, so it is tried
  /// a few times.
  Future<List<_Node>> screen() async {
    for (var i = 0; i < 6; i++) {
      final out = await sh('uiautomator dump /sdcard/cfgpia_ui.xml >/dev/null 2>&1 && cat /sdcard/cfgpia_ui.xml');
      if (out.contains('<hierarchy')) {
        final nodes = <_Node>[];
        for (final m in RegExp(r'<node ([^>]*)>').allMatches(out)) {
          final a = m.group(1)!;
          String attr(String n) => RegExp('$n="([^"]*)"').firstMatch(a)?.group(1) ?? '';
          final label = _unescape(attr('content-desc').isNotEmpty ? attr('content-desc') : attr('text'));
          final b = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(attr('bounds'));
          if (label.isEmpty || b == null) continue;
          int at(int g) => int.parse(b.group(g)!);
          nodes.add(_Node(label, (at(1) + at(3)) ~/ 2, (at(2) + at(4)) ~/ 2));
        }
        return nodes;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return [];
  }

  Future<_Node?> find(String label, {bool contains = false}) async {
    for (final n in await screen()) {
      if (contains ? n.label.contains(label) : n.label == label) return n;
    }
    return null;
  }

  /// Waits up to [within] for [label] on the screen.
  Future<_Node?> waitFor(String label, {bool contains = false, Duration within = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(within);
    while (DateTime.now().isBefore(end)) {
      final n = await find(label, contains: contains);
      if (n != null) return n;
      await Future.delayed(const Duration(milliseconds: 700));
    }
    return null;
  }

  Future<void> tap(_Node n) => sh('input tap ${n.x} ${n.y}');
  Future<void> back() => sh('input keyevent 4');

  /// Scrolls down until [label] shows, up to eight screens.
  Future<_Node?> scrollTo(String label) async {
    for (var i = 0; i < 8; i++) {
      final n = await find(label);
      if (n != null) return n;
      await sh('input swipe 700 2200 700 900 400');
      await Future.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }

  Future<void> airplane(bool on) => sh('cmd connectivity airplane-mode ${on ? 'enable' : 'disable'}');

  Future<bool> appInFront() async => (await sh('dumpsys window | grep mCurrentFocus')).contains(_package);

  /// The home screen widget's data, as the app last wrote it.
  Future<Map<String, String>> widgetData() async {
    final xml = await sh('run-as $_package cat shared_prefs/HomeWidgetPreferences.xml');
    return {
      for (final m in RegExp(r'<string name="([^"]+)">([^<]*)</string>').allMatches(xml)) m.group(1)!: _unescape(m.group(2)!)
    };
  }

  /// Back to the main menu: closes what is open, never the app.
  Future<bool> home() async {
    for (var i = 0; i < 8; i++) {
      final s = await screen();
      bool has(String l) => s.any((n) => n.label == l);
      if (has('MANAGE') && has('SETTINGS') && has('ABOUT') && has('WATCHDOG')) return true;
      final close = s.where((n) => n.label == 'CLOSE' || n.label == 'OK' || n.label == 'HOME').toList();
      if (close.isNotEmpty) {
        await tap(close.first);
      } else {
        await back();
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }
}

class _AppRun {
  _AppRun(this.router, this.user, this.pass, this.adb, {required this.allowed});

  final String router, user, pass;
  final _Adb adb;
  final bool allowed;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  late final SSHClient _client;
  bool _connected = false;

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    _log.writeln(line);
  }

  void _result(String id, bool pass, String why) {
    _say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
    if (!pass) failures.add('$id: $why');
  }

  Future<String> _sh(String cmd) async => (await runRouterCommand(_client, cmd, allowFailure: true)).stdout.trim();
  Future<int> _mark() async => int.tryParse(await _sh('wc -l < /tmp/syslog.log')) ?? 0;
  Future<String> _since(int mark) => _sh('tail -n +${mark + 1} /tmp/syslog.log');
  Future<String> _header(String path) => _sh("sed -n 2p '$path'");
  Future<bool> _whole(String path, String name) async => (await _sh("tail -n 1 '$path'")) == scriptEndLine(name);

  Future<void> go() async {
    _say('Connecting to $router as $user...');
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(router, user, pass, hostKeys: keys);
    _connected = true;
    if (classifyFirmwareTag(await _sh('nvram get 3rd-party')) != RouterFirmware.stock) {
      _result('START', false, 'this run is for stock firmware');
      return;
    }
    setRouterFirmware(RouterFirmware.stock);
    final w1 = watchdogScriptPath(1);
    final version = parseScriptVersion(await _header(w1));
    final front = await adb.appInFront();
    final home = front && await adb.home();
    final connected = home && await _appConnected();
    final start = <String, bool>{
      'the app in front on ${adb.device}': front,
      'the app at its main menu': home,
      'the app logged in to the router this run (ABOUT reads the router without asking)': connected,
      'wgc1 script whole, build 554 or later': (scriptBuild(version) ?? 0) >= kFirstBuildWithEndLine && await _whole(w1, 'watchdog_wgc1.sh'),
      'wgc5 script whole': await _whole(watchdogScriptPath(5), 'watchdog_wgc5.sh'),
    };
    for (final e in start.entries) {
      _say('START ${e.value ? 'ok  ' : 'NOT '} ${e.key}');
    }
    if (start.values.contains(false)) {
      _result('START', false, 'the start state is not there, and nothing was changed: `flutter run -d ${adb.device}`, then on the emulator open MANAGE and log in to the router');
      return;
    }
    appVersionLabel = version!;
    if (!allowed) {
      _say('The plan, not run. Set CFG_LIVE_GO=1 to run it:');
      _say('  ABT-8   UPDATE in ABOUT: back held while it writes; the network cut part-way through wgc5: red failure, wgc5 unchanged, the failure written late, the retry works.');
      _say('  ID-493  GENERATE: the first refresh reaches the router with the new key.');
      _say('  ABT-7   wgc1 cut short: the widget says "watchdog broken"; put back: it does not.');
      return;
    }
    for (final (name, step) in [('ABT-8', _abt8), ('WIDGET', _widget)]) {
      _say('---- $name');
      final mark = await _mark();
      await _sh('logger "**$name START** live/app_live_test.dart"');
      try {
        await step();
      } catch (e) {
        _result(name, false, 'stopped: $e');
      }
      await _sh('logger "**$name END** live/app_live_test.dart"');
      _log.writeln('  router log:\n${(await _since(mark)).split('\n').map((l) => '    $l').join('\n')}');
      await adb.home();
    }
  }

  /// Whether the app holds a router session it can reuse: ABOUT then reads the router by itself,
  /// where without one it offers "login to router to retrieve". Every step needs it, so it is checked
  /// before anything is changed (2026-11-01: a run started with the app freshly restarted, and both
  /// steps stopped part-way).
  Future<bool> _appConnected() async {
    final about = await adb.find('ABOUT');
    if (about == null) return false;
    await adb.tap(about);
    await Future.delayed(const Duration(seconds: 3));
    final read = await adb.waitFor('Watchdog script: v', contains: true, within: const Duration(seconds: 15));
    final asks = await adb.find('login to router to retrieve');
    await adb.home();
    return read != null && asks == null;
  }

  // ABT-8's phone steps (ID-483): the network cut while ABOUT writes the scripts. Both watchdog scripts
  // are made older, so the update writes wgc1's and then wgc5's. While wgc1's is going in, the back
  // key is pressed: the screen must hold. The moment wgc5's first piece lands, the network goes, so the
  // cut falls part-way through a write, and wgc5 is the script that must be left as it was. (The back
  // key was first pressed after the cut: a cut network fails the update at once, so by then nothing
  // was being written, and leaving was allowed.)
  Future<void> _abt8() async {
    final f1 = watchdogScriptPath(1), f5 = watchdogScriptPath(5);
    String watch(String f) => "end=\$((\$(date +%s) + 40)); while [ \$(date +%s) -lt \$end ]; do "
        "ls '$f'.new.* >/dev/null 2>&1 && { echo SEEN; break; }; done";
    try {
      for (final f in [f1, f5]) {
        await _sh("sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v0.0.1 build 1;/' '$f'");
      }
      final about = await adb.find('ABOUT');
      if (about == null) throw StateError('no ABOUT on the main menu');
      await adb.tap(about);
      final update = await adb.waitFor('UPDATE WATCHDOG VERSION');
      if (update == null) throw StateError('ABOUT offers no UPDATE: is the app connected to the router?');
      final mark = await _mark();
      final seen1 = _sh(watch(f1));
      final seen5 = _sh(watch(f5));
      // The cut runs on its own, so a slow screen read below can't make it late.
      var cutAfterWgc5 = false;
      final cut = seen5.then((s) async {
        cutAfterWgc5 = s == 'SEEN';
        await adb.airplane(true);
      });
      // Back straight after the tap: the screen is busy from the tap until the update ends, and on a
      // LAN both scripts go over in about a second, so waiting for the router to see the first piece
      // was too late (2026-11-01: by then the cut had already failed the update).
      await adb.tap(update);
      await adb.back();
      final held = await adb.waitFor('Wait until the watchdog scripts have been written to the router.', within: const Duration(seconds: 4));
      _log.writeln('  on screen after back: ${(await adb.screen()).map((n) => n.toString()).join(' | ')}');
      _result('ABT-8 says why', held != null, 'the back key, pressed while it wrote, said "Wait until the watchdog scripts have been written to the router."');
      if (await seen1 != 'SEEN') _say("ABT-8 info: wgc1's write was not seen by the router watch");
      await cut;
      _say('ABT-8: ${cutAfterWgc5 ? "wgc5's first piece landed, then" : "no wgc5 piece seen in 40 s, but"} the network was cut');
      final error = await adb.waitFor('Could not', contains: true, within: const Duration(seconds: 120));
      _result('ABT-8 screen', error != null, 'the failure is on screen: ${error ?? 'nothing in 120 s'}');
      await adb.airplane(false);
      await Future.delayed(const Duration(seconds: 10));
      final ok = await adb.find('OK');
      if (ok != null) await adb.tap(ok);
      // Looked for once the failure's dialog is closed: a dialog hides what is behind it from
      // uiautomator, so ABOUT under it read as gone (2026-11-01). The dialog itself only shows on a
      // screen still open, so ABOUT here is the screen the back key was pressed on.
      // COPY BUILD INFO, not the heading: the main menu has an ABOUT row too.
      _result('ABT-8 held', await adb.waitFor('COPY BUILD INFO', within: const Duration(seconds: 5)) != null,
          'the back key, pressed while it wrote, left the screen where it was: ABOUT is still open');
      _result('ABT-8 unchanged', cutAfterWgc5 && (await _header(f5)).contains('build 1;') && await _whole(f5, 'watchdog_wgc5.sh'),
          'wgc5, cut part-way, is still the older script, whole');
      _say('ABT-8 info: ${await _sh("ls '$f5'.new.* 2>/dev/null | wc -l")} temporary file(s) beside it');
      final again = await adb.waitFor('UPDATE WATCHDOG VERSION', within: const Duration(seconds: 10));
      if (again == null) throw StateError('no UPDATE to press again');
      await adb.tap(again);
      final done = await adb.waitFor('Watchdog script updated on', contains: true, within: const Duration(seconds: 90));
      var current = true;
      for (final f in [f1, f5]) {
        current = current && parseScriptVersion(await _header(f)) == appVersionLabel && await _sh("ls '$f'.new.* 2>/dev/null | wc -l") == '0';
      }
      _result('ABT-8 retry', done != null && current, 'with the network back, UPDATE works and leaves nothing beside either script');
      final logged = await _since(mark);
      _result('ABT-8 late', logged.contains('ERROR during update of the watchdog scripts') && logged.contains('logged late'),
          'the router log has the failure, written at the next connection, marked late');
      await adb.home();
      final appLog = await adb.find('APP LOG');
      if (appLog != null) await adb.tap(appLog);
      final entry = await adb.waitFor('Watchdog update of the watchdog scripts failed', contains: true, within: const Duration(seconds: 10));
      _result('ABT-8 app log', entry != null, 'the app log has the failure');
    } finally {
      await adb.airplane(false);
      final stale = {
        for (final s in [1, 5])
          if (parseScriptVersion(await _header(watchdogScriptPath(s))) != appVersionLabel) s
      };
      if (stale.isNotEmpty) await RouterWatchdog(_client).redeployScripts(only: stale);
    }
  }

  /// GENERATE in SETTINGS, then the widget's data once its first refresh has written it, or after
  /// [within] whatever it holds.
  Future<Map<String, String>> _generate(bool Function(Map<String, String>) settled,
      {Duration within = const Duration(seconds: 45)}) async {
    if (!await adb.home()) throw StateError('could not get back to the main menu');
    final settings = await adb.find('SETTINGS');
    if (settings == null) throw StateError('no SETTINGS on the main menu');
    await adb.tap(settings);
    final key = await adb.scrollTo('HOME SCREEN WIDGET KEY');
    if (key == null) throw StateError('no HOME SCREEN WIDGET KEY in SETTINGS');
    await adb.tap(key);
    final generate = await adb.waitFor('GENERATE');
    if (generate == null) throw StateError('no GENERATE');
    await adb.tap(generate);
    final note = await adb.waitFor('installed on your router', contains: true);
    if (note == null) throw StateError('GENERATE did not say it installed the key');
    final end = DateTime.now().add(within);
    var data = await adb.widgetData();
    while (!settled(data) && DateTime.now().isBefore(end)) {
      await Future.delayed(const Duration(seconds: 2));
      data = await adb.widgetData();
    }
    final close = await adb.find('CLOSE');
    if (close != null) await adb.tap(close);
    return data;
  }

  String _wgc1Row(Map<String, String> d) => [
        for (final e in d.entries)
          if (RegExp(r'^tunnel\d_detail$').hasMatch(e.key) && e.value.startsWith('wgc1 ')) e.value
      ].join();

  // ID-493 and ID-488: GENERATE's first refresh, and the widget's line for a broken watchdog.
  Future<void> _widget() async {
    final f = watchdogScriptPath(1);
    const whole = '/tmp/cfgpia-live-wgc1.whole';
    final alerts = await _sh('nvram get wgc1_wd_email_enabled');
    try {
      final first = await _generate((d) => (d['last_checked_text'] ?? '').startsWith('Router checked') &&
          !(d['last_checked_text'] ?? '').contains('could not reach'));
      final footer = first['last_checked_text'] ?? '';
      _result('ID-493', footer.startsWith('Router checked') && !footer.contains('could not reach'),
          "GENERATE's first refresh reached the router with the new key: \"$footer\"");
      _result('WIDGET whole', _wgc1Row(first).isNotEmpty && !_wgc1Row(first).contains('watchdog broken'),
          'with wgc1 whole, its row says nothing of the kind: "${_wgc1Row(first)}"');

      // Cut short as ABT-7 does, with wgc1's alerts off so cron's runs of it email nobody.
      await _sh('nvram set wgc1_wd_email_enabled=0');
      await _sh("cp '$f' $whole && dd if=$whole of='$f' bs=7940 count=1 2>/dev/null");
      final broken = await _generate((d) => _wgc1Row(d).contains('watchdog broken'));
      _result('WIDGET broken', _wgc1Row(broken).contains('watchdog broken'),
          'with wgc1 cut short, its row says so: "${_wgc1Row(broken)}"');
      if (broken['badge'] == 'protected') {
        _result('WIDGET compact', broken['compact_detail_text'] == 'wgc1 watchdog broken · open the app',
            'the compact widget says so too: "${broken['compact_detail_text']}"');
      }

      await _sh("cp $whole '$f'");
      final back = await _generate((d) => _wgc1Row(d).isNotEmpty && !_wgc1Row(d).contains('watchdog broken'));
      _result('WIDGET back', !_wgc1Row(back).contains('watchdog broken'), 'put back, the row is plain again: "${_wgc1Row(back)}"');
    } finally {
      if (!await _whole(f, 'watchdog_wgc1.sh')) await _sh("[ -f $whole ] && cp $whole '$f'");
      await _sh('rm -f $whole');
      await _sh('nvram set wgc1_wd_email_enabled=$alerts');
      await _sh('rm -f /tmp/watchdog_fault_wgc1');
    }
  }

  Future<void> close() async {
    await adb.airplane(false);
    if (_connected) _client.close();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_app.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }
}
