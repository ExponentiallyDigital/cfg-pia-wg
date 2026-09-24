// test/widgets/ssh_creds_dialog_test.dart - the login ABOUT, SETTINGS and ROUTER LOG share (ID-155).
//
// The login is checked while the dialog is still open, so a password manager is offered the
// credentials only once the router has accepted them, and every other screen reuses them.
import 'package:cfg_pia_wg/screens/router_log_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/ssh_creds_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

void main() {
  late SessionController c;
  setUp(() => c = SessionController(tickInterval: const Duration(hours: 1)));
  tearDown(() => c.dispose());

  Future<(String, String, String)?> open(WidgetTester tester, {required bool reachable}) async {
    (String, String, String)? result;
    await tester.pumpWidget(SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async => result = await showDialog<(String, String, String)?>(
                context: ctx,
                builder: (_) => SshCredsDialog(
                  initialIp: '192.168.1.1',
                  initialUser: '',
                  initialPass: '',
                  verify: (ip, user, pass) => verifyRouterLogin(c, ip, user, pass,
                      testClientFactory: (_, __, ___) async =>
                          reachable ? RecordingSSHClient() : throw Exception('Connection refused')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'SSH Username'), 'admin');
    await tester.enterText(find.widgetWithText(TextFormField, 'SSH Password'), 'pw');
    await tester.tap(find.byKey(const Key('about_ssh_continue')));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a login the router accepts closes the dialog and is kept for the session', (tester) async {
    await open(tester, reachable: true);
    expect(find.byType(SshCredsDialog), findsNothing);
    expect(c.routerConnected, isTrue);
    expect(c.canReuseRouterSession, isTrue, reason: 'MANAGE and the rest reuse it without asking');
  });

  testWidgets('a login that fails keeps the dialog open with the reason, and is not kept', (tester) async {
    await open(tester, reachable: false);
    expect(find.byType(SshCredsDialog), findsOneWidget);
    expect(find.textContaining('Could not connect to the router at 192.168.1.1'), findsOneWidget);
    expect(c.routerConnected, isFalse);
    expect(c.log.any((e) => e.message.contains('Connection refused')), isTrue, reason: 'the raw error is logged');
  });

  testWidgets('CANCEL at ROUTER LOG\'s first login goes back, not to an empty log', (tester) async {
    await tester.pumpWidget(SessionScope(
      controller: c,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: RouterLogScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient())))),
              child: const Text('where the user was'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('where the user was'));
    await tester.pumpAndSettle();
    expect(find.byType(SshCredsDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('about_ssh_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(RouterLogScreen), findsNothing);
    expect(find.text('where the user was'), findsOneWidget);
  });
}
