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

    // ID-377, measured on stock 2026-10-12: the app's record of its entries was empty, the filter off,
    // and two pinned devices' entries still in it, in the app's own form. They read as the user's, so
    // the filter was refused for all twelve pinned devices, and stayed refused run after run.
    group("entries the app's record has lost (ID-377)", () {
      test('are claimed, so the filter goes on and holds every pinned device', () async {
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5><1>192.0.2.21>>9>');
        final r = await g.run();
        expect('${r.stdout}', isNot(contains('filter refused')));
        expect('${r.stdout}', contains('filter claimed 192.0.2.20/TCP 192.0.2.20/UDP'));
        expect('${r.stdout}', contains('filter held 2 of 2'));
        expect(g.nv('fw_lw_enable_x'), '1');
        expect(g.nv('cfg_pia_wg_lwlist').split(' '),
            unorderedEquals(['192.0.2.20/TCP', '192.0.2.20/UDP', '192.0.2.21/TCP', '192.0.2.21/UDP']));
        expect(g.filterLog(), contains(contains("took over entries that matched the app's own")));
      });

      test('once claimed, they are the app\'s: unpinning takes them out, and the filter goes off again', () async {
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        await g.run();
        final again = await g.run();
        expect('${again.stdout}', isNot(contains('filter claimed')), reason: 'claimed once, then simply the app\'s');
        g.set('vpnc_dev_policy_list', '');
        await g.run();
        expect(g.nv('filter_lwlist'), '');
        expect(g.nv('cfg_pia_wg_lwlist'), '');
        expect(g.nv('fw_lw_enable_x'), '0', reason: 'the app turned it on, and nothing is left in it');
      });

      test('only one of the pair is there: that one is claimed and the other added', () async {
        g.set('filter_lwlist', '<192.0.2.20>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        final r = await g.run();
        expect('${r.stdout}', contains('filter claimed 192.0.2.20/UDP'));
        expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>UDP<192.0.2.20>>>>TCP');
        expect(g.nv('cfg_pia_wg_lwlist').split(' '), unorderedEquals(['192.0.2.20/TCP', '192.0.2.20/UDP']));
      });

      test("an entry with anything else filled in is the user's, not claimed, and still refuses", () async {
        g.set('filter_lwlist', '<192.0.2.20>>>443>TCP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        final r = await g.run();
        expect('${r.stdout}', contains('filter refused: it is off'));
        expect('${r.stdout}', isNot(contains('filter claimed')));
        expect(g.nv('cfg_pia_wg_lwlist'), '');
      });

      // The same router the next day, 2026-10-13: one of the two devices had been set to Internet
      // meanwhile, and kept its entries, because nothing recorded them as the app's to take out. Left
      // the user's, they would have kept the filter refused - and, turned on, cut that device off.
      test("a device set to Internet since the record was lost: its entries are claimed and taken out", () async {
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP<192.0.2.55>>>>TCP<192.0.2.55>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5><0>192.0.2.55>>0>');
        final r = await g.run();
        expect('${r.stdout}', isNot(contains('filter refused')));
        expect('${r.stdout}', contains('filter claimed 192.0.2.20/TCP 192.0.2.20/UDP 192.0.2.55/TCP 192.0.2.55/UDP'));
        expect('${r.stdout}', contains('filter released 192.0.2.55/TCP 192.0.2.55/UDP'));
        expect('${r.stdout}', contains('filter held 1 of 1'));
        expect(g.nv('fw_lw_enable_x'), '1');
        expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP', reason: 'the Internet device is not blocked');
        expect(g.nv('cfg_pia_wg_lwlist').split(' '), unorderedEquals(['192.0.2.20/TCP', '192.0.2.20/UDP']));
        expect(g.filterLog(), contains(contains('took out the ones for devices not pinned to a tunnel: 192.0.2.55/TCP 192.0.2.55/UDP')));
      });

      test('with nothing pinned, nothing is claimed: the guard leaves the filter alone', () async {
        g.set('filter_lwlist', '<192.0.2.55>>>>TCP');
        g.set('vpnc_dev_policy_list', '0>192.0.2.55>>0>');
        final r = await g.run();
        expect('${r.stdout}', isNot(contains('filter claimed')));
        expect(g.nv('filter_lwlist'), '<192.0.2.55>>>>TCP');
        expect(g.nv('fw_lw_enable_x'), '0');
      });

      test("UNINSTALL's clean-up claims nothing: it takes out only what the record lists", () async {
        g.set('filter_lwlist', '<192.0.2.55>>>>TCP<192.0.2.55>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5><0>192.0.2.55>>0>');
        g.set('fw_lw_enable_x', '1');
        final r = await g.run(['clear']);
        expect('${r.stdout}', isNot(contains('filter claimed')));
        expect(g.nv('filter_lwlist'), '<192.0.2.55>>>>TCP<192.0.2.55>>>>UDP');
      });

      test("an entry for an address DEVICES doesn't know is the user's, not claimed, and still refuses", () async {
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP<192.0.2.99>>>>TCP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        final r = await g.run();
        expect('${r.stdout}', contains('filter refused: it is off'));
        expect('${r.stdout}', isNot(contains('filter claimed')), reason: 'a refused run claims nothing');
        expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.99>>>>TCP');
        expect(g.nv('cfg_pia_wg_lwlist'), '');
        expect(g.commits(), 0);
      });

      test('an allow list claims nothing: there, an entry lets a device out', () async {
        g.set('filter_lw_default_x', 'DROP');
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        final r = await g.run();
        expect('${r.stdout}', contains('filter refused: it is an allow list'));
        expect('${r.stdout}', isNot(contains('filter claimed')));
        expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>TCP', reason: 'the user\'s, so left alone');
        expect(g.nv('cfg_pia_wg_lwlist'), '');
      });

      test('with the filter already on, a lost entry is claimed too, so unpinning can clean it up', () async {
        g.set('fw_lw_enable_x', '1');
        g.set('filter_lwlist', '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
        g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
        final r = await g.run();
        expect('${r.stdout}', contains('filter claimed 192.0.2.20/TCP 192.0.2.20/UDP'));
        g.set('vpnc_dev_policy_list', '');
        await g.run();
        expect(g.nv('filter_lwlist'), '', reason: 'left unclaimed, it would keep an unpinned device off the internet');
      });
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

    // ID-364. The guard runs on firewall-start, which every firewall restart raises, so asking for a
    // restart whenever the read-back came up short would loop. It asks only when the list changed,
    // and a restart the queue dropped is put right by the router's next one, whatever causes it.
    test('a firewall restart is asked for only when the list changed, so a run on firewall-start cannot loop', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      File('${g.state.path}/drop_service').writeAsStringSync('');
      final r1 = await g.run();
      expect('${r1.stdout}', contains('filter held 0 of 1'), reason: 'the restart was dropped, and the report says so');
      File('${g.state.path}/drop_service').deleteSync();
      final r2 = await g.run();
      expect('${r2.stdout}', contains('filter held 0 of 1'));
      expect(g.services().where((s) => s == 'restart_firewall'), hasLength(1), reason: 'the list was already right');
      await g.firewallRestart();
      final r3 = await g.run();
      expect('${r3.stdout}', contains('filter held 1 of 1'), reason: "the router's own restart built it from NVRAM");
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
