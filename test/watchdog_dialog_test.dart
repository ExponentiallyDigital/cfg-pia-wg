// test/watchdog_dialog_test.dart - widget tests for the watchdog EDIT dialog (save-redeploy).
import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/widgets/applying_panel.dart';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/watchdog_dialog.dart';
import 'package:cfg_pia_wg/watchdog_email.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';
import 'package:cfg_pia_wg/widgets/common_fields.dart';

import 'watchdog_test_utils.dart';

/// A PIA that answers the region list only when told to, like one taking its time (ID-279).
class _SlowPia extends _FakePia {
  final regions = Completer<void>();

  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async {
    await regions.future;
    return super.fetchRegions(onProgress: onProgress);
  }
}

class _FakePia extends PiaService {
  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async => const [
        Region(
          id: 'aus_melbourne',
          wgServers: [WgServer(ip: '1.2.3.4', cn: 'aus')],
        ),
      ];
}

/// PIA's login service down: the token request gets no answer, as on 2026-10-01.
class _DownPia extends _FakePia {
  @override
  Future<String> getToken(String username, String password, {void Function(String)? onProgress}) async =>
      throw piaLoginUnavailable('no answer in 20 s');
}

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Widget _host(
  RecordingSSHClient client,
  SessionController c, {
  bool slotIsEmpty = false,
  String regionDesc = 'aus_melbourne',
  String piaUser = 'p1234567',
  String piaPass = 'secret',
  Future<SSHClient> Function()? connect,
  Map<int, String> otherSlotDns = const {},
  PiaService? pia,
}) {
  return SessionScope(
    controller: c,
    child: MaterialApp(
      home: Scaffold(
        body: WatchdogDialog(
          slotIndex: 1,
          regionDesc: regionDesc,
          slotIsEmpty: slotIsEmpty,
          controller: c,
          piaUsername: piaUser,
          piaPassword: piaPass,
          connect: connect ?? () async => client,
          piaService: pia ?? _FakePia(),
          serviceFactory: (cl) => RouterWatchdog(cl, onLog: c.onLog),
          otherSlotDns: otherSlotDns,
        ),
      ),
    ),
  );
}

/// A stock router with both preconditions satisfied: `jq` installed, and the init directory that
/// Download Master provides. Tests about anything else should not have to think about them.
String _stockReady(String cmd) =>
    cmd.contains(kStockJqPath) || cmd.contains("-d '$kStockBootDir'") ? '1' : '';

