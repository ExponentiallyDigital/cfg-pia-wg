// test/screens/standalone_config_screen_test.dart - widget tests for the standalone generate screen.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/session_controller.dart';
import 'package:pia_wireguard_cfga/screens/standalone_config_screen.dart';

import '../http_test_helpers.dart';
import '../pia_generate_harness.dart';

SessionController _controller(List<String> clipWrites) =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (t) async => clipWrites.add(t));

// In the real app AppChrome's Scaffold provides the Material ancestor every route shares; in
// isolation we supply one here.
Widget _host(SessionController c) => SessionScope(
      controller: c,
      child: const MaterialApp(home: Scaffold(body: StandaloneConfigScreen())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GENERATE is disabled until region + username + password are filled', (tester) async {
    final c = _controller([]);
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    ElevatedButton btn() => tester.widget<ElevatedButton>(find.byKey(const Key('generate_config')));
    expect(btn().onPressed, isNull); // grey

    await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
    await tester.pump();
    expect(btn().onPressed, isNotNull); // green

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('PIA credentials pre-fill from the shared session', (tester) async {
    final c = _controller([])
      ..piaUsername = 'puser'
      ..piaPassword = 'ppass';
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'puser'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  group('full generate path', () {
    late ServerSocket probeServer;
    late StreamSubscription<Socket> sub;

    setUp(() async {
      probeServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 1337);
      sub = probeServer.listen((s) => s.destroy());
    });
    tearDown(() async {
      await sub.cancel();
      await probeServer.close();
    });

    testWidgets('generates a config and reveals COPY + SHARE/SAVE (no push button)', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clip = <String>[];
      final c = _controller(clip);
      await withFakeHttpClient(() async {
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
        await tester.pump();

        await tester.tap(find.byKey(const Key('generate_config')));
        await driveUntil(tester, () => find.byKey(const Key('generated_config_text')).evaluate().isNotEmpty);

        expect(find.byKey(const Key('generated_config_text')), findsOneWidget);
        expect(find.text('COPY'), findsOneWidget);
        expect(find.text('SHARE / SAVE'), findsOneWidget);
        expect(find.text('PUSH CONFIG TO ROUTER...'), findsNothing); // dropped (spec 2.1.1)

        await tester.tap(find.text('COPY'));
        await tester.pump();
        expect(clip, isNotEmpty);
        expect(clip.last, contains('[Interface]'));
        expect(find.text('Config copied'), findsOneWidget);
      }, fakeGenerateResponses);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  testWidgets('region picker loads and selects a region', (tester) async {
    final c = _controller([]);
    await withFakeHttpClient(() async {
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.list_alt));
      await tester.pumpAndSettle();
      expect(find.text(kTestRegion), findsOneWidget);

      await tester.tap(find.text(kTestRegion));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, kTestRegion), findsOneWidget);
    }, fakeGenerateResponses);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
