// test/screens/slot_params_editor_test.dart - WireGuard slot parameter editor (spec 3.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/screens/slot_params_editor.dart';

import '../watchdog_test_utils.dart';

Widget _editor({String desc = ''}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: ctx,
              builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), desc: desc, onSave: (_) async {}),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

// initial values with addr/desc/ep_addr/ppub/priv blank (no defaults) so SAVE starts disabled.
Map<String, String> _initial() => {
      'addr': '',
      'alive': '25',
      'desc': '',
      'dns': '9.9.9.9, 149.112.112.112',
      'enable': '1',
      'enforce': '1',
      'ep_addr': '',
      'ep_addr_r': '203.0.113.9',
      'ep_port': '1337',
      'fw': '0',
      'mtu': '1420',
      'nat': '1',
      'ppub': '',
      'priv': '',
      'psk': '',
      'rip': '198.51.100.7',
      'aips': '0.0.0.0/0',
    };

void main() {
  // Reported from a device: the keyboard covered the editor. The dialog must fit the height the
  // keyboard leaves and scroll inside it, never overflow.
  testWidgets('fits above the keyboard and scrolls instead of overflowing', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_editor(desc: 'aus_melbourne'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow');
    const keyboardTop = 800.0 - 500.0;
    // The card itself, not find.byType(Dialog) - that measures the full-screen padding wrapper.
    expect(tester.getRect(find.byType(SingleChildScrollView)).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(find.text('EDIT wgc1:aus_melbourne')).bottom, lessThanOrEqualTo(keyboardTop));
  });

  testWidgets('SAVE is disabled until every editable text field is filled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async {}),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    ElevatedButton save() => tester.widget<ElevatedButton>(find.byKey(const Key('slot_params_save')));
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('slot_addr')), '10.0.0.2/32');
    await tester.enterText(find.byKey(const Key('slot_desc')), 'aus_melbourne');
    await tester.enterText(find.byKey(const Key('slot_ep_addr')), '203.0.113.5');
    await tester.enterText(find.byKey(const Key('slot_ppub')), 'pub==');
    await tester.enterText(find.byKey(const Key('slot_priv')), 'priv==');
    await tester.pump();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('SAVE returns the editable params including the boolean toggles', (tester) async {
    Map<String, String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (p) async => saved = p),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('slot_addr')), '10.0.0.2/32');
    await tester.enterText(find.byKey(const Key('slot_desc')), 'aus_melbourne');
    await tester.enterText(find.byKey(const Key('slot_ep_addr')), '203.0.113.5');
    await tester.enterText(find.byKey(const Key('slot_ppub')), 'pub==');
    await tester.enterText(find.byKey(const Key('slot_priv')), 'priv==');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('slot_fw')));
    await tester.tap(find.byKey(const Key('slot_fw'))); // flip fw 0 -> 1
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('slot_params_save')));
    await tester.tap(find.byKey(const Key('slot_params_save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['addr'], '10.0.0.2/32');
    expect(saved!['desc'], 'aus_melbourne');
    expect(saved!['priv'], 'priv==');
    expect(saved!['enforce'], '1');
    expect(saved!['fw'], '1');
    expect(saved!['nat'], '1');
    // Read-only fields are not part of the saved editable set.
    expect(saved!.containsKey('enable'), isFalse);
    expect(saved!.containsKey('rip'), isFalse);
  });

  testWidgets('read-only fields are displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async {}),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('198.51.100.7'), findsOneWidget); // rip
    expect(find.text('203.0.113.9'), findsOneWidget); // ep_addr_r
    expect(find.text('YES'), findsOneWidget); // Enabled (enable == '1')
  });

  // The heading names the VPN, not just the slot, so the user can see what they are editing.
  group('heading', () {
    testWidgets('shows the slot and its description', (tester) async {
      await tester.pumpWidget(_editor(desc: 'pia-aus_melbourne'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT wgc1:pia-aus_melbourne'), findsOneWidget);
    });

    testWidgets('falls back to the bare slot when there is no description', (tester) async {
      await tester.pumpWidget(_editor());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT wgc1'), findsOneWidget);
    });
  });

  // Stock exposes 12 of the 17 fields (ARCHITECTURE.md 2.3.1); the four the app cannot write are
  // hidden rather than shown as controls that silently do nothing.
  testWidgets('the Merlin-only fields are hidden on stock', (tester) async {
    useStock();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async {}),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('slot_enforce')), findsNothing);
    expect(find.byKey(const Key('slot_fw')), findsNothing);
    expect(find.text('198.51.100.7'), findsNothing); // rip
    expect(find.text('203.0.113.9'), findsNothing); // ep_addr_r

    // Everything stock does have is still there.
    expect(find.byKey(const Key('slot_nat')), findsOneWidget);
    expect(find.byKey(const Key('slot_desc')), findsOneWidget);
    expect(find.text('YES'), findsOneWidget); // Enabled
  });
}
