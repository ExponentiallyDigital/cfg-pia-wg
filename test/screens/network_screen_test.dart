// test/screens/network_screen_test.dart - NETWORK (ID-458): looked up as it opens and on REFRESH, the
// device's row with or without a router, a row for each tunnel that is up against a fake router, and the
// footer that names the source and opens its page.
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show kUpInterfacesCommand;
import 'package:cfg_pia_wg/screens/network_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _phone = NetworkFacts(ip: '198.51.100.7', country: 'Australia', city: 'Sydney', provider: 'Home ISP');
const _reply = '{"ip":"203.0.113.9","cn":"Australia","cty":"Melbourne","isp":"PIA Exit"}';

/// A router with wgc5 up as "Melbourne, Australia", answering the lookup through it with [tunnel].
RecordingSSHClient _router({String firmwareTag = 'merlin', String tunnel = _reply, String up = 'wgc5'}) =>
    RecordingSSHClient(responder: (cmd) {
      if (cmd == 'nvram get 3rd-party') return firmwareTag;
      if (cmd == 'nvram get wgc5_desc') return 'Melbourne, Australia';
      if (cmd == kUpInterfacesCommand) return up;
      if (cmd.contains(kTunnelLookupMarker)) return '\n${kTunnelLookupMarker}5\n$tunnel\n';
      return '';
    });

void main() {
  tearDown(resetRouterFirmware);

  Future<({SessionController c, List<int> phoneCalls, List<Uri> opened})> pump(
    WidgetTester tester, {
    RecordingSSHClient? ssh,
    Future<NetworkFacts> Function()? phone,
  }) async {
    final calls = <int>[];
    final opened = <Uri>[];
    final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});
    if (ssh != null) {
      c
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
    }
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SessionScope(
        controller: c,
        child: Scaffold(
          body: NetworkScreen(
            testClientFactory: (_, __, ___) async => ssh ?? RecordingSSHClient(),
            phoneLookup: () async {
              calls.add(1);
              return phone == null ? _phone : await phone();
            },
            addressLookup: () async => '104.18.40.93',
            openUrl: (url) async => opened.add(url),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (c: c, phoneCalls: calls, opened: opened);
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text))).map((t) => t.data ?? t.textSpan!.toPlainText()).join('\n');

  // Andrew, 2026-10-25: no text above the results, a lookup as the screen opens, REFRESH and HOME below.
  testWidgets('looks up as it opens, with nothing above the results but the heading', (tester) async {
    final ssh = _router();
    final r = await pump(tester, ssh: ssh);
    expect(r.phoneCalls, [1]);
    expect(ssh.commands.where((c) => c.contains(kTunnelLookupMarker)), hasLength(1));
    final heading = tester.getRect(find.byKey(const Key('network_heading')));
    final device = tester.getRect(find.byKey(const Key('network_phone')));
    expect(device.top - heading.bottom, lessThan(30), reason: 'the device card straight under the heading');
    expect(find.textContaining('LOOK UP'), findsNothing);
    expect(find.byKey(const Key('screen_close')), findsNothing, reason: "REFRESH and HOME, not the scaffold's HOME");
    expect(find.byKey(const Key('network_refresh')), findsOneWidget);
    expect(find.byKey(const Key('network_home')), findsOneWidget);
  });

  testWidgets('REFRESH looks up again, the device and the tunnels', (tester) async {
    final ssh = _router();
    final r = await pump(tester, ssh: ssh);
    await tester.tap(find.byKey(const Key('network_refresh')));
    await tester.pumpAndSettle();
    expect(r.phoneCalls, [1, 1]);
    expect(ssh.commands.where((c) => c.contains(kTunnelLookupMarker)), hasLength(2));
  });

  testWidgets('without a router: the device\'s row, and the tunnels offered by a login', (tester) async {
    await pump(tester);
    final row = textOf(tester, const Key('network_phone'));
    expect(row, contains('This device'));
    expect(row, contains('198.51.100.7'));
    expect(row, contains('Sydney, Australia'));
    expect(row, contains('Home ISP'));
    expect(find.textContaining('login to router for tunnel details', findRichText: true), findsOneWidget);
  });

  testWidgets('the whole footer line names PIA and opens its What is my IP page', (tester) async {
    final r = await pump(tester);
    expect(textOf(tester, const Key('network_source')), 'Address data from PIA.');
    await tester.ensureVisible(find.byKey(const Key('network_source')));
    await tester.tap(find.byKey(const Key('network_source')));
    await tester.pumpAndSettle();
    expect(r.opened, [Uri.parse('https://www.privateinternetaccess.com/what-is-my-ip')]);
  });

  testWidgets('with a router: a row for each tunnel up, with PIA\'s region beside the place', (tester) async {
    final ssh = _router();
    await pump(tester, ssh: ssh);
    final row = textOf(tester, const Key('network_wgc5'));
    expect(row, contains('wgc5:Melbourne, Australia'));
    expect(row, contains('203.0.113.9'));
    expect(row, contains('Melbourne, Australia'));
    expect(row, contains('PIA Exit'));
    expect(row, contains('PIA region'));
    expect(find.textContaining(kNetworkLoginPrompt, findRichText: true), findsNothing);
    final asked = ssh.commands.singleWhere((c) => c.contains(kTunnelLookupMarker));
    expect(asked, contains('--interface "wgc\$N"'), reason: 'Merlin binds to the tunnel');
    expect(asked, contains('for N in 5;'));
  });

  testWidgets('on stock the route is read back, and a tunnel with no route says so plainly', (tester) async {
    final ssh = _router(firmwareTag: '', tunnel: '@@NOROUTE');
    await pump(tester, ssh: ssh);
    expect(ssh.commands.singleWhere((c) => c.contains(kTunnelLookupMarker)), contains('ip route get'));
    expect(textOf(tester, const Key('network_wgc5')), contains('Not checked: the router has no route through this tunnel right now.'));
  });

  testWidgets('no tunnel up: says so, and asks the router nothing more', (tester) async {
    final ssh = _router(up: '');
    await pump(tester, ssh: ssh);
    expect(find.byKey(const Key('network_no_tunnels')), findsOneWidget);
    expect(ssh.commands.where((c) => c.contains(kTunnelLookupMarker)), isEmpty);
  });

  testWidgets('a device lookup that fails says so, and the tunnels are still shown', (tester) async {
    await pump(tester, ssh: _router(), phone: () async => throw Exception('no network'));
    expect(textOf(tester, const Key('network_phone')), contains('No answer from PIA'));
    expect(find.byKey(const Key('network_wgc5')), findsOneWidget);
  });

  testWidgets('a firmware it does not know: the tunnels say so, and nothing is sent through them', (tester) async {
    final ssh = _router(firmwareTag: 'koolshare');
    await pump(tester, ssh: ssh);
    expect(textOf(tester, const Key('network_tunnels_error')), contains('this router firmware is not supported'));
    expect(ssh.commands.where((c) => c.contains(kTunnelLookupMarker)), isEmpty);
  });
}
