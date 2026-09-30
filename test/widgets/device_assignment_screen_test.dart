// test/widgets/device_assignment_screen_test.dart - the assignment screen over a fake router.
//
// The checks that matter are the ones a hardware run would only catch late: nothing is written
// until APPLY, a device with no address cannot be picked at all, and a device belonging to a VPN
// this app does not manage is named rather than shown as unassigned.
//
// MACs are invented - see test/unit/no_lan_identifiers_test.dart.
import 'dart:async';
import 'dart:typed_data';

import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/device_assignment_service.dart';
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_session.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';
import 'package:cfg_pia_wg/widgets/applying_panel.dart';
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

String _blob({String policy = _policyList, String defaultKey = '9', String? rules, String? ipv6}) => [
      '', _clientlist, policy, defaultKey, _staticlist, '', _cfgDeviceList, _clJson, _cache, '',
      // `ip rule show` since ID-319, and `ipv6_service` since ID-317, after the parental controls.
      if (rules != null || ipv6 != null) ...[rules ?? '', ipv6 ?? '', ''],
    ].join('\n$_sep\n');

/// The tunnel check's one round trip: the up interfaces, the router clock (10000), then each slot the
/// command asks about, in its order.
String _health(String cmd, Map<int, int> handshakes) => [
      '',
      '3: wgc1: <POINTOPOINT,NOARP,UP,LOWER_UP>',
      '10000',
      for (final m in RegExp(r'wg show wgc(\d) latest-handshakes').allMatches(cmd))
        handshakes.containsKey(int.parse(m.group(1)!)) ? 'peerkey=\t${handshakes[int.parse(m.group(1)!)]}' : '',
      '',
    ].join('\n$_sep\n');

RecordingSSHClient _router({
  String policy = _policyList,
  String defaultKey = '9',
  // wgc1's server answered 50 seconds ago on the router clock.
  Map<int, int> handshakes = const {1: 9950},
  String? rules,
  String? ipv6,
}) =>
    RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('cfg_device_list')) return _blob(policy: policy, defaultKey: defaultKey, rules: rules, ipv6: ipv6);
      // Before the plain interface check below: the tunnel check's round trip contains that command.
      if (cmd.contains('latest-handshakes')) return _health(cmd, handshakes);
      if (cmd == 'nvram get vpnc_dev_policy_list') return policy;
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

Future<RecordingSSHClient> _pumpConnected(WidgetTester tester, {RecordingSSHClient? router}) async {
  final ssh = router ?? _router();
  await tester.pumpWidget(_wrap(ssh));
  await tester.enterText(find.byType(TextFormField).first, '192.168.1.1');
  await tester.enterText(find.byType(TextFormField).at(1), 'admin');
  await tester.enterText(find.byType(TextFormField).at(2), 'pw');
  await tester.pump();
  await tester.tap(find.byKey(const Key('device_connect')));
  await tester.pumpAndSettle();
  return ssh;
}

/// A router that holds one command until [release] is called, to look at the screen mid-APPLY.
class _HeldRouter extends RecordingSSHClient {
  _HeldRouter({required super.responder, required this.holdOn});
  final String holdOn;
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<Uint8List> run(String command,
      {Map<String, String>? environment, bool runInPty = false, bool stderr = true, bool stdout = true}) async {
    if (command.contains(holdOn)) await _gate.future;
    return super.run(command, environment: environment, runInPty: runInPty, stderr: stderr, stdout: stdout);
  }
}

