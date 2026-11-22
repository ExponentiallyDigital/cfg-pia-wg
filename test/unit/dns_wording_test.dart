// test/unit/dns_wording_test.dart - what the app says about whose lookups depend on the router's resolver, for each
// firmware and default connection (ID-640).
//
// The messages said that devices that aren't pinned "can't look names up" when the router's resolver fails.
// That is stock's behaviour (September 2026). On Merlin with a tunnel as the default those devices have their
// lookups rewritten to the default slot's DNS servers and never ask the resolver (measured 2026-11-20, 388.13).
// The fixtures here are the router's replies for each case, with invented addresses.
import 'package:cfg_pia_wg/dns_wording.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_dns.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../router_dns_fixtures.dart';

const _tunnel = DnsWording(RouterFirmware.merlin, DefaultConnection.tunnel);
const _internet = DnsWording(RouterFirmware.merlin, DefaultConnection.internet);
const _unknown = DnsWording(RouterFirmware.merlin);

// VPN Director's rules file as Merlin writes it (no trailing newline): one device rule, and a whole-network rule
// when there is a default tunnel. The router is `192.168.1.1/255.255.255.0`, invented.
const _deviceRule = '<1>laptop>192.168.1.55>>WGC1';
const _defaultRule = '<1>default>192.168.1.0/24>>WGC5';

String _merlinReply({String rules = '', bool file = true, String lan = '192.168.1.1\n255.255.255.0', String fw = 'merlin'}) =>
    '@@FW\n$fw\n@@RULES ${file ? 1 : 0}\n$rules\n@@LAN\n$lan\n';

NslookupResult _dead() => const NslookupResult(finished: true, exitCode: 1, addresses: [], error: 'no answer');

String _advice(DnsWording w, {bool running = true, bool dotOn = false}) => resolverAdvice(
        dnsmasq: _dead(), dnsmasqRunning: running, stubby: null, stubbyRunning: true, dotOn: dotOn, wording: w) ??
    '';

