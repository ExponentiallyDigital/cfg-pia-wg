// test/widgets/router_slots_screen_test.dart - the order the entry checks run in.
//
// This file exists for one property, and it is a property about ORDER rather than about output,
// which is why a comment in the source was not enough to protect it. The screen asks three
// questions before it will show a slot list: is the firmware supported, is the user entitled, and
// are the stock helper binaries present. Swapping the last two compiles, passes every other test,
// and sends a locked user off to install packages on their router for a feature they cannot use.
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/router_slots_screen.dart';
import 'package:cfg_pia_wg/widgets/slot_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

/// In memory: the real store is a file, and a widget test does not finish real file I/O.
class _MemoryRouterPrefs extends RouterPrefs {
  String value = '';

  @override
  Future<String> load() async => value;

  @override
  Future<String> remember(String ip) async => value = ip.trim();

  @override
  Future<void> forget() async => value = '';
}

// A stock router with NEITHER helper binary: every `which` probe comes back empty.
RecordingSSHClient _bareRouter() => RecordingSSHClient(responder: (_) => '');

Widget _wrap(RecordingSSHClient ssh, SessionController c) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: RouterSlotsScreen(
          mode: SlotModalMode.watchdog, // the mode that wants mailsend as well as jq
          testClientFactory: (_, __, ___) async => ssh,
          slotServiceFactory: (cl) => RouterSlotService(cl, onLog: c.onLog),
        ),
      ),
    );

Future<void> _connect(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
  await tester.enterText(find.byType(TextFormField).at(1), 'admin');
  await tester.enterText(find.byType(TextFormField).at(2), 'pw');
  await tester.pump();
  await tester.tap(find.byKey(const Key('connect_router')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(useStock);
  tearDown(() => Entitlement.debugSetUnlocked(null));

  testWidgets('an UNLOCKED user on stock without the binaries is offered the install', (tester) async {
    Entitlement.debugSetUnlocked(true);
    final c = SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);

    await tester.pumpWidget(_wrap(_bareRouter(), c));
    await _connect(tester);

    expect(find.text('Install helper programs?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // ID-201: CON-3 on 2026-09-19 logged in correctly, chose NOT NOW at the install prompt, and the
  // app kept neither the address nor the offer to save the login.
  testWidgets('a proven login is remembered even when the helper install is put off', (tester) async {
    Entitlement.debugSetUnlocked(true);
    final c = SessionController(tickInterval: const Duration(hours: 1), routerPrefs: _MemoryRouterPrefs());
    addTearDown(c.dispose);

    await tester.pumpWidget(_wrap(_bareRouter(), c));
    await _connect(tester);
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpAndSettle();

    expect(c.rememberedRouterIp, '192.168.1.1');

    await tester.pumpWidget(const SizedBox());
  });

  // The same router, the same missing binaries, the only difference being who is asking.
  testWidgets('a LOCKED user is never sent to install anything on their router', (tester) async {
    Entitlement.debugSetUnlocked(false);
    final c = SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);

    await tester.pumpWidget(_wrap(_bareRouter(), c));
    await _connect(tester);

    expect(find.text('Install helper programs?'), findsNothing,
        reason: 'work on their hardware, for a feature they cannot use, in answer to a question they did not ask');
    expect(find.byKey(const Key('slot_row_1')), findsOneWidget, reason: 'they still get to look');

    await tester.pumpWidget(const SizedBox());
  });
}
