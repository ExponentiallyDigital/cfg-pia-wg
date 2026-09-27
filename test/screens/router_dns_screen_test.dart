// test/screens/router_dns_screen_test.dart - the two SETTINGS windows on the router's name lookups (ID-194).
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/device_assignment.dart' show kDeviceSourcesCommand;
import 'package:cfg_pia_wg/screens/router_dns_screen.dart';
import 'package:cfg_pia_wg/screens/settings_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart' show ScreenHeading;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../router_dns_fixtures.dart';
import '../watchdog_test_utils.dart';

/// A router answering each command the two windows send with the captured output.
String _router(String cmd) {
  if (cmd.contains('pidof')) return kFactsFixture;
  if (cmd.contains('@@FILE')) return kFilesFixture;
  if (cmd.contains('nslookup')) return '@@CHECK a\n$kNslookupOkFixture\n@@CHECK b\n$kNslookupOkFixture';
  if (cmd.contains('@@RESOLV')) return kRoutingFixture;
  if (cmd == kDeviceSourcesCommand) return '';
  return '';
}

SessionController _connected({List<String>? copied}) => SessionController(
      tickInterval: const Duration(hours: 1),
      clipboardWriter: (t) async => copied?.add(t),
    )
      ..routerIp = '192.168.1.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
      ..routerConnected = true;

Future<void> _pumpSettings(WidgetTester tester, SessionController c, {String Function(String)? router}) async {
  addTearDown(c.dispose);
  // SessionScope above the navigator, as production has it, so the window SETTINGS pushes can see it.
  await tester.pumpWidget(SessionScope(
    controller: c,
    child: MaterialApp(
      home: Scaffold(
        body: SettingsScreen(
            testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: router ?? _router)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Selects everything in the open window with Ctrl+A, copies it with Ctrl+C, and returns what reached
/// the clipboard. [inside] is a piece of text in the selectable area, to give it the keyboard.
Future<String?> _selectAllAndCopy(WidgetTester tester, String inside) async {
  String? clipboard;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  await tester.tap(find.textContaining(inside).first);
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pumpAndSettle();
  return clipboard;
}

void main() {
  group('SETTINGS', () {
    testWidgets('the two new buttons follow MAX ACTIVE VPNS, teal, with icons used nowhere else', (tester) async {
      await _pumpSettings(tester, _connected());
      final max = tester.getTopLeft(find.byKey(const Key('settings_max_vpns'))).dy;
      final resolver = tester.getTopLeft(find.byKey(const Key('settings_resolver_status'))).dy;
      final routing = tester.getTopLeft(find.byKey(const Key('settings_dns_routing'))).dy;
      expect(max < resolver && resolver < routing, isTrue);
      expect(find.byIcon(Icons.troubleshoot_outlined), findsOneWidget);
      expect(find.byIcon(Icons.alt_route_outlined), findsOneWidget);
      final label = tester.widget<Text>(find.text('ROUTER RESOLVER STATUS'));
      expect(label.style?.color, kHighlight);
    });
  });

  group('ROUTER RESOLVER STATUS', () {
    testWidgets('a teal heading, the live check with every address, and the files', (tester) async {
      await _pumpSettings(tester, _connected());
      await _open(tester, 'settings_resolver_status');

      expect(tester.widget<ScreenHeading>(find.byKey(const Key('resolver_heading'))).colour, kHighlight);
      expect(find.text('OK'), findsNWidgets(2));
      expect(find.textContaining('2606:4700:10::6814:179a'), findsNWidgets(2));
      expect(find.textContaining('/etc/stubby/stubby.yml'), findsOneWidget);
      expect(find.textContaining("Lists every reserved device's MAC and address: review before sharing."), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget, reason: 'every word can be selected and copied');
    });

    // Found 2026-09-27: a selection across the window joined every piece of text with nothing between,
    // "dnsmasqOK172.66.147.243" and "179arunning". COPY was fine; selecting by hand was not.
    testWidgets('selecting all and copying gives separate lines, not one run', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pumpSettings(tester, _connected());
      await _open(tester, 'settings_resolver_status');

      // Inside the selectable area, to give it the keyboard.
      await tester.tap(find.text('dnsmasq '));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(clipboard, isNotNull, reason: 'select all and copy reached the clipboard');
      expect(clipboard, contains('dnsmasq OK 172.66.147.243\n104.20.23.154'));
      expect(clipboard, contains('2606:4700:10::6814:179a\nrunning · 40 ms'));
      expect(clipboard, isNot(contains('179arunning')));
      expect(clipboard, contains('/etc/hosts written 12:10'));
    });

    testWidgets('COPY copies the whole window as text', (tester) async {
      final copied = <String>[];
      await _pumpSettings(tester, _connected(copied: copied));
      await _open(tester, 'settings_resolver_status');
      await tester.tap(find.byKey(const Key('resolver_copy')));
      await tester.pumpAndSettle();

      expect(copied.single, startsWith('ROUTER RESOLVER STATUS'));
      expect(copied.single, contains('nameserver 127.0.1.1'));
    });

    testWidgets('a router that cannot be read says so, rather than showing an empty window', (tester) async {
      await _pumpSettings(tester, _connected(), router: (_) => throw Exception('connection reset'));
      await _open(tester, 'settings_resolver_status');

      expect(find.textContaining('connection reset'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('resolver_copy'))).onPressed, isNull,
          reason: 'nothing read, nothing to copy');
    });
  });

  group('ROUTER DNS ROUTING', () {
    testWidgets('a selection copies each line with its tags, separated', (tester) async {
      await _pumpSettings(tester, _connected());
      await _open(tester, 'settings_dns_routing');
      final copied = await _selectAllAndCopy(tester, 'Only pinned devices');

      expect(copied, contains('Internet, encrypted (DoT)'));
      expect(copied, contains('wgc1:pia-aus_perth → 9.9.9.9\n'));
      expect(copied, isNot(contains('Internetencrypted')));
    });

    testWidgets('the answer first, then each lookup with where it goes and whether it is encrypted', (tester) async {
      await _pumpSettings(tester, _connected());
      await _open(tester, 'settings_dns_routing');

      expect(find.textContaining("Only pinned devices' lookups go through a tunnel."), findsOneWidget);
      expect(find.text('encrypted to PIA'), findsOneWidget);
      expect(find.text('not encrypted'), findsNWidgets(2), reason: "the router's own two DNS servers");
      expect(find.text('encrypted (DoH)'), findsNWidgets(4), reason: 'the four watchdogs');
      expect(find.text('not configured'), findsOneWidget, reason: 'wgc4');
    });
  });

  test('the two windows are named after their buttons', () {
    expect(DnsReportScreen.resolver(client: RecordingSSHClient(responder: (_) => '')).title, 'ROUTER RESOLVER STATUS');
    expect(DnsReportScreen.routing(client: RecordingSSHClient(responder: (_) => '')).title, 'ROUTER DNS ROUTING');
  });
}
