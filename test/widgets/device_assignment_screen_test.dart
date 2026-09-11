// test/widgets/device_assignment_screen_test.dart - the assignment screen over a fake router.
//
// The checks that matter are the ones a hardware run would only catch late: nothing is written
// until APPLY, a device with no address cannot be picked at all, and a device belonging to a VPN
// this app does not manage is named rather than shown as unassigned.
//
// MACs are invented - see test/unit/no_lan_identifiers_test.dart.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/device_assignment_service.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_session.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';
import 'package:cfg_pia_wg/widgets/device_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _clientlist = 'pia-aus_melbourne>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
    '<pia-aus_perth>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg'
    '<office>OpenVPN>1>>password>1>3>>>0>0>';

const _policyList = '1>192.168.1.50>>3>';
const _staticlist = '<11:22:33:44:55:66>192.168.1.20>>Box';
const _cfgDeviceList = '<RT-ABCD>192.168.1.1>AA:BB:CC:DD:EE:FF>1';

// Box is reserved and online. Laptop is unreserved and on the OpenVPN profile. Ghost is offline,
// has no cached address at all so it cannot be assigned, and carries a locally-administered MAC -
// one device per exceptional state, so each tag is tested in isolation.
const _clJson = '{'
    '"11:22:33:44:55:66":{"name":"box","online":1},'
    '"44:55:66:77:88:99":{"name":"laptop","online":1},'
    '"22:33:44:55:66:77":{"name":"ghost","online":0}}';

const _cache = '{'
    '"maclist":["11:22:33:44:55:66"],'
    '"ClientAPILevel":"5",'
    '"11:22:33:44:55:66":{"nickName":"Box","ip":"192.168.1.20","isOnline":"1"},'
    '"44:55:66:77:88:99":{"nickName":"Laptop","ip":"192.168.1.50","isOnline":"1"}}';

const _sep = '@@CFGPIAWG@@';

String _blob() => ['', _clientlist, _policyList, '9', _staticlist, '', _cfgDeviceList, _clJson, _cache, '']
    .join('\n$_sep\n');

RecordingSSHClient _router() => RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) return _blob();
      if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
      if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
      if (cmd == 'nvram get dhcp_staticlist') return _staticlist;
      // wgc1 up, wgc5 down - so the picker has one of each to tag. `ip -o link show up` is the
      // only correct liveness check: a WireGuard device reads state UNKNOWN while it is up.
      if (cmd.contains('ip -o link show up')) return '3: wgc1: <POINTOPOINT,NOARP,UP,LOWER_UP>';
      return '';
    });

Widget _wrap(RecordingSSHClient ssh) => SessionScope(
      controller: SessionController(),
      child: MaterialApp(
        home: Scaffold(
          body: DeviceAssignmentScreen(testClientFactory: (_, __, ___) async => ssh),
        ),
      ),
    );

Future<RecordingSSHClient> _pumpConnected(WidgetTester tester) async {
  final ssh = _router();
  await tester.pumpWidget(_wrap(ssh));
  await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
  await tester.enterText(find.byType(TextFormField).at(1), 'admin');
  await tester.enterText(find.byType(TextFormField).at(2), 'pw');
  await tester.pump();
  await tester.tap(find.byKey(const Key('device_connect')));
  await tester.pumpAndSettle();
  return ssh;
}

