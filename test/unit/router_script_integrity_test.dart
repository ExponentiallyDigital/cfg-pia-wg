// lib/router_script_integrity.dart: the write beside, then rename (ID-482); what the app reads of the
// scripts on the router (ID-486); and the check at the first connection that replaces what is
// damaged or older (ID-487).

import 'dart:async';
import 'dart:math';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_log_paging.dart';
import 'package:cfg_pia_wg/router_script_integrity.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const String kPath = '/jffs/cfg-pia-wg/watchdog_wgc5.sh';

/// About 12 KB: three pieces, with MARK-C3 in the third.
final String kBody = [
  for (var i = 0; i < 300; i++) i == 220 ? 'echo MARK-C3' : 'echo line $i ${'x' * 30}',
  '# end of watchdog_wgc5.sh',
].join('\n');

Future<String> _read(RecordingSSHClient c, String cmd) async => String.fromCharCodes(await c.run(cmd)).trim();

Future<int> write(RecordingSSHClient c, {String body = '', int seed = 1}) => writeRouterFile(
      path: kPath,
      body: body.isEmpty ? kBody : body,
      what: 'watchdog script',
      mode: '+x',
      run: (cmd) async {
        final r = await c.runWithResult(cmd);
        if (r.exitCode != 0) throw Exception(String.fromCharCodes(r.stderr));
        return String.fromCharCodes(r.stdout).trim();
      },
      read: (cmd) => _read(c, cmd),
      options: WriteOptions(random: Random(seed)),
    );

