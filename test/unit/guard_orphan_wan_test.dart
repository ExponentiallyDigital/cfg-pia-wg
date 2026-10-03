// Runs the real guard script under a POSIX shell, against the fake router in guard_harness.dart:
// pins to deleted profiles, the guard's own table for each tunnel, and `guard.sh soon`.
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

  // ID-364. The guard keeps a table of its own per tunnel, 200 + slot, and rule 90 looks the device
  // up there. It holds the tunnel's default and the router's local routes and never a route via the
  // WAN - so the router's DNS servers, its gateway and the WAN subnet go through the tunnel like
  // everything else, which is what rules 88 and 89 used to arrange address by address (ID-347).
  group("guard.sh: the guard's own table for each tunnel (ID-364)", () {
    const local = [
      '10.6.0.2 dev wgs1 scope link',
      '127.0.0.0/8 dev lo scope link',
      '192.168.1.0/24 dev br0 scope link',
      '192.168.101.0/24 dev br1 scope link',
    ];

    test('holds the local routes and the tunnel default, and nothing via the WAN', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      g.up('wgc5');
      final r = await g.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), unorderedEquals(['90: from 192.0.2.50 lookup 205', '91: from 192.0.2.50 blackhole']));
      expect(g.table(205), unorderedEquals([...local, 'default dev wgc5 scope link']));
      expect(g.table(205).where((l) => l.contains('eth0')), isEmpty);
    });

    test('with the tunnel down it gets no default, so rule 91 decides', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 1 of 1'), reason: 'the rules are the guard; the table only restores service');
      expect(g.table(205).where((l) => l.startsWith('default')), isEmpty);
    });

    test('a second run changes nothing', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      g.up('wgc5');
      await g.run();
      final rules = g.rules(), table = g.table(205);
      await g.run();
      expect(g.rules(), rules);
      expect(g.table(205), table);
    });

    test('only tunnels with a pin get a table, and one nobody is pinned to any more is emptied', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      g.up('wgc5');
      await g.run();
      expect(g.table(201), isEmpty);
      expect(g.table(205), isNotEmpty);
      g.set('vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      await g.run();
      expect(g.table(205), isEmpty);
    });

    // Nothing the guard adds can leave by the WAN, but a route that did, put there by anything else,
    // would send the device out by it ahead of rule 91. So every run takes out what it wouldn't add.
    for (final up in [true, false]) {
      test('a route out of the WAN found in its table is taken out, with the tunnel ${up ? 'up' : 'down'}', () async {
        g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
        g.mainTable();
        if (up) g.up('wgc5');
        await g.run();
        File('${g.state.path}/table_205')
            .writeAsStringSync('198.51.100.0/24 dev eth0  proto kernel  scope link  src 198.51.100.36\n', mode: FileMode.append);
        final r = await g.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(g.table(205).where((l) => l.contains('eth0')), isEmpty);
        expect(g.table(205), up ? unorderedEquals([...local, 'default dev wgc5 scope link']) : isEmpty);
      });
    }

    test('rules 88 and 89 from before build 491 are taken out', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      File('${g.state.path}/rules').writeAsStringSync([
        for (final x in ['1.1.1.2', '203.0.113.9', '198.51.100.0/24', '198.51.100.1', '1.0.0.2']) ...[
          '88:\tfrom 192.0.2.50 to $x lookup 205',
          '89:\tfrom 192.0.2.50 to $x blackhole',
        ],
        '90:\tfrom 192.0.2.50 lookup 5 suppress_prefixlength 0',
        '91:\tfrom 192.0.2.50 blackhole',
      ].join('\n'));
      final r = await g.run();
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), unorderedEquals(['90: from 192.0.2.50 lookup 205', '91: from 192.0.2.50 blackhole']));
    });

    test('clear removes every rule and empties the tables', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      g.mainTable();
      g.up('wgc5');
      await g.run();
      await g.run(['clear']);
      expect(g.rules(), isEmpty);
      expect(g.table(205), isEmpty);
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

  // ID-364. The boot hook calls `guard.sh soon` on every firewall-start, and a restart_vpnc alone
  // raised three inside two seconds (2026-10-03). Runs a second or so apart are what crash the
  // firmware's asd (ID-361), so a burst must cost one run.
  group('guard.sh soon', () {
    test('runs once the wait is over', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      final r = await g.run(['soon']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(g.rules(), hasLength(2));
    });

    test('a burst of requests costs one run, the last', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      g.soonSeconds = 4;
      final first = g.run(['soon']);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final second = g.run(['soon']);
      final results = await Future.wait([first, second]);
      expect('${results[0].stdout}', isNot(contains('guarded')), reason: 'a newer request came, so this one stood down');
      expect('${results[1].stdout}', contains('guarded 1 of 1'));
      expect(g.log(), ['Fail-closed guard on for 192.0.2.50 (wgc1)'], reason: 'one run, so one line');
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);
}
