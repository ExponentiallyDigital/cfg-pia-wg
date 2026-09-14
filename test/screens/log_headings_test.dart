// test/screens/log_headings_test.dart - APP LOG and ROUTER LOG name themselves, as the watchdog log does (ID-033).
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionController _quietController() =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

void main() {
  for (final (menuKey, headingKey, title) in [
    ('menu_log', 'app_log_heading', 'APP LOG'),
    ('menu_router_log', 'router_log_heading', 'ROUTER LOG'),
  ]) {
    testWidgets('$title is headed with its menu name, in teal capitals like the watchdog log', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(menuKey)));
      await tester.pumpAndSettle();

      final heading = tester.widget<Text>(find.byKey(Key(headingKey)));
      expect(heading.data, title);
      expect(heading.style?.color, kHighlight);
      expect(heading.style?.fontSize, 13, reason: 'the size of the watchdog log heading');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
