// test/unit/router_facts_test.dart - the router's own details for NETWORK's box (ID-706).
import 'package:cfg_pia_wg/router_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads each line, with the DDNS name when DDNS is on', () {
    final f = parseRouterFacts('WAN=203.0.113.9\nDDNSON=1\nDDNS=myhome.example.net\nHOST=router\nDOMAIN=home.example.net\nLAN=192.168.1.1\n');
    expect(f.wanIp, '203.0.113.9');
    expect(f.ddns, 'myhome.example.net');
    expect(f.hostname, 'router');
    expect(f.domain, 'home.example.net');
    expect(f.lanIp, '192.168.1.1');
  });

  test('a DDNS name the router kept after DDNS was switched off is not shown', () {
    expect(parseRouterFacts('DDNSON=0\nDDNS=old.example.net\n').ddns, '');
    expect(parseRouterFacts('DDNS=old.example.net\n').ddns, '', reason: 'no setting read is not "on"');
  });

  test('nothing, or lines that are not settings, give empty values and no error', () {
    final f = parseRouterFacts('');
    expect((f.wanIp, f.ddns, f.hostname, f.domain, f.lanIp), ('', '', '', '', ''));
    expect(parseRouterFacts('garbage\n=x\nWAN\n').wanIp, '');
  });

  test('keeps an equals sign in a value, and trims what the router pads', () {
    expect(parseRouterFacts('HOST= a=b \r\n').hostname, 'a=b');
  });

  test('the command only reads', () {
    expect(kRouterFactsCommand, isNot(contains('nvram set')));
    expect(kRouterFactsCommand, isNot(contains('commit')));
    expect(RegExp(r'nvram get').allMatches(kRouterFactsCommand).length, 6);
  });
}
