// test/screens/main_menu_screen_test.dart - main menu + global chrome + drawer navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/app_shell.dart';
import 'package:pia_wireguard_cfga/session_controller.dart';

// A controller whose 1 Hz countdown tick is pushed far into the future so the live countdown
// does not schedule frames during the test (otherwise pumpAndSettle would never settle).
SessionController _quietController() => SessionController(
      tickInterval: const Duration(hours: 1),
      clipboardWriter: (_) async {},
    );

// Unmounts the app and disposes the injected controller (cancelling its pending tick timer).
Future<void> _teardown(WidgetTester tester, SessionController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void main() {
  testWidgets('main menu shows five entries, the footnote, hamburger and header', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    expect(find.text('Configure PIA WireGuard'), findsOneWidget); // static header
    expect(find.byIcon(Icons.menu), findsOneWidget); // hamburger
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);
    expect(find.byKey(const Key('menu_manage_router')), findsOneWidget);
    expect(find.byKey(const Key('menu_watchdog')), findsOneWidget);
    expect(find.byKey(const Key('menu_log')), findsOneWidget);
    expect(find.byKey(const Key('menu_close_app')), findsOneWidget);
    expect(find.text('* requires SSH connectivity to an Asus router.'), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('tapping a menu button navigates, and CLOSE returns to a fresh main menu', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_standalone')));
    await tester.pumpAndSettle();
    expect(find.text('GENERATE CONFIG'), findsOneWidget); // the standalone screen

    await tester.tap(find.byKey(const Key('screen_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('hamburger drawer navigates between destinations', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_log')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drawer_log')));
    await tester.pumpAndSettle();
    expect(find.text('CLEAR LOG'), findsOneWidget); // log screen

    await _teardown(tester, c);
  });
}
