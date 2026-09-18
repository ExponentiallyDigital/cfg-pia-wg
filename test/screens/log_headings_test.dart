// test/screens/log_headings_test.dart - APP LOG and ROUTER LOG name themselves, as the watchdog log
// does (ID-033), each in its own menu colour from the one shared map (ID-112).
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionController _quietController() =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

void main() {
  for (final (menuKey, headingKey, dest) in [
    ('menu_log', 'app_log_heading', AppDestination.log),
    ('menu_router_log', 'router_log_heading', AppDestination.routerLog),
  ]) {
    testWidgets('${dest.title} is headed with its menu name, in its menu colour', (tester) async {
      final c = _quietController();
      await tester.pumpWidget(PiaWgApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(menuKey)));
      await tester.pumpAndSettle();

      final heading = tester.widget<ScreenHeading>(find.byKey(Key(headingKey)));
      expect(heading.text, dest.title);
      expect(heading.colour, destinationColour(dest), reason: 'the colour the menu row uses');
      expect(heading.colour, isNot(kHighlight), reason: 'both logs have a colour of their own');
      expect(ScreenHeading.style.fontSize, 12, reason: 'the size the configuration headings use');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
