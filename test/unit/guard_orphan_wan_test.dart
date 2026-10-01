// Runs the real guard script under a POSIX shell, against the fake router in guard_harness.dart:
// pins to deleted profiles, and the addresses a tunnel's table sends out the WAN.
//
// The first behavioural test of router-side shell in this repo (BACKLOG ID-205 is the wider
// harness). String checks alone would have passed a script that re-added its rules on every run,
// which is exactly the kind of fault only running it finds. Skipped where no `sh` is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_harness.dart';

void main() {
  final g = GuardRouter();
  final shell = g.shell;

  setUp(g.setUp);
  tearDown(g.tearDown);

  // Hostile review (ID-346): a profile deleted in the web interface leaves its pins behind, and the
  // guard used to drop those devices' rules, sending them to the default connection.
  group('guard.sh: a pin to a profile that no longer exists', () {
    test('is kept off the internet by rule 91 alone, counted, and logged once', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.60>>7>');
      final r = await g.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), ['91: from 192.0.2.60 blackhole']);
      expect(g.log().where((l) => l.contains('no longer exists')), hasLength(1));
      await g.run();
      expect(g.rules(), ['91: from 192.0.2.60 blackhole'], reason: 'a second run adds nothing');
      expect(g.log().where((l) => l.contains('no longer exists')), hasLength(1), reason: 'and logs nothing more');
    });

    test('keeps its rule 91 when it had a full guard before its profile went', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.60>>5>');
      await g.run();
      expect(g.rules(), contains('91: from 192.0.2.60 blackhole'));
      g.set('vpnc_clientlist', 'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg');
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), ['91: from 192.0.2.60 blackhole'], reason: 'rule 90 goes with the profile; 91 stays');
    });

    test('pins to an OpenVPN profile and to Internet are left alone', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.61>>3><1>192.0.2.62>>0>');
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 0 of 0'));
      expect(g.rules(), isEmpty);
    });

    test('its rule goes when the pin does', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.60>>7>');
      await g.run();
      g.set('vpnc_dev_policy_list', '0>192.0.2.60>>0>');
      await g.run();
      expect(g.rules(), isEmpty);
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

  group('guard.sh: what the tunnel\'s table sends out the WAN (ID-347)', () {
    test('each such address is held to the tunnel, with a blackhole behind it', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      g.up('wgc5');
      final r = await g.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 5 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
        for (final x in ['1.1.1.2', '203.0.113.9', '198.51.100.0/24']) ...[
          '88: from 192.0.2.50 to $x lookup 205',
          '89: from 192.0.2.50 to $x blackhole',
        ],
      ]));
      expect(File('${g.state.path}/table_205').readAsLinesSync(),
          unorderedEquals(['0.0.0.0/1 dev wgc5 scope link', '128.0.0.0/1 dev wgc5 scope link']));
    });

    test('a second run changes nothing', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      g.up('wgc5');
      await g.run();
      final before = g.rules();
      await g.run();
      expect(g.rules(), before);
    });

    test('with the tunnel down, its tunnel-only table stays empty, so the blackhole decides', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      await g.run();
      expect(g.rules(), contains('89: from 192.0.2.50 to 1.1.1.2 blackhole'));
      expect(File('${g.state.path}/table_205').existsSync(), isFalse);
    });

    test('a new PIA server replaces the old one\'s rules', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      g.up('wgc5');
      await g.run();
      g.table5(endpoint: '203.0.113.77');
      await g.run();
      expect(g.rules().where((r) => r.contains('203.0.113.9')), isEmpty);
      expect(g.rules(), contains('89: from 192.0.2.50 to 203.0.113.77 blackhole'));
    });

    test('a blackhole that cannot be added is counted as not guarded, and reported', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      File('${g.state.path}/fail_add_89').writeAsStringSync('1');
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 0 of 1'));
      expect(r.exitCode, isNot(0));
    });

    test('clear removes them, and empties the tunnel-only table', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.table5();
      g.up('wgc5');
      await g.run();
      await g.run(['clear']);
      expect(g.rules(), isEmpty);
      expect(File('${g.state.path}/table_205').existsSync(), isFalse);
    });
  });
}
