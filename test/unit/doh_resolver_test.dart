// test/unit/doh_resolver_test.dart - where the watchdog sends its own lookups (ID-076, ID-307).
//
// These are SHAPE tests: they pin what goes into the script, not what the router does with it.
// The behaviour - a real DNS query to the DoH server, its answer read, and the fallback logged
// when the server fails - is in doh_lookup_test.dart, against the harness. Shape tests are what
// stayed green while ASUS's curl ignored --doh-url for two weeks (found 2026-09-30).
//
// Measured on stock 2026-09-19: an IP-literal URL is refused silently by ASUS's curl (`Invalid DL
// URL`), so the DoH server is always named by host, and `--resolve` supplies its address.
import 'package:cfg_pia_wg/input_checks.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both halves, or nothing', () {
    // A URL with no address would leave the resolver's own name to be looked up in the clear.
    expect(dohEndpoint('https://security.cloudflare-dns.com/dns-query', ''), isNull);
    expect(dohEndpoint('', '1.1.1.2'), isNull);
    expect(dohEndpoint('', ''), isNull);
    expect(dohEndpoint('   ', '   '), isNull);
  });

  test('the endpoint is the URL, its host, and the address to pin the host to', () {
    final e = dohEndpoint('https://security.cloudflare-dns.com/dns-query', '1.1.1.2')!;
    expect(e.url, 'https://security.cloudflare-dns.com/dns-query');
    expect(e.host, 'security.cloudflare-dns.com');
    expect(e.addresses, '1.1.1.2');
  });

  test('surrounding space in either field is not passed to the shell', () {
    final e = dohEndpoint('  https://dns.google/dns-query  ', ' 8.8.8.8 ')!;
    expect((e.url, e.host, e.addresses), ('https://dns.google/dns-query', 'dns.google', '8.8.8.8'));
  });

  test('a description for the log, naming both', () {
    expect(dohDescription('https://dns.quad9.net/dns-query', '9.9.9.9'), 'dns.quad9.net (9.9.9.9)');
    expect(dohDescription('', ''), isEmpty, reason: 'nothing configured, nothing to say');
  });

  test('every offered resolver is a hostname URL with an address', () {
    expect(kDohResolvers, isNotEmpty);
    for (final r in kDohResolvers) {
      expect(r.url, startsWith('https://'), reason: r.label);
      final host = Uri.parse(r.url).host;
      expect(host, isNotEmpty, reason: r.label);
      // An IP literal in the URL is what stock firmware refuses, silently.
      expect(RegExp(r'^[0-9.]+$').hasMatch(host), isFalse, reason: '${r.label} must not be an IP literal');
      expect(RegExp(r'^[0-9.]+$').hasMatch(r.ip), isTrue, reason: '${r.label} needs a literal address');
      expect(dohEndpoint(r.url, r.ip)?.host, host, reason: r.label);
      expect(checkDohPair(r.url, r.ip), isEmpty, reason: '${r.label} passes the form check');
    }
    // ID-226: Control D, AdGuard and Mullvad, and each URL once, since the menu is keyed on it.
    expect(kDohResolvers.map((r) => r.label).join(' '), allOf(contains('Control D'), contains('AdGuard'), contains('Mullvad')));
    expect(kDohResolvers.map((r) => r.url).toSet(), hasLength(kDohResolvers.length));
  });

  test('the default is one of the offered ones', () {
    expect(kDohResolvers.map((r) => r.url), contains(kDefaultDohResolver.url));
    expect(kDefaultDohResolver.ip, '1.1.1.2');
  });

  group('the script', () {
    WatchdogConfig cfg({String url = '', String ip = ''}) => WatchdogConfig(
          slotIndex: 1,
          primaryIp: '8.8.8.8',
          secondaryIp: '1.1.1.1',
          dohUrl: url,
          dohIp: ip,
        );

    test('carries the endpoint when a resolver is configured', () {
      final s = buildWatchdogScript(cfg(url: 'https://dns.google/dns-query', ip: '8.8.8.8'));
      expect(s, contains('DOHURL="https://dns.google/dns-query"'));
      expect(s, contains('DOHHOST="dns.google"'));
      expect(s, contains('DOHIPS="8.8.8.8"'));
      expect(s, contains('DOHDESC="dns.google (8.8.8.8)"'));
      // The retry drops back to plain resolution rather than failing the rebuild.
      expect(s, contains(r'$CURLPLAIN -S -o "$TMPTOK"'));
    });

    test('carries nothing when none is configured', () {
      final s = buildWatchdogScript(cfg());
      expect(s, contains('DOHURL=""'));
      expect(s, contains('DOHDESC=""'));
    });

    test("never passes --doh-url, which ASUS's curl ignores (ID-307)", () {
      for (final c in [cfg(), cfg(url: 'https://dns.google/dns-query', ip: '8.8.8.8')]) {
        final commands = buildWatchdogScript(c).split('\n').where((l) => !l.trimLeft().startsWith('#'));
        expect(commands.where((l) => l.contains('--doh-url')), isEmpty);
      }
    });

    test('the SMTP host is resolved the same way before the mailer runs (ID-077)', () {
      final s = buildWatchdogScript(cfg(url: 'https://dns.google/dns-query', ip: '8.8.8.8'));
      expect(s, contains('resolve_smtp()'));
      expect(s, contains(r'SMTP_IP="$(doh_a "$SMTP_HOST")"'));
      // The entry goes in immediately before the send and comes out immediately after.
      expect(s.indexOf('resolve_smtp\n'), lessThan(s.indexOf('hosts_clean\n  rm -f "\$TMPMAIL"')));
      // And a run that was killed mid-send is cleaned up by the next one.
      expect(s, contains('HOSTSMARK="cfg-pia-wg-\$IFACE"'));
    });
  });
}
