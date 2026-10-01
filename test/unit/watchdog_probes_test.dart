// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart): two watchdogs at once, and the kill-switch line.
//
// Each group reproduces something found on hardware, so the fault it guards against can never come
// back unnoticed. Skipped where no POSIX shell is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

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

  group('the watchdog on a stock router', () {

  // ID-193. Two watchdogs start in the same second, and each used to sweep away the other's
    // temporary DNS rule at the start of its run.
    group('two watchdogs at once (ID-193)', () {
      test("a run leaves another slot's probe rule alone", () async {
        h.addRule('1000:\tfrom all to 9.9.9.9 iif lo lookup 5');
        await h.run();
        expect(h.rules, contains('1000: from all to 9.9.9.9 iif lo lookup 5'));
      });

      test('a run clears its own leftover probe rule', () async {
        h.addRule('1000:\tfrom all to 9.9.9.9 iif lo lookup 9');
        await h.run();
        expect(h.rules.where((r) => r.startsWith('1000:')), isEmpty);
      });

      test('a probe waits for the one before it, and leaves no lock behind', () async {
        final lock = Directory('${h.root.path}/tmp/cfg-pia-wg-dnsprobe.lock')..createSync();
        final r = await h.run();
        expect(r.exitCode, 0, reason: h.log.join('\n'));
        expect(h.lookups, hasLength(1), reason: 'a lock that old was left by a killed run, and is broken');
        expect(lock.existsSync(), isFalse);
      });
    });
    // ID-320: the email's "the guard kept these devices off the internet" counted rule-90s by table,
    // so a device whose blocking rule 91 was gone still counted as guarded.
    group('the kill-switch line counts guarded devices from the kernel', () {
      Future<String> guarded() async {
        final s = h.script();
        final start = s.indexOf('GUARDED=0');
        final block = s.substring(start, s.indexOf('\ndone\n', start) + 6);
        final r = await h.runSnippet('MYIDX=9\n$block\n' r'echo "$GUARDED"' '\n');
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        return '${r.stdout}'.trim();
      }

      setUp(() => h.set('vpnc_dev_policy_list', '<1>192.168.1.20>>9><1>192.168.1.21>>9><1>192.168.1.22>>5>'));

      test('a device with both rules counts; one missing its blackhole does not', () async {
        h
          ..addRule('90:\tfrom 192.168.1.20 lookup 9 suppress_prefixlength 0')
          ..addRule('91:\tfrom 192.168.1.20 blackhole')
          ..addRule('90:\tfrom 192.168.1.21 lookup 9 suppress_prefixlength 0');
        expect(await guarded(), '1');
      });

      test('a 90 rule without suppress_prefixlength 0 does not count', () async {
        h
          ..addRule('90:\tfrom 192.168.1.20 lookup 9')
          ..addRule('91:\tfrom 192.168.1.20 blackhole');
        expect(await guarded(), '0');
      });

      test('both pinned devices with both rules count 2, and another tunnel\'s device is not counted', () async {
        for (final ip in ['192.168.1.20', '192.168.1.21', '192.168.1.22']) {
          h
            ..addRule('90:\tfrom $ip lookup ${ip.endsWith('22') ? 5 : 9} suppress_prefixlength 0')
            ..addRule('91:\tfrom $ip blackhole');
        }
        expect(await guarded(), '2');
      });
    });

    // ID-242: the alert email counted the pinned devices - "the 1 device pinned to this tunnel" - where
    // DEVICE ASSIGNMENT names them. The names come from the same places the screen reads.
    group('the kill-switch line names the pinned devices', () {
      Future<String> names() async {
        final s = h.script();
        final start = s.indexOf('pinned_names() {');
        final fn = s.substring(start, s.indexOf('\n}\n', start) + 3);
        final r = await h.runSnippet('JQ=/jffs/cfg-pia-wg/jq\nMYIDX=9\n${fn}pinned_names\n');
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        return '${r.stdout}'.trim();
      }

      test("by the user's name, else the address, in list order, and only this tunnel's", () async {
        h
          ..set('vpnc_dev_policy_list',
              '<1>192.168.1.20>>9><1>192.168.1.21>>5><0>192.168.1.22>>9><1>192.168.1.23>>9>')
          ..set('dhcp_staticlist', '<aa:bb:cc:00:00:20>192.168.1.20>><AA:BB:CC:00:00:21>192.168.1.21>>')
          ..set('custom_clientlist', '<TABLET>AA:BB:CC:00:00:20>0>0>>><PHONE>AA:BB:CC:00:00:21>0>0>>>');
        expect(await names(), 'TABLET, 192.168.1.23');
      });

      test('a device with no name anywhere is named by its address', () async {
        h
          ..set('vpnc_dev_policy_list', '<1>192.168.1.30>>9>')
          ..set('dhcp_staticlist', '<AA:BB:CC:00:00:30>192.168.1.30>>')
          ..set('custom_clientlist', '');
        expect(await names(), '192.168.1.30');
      });
    });
  }, skip: skip);
}
