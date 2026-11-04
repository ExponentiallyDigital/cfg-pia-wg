// test/release/readme_screenshots_test.dart - every README screenshot of the app, and the store's
// tablet shots, drawn by Flutter with invented details (ID-458, ID-517): every name, address, MAC and
// login made up, and the header's version this build's. A colour change or a new version is a rerun,
// not a session with a phone.
//
// Skipped unless asked for, since it writes into images/ and needs real fonts (a Mac's, or Windows').
// Then the crops, then both stores' sets, which are built from these:
//
//   flutter test test/release/readme_screenshots_test.dart --update-goldens --dart-define=README_SHOT=true
//   python scripts/readme-crops.py
//   python scripts/play-screenshots.py
//   python scripts/app-store-screenshots.py
//
// Phone shots are drawn at the Pixel 7 Pro's 1440 x 3120 the README's first screenshots were taken at,
// tablet ones at play-store/screenshots/tablet-source/'s 1600 x 2560. Flutter draws only the app, so the
// device's status bar and gesture handle are copied from a real screenshot over the top and bottom
// edges. Roboto is Flutter's own copy, Android's font; Menlo on a Mac, DejaVu Sans Mono on Windows,
// stands in for Android's monospace. The README's crops of a single dialog that no colour reaches (the
// region list, the PIA login, the email settings, the reboot countdown) are left as they were taken.
import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/build_info_service.dart' show buildInfoChannel;
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/firmware.dart' show appVersionLabel, kStockJqPath;
import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show RouterSlots, SlotInfo, kUpInterfacesCommand;
import 'package:cfg_pia_wg/screens/about_screen.dart';
import 'package:cfg_pia_wg/screens/log_screen.dart';
import 'package:cfg_pia_wg/screens/network_screen.dart';
import 'package:cfg_pia_wg/screens/router_log_screen.dart';
import 'package:cfg_pia_wg/screens/settings_screen.dart';
import 'package:cfg_pia_wg/screens/standalone_config_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_button.dart';
import 'package:cfg_pia_wg/widgets/device_assignment_screen.dart';
import 'package:cfg_pia_wg/widgets/slot_text.dart';
import 'package:cfg_pia_wg/widgets/slot_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../router_dns_fixtures.dart';
import '../watchdog_test_utils.dart';

const _wanted = bool.fromEnvironment('README_SHOT');
final _flutterFonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
// Menlo on a Mac; DejaVu Sans Mono on Windows, the nearest there to Android's monospace (ID-517).
final _mono = Platform.isWindows ? 'C:/Windows/Fonts/DejaVuSansMono.ttf' : '/System/Library/Fonts/Menlo.ttc';
var _realShot = 'images/02.0-router-slot-management.png';

/// The phone's own bars in [_realShot], in pixels: the status bar above the header, the gesture handle below.
double _statusBar = 145, _gestureBar = 80;
Size _screen = const Size(1440, 3120);
// Not the Pixel 7 Pro's default 3.5: the README's screenshots were taken at a smaller display size,
// with text 0.85 of the default's width ("by Exponentially Digital" 284 px against 336).
double _dpr = 3.0;

/// The 10-inch tablet the store's tablet shots were taken on (play-store/screenshots/tablet-source/),
/// for the rest of the test that calls it: 1600 x 2560 at 2.0, its own status bar and gesture handle.
void _usePhone() {
  _realShot = 'images/02.0-router-slot-management.png';
  _statusBar = 145;
  _gestureBar = 80;
  _screen = const Size(1440, 3120);
  _dpr = 3.0;
}

