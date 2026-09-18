// test/screens/main_menu_screen_test.dart - main menu + global chrome + drawer navigation.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/review_service.dart';
import '../unit/review_service_test.dart' show installUrlLauncherMock;
import 'package:cfg_pia_wg/screens/main_menu_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_drawer.dart';

// A controller whose 1 Hz countdown tick is pushed far into the future so the live countdown
// does not schedule frames during the test (otherwise pumpAndSettle would never settle).
SessionController _quietController() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

// Unmounts the app and disposes the injected controller (cancelling its pending tick timer).
Future<void> _teardown(WidgetTester tester, SessionController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void main() {
  testWidgets('main menu shows all nine entries in drawer order, with no footnotes', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    expect(find.text('cfg-pia-wg'), findsOneWidget); // static header
    expect(find.byKey(const Key('app_hamburger')), findsOneWidget); // hamburger
    // Every destination, capitalised and in the drawer's order, then EXIT (2026-09-13).
    const labels = {
      'menu_standalone': 'STANDALONE',
      'menu_manage_router': 'MANAGE',
      'menu_watchdog': 'WATCHDOG',
      'menu_device_assignment': 'DEVICE ASSIGNMENT',
      'menu_router_log': 'ROUTER LOG',
      'menu_log': 'APP LOG',
      'menu_settings': 'SETTINGS',
      'menu_about': 'ABOUT',
      'menu_close_app': 'EXIT',
    };
    final tops = <double>[];
    for (final entry in labels.entries) {
      expect(find.descendant(of: find.byKey(Key(entry.key)), matching: find.text(entry.value)), findsOneWidget,
          reason: entry.key);
      tops.add(tester.getTopLeft(find.byKey(Key(entry.key))).dy);
    }
    expect(tops, orderedEquals(List.of(tops)..sort()), reason: 'in the order listed, EXIT last');
    // The superscript markers and both footnotes are gone.
    expect(find.textContaining('requires SSH connectivity'), findsNothing);
    expect(find.textContaining('stock firmware only'), findsNothing);
    expect(find.textContaining('¹'), findsNothing);
    expect(find.byKey(const Key('menu_help')), findsOneWidget);
    expect(find.textContaining('Select from the above'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('menu_help'))).textAlign, TextAlign.start);
    expect(find.byKey(const Key('menu_review')), findsOneWidget);
    // The donation block went when the app gained a price. Asking for money twice, in two different
    // ways, on the same screen reads as pleading; the review ask is the only thing left down there.
    expect(find.text('Support development:'), findsNothing);
    expect(find.byKey(const Key('donate_paypal')), findsNothing);
    expect(find.byKey(const Key('donate_patreon')), findsNothing);

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
    final icon = (span.children!.first as WidgetSpan).child as Icon;
    expect(icon.color, kLinkIconColour, reason: 'the khaki-gold the two footer icons share (ID-109)');
    final help = span.children!.last as TextSpan;
    expect(help.style?.decoration, isNot(TextDecoration.underline), reason: 'no underline (ID-110)');
    expect(help.recognizer, isNotNull, reason: 'still tappable');

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
    expect(find.byKey(const Key('app_log_clear')), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('drawer HOME returns to the main menu', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    // Go to the log screen, then use the drawer HOME entry to come back.
    await tester.tap(find.byKey(const Key('menu_log')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_log_clear')), findsOneWidget);

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
    await tester.tap(find.widgetWithText(OutlinedButton, 'CANCEL'));
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
    expect(find.byKey(const Key('app_log_clear')), findsOneWidget); // log screen

    await _teardown(tester, c);
  });

  testWidgets('the drawer About entry sits below the log entry and navigates', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_about')), findsOneWidget);
    // Ordering: ABOUT is the last destination, below APP LOG.
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
    /// The URLs url_launcher was asked to open.
    List<String> launchedUrls(List<MethodCall> calls) =>
        [for (final call in calls.where((c) => c.method == 'launch')) (call.arguments as Map)['url'] as String];

    testWidgets('a real tap opens the store listing', (tester) async {
      final calls = installUrlLauncherMock();
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('menu_review')));
      await tester.tap(find.byKey(const Key('menu_review')));
      await tester.pumpAndSettle();

      // The listing itself, every time. Play's in-app card is quota-limited and reports success
      // whether or not it drew anything, so a link built on it could not tell a shown card from
      // nothing happening at all.
      expect(launchedUrls(calls), [kPlayStoreListingUrl]);

      await _teardown(tester, c);
    });

    // A 12px line is a small thing to hit. The whole row is the target, not just the glyphs.
    testWidgets('the whole row is tappable, not only the text', (tester) async {
      final calls = installUrlLauncherMock();
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      // Under nine buttons it starts below the fold on the test surface, so scroll to it first.
      await tester.ensureVisible(find.byKey(const Key('menu_review')));
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byKey(const Key('menu_review')));
      expect(row.height, greaterThan(24), reason: 'a bare 12px line is not a comfortable target');
      // Well off to the side of the centred text, and still inside the row.
      await tester.tapAt(Offset(row.left + 8, row.center.dy));
      await tester.pumpAndSettle();

      expect(launchedUrls(calls), [kPlayStoreListingUrl]);

      await _teardown(tester, c);
    });

    // 2026-09-13: the help and review lines sit together directly under the buttons, with no gap between
    // them. They used to be split - help under the footnotes, the review pushed down to the foot.
    testWidgets('sits directly under the help line, which sits under the buttons', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final exitBottom = tester.getBottomLeft(find.byKey(const Key('menu_close_app'))).dy;
      final help = tester.getRect(find.byKey(const Key('menu_help')));
      final review = tester.getRect(find.byKey(const Key('menu_review')));
      expect(help.top, greaterThan(exitBottom), reason: 'after the buttons');
      expect(review.top, moreOrLessEquals(help.bottom, epsilon: 1), reason: 'no gap between the two lines');

      await _teardown(tester, c);
    });

    testWidgets('is an icon followed by the whole label, with no underline', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('menu_review')),
        matching: find.byType(Text),
      ));
      final span = text.textSpan! as TextSpan;
      expect(span.children, hasLength(2));
      final icon = (span.children!.first as WidgetSpan).child as Icon;
      expect(icon.color, kLinkIconColour, reason: 'the khaki-gold the two footer icons share (ID-109)');
      final label = span.children!.last as TextSpan;
      expect(label.text, ' add a Play Store app review');
      expect(label.style?.decoration, isNot(TextDecoration.underline), reason: 'no underline (ID-110)');

      await _teardown(tester, c);
    });

    // On a host that cannot open Play the tap must still say something, or it looks like the bug
    // it replaced.
    testWidgets('a host that cannot open Play says so in the app log', (tester) async {
      installUrlLauncherMock(failWith: PlatformException(code: 'ACTIVITY_NOT_FOUND', message: 'no store here'));
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('menu_review')));
      await tester.tap(find.byKey(const Key('menu_review')));
      await tester.pumpAndSettle();

      expect(c.log.any((e) => e.message.contains('Could not open the Play Store listing')), isTrue);

      await _teardown(tester, c);
    });
  });

  // ID-031: the menu is a left-aligned list. Icon and label used to be centred together, so every row's icon
  // started somewhere different and the screen read as nine disjointed bundles.
  group('the menu as a list', () {
    ButtonStyle styleOf(WidgetTester tester, String key) => tester.widget<OutlinedButton>(find.byKey(Key(key))).style!;
    Finder iconIn(String key, IconData icon) => find.descendant(of: find.byKey(Key(key)), matching: find.byIcon(icon));
    final rowKeys = [for (final d in AppDrawer.destinations) 'menu_${d.routeName}', 'menu_close_app'];

    testWidgets('each destination is a row: its own icon, its label and a chevron', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      for (final d in AppDrawer.destinations) {
        final key = 'menu_${d.routeName}';
        expect(iconIn(key, destinationIcon(d)), findsOneWidget, reason: '$key has its icon');
        expect(iconIn(key, Icons.chevron_right), findsOneWidget, reason: '$key opens a screen');
        final style = styleOf(tester, key);
        expect(style.backgroundColor!.resolve(<WidgetState>{}), kBg, reason: 'the screen colour, so it reads as bordered');
        expect(style.side!.resolve(<WidgetState>{})!.color, kHighlight, reason: 'every outline stays teal (ID-112)');
        expect(style.foregroundColor!.resolve(<WidgetState>{}), destinationColour(d),
            reason: 'icon and label take the destination colour (ID-112)');
      }

      await _teardown(tester, c);
    });

    testWidgets('EXIT is red, with the power icon and no chevron', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      expect(iconIn('menu_close_app', kExitIcon), findsOneWidget);
      expect(iconIn('menu_close_app', Icons.chevron_right), findsNothing, reason: 'it does not open a screen');
      expect(styleOf(tester, 'menu_close_app').side!.resolve(<WidgetState>{})!.color, kError);

      await _teardown(tester, c);
    });

    testWidgets('the icons form one column and the labels start in line', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final iconLefts = <double>[];
      final labelLefts = <double>[];
      for (final key in rowKeys) {
        iconLefts.add(tester.getTopLeft(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon)).first).dx);
        labelLefts.add(tester.getTopLeft(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)).first).dx);
      }
      for (final x in iconLefts) {
        expect(x, moreOrLessEquals(iconLefts.first, epsilon: 0.5), reason: 'one column of icons');
      }
      for (final x in labelLefts) {
        expect(x, moreOrLessEquals(labelLefts.first, epsilon: 0.5), reason: 'labels start in line, EXIT included');
      }

      await _teardown(tester, c);
    });

    test('every destination, HOME and EXIT has a different icon', () {
      final icons = {for (final d in AppDestination.values) destinationIcon(d), kExitIcon};
      expect(icons, hasLength(AppDestination.values.length + 1));
    });

    testWidgets('on a tablet the list stops at the cap and centres', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      final row = tester.getRect(find.byKey(const Key('menu_standalone')));
      expect(row.width, lessThanOrEqualTo(kMenuMaxWidth));
      expect(row.center.dx, moreOrLessEquals(640, epsilon: 1), reason: 'centred on the screen');

      await _teardown(tester, c);
    });

    testWidgets('on a phone the rows use the full width', (tester) async {
      // 412, a common Android phone width. At 360 the test font, which draws every glyph a full em wide, overflows
      // the header's "by Exponentially Digital" line - a test-font artefact that has nothing to do with the menu.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      // 20 of body padding each side.
      expect(tester.getRect(find.byKey(const Key('menu_standalone'))).width, moreOrLessEquals(372, epsilon: 1));

      await _teardown(tester, c);
    });

    testWidgets('the help and review lines line up with the rows, not the centre', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('menu_help'))).textAlign, TextAlign.start);
      final review = tester.widget<Text>(find.descendant(of: find.byKey(const Key('menu_review')), matching: find.byType(Text)));
      expect(review.textAlign, TextAlign.start);

      await _teardown(tester, c);
    });

    // ID-109: the two footer lines belong to the same column as the rows above them. Their icons
    // are 16px against the rows' 20px, so it is the icon CENTRES that have to agree, not the edges.
    testWidgets('the footer links put their icons in the menu icon column', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();

      double iconCentre(Finder of) =>
          tester.getRect(find.descendant(of: of, matching: find.byType(Icon)).first).center.dx;

      final rowIcon = iconCentre(find.byKey(const Key('menu_standalone')));
      expect(iconCentre(find.byKey(const Key('menu_help'))), moreOrLessEquals(rowIcon, epsilon: 1),
          reason: 'the help icon sits in the menu icon column');
      expect(iconCentre(find.byKey(const Key('menu_review'))), moreOrLessEquals(rowIcon, epsilon: 1),
          reason: 'the review icon sits in the menu icon column');

      await _teardown(tester, c);
    });

    // ID-107: on a screen taller than the menu the spare height is shared rather than all falling
    // below the block, and the share is weighted - an evenly split block reads slightly low.
    group('optical centring', () {
      Finder spacers() => find.descendant(of: find.byType(MainMenuScreen), matching: find.byType(Spacer));

      testWidgets('a tall screen shares the spare height, more of it below', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 1600);
        addTearDown(tester.view.reset);
        final c = _quietController();
        await tester.pumpWidget(PiaWgApp(controller: c));
        await tester.pumpAndSettle();

        expect(spacers(), findsNWidgets(2));
        final above = tester.getRect(spacers().at(0)).height;
        final below = tester.getRect(spacers().at(1)).height;
        expect(above, greaterThan(0), reason: 'the block no longer starts at the top');
        expect(below, greaterThan(above), reason: 'the smaller share goes above');
        expect(above / below, moreOrLessEquals(10 / 12, epsilon: 0.02));

        await _teardown(tester, c);
      });

      testWidgets('a short screen is unchanged: there is no spare height to share', (tester) async {
        // 412 x 640: the menu fills the viewport, so the spacers have nothing to take and the
        // screen scrolls exactly as it did before ID-107.
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(412, 640);
        addTearDown(tester.view.reset);
        final c = _quietController();
        await tester.pumpWidget(PiaWgApp(controller: c));
        await tester.pumpAndSettle();

        for (var i = 0; i < 2; i++) {
          expect(tester.getRect(spacers().at(i)).height, 0, reason: 'the spacers collapse and the screen scrolls');
        }

        await _teardown(tester, c);
      });
    });

    testWidgets('the drawer shows the same icon for each destination, plus HOME and EXIT', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('app_hamburger')));
      await tester.pumpAndSettle();

      expect(iconIn('drawer_menu', destinationIcon(AppDestination.menu)), findsOneWidget);
      for (final d in AppDrawer.destinations) {
        expect(iconIn('drawer_${d.routeName}', destinationIcon(d)), findsOneWidget, reason: d.routeName);
      }
      expect(iconIn('drawer_close_app', kExitIcon), findsOneWidget);

      await _teardown(tester, c);
    });
  });
}
