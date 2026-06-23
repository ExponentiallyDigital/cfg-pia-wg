import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('password visibility toggles on the standalone screen', (tester) async {
    final c = quietController();
    await pumpAppAtStandalone(tester, c);

    expect(find.byIcon(Icons.visibility), findsWidgets);
    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await disposeApp(tester, c);
  });
}