void main() {
  setUp(useStock);

  // ID-285, EXT-8: the drawer sits above the navigator, so a screen picked from it mid-APPLY went on
  // top of the "Applying" dialog. The APPLY then ended with a plain pop, which closed THAT screen
  // and left the dialog up for good over a DEVICES that had finished.
  testWidgets('a screen opened over the Applying dialog stays, and the dialog still goes', (tester) async {
    final ssh = _HeldRouter(responder: _router().responder, holdOn: 'nvram set vpnc_dev_policy_list');
    await _pumpConnected(tester, router: ssh);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_internet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ApplyingPanel), findsOneWidget);

    // What the drawer does: push the chosen screen on the app's navigator.
    Navigator.of(tester.element(find.byType(DeviceAssignmentScreen))).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('APP LOG', key: Key('other_screen'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    ssh.release();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('other_screen')), findsOneWidget, reason: 'the screen the user chose is not closed');
    expect(find.byType(ApplyingPanel), findsNothing, reason: 'the dialog goes when the APPLY ends');
    expect(ssh.ran('service restart_vpnc_dev_policy'), isTrue, reason: 'and the APPLY completed');
  });

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

  // ID-032: the name and its exceptions on the first line, the address and MAC on the second.
  testWidgets('tags only the exception, with the address and MAC underneath', (tester) async {
    await _pumpConnected(tester);
    // Box is reserved and online, so its first line is just its name.
    expect(find.text('Box'), findsOneWidget);
    expect(find.text('192.168.1.20 11:22:33:44:55:66'), findsOneWidget);
    // Laptop has no reservation.
    expect(find.text('Laptop - DHCP'), findsOneWidget);
    expect(find.text('192.168.1.50 44:55:66:77:88:99'), findsOneWidget);
    // Ghost is offline, has no address anywhere, and its address is locally administered: the tags share a bar.
    expect(find.text('ghost - offline | random MAC'), findsOneWidget);
    expect(find.text('22:33:44:55:66:77'), findsOneWidget, reason: 'no address is known, so the MAC alone');
  });

  testWidgets('a device with NO ADDRESS cannot be assigned', (tester) async {
    // The policy record is keyed by IP, so there is nothing that could be written for it. Listing
    // it but disabling the picker is honest; hiding it would be a silent hole in the list.
    await _pumpConnected(tester);
    expect(find.text('connect this device once to assign it'), findsOneWidget);
    // ID-283: the address line's colour, not kHint, which was almost unreadable on a dimmed row.
    expect(tester.widget<Text>(find.text('connect this device once to assign it')).style?.color, kMuted);
    expect(find.byKey(const Key('row_22:33:44:55:66:77')), findsNothing);
  });

  testWidgets('a device on a VPN we do not manage is NAMED, not shown as unassigned', (tester) async {
    await _pumpConnected(tester);
    expect(find.text('OpenVPN, not app managed'), findsOneWidget);
  });

  testWidgets('the default connection is shown at the top with its explanation', (tester) async {
    await _pumpConnected(tester);
    expect(find.text('Default connection'), findsOneWidget);
    expect(find.textContaining('never falls back to it'), findsOneWidget);
    expect(find.textContaining('fall back to it if their tunnel drops'), findsNothing, reason: 'false since the guard (ID-340)');
    expect(find.text('wgc1:pia-aus_melbourne'), findsWidgets);
  });

  // ID-317: the app does not support IPv6, and a pinned device's IPv6 leaves outside its tunnel.
  testWidgets('with IPv6 on in the router, DEVICES says what that means for assigned devices', (tester) async {
    await _pumpConnected(tester, router: _router(ipv6: 'dhcp6'));
    expect(find.byKey(const Key('ipv6_warning')), findsOneWidget);
  });

  testWidgets('with IPv6 off, or not read, there is no IPv6 warning', (tester) async {
    await _pumpConnected(tester, router: _router(ipv6: 'disabled'));
    expect(find.byKey(const Key('ipv6_warning')), findsNothing);
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

  // ID-090: the pair is a row at every width. It used to reflow to a stack, and did so exactly in
  // the idle state, because APPLY 0 CHANGES is the widest label the screen ever shows.
  testWidgets('DISCARD and APPLY sit side by side with nothing staged', (tester) async {
    await _pumpConnected(tester);

    final discard = tester.getRect(find.byKey(const Key('device_discard')));
    final apply = tester.getRect(find.byKey(const Key('device_apply')));
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget, reason: 'the idle label, the widest one');
    expect(apply.top, moreOrLessEquals(discard.top, epsilon: 0.5), reason: 'one row, not a stack');
    expect(apply.left, greaterThan(discard.right), reason: 'APPLY sits to the right of DISCARD');
    expect(apply.width, moreOrLessEquals(discard.width, epsilon: 0.5), reason: 'equal halves');
  });

  testWidgets('staged changes can be discarded in one go', (tester) async {
    await _pumpConnected(tester);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('device_discard'))).onPressed, isNull,
        reason: 'shown, but nothing is staged to discard yet');

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('device_discard')));
    await tester.tap(find.byKey(const Key('device_discard')));
    await tester.pumpAndSettle();
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget);
  });

  testWidgets('APPLY is disabled until something is staged, and counts changes', (tester) async {
    await _pumpConnected(tester);
    final apply = find.byKey(const Key('device_apply'));
    expect(tester.widget<OutlinedButton>(apply).onPressed, isNull);
    expect(find.text('APPLY 0 CHANGES'), findsOneWidget);

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();

    expect(find.text('APPLY 1 CHANGE'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(apply).onPressed, isNotNull);
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
    // The exit notes can push APPLY under the pinned HOME button; a user scrolls, and so does this.
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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

    await tester.ensureVisible(find.byKey(const Key('device_discard')));
    await tester.tap(find.byKey(const Key('device_discard')));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('device_discard'))).onPressed, isNull);
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

  // Item 10: the pair follows the pending state rather than appearing and disappearing. Red DISCARD and
  // teal APPLY while something is staged; both grey and disabled otherwise. APPLY lost its fill.
  testWidgets('DISCARD and APPLY are grey with nothing staged, red and teal with something', (tester) async {
    await _pumpConnected(tester);
    Color border(String key) =>
        tester.widget<OutlinedButton>(find.byKey(Key(key))).style!.side!.resolve(<WidgetState>{})!.color;

    expect(border('device_discard'), kHint);
    expect(border('device_apply'), kHint);

    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();

    expect(border('device_discard'), kError);
    expect(border('device_apply'), kHighlight);
  });

  testWidgets('APPLY confirms, then writes', (tester) async {
    final ssh = await _pumpConnected(tester);
    await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_5')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
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
    await tester.ensureVisible(find.byKey(const Key('device_apply')));
    await tester.tap(find.byKey(const Key('device_apply')));
    await tester.pumpAndSettle();
    // ID-191: the cost is the restart. It used to add that a watchdog "will report the outage",
    // which a restart of seconds almost never gives it the chance to.
    expect(find.textContaining('stops and restarts your VPN tunnels'), findsOneWidget);
    expect(find.textContaining('report the outage'), findsNothing);
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

  // Reported 2026-09-13 while testing on hardware: devices were moved onto a tunnel that looked fine
  // and was not, and the screen gave no hint. APPLY now reads the tunnels first.
  group('APPLY checks the tunnels it moves devices onto', () {
    Future<void> stage(WidgetTester tester, String row, String pick) async {
      await tester.tap(find.byKey(Key(row)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(pick)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('device_apply')));
      await tester.tap(find.byKey(const Key('device_apply')));
      await tester.pumpAndSettle();
    }

    testWidgets('a tunnel that is not running is named, with the device held off the internet - and still applies',
        (tester) async {
      final ssh = await _pumpConnected(tester);
      await stage(tester, 'row_11:22:33:44:55:66', 'pick_5');

      expect(
          // ID-213: it used to say Box would use the default connection meanwhile - the fall-through
          // the fail-closed guard now prevents.
          find.text('wgc5:pia-aus_perth is not running. Until it is enabled, Box will have no internet.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('apply_confirm')));
      await tester.pumpAndSettle();
      expect(ssh.commands.any((c) => c.startsWith('nvram set vpnc_dev_policy_list')), isTrue,
          reason: 'a warning, not a block: assigning to a disabled slot is legitimate');
    });

    testWidgets('a server that has not answered for a while is named, with how long', (tester) async {
      await _pumpConnected(tester, router: _router(handshakes: const {1: 9000}));
      await stage(tester, 'row_11:22:33:44:55:66', 'pick_9');

      expect(
          find.text('wgc1:pia-aus_melbourne is up, but its server has not answered for 16 minutes. '
              'Box may have no internet.'),
          findsOneWidget);
    });

    testWidgets('a healthy tunnel adds nothing to the confirmation', (tester) async {
      await _pumpConnected(tester);
      await stage(tester, 'row_11:22:33:44:55:66', 'pick_9');

      expect(find.textContaining('is not running'), findsNothing);
      expect(find.textContaining('has not answered'), findsNothing);
    });

    testWidgets('a new default connection that is not running gets its own warning', (tester) async {
      await _pumpConnected(tester);
      await tester.tap(find.byKey(const Key('default_picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('default_pick_5')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('device_apply')));
      await tester.tap(find.byKey(const Key('device_apply')));
      await tester.pumpAndSettle();

      expect(
          find.text('wgc5:pia-aus_perth is not running. Until it is, devices on the default connection are not on that VPN.'),
          findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
    });
  });

  // Measured on hardware 2026-09-13: a device pinned to a disabled slot keeps its pin and falls
  // through to the default connection, while the screen went on naming the slot.
  group('where a device actually exits when its tunnel is not running', () {
    testWidgets('a device pinned to a stopped tunnel is shown as having no internet, not as falling through',
        (tester) async {
      await _pumpConnected(tester, router: _router(policy: '1>192.168.1.20>>5>'));

      expect(
          tester.widget<Text>(find.byKey(const Key('exit_11:22:33:44:55:66'))).data,
          'wgc5:pia-aus_perth is not running - no internet until it is enabled');
      // The picker still names the assignment: the pin is intact, and enabling wgc5 restores it.
      expect(
          find.descendant(of: find.byKey(const Key('row_11:22:33:44:55:66')), matching: find.text('wgc5:pia-aus_perth')),
          findsOneWidget);
    });

    // ID-319: "no internet" was worked out from the tunnel's state alone. It is now said only when the
    // router holds the device's guard rules, and a device without them is called unguarded.
    testWidgets('a pinned device whose guard the router holds is still shown as having no internet', (tester) async {
      await _pumpConnected(tester,
          router: _router(
              policy: '1>192.168.1.20>>5>',
              rules: '0:\tfrom all lookup local\n90:\tfrom 192.168.1.20 lookup 5 suppress_prefixlength 0\n'
                  '91:\tfrom 192.168.1.20 blackhole\n100:\tfrom 192.168.1.20 lookup 5'));
      expect(tester.widget<Text>(find.byKey(const Key('exit_11:22:33:44:55:66'))).data,
          'wgc5:pia-aus_perth is not running - no internet until it is enabled');
    });

    testWidgets('a pinned device missing its guard rules is shown as unguarded, not as having no internet',
        (tester) async {
      await _pumpConnected(tester,
          router: _router(
              policy: '1>192.168.1.20>>5>',
              rules: '0:\tfrom all lookup local\n90:\tfrom 192.168.1.20 lookup 5 suppress_prefixlength 0\n'
                  '100:\tfrom 192.168.1.20 lookup 5'));
      expect(tester.widget<Text>(find.byKey(const Key('exit_11:22:33:44:55:66'))).data,
          startsWith('fail-closed guard missing - while wgc5:pia-aus_perth is down'));
    });

    testWidgets('a default that is not running sends unassigned devices to the internet', (tester) async {
      await _pumpConnected(tester, router: _router(defaultKey: '5'));

      expect(tester.widget<Text>(find.byKey(const Key('default_exit'))).data,
          'wgc5:pia-aus_perth is not running - unassigned devices use Internet, with no VPN');
      expect(tester.widget<Text>(find.byKey(const Key('exit_11:22:33:44:55:66'))).data,
          'wgc5:pia-aus_perth is not running - traffic uses Internet, with no VPN');
    });

    testWidgets('running tunnels, and a VPN this app does not manage, add no note', (tester) async {
      await _pumpConnected(tester);
      expect(find.byKey(const Key('default_exit')), findsNothing);
      expect(find.textContaining('is not running'), findsNothing, reason: 'the OpenVPN profile state is unknown, not down');
    });
  });

  // ID-218: read once at connect, the notes went stale - straight after a reboot every device read
  // "not running" while every tunnel was up, and going to MANAGE and back changed nothing.
  group('keeping which tunnels are running current (ID-218)', () {
    const exitKey = Key('exit_11:22:33:44:55:66');

    /// Box pinned to wgc5. [up] is read on every command, so a test can bring a tunnel up mid-way.
    RecordingSSHClient liveRouter(List<String> up) => RecordingSSHClient(responder: (cmd) {
          final ifaces = up.map((i) => '3: $i: <POINTOPOINT,NOARP,UP,LOWER_UP>').join('\n');
          if (cmd.contains('cfg_device_list')) return _blob(policy: '1>192.168.1.20>>5>');
          if (cmd.contains('latest-handshakes')) {
            return [
              '',
              ifaces,
              '10000',
              for (final _ in RegExp(r'wg show wgc\d latest-handshakes').allMatches(cmd)) 'peerkey=\t9950',
              '',
            ].join('\n$_sep\n');
          }
          if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
          if (cmd.contains('ip -o link show up')) return ifaces;
          return '';
        });

    int checks(RecordingSSHClient c) => c.commands.where((cmd) => cmd.contains('latest-handshakes')).length;

    testWidgets('a tunnel that comes up clears its note within 15 seconds, and nothing is logged', (tester) async {
      final up = ['wgc1'];
      final c = await _pumpConnected(tester, router: liveRouter(up));
      expect(find.byKey(exitKey), findsOneWidget);
      final session = SessionScope.of(tester.element(find.byType(DeviceAssignmentScreen)));
      final logged = session.log.length;
      final before = checks(c);

      up.add('wgc5');
      await tester.pump(const Duration(seconds: 10));
      expect(checks(c), before, reason: 'not before the interval');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(checks(c), before + 1);
      expect(find.byKey(exitKey), findsNothing);
      expect(session.log.length, logged, reason: 'a quiet check writes nothing to the app log');
    });

    testWidgets('coming back to the screen checks at once, and nothing is checked while away', (tester) async {
      final up = ['wgc1'];
      final c = await _pumpConnected(tester, router: liveRouter(up));
      final before = checks(c);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const Text('MANAGE'))));
      await tester.pumpAndSettle();
      up.add('wgc5');
      await tester.pump(const Duration(seconds: 20));
      expect(checks(c), before, reason: 'the screen is covered');

      nav.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(checks(c), before + 1);
      expect(find.byKey(exitKey), findsNothing);
    });

    testWidgets('pull to refresh reads the devices and the tunnels again', (tester) async {
      final up = ['wgc1'];
      final c = await _pumpConnected(tester, router: liveRouter(up));
      final reads = c.commands.where((cmd) => cmd.contains('cfg_device_list')).length;
      up.add('wgc5');
      await tester.fling(find.byType(SingleChildScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(c.commands.where((cmd) => cmd.contains('cfg_device_list')).length, reads + 1);
      expect(find.byKey(exitKey), findsNothing);
    });
  });

  // Looking at your own devices is the most persuasive thing this screen can do, so browsing and
  // staging stay free for everyone. APPLY is the moment the router changes, and the only gate.
  group('what a locked user can do', () {
    setUp(() => Entitlement.debugSetUnlocked(false));
    tearDown(() => Entitlement.debugSetUnlocked(null));

    testWidgets('browses and stages freely; APPLY opens the paywall and writes nothing', (tester) async {
      final ssh = await _pumpConnected(tester);
      expect(find.text('Box'), findsOneWidget, reason: 'the list is free to look at');

      await tester.tap(find.byKey(const Key('row_11:22:33:44:55:66')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_5')));
      await tester.pumpAndSettle();
      expect(find.text('APPLY 1 CHANGE'), findsOneWidget, reason: 'staging is free, and shows the tally');

      await tester.ensureVisible(find.byKey(const Key('device_apply')));
      await tester.tap(find.byKey(const Key('device_apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paywall_buy')), findsOneWidget);
      expect(ssh.commands.any((c) => c.contains('nvram set')), isFalse,
          reason: 'the paywall stands in FRONT of the write, not after it');

      // Closing it leaves the staged change where it was: nothing is lost by declining.
      await tester.tap(find.byKey(const Key('paywall_close')));
      await tester.pumpAndSettle();
      expect(find.text('APPLY 1 CHANGE'), findsOneWidget);
    });
  });

  // ID-261: rename a device, and disable its internet, from the same screen and the same APPLY.
  group('names and disabling', () {
    const box = '11:22:33:44:55:66';

    Future<void> applyAll(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('device_apply')));
      await tester.tap(find.byKey(const Key('device_apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply_confirm')));
      await tester.pumpAndSettle();
    }

    testWidgets('tap a name, type, Enter: staged in amber, and written only by APPLY', (tester) async {
      final ssh = await _pumpConnected(tester);
      await tester.tap(find.byKey(const Key('name_$box')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name_field_$box')), 'Kids tablet');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final name = tester.widget<Text>(find.descendant(of: find.byKey(const Key('name_$box')), matching: find.byType(Text)));
      expect(name.data, startsWith('Kids tablet'));
      expect(name.style?.color, kWarn, reason: 'amber until APPLY, as a staged picker is');
      expect(find.text('APPLY 1 CHANGE'), findsOneWidget);
      expect(ssh.commands.any((c) => c.contains('custom_clientlist=')), isFalse, reason: 'nothing before APPLY');

      await applyAll(tester);
      expect(ssh.ran("nvram set custom_clientlist='<Kids tablet>$box>0>0>>>>'"), isTrue);
    });

    testWidgets('a name the router would refuse is not staged, and says why', (tester) async {
      await _pumpConnected(tester);
      await tester.tap(find.byKey(const Key('name_$box')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name_field_$box')), 'a<b');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('name_error_$box')), findsOneWidget);
      expect(find.text('APPLY 0 CHANGES'), findsOneWidget);
    });

    testWidgets('tapping away leaves the name as it was', (tester) async {
      await _pumpConnected(tester);
      await tester.tap(find.byKey(const Key('name_$box')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name_field_$box')), 'Something else');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('name_field_$box')), findsNothing);
      expect(find.text('APPLY 0 CHANGES'), findsOneWidget);
    });

    testWidgets('Disabled is the last choice, in red, and shows on the row; APPLY writes Time Scheduling', (tester) async {
      final ssh = await _pumpConnected(tester);
      await tester.tap(find.byKey(const Key('row_$box')));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('pick_disabled'));
      expect(tile, findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: tile, matching: find.text('Disabled'))).style?.color, kError);
      expect(find.text('no Internet or VPN access'), findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row_${box}_disabled')), findsOneWidget);

      await applyAll(tester);
      expect(ssh.ran("nvram set MULTIFILTER_MAC='$box'"), isTrue);
      expect(ssh.ran("nvram set MULTIFILTER_ENABLE='2'"), isTrue);
      expect(ssh.ran('service restart_firewall'), isTrue);
      // The VPN assignment is kept underneath (Andrew's decision): the policy list is not rewritten.
      expect(ssh.commands.any((c) => c.startsWith('nvram set vpnc_dev_policy_list')), isFalse);
    });

    testWidgets('choosing a connection for a disabled device enables it again, where it was', (tester) async {
      final blocked = RecordingSSHClient(responder: (cmd) {
        const ts = 'MULTIFILTER_ALL=1\nMULTIFILTER_MAC=$box\nMULTIFILTER_DEVICENAME=Box\nMULTIFILTER_ENABLE=2\n'
            'MULTIFILTER_MACFILTER_DAYTIME_V2=W03E21000700<W04122000800';
        if (cmd.contains('cfg_device_list')) {
          return ['', _clientlist, _policyList, '9', _staticlist, '', _cfgDeviceList, _clJson, _cache, ts, '']
              .join('\n$_sep\n');
        }
        if (cmd.startsWith('echo "MULTIFILTER_ALL=')) return ts;
        if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
        if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
        return '';
      });
      final ssh = await _pumpConnected(tester, router: blocked);
      expect(find.byKey(const Key('row_${box}_disabled')), findsOneWidget, reason: "the router's own state");

      await tester.tap(find.byKey(const Key('row_$box')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_default')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row_${box}_disabled')), findsNothing);

      await applyAll(tester);
      expect(ssh.ran("nvram set MULTIFILTER_MAC=''"), isTrue, reason: 'the entry it would have made is removed');
      expect(ssh.ran("nvram set MULTIFILTER_ALL='0'"), isTrue, reason: 'with nothing left, Time Scheduling goes off');
    });

    testWidgets('APPLY names the schedules that disabling a device would switch on', (tester) async {
      final scheduled = RecordingSSHClient(responder: (cmd) {
        const ts = 'MULTIFILTER_ALL=0\nMULTIFILTER_MAC=44:55:66:77:88:99\nMULTIFILTER_DEVICENAME=Laptop\n'
            'MULTIFILTER_ENABLE=1\nMULTIFILTER_MACFILTER_DAYTIME_V2=W01E08001700';
        if (cmd.contains('cfg_device_list')) {
          return ['', _clientlist, _policyList, '9', _staticlist, '', _cfgDeviceList, _clJson, _cache, ts, '']
              .join('\n$_sep\n');
        }
        if (cmd.startsWith('echo "MULTIFILTER_ALL=')) return ts;
        return '';
      });
      await _pumpConnected(tester, router: scheduled);
      await tester.tap(find.byKey(const Key('row_$box')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_disabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('device_apply')));
      await tester.tap(find.byKey(const Key('device_apply')));
      await tester.pumpAndSettle();
      final warning = tester.widget<Text>(find.byKey(const Key('apply_schedule_warning'))).data!;
      expect(warning, contains('Time Scheduling is off'));
      expect(warning, contains('Laptop'));
    });
  });
}
