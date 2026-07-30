// test/unit/main_unit_test.dart - full-app integration of the standalone generate flow.
//
// Drives the real PiaWgApp shell (menu -> standalone -> generate) with the shared generate harness
// (loopback probe listener + cert PEM + FakeHttpClient). Complements standalone_config_screen_test,
// which exercises the screen in isolation.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/pia_service.dart';

import '../app_test_harness.dart';
import '../http_test_helpers.dart';
import '../pia_generate_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell builds with the main menu', (tester) async {
    final c = quietController();
    await pumpApp(tester, c);
    expect(find.text('cfg-pia-wg'), findsOneWidget);
    expect(find.byKey(const Key('menu_standalone')), findsOneWidget);
    await disposeApp(tester, c);
  });

  group('full generate path through the app menu...', () {
    ServerSocket? probeServer;
    StreamSubscription<Socket>? sub;

    // This drives the real PiaWgApp shell, which constructs StandaloneConfigScreen itself (see
    // app_drawer.dart), so there is no seam to inject PiaService(probePort:) through — unlike the
    // other probe tests it must bind the real default port. That is safe because it is now the
    // only file to do so; everything else binds an ephemeral port.
    setUp(() async {
      probeServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, PiaService.defaultProbePort);
      sub = probeServer!.listen((s) => s.destroy());
    });

    tearDown(() async {
      // Null-safe cleanup prevents LateInitializationError
      await sub?.cancel();
      sub = null;
      await probeServer?.close();
      probeServer = null;
    });

    testWidgets('menu -> standalone -> generate -> config shown and logged', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final c = quietController();
      await withFakeHttpClient(() async {
        await pumpAppAtStandalone(tester, c);

        await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
        await tester.pump();

        await tester.tap(find.byKey(const Key('generate_config')));
        await driveUntil(tester, () => find.byKey(const Key('generated_config_text')).evaluate().isNotEmpty);

        expect(find.byKey(const Key('generated_config_text')), findsOneWidget);
        expect(find.text('PUSH CONFIG TO ROUTER...'), findsNothing);

        // The success line is visible on the dedicated log screen.
        expect(c.log.any((e) => e.message.contains('Config generated successfully')), isTrue);
      }, fakeGenerateResponses);

      await disposeApp(tester, c);
    });
  });
}
