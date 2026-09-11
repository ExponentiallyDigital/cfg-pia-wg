// test/watchdog_dialog_test.dart - widget tests for the watchdog EDIT dialog (save-redeploy).
import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/watchdog_dialog.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';

import 'watchdog_test_utils.dart';

class _FakePia extends PiaService {
  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async => const [
        Region(
          id: 'aus_melbourne',
          wgServers: [WgServer(ip: '1.2.3.4', cn: 'aus')],
        ),
      ];
}

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Widget _host(
  RecordingSSHClient client,
  SessionController c, {
  bool slotIsEmpty = false,
  String piaUser = 'p1234567',
  String piaPass = 'secret',
  Future<SSHClient> Function()? connect,
}) {
  return SessionScope(
    controller: c,
    child: MaterialApp(
      home: Scaffold(
        body: WatchdogDialog(
          slotIndex: 1,
          regionDesc: 'aus_melbourne',
          slotIsEmpty: slotIsEmpty,
          controller: c,
          piaUsername: piaUser,
          piaPassword: piaPass,
          connect: connect ?? () async => client,
          piaService: _FakePia(),
          serviceFactory: (cl) => RouterWatchdog(cl, onLog: c.onLog),
        ),
      ),
    ),
  );
}

void main() {
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
      expect(find.text('SAVE & SELECT REGION'), findsOneWidget);
      final overlay = find.byKey(const Key('wd_saving_overlay'));
      expect(overlay, findsOneWidget, reason: 'a save shows a progress overlay');
      expect(
        find.ancestor(of: overlay, matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'in a scroll view it can be below the fold, which is this bug, four times over',
      );
      expect(tester.getRect(overlay), const Rect.fromLTWH(0, 0, 360, 560));
      expect(find.descendant(of: overlay, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
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
    // SAVE is not the end of the flow - a region picker follows it, and the label says so.
    expect(find.text('SAVE & SELECT REGION'), findsOneWidget);
    // DISABLE / VIEW LOG are now slot-modal actions, not part of EDIT.
    expect(find.text('DISABLE'), findsNothing);
    expect(find.text('VIEW LOG'), findsNothing);
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
    final save = tester.widget<ElevatedButton>(find.byKey(const Key('wd_save')));
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

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
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

  testWidgets('save on a disabled empty slot picks a region and writes wgcN_desc', (tester) async {
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

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    // Region picker (fake PiaService) appears; choose the region.
    expect(find.text('aus_melbourne'), findsWidgets);
    await tester.tap(find.text('aus_melbourne').last);
    await tester.pumpAndSettle();

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
  });

  group('stock firmware', () {
    testWidgets('jq is probed at the install path and SAVE stays live when it is there', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains(kStockJqPath) ? '1' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(ssh.ran("[ -x '$kStockJqPath' ]"), isTrue);
      expect(ssh.ran('which jq'), isFalse);
      expect(find.textContaining('is not installed'), findsNothing);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('wd_save'))).onPressed, isNotNull);
    });

    testWidgets('a missing jq names the stock path in the banner', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (_) => '0');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

      expect(find.textContaining('$kStockJqPath is not installed'), findsWidgets);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('wd_save'))).onPressed, isNull);
    });

    testWidgets('TEST EMAIL goes through mailsend-go', (tester) async {
      useStock();
      final c = _controller();
      addTearDown(c.dispose);
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains(kStockJqPath) ? '1' : '');
      await tester.pumpWidget(_host(ssh, c));
      await tester.pumpAndSettle();

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
