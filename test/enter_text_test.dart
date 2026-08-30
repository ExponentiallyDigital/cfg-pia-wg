import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('user can enter credentials on the standalone screen', (tester) async {
    final c = quietController();
    await pumpAppAtStandalone(tester, c);

    await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), 'aus_melbourne');
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
    await tester.pump();

    expect(find.text('aus_melbourne'), findsOneWidget);
    expect(find.text('p123456'), findsOneWidget);

    await disposeApp(tester, c);
  });
}
