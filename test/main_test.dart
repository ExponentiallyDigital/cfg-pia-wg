import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/watchdog_email.dart';

import 'app_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiaWgApp shell', () {
    testWidgets('runApp builds without throwing', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);
      expect(find.byType(PiaWgApp), findsOneWidget);
      await disposeApp(tester, c);
    });

    testWidgets('app lifecycle transitions resync without error', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);

      final dynamic binding = WidgetsBinding.instance;
      for (final s in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }

      await disposeApp(tester, c);
    });

    testWidgets('navigates to each destination from the main menu', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);

      for (final key in const ['menu_manage_router', 'menu_watchdog']) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('screen_close')), findsOneWidget);
        await tester.tap(find.byKey(const Key('screen_close')));
        await tester.pumpAndSettle();
      }

      // The app log carries its own HOME in the three-button row, like both other log screens.
      await tester.tap(find.byKey(const Key('menu_log')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app_log_home')), findsOneWidget);
      await tester.tap(find.byKey(const Key('app_log_home')));
      await tester.pumpAndSettle();

      await disposeApp(tester, c);
    });

    // The screen HOME button matches the slot modal's: teal text and border, not muted/grey.
    testWidgets('screen HOME is teal', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('menu_manage_router')));
      await tester.pumpAndSettle();

      final style = tester.widget<OutlinedButton>(find.byKey(const Key('screen_close'))).style!;
      const states = <WidgetState>{};
      expect(style.foregroundColor!.resolve(states), kHighlight);
      expect(style.side!.resolve(states)!.color, kHighlight);

      await disposeApp(tester, c);
    });

    testWidgets('currentDestination tracks the top route', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);
      expect(c.currentDestination, AppDestination.menu);

      await tester.tap(find.byKey(const Key('menu_log')));
      await tester.pumpAndSettle();
      expect(c.currentDestination, AppDestination.log);

      await disposeApp(tester, c);
    });

    testWidgets('EXIT confirms, wipes credentials and asks the platform to exit', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final c = quietController();
      await pumpApp(tester, c);
      c.piaUsername = 'p1234567';

      await tester.ensureVisible(find.byKey(const Key('menu_close_app')));
      await tester.tap(find.byKey(const Key('menu_close_app')));
      await tester.pumpAndSettle();

      // Confirmation dialog (all exit paths) — Exit proceeds.
      expect(find.text('Exit cfg-pia-wg?'), findsOneWidget);
      // The menu's own button is labelled EXIT too now, so the dialog's is found inside the dialog.
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(OutlinedButton, 'EXIT')));
      await tester.pumpAndSettle();

      expect(c.piaUsername, isEmpty);
      expect(calls, contains('SystemNavigator.pop'));

      await disposeApp(tester, c);
    });
  });

  // ID-394. An iOS app can't close itself, so on iOS EXIT reads CLEAR: the same wipe, then back to the
  // main menu. Android keeps EXIT, which the test above and main_menu_screen_test.dart hold.
  group('CLEAR on iOS', () {
    late List<String> calls;

    setUp(() {
      calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    });

    /// Every field [SessionController.wipeAll] clears, set to something it must take away.
    void fill(SessionController c) {
      c.piaUsername = 'p1234567';
      c.piaPassword = 'pia-secret';
      c.dns = '9.9.9.9';
      c.routerIp = '192.0.2.1';
      c.sshUsername = 'admin';
      c.sshPassword = 'ssh-secret';
      c.generatedConfig = '[Interface]\nPrivateKey = secret';
      c.generatedRegionId = 'au_melbourne';
      c.watchdogEmail = const EmailSettings(smtpServer: 'smtp.example.com', to: 'a@example.com', smtpPass: 'mail-secret');
      c.routerConnected = true;
    }

    Map<String, Object?> state(SessionController c) => {
          'piaUsername': c.piaUsername,
          'piaPassword': c.piaPassword,
          'dns': c.dns,
          'routerIp': c.routerIp,
          'sshUsername': c.sshUsername,
          'sshPassword': c.sshPassword,
          'generatedConfig': c.generatedConfig,
          'generatedRegionId': c.generatedRegionId,
          'watchdogEmail': c.watchdogEmail,
          'routerConnected': c.routerConnected,
        };

    /// Fills [c], taps the menu's last row and confirms, as [platform]; returns what is left.
    Future<Map<String, Object?>> leaveAs(WidgetTester tester, SessionController c, TargetPlatform platform, String label) async {
      debugDefaultTargetPlatformOverride = platform;
      await pumpApp(tester, c);
      fill(c);
      await tester.ensureVisible(find.byKey(const Key('menu_close_app')));
      await tester.tap(find.byKey(const Key('menu_close_app')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(OutlinedButton, label)));
      await tester.pumpAndSettle();
      final left = state(c);
      await disposeApp(tester, c);
      debugDefaultTargetPlatformOverride = null;
      return left;
    }

    testWidgets('the menu and the drawer say CLEAR, and the dialog says what happens', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = quietController();
      await pumpApp(tester, c);

      expect(find.descendant(of: find.byKey(const Key('menu_close_app')), matching: find.text('CLEAR')), findsOneWidget);
      expect(find.text('EXIT'), findsNothing);
      await tester.tap(find.byKey(const Key('app_hamburger')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('drawer_close_app')), matching: find.text('CLEAR')), findsOneWidget);

      await tester.tap(find.byKey(const Key('drawer_close_app')));
      await tester.pumpAndSettle();
      expect(find.text('Clear cfg-pia-wg?'), findsOneWidget);
      expect(find.textContaining('returns to the main menu'), findsOneWidget);
      expect(find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(OutlinedButton, 'CLEAR')), findsOneWidget);

      await disposeApp(tester, c);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('CLEAR wipes everything EXIT wipes, and does not ask iOS to close the app', (tester) async {
      final exited = await leaveAs(tester, quietController(), TargetPlatform.android, 'EXIT');
      expect(calls, contains('SystemNavigator.pop'));

      calls.clear();
      final c = quietController();
      final cleared = await leaveAs(tester, c, TargetPlatform.iOS, 'CLEAR');

      expect(cleared, exited);
      expect(cleared['piaPassword'], isEmpty);
      expect(cleared['sshPassword'], isEmpty);
      expect(cleared['generatedConfig'], isNull);
      expect(cleared['watchdogEmail'], isNull);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(c.log.map((e) => e.message), contains(endsWith('All credentials and WireGuard configuration wiped from memory (cleared).')));
    });

    testWidgets('CLEAR from a screen deep in the app closes it and returns to the main menu', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = quietController();
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('menu_log')));
      await tester.pumpAndSettle();
      expect(c.currentDestination, AppDestination.log);

      await tester.tap(find.byKey(const Key('app_hamburger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drawer_close_app')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(OutlinedButton, 'CLEAR')));
      await tester.pumpAndSettle();

      expect(c.currentDestination, AppDestination.menu);
      expect(find.byKey(const Key('app_log_clear')), findsNothing, reason: 'the log screen is closed');
      expect(find.byKey(const Key('menu_close_app')), findsOneWidget);

      await disposeApp(tester, c);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('CANCEL leaves everything as it was', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = quietController();
      await pumpApp(tester, c);
      fill(c);
      await tester.ensureVisible(find.byKey(const Key('menu_close_app')));
      await tester.tap(find.byKey(const Key('menu_close_app')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'CANCEL'));
      await tester.pumpAndSettle();
      expect(c.sshPassword, 'ssh-secret');

      await disposeApp(tester, c);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
