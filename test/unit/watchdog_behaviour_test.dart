// The watchdog script, run for real against a fake stock router (test/watchdog_harness.dart).
//
// Each group reproduces something found on hardware, so the fault it guards against can never come
// back unnoticed. Skipped where no POSIX shell is on the PATH.
import 'dart:io';

import 'package:cfg_pia_wg/router_watchdog.dart';
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
    group('a healthy tunnel', () {
      test('is checked, passes, and resets the backoff', () async {
        h.backoff(3, 9999);
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log, contains('Checking wgc1 pia-nz connectivity'));
        expect(h.log.any((l) => l.startsWith('Handshake ')), isTrue);
        expect(h.backoffFile, '0\n0\n');
        expect(h.curls, isEmpty, reason: 'a healthy check asks PIA for nothing');
      });

      // ID-194: the router's own resolver, which every unpinned device depends on, gets a line of its
      // own on every run - and is never a reason to touch this tunnel.
      test("logs the router's own resolver as OK", () async {
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log, contains('Router resolver OK'));
      });

      test("a dead router resolver is logged, and the healthy tunnel is left alone", () async {
        h.routerResolverDown();
        final r = await h.run();
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(h.log.any((l) => l.startsWith('Router resolver FAILED')), isTrue);
        expect(h.curls, isEmpty, reason: "no rebuild: it is not the tunnel's fault");
        expect(h.backoffFile, '0\n0\n');
      });

      test('a disabled slot stands down before any probe', () async {
        h.set('wgc1_enable', '0');
        await h.run();
        expect(h.log.last, 'wgc1 is disabled in the router; standing down until it is enabled again');
        expect(h.lookups, isEmpty);
      });
    });

    // BRK-6 on 2026-09-20 "failed" every rung because the test ran the script without a mode, so it
    // relaunched itself in the background and the test read the log before anything was written.
    // Run in the foreground, the ladder does what it says.
    group('the backoff ladder (ID-199)', () {
      const ladder = {1: 120, 2: 240, 3: 480, 4: 960, 5: 1800, 6: 3600, 7: 5400, 12: 5400};
      for (final e in ladder.entries) {
        test('after ${e.key} failed attempts a new check waits ${e.value}s, and asks PIA for nothing', () async {
          h.tunnelUp(handshakeAgo: null);
          h.backoff(e.key, 0);
          await h.run();
          expect(h.log.last,
              matches(RegExp('^Backing off after ${e.key} failed attempts: [0-9]+s of ${e.value}s elapsed\$')));
          expect(h.curls, isEmpty);
          expect(h.backoffFile.split('\n').first, '${e.key}', reason: 'a turned-away run leaves the count alone');
        });
      }
    });

    // BRK-7: a WAN outage is not the tunnel's fault and must not climb the ladder.
    test('a WAN outage exits without climbing the ladder', () async {
      h.tunnelUp(handshakeAgo: null);
      h.wan(false);
      h.backoff(2, 9999);
      await h.run();
      expect(h.log.last, 'no Internet on WAN interface, exiting.');
      expect(h.backoffFile.split('\n').first, '2');
    });

    // ID-192. Found by hand at BRK-8: the strike file was written and then deleted in the same run.
    group('the two-strike DNS rule (ID-192)', () {
      test('one miss is a warning, not a rebuild', () async {
        h.dns('fail');
        await h.run();
        expect(h.log, contains('no answer from 9.9.9.9; one more and it counts as broken'));
        // The router's own resolver is logged after every run's checks, this one included (ID-194).
        expect(h.log.last, 'Router resolver OK');
        expect(h.dnsFailFile, '1');
        expect(h.curls, isEmpty);
      });

      test('a second miss in a row rebuilds the tunnel', () async {
        h.dns('fail');
        await h.run();
        await h.run();
        expect(h.log, contains('wgc1 is up and handshaking, but 9.9.9.9 has answered nothing twice in a row'));
        expect(h.log.any((l) => l.startsWith('Name resolution lost on wgc1; reconfiguring')), isTrue);
      });

      // ID-329: the rebuild was reported as fixing the DNS failure without asking the DNS server again.
      test('a rebuild after a DNS failure asks again, and says so when it still does not answer', () async {
        h.dns('fail');
        await h.run();
        await h.run();
        expect(h.log, contains('Rebuilt wgc1, but 9.9.9.9 still does not answer through it'));
      });

      test('a rebuild after a DNS failure that fixes it is reported as fixed, after asking', () async {
        h.dns('fail');
        await h.run();
        h.dnsFailsUntilRebuild();
        await h.run();
        expect(h.log.where((l) => l.contains('still does not answer')), isEmpty);
        expect(h.lookups.length, greaterThanOrEqualTo(3), reason: 'two misses, then the check after the rebuild');
      });

      test('an answer in between starts the count again', () async {
        h.dns('fail');
        await h.run();
        h.dns('ok');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
        h.dns('fail');
        await h.run();
        // The count started again: this miss is a first strike, a warning, not the second of a pair.
        expect(h.dnsFailFile, '1');
        expect(h.log.where((l) => l.contains('twice in a row')), isEmpty);
      });

      // BRK-9.
      test('a slot with no DNS server set skips the check and passes', () async {
        h.set('wgc1_dns', '');
        await h.run();
        expect(h.log, contains('No DNS server set on wgc1; skipping the name check'));
        expect(h.lookups, isEmpty);
        expect(h.backoffFile, '0\n0\n');
      });

      test('the probe asks through its own tunnel', () async {
        await h.run();
        expect(h.lookups.single, contains('dev wgc1'));
        expect(h.rules.where((r) => r.startsWith('1000:')), isEmpty, reason: 'its temporary rule is removed');
      });
    });

    // A broken tunnel is rebuilt on a new key, restarted through VPN Fusion, and confirmed.
    group('a rebuild', () {
      test('ends in SUCCESS on the new server', () async {
        h.tunnelUp(handshakeAgo: null);
        final r = await h.run();
        expect(r.exitCode, 0, reason: h.log.join('\n'));
        expect(h.get('wgc1_ppub'), 'NEWSERVERKEY');
        expect(h.services, contains('restart_vpnc'));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
      });

      test('on stock, restarts through VPN Fusion on its own clientlist row', () async {
        h.tunnelUp(handshakeAgo: null);
        await h.run();
        expect(h.log, contains('Restarting wgc1 through VPN Fusion (vpnc_unit=0)'));
        expect(h.get('vpnc_unit'), '0');
      });

      // BRK-3.
      test('an interface that is down is rebuilt, and comes back up', () async {
        h.tunnelDown();
        await h.run();
        expect(h.log, contains('Interface wgc1 is down or absent'));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
        expect(h.isUp, isTrue);
      });

      // BRK-3, second half: the interface on its own is not a success.
      test('one that never handshakes is a FAILED', () async {
        h.tunnelUp(handshakeAgo: null);
        h.neverHandshakes();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(h.log.last, 'ERROR: wgc1 came up but the PIA server never answered it (no handshake in 20s)');
      });

      // BRK-5.
      // ID-245: the email said "failed to obtain PIA token (exit 0, HTTP 504, body 16B: error code:
      // 504)", which reads as the router's fault.
      test("PIA's login service being down is named as PIA's, not the login's", () async {
        h.tunnelUp(handshakeAgo: null);
        h.piaDown();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(
            h.log,
            contains("ERROR: PIA's login service isn't answering (HTTP 504). This is at PIA's end; "
                'the watchdog will try again.'));
        expect(h.log.where((l) => l.contains('rejected the username')), isEmpty);
      });

      test('a rejected PIA login says so, and counts one attempt', () async {
        h.tunnelUp(handshakeAgo: null);
        h.piaRejects();
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(
            h.log.any(
                (l) => l.startsWith('ERROR: PIA rejected the username and password stored on this router (HTTP 403)')),
            isTrue,
            reason: h.log.join('\n'));
        expect(h.backoffFile.split('\n').first, '1');
        expect(h.services, isEmpty, reason: 'nothing is written or restarted without a token');
      });

      // ID-222: the certificate download had no fallback, so a resolver problem stopped the rebuild
    // at its first step, and said "not valid PEM" when nothing had been downloaded at all.
    WatchdogConfig withDoh() => WatchdogConfig(
          slotIndex: 1,
          cronIntervalMinutes: 5,
          primaryIp: '8.8.8.8',
          secondaryIp: '1.1.1.1',
          piaUsername: 'p123456789',
          piaPassword: 'secret',
          dohUrl: 'https://freedns.controld.com/p1',
          dohIp: '76.76.2.1',
        );

    test('downloads the certificate when it has none', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      await h.run(config: withDoh());
      expect(h.log, contains(startsWith('CA cert cached at')));
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
    });

    // ID-331: a DELETE made while a rebuild was under way was undone by it - the run wrote enable=1
    // and restarted the tunnel the user had just removed.
    test('a watchdog deleted mid-rebuild stops the rebuild before it writes anything', () async {
      h.tunnelUp(handshakeAgo: null);
      h.deletedDuringRebuild();
      await h.run();
      expect(h.log, contains("wgc1's watchdog was deleted while this run was rebuilding; stopping before writing anything"));
      expect(h.nvramWrites.where((w) => w.startsWith('set wgc1_')), isEmpty);
      expect(h.services, isEmpty, reason: 'nothing restarted');
    });

    // The CA pin, as measured on ASUS's curl 2026-09-30: --cacert is honoured, so a cached file that
    // is not PIA's CA stops the rebuild at addKey rather than trusting whoever answered (ID-341).
    test('addKey refuses a server when the cached CA is not PIA\'s', () async {
      h.tunnelUp(handshakeAgo: null);
      File('${h.root.path}/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt')
          .writeAsStringSync('-----BEGIN CERTIFICATE-----\nSOMEONE-ELSE\n-----END CERTIFICATE-----\n');
      await h.run();
      expect(h.log, contains(startsWith('ERROR: curl addKey failed (exit 60')));
      expect(h.log.where((l) => l.startsWith('Reconfig SUCCESS')), isEmpty);
    });

    // What MRL-8 found on 2026-09-30 (ID-307): the router's own resolver is down, and because ASUS's
    // curl ignores --doh-url, "encrypted DNS" was never a way round it. The script's own lookup is.
    test('with the router resolver down, the rebuild still finds PIA through its own DoH lookups (ID-307)', () async {
      h.tunnelUp(handshakeAgo: null);
      h.noCachedCert();
      h.systemDnsDown();
      await h.run(config: withDoh());
      expect(h.resolvedBySystem, isEmpty, reason: 'nothing asked of the ordinary resolver');
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
    });

    test('a DoH pair stored the wrong way round is named in the log, not passed off as none (ID-221)', () async {
      h.tunnelUp(handshakeAgo: null);
      await h.run(
          config: WatchdogConfig(
        slotIndex: 1,
        cronIntervalMinutes: 5,
        primaryIp: '8.8.8.8',
        secondaryIp: '1.1.1.1',
        piaUsername: 'p123456789',
        piaPassword: 'secret',
        dohUrl: '76.76.2.1',
        dohIp: 'https://freedns.controld.com/p1',
      ));
      expect(h.log, contains(startsWith('Name lookups are NOT encrypted: encrypted DNS is set')));
    });

    test('clears the DNS strike count', () async {
        h.tunnelUp(handshakeAgo: null);
        File('${h.root.path}/tmp/watchdog_dnsfail_wgc1').writeAsStringSync('1');
        await h.run();
        expect(h.dnsFailFile, isEmpty);
      });
    });

    // ID-214. Seen on 2026-09-21: the router was busy, dropped the restart, and the old peer's old
    // handshake passed every check after it. The rebuild was reported as a SUCCESS that never happened.
    group('a restart the router skips (ID-214)', () {
      test('is noticed, and tried once more', () async {
        h.tunnelUp(handshakeAgo: null);
        h.skipRestarts(1);
        await h.run();
        expect(h.log, contains('The router skipped the restart of wgc1; trying once more'));
        expect(h.services.where((s) => s == 'restart_vpnc'), hasLength(2));
        expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
      });

      test('twice is a FAILED, never a SUCCESS', () async {
        h.tunnelUp(handshakeAgo: null);
        h.skipRestarts(2);
        final r = await h.run();
        expect(r.exitCode, 1);
        expect(h.log.any((l) => l.startsWith('ERROR: the router skipped the restart of wgc1 twice')), isTrue);
        expect(h.log.where((l) => l.contains('SUCCESS')), isEmpty);
      });

      test('a ghost rc_service marker is cleared before the restart', () async {
        h.tunnelUp(handshakeAgo: null);
        h.set('rc_service', 'restart_vpnc');
        h.set('rc_service_pid', '999999');
        await h.run();
        expect(h.log.any((l) => l.startsWith('Cleared a stale rc_service marker (restart_vpnc, pid 999999)')), isTrue);
        expect(h.get('rc_service'), isEmpty);
        expect(h.log.last, startsWith('Reconfig SUCCESS'));
      });
    });

    // ID-227, measured 2026-09-27: watchdog runs packed into a few seconds crash the firmware's asd,
  // and every crash restarts the firewall. Spaced 15 s apart they did not.
  group('spacing the watchdogs out (ID-227)', () {
    Future<List<String>> sleepsFor(int slot, String mode) async {
      final w = WatchdogHarness.create(slot: slot, shell: shell)!;
      addTearDown(w.dispose);
      await w.run(mode: mode);
      return w.sleeps;
    }

    test('a cron start waits 15 s for every slot below it', () async {
      expect(await sleepsFor(5, 'detached'), contains('60'));
      expect(await sleepsFor(3, 'detached'), contains('30'));
    });

    test('wgc1 starts at once', () async {
      expect((await sleepsFor(1, 'detached')).where((s) => s != '1'), isEmpty,
          reason: 'only the one-second waits for the hand-over to init');
    });

    test('a deploy and a run by hand are never delayed', () async {
      expect(await sleepsFor(5, 'deploy'), isNot(contains('60')));
      expect(await sleepsFor(5, 'foreground'), isNot(contains('60')));
    });
  });

  // ID-240: found 2026-09-27. MANAGE DELETE removed wgc2's watchdog while its cron run was waiting
  // its 15 s, and the run woke and carried on: the shell already had the script open.
  group('a watchdog paused or removed while its run waits', () {
    test('a cron run whose schedule has gone stands down, having done nothing', () async {
      h.unschedule();
      final r = await h.run(mode: 'detached');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(h.log.last, "wgc1's watchdog was paused or removed while this run waited; standing down");
      expect(h.lookups, isEmpty);
      expect(h.curls, isEmpty);
    });

    test('a cron run that is still scheduled carries on', () async {
      await h.run(mode: 'detached');
      expect(h.log, contains('Checking wgc1 pia-nz connectivity'));
    });

    test('a run whose settings have gone stands down, rather than pinging nothing', () async {
      h.set('wgc1_wd_check_interval', '');
      await h.run();
      expect(h.log.last, 'wgc1 has no watchdog settings; standing down');
      expect(h.log.where((l) => l.contains('no Internet on WAN')), isEmpty);
    });

    test('a deploy runs whatever the schedule says: it is what writes the schedule', () async {
      h.unschedule();
      await h.run(mode: 'deploy');
      expect(h.log.where((l) => l.contains('standing down')), isEmpty);
    });
  });

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
