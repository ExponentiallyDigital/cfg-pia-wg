// test/main_wipe_timer_test.dart - verifies the session-wipe timer is disabled on "Push to router".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pia_wireguard_cfga/main.dart';
import 'package:pia_wireguard_cfga/pia_service.dart';

class _FakePiaService extends PiaService {
  @override
  Future<String> generateConfig({
    required String region,
    required String username,
    required String password,
    required String dns,
    void Function(String)? onProgress,
  }) async {
    return '[Interface]\n'
        'PrivateKey = x\n'
        'Address = 10.0.0.2/32\n'
        'DNS = 1.1.1.1\n'
        'MTU = 1420\n\n'
        '[Peer]\n'
        'PublicKey = y\n'
        'Endpoint = 1.2.3.4:1337\n'
        'PersistentKeepalive = 25\n'
        'AllowedIPs = 0.0.0.0/0\n';
  }
}

void main() {
  testWidgets('tapping "PUSH CONFIG TO ROUTER" disables the session-wipe timer', (tester) async {
    // Tall surface so the whole screen is laid out without needing to scroll.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: MainScreen(service: _FakePiaService())));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'aus_melbourne');
    await tester.enterText(find.byType(TextFormField).at(1), 'p1234567');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret');
    await tester.pump();

    await tester.tap(find.text('GENERATE CONFIG'));
    await tester.pump(); // resolve the (fake) generateConfig future
    await tester.pump(); // rebuild with the generated config + running wipe timer

    // The wipe countdown is running.
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('PUSH CONFIG TO ROUTER...'), findsOneWidget);

    // Tapping push disables the timer (and opens the router sheet). Safe to settle now.
    await tester.tap(find.text('PUSH CONFIG TO ROUTER...'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    expect(find.text('ROUTER SSH LOGIN'), findsOneWidget);
  });
}
