// ROUTER RESOLVER STATUS names the slot when a slot that shares the router's DNS addresses is why the router's
// resolver fails (ID-665).
//
// The advice said "Check the DoT Server List in the web interface, or reboot the router." Seen on the emulator on
// 2026-11-22 with a shared slot's tunnel cut: neither helps when the cause is that slot, running and answering
// nothing, or stopped and refused by the guard.
import 'package:cfg_pia_wg/dns_wording.dart';
import 'package:cfg_pia_wg/firmware.dart' show RouterFirmware;
import 'package:cfg_pia_wg/router_dns.dart';
import 'package:flutter_test/flutter_test.dart';

import '../router_dns_fixtures.dart';

const _dead = "nslookup: can't resolve 'example.com'\n@@RC 1\n@@T 100.00 105.00";
const _merlinTunnel = DnsWording(RouterFirmware.merlin, DefaultConnection.tunnel);

/// The facts fixture with one slot line per entry of [slots]: `N|region|up|dns`.
String _facts(List<String> slots) => '$kFactsFixture\n@@SLOTS\n${slots.join('\n')}';

String? _advice(String facts, {DnsWording wording = _merlinTunnel}) {
  final blocks = buildResolverStatus(
      facts: facts,
      checks: '@@CHECK a\n$_dead\n@@CHECK b\n$_dead',
      files: kFilesFixture,
      checkedAt: '04:08:12',
      wording: wording);
  return blocks.whereType<DnsCheck>().single.advice;
}

void main() {
  const shared = '3|pia-aus_melbourne|1|1.1.1.2, 1.0.0.2';
  const elsewhere = '5|pia-uk|1|9.9.9.9';

  group('a running slot that lists the router\'s DoT addresses', () {
    test('is named, as likely to be answering nothing, in place of "check the list or reboot"', () {
      final a = _advice(_facts([shared, elsewhere]))!;
      expect(a, contains('wgc3:pia-aus_melbourne lists those servers and is running'));
      expect(a, contains('may be answering nothing'));
      expect(a, isNot(contains('Check the DoT Server List')));
      expect(a, isNot(contains('reboot')));
      expect(a, startsWith("stubby is running but can't reach your DNS-over-TLS servers, so"), reason: 'the symptom is still said first');
    });

    test('and two of them are named together', () {
      final a = _advice(_facts([shared, '4|pia-nz|1|1.0.0.2']))!;
      expect(a, contains('wgc3:pia-aus_melbourne and wgc4:pia-nz list'.replaceFirst(' list', ' lists')));
      expect(a, contains('are running'));
    });
  });

  group('a stopped slot that lists them', () {
    const stopped = '3|pia-aus_melbourne|0|1.1.1.2, 1.0.0.2';

    test('on Merlin is named as what the guard refuses the router\'s lookups for, with the step to take', () {
      final a = _advice(_facts([stopped]))!;
      expect(a, contains("wgc3:pia-aus_melbourne lists those servers and isn't running"));
      expect(a, contains("the app's guard refuses the router's lookups to them until it is"));
      expect(a, contains('Start it in MANAGE (ENABLE).'));
    });

    test('on stock says nothing of it: a stopped slot there moves its lookups elsewhere, so it is not why they fail', () {
      final a = _advice(_facts([stopped]), wording: DnsWording.stock)!;
      expect(a, contains('Check the DoT Server List'));
      expect(a, isNot(contains('wgc3')));
    });
  });

  group('nothing changes when no slot shares an address', () {
    test('a slot with other servers is not named', () {
      expect(_advice(_facts([elsewhere]))!, contains('Check the DoT Server List in the web interface, or reboot the router.'));
    });

    test('a router that reports no slots, as before this was read, gets the old advice', () {
      expect(_advice(kFactsFixture)!, contains('Check the DoT Server List in the web interface, or reboot the router.'));
    });

    // With DNS-over-TLS off dnsmasq's servers file names the DNS Server setting, and that is what the router uses.
    String dotOff(String facts) => facts.replaceFirst('wan0_dns=1.1.1.2 1.0.0.2', 'wan0_dns=9.9.9.9 9.9.9.10');
    String? adviceDotOff(List<String> slots) {
      final blocks = buildResolverStatus(
          facts: dotOff(_facts(slots)),
          checks: '@@CHECK a\n$_dead',
          files: kFilesFixture.replaceFirst('@@FILE /tmp/resolv.dnsmasq 02:04\nserver=127.0.1.1', '@@FILE /tmp/resolv.dnsmasq 02:04\nserver=9.9.9.9'),
          checkedAt: '04:08:12',
          wording: _merlinTunnel);
      return blocks.whereType<DnsCheck>().single.advice;
    }

    test('with DNS-over-TLS off the DNS Server setting is what counts: a slot on the DoT list is not named', () {
      expect(adviceDotOff([shared]), isNot(contains('wgc3')));
    });

    test('and one on the DNS Server setting is, with DNS-over-TLS off', () {
      expect(adviceDotOff(['3|pia-aus_melbourne|1|9.9.9.9']), contains('wgc3:pia-aus_melbourne lists those servers'));
    });
  });

  test('the facts command reads each slot that has a server, with its interface and DNS', () {
    expect(kResolverFactsCommand, contains('@@SLOTS'));
    expect(kResolverFactsCommand, contains(r'wgc${N}_ep_addr'));
    expect(kResolverFactsCommand, contains(r'ip -o link show wgc$N up'));
    expect(kResolverFactsCommand, contains(r'wgc${N}_dns'));
  });
}