void main() {
  group('stock: the text the app has always shown, unchanged', () {
    const w = DnsWording.stock;

    test('the clause after "so" is the one resolverAdvice always used', () {
      expect(w.unpinnedLookupsFail, "devices that aren't pinned to a VPN can't look names up");
    });

    test('the heading over the resolver files', () {
      expect(w.resolverGroup, "YOUR DEVICES' LOOKUPS");
    });

    test("the watchdog's log lines end as they always did", () {
      expect(w.watchdogResolverTail, "so devices that aren't pinned can't look names up");
    });

    test("the slot form's note, word for word", () {
      expect(
          w.overlapNote,
          'Your router uses this address for its own encrypted DNS. While this slot is running, the '
          "router's lookups, and those of every device you have not pinned, travel through it - and stop "
          'if it stops answering.');
    });

    test('the default connection makes no difference on stock', () {
      for (final d in DefaultConnection.values) {
        final other = DnsWording(RouterFirmware.stock, d);
        expect(other.unpinnedLookupsFail, w.unpinnedLookupsFail);
        expect(other.resolverGroup, w.resolverGroup);
      }
    });

    test('the advice, as before', () {
      expect(_advice(w, running: false),
          "dnsmasq, the router's DNS server, isn't running, so devices that aren't pinned to a VPN can't look names up. Reboot the router.");
    });
  });

  group('Merlin with a tunnel as the default: devices that aren\'t pinned do not use the resolver', () {
    test('the advice says the router\'s own lookups fail and that those devices are not affected', () {
      expect(_advice(_tunnel, running: false),
          "dnsmasq, the router's DNS server, isn't running, so the router's own lookups fail, though devices that "
          "aren't pinned use the default tunnel's DNS servers and still look names up. Reboot the router.");
    });

    test('it never says that devices that are not pinned cannot look names up', () {
      for (final running in [true, false]) {
        for (final dotOn in [true, false]) {
          expect(_advice(_tunnel, running: running, dotOn: dotOn), isNot(contains("can't look names up")));
        }
      }
    });

    test("the resolver files are headed as the router's own", () {
      expect(_tunnel.resolverGroup, "THE ROUTER'S RESOLVER");
    });
  });

  group('Merlin with the internet as the default: devices that aren\'t pinned use the resolver', () {
    test('the advice names them, and the router\'s own lookups', () {
      expect(_advice(_internet, running: false),
          "dnsmasq, the router's DNS server, isn't running, so the router's own lookups fail, and so do those of "
          "devices that aren't pinned, which use its resolver while the default connection is the internet. Reboot the router.");
    });

    test("the heading is stock's, since those devices use it", () {
      expect(_internet.resolverGroup, "YOUR DEVICES' LOOKUPS");
    });
  });

  group('Merlin with the default not known: both are said, neither is claimed', () {
    test('the advice covers both', () {
      final advice = _advice(_unknown, running: false);
      expect(advice, contains("devices that aren't pinned, when the default connection is the internet"));
      expect(advice, contains("(with a tunnel as the default they use its DNS servers instead)"));
    });

    test('the heading is the router\'s own', () {
      expect(_unknown.resolverGroup, "THE ROUTER'S RESOLVER");
    });
  });

  test("Merlin's note and the watchdog's lines name the router's own lookups first, and no default", () {
    for (final w in [_tunnel, _internet, _unknown]) {
      expect(w.overlapNote, startsWith('Your router uses this address for its own lookups.'));
      expect(w.overlapNote, contains('they travel through it'));
      expect(w.watchdogResolverTail, startsWith("so the router's own lookups fail"));
    }
  });

  test("Merlin's note says what the hold does and what it doesn't cover (ID-636)", () {
    const note = _tunnel;
    expect(note.overlapNote, contains('While this slot is stopped, disabled or being rebuilt, the router refuses them'));
    expect(note.overlapNote, contains('rather than send them over your internet connection'));
    expect(note.overlapNote, contains('The first two minutes after a reboot are not covered.'));
    expect(note.overlapNote, contains('Different DNS servers for the router and this slot avoid all of this.'));
    expect(DnsWording.stock.overlapNote, isNot(contains('refuses')), reason: 'stock has no hold');
  });

  group('the reader: firmware and default connection from the router', () {
    test('stock answers an empty tag and is stock whatever else came back', () {
      expect(parseDnsWording(_merlinReply(fw: '', rules: _defaultRule)).firmware, RouterFirmware.stock);
    });

    test('a whole-network rule to a WireGuard slot is a tunnel as the default', () {
      final w = parseDnsWording(_merlinReply(rules: '$_deviceRule$_defaultRule'));
      expect(w.firmware, RouterFirmware.merlin);
      expect(w.defaultConnection, DefaultConnection.tunnel);
    });

    test('device rules alone leave the internet as the default', () {
      expect(parseDnsWording(_merlinReply(rules: _deviceRule)).defaultConnection, DefaultConnection.internet);
    });

    test('no rules file is no rules: the internet', () {
      expect(parseDnsWording(_merlinReply(file: false)).defaultConnection, DefaultConnection.internet);
    });

    test('a whole-network rule that is switched off is not the default', () {
      expect(parseDnsWording(_merlinReply(rules: '<0>default>192.168.1.0/24>>WGC5')).defaultConnection,
          DefaultConnection.internet);
    });

    test('a rule for part of the network, or to the internet, is not a default tunnel', () {
      expect(parseDnsWording(_merlinReply(rules: '<1>half>192.168.1.0/25>>WGC5')).defaultConnection, DefaultConnection.internet);
      expect(parseDnsWording(_merlinReply(rules: '<1>wan>192.168.1.0/24>>WAN')).defaultConnection, DefaultConnection.internet);
    });

    test('without the LAN settings the default is not known', () {
      expect(parseDnsWording(_merlinReply(rules: _defaultRule, lan: '')).defaultConnection, DefaultConnection.unknown);
    });

    test('the command asks for all three and changes nothing', () {
      expect(kDnsWordingCommand, allOf(contains('3rd-party'), contains('vpndirector_rulelist'), contains('lan_netmask')));
      expect(kDnsWordingCommand, isNot(contains('nvram set')));
    });
  });

  group('the resolver screen is worded for the router it reads', () {
    List<DnsBlock> build(DnsWording w) => buildResolverStatus(
        facts: kFactsFixture,
        checks: '@@CHECK a\n@@CHECK b',
        files: kFilesFixture,
        checkedAt: '04:08:12',
        wording: w);

    test('on stock and with the internet as the default, the headings are as ever', () {
      for (final w in [DnsWording.stock, _internet]) {
        expect(build(w).whereType<DnsGroup>().map((g) => g.title), ["YOUR DEVICES' LOOKUPS", "THE ROUTER'S OWN LOOKUPS", 'SETTINGS']);
      }
    });

    test('with a tunnel as the default, the files that serve the router are headed as the router\'s', () {
      expect(build(_tunnel).whereType<DnsGroup>().map((g) => g.title), ["THE ROUTER'S RESOLVER", "THE ROUTER'S OWN LOOKUPS", 'SETTINGS']);
    });

    test("dnsmasq's files are described as answering your devices on stock, and 'the lookups it is asked' with a tunnel", () {
      String role(DnsWording w, String name) => build(w).whereType<DnsFile>().firstWhere((f) => f.name == name).role;
      expect(role(DnsWording.stock, '/etc/dnsmasq.conf'), contains("how it answers your devices' lookups"));
      expect(role(DnsWording.stock, '/tmp/resolv.dnsmasq'), "Where dnsmasq sends your devices' lookups it can't answer itself.");
      expect(role(_tunnel, '/etc/dnsmasq.conf'), contains('how it answers the lookups it is asked'));
      expect(role(_tunnel, '/tmp/resolv.dnsmasq'), "Where dnsmasq sends the lookups it is asked it can't answer itself.");
      expect(role(_unknown, '/tmp/resolv.dnsmasq'), contains('the lookups it is asked'));
      expect(role(_internet, '/tmp/resolv.dnsmasq'), contains("your devices' lookups"));
    });

    test('the advice on the screen is the model\'s', () {
      final advice = (build(_tunnel).first as DnsCheck).advice!;
      expect(advice, contains("devices that aren't pinned use the default tunnel's DNS servers and still look names up"));
      final stock = (build(DnsWording.stock).first as DnsCheck).advice!;
      expect(stock, contains("devices that aren't pinned to a VPN can't look names up"));
    });
  });

  group("the watchdog's log lines, for the firmware the script is built for", () {
    const cfg = WatchdogConfig(
      slotIndex: 1,
      primaryIp: '8.8.8.8',
      secondaryIp: '1.1.1.1',
      piaUsername: 'p1234567',
      piaPassword: 'secret',
      emailAlertsEnabled: false,
      emailFrom: '',
      emailTo: '',
      emailSubject: '',
      smtpServer: '',
      smtpUsername: '',
      smtpPassword: '',
    );

    test('stock\'s script is as it always was', () {
      final script = buildWatchdogScript(cfg, firmware: RouterFirmware.stock);
      expect(script, contains('log "Router resolver FAILED: no answer from 127.0.0.1 in 6s, so devices that aren\'t pinned can\'t look names up"'));
      expect(script, contains('log "Router resolver FAILED: 127.0.0.1 could not look up example.com, so devices that aren\'t pinned can\'t look names up"'));
    });

    test("Merlin's script names the router's own lookups, and nothing is left unreplaced", () {
      final script = buildWatchdogScript(cfg, firmware: RouterFirmware.merlin);
      const tail = "so the router's own lookups fail, and so do those of any device that relies on its resolver";
      expect(script, contains('log "Router resolver FAILED: no answer from 127.0.0.1 in 6s, $tail"'));
      expect(script, contains('log "Router resolver FAILED: 127.0.0.1 could not look up example.com, $tail"'));
      expect(script, isNot(contains("devices that aren't pinned can't look names up")));
      expect(script, isNot(contains('__RRTAIL__')));
    });
  });
}
