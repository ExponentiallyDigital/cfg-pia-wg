// test/screens/main_menu_screen_test.dart - main menu + global chrome + drawer navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/app_shell.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';

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
    expect(find.byKey(const Key('app_hamburger')), findsOneWidget); // hamburger
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);
    expect(find.byKey(const Key('menu_manage_router')), findsOneWidget);
    expect(find.byKey(const Key('menu_watchdog')), findsOneWidget);
    expect(find.byKey(const Key('menu_log')), findsOneWidget);
    expect(find.byKey(const Key('menu_close_app')), findsOneWidget);
    expect(find.text('* requires SSH connectivity to an Asus router.'), findsOneWidget);
    expect(find.textContaining('Select from the above'), findsOneWidget); // green hint
    expect(find.text('Support development:'), findsOneWidget);
    expect(find.byKey(const Key('donate_paypal')), findsOneWidget);
    expect(find.byKey(const Key('donate_patreon')), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('drawer HOME returns to the main menu', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    // Go to the log screen, then use the drawer HOME entry to come back.
    await tester.tap(find.byKey(const Key('menu_log')));
    await tester.pumpAndSettle();
    expect(find.text('CLEAR LOG'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget); // back on the menu

    await _teardown(tester, c);
  });

  testWidgets('the Android back key prompts to confirm exit', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // simulate the back button on the main menu
    await tester.pumpAndSettle();
    expect(find.text('Exit application?'), findsOneWidget);

    // Cancel keeps the app open.
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('tapping a menu button navigates, and HOME returns to a fresh main menu', (tester) async {
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

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_log')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drawer_log')));
    await tester.pumpAndSettle();
    expect(find.text('CLEAR LOG'), findsOneWidget); // log screen

    await _teardown(tester, c);
  });
}
