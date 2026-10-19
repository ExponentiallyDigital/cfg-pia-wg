// test/unit/router_dns_golden_test.dart - ROUTER DNS ROUTING and ROUTER RESOLVER STATUS, word for word
// (ID-041 step 2).
//
// buildDnsRouting and dnsReportText were split into smaller functions in build 509, with the rule that
// nothing they produce changes. These goldens were written from the code BEFORE the split, so a split
// that changes one character fails here. The cases reach every branch: stock and Merlin, DNS-over-TLS
// on and off, the internet provider's DNS, a slot with no watchdog and one with no encrypted DNS,
// no pinned device, no slot DNS servers, and routes read from the router.
//
// To write them again after a deliberate change: UPDATE_DNS_GOLDENS=1 flutter test test/unit/router_dns_golden_test.dart
import 'dart:io';

import 'package:cfg_pia_wg/router_dns.dart';
import 'package:flutter_test/flutter_test.dart';

import '../router_dns_fixtures.dart';

String _routing(String output, {bool merlin = false}) => dnsReportText(
    'ROUTER DNS ROUTING', buildDnsRouting(parseDnsRouting(output, names: {'192.168.1.55': 'TABLET'}, merlin: merlin), readAt: '04:09:30'));

String _replace(String s, List<(Pattern, String)> edits) {
  for (final (from, to) in edits) {
    final next = s.replaceFirst(from, to);
    if (next == s) throw StateError('golden case edit found nothing to change: $from');
    s = next;
  }
  return s;
}

final _cases = <String, String Function()>{
  'routing_stock': () => _routing(kRoutingFixture),
  'routing_merlin': () => _routing(kRoutingFixture, merlin: true),
  'routing_dot_off': () => _routing(_replace(kRoutingFixture, [
        ('nameserver 127.0.1.1\n', ''),
        ('@@DNSMASQ\nserver=127.0.1.1', '@@DNSMASQ\nserver=1.1.1.2\nserver=1.0.0.2'),
        ('dnspriv_enable=1', 'dnspriv_enable=0'),
      ])),
  'routing_isp_unpinned_watchdogs': () => _routing(_replace(kRoutingFixture, [
        ('nameserver 1.0.0.2\n', ''),
        ('wan0_dnsenable_x=0', 'wan0_dnsenable_x=1'),
        (RegExp(r'-A VPN_FUSION .*\n'), ''),
        ('wgc2_wd_check_interval=5\n', ''),
        ('wgc3_wd_doh_url=https://security.cloudflare-dns.com/dns-query\nwgc3_wd_doh_ip=1.1.1.2\n', ''),
        ('wgc1_dns=9.9.9.9, 149.112.112.112', 'wgc1_dns=9.9.9.9'),
      ])),
  'routing_no_slot_dns': () => _routing(_replace(kRoutingFixture, [
        ('wgc1_dns=9.9.9.9, 149.112.112.112\n', ''),
        ('wgc2_dns=9.9.9.9, 149.112.112.112\n', ''),
        ('wgc3_dns=9.9.9.9, 149.112.112.112\n', ''),
        ('wgc5_dns=9.9.9.9, 149.112.112.112\n', ''),
        (RegExp(r'@@RULES\n(.*\n)*?@@FUSION'), '@@RULES\n@@FUSION'),
      ])),
  'routing_routes_read': () => _routing(_replace(kRoutingFixture, [
        ('@@ROUTES\n', '@@ROUTES\n1.1.1.2 1.1.1.2 via 10.0.0.1 dev eth0 src 10.0.0.2\n1.0.0.2 1.0.0.2 dev wgc1 src 10.100.9.168\n'),
        ('wgc1\nbr0', 'br0'),
      ])),
  'resolver_status': () => dnsReportText(
      'ROUTER RESOLVER STATUS',
      buildResolverStatus(
          facts: kFactsFixture,
          checks: '@@CHECK a\n$kNslookupOkFixture\n@@CHECK b\n$kNslookupOkFixture',
          files: kFilesFixture,
          checkedAt: '04:08:12')),
  'resolver_status_failed': () => dnsReportText(
      'ROUTER RESOLVER STATUS',
      buildResolverStatus(
          facts: kFactsFixture.replaceFirst('@@stubby 4750\n', ''),
          checks: '@@CHECK a\n$kNslookupOkFixture',
          files: kFilesFixture,
          checkedAt: '04:08:12')),
  'resolver_status_dot_off': () => dnsReportText(
      'ROUTER RESOLVER STATUS',
      buildResolverStatus(
          facts: kFactsFixture.replaceFirst('dnspriv_enable=1', 'dnspriv_enable=0'),
          checks: '@@CHECK a\n$kNslookupOkFixture',
          files: _replace(kFilesFixture, [('@@FILE /tmp/resolv.dnsmasq 02:04\nserver=127.0.1.1', '@@FILE /tmp/resolv.dnsmasq 02:04\nserver=1.1.1.2')]),
          checkedAt: '04:08:12')),
};

void main() {
  final update = Platform.environment['UPDATE_DNS_GOLDENS'] == '1';

  for (final MapEntry(key: name, value: build) in _cases.entries) {
    test(name, () {
      final file = File('test/fixtures/dns_golden/$name.txt');
      final text = build();
      if (update) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
        return;
      }
      expect(text, file.readAsStringSync(), reason: 'the report changed; if on purpose, write the goldens again');
    });
  }

  test('the cases are all different, so each one pins something', () {
    final texts = {for (final build in _cases.values) build()};
    expect(texts, hasLength(_cases.length));
  });
}
