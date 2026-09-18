// test/screens/router_log_screen_test.dart - the router's own syslog, in the app.
//
// Every alert email and half the failure messages end with "check your router log", which used to
// mean leaving the app for an SSH client. The log reached 512 KB in a day on the maintainer's
// router and the firmware rotates it rather than truncating, so it is read in pages, newest first.
import 'package:cfg_pia_wg/app_colors.dart';
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
    // ID-099: an older page is inserted ABOVE what is on screen, so the reader has to stay where
    // they were relative to the newest line. Scrolling back many screens quickly used to throw the
    // view down by several screens instead - two loads ran at once, each correcting the offset for
    // its own insertion.
    testWidgets('an older page holds the reader where they were', (tester) async {
      // A log far bigger than one page, so there is always something older to fetch.
      final ssh = _router(body: List.filled(400, 'Sep 10 09:00:01 router: a line of syslog').join('\n'), liveSize: 400000);
      await _pump(tester, ssh: ssh);
      final before = ssh.commands.where((c) => c.startsWith('tail -c')).length;

      // Two scrolls to the top with no settle between them, which is what a fast flick produces:
      // the second arrives while the first load is still waiting on the router.
      final scroller = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).last).controller!;
      scroller.jumpTo(0);
      scroller.jumpTo(1);
      await tester.pumpAndSettle();

      final after = ssh.commands.where((c) => c.startsWith('tail -c')).length;
      expect(after - before, 1, reason: 'one page per load, however fast the scrolling');
      // Held: the offset moved down by what was added above, rather than staying at the top of the
      // newly-inserted page or jumping to an unrelated part of the log.
      // The reader was at the top of what had been loaded; the page arrives ABOVE that, so the
      // offset moves down by the height of the new page rather than staying at zero - which is
      // what "held" means here. It also has not been thrown to the bottom.
      expect(scroller.offset, greaterThan(0));
      expect(scroller.position.maxScrollExtent - scroller.offset, greaterThan(100),
          reason: 'still the same distance from the newest line');
    });

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

  group("telling our lines from the router's", () {
    // Both the app and the deployed watchdog write under the tag `cfg-pia-wg`; only the interface
    // prefix the script adds separates them. A page of syslog is otherwise a wall of identical
    // grey, and the lines worth reading are a handful among hundreds.
    test('a line with the tag and no interface prefix is the app', () {
      expect(classifyLogLine('Sep 11 12:00:01 router cfg-pia-wg: Laptop (192.168.1.20) -> wgc5 reassigned'),
          RouterLogSource.app);
    });

    test('the same tag with an interface prefix is the watchdog on the router', () {
      expect(classifyLogLine('Sep 11 12:00:01 router cfg-pia-wg: wgc1: Checking wgc1 connectivity'),
          RouterLogSource.watchdog);
    });

    test('a two-digit interface is still the watchdog', () {
      expect(classifyLogLine('cfg-pia-wg: wgc10: something'), RouterLogSource.watchdog);
    });

    test('everything else is the router itself', () {
      expect(classifyLogLine('Sep 11 12:00:01 router dropbear[123]: Password auth succeeded'), RouterLogSource.other);
      expect(classifyLogLine(''), RouterLogSource.other);
      expect(classifyLogLine('Sep 11 kernel: wgc1 is up'), RouterLogSource.other,
          reason: 'naming an interface is not the same as being tagged by us');
    });

    // Our errors in red. A firmware line that happens to say "failed" stays as it is.
    test('an error the app or the watchdog wrote is picked out', () {
      expect(isRouterLogError('Sep 11 12:00:01 router cfg-pia-wg: ERROR during deploy: timed out'), isTrue);
      expect(isRouterLogError('Sep 11 12:00:01 router cfg-pia-wg: Email FAILED (exit=1) stderr=[]'), isTrue);
      expect(isRouterLogError('cfg-pia-wg: wgc1: No handshake and both pings failed (9.9.9.9, 1.1.1.1)'), isTrue);
      expect(isRouterLogError('cfg-pia-wg: wgc1: Connectivity lost; reconfiguring (attempt #2)'), isTrue);
      expect(isRouterLogError('cfg-pia-wg: wgc1: Interface wgc1 is down or absent'), isTrue);
    });

    test('an ordinary line of ours is not an error, and neither is the firmware saying failed', () {
      expect(isRouterLogError('cfg-pia-wg: wgc1: Primary ping OK (9.9.9.9)'), isFalse);
      // ID-048: a deploy run's first check, on a slot whose tunnel is not built yet, is the starting state.
      expect(isRouterLogError('cfg-pia-wg: wgc1: Interface wgc1 is not up yet'), isFalse);
      expect(isRouterLogError('cfg-pia-wg: wgc1: Not connected yet: no handshake, and no answer from 9.9.9.9 or 1.1.1.1'), isFalse);
      expect(isRouterLogError('Sep 11 12:00:01 router cfg-pia-wg: Enabled wgc1:aus_melbourne'), isFalse);
      expect(isRouterLogError('Sep 11 12:00:01 router dnsmasq[1]: failed to access /tmp/x'), isFalse);
    });
  });

  // ID-034: the watchdog's lines were amber, which everywhere else in the app means a warning, so a healthy line looked
  // like a problem. They are lavender, apart from teal (the app), red (errors), amber and the plain text.
  group('line colours', () {
    test('the app teal, the watchdog lavender, errors red, the firmware plain', () {
      expect(routerLogLineColour('Sep 11 12:00:01 router cfg-pia-wg: Laptop (192.168.1.20) -> wgc5 reassigned'), kHighlight);
      expect(routerLogLineColour('cfg-pia-wg: wgc1: Handshake 25s ago'), kWatchdogText);
      expect(routerLogLineColour('cfg-pia-wg: wgc1: Connectivity lost; reconfiguring (attempt #2)'), kError);
      expect(routerLogLineColour('Sep 11 12:00:01 router dropbear[123]: Password auth succeeded'), isNull);
    });

    test('the watchdog colour is none of the others', () {
      expect({kWatchdogText, kHighlight, kError, kWarn, kText}, hasLength(5));
    });
  });
}
