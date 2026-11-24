// test/screens/network_screen_test.dart - NETWORK (ID-458): looked up as it opens and on REFRESH, the
// device's row with or without a router, a row for each tunnel that is up against a fake router, and the
// footer that names the source and opens its page.
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:cfg_pia_wg/router_facts.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show kUpInterfacesCommand;
import 'package:cfg_pia_wg/screens/network_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/tunnel_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _phone = NetworkFacts(ip: '198.51.100.7', country: 'Australia', city: 'Sydney', provider: 'Home ISP');
const _reply = '{"ip":"203.0.113.9","cn":"Australia","cty":"Melbourne","isp":"PIA Exit"}';

/// A router with wgc5 up as "Melbourne, Australia", answering the lookup through it with [tunnel].
RecordingSSHClient _router({
  String firmwareTag = 'merlin',
  String tunnel = _reply,
  String up = 'wgc5',
  String status = _status,
  String speed = _speedReply,
  String facts = _facts,
  bool factsFail = false,
}) =>
    RecordingSSHClient(responder: (cmd) {
      if (cmd == 'nvram get 3rd-party') return firmwareTag;
      if (cmd == 'nvram get wgc5_desc') return 'Melbourne, Australia';
      if (cmd == kUpInterfacesCommand) return up;
      if (cmd.contains(kTunnelLookupMarker)) return '\n${kTunnelLookupMarker}5\n$tunnel\n';
      if (cmd.contains(kTunnelStatusMarker)) return status;
      if (cmd.contains(kSpeedMarker)) return speed;
      if (cmd == kRouterFactsCommand) {
        if (factsFail) throw Exception('read failed');
        return facts;
      }
      return '';
    });

// Invented addresses; the router's own are never written into a tracked file.
const _facts = 'WAN=203.0.113.9\nDDNSON=1\nDDNS=myhome.example.net\nHOST=router\nDOMAIN=home.example.net\nLAN=192.168.1.1\n';
const _status = '\n${kTunnelStatusMarker}5\nnow 1000000\nhs 999958\nxfer 1200000000 310000000\nep 203.0.113.50:1337\nrb 2\n';
const _speedReply = '@@SPEED wgc5\nL 0.19\nL 0.060\nL 0.070\nL 0.062\nL 0.066\nL 0.072\nD 90000000 9.0\nD 90000000 9.5\nD 90000000 9.2\nD 90000000 9.8\n'
    'U 20000000 4.0\nU 20000000 4.5\nU 20000000 4.2\nU 20000000 4.4\n';

