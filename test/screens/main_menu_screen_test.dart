// test/screens/main_menu_screen_test.dart - main menu + global chrome + drawer navigation.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/review_service.dart';
import '../unit/review_service_test.dart' show FakeInAppReview;
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
    expect(find.byKey(const Key('menu_review')), findsOneWidget);
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
    expect(help.text, ' how to use this app');
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


  // Reported: after using the back button and the hamburger menu in turn, the drawer's "View app
  // log" entry stopped working - the app thought that screen was already current. Popping a page
  // that sat above an open MODAL reported the dialog as the previous route, which the observer
  // ignored, so currentDestination kept naming the page just left.
  testWidgets('the drawer still navigates after a page is popped from above a dialog', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    // A dialog over the main menu, then a page pushed on top of it from the drawer.
    final ctx = tester.element(find.byKey(const Key('menu_log')));
    showDialog<void>(context: ctx, builder: (_) => const AlertDialog(content: Text('a modal')));
    await tester.pumpAndSettle();
    expect(c.currentDestination, AppDestination.menu, reason: 'a dialog is not a destination');

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer_log')));
    await tester.pumpAndSettle();
    expect(c.currentDestination, AppDestination.log);

    // Back: the log page pops and the dialog is on top again. The Android back key, not a back
    // button - these screens have no AppBar.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('a modal'), findsOneWidget);
    expect(c.currentDestination, AppDestination.menu, reason: 'the page below the dialog is the menu');

    // The drawer entry has to work again.
    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer_log')));
    await tester.pumpAndSettle();
    expect(find.text('CLEAR LOG'), findsOneWidget);

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

  // Reported in 407: the link did nothing when tapped, on debug and release alike. The tests that
  // shipped with it drove the TextSpan's recogniser directly, which bypasses hit-testing entirely -
  // so they would have passed against a link nobody could hit. These tap it for real.
  group('the Play Store review link', () {
    /// Stands in for the plugin. A method-channel mock is not enough: the plugin chooses its
    /// behaviour from the host platform in Dart, and a test host is not Android.
    FakeInAppReview installFakeReview({Object? failWith}) {
      final fake = FakeInAppReview(failWith: failWith);
      debugReviewOverride = fake;
      addTearDown(() => debugReviewOverride = null);
      return fake;
    }

    testWidgets('a real tap opens the store listing', (tester) async {
      final fake = installFakeReview();
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_review')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['openStoreListing']);
      // Play's in-app card is quota-limited and reports success whether or not it drew anything,
      // so a link built on it could not tell a shown card from nothing happening at all.
      expect(fake.calls, isNot(contains('requestReview')));

      await _teardown(tester, c);
    });

    // A 12px line is a small thing to hit. The whole row is the target, not just the glyphs.
    testWidgets('the whole row is tappable, not only the text', (tester) async {
      final fake = installFakeReview();
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final row = tester.getRect(find.byKey(const Key('menu_review')));
      expect(row.height, greaterThan(24), reason: 'a bare 12px line is not a comfortable target');
      // Well off to the side of the centred text, and still inside the row.
      await tester.tapAt(Offset(row.left + 8, row.center.dy));
      await tester.pumpAndSettle();

      expect(fake.calls, ['openStoreListing']);

      await _teardown(tester, c);
    });

    testWidgets('sits above the donation block, with a gap between them', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final review = tester.getBottomLeft(find.byKey(const Key('menu_review')));
      final donate = tester.getTopLeft(find.text('Support development:'));
      expect(review.dy, lessThan(donate.dy), reason: 'the ask comes first');
      expect(donate.dy - review.dy, greaterThan(16), reason: 'a few lines of air, not a tight stack');

      await _teardown(tester, c);
    });

    testWidgets('is an icon followed by the whole label, underlined', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('menu_review')),
        matching: find.byType(Text),
      ));
      final span = text.textSpan! as TextSpan;
      expect(span.children, hasLength(2));
      expect(span.children!.first, isA<WidgetSpan>(), reason: 'the icon leads the line');
      final label = span.children!.last as TextSpan;
      expect(label.text, ' add a Play Store app review');
      expect(label.style?.decoration, TextDecoration.underline, reason: 'it has to read as a link');

      await _teardown(tester, c);
    });

    // On a host that cannot open Play the tap must still say something, or it looks like the bug
    // it replaced.
    testWidgets('a host that cannot open Play says so in the app log', (tester) async {
      installFakeReview(failWith: UnsupportedError('no store here'));
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_review')));
      await tester.pumpAndSettle();

      expect(c.log.any((e) => e.message.contains('Could not open the Play Store listing')), isTrue);

      await _teardown(tester, c);
    });
  });

}
