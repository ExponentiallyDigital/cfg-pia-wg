// test/screens/about_screen_test.dart - About screen content + build-info channel fallback.
//
// The metadata rows are Text.rich, so every assertion on them needs findRichText: true --
// find.text() only inspects Text.data, which is null for a spanned Text.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/build_info_service.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/screens/about_screen.dart';
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/session_controller.dart';

import '../watchdog_test_utils.dart';


// Deliberately unmistakable values so a passing assertion cannot be a coincidence.
const _hostReply = <String, String>{
  'versionName': '9.9.9',
  'buildNumber': '999',
  'installer': 'Google Play',
  'buildTimestamp': '2026-07-29 03:34:57 UTC',
  'buildType': 'release',
  'commitHash': 'abc1234',
  'commitDate': '2026-07-29T04:23:09+10:00',
  'gitBranch': 'v9.9.9',
  'runnerId': '1234567890',
  'cpuAbi': 'arm64-v8a',
  'osVersion': 'Android 15 (API 35)',
  'compileSdk': '36',
  'kotlinVersion': '2.3.20',
};

/// In-memory stand-in for [RouterPrefs].
///
/// Installs [handler] as the native side of [buildInfoChannel] for the current test.
void _mockChannel(WidgetTester tester, Future<Object?>? Function(MethodCall)? handler) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(buildInfoChannel, handler);
  addTearDown(() => messenger.setMockMethodCallHandler(buildInfoChannel, null));
}

