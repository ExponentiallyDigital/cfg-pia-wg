// Runs the real guard script under a POSIX shell, against the fake router in guard_harness.dart:
// the guard's rules for pinned devices, and its script text.
//
// The first behavioural test of router-side shell in this repo (BACKLOG ID-205 is the wider
// harness). String checks alone would have passed a script that re-added its rules on every run,
// which is exactly the kind of fault only running it finds. Skipped where no `sh` is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cfg_pia_wg/fail_closed_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'guard_harness.dart';

void main() {
  final g = GuardRouter();
  final shell = g.shell;

  setUp(g.setUp);
  tearDown(g.tearDown);

  // ID-320: a 90 rule without suppress_prefixlength 0 counted as guarded, though it hands the device
  // the WAN default the firmware copies into the tunnel's table.
  test('guard.sh replaces a 90 rule that lacks suppress_prefixlength 0', () async {
    g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
    File('${g.state.path}/rules').writeAsStringSync('90:\tfrom 192.0.2.50 lookup 9\n91:\tfrom 192.0.2.50 blackhole\n');
    final r = await g.run();
    expect('${r.stdout}', contains('guarded 1 of 1'));
    expect(g.rules(), unorderedEquals(['90: from 192.0.2.50 lookup 9 suppress_prefixlength 0', '91: from 192.0.2.50 blackhole']));
  });

  group('guard.sh', () {
    test('a device pinned to a WireGuard tunnel gets both rules', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      final r = await g.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1'));
      expect(g.rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 9 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
      expect(g.log(), ['Fail-closed guard on for 192.0.2.50 (wgc1)']);
    });

    // ID-262: ROUTER LOG gave the address alone, where DEVICE ASSIGNMENT shows a name.
    test('the log names the device, as DEVICE ASSIGNMENT does, before its address', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      g.set('dhcp_staticlist', '<aa:bb:cc:00:00:50>192.0.2.50>>');
      g.set('custom_clientlist', '<TABLET>AA:BB:CC:00:00:50>0>0>>>');
      await g.run();
      expect(g.log(), ['Fail-closed guard on for TABLET 192.0.2.50 (wgc1)']);
      g.set('vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      await g.run();
      expect(g.log().last, 'Fail-closed guard removed for TABLET 192.0.2.50');
    });

    test('a device with a reservation but no name of its own is named by its address', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      g.set('dhcp_staticlist', '<AA:BB:CC:00:00:50>192.0.2.50>>');
      await g.run();
      expect(g.log(), ['Fail-closed guard on for 192.0.2.50 (wgc1)']);
    });

    test('a second run changes nothing and logs nothing', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await g.run();
      final before = g.rules();
      final r = await g.run();
      expect(r.exitCode, 0);
      expect(g.rules(), before, reason: 'the guard must not re-add rules it already holds');
      expect(g.log(), hasLength(1));
    });

    test('a device that stops being pinned loses its guard', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await g.run();
      g.set('vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      final r = await g.run();
      expect(r.exitCode, 0);
      expect(g.rules(), isEmpty);
      expect(g.log().last, 'Fail-closed guard removed for 192.0.2.50');
    });

    test('a device moved between tunnels is guarded for the new one only', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await g.run();
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      await g.run();
      expect(g.rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 5 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
    });

    test('no guard for a device on Internet, on the default, or on a VPN the app does not manage', () async {
      // Pinned to Internet (index 0), following the default (enabled 0), pinned to OpenVPN (3).
      g.set('vpnc_dev_policy_list', '1>192.0.2.51>>0><0>192.0.2.52>>9><1>192.0.2.53>>3>');
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 0'));
      expect(g.rules(), isEmpty);
    });

    test('duplicates are reduced to one of each', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      File('${g.state.path}/rules').writeAsStringSync(
        '90:\tfrom 192.0.2.50 lookup 9 suppress_prefixlength 0\n'
        '90:\tfrom 192.0.2.50 lookup 9 suppress_prefixlength 0\n'
        '91:\tfrom 192.0.2.50 blackhole\n'
        '91:\tfrom 192.0.2.50 blackhole\n',
      );
      await g.run();
      expect(g.rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 9 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
    });

    test("the firmware's own rules are never touched", () async {
      g.set('vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      const firmware = [
        '100: from 192.0.2.50 lookup 9',
        '1016: from all to 9.9.9.9 iif lo lookup 5',
        '10000: from all iif br0 lookup 5',
      ];
      File('${g.state.path}/rules').writeAsStringSync(firmware.map((l) => l.replaceFirst(': ', ':\t')).join('\n'));
      await g.run();
      await g.run(['clear']);
      expect(g.rules(), firmware);
    });

    test('clear removes every guard rule', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9><1>192.0.2.60>>5>');
      await g.run();
      expect(g.rules(), hasLength(4));
      final r = await g.run(['clear']);
      expect(r.exitCode, 0);
      expect(g.rules(), isEmpty);
    });

    test('a rule the router refuses is reported, not hidden', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      File('${g.state.path}/fail_add').writeAsStringSync('');
      final r = await g.run();
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}', contains('failed 2'));
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

  group('the script text', () {
    // 88 and 89 since ID-347. Measured free on a stock router 2026-09-30: the firmware uses 0, 90-91
    // (the guard's), 100, 1016-1029, 32766 and 32767.
    test('uses only priorities 88 to 91, which nothing else on the router uses', () {
      final prios = RegExp(r'priority (\d+)').allMatches(kGuardScript).map((m) => m.group(1)).toSet();
      expect(prios, {'88', '89', '90', '91'});
    });

    test('adds the drop rule before the tunnel rule, so a half-added guard fails closed', () {
      expect(kGuardScript.indexOf('blackhole priority 91 ||'),
          lessThan(kGuardScript.indexOf('suppress_prefixlength 0 priority 90; then')));
    });

    test('has LF line endings only', () => expect(kGuardScript.contains('\r'), isFalse));
  });
}
