// test/app_shell_inactivity_test.dart - global 10-minute idle wipe + countdown (spec §3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/app_shell.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';

void main() {
  // The timer-expiry logic itself (fires the callback + wipes) is unit-tested in
  // session_controller_test using real time. Here we verify the SHELL wiring: when the idle
  // timeout's wipe + redirect callback run, credentials are cleared and we return to the menu.
  // (A fake-clock pump can't drive the controller's DateTime.now()-based deadline.)
  testWidgets('idle wipe + redirect callback returns to the main menu and clears credentials', (tester) async {
    final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_standalone')));
    await tester.pumpAndSettle();
    c.piaUsername = 'p1234567';
    c.piaPassword = 'secret';

    await c.wipeAll(reason: '10 minutes of inactivity');
    c.onInactivityExpire?.call(); // shell-installed redirect
    await tester.pumpAndSettle();

    expect(c.piaUsername, isEmpty);
    expect(c.piaPassword, isEmpty);
    expect(c.log.any((e) => e.message.contains('inactivity')), isTrue);
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget); // back at the menu

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('countdown is shown on a screen and hidden while a modal is open', (tester) async {
    final c = SessionController(
      inactivityTimeout: const Duration(minutes: 10),
      tickInterval: const Duration(milliseconds: 200),
      clipboardWriter: (_) async {},
    );
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pump(const Duration(milliseconds: 300)); // one tick populates the countdown

    expect(find.byKey(const Key('inactivity_countdown')), findsOneWidget);

    // Simulate a modal opening: the countdown hides.
    c.enterModal();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('inactivity_countdown')), findsNothing);

    c.exitModal();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('inactivity_countdown')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
