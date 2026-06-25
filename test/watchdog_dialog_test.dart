// test/watchdog_dialog_test.dart - widget tests for the watchdog EDIT dialog (save-not-deploy).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cfg_pia_wireguard/pia_service.dart';
import 'package:cfg_pia_wireguard/router_watchdog.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';
import 'package:cfg_pia_wireguard/watchdog_dialog.dart';

import 'watchdog_test_utils.dart';

class _FakePia extends PiaService {
  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async => const [
        Region(id: 'aus_melbourne', wgServers: [WgServer(ip: '1.2.3.4', cn: 'aus')])
      ];
}

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Widget _host(
  RecordingSSHClient client,
  SessionController c, {
  bool slotIsEmpty = false,
  String piaUser = 'p1234567',
  String piaPass = 'secret',
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
          connect: () async => client,
          piaService: _FakePia(),
          serviceFactory: (cl) => RouterWatchdog(cl, onLog: c.onLog),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders title, status and configuration fields; no DISABLE/VIEW LOG buttons', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG · wgc1'), findsOneWidget);
    expect(find.byKey(const Key('wd_primary')), findsOneWidget);
    expect(find.byKey(const Key('wd_save')), findsOneWidget);
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

  testWidgets('valid save on an enabled watchdog writes NVRAM but does NOT deploy', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('cru l')) return '1'; // already enabled -> no region pick
      if (cmd.contains('ping')) return 'OK';
      return '';
    });
    await tester.pumpWidget(_host(ssh, c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(ssh.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
    expect(ssh.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isFalse); // not deployed
    expect(ssh.ran('cru a watchdog_wgc1'), isFalse);
  });

  testWidgets('save on a disabled empty slot picks a region and writes wgcN_desc', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    final ssh = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('cru l')) return '0'; // disabled -> region selection
      if (cmd.contains('ping')) return 'OK';
      return '';
    });
    await tester.pumpWidget(_host(ssh, c, slotIsEmpty: true));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    // Region picker (fake PiaService) appears; choose the region.
    expect(find.text('aus_melbourne'), findsWidgets);
    await tester.tap(find.text('aus_melbourne').last);
    await tester.pumpAndSettle();

    expect(ssh.ran("nvram set wgc1_desc='aus_melbourne'"), isTrue);
    expect(ssh.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isFalse); // still not deployed
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
    expect(ssh.ran('config test'), isTrue);
  });
}
