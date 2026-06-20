// test/router_push_watchdog_test.dart - watchdog integration points inside RouterPushSheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';

import 'package:pia_wireguard_cfga/router_push.dart';
import 'package:pia_wireguard_cfga/router_watchdog.dart';

import 'watchdog_test_utils.dart';

void _noop(String m, {bool isError = false, bool isSuccess = false}) {}

const _sampleConfig = '[Interface]\n'
    'PrivateKey = x\n'
    'Address = 10.0.0.2/32\n'
    'DNS = 1.1.1.1\n'
    'MTU = 1420\n\n'
    '[Peer]\n'
    'PublicKey = y\n'
    'Endpoint = 1.2.3.4:1337\n'
    'AllowedIPs = 0.0.0.0/0\n';

Widget _app(RecordingSSHClient client, {RouterWatchdog Function(SSHClient)? wdFactory}) {
  return MaterialApp(
    home: Scaffold(
      body: RouterPushSheet(
        config: _sampleConfig,
        regionId: 'aus_melbourne',
        onLog: _noop,
        piaUsername: 'p1234567',
        piaPassword: 'secret',
        testClientFactory: (ip, user, pass) async => client,
        watchdogServiceFactory: wdFactory,
      ),
    ),
  );
}

Future<void> _login(WidgetTester tester) async {
  final tf = find.byType(TextField);
  await tester.enterText(tf.at(0), '192.168.1.1');
  await tester.enterText(tf.at(1), 'admin');
  await tester.enterText(tf.at(2), 'pw');
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONNECT'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('WATCHDOG button appears only on Merlin routers', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('3rd-party')) return 'merlin';
      if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
      return '';
    });
    await tester.pumpWidget(_app(c));
    await _login(tester);
    expect(find.text('WATCHDOG CONFIG'), findsOneWidget);
  });

  testWidgets('WATCHDOG button is hidden on non-Merlin routers', (tester) async {
    final c = RecordingSSHClient(responder: (_) => ''); // 3rd-party -> '' (not merlin)
    await tester.pumpWidget(_app(c));
    await _login(tester);
    expect(find.text('WATCHDOG CONFIG'), findsNothing);
  });

  testWidgets('"WATCHDOG ACTIVE" and "KILL SWITCH" badges show for slot 1', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('3rd-party')) return 'merlin';
      if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
      if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
      if (cmd.contains('wgc1_enforce')) return '1'; // kill switch on for slot 1
      return '';
    });
    await tester.pumpWidget(_app(c));
    await _login(tester);
    expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
    expect(find.text('⚑ KILL SWITCH'), findsOneWidget);
  });

  testWidgets('tapping WATCHDOG opens the dialog', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('3rd-party')) return 'merlin';
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
      return '';
    });
    await tester.pumpWidget(_app(c, wdFactory: (cl) => RouterWatchdog(cl, onLog: _noop)));
    await _login(tester);

    await tester.ensureVisible(find.text('WATCHDOG CONFIG'));
    await tester.tap(find.text('WATCHDOG CONFIG'));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG · wgc1'), findsOneWidget);

    await tester.ensureVisible(find.text('CLOSE'));
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text('WATCHDOG · wgc1'), findsNothing);
  });
}
