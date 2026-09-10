// test/screens/router_log_screen_test.dart - the router's own syslog, in the app.
//
// Every alert email and half the failure messages end with "check your router log", which used to
// mean leaving the app for an SSH client. The log reached 512 KB in a day on the maintainer's
// router and the firmware rotates it rather than truncating, so it is read in pages, newest first.
import 'package:cfg_pia_wg/router_log_paging.dart';
import 'package:cfg_pia_wg/screens/router_log_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _log = 'Sep 10 09:00:01 kernel: first line\n'
    'Sep 10 09:00:02 cfg-pia-wg: wgc1: Watchdog started for wgc1\n'
    'Sep 10 09:00:03 kernel: last line';

/// A router with a live log of [liveSize] bytes and a rotated one of [rotatedSize].
///
/// Page contents are synthetic - what matters is which bytes were ASKED for, and the screen has no
/// business caring what is in them.
RecordingSSHClient _router({String body = _log, int? liveSize, int rotatedSize = 0}) {
  final size = liveSize ?? body.length;
  return RecordingSSHClient(responder: (cmd) {
    if (cmd.contains('wc -c')) return '$size\n$rotatedSize';
    if (cmd.startsWith('tail -c')) return body;
    return '';
  });
}

Future<RecordingSSHClient> _pump(WidgetTester tester, {RecordingSSHClient? ssh}) async {
  final client = ssh ?? _router();
  final c = SessionController(tickInterval: const Duration(hours: 1))
    ..routerIp = '192.168.1.1'
    ..sshUsername = 'admin'
    ..sshPassword = 'pw'
    ..routerConnected = true;
  addTearDown(c.dispose);
  await tester.pumpWidget(MaterialApp(
    home: SessionScope(
      controller: c,
      child: Scaffold(body: RouterLogScreen(testClientFactory: (_, __, ___) async => client)),
    ),
  ));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  group('paging arithmetic', () {
    test('the first page is the LAST 32K of the live log', () {
      final page = nextLogPage(sizes: [100000, 0], consumed: [0, 0])!;
      expect(page.file, kRouterLogFiles.first);
      expect(page.fromEnd, 0);
      expect(page.length, kLogPageBytes);
      expect(page.reachesStart, isFalse);
      // The router does the seeking, so only one page crosses SSH however far back you scroll.
      expect(page.command, contains('tail -c $kLogPageBytes'));
      expect(page.command, contains('head -c $kLogPageBytes'));
    });

    test('the second page ends where the first began', () {
      final page = nextLogPage(sizes: [100000, 0], consumed: [kLogPageBytes, 0])!;
      expect(page.fromEnd, kLogPageBytes);
      expect(page.command, contains('tail -c ${kLogPageBytes * 2}'));
      expect(page.command, contains('head -c $kLogPageBytes'));
    });

    test('the last page of a file is short, and says it reaches the start', () {
      final page = nextLogPage(sizes: [40000, 0], consumed: [kLogPageBytes, 0])!;
      expect(page.length, 40000 - kLogPageBytes);
      expect(page.reachesStart, isTrue);
    });

    // The history a user wants can span two files: the firmware rotates rather than truncating.
    test('paging continues into the rotated log when the live one runs out', () {
      final page = nextLogPage(sizes: [40000, 90000], consumed: [40000, 0])!;
      expect(page.file, kRouterLogFiles[1]);
      expect(page.fromEnd, 0);
      expect(page.length, kLogPageBytes);
    });

    test('null when both files are exhausted', () {
      expect(nextLogPage(sizes: [40000, 9000], consumed: [40000, 9000]), isNull);
    });

    test('null when there is no log at all', () {
      expect(nextLogPage(sizes: [0, 0], consumed: [0, 0]), isNull);
    });

    test('a missing rotated log contributes nothing rather than an error', () {
      expect(parseLogSizes('12345\n0'), [12345, 0]);
      expect(parseLogSizes(''), [0, 0]);
      expect(buildLogSizesCommand(), contains(kRouterLogFiles[1]));
    });

    // Every page but the oldest starts mid-line, because the cut is a byte offset. Showing that
    // fragment puts half a timestamp at the top of the screen.
    test('the leading partial line is dropped, except at the start of a file', () {
      const page = 'g started for wgc1\nSep 10 09:00:03 kernel: last line';
      expect(trimPartialFirstLine(page, reachesStart: false), 'Sep 10 09:00:03 kernel: last line');
      expect(trimPartialFirstLine(page, reachesStart: true), page);
    });

    test('a page with no newline at all yields nothing rather than a fragment', () {
      expect(trimPartialFirstLine('no newline here', reachesStart: false), '');
    });
  });

  group('the screen', () {
    testWidgets('reads the newest page on entry, without waiting to be asked', (tester) async {
      final ssh = await _pump(tester);

      expect(ssh.commands.any((c) => c.contains('wc -c')), isTrue);
      expect(ssh.commands.any((c) => c.startsWith('tail -c')), isTrue);
      expect(find.textContaining('Watchdog started for wgc1'), findsOneWidget);
    });

    testWidgets('REFRESH starts again from the newest page', (tester) async {
      final ssh = await _pump(tester);
      final before = ssh.commands.where((c) => c.startsWith('tail -c')).length;

      await tester.tap(find.byKey(const Key('router_log_refresh')));
      await tester.pumpAndSettle();

      expect(ssh.commands.where((c) => c.startsWith('tail -c')).length, greaterThan(before));
    });

    // Android places its Copy/Share toolbar relative to the SELECTION, so on a full-height
    // selection it lands on these buttons - which is how a tap meant for Copy cleared the watchdog
    // log on 2026-09-10. An in-app copy removes the need for it.
    testWidgets('COPY takes everything loaded, without arming the clipboard countdown', (tester) async {
      final copied = <String>[];
      final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (t) async => copied.add(t))
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: RouterLogScreen(testClientFactory: (_, __, ___) async => _router())),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('router_log_copy')));
      await tester.pumpAndSettle();

      expect(copied.single, contains('last line'));
      expect(c.clipboardSeconds, 0, reason: 'a log is not a credential');
    });

    testWidgets('carries COPY, REFRESH and HOME in one row, in that order', (tester) async {
      await _pump(tester);
      final copy = tester.getCenter(find.byKey(const Key('router_log_copy')));
      final refresh = tester.getCenter(find.byKey(const Key('router_log_refresh')));
      final home = tester.getCenter(find.byKey(const Key('router_log_home')));

      expect(copy.dy, refresh.dy);
      expect(refresh.dy, home.dy);
      expect(copy.dx, lessThan(refresh.dx));
      expect(refresh.dx, lessThan(home.dx));
    });

    // Bordered, like every other button in the app. They were bare TextButtons and read as three
    // unrelated links.
    testWidgets('the buttons are bordered', (tester) async {
      await _pump(tester);
      for (final key in ['router_log_copy', 'router_log_refresh', 'router_log_home']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        expect(tester.widget<OutlinedButton>(find.byKey(Key(key))).style?.side, isNotNull, reason: key);
      }
    });

    testWidgets('an empty log says so rather than showing nothing', (tester) async {
      await _pump(tester, ssh: _router(body: '', liveSize: 0));
      expect(find.text('No log read yet.'), findsOneWidget);
    });
  });
}
