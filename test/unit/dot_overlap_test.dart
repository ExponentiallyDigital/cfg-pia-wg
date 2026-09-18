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
}
