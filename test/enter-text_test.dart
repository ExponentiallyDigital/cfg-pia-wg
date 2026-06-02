import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/main.dart';

void main() {
  testWidgets('user can enter credentials', (tester) async {
    await tester.pumpWidget(const PiaWgApp());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Region ID'), 'aus_melbourne');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'PIA username'), 'p123456');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'PIA password'), 'secret');
    expect(find.text('aus_melbourne'), findsOneWidget);
    expect(find.text('p123456'), findsOneWidget);
  });
}