void main() {
  group('writing a file beside the live one, then renaming it over (ID-482)', () {
    test('a write that works ends with the new file in place and nothing left beside it', () async {
      final c = RecordingSSHClient()..files[kPath] = StringBuffer('old\n');
      final size = await write(c);
      expect(c.files[kPath].toString(), '$kBody\n');
      expect(size, writtenByteCount(kBody));
      expect(c.files.keys.where((k) => k.contains('.new.')), isEmpty);
      final move = c.commands.firstWhere((x) => x.contains('mv -f'));
      expect(move, matches(RegExp(r"^chmod \+x '/jffs/cfg-pia-wg/watchdog_wgc5\.sh\.new\.[0-9a-f]{8}' && mv -f '\S+' '/jffs/cfg-pia-wg/watchdog_wgc5\.sh'$")));
      expect(c.commands.where((x) => x.startsWith('cat ')).every((x) => x.contains('.new.')), isTrue,
          reason: 'no piece is ever written to the live file');
      expect(c.commands.last, "rm -f '$kPath'.new.*", reason: 'leftovers of failed writes go once this one is in place');
    });

    test('a connection that fails part-way leaves the live file as it was, and says so', () async {
      final c = RecordingSSHClient(throwOn: ['MARK-C3'])..files[kPath] = StringBuffer('old\n');
      await expectLater(
          write(c),
          throwsA(predicate((e) =>
              e.toString().contains('failed part-way') && e.toString().contains('The router kept the watchdog script it had'))));
      expect(c.files[kPath].toString(), 'old\n', reason: 'the 2026-10-29 failure, now harmless');
      expect(c.commands.any((x) => x.contains('mv -f')), isFalse);
      expect(c.commands.any((x) => RegExp(r"^rm -f '\S+\.new\.[0-9a-f]{8}'$").hasMatch(x)), isTrue, reason: 'its pieces are removed');
    });

    test('a connection that is gone for good still gives the reason, not the failed tidy-up', () async {
      // MARK-C3 fails the third piece; every command after it fails as well, as a dropped router does.
      var gone = false;
      final c = RecordingSSHClient(responder: (cmd) {
        if (gone || cmd.contains('MARK-C3')) {
          gone = true;
          throw Exception('Connection closed');
        }
        return '';
      })
        ..files[kPath] = StringBuffer('old\n');
      await expectLater(
          write(c),
          throwsA(predicate((e) =>
              e.toString().contains('failed part-way') && e.toString().contains('The router kept the watchdog script it had'))));
      expect(c.files[kPath].toString(), 'old\n');
    });

    test('a connection that goes silent, as when Wi-Fi goes off, holds the write up for a bounded time', () async {
      // From the third piece on, nothing ever answers: no error, no reply.
      var silent = false;
      Future<String> hangOrAnswer(String cmd) {
        if (silent || cmd.contains('MARK-C3')) {
          silent = true;
          return Completer<String>().future;
        }
        return Future.value('');
      }

      final watch = Stopwatch()..start();
      await expectLater(
          writeRouterFile(
            path: kPath,
            body: kBody,
            what: 'watchdog script',
            mode: '+x',
            run: hangOrAnswer,
            read: hangOrAnswer,
            options: const WriteOptions(chunkTimeout: Duration(milliseconds: 300), tidyTimeout: Duration(milliseconds: 300)),
          ),
          throwsA(predicate((e) => e.toString().contains('longer than') && e.toString().contains('The router kept'))));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('control: the old write, straight over the live file, left it cut short', () async {
      // What heredocWriteCommands alone did before ID-482, to show the test above can tell.
      final c = RecordingSSHClient(throwOn: ['MARK-C3'])..files[kPath] = StringBuffer('old\n');
      try {
        for (final cmd in heredocWriteCommands(kPath, kBody)) {
          await c.run(cmd);
        }
      } catch (_) {}
      expect(c.files[kPath].toString(), isNot('old\n'));
      expect(c.files[kPath].toString().length, lessThan(kBody.length));
    });

    test('a file that arrives short, long or with another last line is never put in place', () async {
      for (final answer in [
        (String cmd) => cmd.startsWith('wc -c') && cmd.contains('.new.') ? '7940' : null,
        (String cmd) => cmd.startsWith('wc -c') && cmd.contains('.new.') ? '99999' : null,
        (String cmd) => cmd.startsWith('tail -n 1') ? 'echo line 3' : null,
      ]) {
        final c = RecordingSSHClient(responder: (cmd) => answer(cmd) ?? '')..files[kPath] = StringBuffer('old\n');
        await expectLater(write(c), throwsA(predicate((e) => e.toString().contains('The router kept'))));
        expect(c.files[kPath].toString(), 'old\n');
        expect(c.commands.any((x) => x.contains('mv -f')), isFalse);
      }
    });

    test('two writes go to different temporary files', () {
      expect(tempWritePath(kPath, Random(1)), isNot(tempWritePath(kPath, Random(2))));
      expect(tempWritePath(kPath), matches(RegExp(r'\.new\.[0-9a-f]{8}$')));
    });
  });

  group('what the app reads of the scripts (ID-486)', () {
    final saved = appVersionLabel;
    setUp(() => appVersionLabel = 'v0.8.184 build 554');
    tearDown(() => appVersionLabel = saved);

    String header(String name, String version) => '# $name - auto-generated by cfg-pia-wg $version; *do* *not* edit.';

    test('a whole script, a damaged one, an older one and a missing one', () {
      final h = parseScriptHealth([
        'wgc1|1|1|49000|${header('watchdog_wgc1.sh', 'v0.8.184 build 554')}|# end of watchdog_wgc1.sh',
        'wgc2|1|1|7940|${header('watchdog_wgc2.sh', 'v0.8.184 build 554')}|else',
        'wgc3|1|1|48994|${header('watchdog_wgc3.sh', 'v0.8.183 build 553')}|exit 0',
        'wgc4|1|0|0||',
        'wgc5|1|1|49000|${header('watchdog_wgc5.sh', 'v0.8.190 build 560')}|# end of watchdog_wgc5.sh',
        'guard|0|1|16475|# guard.sh - auto-generated by cfg-pia-wg; *do* *not* edit.|exit 0',
        'fault|2|1793000000|watchdog_wgc2.sh is damaged (7940 bytes, and its last line is missing)',
      ].join('\n'));
      final by = {for (final s in h.watchdogs) s.slot: s};
      expect(by[1]!.damaged || by[1]!.needsUpdate, isFalse);
      expect(by[2]!.damaged, isTrue);
      expect(by[2]!.problem, 'ERROR: watchdog_wgc2.sh on the router is damaged (7940 bytes, and its last line is missing), so that watchdog is not running.');
      expect(by[3]!.damaged, isFalse, reason: 'build 553 had no end line: out of date, not damaged');
      expect(by[3]!.olderThanApp, isTrue);
      expect(by[4]!.missing && by[4]!.damaged, isTrue);
      expect(by[4]!.problem, contains("wgc4's watchdog is scheduled, but its script watchdog_wgc4.sh is missing"));
      expect(by[5]!.newerThanApp, isTrue);
      expect(by[5]!.needsUpdate, isFalse, reason: 'never replaced only for being newer');
      expect(h.guard!.version, isNull);
      expect(h.guard!.olderThanApp, isTrue, reason: 'a guard with no version is from before 554');
      expect(h.guard!.damaged, isFalse);
      expect(h.faults.single.slot, 2);
      expect(h.faults.single.message, startsWith('watchdog_wgc2.sh is damaged'));
      expect(h.damaged.map((s) => s.fileName), ['watchdog_wgc2.sh', 'watchdog_wgc4.sh']);
    });

    test('each problem is red in the router log as well as the app log', () {
      final s = parseScriptHealth('wgc2|1|1|7940|${header('watchdog_wgc2.sh', 'v0.8.184 build 554')}|else').watchdogs.single;
      expect(isRouterLogError('Oct 29 15:10:00 cfg-pia-wg: ${s.problem}'), isTrue);
    });

    test('the read is one round trip, and names every script and fault file', () {
      expect(kScriptHealthCommand, contains('/jffs/cfg-pia-wg/watchdog_wgc\$S.sh'));
      expect(kScriptHealthCommand, contains('/jffs/cfg-pia-wg/guard.sh'));
      expect(kScriptHealthCommand, contains('/tmp/watchdog_lastfault_wgc\$S'));
      expect(kScriptHealthCommand, contains('tail -n 1'));
    });
  });

  group("the widget's read (ID-488)", () {
    String head(int slot, int build) => '# watchdog_wgc$slot.sh - auto-generated by cfg-pia-wg v0.8.$build build $build; *do* *not* edit.';
    const cron = '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#\n'
        '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc3.sh #watchdog_wgc3#\n'
        '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc5.sh #watchdog_wgc5#\n'
        '0 0 * * * mv /tmp/watchdog_wgc5.log /tmp/watchdog_wgc5.log.old #watchdog_log_rotate_wgc5#';

    test('a damaged script and a missing one are broken; a whole one and an older one are not', () {
      final out = [
        head(1, 554), '# end of watchdog_wgc1.sh', // whole
        head(5, 554), 'else', // cut short
        head(2, 553), 'exit 0', // older, and not scheduled
      ].join('\n');
      expect(brokenWatchdogSlots(cronList: cron, headsAndTails: out), {5, 3}, reason: 'wgc3 is scheduled with no script');
    });

    test('a key made before this build reads nothing here, and nothing is called broken', () {
      expect(brokenWatchdogSlots(cronList: '', headsAndTails: ''), isEmpty);
    });

    test('the read needs no double quotes, for the key restriction it is part of', () {
      expect(kWatchdogHeadsAndTailsCommand, isNot(contains('"')));
    });
  });

  group('the check at the first connection (ID-487)', () {
    final saved = appVersionLabel;
    setUp(() {
      appVersionLabel = 'v0.8.184 build 554';
      clearKeptRouterLog();
    });
    tearDown(() => appVersionLabel = saved);

    RecordingSSHClient router(String health) => RecordingSSHClient(responder: (cmd) {
          if (cmd == 'nvram get 3rd-party') return '';
          if (cmd == kScriptHealthCommand) return health;
          return '';
        });

    final damaged = 'wgc5|1|1|7940|# watchdog_wgc5.sh - auto-generated by cfg-pia-wg v0.8.184 build 554; *do* *not* edit.|else';
    final older = 'wgc1|1|1|48994|# watchdog_wgc1.sh - auto-generated by cfg-pia-wg v0.8.183 build 553; *do* *not* edit.|exit 0';
    final newer = 'wgc3|1|1|49000|# watchdog_wgc3.sh - auto-generated by cfg-pia-wg v0.8.190 build 560; *do* *not* edit.|# end of watchdog_wgc3.sh';

    test('a paid version replaces the damaged and the older, never the newer, and logs it', () async {
      useStock();
      final c = router([damaged, older, newer].join('\n'));
      final logs = <(String, bool)>[];
      final r = await checkRouterScripts(c, canUpdate: true, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add((m, isError)));
      expect(r.updated, ['watchdog_wgc1.sh', 'watchdog_wgc5.sh']);
      expect(r.unfixed, isEmpty);
      expect(c.files.keys, containsAll([watchdogScriptPath(1), watchdogScriptPath(5)]));
      expect(c.files.containsKey(watchdogScriptPath(3)), isFalse);
      expect(logs.where((l) => l.$2).map((l) => l.$1), contains(startsWith('ERROR: watchdog_wgc5.sh on the router is damaged')));
      expect(c.commands.any((x) => x.startsWith('logger') && x.contains('ERROR: watchdog_wgc5.sh on the router is damaged')), isTrue);
      expect(c.commands.any((x) => x.startsWith('logger') && x.contains('Watchdog script updated automatically to v0.8.184 build 554')), isTrue);
    });

    test('an unpaid version reports, writes nothing, and leaves the damage for the banner', () async {
      useStock();
      final c = router([damaged, older].join('\n'));
      final r = await checkRouterScripts(c, canUpdate: false);
      expect(r.updated, isEmpty);
      expect(r.unfixed.single, startsWith('watchdog_wgc5.sh on the router is damaged'));
      expect(c.commands.any((x) => x.startsWith('cat ')), isFalse);
    });

    test('a guard from before this build is brought up to date on stock', () async {
      useStock();
      final c = router('guard|0|1|16475|# guard.sh - auto-generated by cfg-pia-wg; *do* *not* edit.|exit 0');
      final r = await checkRouterScripts(c, canUpdate: true);
      expect(r.updated, ['guard.sh']);
      expect(c.files.containsKey('/jffs/cfg-pia-wg/guard.sh'), isTrue);
    });

    test('a fault from the last day is logged once a run of the app; an older one is not', () async {
      useStock();
      final now = DateTime(2026, 11, 1, 12);
      final recent = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
      final old = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000;
      final c = router('fault|5|$recent|This watchdog\'s last run reported a script error: [boom]\nfault|1|$old|ancient');
      final seen = <String>{};
      final logs = <String>[];
      void log(String m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logs.add(m);
      await checkRouterScripts(c, canUpdate: false, onLog: log, seenFaults: seen, clock: () => now);
      await checkRouterScripts(c, canUpdate: false, onLog: log, seenFaults: seen, clock: () => now);
      expect(logs.where((l) => l.contains('boom')), hasLength(1));
      expect(logs.single, startsWith("ERROR: wgc5's watchdog reported at 2026-11-01 10:00: "));
      expect(logs.any((l) => l.contains('ancient')), isFalse);
    });

    test('a router whose firmware is not supported is left alone', () async {
      final c = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get 3rd-party' ? 'something-else' : damaged);
      final r = await checkRouterScripts(c, canUpdate: true);
      expect(r.updated, isEmpty);
      expect(c.commands, ['nvram get 3rd-party']);
    });
  });
}
