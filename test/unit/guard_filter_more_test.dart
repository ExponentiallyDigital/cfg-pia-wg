// Runs the real guard script under a POSIX shell, against the fake router in guard_harness.dart:
// the Network Services Filter, part two.
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

  group('guard.sh: the Network Services Filter', () {
    test('an allow list is refused, and the app takes its own entries out of one', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      g.set('filter_lw_default_x', 'DROP');
      final r = await g.run();
      expect('${r.stdout}', contains('filter refused: it is an allow list'));
      expect(g.nv('filter_lwlist'), '', reason: 'in an allow list, its entries would let the device out');
      expect(g.nv('cfg_pia_wg_lwlist'), '');
    });

    test("a filter that is off with the user's entries in it is not turned on", () async {
      g.set('filter_lwlist', '<192.0.2.99>>>>TCP');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await g.run();
      expect('${r.stdout}', contains('filter refused: it is off, and turning it on would also apply the entries you made'));
      expect(g.nv('fw_lw_enable_x'), '0');
      expect(g.nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(g.commits(), 0);
    });

    test('a firewall with no filter at all is refused', () async {
      g.set('fw_enable_x', '0');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await g.run();
      expect('${r.stdout}', contains("filter refused: the router's firewall is off"));
      expect(g.nv('filter_lwlist'), '');
    });

    test('pings are held only when the user asks, and the setting is put back as it was', () async {
      g.set('filter_lw_icmp_x', '0');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      expect(g.nv('filter_lw_icmp_x'), '0', reason: 'off by default');
      g.set('cfg_pia_wg_lw_icmp', '1');
      await g.run();
      expect(g.nv('filter_lw_icmp_x'), '0 8');
      expect(g.fw(), contains('-A FORWARD -i br0 -o eth0 -p icmp -m icmp --icmp-type 8 -j DROP'));
      g.set('cfg_pia_wg_lw_icmp', '0');
      await g.run();
      expect(g.nv('filter_lw_icmp_x'), '0');
      expect(g.nv('cfg_pia_wg_lw_icmp8'), '');
    });

    test('a restart the service queue dropped is asked for again', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      File('${g.state.path}/drop_service').writeAsStringSync('');
      final r1 = await g.run();
      expect('${r1.stdout}', contains('filter held 0 of 1'));
      File('${g.state.path}/drop_service').deleteSync();
      final r2 = await g.run();
      expect('${r2.stdout}', contains('filter held 1 of 1'), reason: 'the settings were right; the firewall was asked again');
      expect(g.services().where((s) => s == 'restart_firewall'), hasLength(2));
    });

    test('a timetable on the filter is reported', () async {
      g.set('filter_lw_date_x', '0111110');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await g.run();
      expect('${r.stdout}', contains('filter scheduled'));
    });

    test('a pin to a deleted profile is listed too, and clear takes out only the app\'s entries', () async {
      g.set('fw_lw_enable_x', '1');
      g.set('filter_lwlist', '<192.0.2.99>>>>TCP');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5><1>192.0.2.60>>7>');
      final r = await g.run();
      expect('${r.stdout}', contains('filter held 2 of 2'));
      expect(g.nv('filter_lwlist'), contains('<192.0.2.60>>>>UDP'));
      await g.run(['clear']);
      expect(g.nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(g.nv('cfg_pia_wg_lwlist'), '');
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);
}
