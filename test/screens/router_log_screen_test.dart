// test/screens/router_log_screen_test.dart - the router's own syslog, in the app.
//
// Every alert email and half the failure messages end with "check your router log", which used to
// mean leaving the app for an SSH client or the web interface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/screens/router_log_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';

import '../watchdog_test_utils.dart';

const _log = 'Sep 10 09:00:01 kernel: first line\n'
    'Sep 10 09:00:02 cfg-pia-wg: wgc1: Watchdog started for wgc1\n'
    'Sep 10 09:00:03 kernel: last line';

Future<RecordingSSHClient> _pump(WidgetTester tester, {String reply = _log}) async {
  final ssh = RecordingSSHClient(responder: (_) => reply);
  final c = SessionController(tickInterval: const Duration(hours: 1))
    ..routerIp = '192.168.1.1'
    ..sshUsername = 'admin'
    ..sshPassword = 'pw'
    ..routerConnected = true;
  addTearDown(c.dispose);
  await tester.pumpWidget(MaterialApp(
    home: SessionScope(
      controller: c,
      child: Scaffold(body: RouterLogScreen(testClientFactory: (_, __, ___) async => ssh)),
    ),
  ));
  await tester.pumpAndSettle();
  return ssh;
}

void main() {
  testWidgets('reads the log on entry, without waiting to be asked', (tester) async {
    final ssh = await _pump(tester);

    expect(ssh.commands.any((c) => c.contains('/tmp/syslog.log')), isTrue);
    expect(find.textContaining('Watchdog started for wgc1'), findsOneWidget);
  });

  // A syslog runs to megabytes after an uptime of weeks, and everything above the last few hundred
  // lines is scrollback nobody reads on a phone.
  testWidgets('tails rather than reading the whole file', (tester) async {
    final ssh = await _pump(tester);
    expect(ssh.commands.firstWhere((c) => c.contains('syslog.log')), startsWith('tail -n '));
  });

  testWidgets('REFRESH re-reads it', (tester) async {
    final ssh = await _pump(tester);
    final before = ssh.commands.where((c) => c.contains('syslog.log')).length;

    await tester.tap(find.byKey(const Key('router_log_refresh')));
    await tester.pumpAndSettle();

    expect(ssh.commands.where((c) => c.contains('syslog.log')).length, before + 1);
  });

  // Selectable so a line can be pasted into a bug report, and NOT through the clipboard countdown:
  // a log is not a credential, and arming the 60s auto-clear would wipe what was just copied.
  testWidgets('the text is selectable', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('router_log_text')), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('router_log_text'))).data, contains('last line'));
  });

  testWidgets('an empty log says so rather than showing nothing', (tester) async {
    await _pump(tester, reply: '');
    expect(tester.widget<SelectableText>(find.byKey(const Key('router_log_text'))).data, contains('empty'));
  });

  testWidgets('carries REFRESH and HOME, in that order', (tester) async {
    await _pump(tester);
    final refresh = tester.getCenter(find.byKey(const Key('router_log_refresh')));
    final home = tester.getCenter(find.byKey(const Key('router_log_home')));
    expect(refresh.dy, home.dy, reason: 'one row');
    expect(refresh.dx, lessThan(home.dx));
  });
}