void _useTablet() {
  _realShot = 'play-store/screenshots/tablet-source/05.png';
  _statusBar = 60;
  _gestureBar = 80;
  _screen = const Size(1600, 2560);
  _dpr = 2.0;
}

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
      if (cmd == 'nvram get 3rd-party') return ''; // stock, as every README screenshot is
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
    // Text with a size but no family falls back to the test's own font, which draws blocks; on a
    // phone it is the system font, which Roboto is on Android (ID-517).
    for (final family in ['FlutterTest', 'Ahem']) {
      await _load(family, [for (final w in ['Regular', 'Medium', 'Bold']) '$_flutterFonts/Roboto-$w.ttf']);
    }
    await _load('monospace', [_mono]);
    await _load('MaterialIcons', ['$_flutterFonts/MaterialIcons-Regular.otf']);
    final version = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    PackageInfo.setMockInitialValues(
        appName: 'cfg-pia-wg', packageName: 'cfg_pia_wg', version: version.group(1)!, buildNumber: version.group(2)!, buildSignature: '');
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = FakeViewPadding(top: _statusBar, bottom: _gestureBar);
    tester.view.viewPadding = FakeViewPadding(top: _statusBar, bottom: _gestureBar);
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
    useStock();
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

  // ── ID-517: the rest of the README's screens, redrawn for the new colours and this build's version ──

  /// [screen] pushed over the app, as the menu would push it, then drawn to images/[name].
  Future<void> shoot(WidgetTester tester, String name, Widget screen,
      {SessionController? controller, String? route, Future<void> Function()? then}) async {
    final real = await setUp(tester);
    final c = controller ?? SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);
    await tester.pumpWidget(_phone(PiaWgApp(controller: c), real));
    await settle(tester, real);
    tester.state<NavigatorState>(find.byType(Navigator).last).push(MaterialPageRoute<void>(
          settings: RouteSettings(name: route),
          builder: (_) => screen,
        ));
    await tester.pumpAndSettle();
    if (then != null) await then();
    await expectLater(find.byType(Stack).first, matchesGoldenFile(name.contains('/') ? '../../$name' : '../../images/$name'));
    await tester.pumpWidget(const SizedBox());
  }

  /// The five tunnels of images/02.0, all up; wgc5 and wgc1 with a watchdog and email alerting.
  RouterSlots slots() => RouterSlots(
        slots: {
          for (final e in _tunnels.entries)
            e.key: SlotInfo(
              index: e.key,
              desc: e.value.$1,
              enabled: true,
              killSwitch: false,
              watchdogActive: e.key == 5 || e.key == 1,
              watchdogConfigured: e.key == 5 || e.key == 1,
              emailAlerting: e.key == 5 || e.key == 1,
            ),
        },
        activeSlots: _tunnels.keys.toSet(),
        answeringSlots: _tunnels.keys.toSet(),
        routerDotServers: const {},
        isMerlin: false, // stock, as every README screenshot is
      );

  SlotModal slotScreen(SlotModalMode mode, SessionController c) => SlotModal(
        mode: mode,
        controller: c,
        connect: () async => _router(),
        initialSlots: slots(),
        piaService: PiaService(),
        quietRefreshInterval: null,
      );

  // DEVICES (images/04.x): wgc5 and wgc1 up with watchdogs, wgc3 stopped; every name, address and MAC invented.
  const devTunnels = {5: ('pia-aus_melbourne', true), 1: ('pia-nz', true), 3: ('pia-au_brisbane-pf', false)};
  // name, ip, mac, slot (0 Internet, null the default), online
  const devices = [
    ('GamesConsole', '192.168.1.30', '00:1B:44:9C:5E:71', 0, true),
    ('KitchenTablet', '192.168.1.64', '00:3D:A2:18:4F:C0', 1, true),
    ('Laptop-Study', '192.168.1.20', '00:5E:77:B3:21:8D', 5, true),
    ('RoboVacuum', '192.168.1.87', '00:2C:90:47:D6:33', null, true),
    ('TABLET', '192.168.1.66', '00:4C:8E:21:7A:09', 1, true),
    ('TV-Lounge', '192.168.1.112', '00:9F:6A:D4:0B:57', 5, true),
    ('GuestPhone-5G', '192.168.1.99', 'EE:4A:31:D8:6C:92', null, false),
  ];
  const sep = '@@CFGPIAWG@@';
  RecordingSSHClient devRouter() {
    final clientlist = [
      for (final e in devTunnels.entries)
        '${e.value.$1}>WireGuard>${e.key}>>password>${e.value.$2 ? 1 : 0}>${10 - e.key}>>>0>0>cfg-pia-wg'
    ].join('<');
    final policy = [
      for (final d in devices)
        if (d.$4 != null) '1>${d.$2}>>${d.$4 == 0 ? 0 : 10 - d.$4!}>'
    ].join('<');
    final reserved = [for (final d in devices) '<${d.$3}>${d.$2}>>${d.$1}'].join();
    final inventory = '{${[for (final d in devices) '"${d.$3}":{"name":"${d.$1}","online":${d.$5 ? 1 : 0}}'].join(',')}}';
    final cache = '{"maclist":[${[for (final d in devices) if (d.$5) '"${d.$3}"'].join(',')}],"ClientAPILevel":"5",'
        '${[for (final d in devices) if (d.$5) '"${d.$3}":{"nickName":"${d.$1}","ip":"${d.$2}","isOnline":"1"}'].join(',')}}';
    final up = [for (final e in devTunnels.entries) if (e.value.$2) '3: wgc${e.key}: <POINTOPOINT,NOARP,UP,LOWER_UP>'].join('\n');
    return RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) {
        return ['', clientlist, policy, '5', reserved, '', '<RT-ABCD>192.168.1.1>00:BB:CC:DD:EE:FF>1', inventory, cache, '']
            .join('\n$sep\n');
      }
      if (cmd.contains('latest-handshakes')) {
        return [
          '',
          up,
          '10000',
          for (final m in RegExp(r'wg show wgc(\d) latest-handshakes').allMatches(cmd))
            devTunnels[int.parse(m.group(1)!)]?.$2 == true ? 'peerkey=\t9950' : '',
          '',
        ].join('\n$sep\n');
      }
      if (cmd == 'nvram get vpnc_clientlist') return clientlist;
      if (cmd.contains('ip -o link show up')) return up;
      // A watchdog on wgc5 and wgc1: scheduled, with its script there.
      final wd = RegExp(r'^cru l \| grep -qw watchdog_wgc(\d)').firstMatch(cmd);
      if (wd != null) return wd.group(1) == '5' || wd.group(1) == '1' ? '1' : '0';
      return '';
    });
  }

  // The picker of each device the shots open: TABLET, moved to the stopped wgc3, and KitchenTablet.
  const tabletRow = 'row_00:4C:8E:21:7A:09', kitchenRow = 'row_00:3D:A2:18:4F:C0';

  Future<void> devicesShot(WidgetTester tester, String name, Future<void> Function() steps) async {
    useStock(); // the firmware is global; every README screenshot is of stock
    final ssh = devRouter();
    await shoot(tester, name, DeviceAssignmentScreen(testClientFactory: (_, __, ___) async => ssh),
        route: AppDestination.deviceAssignment.routeName, then: () async {
      // The connect form, unless an earlier shot's session is still there to reuse.
      if (find.byKey(const Key('device_connect')).evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
        await tester.enterText(find.byType(TextFormField).at(1), 'admin');
        await tester.enterText(find.byType(TextFormField).at(2), 'x');
        await tester.pump();
        await tester.tap(find.byKey(const Key('device_connect')));
        await tester.pumpAndSettle();
      }
      await steps();
    });
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('04.0-device-assignment.png', (tester) async {
    await devicesShot(tester, '04.0-device-assignment.png', () async {});
  }, skip: !_wanted || !fontsThere);

  testWidgets('04.01-default-connection.png', (tester) async {
    await devicesShot(tester, '04.01-default-connection.png', () => tapKey(tester, 'default_picker'));
  }, skip: !_wanted || !fontsThere);

  testWidgets('04.02-assign-device.png', (tester) async {
    await devicesShot(tester, '04.02-assign-device.png', () => tapKey(tester, kitchenRow));
  }, skip: !_wanted || !fontsThere);

  testWidgets('04.03-assign-stopped-tunnel.png', (tester) async {
    await devicesShot(tester, '04.03-assign-stopped-tunnel.png', () => tapKey(tester, tabletRow));
  }, skip: !_wanted || !fontsThere);

  testWidgets('04.031-assign-stopped-tunnel.png', (tester) async {
    await devicesShot(tester, '04.031-assign-stopped-tunnel.png', () async {
      await tapKey(tester, tabletRow);
      await tester.tap(find.byKey(const Key('pick_7')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'device_apply');
    });
  }, skip: !_wanted || !fontsThere);

  SessionController connected() => SessionController(tickInterval: const Duration(hours: 1))
    ..routerIp = '192.168.1.1'
    ..sshUsername = 'router-admin'
    ..sshPassword = 'x'
    ..routerConnected = true;

  // ROUTER LOG: images/05.02's own lines, already invented (documentation addresses, made-up names).
  const guardLog = 'Sep 29 21:04:11 dropbear[3112]: Password auth succeeded for router-admin from 192.168.1.20\n'
      'Sep 29 21:04:15 cfg-pia-wg: TABLET: default - wgc5:pia-aus_melbourne -> wgc1:pia-nz reassigned\n'
      'Sep 29 21:04:15 cfg-pia-wg: LAPTOP: Internet -> wgc1:pia-nz reassigned\n'
      'Sep 29 21:04:16 rc_service: service 20417:notify_rc restart_dnsmasq\n'
      'Sep 29 21:04:17 cfg-pia-wg: Fail-closed guard on for TABLET 192.168.1.21 (wgc1)\n'
      'Sep 29 21:04:17 cfg-pia-wg: Fail-closed guard on for LAPTOP 192.168.1.22 (wgc1)\n'
      'Sep 29 21:05:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.194 build 564]\n'
      'Sep 29 21:05:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity\n'
      'Sep 29 21:05:00 cfg-pia-wg: wgc1: Handshake 52s ago\n'
      'Sep 29 21:05:01 cfg-pia-wg: wgc1: Router resolver OK\n'
      'Sep 30 03:40:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.194 build 564]\n'
      'Sep 30 03:40:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity\n'
      'Sep 30 03:40:12 cfg-pia-wg: wgc1: No handshake and both pings failed (8.8.8.8, 1.1.1.1)\n'
      'Sep 30 03:40:13 cfg-pia-wg: wgc1: WAN has internet connectivity\n'
      'Sep 30 03:40:13 cfg-pia-wg: wgc1: Connectivity lost; reconfiguring (attempt #1) [script v0.8.194 build 564]\n'
      'Sep 30 03:40:13 cfg-pia-wg: wgc1: Using cached CA cert\n'
      'Sep 30 03:40:13 cfg-pia-wg: wgc1: Name lookups encrypted via security.cloudflare-dns.com (1.1.1.2)\n'
      'Sep 30 03:40:14 cfg-pia-wg: wgc1: Requesting PIA token for user p123456789\n'
      'Sep 30 03:40:15 cfg-pia-wg: wgc1: PIA token obtained (len=128)\n'
      'Sep 30 03:40:16 cfg-pia-wg: wgc1: Servers: 2 candidates\n'
      'Sep 30 03:40:17 cfg-pia-wg: wgc1: Latency to 192.0.2.51 (auckland404): 31ms\n'
      'Sep 30 03:40:17 cfg-pia-wg: wgc1: Latency to 192.0.2.52 (auckland411): 29ms\n'
      'Sep 30 03:40:19 rc_service: service 20981:notify_rc restart_vpnc\n'
      'Sep 30 03:40:25 cfg-pia-wg: wgc1: Interface wgc1 is up\n'
      'Sep 30 03:40:29 cfg-pia-wg: wgc1: Handshake 2s ago after 4s\n'
      'Sep 30 03:40:29 cfg-pia-wg: wgc1: Reconfig SUCCESS: region pia-nz via 192.0.2.52:1337\n'
      'Sep 30 03:40:33 cfg-pia-wg: wgc1: Alert email sent (SUCCESS)\n'
      'Sep 30 03:45:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.194 build 564]\n'
      'Sep 30 03:45:00 cfg-pia-wg: wgc1: Handshake 31s ago';
  const plainLog = 'Sep 30 07:58:02 kernel: wgc5: renamed from wg0\n'
      'Sep 30 07:58:04 rc_service: service 1903:notify_rc restart_vpnrouting0\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.194 build 564]\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc5: Checking wgc5 pia-aus_melbourne connectivity\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc5: Handshake 14s ago\n'
      'Sep 30 08:00:01 cfg-pia-wg: wgc5: Router resolver OK\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc1: Watchdog started for wgc1 [script v0.8.194 build 564]\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc1: Checking wgc1 pia-nz connectivity\n'
      'Sep 30 08:00:00 cfg-pia-wg: wgc1: Handshake 47s ago\n'
      'Sep 30 08:00:01 cfg-pia-wg: wgc1: Router resolver OK\n'
      'Sep 30 08:02:37 dropbear[4120]: Password auth succeeded for router-admin from 192.168.1.20\n'
      'Sep 30 08:02:41 cfg-pia-wg: Connected from cfg-pia-wg v0.8.194 build 564\n'
      'Sep 30 08:05:00 cfg-pia-wg: wgc5: Watchdog started for wgc5 [script v0.8.194 build 564]\n'
      'Sep 30 08:05:00 cfg-pia-wg: wgc5: Handshake 19s ago';
  RecordingSSHClient logRouter(String body) => RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wc -c')) return '${body.length}\n0';
        if (cmd.contains('tail -c')) return body;
        return '';
      });
  for (final (name, body) in [('05.01-router-log.png', plainLog), ('05.02-router-log-guard.png', guardLog)]) {
    testWidgets(name, (tester) async {
      final ssh = logRouter(body);
      await shoot(tester, name, RouterLogScreen(testClientFactory: (_, __, ___) async => ssh),
          controller: connected(), route: AppDestination.routerLog.routeName);
    }, skip: !_wanted || !fontsThere);
  }

  // SETTINGS and its two DNS windows, answered from the DNS tests' fixtures.
  String dnsRouter(String cmd) {
    if (cmd.contains('pidof')) return kFactsFixture;
    if (cmd.contains('@@FILE')) return kFilesFixture;
    if (cmd.contains('nslookup')) return '@@CHECK a\n$kNslookupOkFixture\n@@CHECK b\n$kNslookupOkFixture';
    if (cmd.contains('@@RESOLV')) return kRoutingFixture;
    return '';
  }

  Future<void> settingsShot(WidgetTester tester, String name, Future<void> Function() steps) async {
    await shoot(tester, name,
        SettingsScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: dnsRouter), testRestore: () async => true),
        controller: connected(), route: AppDestination.settings.routeName, then: steps);
  }

  testWidgets('06.01-settings.png', (tester) async {
    await settingsShot(tester, '06.01-settings.png', () async {});
  }, skip: !_wanted || !fontsThere);
  testWidgets('06.03-router-resolver-status.png', (tester) async {
    await settingsShot(tester, '06.03-router-resolver-status.png', () => tapKey(tester, 'settings_resolver_status'));
  }, skip: !_wanted || !fontsThere);
  testWidgets('06.04-router-resolver-files.png', (tester) async {
    await settingsShot(tester, '06.04-router-resolver-files.png', () async {
      await tapKey(tester, 'settings_resolver_status');
      await tester.scrollUntilVisible(find.textContaining('/etc/dnsmasq.conf').first, 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    });
  }, skip: !_wanted || !fontsThere);
  testWidgets('06.05-router-dns-routing.png', (tester) async {
    await settingsShot(tester, '06.05-router-dns-routing.png', () => tapKey(tester, 'settings_dns_routing'));
  }, skip: !_wanted || !fontsThere);

  testWidgets('06.0-app-log.png', (tester) async {
    final c = connected();
    for (final (m, ok, warn, err) in const [
      ('Connected to the router at 192.168.1.1, stock firmware.', false, false, false),
      ('wgc5:pia-aus_melbourne enabled. Traffic confirmed through the tunnel.', true, false, false),
      ('Watchdog for wgc5:pia-aus_melbourne deployed, checking every 5 minutes.', true, false, false),
      ('wgc1:pia-nz: the PIA server took 4 seconds to answer.', false, true, false),
      ('Devices: TABLET default -> wgc1:pia-nz, LAPTOP Internet -> wgc1:pia-nz.', false, false, false),
      ('Fail-closed guard on for 2 devices on wgc1.', true, false, false),
      ('wgc3:pia-au_brisbane-pf did not come up within 10 seconds, so it was turned off again.', false, false, true),
    ]) {
      c.logEntry(m, isSuccess: ok, isWarning: warn, isError: err);
    }
    await shoot(tester, '06.0-app-log.png', const LogScreen(), controller: c, route: AppDestination.log.routeName);
  }, skip: !_wanted || !fontsThere);

  testWidgets('01.0-standalone-config.png', (tester) async {
    await shoot(tester, '01.0-standalone-config.png', StandaloneConfigScreen(service: PiaService()),
        route: AppDestination.standalone.routeName);
  }, skip: !_wanted || !fontsThere);

  /// What the phone tells ABOUT about this build, as a store build from the tag would.
  void buildInfo(WidgetTester tester) {
    final v = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(buildInfoChannel, (_) async => <String, String>{
          'versionName': v.group(1)!,
          'buildNumber': v.group(2)!,
          'installer': 'Google Play',
          'buildTimestamp': '2026-11-04 09:12:40 UTC',
          'buildType': 'release',
          'commitHash': '0a1b2c3',
          'commitDate': '2026-11-04T19:58:02+11:00',
          'gitBranch': 'v${v.group(1)}',
          'runnerId': '41500000000',
          'cpuAbi': 'arm64-v8a',
          'osVersion': 'Android 17 (API 37)',
          'compileSdk': '36',
          'kotlinVersion': '2.3.20',
        });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(buildInfoChannel, null));
    // What main() sets at start, which ABOUT compares the router's script with.
    final saved = appVersionLabel;
    appVersionLabel = 'v${v.group(1)} build ${v.group(2)}';
    addTearDown(() => appVersionLabel = saved);
  }

  testWidgets('07.01-about.png', (tester) async {
    buildInfo(tester);
    await shoot(tester, '07.01-about.png', const AboutScreen(), route: AppDestination.about.routeName);
  }, skip: !_wanted || !fontsThere);

  testWidgets('99.02-hamburger-menu.png', (tester) async {
    final real = await setUp(tester);
    final c = SessionController(tickInterval: const Duration(hours: 1));
    addTearDown(c.dispose);
    await tester.pumpWidget(_phone(PiaWgApp(controller: c), real));
    await settle(tester, real);
    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(Stack).first, matchesGoldenFile('../../images/99.02-hamburger-menu.png'));
    await tester.pumpWidget(const SizedBox());
  }, skip: !_wanted || !fontsThere);

  // The flows inside MANAGE and WATCHDOG, unlocked so ENABLE, EDIT and CREATE/EDIT open their screens.
  // A crop's rectangle goes to build/readme_crops.json, for scripts/readme-crops.py to cut it as the
  // original was cut.
  // Merged into what is there, so a shot drawn on its own keeps the others' rectangles.
  void cropAround(WidgetTester tester, String name, Finder anchor) {
    final r = tester.getRect(anchor.first);
    final file = File('build/readme_crops.json');
    final crops = file.existsSync() ? Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map) : <String, dynamic>{};
    crops[name] = [r.left * _dpr, r.top * _dpr, r.right * _dpr, r.bottom * _dpr];
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(crops));
  }

  const slotValues = {
    'addr': '10.13.128.2', 'alive': '25', 'dns': '10.0.0.243', 'enable': '1', 'ep_addr': '203.0.113.45',
    'ep_port': '1337', 'mtu': '1420', 'nat': '1', 'aips': '0.0.0.0/0',
    'ppub': 'yzE6GkU0Y1pVbXR0aW1lc3RhbXBpbnZlbnRlZGtleT0=', 'priv': 'aW52ZW50ZWRwcml2YXRla2V5Zm9yc2NyZWVuc2hvdD0=',
  };
  RecordingSSHClient flowRouter() => RecordingSSHClient(responder: (cmd) {
        final key = RegExp(r'^nvram get wgc(\d)_(\w+)$').firstMatch(cmd);
        if (key != null) {
          if (key.group(2) == 'desc') return _tunnels[int.parse(key.group(1)!)]?.$1 ?? '';
          return slotValues[key.group(2)] ?? '';
        }
        if (cmd == "[ -x '$kStockJqPath' ] && echo 1 || echo 0") return '1'; // installed by the app on stock
        // ABOUT's facts: a watchdog script from an older build, so UPDATE WATCHDOG VERSION shows.
        if (cmd.contains('@@CFGPIAWGABOUT@@')) {
          return '/jffs/cfg-pia-wg/watchdog_wgc5.sh:# watchdog_wgc5.sh - auto-generated by cfg-pia-wg v0.8.190 build 560; '
              '*do* *not* edit.\n@@CFGPIAWGABOUT@@\n2026-09-19@@7@@2@@RT-ABCD@@3.0.0.4.388_24385-g3fd7311@@';
        }
        if (cmd.contains('/tmp/watchdog_wgc1.log')) {
          return guardLog.split('\n').where((l) => l.contains('wgc1:')).map((l) => l.replaceFirst(RegExp(r'^(\S+ \S+ \S+) cfg-pia-wg: wgc1: '), r'$1 ')).join('\n');
        }
        if (cmd.contains('watchdog_wgc\$S.sh')) {
          return 'wgc5|1|1|7940|# watchdog_wgc5.sh - auto-generated by cfg-pia-wg v0.8.190 build 560; *do* *not* edit.|'
              '# end of watchdog_wgc5.sh';
        }
        return '';
      });

  SlotModal flowScreen(SlotModalMode mode, SessionController c, RouterSlots initial) => SlotModal(
        mode: mode,
        controller: c,
        connect: () async => flowRouter(),
        initialSlots: initial,
        piaService: PiaService(),
        quietRefreshInterval: null,
      );

  /// images/02.0's tunnels with wgc2 stopped, for ENABLE and a fresh CREATE.
  RouterSlots stopped2() {
    final s = slots();
    return RouterSlots(
      slots: {...s.slots, 2: SlotInfo(index: 2, desc: 'pia-italy', enabled: false, killSwitch: false, watchdogActive: false, watchdogConfigured: false, emailAlerting: false)},
      activeSlots: s.activeSlots.difference({2}),
      answeringSlots: s.answeringSlots.difference({2}),
      routerDotServers: const {},
      isMerlin: false, // stock, as every README screenshot is
    );
  }

  Future<void> flowShot(WidgetTester tester, String name, SlotModalMode mode, RouterSlots initial, Future<void> Function() steps) async {
    useStock();
    Entitlement.debugSetUnlocked(true);
    addTearDown(() => Entitlement.debugSetUnlocked(null));
    final c = SessionController(tickInterval: const Duration(hours: 1));
    await shoot(tester, name, flowScreen(mode, c, initial), controller: c, then: steps);
  }

  const pingShot = '02.04-ping-targets.png', createdShot = '02.03-slot-created.png';
  const updateShot = '07.02-about-update-watchdog.png';

  testWidgets(pingShot, (tester) async {
    await flowShot(tester, pingShot, SlotModalMode.manage, stopped2(), () async {
      await tapKey(tester, 'slot_row_2');
      await tapKey(tester, 'slot_enable');
      cropAround(tester, pingShot, find.text('Connectivity check targets'));
    });
  }, skip: !_wanted || !fontsThere);

  testWidgets(createdShot, (tester) async {
    await flowShot(tester, createdShot, SlotModalMode.manage, stopped2(), () async {
      await tapKey(tester, 'slot_row_2');
      // The message CREATE ends with when the slot's old tunnel was stopped, drawn as the app draws it.
      showDialog<void>(
        context: tester.element(find.byType(SlotModal)),
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          title: const SlotText('Slot created', style: TextStyle(color: kHighlight, fontSize: 15)),
          content: const SlotText(
              'wgc2 has been created. Its old tunnel was stopped, so the slot is disabled. Remember to ENABLE it via '
              'the ENABLE button.',
              style: TextStyle(color: kText, fontSize: 13)),
          actions: [AppButton(label: 'OK', onPressed: () => Navigator.pop(ctx))],
        ),
      );
      await tester.pumpAndSettle();
      cropAround(tester, createdShot, find.text('Slot created'));
    });
  }, skip: !_wanted || !fontsThere);

  testWidgets('02.05-slot-edit.png', (tester) async {
    await flowShot(tester, '02.05-slot-edit.png', SlotModalMode.manage, slots(), () async {
      await tapKey(tester, 'slot_row_5');
      await tapKey(tester, 'slot_edit');
    });
  }, skip: !_wanted || !fontsThere);

  testWidgets('03.01-watchdog-editing.png', (tester) async {
    await flowShot(tester, '03.01-watchdog-editing.png', SlotModalMode.watchdog, slots(), () async {
      await tapKey(tester, 'slot_row_1');
      await tapKey(tester, 'slot_edit');
    });
  }, skip: !_wanted || !fontsThere);

  testWidgets('03.02-watchdog-log.png', (tester) async {
    await flowShot(tester, '03.02-watchdog-log.png', SlotModalMode.watchdog, slots(), () async {
      await tapKey(tester, 'slot_row_1');
      await tapKey(tester, 'slot_view_log');
    });
  }, skip: !_wanted || !fontsThere);

  testWidgets(updateShot, (tester) async {
    useStock();
    buildInfo(tester);
    final ssh = flowRouter();
    await shoot(tester, updateShot, AboutScreen(testClientFactory: (_, __, ___) async => ssh),
        controller: connected(), route: AppDestination.about.routeName, then: () async {
      cropAround(tester, updateShot, find.byKey(const Key('about_heading')));
    });
  }, skip: !_wanted || !fontsThere);

  for (final (name, mode, selected) in [
    ('02.0-router-slot-management.png', SlotModalMode.manage, 5),
    ('03.0-watchdog-configuration.png', SlotModalMode.watchdog, 1),
  ]) {
    testWidgets(name, (tester) async {
      useStock();
      final c = SessionController(tickInterval: const Duration(hours: 1));
      await shoot(tester, name, slotScreen(mode, c), controller: c, then: () async {
        await tester.tap(find.byKey(Key('slot_row_$selected')));
        await tester.pumpAndSettle();
      });
    }, skip: !_wanted || !fontsThere);
  }

  // ── The store's tablet shots (play-store/screenshots/tablet-source/), the same screens at 10 inches ──
  const tablet = 'play-store/screenshots/tablet-source';
  void onTablet() {
    _useTablet();
    addTearDown(_usePhone);
  }

  testWidgets('tablet 01 to 03: DEVICES', (tester) async {
    onTablet();
    await devicesShot(tester, '$tablet/01.png', () async {});
  }, skip: !_wanted || !fontsThere);
  testWidgets('tablet 02: a device picked', (tester) async {
    onTablet();
    await devicesShot(tester, '$tablet/02.png', () => tapKey(tester, kitchenRow));
  }, skip: !_wanted || !fontsThere);
  testWidgets('tablet 03: APPLY to a stopped tunnel', (tester) async {
    onTablet();
    await devicesShot(tester, '$tablet/03.png', () async {
      await tapKey(tester, tabletRow);
      await tester.tap(find.byKey(const Key('pick_7')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'device_apply');
    });
  }, skip: !_wanted || !fontsThere);
  for (final (n, mode, selected) in [('04', SlotModalMode.watchdog, 1), ('05', SlotModalMode.manage, 5)]) {
    testWidgets('tablet $n: the slot list', (tester) async {
      onTablet();
      useStock();
      final c = SessionController(tickInterval: const Duration(hours: 1));
      await shoot(tester, '$tablet/$n.png', slotScreen(mode, c), controller: c, then: () async {
        await tester.tap(find.byKey(Key('slot_row_$selected')));
        await tester.pumpAndSettle();
      });
    }, skip: !_wanted || !fontsThere);
  }
  testWidgets('tablet 06: ROUTER DNS ROUTING', (tester) async {
    onTablet();
    await settingsShot(tester, '$tablet/06.png', () => tapKey(tester, 'settings_dns_routing'));
  }, skip: !_wanted || !fontsThere);
  testWidgets('tablet 07: ROUTER LOG with the guard', (tester) async {
    onTablet();
    final ssh = logRouter(guardLog);
    await shoot(tester, '$tablet/07.png', RouterLogScreen(testClientFactory: (_, __, ___) async => ssh),
        controller: connected(), route: AppDestination.routerLog.routeName);
  }, skip: !_wanted || !fontsThere);
  testWidgets('tablet 08: STANDALONE', (tester) async {
    onTablet();
    await shoot(tester, '$tablet/08.png', StandaloneConfigScreen(service: PiaService()), route: AppDestination.standalone.routeName);
  }, skip: !_wanted || !fontsThere);
}
