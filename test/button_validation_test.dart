import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/main.dart';

void main() {
  testWidgets('generate validates empty fields', (tester) async {
    await tester.pumpWidget(const PiaWgApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('GENERATE CONFIG'));
    await tester.pumpAndSettle();

    expect(find.textContaining("password required"), findsOneWidget);
  });
}
