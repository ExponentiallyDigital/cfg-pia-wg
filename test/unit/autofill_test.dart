// test/unit/autofill_test.dart - credentials come from the device's password manager.
//
// Android's autofill framework only sees a field that declares `autofillHints`; Flutter's own docs
// are explicit that "on Android and web, setting this to null will disable autofill for this text
// field". So the hints ARE the feature, and a field that loses them silently stops working with
// KeePass and every other provider - no crash, no test failure, just a manager that never offers.
//
// The grouping matters as much as the hints: this app holds three different logins (PIA, router
// SSH, SMTP), and a provider that cannot tell them apart offers the wrong one for all three.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/widgets/common_fields.dart';

void main() {
  /// The hints declared by the one text field inside [widget].
  List<String>? hintsOf(WidgetTester tester, Widget widget) {
    final field = find.descendant(of: find.byWidget(widget), matching: find.byType(EditableText));
    return tester.widget<EditableText>(field).autofillHints?.toList();
  }

  /// Null and empty both mean "the platform is told nothing about this field"; null is the
  /// stronger of the two on Android, where it disables autofill outright.
  Future<List<String>> pumpAndRead(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AutofillGroup(child: widget))));
    return hintsOf(tester, widget) ?? const <String>[];
  }

  group('credential fields declare autofill hints', () {
    testWidgets('PIA username and password', (tester) async {
      final user = TextEditingController(), pass = TextEditingController();
      addTearDown(user.dispose);
      addTearDown(pass.dispose);

      expect(await pumpAndRead(tester, PiaUsernameField(controller: user)), [AutofillHints.username]);
      expect(await pumpAndRead(tester, PiaPasswordField(controller: pass, visible: false, onToggle: () {})),
          [AutofillHints.password]);
    });

    testWidgets('SSH username and password', (tester) async {
      final user = TextEditingController(), pass = TextEditingController();
      addTearDown(user.dispose);
      addTearDown(pass.dispose);

      expect(await pumpAndRead(tester, SshUsernameField(controller: user)), [AutofillHints.username]);
      expect(await pumpAndRead(tester, SshPasswordField(controller: pass, visible: false, onToggle: () {})),
          [AutofillHints.password]);
    });

    testWidgets('an obscured field without hints stays out of autofill', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      final field = ObscuredField(
          controller: ctrl, label: 'Something private', prefixIcon: Icons.lock, visible: false, onToggle: () {});
      expect(await pumpAndRead(tester, field), isEmpty, reason: 'hints are opt-in, per field');
    });
  });

  // The router IP, the DNS servers and the ping targets are not secrets. A password manager filling
  // them would be wrong, and an entry saved from them would be noise in the user's vault.
  group('fields that are not credentials carry no hints', () {
    testWidgets('router IP and DNS servers', (tester) async {
      final ip = TextEditingController(), dns = TextEditingController();
      addTearDown(ip.dispose);
      addTearDown(dns.dispose);

      expect(await pumpAndRead(tester, RouterIpField(controller: ip)), isEmpty);
      expect(await pumpAndRead(tester, DnsField(controller: dns)), isEmpty);
    });
  });
}
