import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pia_wireguard_cfga/main.dart';

void main() {
  testWidgets('region button is tappable', (tester) async {
    await tester.pumpWidget(const PiaWgApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
  });
}
