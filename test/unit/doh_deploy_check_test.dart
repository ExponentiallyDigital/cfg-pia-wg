// test/unit/doh_deploy_check_test.dart - SAVE & DEPLOY tries the watchdog's encrypted DNS from the
// router before anything is written (ID-612).
//
// Seen on Merlin 388.13_0, 2026-11-15: Quad9's DoH answers only over HTTP/2, the router's curl
// (8.17.0) has none, and every lookup through https://dns.quad9.net/dns-query came back HTTP 505.
// The form offers Quad9, and a watchdog set to it fell back to the router's own resolver on every
// lookup, saying so only in its log. What the router answers here is as measured that day; that the
// check refuses Quad9 on the router itself is TESTING's hand test, not this file.
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _quad9 = (url: 'https://dns.quad9.net/dns-query', ip: '9.9.9.9');

WatchdogConfig _cfg({String url = '', String ip = ''}) => WatchdogConfig(
    slotIndex: 1, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1', dohUrl: url, dohIp: ip);

RouterWatchdog _wd(RecordingSSHClient c) => RouterWatchdog(c, verifyPollInterval: Duration.zero, verifyMaxAttempts: 1);

void main() {
  group('the lookup the router is asked to make', () {
    final cmd = dohCheckCommand(dohEndpoint(_quad9.url, _quad9.ip)!);

    test('is one DNS query for a name, posted to the server as the watchdog posts its own', () {
      expect(cmd, contains("--data-binary @"));
      expect(cmd, contains("-H 'content-type: application/dns-message'"));
      expect(cmd, contains("--resolve 'dns.quad9.net:443:9.9.9.9'"), reason: 'the address is given, so no name is looked up to ask');
      expect(cmd, contains("'https://dns.quad9.net/dns-query'"));
      expect(cmd, contains("-w '%{http_code}'"));
    });

    test('leaves nothing behind: its query file goes, and the firmware\'s record of the command', () {
      expect(cmd, contains('rm -f "\$Q"'));
      expect(cmd, contains('[ -f /jffs/curllst ] && : > /jffs/curllst'));
    });
  });

  group('what an answer means', () {
    test('200 is a server the router can use', () {
      expect(dohCheckProblem('dns.quad9.net (9.9.9.9)', '200'), isNull);
    });

    test('505 is said in words: the server needs HTTP/2 and the router has none', () {
      final p = dohCheckProblem('dns.quad9.net (9.9.9.9)', '505')!;
      expect(p, contains('dns.quad9.net (9.9.9.9)'));
      expect(p, contains('HTTP/2'));
      expect(p, contains('Choose another'));
    });

    test('no connection, and any other refusal, each say what came back', () {
      expect(dohCheckProblem('x (1.2.3.4)', '000'), contains('did not answer'));
      expect(dohCheckProblem('x (1.2.3.4)', ''), contains('did not answer'));
      expect(dohCheckProblem('x (1.2.3.4)', '403'), contains('HTTP 403'));
    });
  });

  group('asked of the router', () {
    test('a server that answers 505 is a problem, and one that answers 200 is not', () async {
      final refused = RecordingSSHClient(responder: (cmd) => cmd.contains('application/dns-message') ? '505' : '');
      expect(await _wd(refused).dohProblem(_cfg(url: _quad9.url, ip: _quad9.ip)), contains('HTTP/2'));
      final fine = RecordingSSHClient(responder: (cmd) => cmd.contains('application/dns-message') ? '200' : '');
      expect(await _wd(fine).dohProblem(_cfg(url: _quad9.url, ip: _quad9.ip)), isNull);
    });

    test('with no encrypted DNS set there is nothing to try, and the router is not asked', () async {
      final c = RecordingSSHClient(responder: (_) => '');
      expect(await _wd(c).dohProblem(_cfg()), isNull);
      expect(c.commands, isEmpty);
    });
  });
}
