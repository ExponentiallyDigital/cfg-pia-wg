import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('GENERATE stays disabled while required fields are empty', (tester) async {
    final c = quietController();
    await pumpAppAtStandalone(tester, c);

    final btn = tester.widget<ElevatedButton>(find.byKey(const Key('generate_config')));
    expect(btn.onPressed, isNull);

    await disposeApp(tester, c);
  });
}
