import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('shows the main menu and static header', (tester) async {
    final c = quietController();
    await pumpApp(tester, c);

    expect(find.text('Configure PIA WireGuard'), findsOneWidget); // static header
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);
    expect(find.byKey(const Key('menu_manage_router')), findsOneWidget);
    expect(find.byKey(const Key('menu_watchdog')), findsOneWidget);
    expect(find.byKey(const Key('menu_log')), findsOneWidget);

    await disposeApp(tester, c);
  });
}
