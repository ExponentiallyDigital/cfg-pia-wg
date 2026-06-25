// test/screens/router_screens_test.dart - Manage-router + VPN-watchdog connect screens.
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/router_slot_service.dart';
import 'package:cfg_pia_wireguard/screens/manage_router_screen.dart';
import 'package:cfg_pia_wireguard/screens/watchdog_management_screen.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';

import '../watchdog_test_utils.dart';

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

RouterSlotService _fastSvc(SSHClient c, SessionController ctrl) =>
    RouterSlotService(c, onLog: ctrl.onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: 1);

Widget _manage(RecordingSSHClient ssh, SessionController c) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(
          body: ManageRouterScreen(
            testClientFactory: (ip, u, p) async => ssh,
            slotServiceFactory: (cl) => _fastSvc(cl, c),
          ),
        ),
      ),
    );

Widget _watchdog(RecordingSSHClient ssh, SessionController c) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(
          body: WatchdogManagementScreen(
            testClientFactory: (ip, u, p) async => ssh,
            slotServiceFactory: (cl) => _fastSvc(cl, c),
          ),
        ),
      ),
    );

Future<void> _fillCreds(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Router IP'), '192.168.0.254');
  await tester.enterText(find.widgetWithText(TextFormField, 'SSH Username'), 'admin');
  await tester.enterText(find.widgetWithText(TextFormField, 'SSH Password'), 'pw');
  await tester.pump();
}

void main() {
  testWidgets('CONNECT is disabled until IP + username + password are filled', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(find.byKey(const Key('connect_router'))).onPressed, isNull);
    await _fillCreds(tester);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('connect_router'))).onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('SSH credentials pre-fill from the shared session', (tester) async {
    final c = _controller()
      ..routerIp = '10.0.0.1'
      ..sshUsername = 'root';
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '10.0.0.1'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'root'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('manage CONNECT opens the slot modal', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('3rd-party')) return 'merlin';
      if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
      return '';
    });
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    await _fillCreds(tester);
    await tester.tap(find.byKey(const Key('connect_router')));
    await tester.pumpAndSettle();

    expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);
    expect(find.text('aus_melbourne'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('watchdog CONNECT opens the slot modal on Merlin', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : '');
    await tester.pumpWidget(_watchdog(ssh, c));
    await tester.pumpAndSettle();

    await _fillCreds(tester);
    await tester.tap(find.byKey(const Key('connect_router')));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG CONFIGURATION'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('watchdog CONNECT on non-Merlin firmware is rejected', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (_) => ''); // 3rd-party != merlin
    await tester.pumpWidget(_watchdog(ssh, c));
    await tester.pumpAndSettle();

    await _fillCreds(tester);
    await tester.tap(find.byKey(const Key('connect_router')));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG CONFIGURATION'), findsNothing);
    expect(find.textContaining('Merlin'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
