import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/main.dart';

void main() {
  testWidgets('log panel initially shows ready', (tester) async {
    await tester.pumpWidget(const PiaWgApp());
    await tester.pumpAndSettle();
    expect(find.text('Ready.'), findsOneWidget);
  });
}