void main() {
  tearDown(resetRouterFirmware);

  Future<({SessionController c, List<int> phoneCalls, List<Uri> opened})> pump(
    WidgetTester tester, {
    RecordingSSHClient? ssh,
    Future<NetworkFacts> Function()? phone,
    String? speedAddress = '104.18.40.93',
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
            testClientFactory: (_, _, _) async => ssh ?? RecordingSSHClient(),
            phoneLookup: () async {
              calls.add(1);
              return phone == null ? _phone : await phone();
            },
            addressLookup: () async => '104.18.40.93',
            speedAddressLookup: () async => speedAddress,
            clock: () => DateTime(2026, 11, 24, 14, 2),
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
    final router = tester.getRect(find.byKey(const Key('network_router')));
    final device = tester.getRect(find.byKey(const Key('network_phone')));
    expect(router.top - heading.bottom, lessThan(30), reason: "the router's box straight under the heading (ID-706)");
    expect(device.top, greaterThanOrEqualTo(router.bottom), reason: '"This device" below it');
    expect(find.textContaining('LOOK UP'), findsNothing);
    expect(find.byKey(const Key('screen_close')), findsNothing, reason: "REFRESH and HOME, not the scaffold's HOME");
    expect(find.byKey(const Key('network_refresh')), findsOneWidget);
    expect(find.byKey(const Key('network_home')), findsOneWidget);
  });

  // ID-706: a box above "This device" with the router's own details.
  testWidgets('the router\'s box shows its WAN address, DDNS name, name, domain and LAN address', (tester) async {
    await pump(tester, ssh: _router());
    final box = textOf(tester, const Key('network_router'));
    expect(box, contains('Router'));
    expect(box, contains('WAN IP: 203.0.113.9'));
    expect(box, contains('DDNS: myhome.example.net'));
    expect(box, contains('Hostname: router'));
    expect(box, contains('Domain name: home.example.net'));
    expect(box, contains('LAN IP: 192.168.1.1'));
  });

  testWidgets('with no DDNS or domain name set those two lines are left out', (tester) async {
    // DDNS off keeps the name it had, which is not shown; the domain is empty.
    await pump(tester, ssh: _router(facts: 'WAN=203.0.113.9\nDDNSON=0\nDDNS=old.example.net\nHOST=router\nDOMAIN=\nLAN=192.168.1.1\n'));
    final box = textOf(tester, const Key('network_router'));
    expect(box, contains('WAN IP: 203.0.113.9'));
    expect(box, contains('Hostname: router'));
    expect(box, contains('LAN IP: 192.168.1.1'));
    expect(box, isNot(contains('DDNS')));
    expect(box, isNot(contains('Domain name')));
  });

  testWidgets('a router read that fails leaves the box out, and the tunnels are still looked up', (tester) async {
    final r = await pump(tester, ssh: _router(factsFail: true));
    expect(find.byKey(const Key('network_router')), findsNothing);
    expect(find.byKey(const Key('network_wgc5')), findsOneWidget);
    expect(r.c.log.any((e) => e.message.contains("router's own details could not be read") && e.isWarning), isTrue);
  });

  testWidgets('not logged in, there is no router box', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('network_router')), findsNothing);
  });

  // ID-708: where the speed test's data comes from, at the foot of the screen.
  testWidgets('the foot says speed test data is from Cloudflare, and opens its page', (tester) async {
    final r = await pump(tester, ssh: _router());
    final line = find.byKey(const Key('network_speed_source'));
    await tester.ensureVisible(line);
    expect(find.text('Speed test data from Cloudflare.'), findsOneWidget);
    await tester.tap(line);
    await tester.pump();
    expect(r.opened.last.toString(), 'https://speed.cloudflare.com');
  });

  testWidgets('no speed test data line when no tunnel can be tested', (tester) async {
    await pump(tester, ssh: _router(up: ''));
    expect(find.byKey(const Key('network_speed_source')), findsNothing);
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

  // ID-600: wg show's handshake, server and data, and the watchdog's restarts, on each tunnel's card.
  testWidgets('a tunnel card shows the handshake, the server, the data and the watchdog restarts', (tester) async {
    await pump(tester, ssh: _router());
    final row = textOf(tester, const Key('network_wgc5'));
    expect(row, contains('Handshake: 42 s ago'));
    expect(row, contains('Server: 203.0.113.50:1337'));
    expect(row, contains('Transferred: 1.2 GB in, 310 MB out'));
    expect(row, contains('Watchdog restarts: 2 since 12am'));
  });

  testWidgets('a status the router could not give leaves its lines out, and the lookup still shows', (tester) async {
    await pump(tester, ssh: _router(status: ''));
    final row = textOf(tester, const Key('network_wgc5'));
    expect(row, isNot(contains('Handshake')));
    expect(row, isNot(contains('Watchdog restarts')));
    expect(row, contains('203.0.113.9'));
  });

  testWidgets('a status read that fails is logged and leaves the lookup alone', (tester) async {
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd == 'nvram get 3rd-party') return 'merlin';
      if (cmd == 'nvram get wgc5_desc') return 'Melbourne, Australia';
      if (cmd == kUpInterfacesCommand) return 'wgc5';
      if (cmd.contains(kTunnelLookupMarker)) return '\n${kTunnelLookupMarker}5\n$_reply\n';
      if (cmd.contains(kTunnelStatusMarker)) throw Exception('wg is not here');
      return '';
    });
    final r = await pump(tester, ssh: ssh);
    expect(textOf(tester, const Key('network_wgc5')), contains('203.0.113.9'));
    expect(r.c.log.any((e) => e.message.contains('status could not be read')), isTrue);
  });

  // ID-604: TEST SPEED confirms first, tests one tunnel, and keeps the figures with the time.
  testWidgets('TEST SPEED asks first, says how much and to whom, and sends nothing when cancelled', (tester) async {
    final ssh = _router();
    await pump(tester, ssh: ssh);
    await tester.ensureVisible(find.byKey(const Key('network_speed_wgc5')));
    await tester.tap(find.byKey(const Key('network_speed_wgc5')));
    await tester.pumpAndSettle();
    expect(find.textContaining('about 2.5 MB for each 1 Mbps', findRichText: true), findsOneWidget);
    expect(find.textContaining('Cloudflare', findRichText: true), findsWidgets);
    expect(find.textContaining('never your home address', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const Key('network_speed_cancel')));
    await tester.pumpAndSettle();
    expect(ssh.commands.where((c) => c.contains(kSpeedMarker)), isEmpty);
    expect(textOf(tester, const Key('network_wgc5')), isNot(contains('Speed')));
  });

  testWidgets('TEST SPEED on Merlin binds to the tunnel and shows Mbps each way with the time', (tester) async {
    final ssh = _router();
    await pump(tester, ssh: ssh);
    await tester.ensureVisible(find.byKey(const Key('network_speed_wgc5')));
    await tester.tap(find.byKey(const Key('network_speed_wgc5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network_speed_confirm')));
    await tester.pumpAndSettle();
    final asked = ssh.commands.singleWhere((c) => c.contains(kSpeedMarker));
    expect(asked, contains('--interface "wgc5"'));
    expect(asked, contains('IP=104.18.40.93'));
    expect(textOf(tester, const Key('network_wgc5')), contains('Speed: 144 Mbps down, 32 Mbps up (14:02)'));
    // ID-703: after the dropped first, 60 70 62 66 72: the median is 66 ms, and the differences 10 8 4 6 give 7 ms.
    expect(textOf(tester, const Key('network_wgc5')), contains('Latency: 66 ms'));
    expect(textOf(tester, const Key('network_wgc5')), contains('Jitter: 7.0 ms'));
  });

  testWidgets('TEST SPEED on stock reads the route back, and says plainly when there is none', (tester) async {
    final ssh = _router(firmwareTag: '', speed: '@@SPEED wgc5\n@@NOROUTE\n');
    await pump(tester, ssh: ssh);
    await tester.ensureVisible(find.byKey(const Key('network_speed_wgc5')));
    await tester.tap(find.byKey(const Key('network_speed_wgc5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network_speed_confirm')));
    await tester.pumpAndSettle();
    expect(ssh.commands.singleWhere((c) => c.contains(kSpeedMarker)), contains('ip route get'));
    expect(textOf(tester, const Key('network_wgc5')), contains(kSpeedNoRoute));
    expect(textOf(tester, const Key('network_wgc5')), isNot(contains('Mbps')));
  });

  // ID-705: Cloudflare answered wgc5 with HTTP 429 and Retry-After: 1967, and the card said only "no figure".
  testWidgets('TEST SPEED refused by Cloudflare shows its status and how long to wait, on the card and in the log', (tester) async {
    final ssh = _router(speed: '@@SPEED wgc5\nH 429\nRA 1967\n');
    final r = await pump(tester, ssh: ssh);
    await tester.ensureVisible(find.byKey(const Key('network_speed_wgc5')));
    await tester.tap(find.byKey(const Key('network_speed_wgc5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network_speed_confirm')));
    await tester.pumpAndSettle();
    const message = '429, test limit exceeded, try again after about 33 minutes';
    expect(textOf(tester, const Key('network_wgc5')), contains(message));
    expect(textOf(tester, const Key('network_wgc5')), isNot(contains(kSpeedFailed)));
    expect(r.c.log.any((e) => e.message.contains('the speed test of wgc5 was refused by Cloudflare: $message') && e.isWarning), isTrue);
  });

  testWidgets('TEST SPEED with no address for the server tests nothing and says so', (tester) async {
    final ssh = _router();
    final r = await pump(tester, ssh: ssh, speedAddress: null);
    await tester.ensureVisible(find.byKey(const Key('network_speed_wgc5')));
    await tester.tap(find.byKey(const Key('network_speed_wgc5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network_speed_confirm')));
    await tester.pumpAndSettle();
    expect(ssh.commands.where((c) => c.contains(kSpeedMarker)), isEmpty);
    expect(textOf(tester, const Key('network_wgc5')), contains(kSpeedFailed));
    expect(r.c.log.any((e) => e.message.contains("couldn't find an address for Cloudflare")), isTrue);
  });

  testWidgets('a tunnel with no route in the lookup offers no speed test', (tester) async {
    await pump(tester, ssh: _router(tunnel: '@@NOROUTE'));
    expect(find.byKey(const Key('network_speed_wgc5')), findsNothing);
  });

  testWidgets('a firmware it does not know: the tunnels say so, and nothing is sent through them', (tester) async {
    final ssh = _router(firmwareTag: 'koolshare');
    await pump(tester, ssh: ssh);
    expect(textOf(tester, const Key('network_tunnels_error')), contains('this router firmware is not supported'));
    expect(ssh.commands.where((c) => c.contains(kTunnelLookupMarker)), isEmpty);
  });
}
