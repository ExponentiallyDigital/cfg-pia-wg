import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('region browse button is tappable on the standalone screen', (tester) async {
    final c = quietController();
    await pumpAppAtStandalone(tester, c);

    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();

    await disposeApp(tester, c);
  });
}
