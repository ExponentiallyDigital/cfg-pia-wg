// test/screens/slot_params_editor_test.dart - WireGuard slot parameter editor (spec 3.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/screens/slot_params_editor.dart';

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
  testWidgets('SAVE is disabled until every editable text field is filled', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));
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
    await tester.pumpWidget(MaterialApp(
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
    ));
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
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('198.51.100.7'), findsOneWidget); // rip
    expect(find.text('203.0.113.9'), findsOneWidget); // ep_addr_r
  });
}