// The controller COPY BUILD INFO writes through. Its 1 Hz countdown tick is pushed far out so
// pumpAndSettle still settles.
SessionController _quietController() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Future<void> _pumpAbout(WidgetTester tester, {SessionController? controller}) async {
  // Scaffold mirrors production, where AppChrome supplies one above the Navigator; the COPY
  // confirmation snackbar needs it. SessionScope likewise - COPY BUILD INFO goes through the
  // controller so it can stand down a countdown a config copy left running.
  // A controller passed in belongs to the test, which disposes it inside the test body - the
  // binding checks for pending timers before tearDowns run, and an armed countdown has one.
  final c = controller ?? _quietController();
  if (controller == null) addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(home: SessionScope(controller: c, child: const Scaffold(body: AboutScreen()))),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Reported: "accessibility" appeared 16 times in the licences list. LicenseRegistry yields one
  // entry per licence TEXT, each naming every package it covers, so rendering entries directly
  // repeats a package once per distinct text.
  group('groupLicensesByPackage', () {
    LicenseEntry entry(List<String> packages, String text) => LicenseEntryWithLineBreaks(packages, text);
    // Notices are kept as paragraphs so indent survives; flatten them for readable assertions.
    List<String> texts(List<List<LicenseParagraph>> notices) => notices.map((n) => n.map((p) => p.text).join(' ')).toList();

    test('lists a package once however many entries name it', () {
      final grouped = groupLicensesByPackage([
        entry(['accessibility'], 'Copyright 2009 Chromium'),
        entry(['accessibility'], 'Copyright 2010 Chromium'),
        entry(['accessibility', 'angle', 'dart'], 'Copyright 2011 Chromium'),
        entry(['accessibility', 'skia'], 'Copyright 2013 Chromium'),
      ]);

      expect(grouped.map((g) => g.$1), ['accessibility', 'angle', 'dart', 'skia']);
      expect(grouped.where((g) => g.$1 == 'accessibility'), hasLength(1));
    });

    test('keeps every distinct licence text for a package', () {
      final grouped = groupLicensesByPackage([
        entry(['accessibility'], 'Copyright 2009 Chromium'),
        entry(['accessibility'], 'Copyright 2010 Chromium'),
      ]);

      // Different years are different notices; both must survive.
      expect(texts(grouped.single.$2), ['Copyright 2009 Chromium', 'Copyright 2010 Chromium']);
    });

    test('collapses byte-identical texts', () {
      final grouped = groupLicensesByPackage([
        entry(['skia'], 'Same text'),
        entry(['skia', 'angle'], 'Same text'),
      ]);

      expect(texts(grouped.firstWhere((g) => g.$1 == 'skia').$2), ['Same text']);
      expect(texts(grouped.firstWhere((g) => g.$1 == 'angle').$2), ['Same text']);
    });

    test('sorts packages case-insensitively', () {
      final grouped = groupLicensesByPackage([
        entry(['Zebra'], 'x'),
        entry(['apple'], 'y'),
        entry(['Banana'], 'z'),
      ]);
      expect(grouped.map((g) => g.$1), ['apple', 'Banana', 'Zebra']);
    });

    test('keeps paragraph indent, including the centred-header marker', () {
      // Flutter's parser marks a paragraph indented by more than 10 columns as a centred header,
      // and others as indent = columns ~/ 3. Both have to reach the renderer or every licence
      // reads as one flat block.
      final grouped = groupLicensesByPackage([
        entry(['expat'], '            centred header\n\nplain paragraph\n\n      indented'),
      ]);
      final paragraphs = grouped.single.$2.single;
      expect(paragraphs.map((p) => p.indent), [LicenseParagraph.centeredIndent, 0, 2]);
    });

    test('an empty registry yields nothing', () {
      expect(groupLicensesByPackage([]), isEmpty);
    });
  });
  group('prefilled bug report', () {
    Map<String, String> params(BuildInfo? info) => Uri.parse(bugReportUrl(info)).queryParameters;

    test('targets the new-issue form on the repository', () {
      final uri = Uri.parse(bugReportUrl(null));
      expect(uri.origin + uri.path, 'https://github.com/ExponentiallyDigital/cfg-pia-wg/issues/new');
      expect(params(null)['title'], startsWith('[BUG] '));
    });

    // GitHub applies a template OR a body parameter, never both, so the body has to reproduce the
    // template's sections. This fails if bug_report.md grows or renames one.
    test('carries every section heading from bug_report.md', () {
      final template = File('.github/ISSUE_TEMPLATE/bug_report.md').readAsStringSync().replaceAll('\r\n', '\n');
      final headings = RegExp(r'^\*\*.+\*\*$', multiLine: true).allMatches(template).map((m) => m.group(0)!).toList();

      expect(headings, isNotEmpty, reason: 'template should have **bold** section headings');
      final body = params(null)['body']!;
      for (final h in headings) {
        expect(body, contains(h), reason: h);
      }
    });

    test('embeds exactly what COPY BUILD INFO produces', () {
      const info = BuildInfo(
        versionName: '9.9.9',
        buildNumber: '999',
        installer: 'Google Play',
        buildTimestamp: '2026-07-29 03:34:57 UTC',
        buildType: 'release',
        commitHash: 'abc1234',
        commitDate: '2026-07-29T04:23:09+10:00',
        gitBranch: 'v9.9.9',
        runnerId: '1234567890',
        cpuAbi: 'arm64-v8a',
        osVersion: 'Android 15 (API 35)',
        compileSdk: '36',
        kotlinVersion: '2.3.20',
      );
      final body = params(info)['body']!;
      expect(body, contains('cfg-pia-wg v9.9.9 build 999'));
      expect(body, contains('Commit hash: abc1234'));
      expect(body, contains('Kotlin: 2.3.20'));
      // Fenced so GitHub renders it verbatim rather than collapsing the lines.
      expect(body, contains('```text'));
    });

    test('reports the detected router firmware, or says it is unknown', () {
      resetRouterFirmware();
      expect(params(null)['body'], contains('Router firmware: not detected this session'));

      setRouterFirmware(RouterFirmware.stock);
      addTearDown(resetRouterFirmware);
      expect(params(null)['body'], contains('Router firmware: stock'));
    });

    test('stays well inside a usable URL length', () {
      expect(bugReportUrl(BuildInfo.unknown()).length, lessThan(2000));
    });
  });
  testWidgets('renders the build metadata supplied by the platform channel', (tester) async {
    _mockChannel(tester, (call) async {
      expect(call.method, kGetBuildInfoMethod);
      return _hostReply;
    });

    await _pumpAbout(tester);

    expect(find.textContaining('cfg-pia-wg v9.9.9 build 999', findRichText: true), findsOneWidget);
    expect(find.textContaining('Built by: Google Play at 2026-07-29 03:34:57 UTC', findRichText: true), findsOneWidget);
    expect(find.textContaining('Build type: release', findRichText: true), findsOneWidget);
    expect(find.textContaining('Commit hash: abc1234', findRichText: true), findsOneWidget);
    expect(find.textContaining('Git branch/tag: v9.9.9', findRichText: true), findsOneWidget);
    expect(find.textContaining('Build runner ID: 1234567890', findRichText: true), findsOneWidget);
    expect(find.textContaining('CPU Architecture (ABI): arm64-v8a', findRichText: true), findsOneWidget);
    expect(find.textContaining('Target Android version: Android 15 (API 35)', findRichText: true), findsOneWidget);
    expect(find.textContaining('Compile SDK: 36', findRichText: true), findsOneWidget);
    expect(find.textContaining('Kotlin: 2.3.20', findRichText: true), findsOneWidget);
  });

  // Under `flutter test` there is no native side at all, so this is the path CI actually takes.
  testWidgets('falls back to unknown when the channel is unavailable', (tester) async {
    _mockChannel(tester, (call) async => throw MissingPluginException('no host'));

    await _pumpAbout(tester);

    expect(find.textContaining('cfg-pia-wg v$kUnknownBuildValue build $kUnknownBuildValue', findRichText: true), findsOneWidget);
    expect(find.textContaining('Commit hash: $kUnknownBuildValue', findRichText: true), findsOneWidget);
    expect(find.textContaining('Kotlin: $kUnknownBuildValue', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to unknown when the host raises a PlatformException', (tester) async {
    _mockChannel(tester, (call) async => throw PlatformException(code: 'ERR'));

    await _pumpAbout(tester);

    expect(find.textContaining('Build type: $kUnknownBuildValue', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // A partial reply must degrade one row at a time rather than throwing.
  testWidgets('fills in unknown for keys the host omits', (tester) async {
    _mockChannel(tester, (call) async => <String, String>{'versionName': '1.2.3', 'buildNumber': '7'});

    await _pumpAbout(tester);

    expect(find.textContaining('cfg-pia-wg v1.2.3 build 7', findRichText: true), findsOneWidget);
    expect(find.textContaining('Commit hash: $kUnknownBuildValue', findRichText: true), findsOneWidget);
  });

  testWidgets('lists every project link', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    // The label IS the link since 422; the URL is not shown. A raw GitHub blob URL is 70-odd
    // characters that wrap across two lines on a phone and tell the reader nothing.
    const expected = ['ReadMe', 'Change log', 'Security policy', 'Privacy policy'];
    for (final line in expected) {
      expect(find.textContaining(line, findRichText: true), findsOneWidget, reason: line);
    }

    // Order matters: the repository link sits below Privacy policy.
    final labels = RegExp(r'^(ReadMe|Change log|Security policy|Privacy policy)$');
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .where(labels.hasMatch)
        .toList();
    expect(rendered, expected);
  });

  // The app updates from the store while the deployed script only changes on a deploy, so "which
  // script is actually on my router" is a question this screen exists to answer.
  group('deployed watchdog script version', () {
    testWidgets('offers a login when the session has no connection', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      // Two rows offer it now, the script version and the watchdog history. Either fetches both,
      // because one round trip answers both questions.
      expect(find.textContaining(kScriptLoginPrompt, findRichText: true), findsNWidgets(2));
    });

    testWidgets('reads it without prompting when the session already has one', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      final ssh = RecordingSSHClient(
        responder: (_) => '# watchdog_wgc1.sh - auto-generated by cfg-pia-wg v0.8.49 build 419; *do* *not* edit.',
      );
      final c = _quietController()
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);

      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: AboutScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('v0.8.49 build 419', findRichText: true), findsOneWidget);
      expect(find.textContaining(kScriptLoginPrompt, findRichText: true), findsNothing);
      // One command, not a probe per slot - any deployed script answers the question.
      expect(ssh.commands.where((x) => x.contains('watchdog_wgc')).length, 1);
    });

    // The issue body goes to whoever reads the report, not to the user standing in front of the
    // app - "login to router to retrieve" is an instruction, and tells a reader nothing.
    test('the GitHub issue body says UNKNOWN rather than the login prompt', () {
      expect(bugReportUrl(null, scriptStatus: kScriptLoginPrompt), contains('UNKNOWN'));
      expect(bugReportUrl(null, scriptStatus: kScriptLoginPrompt), isNot(contains('login+to+router')));
      // Query encoding turns spaces into '+', so decode before looking for the version.
      expect(Uri.decodeFull(bugReportUrl(null, scriptStatus: 'v0.8.53 build 423')).replaceAll('+', ' '),
          contains('v0.8.53 build 423'));
    });

    // The same three counters the alert emails carry, shortened for the width here: the email says
    // "recorded 4 successful and 1 failed reconfigurations", this says the same in fewer words.
    testWidgets('shows the watchdog history when the router has counters', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('cfg_pia_wg_sdate')) {
          return '# watchdog_wgc1.sh - auto-generated by cfg-pia-wg v0.8.57 build 427; *do* *not* edit.'
              '\n@@CFGPIAWGABOUT@@\n2026-09-01@@4@@1';
        }
        return '';
      });
      final c = _quietController()
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);

      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: AboutScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Since 2026-09-01: 4 successful & 1 unsuccessful reconfigures', findRichText: true),
          findsOneWidget);
      // One round trip for both rows.
      expect(ssh.commands.where((x) => x.contains('cfg_pia_wg_sdate')).length, 1);
    });

    // An untouched router has no counters, and an empty row where a fact would be is worse than no
    // row at all.
    testWidgets('shows no history row at all when the router has never recorded any', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      final c = _quietController()
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);

      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: AboutScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: (_) => ''))),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('about_watchdog_history')), findsNothing);
    });

    testWidgets('says "not deployed" when the router has no script at all', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      final c = _quietController()
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);

      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: AboutScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: (_) => ''))),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('not deployed', findRichText: true), findsOneWidget);
    });
  });

  group('build info copy', () {
    // Reported: pasting a selection ran every row together ("...debugCommit hash: ..."), because
    // SelectionArea joins the text of separate widgets with no separator. The rows now share one
    // Text, so the line breaks are part of the text and travel with the selection.
    testWidgets('the block is a single Text carrying its own line breaks', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      final block = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
          .firstWhere((t) => t.contains('Commit hash: '), orElse: () => '');

      expect(block, isNotEmpty, reason: 'the build info should live in one Text widget');
      final lines = block.split('\n');
      expect(lines.first, 'cfg-pia-wg v9.9.9 build 999');
      expect(lines, contains('Commit hash: abc1234'));
      expect(lines, contains('Kotlin: 2.3.20'));
      // The exact defect: a label glued onto the previous row's value.
      expect(block, isNot(contains('releaseCommit hash')));
    });

    testWidgets('COPY BUILD INFO puts the same newline-separated text on the clipboard', (tester) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      _mockChannel(tester, (call) async => _hostReply);
      // A controller with the real clipboard writer, so this exercises the whole path down to
      // Clipboard.setData rather than stopping at an injected fake.
      final c = SessionController(tickInterval: const Duration(hours: 1));
      await _pumpAbout(tester, controller: c);

      await tester.ensureVisible(find.byKey(const Key('about_copy_build_info')));
      await tester.tap(find.byKey(const Key('about_copy_build_info')));
      await tester.pumpAndSettle();

      addTearDown(c.dispose);
      expect(copied, isNotNull);
      expect(copied, startsWith('cfg-pia-wg v9.9.9 build 999\n\n'));
      expect(copied, contains('\nCommit hash: abc1234\n'));
      expect(copied, endsWith('Kotlin: 2.3.20'));
      expect(copied, isNot(contains('releaseCommit hash')));
    });

    // Build info is not a secret: copying it must not arm the 60s auto-clear meant for
    // credentials, and it must stand down a countdown an earlier config copy left running -
    // otherwise that deadline wipes the build info the user just copied.
    testWidgets('does not arm the auto-clear, and stands down a running one', (tester) async {
      final c = _quietController();
      await c.copyToClipboard('[Interface] secret');
      expect(c.clipboardSeconds, greaterThan(0));

      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester, controller: c);

      await tester.ensureVisible(find.byKey(const Key('about_copy_build_info')));
      await tester.tap(find.byKey(const Key('about_copy_build_info')));
      await tester.pumpAndSettle();

      expect(c.clipboardSeconds, 0);
      expect(c.log, isEmpty, reason: 'nothing was auto cleared');

      await tester.pumpWidget(const SizedBox());
      c.dispose(); // in-body: the arming copy started a tick timer the binding would flag
    });
  });

  group('create GitHub issue', () {
    testWidgets('sits alongside COPY BUILD INFO', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      expect(find.byKey(const Key('about_create_issue')), findsOneWidget);
      expect(find.text('CREATE GITHUB ISSUE'), findsOneWidget);

      // Same row: at the default 800px test width both fit, so their centres share a y.
      final copy = tester.getCenter(find.byKey(const Key('about_copy_build_info')));
      final issue = tester.getCenter(find.byKey(const Key('about_create_issue')));
      expect(issue.dy, copy.dy);
      expect(issue.dx, greaterThan(copy.dx), reason: 'the issue button sits to the right');
    });

    testWidgets('opens the new-issue form prefilled with the running build', (tester) async {
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') launched.add((call.arguments as Map)['url'] as String);
        return true; // also answers canLaunch
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      await tester.ensureVisible(find.byKey(const Key('about_create_issue')));
      await tester.tap(find.byKey(const Key('about_create_issue')));
      await tester.pumpAndSettle();

      expect(launched, hasLength(1));
      expect(launched.single, startsWith('https://github.com/ExponentiallyDigital/cfg-pia-wg/issues/new?'));
      expect(Uri.parse(launched.single).queryParameters['body'], contains('cfg-pia-wg v9.9.9 build 999'));
    });
  });

  // The cached PIA CA lives on the router, so this button is the only part of ABOUT that needs
  // SSH. Session-only credentials, so it has to cope with not having them.
  group('text selection', () {
    testWidgets('the whole screen is one selection region', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      expect(find.byType(SelectionArea), findsOneWidget);
      // Build info, links and the licence text all sit inside it, so a drag or Select all spans
      // the lot and copies to the system clipboard.
      for (final needle in ['Commit hash', 'Privacy policy', 'GNU GENERAL PUBLIC LICENSE']) {
        expect(
          find.descendant(of: find.byType(SelectionArea), matching: find.textContaining(needle, findRichText: true)),
          findsWidgets,
          reason: needle,
        );
      }
    });

    // A SelectableText nested inside a SelectionArea keeps its own private selection and the region
    // skips it, which would silently punch holes in a "select all".
    testWidgets('no SelectableText is nested inside the region', (tester) async {
      _mockChannel(tester, (call) async => _hostReply);
      await _pumpAbout(tester);

      expect(
        find.descendant(of: find.byType(SelectionArea), matching: find.byType(SelectableText)),
        findsNothing,
      );
    });
  });

  testWidgets('no longer links to the repository root', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    expect(find.textContaining('GitHub source code repository', findRichText: true), findsNothing);
    // No project URL is rendered at all now - the four labels carry the links.
    expect(find.textContaining('/blob/main/', findRichText: true), findsNothing);
    expect(find.byKey(const Key('about_link_0')), findsOneWidget);
  });

  testWidgets('no longer links to ARCHITECTURE.md', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    expect(find.textContaining('ARCHITECTURE.md', findRichText: true), findsNothing);
    // "CPU Architecture (ABI)" is a build-info row and must survive the removal.
    expect(find.textContaining('CPU Architecture (ABI)', findRichText: true), findsOneWidget);
  });

  testWidgets('embeds the full GPL v3 licence text', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
    expect(find.textContaining('TERMS AND CONDITIONS'), findsOneWidget);
    expect(find.textContaining('END OF TERMS AND CONDITIONS'), findsOneWidget);
  });

  // End-to-end for the reported bug: open the real dialog and check a package heads one section.
  testWidgets('licenses dialog lists each package once, with all of its notices', (tester) async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['accessibility'], 'Copyright 2009 Chromium');
      yield const LicenseEntryWithLineBreaks(['accessibility'], 'Copyright 2010 Chromium');
      yield const LicenseEntryWithLineBreaks(['accessibility', 'skia'], 'Copyright 2013 Chromium');
    });

    _mockChannel(tester, (call) async => _hostReply);
    await _pumpAbout(tester);

    // Drive the "licenses" link's recogniser: a TextSpan tap target cannot be tapped directly.
    final span = tester.widget<Text>(find.byKey(const Key('about_licenses_link'))).textSpan! as TextSpan;
    (span.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    // One heading per package, not one per licence text.
    expect(find.text('accessibility'), findsOneWidget);
    expect(find.text('skia'), findsOneWidget);
    // Every notice still shown under its package.
    for (final year in ['2009', '2010', '2013']) {
      expect(find.textContaining('Copyright $year Chromium'), findsWidgets, reason: year);
    }
  });

}
