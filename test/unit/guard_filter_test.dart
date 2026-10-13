// Runs the real guard script under a POSIX shell, against the fake router in guard_harness.dart:
// the Network Services Filter, part one.
//
// The first behavioural test of router-side shell in this repo (BACKLOG ID-205 is the wider
// harness). String checks alone would have passed a script that re-added its rules on every run,
// which is exactly the kind of fault only running it finds. Skipped where no `sh` is on the PATH.

// Two minutes a test, not the default 30 s: these run real router scripts under a POSIX shell, and on
// Windows, with the split files running side by side, one took up to 20 s and some passed 30 (2026-10-01).
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import 'guard_harness.dart';

void main() {
  final g = GuardRouter();
  final shell = g.shell;

  setUp(g.setUp);
  tearDown(g.tearDown);

  // ID-348: the second layer, stock's Network Services Filter, which holds from boot.
  group('guard.sh: the Network Services Filter', () {
    const drop20Tcp = '-A FORWARD -s 192.0.2.20/32 -i br0 -o eth0 -p tcp -j DROP';
    const drop20Udp = '-A FORWARD -s 192.0.2.20/32 -i br0 -o eth0 -p udp -j DROP';

    test('a pinned device is listed for TCP and UDP, the filter turned on, and the firewall shows it', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await g.run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(g.nv('fw_lw_enable_x'), '1');
      expect(g.nv('cfg_pia_wg_lw_on'), '1');
      expect(g.nv('cfg_pia_wg_lwlist'), '192.0.2.20/TCP 192.0.2.20/UDP');
      expect(g.fw(), [drop20Tcp, drop20Udp]);
      expect(g.commits(), 1, reason: 'it has to survive a reboot');
      expect('${r.stdout}', contains('filter held 1 of 1'));
      expect(g.filterLog(), ['Network Services Filter: 1 pinned device(s) kept off the internet connection outside their tunnel']);
    });

    test('an unchanged list costs no NVRAM write and no firewall restart', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      final c = g.commits(), s = g.services().length;
      final r = await g.run();
      expect(g.commits(), c);
      expect(g.services(), hasLength(s), reason: 'cron runs it every minute');
      expect('${r.stdout}', contains('filter held 1 of 1'));
    });

    test('an unpinned device is taken out, and the filter turned off again if the app turned it on', () async {
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      g.set('vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      final r = await g.run();
      expect(g.nv('filter_lwlist'), '');
      expect(g.nv('fw_lw_enable_x'), '0');
      expect(g.nv('cfg_pia_wg_lw_on'), '');
      expect(g.nv('cfg_pia_wg_lwlist'), '');
      expect(g.fw(), isEmpty);
      expect('${r.stdout}', isNot(contains('filter')), reason: 'nothing pinned, nothing to say');
    });

    test("the user's own entries are kept, and a filter they turned on stays on", () async {
      g.set('fw_lw_enable_x', '1');
      g.set('filter_lwlist', '<192.0.2.99>>>>TCP');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      expect(g.nv('filter_lwlist'), '<192.0.2.99>>>>TCP<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(g.nv('cfg_pia_wg_lw_on'), '', reason: 'the app did not turn it on');
      g.set('vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      await g.run();
      expect(g.nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(g.nv('fw_lw_enable_x'), '1');
    });

    // Until ID-377 this entry stayed the user's, and stayed after the unpin. Now an unrecorded entry
    // in exactly the app's form, for a pinned device, is claimed: it can't be told from one the app
    // lost the record of, and left unclaimed it kept an unpinned device off the internet. Andrew's
    // decision, 2026-10-13, accepting that a hand-made entry of exactly that form goes with the unpin.
    test("an entry in the app's own form for a pinned device is claimed, and goes with the unpin", () async {
      g.set('fw_lw_enable_x', '1');
      g.set('filter_lwlist', '<192.0.2.20>>>>TCP');
      g.set('vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await g.run();
      expect(g.nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(g.nv('cfg_pia_wg_lwlist').split(' '), unorderedEquals(['192.0.2.20/TCP', '192.0.2.20/UDP']));
      g.set('vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      await g.run();
      expect(g.nv('filter_lwlist'), '');
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);
}
