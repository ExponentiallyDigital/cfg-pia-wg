// test/widgets/app_button_test.dart - the house button style (CONTEXT.md "HOUSE STYLE: every button").
//
// The colour of a button is its role, and disabled is darker than the dismiss grey. These are the
// two facts a later "just make this one teal" change would break, so they are pinned here rather
// than rediscovered on a device.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<OutlinedButton> pumpButton(WidgetTester tester, AppButton button) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: button))));
    return tester.widget<OutlinedButton>(find.byKey(const Key('b')));
  }

  Color border(OutlinedButton b) => b.style!.side!.resolve(<WidgetState>{})!.color;

  test('each role has its own colour, and disabled is darker than dismiss', () {
    expect(AppButton.tint(ButtonRole.action, enabled: true), kHighlight);
    expect(AppButton.tint(ButtonRole.destructive, enabled: true), kError);
    expect(AppButton.tint(ButtonRole.dismiss, enabled: true), kMuted);
    for (final role in ButtonRole.values) {
      expect(AppButton.tint(role, enabled: false), kHint, reason: '$role disabled');
    }
    expect(kHint, isNot(kMuted), reason: 'a disabled action must not look like a live CANCEL');
  });

  testWidgets('it is bordered, and the border takes the role colour', (tester) async {
    final b = await pumpButton(
        tester, AppButton(keyValue: 'b', label: 'DELETE', role: ButtonRole.destructive, onPressed: () {}));
    expect(border(b), kError);
    expect(b.style!.backgroundColor?.resolve(<WidgetState>{}), anyOf(isNull, Colors.transparent),
        reason: 'unfilled: only the main menu and the paywall have filled buttons');
  });

  testWidgets('a null onPressed disables it and greys the border', (tester) async {
    final b = await pumpButton(tester, const AppButton(keyValue: 'b', label: 'APPLY', onPressed: null));
    expect(b.onPressed, isNull);
    expect(border(b), kHint);
  });

  testWidgets('busy shows a spinner instead of the label', (tester) async {
    await pumpButton(tester, const AppButton(keyValue: 'b', label: 'SAVE', busy: true, onPressed: null));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('SAVE'), findsNothing);
  });

  testWidgets('fullWidth fills the available width', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 300, child: AppButton(keyValue: 'b', label: 'GO', fullWidth: true, onPressed: () {})),
      ),
    ));
    expect(tester.getSize(find.byKey(const Key('b'))).width, 300);
  });
}
