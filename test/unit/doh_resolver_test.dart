// test/unit/doh_resolver_test.dart - the watchdog's own lookups, encrypted (ID-076).
//
// The shape of the curl arguments is the whole feature. Measured on stock firmware 2026-09-19:
// an IP-literal URL is refused silently by ASUS's curl (`Invalid DL URL`), a hostname URL works,
// and a hostname URL with `--resolve` works while looking nothing up in the clear. Anything that
// changes these strings changes whether the watchdog can resolve at all.
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both halves, or nothing', () {
    // A URL with no address would leave curl resolving the resolver's own name in the clear.
    expect(dohCurlArguments('https://security.cloudflare-dns.com/dns-query', ''), '');
    expect(dohCurlArguments('', '1.1.1.2'), '');
    expect(dohCurlArguments('', ''), '');
    expect(dohCurlArguments('   ', '   '), '');
  });

  test('the arguments pin the hostname to the address', () {
    expect(
      dohCurlArguments('https://security.cloudflare-dns.com/dns-query', '1.1.1.2'),
      ' --doh-url https://security.cloudflare-dns.com/dns-query'
      ' --resolve security.cloudflare-dns.com:443:1.1.1.2',
    );
  });

  test('surrounding space in either field is not passed to the shell', () {
    expect(dohCurlArguments('  https://dns.google/dns-query  ', ' 8.8.8.8 '),
        ' --doh-url https://dns.google/dns-query --resolve dns.google:443:8.8.8.8');
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
      expect(dohCurlArguments(r.url, r.ip), contains('--resolve $host:443:${r.ip}'), reason: r.label);
    }
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

    test('carries the arguments when a resolver is configured', () {
      final s = buildWatchdogScript(cfg(url: 'https://dns.google/dns-query', ip: '8.8.8.8'));
      expect(s, contains(r'CURLB="$CURLPLAIN --doh-url https://dns.google/dns-query --resolve dns.google:443:8.8.8.8"'));
      expect(s, contains('DOHDESC="dns.google (8.8.8.8)"'));
      // The retry drops back to plain resolution rather than failing the rebuild.
      expect(s, contains(r'$CURLPLAIN -S -o "$TMPTOK"'));
    });

    test('is exactly what it always was when none is configured', () {
      final s = buildWatchdogScript(cfg());
      expect(s, contains(r'CURLB="$CURLPLAIN"'));
      expect(s, contains('DOHDESC=""'));
      expect(s, isNot(contains('--doh-url')));
    });

    test('the SMTP host is resolved the same way before the mailer runs (ID-077)', () {
      final s = buildWatchdogScript(cfg(url: 'https://dns.google/dns-query', ip: '8.8.8.8'));
      expect(s, contains('resolve_smtp()'));
      expect(s, contains(r"-w '%{remote_ip}'"));
      // The entry goes in immediately before the send and comes out immediately after.
      expect(s.indexOf('resolve_smtp\n'), lessThan(s.indexOf('hosts_clean\n  rm -f "\$TMPMAIL"')));
      // And a run that was killed mid-send is cleaned up by the next one.
      expect(s, contains('HOSTSMARK="cfg-pia-wg-\$IFACE"'));
    });
  });
}
