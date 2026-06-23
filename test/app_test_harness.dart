// test/app_test_harness.dart - shared helpers for full-app widget tests.
//
// The live 1 Hz inactivity countdown schedules a frame every second, so a default controller would
// make pumpAndSettle hang. Tests inject a controller whose tick interval is pushed far out, then
// dispose it (cancelling the timer) at the end of the test body.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/app_shell.dart';
import 'package:pia_wireguard_cfga/session_controller.dart';

SessionController quietController({
  Duration? inactivityTimeout,
  Duration tickInterval = const Duration(hours: 1),
}) =>
    SessionController(
      tickInterval: tickInterval,
      inactivityTimeout: inactivityTimeout ?? const Duration(minutes: 10),
      clipboardWriter: (_) async {},
    );

Future<void> pumpApp(WidgetTester tester, SessionController c) async {
  await tester.pumpWidget(PiaWgApp(controller: c));
  await tester.pumpAndSettle();
}

/// Pumps the app then navigates from the main menu into the standalone generate screen.
Future<void> pumpAppAtStandalone(WidgetTester tester, SessionController c) async {
  await pumpApp(tester, c);
  await tester.tap(find.byKey(const Key('menu_standalone')));
  await tester.pumpAndSettle();
}

/// Unmounts the app and disposes the injected controller (cancels its pending tick timer).
Future<void> disposeApp(WidgetTester tester, SessionController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}
