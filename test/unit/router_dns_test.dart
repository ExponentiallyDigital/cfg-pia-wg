// test/unit/router_dns_test.dart - ROUTER RESOLVER STATUS and ROUTER DNS ROUTING, from real output (ID-194).
//
// The fixtures, in test/router_dns_fixtures.dart, are a stock router's real output, masked.
import 'package:cfg_pia_wg/router_dns.dart';
import 'package:flutter_test/flutter_test.dart';

import '../router_dns_fixtures.dart';

List<DnsBlock> kRoutingFixtureBlocks([String output = kRoutingFixture]) =>
    buildDnsRouting(parseDnsRouting(output, names: {'192.168.1.55': 'TABLET'}, merlin: false), readAt: '04:09:30');

List<DnsFlowLine> _flowAfter(List<DnsBlock> blocks, String group) {
  final i = blocks.indexWhere((b) => b is DnsGroup && b.title == group);
  return (blocks[i + 1] as DnsFlow).lines;
}

void main() {
  group('the live check', () {
    test('every address the lookup returned, after Name:, and the time the router measured', () {
      final r = parseNslookup(kNslookupOkFixture);
      expect(r.ok, isTrue);
      expect(r.addresses, ['172.66.147.243', '104.20.23.154', '2606:4700:10::ac42:93f3', '2606:4700:10::6814:179a'],
          reason: 'not 127.0.0.1, the server it asked, which BusyBox prints first');
      expect(r.ms, 40);
    });

    test('a lookup that never finished is a failure with no time', () {
      final r = parseNslookup('Server:    127.0.1.1\nAddress 1: 127.0.1.1');
      expect(r.ok, isFalse);
      expect(r.finished, isFalse);
      expect(r.ms, isNull);
    });

    test('the command bounds both lookups, since BusyBox has no timeout', () {
      final c = dnsCheckCommand(withStubby: true);
      expect(c, contains('nslookup example.com 127.0.0.1'));
      expect(c, contains('nslookup example.com 127.0.1.1'));
      expect(c, contains('while [ \$W -lt 5 ]'));
      expect(c, isNot(contains('timeout ')));
      expect(dnsCheckCommand(withStubby: false), isNot(contains('127.0.1.1')));
    });
  });

  group('ROUTER RESOLVER STATUS', () {
    List<DnsBlock> build({String checks = '@@CHECK a\n$kNslookupOkFixture\n@@CHECK b\n$kNslookupOkFixture', String facts = kFactsFixture}) =>
        buildResolverStatus(facts: facts, checks: checks, files: kFilesFixture, checkedAt: '04:08:12');

    test('both resolvers answered: OK, running, every address, no advice', () {
      final check = build().first as DnsCheck;
      expect(check.rows.map((r) => r.state), [DnsCheckState.ok, DnsCheckState.ok]);
      expect(check.rows.every((r) => r.running == true), isTrue);
      expect(check.rows.first.addresses, hasLength(4));
      expect(check.advice, isNull);
    });

    test('the files in lookup order, grouped, each with when it was written', () {
      final blocks = build();
      final files = blocks.whereType<DnsFile>().map((f) => f.name).toList();
      expect(files, [...kResolverFiles, 'Active DNS settings (nvram)']);
      expect(blocks.whereType<DnsFile>().first.written, '01:56');
      expect(blocks.whereType<DnsGroup>().map((g) => g.title), ["YOUR DEVICES' LOOKUPS", "THE ROUTER'S OWN LOOKUPS", 'SETTINGS']);
    });

    test('dnsmasq.conf warns before it is shared, because it lists every reservation', () {
      final conf = build().whereType<DnsFile>().first;
      expect(conf.caution, "Lists every reserved device's MAC and address: review before sharing.");
    });

    test('both failing with stubby running: stubby cannot reach its servers', () {
      final check = build(checks: '@@CHECK a\n@@CHECK b').first as DnsCheck;
      expect(check.rows.first.detail, 'no answer in 5 s');
      expect(check.advice, startsWith("stubby is running but can't reach your DNS-over-TLS servers"));
    });

    test('stubby not running is named as the fault', () {
      final check = build(checks: '@@CHECK a\n@@CHECK b', facts: kFactsFixture.replaceFirst('@@stubby 4750', '@@stubby ')).first
          as DnsCheck;
      expect(check.rows.last.running, isFalse);
      expect(check.advice, startsWith("stubby, the DNS-over-TLS client, isn't running"));
    });

    test('dnsmasq answered from memory while stubby failed: says lookups will start to fail', () {
      final check = build(checks: '@@CHECK a\n$kNslookupOkFixture\n@@CHECK b').first as DnsCheck;
      expect(check.advice, contains('answered from what it remembers'));
    });

    test('with DNS-over-TLS off, stubby is not checked and says why', () {
      final off = kFilesFixture.replaceFirst('server=127.0.1.1', 'server=1.1.1.2');
      final check =
          buildResolverStatus(facts: kFactsFixture, checks: '@@CHECK a\n$kNslookupOkFixture', files: off, checkedAt: 'x').first as DnsCheck;
      expect(check.rows.last.state, DnsCheckState.notUsed);
      expect(check.rows.last.detail, 'DNS-over-TLS is off');
    });
  });

  group('ROUTER DNS ROUTING', () {
    test('the one-line answer, on this router', () {
      expect((kRoutingFixtureBlocks().first as DnsVerdict).text, "Only pinned devices' lookups go through a tunnel.");
    });

    test('pinned devices by slot, by region and by name, encrypted to PIA', () {
      final pinned = _flowAfter(kRoutingFixtureBlocks(), "YOUR DEVICES' LOOKUPS").first;
      expect(pinned.head, 'wgc1:pia-aus_perth');
      expect(pinned.rest, ' → 9.9.9.9');
      expect(pinned.note, 'TABLET');
      expect(pinned.encryption!.label, 'encrypted to PIA');
    });

    test('everything else goes through stubby to the DoT servers, encrypted, to the Internet', () {
      final rest = _flowAfter(kRoutingFixtureBlocks(), "YOUR DEVICES' LOOKUPS").last;
      expect(rest.rest, ' → dnsmasq → stubby → 1.1.1.2, 1.0.0.2');
      expect(rest.where.label, 'Internet');
      expect(rest.encryption!.label, 'encrypted (DoT)');
    });

    test("the router's own lookups are ordinary DNS, and stubby only if both fail", () {
      final own = _flowAfter(kRoutingFixtureBlocks(), "THE ROUTER'S OWN LOOKUPS");
      expect(own.map((l) => l.head), ['1.1.1.2', '1.0.0.2', '127.0.1.1']);
      expect(own.first.encryption!.label, 'not encrypted');
      expect(own.last.note, 'to 1.1.1.2 and 1.0.0.2, only if both of the above fail');
      expect(own.last.encryption!.label, 'encrypted (DoT)');
    });

    test('each watchdog, by region, with its encrypted DNS; an empty slot says so', () {
      final wd = _flowAfter(kRoutingFixtureBlocks(), "THE WATCHDOGS' LOOKUPS");
      expect(wd[0].head, 'wgc1:pia-aus_perth');
      expect(wd[0].note, 'freedns.controld.com (76.76.2.1)');
      expect(wd[0].encryption!.label, 'encrypted (DoH)');
      expect(wd[3].where.label, 'not configured', reason: 'wgc4');
    });

    test('shared slot DNS: facts only, naming the rules and the slot that carries them', () {
      final shared = _flowAfter(kRoutingFixtureBlocks(), "THE SLOTS' DNS SERVERS").single;
      expect(shared.head, '9.9.9.9, 149.112.112.112');
      expect(shared.where.label, 'shared by 4');
      expect(shared.note, contains('Rules 1016 and 1017'));
      expect(shared.note, contains('through wgc5:pia-aus_melbourne'));
      expect(shared.note.toLowerCase(), isNot(contains('harmless')));
    });

    test("a router DNS server a slot also uses goes through that slot's tunnel, and the answer says so", () {
      final shared = kRoutingFixture.replaceFirst('nameserver 1.1.1.2', 'nameserver 9.9.9.9');
      final blocks = kRoutingFixtureBlocks(shared);
      final own = _flowAfter(blocks, "THE ROUTER'S OWN LOOKUPS").first;
      expect(own.where.label, 'wgc5:pia-aus_melbourne');
      expect(own.encryption!.label, 'encrypted to PIA');
      expect((blocks.first as DnsVerdict).text, startsWith("Some of the router's own lookups go through a tunnel"));
    });

    test('nothing pinned: the redirect chain is empty, and the evidence says so', () {
      final unpinned = kRoutingFixture.replaceFirst(RegExp(r'-A VPN_FUSION .*\n'), '');
      final blocks = kRoutingFixtureBlocks(unpinned);
      expect((blocks.first as DnsVerdict).text, 'No lookups go through a tunnel.');
      final fusion = blocks.whereType<DnsFile>().firstWhere((f) => f.name.startsWith('DNS redirects'));
      expect(fusion.content, startsWith('(none'));
    });

    test('COPY carries the answer, the tags and the evidence as text', () {
      final text = dnsReportText('ROUTER DNS ROUTING', kRoutingFixtureBlocks());
      expect(text, contains("Only pinned devices' lookups go through a tunnel."));
      expect(text, contains('wgc1:pia-aus_perth → 9.9.9.9 [wgc1:pia-aus_perth, encrypted to PIA] - TABLET'));
      expect(text, contains('1016:   from all to 9.9.9.9 iif lo lookup 5  # wgc5:pia-aus_melbourne'));
    });
  });
}
