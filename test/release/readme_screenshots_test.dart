// test/release/readme_screenshots_test.dart - README screenshots drawn by Flutter, for screens that
// changed or that need invented details: the main menu with NETWORK (ID-458), and NETWORK itself with
// the same invented tunnels as images/02.0-router-slot-management.png.
//
// Skipped unless asked for, since it writes into images/ and needs real fonts (a Mac's):
//
//   flutter test test/release/readme_screenshots_test.dart --update-goldens --dart-define=README_SHOT=true
//
// Drawn at the Pixel 7 Pro's 1440 x 3120 the other README screenshots were taken at. Flutter draws only
// the app, so the phone's status bar and gesture handle are copied from images/02.0's real screenshot
// over the top and bottom edges. Roboto is Flutter's own copy, Android's font; Menlo stands in for
// Android's monospace. The header's version is this build's.
import 'dart:io';

import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show kUpInterfacesCommand;
import 'package:cfg_pia_wg/screens/network_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../watchdog_test_utils.dart';

const _wanted = bool.fromEnvironment('README_SHOT');
final _flutterFonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
const _mono = '/System/Library/Fonts/Menlo.ttc';
const _realShot = 'images/02.0-router-slot-management.png';

/// The phone's own bars in [_realShot], in pixels: the status bar above the header, the gesture handle below.
const double _statusBar = 145, _gestureBar = 80;
const Size _screen = Size(1440, 3120);
// Not the Pixel 7 Pro's default 3.5: the README's screenshots were taken at a smaller display size,
// with text 0.85 of the default's width ("by Exponentially Digital" 284 px against 336).
const double _dpr = 3.0;

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

/// The tunnels in images/02.0, each with an invented exit: every address is from the ranges kept for
/// documentation, and every provider is made up.
const _tunnels = <int, (String, String)>{
  5: ('pia-aus_melbourne', '{"ip":"203.0.113.45","cty":"Melbourne","cn":"Australia","isp":"Example Hosting AU"}'),
  4: ('pia-in', '{"ip":"203.0.113.78","cty":"Mumbai","cn":"India","isp":"Example Hosting IN"}'),
  3: ('pia-sg', '{"ip":"198.51.100.23","cty":"Singapore","cn":"Singapore","isp":"Example Hosting SG"}'),
  2: ('pia-italy', '{"ip":"198.51.100.61","cty":"Milan","cn":"Italy","isp":"Example Hosting IT"}'),
  1: ('pia-uk', '{"ip":"192.0.2.114","cty":"London","cn":"United Kingdom","isp":"Example Hosting UK"}'),
};

RecordingSSHClient _router() => RecordingSSHClient(responder: (cmd) {
      if (cmd == 'nvram get 3rd-party') return 'merlin';
      if (cmd == kUpInterfacesCommand) return _tunnels.keys.map((s) => 'wgc$s').join(' ');
      final desc = RegExp(r'^nvram get wgc(\d)_desc$').firstMatch(cmd);
      if (desc != null) return _tunnels[int.parse(desc.group(1)!)]?.$1 ?? '';
      if (cmd.contains(kTunnelLookupMarker)) {
        return [for (final e in _tunnels.entries) '\n$kTunnelLookupMarker${e.key}\n${e.value.$2}'].join();
      }
      return '';
    });

/// [app], with the real screenshot's status bar and gesture handle laid over its edges.
Widget _phone(Widget app, MemoryImage real) {
  final width = _screen.width / _dpr;
  Widget strip({required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: (top ? _statusBar : _gestureBar) / _dpr,
        child: ClipRect(
          child: OverflowBox(
            alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
            maxHeight: double.infinity,
            child: Image(image: real, width: width, fit: BoxFit.fitWidth),
          ),
        ),
      );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(children: [Positioned.fill(child: app), strip(top: true), strip(top: false)]),
  );
}

void main() {
  final fontsThere = [_mono, '$_flutterFonts/Roboto-Regular.ttf', _realShot].every((p) => File(p).existsSync());

  Future<MemoryImage> setUp(WidgetTester tester) async {
    await _load('Roboto', [for (final w in ['Regular', 'Medium', 'Bold']) '$_flutterFonts/Roboto-$w.ttf']);
    await _load('monospace', [_mono]);
    await _load('MaterialIcons', ['$_flutterFonts/MaterialIcons-Regular.otf']);
    final version = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    PackageInfo.setMockInitialValues(
        appName: 'cfg-pia-wg', packageName: 'cfg_pia_wg', version: version.group(1)!, buildNumber: version.group(2)!, buildSignature: '');
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: _statusBar, bottom: _gestureBar);
    tester.view.viewPadding = const FakeViewPadding(top: _statusBar, bottom: _gestureBar);
    addTearDown(tester.view.reset);
    return MemoryImage(File(_realShot).readAsBytesSync());
  }

  /// Decodes the real screenshot, which a widget test only does outside its fake clock.
  Future<void> settle(WidgetTester tester, MemoryImage real) async {
    await tester.runAsync(() => precacheImage(real, tester.element(find.byType(Stack).first)));
    await tester.pumpAndSettle();
  }

  testWidgets('the main menu, with NETWORK', (tester) async {
    final real = await setUp(tester);
    final c = SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);
    await tester.pumpWidget(_phone(PiaWgApp(controller: c), real));
    await settle(tester, real);
    await expectLater(find.byType(Stack).first, matchesGoldenFile('../../images/00.0-main-menu.png'));
    await tester.pumpWidget(const SizedBox());
  }, skip: !_wanted || !fontsThere);

  testWidgets('NETWORK, with invented addresses', (tester) async {
    final real = await setUp(tester);
    final ssh = _router();
    final c = SessionController(tickInterval: const Duration(hours: 1))
      ..routerIp = '192.168.50.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'x'
      ..routerConnected = true;
    addTearDown(c.dispose);
    await tester.pumpWidget(_phone(PiaWgApp(controller: c), real));
    await settle(tester, real);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.push(MaterialPageRoute<void>(
      settings: RouteSettings(name: AppDestination.network.routeName),
      builder: (_) => NetworkScreen(
        testClientFactory: (_, __, ___) async => ssh,
        phoneLookup: () async =>
            const NetworkFacts(ip: '198.51.100.7', city: 'Sydney', country: 'Australia', provider: 'Example Broadband'),
        addressLookup: () async => '104.18.40.93',
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Stack).first, matchesGoldenFile('../../images/04.5-network.png'));
    await tester.pumpWidget(const SizedBox());
  }, skip: !_wanted || !fontsThere);
}
