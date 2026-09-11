// test/unit/ssh_port_test.dart - the router's SSH daemon is not always on port 22.
//
// The app hardcoded 22 until build 412 and could not reach a router whose sshd had been moved -
// which the router's own WebUI actively encourages ("Due to security concerns, we suggest using a
// port from 1024 to 65535"). The port cannot be probed for first: reading `sshd_port_x` requires a
// working SSH session, so it has to come from the user, appended to the address as host:port.
//
// The parse has to be forgiving in one specific direction. A bad port falls back to 22 and lets the
// connection attempt fail on its own terms, because "connection refused" tells the user more than a
// parse error does.
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('splitHostPort', () {
    test('a bare address keeps the default port', () {
      expect(splitHostPort('192.168.50.1'), (host: '192.168.50.1', port: 22));
    });

    test('an explicit port is used', () {
      expect(splitHostPort('192.168.50.1:2222'), (host: '192.168.50.1', port: 2222));
    });

    test('a hostname works the same way', () {
      expect(splitHostPort('my-router.lan:1024'), (host: 'my-router.lan', port: 1024));
      expect(splitHostPort('my-router.lan'), (host: 'my-router.lan', port: 22));
    });

    test('surrounding whitespace is ignored', () {
      expect(splitHostPort('  192.168.50.1:2222  '), (host: '192.168.50.1', port: 2222));
    });

    test('the full valid range is accepted', () {
      expect(splitHostPort('h:1').port, 1);
      expect(splitHostPort('h:65535').port, 65535);
    });

    // Rather than throwing: a connection error is a more useful message to a user than a parse
    // error, and it is the same failure they would get from a typo in the address itself.
    for (final bad in ['192.168.50.1:', '192.168.50.1:0', '192.168.50.1:65536', '192.168.50.1:abc', '192.168.50.1:-1']) {
      test('falls back to 22 for $bad', () {
        expect(splitHostPort(bad).port, 22, reason: 'a bad port must not throw');
      });
    }

    test('a leading colon is not treated as a port', () {
      // ':22' has no host, so there is nothing to connect to - leave it whole and let the
      // connect fail rather than inventing an empty host.
      expect(splitHostPort(':22'), (host: ':22', port: 22));
    });
  });

  group('RouterPrefs accepts an address with a port', () {
    late Directory dir;
    late RouterPrefs prefs;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('ssh_port_test');
      prefs = RouterPrefs(directory: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a remembered address keeps its port', () async {
      // Before build 412 the validator rejected the colon, so the users who most need their
      // address remembered were the ones it silently refused to remember.
      expect(await prefs.remember('192.168.50.1:2222'), '192.168.50.1:2222');
      expect(await prefs.load(), '192.168.50.1:2222');
      expect(splitHostPort(await prefs.load()).port, 2222);
    });

    test('still refuses anything shell-unsafe', () async {
      for (final bad in ['192.168.50.1:22; reboot', '192.168.50.1:2222:3333', r'$(reboot):22']) {
        expect(await prefs.remember(bad), '', reason: '$bad must be refused');
      }
    });
  });
}
