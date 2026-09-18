// test/unit/router_connect_message_test.dart - a router that cannot be reached says so in words
// (ID-108).
//
// The list of things that mean "unreachable" is the part worth pinning: miss one and the user gets
// `SocketException ... errno = 110` on screen again.
import 'dart:async';
import 'dart:io';

import 'package:cfg_pia_wg/router_session.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unreachable router is named, with advice', () {
    for (final error in <Object>[
      const SocketException('Connection failed (OS Error: Network is unreachable, errno = 110)'),
      Exception('SocketConnection timed out, host: 192.168.1.1'),
      Exception('Connection refused'),
      Exception('No route to host'),
      Exception('Failed host lookup: my-router.example'),
      TimeoutException('no answer'),
    ]) {
      final message = routerConnectMessage(error, '192.168.1.1');
      expect(message, isNotNull, reason: '$error');
      expect(message, contains('the router at 192.168.1.1'), reason: '$error');
      expect(message, isNot(contains('errno')), reason: 'no exception text on screen');
    }
  });

  test('an error the app does not recognise keeps its caller wording', () {
    expect(routerConnectMessage(Exception('jq is not installed'), '192.168.1.1'), isNull);
  });

  test('a refused login is its own sentence', () {
    final message = routerConnectMessage(SSHAuthFailError('all authentication methods failed'), '192.168.1.1');
    expect(message, contains('refused that username or password'));
  });

  test('an address that was never entered still reads as a sentence', () {
    expect(routerConnectMessage(Exception('Connection refused'), '   '), contains('the router.'));
  });
}
