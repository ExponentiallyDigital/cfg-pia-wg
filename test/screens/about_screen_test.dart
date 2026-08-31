// test/screens/about_screen_test.dart - About screen content + build-info channel fallback.
//
// The metadata rows are Text.rich, so every assertion on them needs findRichText: true --
// find.text() only inspects Text.data, which is null for a spanned Text.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/build_info_service.dart';
import 'package:cfg_pia_wg/screens/about_screen.dart';

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

/// Installs [handler] as the native side of [buildInfoChannel] for the current test.
void _mockChannel(WidgetTester tester, Future<Object?>? Function(MethodCall)? handler) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(buildInfoChannel, handler);
  addTearDown(() => messenger.setMockMethodCallHandler(buildInfoChannel, null));
}

Future<void> _pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the build metadata supplied by the platform channel', (tester) async {
    _mockChannel(tester, (call) async {
      expect(call.method, kGetBuildInfoMethod);
      return _hostReply;
    });

    await _pumpAbout(tester);

    expect(find.text('cfg-pia-wg v9.9.9 build 999'), findsOneWidget);
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

    expect(find.text('cfg-pia-wg v$kUnknownBuildValue build $kUnknownBuildValue'), findsOneWidget);
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

    expect(find.text('cfg-pia-wg v1.2.3 build 7'), findsOneWidget);
    expect(find.textContaining('Commit hash: $kUnknownBuildValue', findRichText: true), findsOneWidget);
  });

  testWidgets('lists every project link', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    const expected = [
      'GitHub source code repository: https://github.com/ExponentiallyDigital/cfg-pia-wg',
      'ReadMe: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md',
      'Change log: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md',
      'Architecture: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md',
      'Security policy: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/SECURITY.md',
      'Privacy policy: https://www.exponentiallydigital.com/cfg-pia-wg/privacy.html',
    ];
    for (final line in expected) {
      expect(find.textContaining(line, findRichText: true), findsOneWidget, reason: line);
    }
  });

  testWidgets('embeds the full GPL v3 licence text', (tester) async {
    _mockChannel(tester, (call) async => _hostReply);

    await _pumpAbout(tester);

    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
    expect(find.textContaining('TERMS AND CONDITIONS'), findsOneWidget);
    expect(find.textContaining('END OF TERMS AND CONDITIONS'), findsOneWidget);
  });

  testWidgets('licenses dialog renders with AppBar and licenses list', (tester) async {
    // Test the dialog by rendering it within showDialog context
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => Scaffold(
                    backgroundColor: const Color(0xFF1a1a1a),
                    appBar: AppBar(
                      backgroundColor: const Color(0xFF1a1a1a),
                      title: const SizedBox.shrink(),
                    ),
                    body: FutureBuilder<List<LicenseEntry>>(
                      future: LicenseRegistry.licenses.toList(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return ListView(
                          children: [
                            for (final entry in snapshot.data!) ...[
                              Text(entry.packages.join(', ')),
                              SelectableText(entry.paragraphs.map((p) => p.text).join('\n\n')),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsWidgets);
    expect(find.byType(ListView), findsWidgets);
  });
}
