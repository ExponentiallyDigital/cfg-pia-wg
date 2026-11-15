// test/screens/slot_params_editor_test.dart - WireGuard slot parameter editor (spec 3.3).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/screens/slot_params_editor.dart';
import 'package:cfg_pia_wg/widgets/common_fields.dart';

import '../watchdog_test_utils.dart';

Widget _editor({String desc = ''}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: ctx,
              builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), desc: desc, onSave: (_) async => true),
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

  // Measured 2026-09-13: stock sends a device assigned to a VPN to the slot's FIRST DNS server only.
  testWidgets('on stock the DNS field says assigned devices use only the first server', (tester) async {
    useStock();
    addTearDown(resetRouterFirmware);
    await tester.pumpWidget(_editor());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(kDnsFirstServerNote), findsOneWidget);
  });

  testWidgets('Merlin, where the app assigns no devices, does not', (tester) async {
    useMerlin();
    addTearDown(resetRouterFirmware);
    await tester.pumpWidget(_editor());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(kDnsFirstServerNote), findsNothing);
  });

  testWidgets('SAVE is disabled until every editable text field is filled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async => true),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    OutlinedButton save() => tester.widget<OutlinedButton>(find.byKey(const Key('slot_params_save')));
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('slot_addr')), '10.0.0.2/32');
    await tester.enterText(find.byKey(const Key('slot_desc')), 'aus_melbourne');
    await tester.enterText(find.byKey(const Key('slot_ep_addr')), '203.0.113.5');
    await tester.enterText(find.byKey(const Key('slot_ppub')), 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBQ=');
    await tester.enterText(find.byKey(const Key('slot_priv')), 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCg=');
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
    await tester.enterText(find.byKey(const Key('slot_ppub')), 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBQ=');
    await tester.enterText(find.byKey(const Key('slot_priv')), 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCg=');
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
    expect(saved!['priv'], 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCg=');
    expect(saved!['enforce'], '1');
    expect(saved!['fw'], '1');
    expect(saved!['nat'], '1');
    // Read-only fields are not part of the saved editable set.
    expect(saved!.containsKey('enable'), isFalse);
    expect(saved!.containsKey('rip'), isFalse);
  });

  // ID-611, seen by Andrew on the phone, 2026-11-15: saving wgc1's DNS, the spinner was inside the
  // SAVE button at the bottom of the scrolling card, under the keyboard. The watchdog form had the
  // same fault four times (409 to 435) until its spinner became an overlay outside the scroll view.
  group('saving', () {
    Widget host({required Future<Object?> Function(Map<String, String>) onSave, Future<bool> Function()? confirmSave}) =>
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: ctx,
                  builder: (_) => SlotParamsEditor(
                      slot: 1,
                      initial: {..._initial(), 'addr': '10.0.0.2/32', 'desc': 'aus_melbourne', 'ep_addr': '203.0.113.5'}
                        ..['ppub'] = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBQ='
                        ..['priv'] = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCg=',
                      confirmSave: confirmSave,
                      onSave: onSave),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

    /// Opens the editor with the keyboard up and the DNS field being typed into, then taps SAVE.
    Future<void> typeThenSave(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('slot_dns')));
      await tester.tap(find.byKey(const Key('slot_dns')));
      await tester.enterText(find.byKey(const Key('slot_dns')), '1.1.1.1, 1.0.0.1');
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue, reason: 'the keyboard is up, on the DNS field');
      await tester.ensureVisible(find.byKey(const Key('slot_params_save')));
      await tester.tap(find.byKey(const Key('slot_params_save')));
      await tester.pump();
    }

    testWidgets('drops the keyboard and covers the screen, with the spinner outside the scroll view', (tester) async {
      final done = Completer<Object?>();
      await tester.pumpWidget(host(onSave: (_) => done.future));
      await typeThenSave(tester);

      final overlay = find.byKey(const Key('slot_params_saving_overlay'));
      expect(overlay, findsOneWidget);
      expect(find.ancestor(of: overlay, matching: find.byType(SingleChildScrollView)), findsNothing,
          reason: 'not in the scroll view, so it has no fold to be below');
      expect(tester.getSize(overlay), const Size(400, 800), reason: 'the whole screen');
      expect(tester.testTextInput.hasAnyClients, isFalse, reason: 'no field keeps the keyboard up');

      done.complete(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slot_params_saving_overlay')), findsNothing);
    });

    testWidgets('asks first when there is something to confirm, with no spinner under the question', (tester) async {
      final asked = Completer<bool>();
      var saved = false;
      await tester.pumpWidget(host(onSave: (_) async => saved = true, confirmSave: () => asked.future));
      await typeThenSave(tester);
      expect(find.byKey(const Key('slot_params_saving_overlay')), findsNothing, reason: 'nothing is being saved yet');
      expect(saved, isFalse);

      asked.complete(false);
      await tester.pumpAndSettle();
      expect(saved, isFalse, reason: 'CANCEL saves nothing');
      expect(find.byKey(const Key('slot_params_save')), findsOneWidget, reason: 'and the editor stays open');
    });
  });

  // ID-609: with wgc1's DNS on the address wgc5's watchdog used for its encrypted lookups, those
  // lookups went through wgc1, and the field said nothing.
  testWidgets("the DNS field says when an address is a watchdog's encrypted DNS", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlotParamsEditor(
              slot: 1,
              initial: _initial(),
              watchdogDohServers: const {
                5: {'1.1.1.2'}
              },
              onSave: (_) async => true),
        ),
      ),
    );
    expect(find.textContaining("wgc5's watchdog uses this address"), findsNothing, reason: 'Quad9 is not it');
    await tester.enterText(find.byKey(const Key('slot_dns')), '1.1.1.2, 1.0.0.2');
    await tester.pump();
    expect(find.textContaining("1.1.1.2: wgc5's watchdog uses this address for its own encrypted DNS"), findsOneWidget);
  });

  testWidgets('read-only fields are displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async => true),
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

  // Stock exposes 12 of the 17 fields (ARCHITECTURE.md "Field reference"); the four the app cannot write are
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
                builder: (_) => SlotParamsEditor(slot: 1, initial: _initial(), onSave: (_) async => true),
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
