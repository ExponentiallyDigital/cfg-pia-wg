// test/unit/input_checks_test.dart - what a typed value must look like before it reaches the router (ID-237).
import 'package:cfg_pia_wg/input_checks.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

final _key = '${'B' * 42}Q=';

WatchdogConfig _cfg({String dohUrl = '', String dohIp = '', String slotDns = '', int interval = 5}) => WatchdogConfig(
      slotIndex: 1,
      cronIntervalMinutes: interval,
      primaryIp: '8.8.8.8',
      secondaryIp: '1.1.1.1',
      piaUsername: 'p123456789',
      piaPassword: 'secret',
      dohUrl: dohUrl,
      dohIp: dohIp,
      slotDns: slotDns,
    );

void main() {
  group('the watchdog\'s encrypted DNS (ID-221)', () {
    test('the fields as found on 2026-09-27, swapped, are refused and say which way round', () {
      final errors = _cfg(dohUrl: '76.76.2.1', dohIp: 'https://freedns.controld.com/p1').validate();
      expect(errors.any((e) => e.contains('is an address. The URL goes here')), isTrue);
      expect(errors.any((e) => e.contains('that is a URL. The address goes here')), isTrue);
    });

    test('two addresses are taken, and stored as curl wants them', () {
      final c = _cfg(dohUrl: 'https://freedns.controld.com/p1', dohIp: '76.76.2.1, 76.76.10.1');
      expect(c.validate(), isEmpty);
      expect(c.toNvram()['wgc1_wd_doh_ip'], '76.76.2.1,76.76.10.1');
      expect(dohEndpoint(c.dohUrl, c.dohIp)?.addresses, '76.76.2.1,76.76.10.1');
    });

    test('a router already holding a list with a space still builds one option', () {
      expect(dohEndpoint('https://freedns.controld.com/p1', '76.76.2.1, 76.76.10.1')?.addresses, '76.76.2.1,76.76.10.1');
    });

    test('three addresses, one field alone, http, and an address as the URL host are each refused', () {
      expect(_cfg(dohUrl: 'https://a.example', dohIp: '1.1.1.1,1.0.0.1,9.9.9.9').validate(), isNotEmpty);
      expect(_cfg(dohUrl: 'https://a.example').validate().single, contains('both'));
      expect(_cfg(dohUrl: 'http://a.example', dohIp: '1.1.1.1').validate(), isNotEmpty);
      expect(_cfg(dohUrl: 'https://1.1.1.1/dns-query', dohIp: '1.1.1.1').validate().single, contains('hostname'));
    });

    test('neither field is fine: lookups stay ordinary', () {
      expect(_cfg().validate(), isEmpty);
    });

    test('a stored pair that cannot be used says so in the log, rather than "none configured"', () {
      final script = buildWatchdogScript(_cfg(dohUrl: '76.76.2.1', dohIp: 'https://freedns.controld.com/p1'));
      expect(script, contains('DOHDESC=""'));
      expect(script, contains('DOHBAD="encrypted DNS is set on the WATCHDOG form but cannot be used'));
      expect(buildWatchdogScript(_cfg()), contains('DOHBAD=""'));
      expect(dohUnusableNote('https://freedns.controld.com/p1', '76.76.2.1'), isEmpty);
    });
  });

  group('WATCHDOG form (ID-237)', () {
    test('the check interval runs from 1 to 59 minutes', () {
      expect(_cfg(interval: 59).validate(), isEmpty);
      expect(_cfg(interval: 60).validate().single, contains('1 to 59'));
      expect(_cfg(interval: 0).validate().single, contains('1 to 59'));
    });

    test("the slot's DNS must be one or two addresses", () {
      expect(_cfg(slotDns: '9.9.9.9, 149.112.112.112').validate(), isEmpty);
      expect(_cfg(slotDns: '9.9.9.9 x').validate().single, contains('"x" is not an IPv4 address'));
      expect(_cfg(slotDns: '1.1.1.1, 1.0.0.1, 9.9.9.9').validate().single, contains('at most 2'));
    });

    test('the SMTP server needs a real host and a real port', () {
      expect(checkHostPort('smtp.gmail.com:465', field: 'SMTP server'), isNull);
      expect(checkHostPort(':465', field: 'SMTP server'), contains('host:port'));
      expect(checkHostPort('smtp.gmail.com:abc', field: 'SMTP server'), contains('1 to 65535'));
      expect(checkHostPort('smtps://smtp.gmail.com:465', field: 'SMTP server'), contains('not a server name'));
      expect(checkHostPort(r'smtp.gmail.com$(reboot):465', field: 'SMTP server'), isNotNull);
    });
  });

  group('MANAGE -> EDIT (ID-237)', () {
    Map<String, String> good() => {
          'addr': '10.0.0.2/32',
          'desc': 'pia-aus_perth',
          'dns': '9.9.9.9, 149.112.112.112',
          'ep_addr': '203.0.113.5',
          'ep_port': '1337',
          'ppub': _key,
          'priv': _key,
          'mtu': '1420',
          'alive': '25',
          'aips': '0.0.0.0/0',
        };

    test('a sound slot has nothing wrong with it', () {
      expect(slotParamErrors(good()), isEmpty);
    });

    test('< or > in the description, which would corrupt every VPN profile on the router, is refused', () {
      expect(slotParamErrors(good()..['desc'] = 'home<vpn').single, contains('cannot contain'));
      expect(slotParamErrors(good()..['desc'] = 'Home VPN'), isEmpty, reason: 'a web-interface name with spaces is fine');
    });

    test('each other field is checked for its own shape', () {
      final bad = good()
        ..['addr'] = '10.0.0.2'
        ..['ep_port'] = '70000'
        ..['ppub'] = 'pub=='
        ..['mtu'] = '9000'
        ..['aips'] = '0.0.0.0';
      expect(slotParamErrors(bad), hasLength(5));
    });
  });

  group('shell injection (ID-237)', () {
    test('a DoH URL that would run as shell in the script is refused, and never reaches it', () {
      for (final url in [
        r'https://dns.example/$(reboot)',
        'https://dns.example/`reboot`',
        'https://dns.example/"x',
        r'https://dns.example/a\b',
        'https://dns.example/a b',
      ]) {
        expect(checkDohUrl(url), isNotNull, reason: url);
        expect(dohEndpoint(url, '9.9.9.9'), isNull, reason: 'a value stored before the check: $url');
        expect(dohUnusableNote(url, '9.9.9.9'), isNotEmpty);
      }
      expect(checkDohUrl('https://freedns.controld.com/p1'), isNull);
      expect(checkDohUrl('https://dns.google/dns-query'), isNull);
      expect(checkDohUrl('https://doh.example:8443/dns-query?ecs=0&x=y'), isNull);
    });

    test('an email address that is not plain is refused', () {
      expect(isValidEmail('you@example.com'), isTrue);
      expect(isValidEmail("o'brien+alerts@mail.example.com"), isTrue);
      expect(isValidEmail(r'a$(reboot)@example.com'), isFalse);
      expect(isValidEmail('a@example.com;reboot'), isFalse);
      expect(isValidEmail('a@localhost'), isFalse);
    });

    test('a line break in a login or the subject is refused', () {
      final c = WatchdogConfig(
        slotIndex: 1,
        cronIntervalMinutes: 5,
        primaryIp: '8.8.8.8',
        secondaryIp: '1.1.1.1',
        piaUsername: 'p123456789',
        piaPassword: 'secret',
        emailSubject: 'Router\nBcc: x@example.com',
      );
      expect(c.validate().single, contains('Email subject cannot contain a line break'));
      expect(checkSlotDescription('pia\tnz'), isNotNull);
    });

    test('text holding the upload delimiter on a line of its own is not uploaded', () {
      expect(() => heredocWriteCommands('/tmp/mail.txt', 'one\nWATCHDOG_EOF\nreboot'), throwsArgumentError);
    });
  });

  test('ENABLE check targets and CREATE DNS use the same address rules', () {
    expect(checkIpv4('8.8.8.8', field: 'Primary ping IP'), isNull);
    expect(checkIpv4('8.8.8.8, 1.1.1.1', field: 'Primary ping IP'), isNotNull);
    expect(checkIpv4List('', field: 'DNS servers', required: false), isNull, reason: 'blank takes the defaults');
  });
}
