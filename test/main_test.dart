import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/session_controller.dart';

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

      for (final key in const ['menu_manage_router', 'menu_watchdog', 'menu_log']) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('screen_close')), findsOneWidget);
        await tester.tap(find.byKey(const Key('screen_close')));
        await tester.pumpAndSettle();
      }

      await disposeApp(tester, c);
    });

    // The screen HOME button matches the slot modal's: teal text and border, not muted/grey.
    testWidgets('screen HOME is teal', (tester) async {
      final c = quietController();
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('menu_log')));
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

    testWidgets('Exit app confirms, wipes credentials and asks the platform to exit', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final c = quietController();
      await pumpApp(tester, c);
      c.piaUsername = 'p1234567';

      await tester.tap(find.byKey(const Key('menu_close_app')));
      await tester.pumpAndSettle();

      // Confirmation dialog (all exit paths) — Exit proceeds.
      expect(find.text('Exit cfg-pia-wg?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'EXIT'));
      await tester.pumpAndSettle();

      expect(c.piaUsername, isEmpty);
      expect(calls, contains('SystemNavigator.pop'));

      await disposeApp(tester, c);
    });
  });
}
