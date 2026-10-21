// test/release/paywall_screenshot_test.dart - the in-app purchase's review screenshot (ID-454): the
// app's own paywall, drawn by Flutter at an iPhone's screen size and written to
// app-store/screenshots/iap-review.png, so nobody has to make a fresh purchase to see it again.
//
// Skipped unless asked for, since it writes into the repo and needs real fonts:
//
//   flutter test test/release/paywall_screenshot_test.dart --update-goldens --dart-define=PAYWALL_SHOT=true
//
// Flutter's tests draw text in a placeholder font, so it loads Consolas, from Windows' font folder,
// for the app's monospace, and Noto Sans for anything that asks for Flutter's default instead. The
// theme is the app's own, buildAppTheme(). The price is the App Store's US$9.99
// (ID-461), as the store would hand it over.
import 'dart:io';

import 'package:cfg_pia_wg/app_shell.dart' show buildAppTheme;
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _wanted = bool.fromEnvironment('PAYWALL_SHOT');
const _sans = 'C:/Windows/Fonts/NotoSans-Regular.ttf';
const _mono = 'C:/Windows/Fonts/consola.ttf';
const _monoBold = 'C:/Windows/Fonts/consolab.ttf';
const _sansBold = 'C:/Windows/Fonts/NotoSans-Bold.ttf';

// Each weight the page uses is its own file: the buttons are bold, and a weight with no file draws
// in the placeholder font.
Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

// The app's theme, with one font named: its button theme gives none, so on a phone the button
// label is the system font, and a test, which has no system font, would draw it as boxes. Noto Sans
// stands in for the iPhone's.
ThemeData _theme() {
  final t = buildAppTheme();
  final style = t.elevatedButtonTheme.style!;
  return t.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: style.copyWith(textStyle: WidgetStatePropertyAll(style.textStyle!.resolve({})!.copyWith(fontFamily: 'Roboto'))),
    ),
  );
}

void main() {
  final fontsThere = [_sans, _sansBold, _mono, _monoBold].every((p) => File(p).existsSync());

  testWidgets('the paywall, as App Review sees it', (tester) async {
    await _load('Roboto', [_sans, _sansBold]);
    await _load('monospace', [_mono, _monoBold]);
    // App Store Connect's largest iPhone size, as the listing's screenshots (1290 x 2796).
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);
    Paywall.offer = PaywallOffer(price: r'US$9.99', purchase: () async => false, restore: () async => false);
    addTearDown(() => Paywall.offer = null);

    await tester.pumpWidget(SessionScope(
      controller: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        builder: (context, child) => Scaffold(body: child),
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(onPressed: () => Paywall.show(ctx, c, pitch: Pitch.create), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../app-store/screenshots/iap-review.png'));
  }, skip: !_wanted || !fontsThere);
}
