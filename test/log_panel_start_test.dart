import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('log screen initially shows "Ready."', (tester) async {
    final c = quietController();
    await pumpApp(tester, c);

    await tester.tap(find.byKey(const Key('menu_log')));
    await tester.pumpAndSettle();
    expect(find.text('Ready.'), findsOneWidget);

    await disposeApp(tester, c);
  });
}
