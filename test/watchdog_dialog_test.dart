// test/watchdog_dialog_test.dart - widget tests for the watchdog configuration dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pia_wireguard_cfga/router_watchdog.dart';
import 'package:pia_wireguard_cfga/watchdog_dialog.dart';

import 'watchdog_test_utils.dart';

void _noop(String m, {bool isError = false, bool isSuccess = false}) {}

Widget _host(
  RecordingSSHClient client, {
  void Function(String, {bool isError, bool isSuccess}) onLog = _noop,
  String piaUser = 'p1234567',
  String piaPass = 'secret',
}) {
  return MaterialApp(
    home: Scaffold(
      body: WatchdogDialog(
        slotIndex: 1,
        regionDesc: 'aus_melbourne',
        onLog: onLog,
        piaUsername: piaUser,
        piaPassword: piaPass,
        connect: () async => client,
        serviceFactory: (c) => RouterWatchdog(c, onLog: onLog),
      ),
    ),
  );
}

void main() {
  testWidgets('renders title, status and configuration fields', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG · wgc1'), findsOneWidget);
    expect(find.text('aus_melbourne'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.byKey(const Key('wd_primary')), findsOneWidget);
    expect(find.byKey(const Key('wd_secondary')), findsOneWidget);
    expect(find.byKey(const Key('wd_pia_user')), findsOneWidget);
  });

  testWidgets('PIA fields are pre-filled from the main-screen login', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(c, piaUser: 'puser', piaPass: 'ppass'));
    await tester.pumpAndSettle();

    final userField = tester.widget<TextField>(find.byKey(const Key('wd_pia_user')));
    expect(userField.controller!.text, 'puser');
  });

  testWidgets('enabled status shows the last successful ping', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('cru l')) return '1';
      if (cmd.contains('watchdog_last_ping_success_wgc1')) return '2026-06-19 14:30:00';
      return '';
    });
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.textContaining('Last successful ping: 2026-06-19'), findsOneWidget);
  });

  testWidgets('jq missing warns and disables SAVE', (tester) async {
    final logs = <String>[];
    final c = RecordingSSHClient(responder: (_) => ''); // which jq -> empty
    await tester.pumpWidget(_host(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)));
    await tester.pumpAndSettle();

    expect(find.textContaining('jq is not installed'), findsWidgets);
    expect(logs.any((m) => m.contains('jq is not installed')), isTrue);
    final save = tester.widget<ElevatedButton>(find.byKey(const Key('wd_save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('save is blocked and logged when a required IP is empty', (tester) async {
    final logs = <String>[];
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('wd_primary')), '');
    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(logs.any((m) => m.contains('Primary ping IP is required')), isTrue);
    expect(c.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isFalse);
  });

  testWidgets('valid save deploys the watchdog', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('ping')) return 'OK';
      return '';
    });
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(c.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isTrue);
    expect(c.ran('cru a watchdog_wgc1'), isTrue);
  });

  testWidgets('save blocked when email enabled but SMTP fields empty', (tester) async {
    final logs = <String>[];
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(c, onLog: (m, {isError = false, isSuccess = false}) => logs.add(m)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_email_switch')));
    await tester.tap(find.byKey(const Key('wd_email_switch')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_save')));
    await tester.tap(find.byKey(const Key('wd_save')));
    await tester.pumpAndSettle();

    expect(logs.any((m) => m.contains('SMTP server')), isTrue);
    expect(c.ran("cat > '/jffs/scripts/watchdog_wgc1.sh'"), isFalse);
  });

  testWidgets('test email sends with the supplied SMTP settings', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
    await tester.pumpWidget(_host(c));
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

    expect(c.ran('/usr/sbin/sendmail'), isTrue);
    expect(c.ran('config test'), isTrue);
    expect(c.ran('rm -f /tmp/mail.txt'), isTrue);
  });

  testWidgets('view log fetches and renders the log content', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('watchdog_wgc1.log')) return 'LOG-CONTENT-XYZ';
      return '';
    });
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_view_log')));
    await tester.tap(find.byKey(const Key('wd_view_log')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wd_log_text')), findsOneWidget);
    expect(find.textContaining('LOG-CONTENT-XYZ'), findsOneWidget);
  });

  testWidgets('disable removes the watchdog when currently enabled', (tester) async {
    final c = RecordingSSHClient(responder: (cmd) {
      if (cmd.contains('which jq')) return '/opt/bin/jq';
      if (cmd.contains('cru l')) return '1';
      return '';
    });
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('wd_disable')));
    await tester.tap(find.byKey(const Key('wd_disable')));
    await tester.pumpAndSettle();

    expect(c.ran('cru d watchdog_wgc1'), isTrue);
  });
}