void main() {
  // ID-279: SAVE & DEPLOY asked PIA about the region with nothing on screen, for up to ten seconds,
  // and the form looked hung.
  testWidgets('the spinner shows while SAVE & DEPLOY checks the region with PIA', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final pia = _SlowPia();
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true, pia: pia));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pump();
    expect(find.byKey(const Key('wd_saving_overlay')), findsOneWidget, reason: 'while PIA has not answered');

    pia.regions.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  // The reason this screen is a page and not a Dialog (418). As a card its height was wrong twice
  // over - 409 and again in 412 - and each time SAVE and the spinner that replaces it sat below a
  // fold that would not scroll, so a save looked like nothing had happened. A shrink-wrapping
  // SingleChildScrollView inside an unbounded card has no overflow to scroll; AppScaffold gives it
  // a bounded viewport instead, which is a property rather than an arithmetic result.
  group('a long form on a small screen', () {
    testWidgets('scrolls, rather than overflowing, and SAVE can be reached', (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      // A RenderFlex overflow would surface here, and did whenever the card was sized wrongly.
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('wd_save')));
      await tester.pumpAndSettle();
      final save = tester.getRect(find.byKey(const Key('wd_save')));
      expect(save.bottom, lessThanOrEqualTo(560.0), reason: 'SAVE ends up on screen, not below the fold');
      expect(save.top, greaterThanOrEqualTo(0.0));
    });

    // Fixed in 409, back in 412, fixed again in 425, back again in 435. Every one of those fixes
    // scrolled the SAVE button into view after waiting for the keyboard, and every one of them was
    // a race that one early frame could lose. The STRUCTURAL property is what cannot regress: the
    // spinner does not live in the scroll view, so it has no fold to be below. Put it back inside
    // the SAVE button and it gains a Scrollable ancestor, and this fails.
    testWidgets('the saving spinner is not in the scroll view and covers the screen', (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      // A connect that never returns holds the dialog in its busy state to be inspected. The load
      // on entry goes through the same path a save does, and sets the same flag.
      final held = Completer<SSHClient>();
      addTearDown(() => held.complete(ssh));
      await tester.pumpWidget(_host(ssh, c, connect: () => held.future));
      // pump, not pumpAndSettle: the spinner animates forever, which is the point of it.
      await tester.pump();

      // The SAVE button never turns into a spinner; its label stays put underneath.
      expect(find.text('SAVE & DEPLOY'), findsOneWidget);
      final overlay = find.byKey(const Key('wd_saving_overlay'));
      expect(overlay, findsOneWidget, reason: 'a save shows a progress overlay');
      expect(
        find.ancestor(of: overlay, matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'in a scroll view it can be below the fold, which is this bug, four times over',
      );
      expect(tester.getRect(overlay), const Rect.fromLTWH(0, 0, 360, 560));
      expect(find.descendant(of: overlay, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text(ApplyingPanel.message), findsNothing, reason: 'reading the router is not applying (ID-246)');
    });

    // ID-246: a deploy can take a minute, and a bare spinner gave no hint that leaving would matter.
    testWidgets('SAVE & DEPLOY says "do not leave this screen", and back is blocked until it ends', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      // The load on entry connects at once; the deploy's connect is held, to look at the screen mid-save.
      final held = Completer<SSHClient>();
      addTearDown(() => held.complete(ssh));
      var connects = 0;
      await tester.pumpWidget(_host(ssh, c, connect: () => ++connects == 1 ? Future.value(ssh) : held.future));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('wd_save')));
      await tester.tap(find.byKey(const Key('wd_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump();

      final panel = find.text(ApplyingPanel.message);
      expect(panel, findsOneWidget);
      final scope = tester.widget<PopScope>(find.ancestor(of: panel, matching: find.byType(PopScope)).first);
      expect(scope.canPop, isFalse, reason: 'back must not leave mid-deploy');
    });
    testWidgets('is a page, so it does not carry a Dialog of its own', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      // AppScaffold's own scroll view, bounded by an Expanded - the thing the card never had.
      expect(find.byType(AppScaffold), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  testWidgets('renders title, status and configuration fields; no DISABLE/VIEW LOG buttons', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    // The heading names the region as well, the same shape the EDIT modal and the logs use.
    expect(find.text('WATCHDOG · wgc1:aus_melbourne'), findsOneWidget);
    expect(find.byKey(const Key('wd_primary')), findsOneWidget);
    expect(find.byKey(const Key('wd_save')), findsOneWidget);
    // The region is chosen on the form, so SAVE deploys, and the label says so.
    expect(find.text('SAVE & DEPLOY'), findsOneWidget);
    // DISABLE / VIEW LOG are now slot-modal actions, not part of EDIT.
    expect(find.text('DISABLE'), findsNothing);
    expect(find.text('VIEW LOG'), findsNothing);
  });

  // ID-144: the note blamed "DNS on this router" when the address was this tunnel's own DNS.
  testWidgets("the DoH note names the tunnel's own DNS as the clash, and says nothing without one", (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();
    String note() => tester.widget<Text>(find.byKey(const Key('wd_doh_note'))).data!;

    await tester.enterText(find.widgetWithText(TextFormField, 'DNS servers'), '9.9.9.9, 149.112.112.112');
    await tester.enterText(find.byKey(const Key('wd_doh_ip')), '9.9.9.9');
    await tester.pump();
    expect(note(), startsWith("This address is also this tunnel's DNS server"));
    expect(note(), isNot(contains('on this router')));

    await tester.enterText(find.widgetWithText(TextFormField, 'DNS servers'), '8.8.8.8');
    await tester.pump();
    expect(note(), startsWith('The watchdog resolves PIA'));
  });

  // ID-221: two addresses in the field were compared as one string, so neither was ever flagged; and
  // only this slot's DNS was checked, when another tunnel's DNS carries the lookups just the same.
  testWidgets("the DoH note checks each address against this slot's and every other slot's DNS", (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, otherSlotDns: {2: '76.76.10.1', 5: '9.9.9.9'}));
    await tester.pumpAndSettle();
    String note() => tester.widget<Text>(find.byKey(const Key('wd_doh_note'))).data!;

    await tester.enterText(find.widgetWithText(TextFormField, 'DNS servers'), '1.1.1.1, 76.76.2.1');
    await tester.enterText(find.byKey(const Key('wd_doh_ip')), '76.76.10.1, 76.76.2.1');
    await tester.pump();
    expect(note(), startsWith("This address is also this tunnel's DNS server"), reason: 'the second address matches');

    await tester.enterText(find.widgetWithText(TextFormField, 'DNS servers'), '1.1.1.1');
    await tester.pump();
    expect(note(), startsWith('wgc2 uses this address for DNS'));

    await tester.enterText(find.byKey(const Key('wd_doh_ip')), '76.76.10.1,9.9.9.9');
    await tester.pump();
    expect(note(), startsWith('wgc2 and wgc5 use this address for DNS'));

    await tester.enterText(find.byKey(const Key('wd_doh_ip')), '76.76.2.1');
    await tester.pump();
    expect(note(), startsWith('The watchdog resolves PIA'));
  });

  // ID-170: "Something else" left the last resolver's URL and address in the fields.
  testWidgets('choosing Something else for the DoH resolver empties both fields', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wd_doh_url')), 'https://dns.quad9.net/dns-query');
    await tester.enterText(find.byKey(const Key('wd_doh_ip')), '9.9.9.9');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('wd_doh_choice')));
    await tester.tap(find.byKey(const Key('wd_doh_choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something else').last);
    await tester.pumpAndSettle();

    expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('wd_doh_url')), matching: find.byType(EditableText))).controller.text,
        isEmpty);
    expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('wd_doh_ip')), matching: find.byType(EditableText))).controller.text,
        isEmpty);
  });

  testWidgets('PIA fields pre-fill from the session login', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, piaUser: 'puser', piaPass: 'ppass'));
    await tester.pumpAndSettle();

    final userField = tester.widget<TextField>(find.byKey(const Key('wd_pia_user')));
    expect(userField.controller!.text, 'puser');
  });

  testWidgets('jq missing warns and disables SAVE', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    expect(find.textContaining('jq is not installed'), findsWidgets);
    final save = tester.widget<OutlinedButton>(find.byKey(const Key('wd_save')));
    expect(save.onPressed, isNull);
  });

  // Reported 2026-09-06: the prompt said "Overwrite wgc4?" and left the user to remember which
  // region that was. The delete prompts have named their slot since 404.
  testWidgets('the overwrite prompt names the region, not just the slot', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: false));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.text('Overwrite wgc1:aus_melbourne?'), findsOneWidget);
    expect(find.text('Overwrite wgc1?'), findsNothing);
    expect(find.textContaining('rebuilds the tunnel'), findsNothing, reason: 'the region is unchanged');

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  // The fault CREATE had, on this form (2026-09-14): a new region was written as a name while the old
  // server kept running. A region change is now a rebuild, and the prompt says what that costs.
  testWidgets('changing the region warns that the tunnel is rebuilt, then stops it and clears the old server',
      (tester) async {
    useMerlin();
    final c = _controller();
    addTearDown(c.dispose);
    var stopped = false;
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd == 'service "stop_wgc 1"; service start_vpnrouting0') stopped = true;
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
      if (cmd.contains('nvram get wgc1_enable')) return '1';
      if (cmd.contains('nvram get wgc1_desc')) return 'pia-aus_perth';
      if (cmd.contains('ip -o link show up')) return stopped ? '' : 'wgc1';
      if (cmd.contains('ping')) return 'OK';
      return '';
    });
    await tester.pumpWidget(_host(ssh, c, regionDesc: 'aus_perth'));
    await tester.pumpAndSettle();

    await tester.enterText(find.descendant(of: find.byType(RegionRow), matching: find.byType(TextFormField)), 'aus_melbourne');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.text('Overwrite wgc1:aus_perth?'), findsOneWidget);
    expect(find.textContaining('This rebuilds the tunnel on aus_melbourne'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    final stop = ssh.commands.indexOf('service "stop_wgc 1"; service start_vpnrouting0');
    final blank = ssh.commands.indexOf("nvram set wgc1_ppub=''");
    expect(stop, isNot(-1));
    expect(blank, greaterThan(stop));
    expect(ssh.ran("nvram set wgc1_desc='pia-aus_melbourne'"), isTrue);
  });

  testWidgets('save blocked with a batched error dialog when a required IP is empty', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: false));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('wd_primary')), '');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Primary ping IP is required'), findsOneWidget);
    expect(ssh.ran("nvram set wgc1_wd_primary_ip="), isFalse);
  });

  testWidgets('valid save on an enabled watchdog writes NVRAM and redeploys the script', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('which jq')) return '/opt/bin/jq';
        // Scoped to wgc1 so the one-active-at-a-time sweep doesn't see phantom watchdogs on 2-5.
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1'; // already enabled -> no region pick
        if (cmd.contains('nvram get wgc1_enable')) return '1';
        if (cmd.contains('ip -o link show up')) return 'wgc1';
        if (cmd.contains('ping')) return 'OK';
        return '';
      },
    );
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(ssh.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
    expect(ssh.ran("cat > '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);
    expect(ssh.ran('cru a watchdog_wgc1'), isTrue);
  });

  // 2026-10-01: with PIA's login service down, a deploy went ahead and took 87 seconds to fail on the
  // router, which asked the same service. Now the phone's own answer stops it first, CANCEL first.
  group("PIA's login service down", () {
    RecordingSSHClient router() => RecordingSSHClient(responder: (cmd) {
          if (cmd.contains('which jq')) return '/opt/bin/jq';
          if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
          if (cmd.contains('nvram get wgc1_enable')) return '1';
          if (cmd.contains('ip -o link show up')) return 'wgc1';
          if (cmd.contains('ping')) return 'OK';
          return '';
        });

    Future<void> save(WidgetTester tester, RecordingSSHClient ssh, SessionController c) async {
      await tester.pumpWidget(_host(ssh, c, pia: _DownPia()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wd_save')));
      await tester.tap(find.byKey(const Key('wd_save')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before touching the router, and CANCEL changes nothing', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = router();
      await save(tester, ssh, c);
      expect(find.text("PIA's login service isn't answering"), findsOneWidget);
      await tester.tap(find.byKey(const Key('watchdog_pia_down_cancel')));
      await tester.pumpAndSettle();
      expect(ssh.commands.where((x) => x.startsWith('nvram set') || x.contains('cru a')), isEmpty);
      expect(c.log.last.message, contains('Not deployed: PIA'));
    });

    testWidgets('says what DEPLOY ANYWAY will do: retry on a slot with a tunnel, empty again on an empty one',
        (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await save(tester, router(), c);
      expect(find.textContaining('keeps trying on its schedule'), findsOneWidget);
      await tester.tap(find.byKey(const Key('watchdog_pia_down_cancel')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(router(), c, pia: _DownPia(), slotIsEmpty: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wd_save')));
      await tester.tap(find.byKey(const Key('wd_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('wgc1 is empty again'), findsOneWidget);
      expect(find.textContaining('keeps trying on its schedule'), findsNothing);
    });

    testWidgets('DEPLOY ANYWAY goes on as before', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = router();
      await save(tester, ssh, c);
      await tester.tap(find.byKey(const Key('watchdog_pia_down_deploy')));
      await tester.pumpAndSettle();
      expect(ssh.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
      expect(ssh.ran('cru a watchdog_wgc1'), isTrue);
    });
  });

  // ID-300: a wrong SMTP password was noticed only because it was wrong on purpose. The deploy
  // finished normally, and "Email FAILED" was in the router's log alone.
  testWidgets("a deploy whose alert email failed says so in a popup, and the form stays open", (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('which jq')) return '/opt/bin/jq';
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
        if (cmd.contains('nvram get wgc1_enable')) return '1';
        if (cmd.contains('ip -o link show up')) return 'wgc1';
        if (cmd.contains('ping')) return 'OK';
        if (cmd.startsWith('tail -n +') && cmd.contains('watchdog_wgc1.log')) {
          return '2026-01-01 10:00:05 Email FAILED (mailer exit=1) stderr=[ERROR: 535 5.7.8 Username and Password not accepted.|]';
        }
        return '';
      },
    );
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('could not be sent: 535 5.7.8 Username and Password not accepted. Check the email settings'),
        findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wd_save')), findsOneWidget, reason: 'the form stays open to fix the email settings');
    expect(tester.testTextInput.log.where((m) => m.method == 'TextInput.finishAutofillContext' && m.arguments == true),
        isEmpty, reason: 'the SMTP login may be what is wrong: nothing is offered for saving');
  });

  // ID-327: a first run that found no internet on the WAN exits 0 having done nothing, and the form
  // closed as if the watchdog were proved. It says so in a popup now, not only in the app log.
  testWidgets('a deploy whose first run did nothing says so in a popup, and never "deployed"', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('which jq')) return '/opt/bin/jq';
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
        if (cmd.contains('nvram get wgc1_enable')) return '1';
        if (cmd.contains('ip -o link show up')) return 'wgc1';
        if (cmd.contains('ping')) return 'OK';
        if (cmd.startsWith('tail -n +') && cmd.contains('watchdog_wgc1.log')) {
          return '2026-01-01 10:00:05 no Internet on WAN interface, exiting.';
        }
        return '';
      },
    );
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('The watchdog is scheduled, but its first run found no internet on the WAN'), findsOneWidget);
    expect(c.log.where((e) => e.message.contains('Watchdog deployed')), isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  // ID-255: the warning reached only the app, not ROUTER LOG where the rest of the deploy is recorded.
  testWidgets('an unreachable check target is written to ROUTER LOG, and the save goes on', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('which jq')) return '/opt/bin/jq';
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '1';
        if (cmd.contains('nvram get wgc1_enable')) return '1';
        if (cmd.contains('ip -o link show up')) return 'wgc1';
        if (cmd.contains('ping')) return cmd.contains('1.1.1.1') ? 'OK' : 'FAIL';
        return '';
      },
    );
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    // The Applying panel's spinner runs behind the warning, so the screen never settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('The settings will still be saved.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final logged = ssh.commands.where((cmd) => cmd.startsWith('logger') && cmd.contains('Primary IP 8.8.8.8 is not reachable'));
    expect(logged, hasLength(1));
    expect(logged.single, contains('Saving anyway.'));
    expect(ssh.commands.where((cmd) => cmd.startsWith('logger') && cmd.contains('Secondary IP')), isEmpty);
    expect(ssh.ran("cat > '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);
  });

  testWidgets('save on a disabled empty slot deploys the region chosen on the form', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('which jq')) return '/opt/bin/jq';
        if (cmd.contains('cru l') && cmd.contains('watchdog_wgc1')) return '0'; // disabled -> region selection
        if (cmd.contains('nvram get wgc1_enable')) return '0';
        if (cmd.contains('ip -o link show up')) return '';
        if (cmd.contains('ping')) return 'OK';
        return '';
      },
    );
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true));
    await tester.pumpAndSettle();

    // The region is on the form, chosen with everything else, so SAVE & DEPLOY goes straight on.
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing, reason: 'no picker arriving after SAVE');

    expect(ssh.ran("nvram set wgc1_desc='pia-aus_melbourne'"), isTrue); // same prefix as MANAGE
    expect(ssh.ran("cat > '/jffs/cfg-pia-wg/watchdog_wgc1.sh'"), isTrue);

    // Empty-slot create is enabled immediately; no reminder dialog is shown.
    expect(find.text('Watchdog configured'), findsNothing);
    // Exactly once: deployWatchdog brings the slot up, and the dialog used to do it again
    // afterwards - a second restart that bounced the tunnel the deploy had just established.
    expect(ssh.commands.where((cmd) => cmd.contains('nvram set wgc1_enable=1')), hasLength(1));
  });

  testWidgets('test email sends with the supplied SMTP settings', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_email_switch')));
    await tester.tap(find.byKey(const Key('wd_email_switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wd_from')), 'f@x.com');
    await tester.enterText(find.byKey(const Key('wd_to')), 't@x.com');
    await tester.enterText(find.byKey(const Key('wd_subject')), 'Subj');
    await tester.enterText(find.byKey(const Key('wd_smtp_server')), 'smtp.x.com:465');
    await tester.enterText(find.byKey(const Key('wd_smtp_user')), 'su');
    await tester.enterText(find.byKey(const Key('wd_smtp_pass')), 'sp');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_test_email')));
    await tester.tap(find.byKey(const Key('wd_test_email')));
    await tester.pumpAndSettle();

    expect(ssh.ran('/usr/sbin/sendmail'), isTrue);
    expect(ssh.ran('TEST email'), isTrue, reason: 'the subject says what kind of mail this is');
    // ID-049: the router answers nothing for wgc1_desc here, as before a first deploy; the region comes from the form.
    expect(ssh.ran('TEST email - wgc1:pia-aus_melbourne'), isTrue, reason: 'the region on the form, like the deployed email');
  });

  // ID-050: typing six email fields for every watchdog is tedious, and some autofill providers will not fill
  // several at once. The form starts from the slot's own, then the session's, then the lowest other slot's.
  group('the email fields pre-fill', () {
    const slot3 = '3\temail_from\tme@x.com\n3\temail_to\tyou@x.com\n3\temail_subject\tMy prefix\n'
        '3\tsmtp_server\tmail.x.com:587\n3\tsmtp_user\tu3\n3\tsmtp_pass\tp3\n'
        '5\temail_from\tother@x.com\n5\tsmtp_server\tother.x.com:465\n5\temail_to\tother@x.com\n';

    String Function(String) router({Map<String, String> own = const {}, String others = ''}) => (cmd) {
          if (cmd.contains('which jq')) return '/opt/bin/jq';
          if (cmd.startsWith('for s in 1 2 3 4 5')) return others;
          for (final e in own.entries) {
            if (cmd == 'nvram get wgc1_wd_${e.key}') return e.value;
          }
          return '';
        };

    Future<void> open(WidgetTester tester, RecordingSSHClient ssh, SessionController c) async {
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();
      // The fields show once email is switched on; the switch is the user's to flip.
      await tester.ensureVisible(find.byKey(const Key('wd_email_switch')));
      await tester.tap(find.byKey(const Key('wd_email_switch')));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester, String key) =>
        tester.widget<EditableText>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText))).controller.text;

    List<String> form(WidgetTester tester) =>
        [for (final k in ['wd_from', 'wd_to', 'wd_subject', 'wd_smtp_server', 'wd_smtp_user', 'wd_smtp_pass']) field(tester, k)];

    testWidgets("an empty slot takes the lowest-numbered other slot's, every field", (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: router(others: slot3));
      await open(tester, ssh, c);

      expect(form(tester), ['me@x.com', 'you@x.com', 'My prefix', 'mail.x.com:587', 'u3', 'p3']);
      expect(ssh.commands.where((cmd) => cmd.startsWith('for s in 1 2 3 4 5')), hasLength(1), reason: 'one round trip');
    });

    testWidgets('settings entered this session come before other slots', (tester) async {
      final c = _controller()
        ..watchdogEmail = const EmailSettings(
            from: 's@x.com', to: 'session@x.com', subject: 'Session', smtpServer: 'session.x.com:465', smtpUser: 'su', smtpPass: 'sp');
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: router(others: slot3));
      await open(tester, ssh, c);

      expect(form(tester), ['s@x.com', 'session@x.com', 'Session', 'session.x.com:465', 'su', 'sp']);
      expect(ssh.ran('for s in 1 2 3 4 5'), isFalse, reason: 'no need to read the other slots');
    });

    testWidgets("a slot with its own settings always shows its own", (tester) async {
      final c = _controller()..watchdogEmail = const EmailSettings(to: 'session@x.com', smtpServer: 'session.x.com:465');
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(
        responder: router(own: {
          'email_from': 'own@x.com',
          'email_to': 'own@x.com',
          'email_subject': 'Own',
          'smtp_server': 'own.x.com:465',
          'smtp_user': 'ou',
          'smtp_pass': 'op',
        }, others: slot3),
      );
      await open(tester, ssh, c);

      expect(form(tester), ['own@x.com', 'own@x.com', 'Own', 'own.x.com:465', 'ou', 'op']);
      expect(ssh.ran('for s in 1 2 3 4 5'), isFalse);
    });

    testWidgets('with none anywhere the fields are blank, and the subject keeps its default', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await open(tester, RecordingSSHClient(responder: router()), c);

      expect(form(tester), ['', '', 'cfg-pia-wg alert', '', '', '']);
    });

    testWidgets('what is on the form when it closes is kept for the next one', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await open(tester, RecordingSSHClient(responder: router()), c);
      await tester.enterText(find.byKey(const Key('wd_to')), 't@x.com');
      await tester.enterText(find.byKey(const Key('wd_smtp_server')), 'smtp.x.com:465');
      await tester.enterText(find.byKey(const Key('wd_smtp_pass')), 'secret pass');
      await tester.pumpWidget(const SizedBox());

      expect(c.watchdogEmail, isNotNull);
      expect(c.watchdogEmail!.to, 't@x.com');
      expect(c.watchdogEmail!.smtpServer, 'smtp.x.com:465');
      expect(c.watchdogEmail!.smtpPass, 'secret pass', reason: 'passwords are not trimmed');
    });
  });

  // The region is on the form, as it is on STANDALONE, rather than a picker arriving after SAVE.
  testWidgets("the region is chosen on the form, pre-filled with the slot's own", (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    final field = find.descendant(of: find.byType(RegionRow), matching: find.byType(TextFormField));
    expect(field, findsOneWidget);
    expect(tester.widget<TextFormField>(field).controller!.text, 'aus_melbourne');
  });

  testWidgets('a region PIA does not have is refused before anything reaches the router', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.descendant(of: find.byType(RegionRow), matching: find.byType(TextFormField)), 'nowhere_at_all');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('"nowhere_at_all" is not a PIA WireGuard region'), findsOneWidget);
    expect(ssh.ran('nvram set wgc1_desc'), isFalse);
  });

  // ID-202: a made-up region was reported only once every field below it was right.
  testWidgets('a bad region and a bad field below it are reported together, region first', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.descendant(of: find.byType(RegionRow), matching: find.byType(TextFormField)), 'nowhere_at_all');
    await tester.enterText(find.byKey(const Key('wd_primary')), '');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    final region = find.textContaining('"nowhere_at_all" is not a PIA WireGuard region');
    final ip = find.textContaining('Primary ping IP is required');
    expect(region, findsOneWidget);
    expect(ip, findsOneWidget);
    expect(tester.getTopLeft(region).dy, lessThan(tester.getTopLeft(ip).dy), reason: 'in the order of the form');
  });

  testWidgets('an empty region asks for one', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.descendant(of: find.byType(RegionRow), matching: find.byType(TextFormField)), '');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Choose a region first.'), findsOneWidget);
    expect(ssh.ran('nvram set wgc1_desc'), isFalse);
  });

  group('stock firmware', () {
    testWidgets('jq is probed at the install path and SAVE stays live when it is there', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: _stockReady);
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(ssh.ran("[ -x '$kStockJqPath' ]"), isTrue);
      expect(ssh.ran('which jq'), isFalse);
      expect(find.textContaining('is not installed'), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wd_save'))).onPressed, isNotNull);
    });

    // Without /opt/etc/init.d a watchdog deploys, runs, and then loses its cron entries at the
    // next reboot with nothing said. Blocked rather than warned about, because a watchdog that
    // stops at the next power cut is worse than one never deployed.
    testWidgets("no Download Master directory blocks SAVE and says why in the user's terms", (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      // jq is there; the init directory is not.
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains(kStockJqPath) ? '1' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(ssh.ran("[ -d '$kStockBootDir' ]"), isTrue, reason: 'the directory has to be probed');
      expect(find.byKey(const Key('wd_boot_dir_missing')), findsOneWidget);
      expect(find.textContaining('Download Master is not installed'), findsWidgets,
          reason: 'named as the cause, not as a missing path');
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wd_save'))).onPressed, isNull);
    });

    testWidgets('Merlin is never asked about it', (tester) async {
      useMerlin();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/usr/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(ssh.ran("[ -d '$kStockBootDir' ]"), isFalse, reason: 'Merlin uses services-start');
      expect(find.byKey(const Key('wd_boot_dir_missing')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wd_save'))).onPressed, isNotNull);
    });

    testWidgets('a missing jq names the stock path in the banner', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (_) => '0');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(find.textContaining('$kStockJqPath is not installed'), findsWidgets);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wd_save'))).onPressed, isNull);
    });

    testWidgets('TEST EMAIL goes through mailsend-go', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: _stockReady);
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('wd_email_switch')));
      await tester.tap(find.byKey(const Key('wd_email_switch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('wd_from')), 'f@x.com');
      await tester.enterText(find.byKey(const Key('wd_to')), 't@x.com');
      await tester.enterText(find.byKey(const Key('wd_subject')), 'Subj');
      await tester.enterText(find.byKey(const Key('wd_smtp_server')), 'smtp.x.com:465');
      await tester.enterText(find.byKey(const Key('wd_smtp_user')), 'su');
      await tester.enterText(find.byKey(const Key('wd_smtp_pass')), 'sp');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('wd_test_email')));
      await tester.tap(find.byKey(const Key('wd_test_email')));
      await tester.pumpAndSettle();

      expect(ssh.ran(kStockMailsendPath), isTrue);
      expect(ssh.ran('/usr/sbin/sendmail'), isFalse);
    });

    // ID-225, decided 2026-09-26: a delivered test email proves the SMTP login, so the password
    // manager is offered it then, as it is after a deploy. One that fails offers nothing.
    for (final delivered in [true, false]) {
      testWidgets('a ${delivered ? 'delivered' : 'failed'} test email ${delivered ? 'offers' : 'does not offer'} the login for saving',
          (tester) async {
        useStock();
        final c = _controller();
        addTearDown(c.dispose);
        final ssh = RecordingSSHClient(
            responder: (cmd) => cmd.contains('EXITCODE') ? 'EXITCODE:${delivered ? 0 : 1}' : _stockReady(cmd));
        await tester.pumpWidget(_host(ssh, c));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('wd_email_switch')));
        await tester.tap(find.byKey(const Key('wd_email_switch')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('wd_from')), 'f@x.com');
        await tester.enterText(find.byKey(const Key('wd_to')), 't@x.com');
        await tester.enterText(find.byKey(const Key('wd_subject')), 'Subj');
        await tester.enterText(find.byKey(const Key('wd_smtp_server')), 'smtp.x.com:465');
        await tester.enterText(find.byKey(const Key('wd_smtp_user')), 'su');
        await tester.enterText(find.byKey(const Key('wd_smtp_pass')), 'sp');
        await tester.pumpAndSettle();
        tester.testTextInput.log.clear();

        await tester.ensureVisible(find.byKey(const Key('wd_test_email')));
        await tester.tap(find.byKey(const Key('wd_test_email')));
        await tester.pumpAndSettle();

        final saves = tester.testTextInput.log.where((m) => m.method == 'TextInput.finishAutofillContext' && m.arguments == true);
        expect(saves, delivered ? isNotEmpty : isEmpty);
      });
    }
  });

  group('PIA credential retention', () {
    testWidgets('typed PIA credentials are retained in the session when the dialog closes', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, c, piaUser: '', piaPass: ''));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('wd_pia_user')), 'p9999999');
      await tester.enterText(find.byKey(const Key('wd_pia_pass')), 'typedpass');
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox()); // CLOSE / dismiss disposes the dialog
      await tester.pumpAndSettle();

      expect(c.piaUsername, 'p9999999');
      expect(c.piaPassword, 'typedpass');
    });

    testWidgets('PIA credentials recovered from NVRAM land in the session', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('which jq')) return '/opt/bin/jq';
          if (cmd.contains('nvram get cfg_pia_wg_user')) return 'p7654321';
          if (cmd.contains('nvram get cfg_pia_wg_password')) return 'nvrampass';
          return '';
        },
      );
      await tester.pumpWidget(_host(ssh, c, piaUser: '', piaPass: ''));
      await tester.pumpAndSettle();

      expect(c.piaUsername, 'p7654321');
      expect(c.piaPassword, 'nvrampass');
    });

    testWidgets('closing with a blank field does not discard a known credential', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, c, piaUser: 'keepme', piaPass: 'keeppass'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('wd_pia_user')), '');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(c.piaUsername, 'keepme');
    });
  });
}
