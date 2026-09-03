// test/screens/main_menu_screen_test.dart - main menu + global chrome + drawer navigation.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/screens/main_menu_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';

// A controller whose 1 Hz countdown tick is pushed far into the future so the live countdown
// does not schedule frames during the test (otherwise pumpAndSettle would never settle).
SessionController _quietController() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

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

    expect(find.text('cfg-pia-wg'), findsOneWidget); // static header
    expect(find.byKey(const Key('app_hamburger')), findsOneWidget); // hamburger
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);
    expect(find.byKey(const Key('menu_manage_router')), findsOneWidget);
    expect(find.byKey(const Key('menu_watchdog')), findsOneWidget);
    expect(find.byKey(const Key('menu_log')), findsOneWidget);
    expect(find.byKey(const Key('menu_close_app')), findsOneWidget);
    expect(find.text('* requires SSH connectivity to an ASUS router'), findsOneWidget);
    expect(find.byKey(const Key('menu_help')), findsOneWidget);
    expect(find.textContaining('Select from the above'), findsNothing);
    // Both trailing lines are centred; the Column stretches them, so alignment is the Text's job.
    expect(tester.widget<Text>(find.text('* requires SSH connectivity to an ASUS router')).textAlign, TextAlign.center);
    expect(tester.widget<Text>(find.byKey(const Key('menu_help'))).textAlign, TextAlign.center);
    expect(find.text('Support development:'), findsOneWidget);
    expect(find.byKey(const Key('donate_paypal')), findsOneWidget);
    expect(find.byKey(const Key('donate_patreon')), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('the HELP link opens the README section for using the app', (tester) async {
    final launched = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launched.add((call.arguments as Map)['url'] as String);
      return true; // also answers canLaunch
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    // A TextSpan target cannot be tapped by position, so drive its recogniser.
    final span = tester.widget<Text>(find.byKey(const Key('menu_help'))).textSpan! as TextSpan;
    final help = span.children!.last as TextSpan;
    expect(help.text, ' How to use this app');
    (help.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(launched, ['https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#5-using-the-app']);
    expect(launched.single, kHelpUrl);

    await _teardown(tester, c);
  });

  testWidgets('the help line is an icon followed by the whole label as one link', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    final span = tester.widget<Text>(find.byKey(const Key('menu_help'))).textSpan! as TextSpan;
    expect(span.children, hasLength(2));
    expect(span.children!.first, isA<WidgetSpan>(), reason: 'the icon leads the line');
    final help = span.children!.last as TextSpan;
    expect(help.style?.decoration, TextDecoration.underline, reason: 'it has to read as a link');
    expect(help.recognizer, isNotNull);

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
    expect(find.text('Exit cfg-pia-wg?'), findsOneWidget);

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

  testWidgets('the drawer About entry sits below the log entry and navigates', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_about')), findsOneWidget);
    // Ordering: About is the last destination, directly under "View app log".
    final logY = tester.getCenter(find.byKey(const Key('drawer_log'))).dy;
    final aboutY = tester.getCenter(find.byKey(const Key('drawer_about'))).dy;
    expect(aboutY, greaterThan(logY));

    // No mock handler here, so the build-info channel raises MissingPluginException and the
    // screen must still render (this is the path every full-app test takes).
    await tester.tap(find.byKey(const Key('drawer_about')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Build runner ID:', findRichText: true), findsOneWidget);
    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);

    await _teardown(tester, c);
  });
}