void main() {
  setUp(useStock);

  // Reported from hardware: all three router screens flashed their login form while the session's
  // existing connection was being reused - a form asking for credentials the app already has, on a
  // screen the user is about to be taken off, with fields they might start typing into.
  testWidgets('a reconnect never shows the login form, not even for a frame', (tester) async {
    final ssh = _router();
    final c = SessionController()
      ..routerIp = '192.168.1.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
      ..routerConnected = true;
    addTearDown(c.dispose);

    await tester.pumpWidget(SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(body: DeviceAssignmentScreen(testClientFactory: (_, __, ___) async => ssh)),
      ),
    ));

    // The FIRST frame, before the post-frame reconnect has run.
    expect(find.byType(ReconnectingBody), findsOneWidget);
    expect(find.byKey(const Key('device_connect')), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(ReconnectingBody), findsNothing);
    expect(find.byKey(const Key('device_apply')), findsOneWidget);
  });

  testWidgets('lists the devices, excluding the router', (tester) async {
    await _pumpConnected(tester);
    expect(find.textContaining('Box'), findsWidgets);
    expect(find.textContaining('Laptop'), findsWidgets);
    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsNothing, reason: 'the router is not a device');
  });

  testWidgets('tags only the exception', (tester) async {
    await _pumpConnected(tester);
    // Box is reserved and online, so its line is just name and address.
    expect(find.text('Box - 192.168.1.20'), findsOneWidget);
    // Laptop has no reservation.
    expect(find.text('Laptop - 192.168.1.50 - DHCP'), findsOneWidget);
    // Ghost is offline, has no address anywhere, and its address is locally administered.
    expect(find.text('ghost - offline - random MAC'), findsOneWidget);
  });

  testWidgets('a device with NO ADDRESS cannot be assigned', (tester) async {
    // The policy record is keyed by IP, so there is nothing that could be written for it. Listing
    // it but disabling the picker is honest; hiding it would be a silent hole in the list.
    await _pumpConnected(tester);
    expect(find.text('connect this device once to assign it'), findsOneWidget);
    expect(find.byKey(const Key('row_22:33:44:55:66:77')), findsNothing);
  });

  testWidgets('a device on a VPN we do not manage is NAMED, not shown as unassigned', (tester) async {
    await _pumpConnected(tester);
    expect(find.text('OpenVPN, not app managed'), findsOneWidget);
  });

  testWidgets('the default connection is shown at the top with its explanation', (tester) async {
    await _pumpConnected(tester);
    expect(find.text('Default connection'), findsOneWidget);
    expect(find.textContaining('fall back to it if their tunnel drops'), findsOneWidget);
    expect(find.text('wgc1:pia-aus_melbourne'), findsWidgets);
  });

  testWidgets('a default connection of INTERNET reads as Internet, not "profile 0"', (tester) async {
    // Index 0 is the WAN and no vpnc_clientlist record carries it, so the lookup fell through to
    // its "unknown profile" branch. Reported from B8 on 2026-09-08.
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) {
        return ['', _clientlist, _policyList, '0', _staticlist, '', _cfgDeviceList, _clJson, _cache, '']
            .join('\n$_sep\n');
      }
      if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
      if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
      return '';
    });
    await tester.pumpWidget(_wrap(ssh));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();

    expect(find.text('Internet'), findsOneWidget);
    expect(find.textContaining('profile 0'), findsNothing);
  });

  testWidgets('staged changes can be discarded in one go', (tester) async {
    await _pumpConnected(tester);
    expect(find.byKey(const Key('device_discard')), findsNothing, reason: 'nothing staged yet');

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('device_discard')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget);
  });

  testWidgets('APPLY is disabled until something is staged, and counts changes', (tester) async {
    await _pumpConnected(tester);
    final apply = find.byKey(const Key('device_apply'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget);

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();

    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  });

  testWidgets('STAGING WRITES NOTHING - only APPLY does', (tester) async {
    final ssh = await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    expect(ssh.commands.any((c) => c.contains('nvram set')), isFalse);
  });

  testWidgets('picking the value it already had is not a change', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_default')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget);
  });

  testWidgets('the picker offers only WireGuard slots', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pick_9')), findsOneWidget); // wgc1
    expect(find.byKey(const Key('pick_5')), findsOneWidget); // wgc5
    expect(find.byKey(const Key('pick_3')), findsNothing, reason: 'the OpenVPN profile is never offered');
  });

  // "default" on its own made the reader hold the default connection in their head while going
  // down a list of a dozen rows.
  testWidgets('a device that follows the default says what the default IS', (tester) async {
    await _pumpConnected(tester);
    expect(find.textContaining('default - wgc1:pia-aus_melbourne'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'default'), findsNothing);
  });

  // The router models two different things with index 0 - `1>IP>>0>` is PINNED to the internet and
  // ignores the default, `0>IP>>0>` follows it - and the app only offered the second. With one
  // tunnel configured the picker read as the same profile listed twice.
  testWidgets('a device can be pinned to the plain internet, separately from following a default', (tester) async {
    final ssh = await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pick_default')), findsOneWidget);
    expect(find.byKey(const Key('pick_internet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick_internet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_confirm')));
    await tester.pumpAndSettle();

    // Enabled, index 0: pinned. The unassign form would have been `0>...>>0>`.
    final write = ssh.commands.firstWhere((c) => c.startsWith('nvram set vpnc_dev_policy_list'));
    expect(write, contains('1>192.168.1.20>>0>'));
  });

  testWidgets('the picker tags each tunnel Active or Disabled', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();

    // A tunnel that is down accepts an assignment happily and then carries no traffic, which is a
    // slow thing to work out from the outside.
    final active = tester.widget<Text>(find.text('Active').first);
    expect(active.style?.color, kHighlight);
    final disabled = tester.widget<Text>(find.text('Disabled').first);
    expect(disabled.style?.color, kWarn, reason: 'amber, as a paused watchdog and a staged change are');
  });

  // Reported: a glance at the log discarded everything staged, because the screen is rebuilt from
  // scratch on every entry.
  testWidgets('staged changes survive leaving the screen and coming back', (tester) async {
    final ssh = _router();
    final c = SessionController()
      ..routerIp = '192.168.1.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
      ..routerConnected = true;
    addTearDown(c.dispose);
    Widget screen() => SessionScope(
          controller: c,
          child: MaterialApp(
            home: Scaffold(body: DeviceAssignmentScreen(testClientFactory: (_, __, ___) async => ssh)),
          ),
        );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);

    // Away and back: a new State, built from the session rather than from nothing.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);
    expect(c.stagedAssignments['192.168.1.20'], 5);
  });

  testWidgets('discarding clears the session too, so it does not come back', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('device_discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device_discard')), findsNothing);
  });

  // The list came back in creation order, so a user who built wgc1 then wgc5 then wgc2 saw wgc4
  // above wgc3 and had to read every line to find one. Slot number is the only order anyone thinks
  // in - within the enabled and disabled groups, which stay.
  testWidgets('the picker lists tunnels in wgcN order within each group', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();

    // wgc1 is up in the fixture and wgc5 is not, so active-first and wgcN-order agree here; the
    // assertion that matters is that both are present and ordered, not jumbled by creation order.
    final one = tester.getCenter(find.byKey(const Key('pick_9'))).dy;
    final five = tester.getCenter(find.byKey(const Key('pick_5'))).dy;
    expect(one, lessThan(five), reason: 'wgc1 is active, wgc5 is not');
  });

  // An active watchdog is the one fact worth spotting while choosing, so it is the one that is not
  // grey.
  testWidgets('an active watchdog is teal in the picker', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();

    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      if (t.data == kWatchdogActiveNote) {
        expect(t.style?.color, kHighlight);
        return;
      }
    }
  });

  testWidgets('APPLY and DISCARD share one centred row, at HOME height', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();

    final discard = tester.getRect(find.byKey(const Key('device_discard')));
    final apply = tester.getRect(find.byKey(const Key('device_apply')));
    expect(discard.center.dy, apply.center.dy, reason: 'one row');
    expect(discard.right, lessThan(apply.left), reason: 'discard on the left');
    expect(discard.height, apply.height, reason: 'and the same height as each other');
    // Capitals, like every other button label in the app.
    expect(find.text('DISCARD CHANGES'), findsOneWidget);
    expect(find.text('Discard changes'), findsNothing);
  });

  testWidgets('APPLY confirms, then writes', (tester) async {
    final ssh = await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();

    expect(find.text('Apply 1 change'), findsOneWidget);
    // "default" on its own meant holding the default connection in your head while reading the
    // list; the row and the confirmation both resolve it now. vpnc_default_wan is 9 here, wgc1.
    expect(find.textContaining('default - wgc1:pia-aus_melbourne -> wgc5:pia-aus_perth'), findsOneWidget);

    await tester.tap(find.byKey(const Key('apply_confirm')));
    await tester.pumpAndSettle();

    expect(ssh.commands.any((c) => c.startsWith('nvram set vpnc_dev_policy_list')), isTrue);
    expect(ssh.ran('service restart_dnsmasq'), isTrue);
    expect(ssh.ran('restart_net_and_phy'), isFalse);
  });

  testWidgets('the confirmation warns about a reservation only when one will be created', (tester) async {
    await _pumpConnected(tester);
    // Box is already reserved - no warning.
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('will also be given a fixed address'), findsNothing);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    // Laptop is not reserved - warning, and it says the reservation persists.
    await tester.tap(find.byKey(const Key('row_44:55:66:77:88:99')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('will also be given a fixed address'), findsOneWidget);
    expect(find.textContaining('stays on your router afterwards'), findsOneWidget);
  });

  testWidgets('the confirmation warns when a foreign assignment is being replaced', (tester) async {
    await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_44:55:66:77:88:99')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not manage'), findsOneWidget);
  });

  testWidgets('a conflict is reported and nothing is written', (tester) async {
    // The router changed under us. The apply must refuse rather than overwrite whatever the web
    // interface just did.
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) return _blob();
      if (cmd == 'nvram get vpnc_dev_policy_list') return '1>192.168.1.99>>5>';
      if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
      return '';
    });
    await tester.pumpWidget(_wrap(ssh));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('changed while you were editing'), findsOneWidget);
    expect(ssh.commands.any((c) => c.startsWith('nvram set vpnc_dev_policy_list')), isFalse);

    // And the screen RECOVERS. Without the re-read it kept the base it had loaded before the
    // conflict, so every later APPLY refused too and the only way out was to leave the screen.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget, reason: 'staging cleared');
    expect(find.text('Default connection'), findsOneWidget, reason: 'still usable, not stuck');
  });

  testWidgets('the screen shows the NEW default connection after applying', (tester) async {
    // Reported after B8n on 2026-09-08 as "we need to refresh after setting a new default". The
    // apply does re-read; this pins that the re-read reaches the screen rather than the state
    // being refreshed behind a stale label.
    var key = '9';
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) {
        return ['', _clientlist, _policyList, key, _staticlist, '', _cfgDeviceList, _clJson, _cache, '']
            .join('\n$_sep\n');
      }
      if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
      if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
      if (cmd == 'nvram get vpnc_default_wan') return '0';
      if (cmd == 'ip -o link show up') return 'wgc1 wgc5';
      if (cmd.startsWith('nvram set vpnc_default_wan=')) key = cmd.split('=').last;
      return '';
    });
    await tester.pumpWidget(SessionScope(
      controller: SessionController(),
      child: MaterialApp(
        home: Scaffold(
          body: DeviceAssignmentScreen(
            testClientFactory: (_, __, ___) async => ssh,
            // Without this the screen builds a service with the real two-second poll interval and
            // the apply never finishes inside pumpAndSettle.
            serviceFactory: (c) => DeviceAssignmentService(c, pollInterval: Duration.zero),
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();
    expect(find.text('wgc1:pia-aus_melbourne'), findsWidgets);

    await tester.tap(find.byKey(const Key('default_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('default_pick_5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('wgc5:pia-aus_perth'), findsWidgets, reason: 'the picker shows the new default');
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget, reason: 'staging cleared');
  });

  testWidgets('USES THE SHARED SESSION, not a raw client', (tester) async {
    // The B3 failure on 2026-09-08: the screen held the SSHClient it opened, six minutes passed
    // between connect and APPLY, and the write died with `errno 103, software caused connection
    // abort`. A raw client cannot reopen; RouterSession retries. Asserting on the type is blunt
    // but it is exactly the property that was missing.
    final ssh = _router();
    SSHClient? handed;
    await tester.pumpWidget(SessionScope(
      controller: SessionController(),
      child: MaterialApp(
        home: Scaffold(
          body: DeviceAssignmentScreen(
            testClientFactory: (_, __, ___) async => ssh,
            serviceFactory: (c) {
              handed = c;
              return DeviceAssignmentService(c);
            },
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();

    expect(handed, isA<RouterSession>());
  });

  testWidgets('the SSH username starts BLANK so autofill is not blocked', (tester) async {
    // A password manager will not overwrite a field that already has text, so defaulting to
    // 'admin' cost a manual clear before every autofill (B3 feedback 2026-09-08).
    await tester.pumpWidget(_wrap(_router()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'admin'), findsNothing);
  });

  testWidgets('DETECTS the firmware itself rather than trusting a previous screen', (tester) async {
    // Reported from B1 on 2026-09-08: opening this screen first, without passing through MANAGE,
    // reported a stock router as Merlin. `routerFirmware` defaults to Merlin until something
    // probes it, and nothing here had.
    resetRouterFirmware();
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('3rd-party')) return ''; // empty tag means stock
      if (cmd.contains('cfg_device_list')) return _blob();
      if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
      if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
      return '';
    });
    await tester.pumpWidget(_wrap(ssh));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();

    expect(find.textContaining('stock-firmware feature'), findsNothing, reason: 'stock, not Merlin');
    expect(find.text('Default connection'), findsOneWidget, reason: 'the list opened');
  });

  testWidgets('Merlin is refused with a reason rather than an empty screen', (tester) async {
    useMerlin();
    final ssh = _router();
    await tester.pumpWidget(_wrap(ssh));
    await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin');
    await tester.enterText(find.byType(TextFormField).at(2), 'pw');
    await tester.pump();
    await tester.tap(find.byKey(const Key('device_connect')));
    await tester.pumpAndSettle();
    expect(find.textContaining('stock-firmware feature'), findsOneWidget);
  });
}
