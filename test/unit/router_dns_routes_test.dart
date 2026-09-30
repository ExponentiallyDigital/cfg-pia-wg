// ROUTER DNS ROUTING tags from where the kernel actually sends each address (ID-337, ID-306).
//
// The tags were worked out from the `iif lo` rules alone. On Merlin, with a slot's DNS servers also
// the router's own, the screen said "No lookups go through a tunnel" while every router lookup went
// into wgc1 (MRL-8, 2026-09-30) - Merlin routes a slot's DNS servers with main-table routes, which
// the rules do not show. It also called a tunnel "encrypted to PIA" while it was down, and stamped
// "tunnel" on every pinned device's redirect without routing it. The route answers below are shaped
// as the routers gave them that day, with documentation addresses.
import 'package:cfg_pia_wg/router_dns.dart';
import 'package:flutter_test/flutter_test.dart';

String _output({
  String resolv = 'nameserver 9.9.9.9\nnameserver 149.112.112.112',
  String dnsmasq = 'server=127.0.1.1',
  String rules = '',
  String fusion = '',
  String nvram = 'vpnc_clientlist=pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg\n'
      'wgc1_desc=pia-nz\nwgc1_dns=9.9.9.9, 149.112.112.112\ndnspriv_enable=1\n'
      'dnspriv_rulelist=<1.1.1.1>>cloudflare-dns.com>',
  String routes = '',
  String pinned = '',
  String up = '',
}) =>
    ['@@RESOLV', resolv, '@@DNSMASQ', dnsmasq, '@@RULES', rules, '@@FUSION', fusion, '@@NVRAM', nvram, '@@ROUTES', routes,
            '@@PINNEDROUTES', pinned, '@@UP', up]
        .join('\n');

List<DnsFlowLine> _lines(List<DnsBlock> blocks, int flow) => (blocks.whereType<DnsFlow>().toList()[flow]).lines;

void main() {
  test("Merlin's main-table route for a slot's DNS server is seen: the router's lookups go through wgc1", () {
    final blocks = buildDnsRouting(
        parseDnsRouting(
            _output(
              routes: '9.9.9.9 9.9.9.9 dev wgc1 src 10.100.9.168\n149.112.112.112 149.112.112.112 dev wgc1 src 10.100.9.168\n'
                  '1.1.1.1 1.1.1.1 via 198.51.100.1 dev eth0 src 198.51.100.80',
              up: 'wgc1\nbr0\neth0',
            ),
            names: const {},
            merlin: true),
        readAt: '16:00:00');
    final own = _lines(blocks, 1);
    expect(own.first.where.label, 'wgc1:pia-nz');
    expect(own.first.where.kind, DnsTagKind.tunnel);
    expect((blocks.first as DnsVerdict).text, contains("Some of the router's own lookups go through a tunnel"));
  });

  test('a tunnel that is down is not called a tunnel, nor encrypted', () {
    final blocks = buildDnsRouting(
        parseDnsRouting(_output(routes: '9.9.9.9 9.9.9.9 dev wgc1 src 10.100.9.168', up: 'br0\neth0'),
            names: const {}, merlin: true),
        readAt: '16:00:00');
    final line = _lines(blocks, 1).first;
    expect(line.where.label, 'wgc1:pia-nz, which is down');
    expect(line.where.kind, DnsTagKind.neutral);
    expect(line.encryption, isNull);
  });

  group("a pinned device's lookups, routed from the device", () {
    const fusion = '-A VPN_FUSION -s 192.168.1.20/32 -d 192.168.1.1/32 -p udp -m udp --dport 53 -j DNAT --to-destination 9.9.9.9';
    const policy = '\nvpnc_dev_policy_list=1>192.168.1.20>>9>';

    DnsFlowLine pinnedLine(String route, String up) => _lines(
        buildDnsRouting(
            parseDnsRouting(
                _output(
                    fusion: fusion,
                    nvram: _output().split('@@NVRAM\n')[1].split('\n@@ROUTES')[0] + policy,
                    pinned: '192.168.1.20 9.9.9.9 $route',
                    up: up),
                names: const {'192.168.1.20': 'TABLET'},
                merlin: false),
            readAt: '16:00:00'),
        0)
        .first;

    test('through its tunnel while the tunnel is up: encrypted to PIA', () {
      final l = pinnedLine('9.9.9.9 from 192.168.1.20 dev wgc1', 'wgc1');
      expect(l.where.kind, DnsTagKind.tunnel);
      expect(l.encryption?.label, 'encrypted to PIA');
    });

    test('refused while the tunnel is down: nowhere, and nothing claimed about encryption', () {
      final l = pinnedLine('RTNETLINK answers: Invalid argument', '');
      expect(l.where.label, 'nowhere: blocked');
      expect(l.encryption, isNull);
    });

    test('out the internet: said so, and not encrypted', () {
      final l = pinnedLine('9.9.9.9 from 192.168.1.20 via 198.51.100.1 dev eth0', 'wgc1');
      expect(l.where.kind, DnsTagKind.internet);
      expect(l.encryption?.label, 'not encrypted');
    });
  });
}
