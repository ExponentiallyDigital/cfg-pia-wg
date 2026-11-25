// test/unit/dot_overlap_test.dart - when a slot's DNS is also the router's own (ID-005).
//
// The overlap is what sends the router's own lookups, and every unpinned device's, down one slot's
// tunnel (ID-001). The app only ever says so - the user's DNS settings are the user's - so what is
// pinned here is that it says so at the right times and stays quiet the rest of the time.
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String nvram(String enable, String list) => '$enable\n---\n$list';

  // Measured on a stock router, 2026-09-19.
  const realList = '<9.9.9.9>853>dns.quad9.net><149.112.112.112>853>dns.quad9.net>';

  group('the router\'s own DoT servers', () {
    test('are read from the WebUI list', () {
      expect(parseDotServerList(nvram('1', realList)), {'9.9.9.9', '149.112.112.112'});
    });

    test('are nothing at all when DNS Privacy is off', () {
      // The list stays in nvram with the feature switched off, and then it routes nothing.
      expect(parseDotServerList(nvram('0', realList)), isEmpty);
      expect(parseDotServerList(nvram('', realList)), isEmpty);
    });

    test('an empty or malformed list is empty, not a crash', () {
      expect(parseDotServerList(nvram('1', '')), isEmpty);
      expect(parseDotServerList(''), isEmpty);
      expect(parseDotServerList('1'), isEmpty, reason: 'no separator, so nothing to read');
      expect(parseDotServerList(nvram('1', '<>853>somewhere>')), isEmpty, reason: 'a record with no address');
    });
  });

  // ID-636: with DNS-over-TLS off, the router's own lookups on Merlin use the DNS Server setting, `wan0_dns`, so
  // those are the addresses a slot can share (measured 2026-11-22, the setting and the list set to different
  // addresses). Stock's answer is unchanged.
  group('the DNS Server setting, on Merlin, while DNS-over-TLS is off', () {
    String three(String enable, String list, String wan) => '$enable\n---\n$list\n---\n$wan';

    test("are the router's own lookups' addresses, and the DoT list is not", () {
      expect(parseDotServerList(three('0', realList, '1.1.1.2 1.0.0.2'), dnsServerWhenOff: true), {'1.1.1.2', '1.0.0.2'});
    });

    test('with DNS-over-TLS on the DoT list is, and the DNS Server setting is not', () {
      expect(parseDotServerList(three('1', realList, '1.1.1.2 1.0.0.2'), dnsServerWhenOff: true), {'9.9.9.9', '149.112.112.112'});
    });

    test('on stock, and by default, with DNS-over-TLS off it is nothing, as before', () {
      expect(parseDotServerList(three('0', realList, '1.1.1.2 1.0.0.2')), isEmpty);
      expect(parseDotServerList(three('0', realList, '1.1.1.2 1.0.0.2'), dnsServerWhenOff: false), isEmpty);
    });

    test('a setting that was not read, or is empty, is nothing', () {
      expect(parseDotServerList(nvram('0', realList), dnsServerWhenOff: true), isEmpty, reason: 'no third part');
      expect(parseDotServerList(three('0', realList, ''), dnsServerWhenOff: true), isEmpty);
    });

    test('the command asks for the DNS Server setting as well', () {
      expect(kDotServerListCommand, contains(r'wan${U}_dns'), reason: "the WAN carrying the traffic's setting (ID-721)");
      expect(kDotServerListCommand, contains('wan_primary'));
      expect(kDotServerListCommand, isNot(contains('nvram set')));
    });
  });

  group('what a slot shares with it', () {
    const router = {'9.9.9.9', '149.112.112.112'};

    test('addresses are found however the field is punctuated', () {
      expect(dnsAddressesIn('9.9.9.9, 149.112.112.112'), {'9.9.9.9', '149.112.112.112'});
      expect(dnsAddressesIn('9.9.9.9 149.112.112.112'), {'9.9.9.9', '149.112.112.112'});
      expect(dnsAddressesIn('  9.9.9.9 ,149.112.112.112  '), {'9.9.9.9', '149.112.112.112'});
      expect(dnsAddressesIn(''), isEmpty);
    });

    test('an overlap names the addresses that overlap, not the whole field', () {
      expect(dnsSharedWithRouter('9.9.9.9, 1.1.1.1', router), {'9.9.9.9'});
      expect(dnsSharedWithRouter('9.9.9.9, 149.112.112.112', router), router);
    });

    test('different addresses share nothing, which is the quiet case', () {
      expect(dnsSharedWithRouter('1.1.1.1, 1.0.0.1', router), isEmpty);
      // Quad9's location-hint pair is a different service on different addresses.
      expect(dnsSharedWithRouter('9.9.9.11, 149.112.112.11', router), isEmpty);
    });

    test('with no router list there is nothing to say', () {
      expect(dnsSharedWithRouter('9.9.9.9, 149.112.112.112', const {}), isEmpty);
    });
  });

  // ID-609, measured on Merlin 388.13_0, 2026-11-15: with wgc1's DNS set to 1.1.1.2, wgc5's
  // watchdog's encrypted lookups to 1.1.1.2 went through wgc1. Both firmwares route the router's own
  // traffic to a slot's DNS servers into a slot, so a watchdog whose DoH address is one of them
  // depends on that slot, and the DNS field said nothing.
  group("a slot's DNS that is also a watchdog's encrypted DNS", () {
    const doh = {
      1: {'94.140.14.14'},
      5: {'1.1.1.2', '1.0.0.2'},
    };

    test('each watchdog address is read from its own line, one per slot', () {
      expect(parseWatchdogDohServers('94.140.14.14\n---\n\n---\n\n---\n\n---\n1.1.1.2,1.0.0.2'), doh);
      expect(parseWatchdogDohServers(''), isEmpty);
      expect(parseWatchdogDohServers('\n---\n\n---\n\n---\n\n---\n'), isEmpty);
    });

    test('names each shared address with the slots whose watchdog uses it', () {
      expect(dnsSharedWithWatchdogs('1.1.1.2, 9.9.9.9', doh), {
        '1.1.1.2': [5]
      });
      expect(dnsSharedWithWatchdogs('1.1.1.2, 1.0.0.2', {...doh, 2: {'1.1.1.2'}}), {
        '1.1.1.2': [2, 5],
        '1.0.0.2': [5],
      });
    });

    test('different addresses, or no watchdogs, share nothing', () {
      expect(dnsSharedWithWatchdogs('9.9.9.9, 149.112.112.112', doh), isEmpty);
      expect(dnsSharedWithWatchdogs('1.1.1.2', const {}), isEmpty);
    });

    test('the note says whose watchdog, and what it costs', () {
      expect(dnsMatchesWatchdogNote('1.1.1.2', [5]),
          "1.1.1.2: wgc5's watchdog uses this address for its own encrypted DNS. While this slot is running, those "
          'lookups travel through it - and stop if it stops answering.');
      expect(dnsMatchesWatchdogNote('1.1.1.2', [2, 5]), startsWith("1.1.1.2: wgc2's and wgc5's watchdogs use this address for their"));
    });
  });
}
