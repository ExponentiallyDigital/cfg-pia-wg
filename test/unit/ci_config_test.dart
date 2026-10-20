// test/unit/ci_config_test.dart - settings in .github that are easy to undo by accident: every workflow
// builds with the Flutter pinned in pubspec.yaml (ID-410), Dependabot's PRs go to dev (ID-412), and the
// Play upload goes to the internal track (ID-415).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_pin.dart';

/// Each `subosito/flutter-action` step in [yaml], as the lines from its `uses:` to the next step.
List<String> _flutterSteps(String yaml) {
  final lines = yaml.split('\n');
  final steps = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('uses: subosito/flutter-action@')) continue;
    final b = StringBuffer(lines[i]);
    for (var j = i + 1; j < lines.length && !RegExp(r'^\s*- ').hasMatch(lines[j]) && lines[j].trim().isNotEmpty; j++) {
      b.write('\n${lines[j]}');
    }
    steps.add(b.toString());
  }
  return steps;
}

void main() {
  final workflows = Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml')).toList();

  test('the step reader finds a step and its settings', () {
    const yaml = '      - name: Set up Flutter\n        uses: subosito/flutter-action@abc # v2\n        with:\n          channel: "stable"\n\n      - name: Next\n';
    expect(_flutterSteps(yaml).single, contains('channel: "stable"'));
  });

  test('every Flutter setup installs the version pinned in pubspec.yaml', () {
    var found = 0;
    for (final f in workflows) {
      for (final step in _flutterSteps(f.readAsStringSync())) {
        found++;
        // The weekly job's second setup installs the newer version it is proposing, on purpose.
        if (f.path.endsWith('weekly_updates.yml') && step.contains('steps.pin.outputs.latest')) continue;
        expect(step, contains('flutter-version-file: pubspec.yaml'), reason: '${f.path}:\n$step');
        expect(step, isNot(contains('channel:')), reason: '${f.path}: a channel installs whatever is current\n$step');
      }
    }
    expect(found, greaterThanOrEqualTo(7), reason: 'the step reader has stopped finding the steps');
  });

  test('pubspec.yaml pins an exact Flutter version, as flutter-version-file needs', () {
    expect(pinnedFlutter(File('pubspec.yaml').readAsStringSync()), matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  // ID-415. The action's `tracks` input defaults to production, so the step must name internal itself,
  // and the deprecated `track` is gone: with both, which one wins is the action's business.
  test('the Play upload goes to the internal track, through tracks rather than the deprecated track', () {
    final yaml = File('.github/workflows/release.yml').readAsStringSync();
    final start = yaml.indexOf('uses: r0adkll/upload-google-play@');
    expect(start, greaterThan(0), reason: 'release.yml no longer has the Play upload step');
    final next = yaml.indexOf(RegExp(r'^\s*- name:', multiLine: true), start);
    final step = yaml.substring(start, next < 0 ? yaml.length : next);
    expect(RegExp(r'^\s+tracks:\s*internal\s*$', multiLine: true).hasMatch(step), isTrue, reason: step);
    expect(RegExp(r'^\s+track:', multiLine: true).hasMatch(step), isFalse, reason: step);
  });

  // ID-405. A shape test: it holds the job in place, and the job's own run is the evidence.
  test('the quality workflow builds the iOS app on macOS, so the release PR shows an iOS break', () {
    final yaml = File('.github/workflows/quality_and_security.yml').readAsStringSync();
    final start = yaml.indexOf(RegExp(r'^  ios-build:', multiLine: true));
    expect(start, greaterThan(0), reason: 'no ios-build job');
    final next = yaml.indexOf(RegExp(r'^  [a-z-]+:', multiLine: true), start + 1);
    final job = yaml.substring(start, next < 0 ? yaml.length : next);
    expect(job, contains('runs-on: macos-'));
    expect(job, contains('flutter build ios --simulator'));
    expect(job, contains('flutter-version-file: pubspec.yaml'));
  });

  // ID-418. A shape test, like ID-405's: the job's own run is the evidence that it signs.
  test('the release builds a signed iOS app with the App Store Connect key, and keeps the key secret', () {
    final yaml = File('.github/workflows/release.yml').readAsStringSync();
    final start = yaml.indexOf(RegExp(r'^  ios-release:', multiLine: true));
    expect(start, greaterThan(0), reason: 'no ios-release job');
    final next = yaml.indexOf(RegExp(r'^  [a-z-]+:', multiLine: true), start + 1);
    final job = yaml.substring(start, next < 0 ? yaml.length : next);
    expect(job, contains('runs-on: macos-'));
    expect(job, contains('needs: quality-and-security'));
    for (final s in ['APP_STORE_CONNECT_KEY_ID', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_API_KEY']) {
      expect(job, contains('secrets.$s'), reason: s);
    }
    expect(job, contains('-allowProvisioningUpdates'));
    // ID-401: the App Store build carries the RevenueCat key, and refuses to build without it.
    expect(job, contains('--dart-define=REVENUECAT_IOS_KEY="\$REVENUECAT_IOS_KEY"'));
    expect(job, contains('if [ -z "\$REVENUECAT_IOS_KEY" ]; then'));
    // ID-431: a tag, or a manual run asking for it, uploads to App Store Connect; nothing else does.
    final upload = job.substring(job.indexOf('- name: Upload to App Store Connect for TestFlight'));
    expect(upload.split('\n')[1], contains("if: \${{ startsWith(github.ref, 'refs/tags/v') || inputs.testflight == true }}"));
    expect(upload, contains('Set :destination upload'));
    expect(job, contains('-exportOptionsPlist ios/ExportOptions.plist'));
    // The key never reaches the log, and never outlives the job.
    expect(RegExp(r'echo[^\n]*\$ASC_API_KEY').hasMatch(job), isFalse);
    expect(RegExp(r'if: always\(\)\s+run: rm -f "\$RUNNER_TEMP/AuthKey\.p8"').hasMatch(job), isTrue);

    // Exported for App Store Connect by the team the Xcode project signs with (ID-422).
    final export = File('ios/ExportOptions.plist').readAsStringSync();
    expect(RegExp(r'<key>method</key>\s*<string>app-store-connect</string>').hasMatch(export), isTrue);
    final team = RegExp(r'<key>teamID</key>\s*<string>([^<]+)</string>').firstMatch(export)!.group(1);
    expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), contains('DEVELOPMENT_TEAM = $team;'));
  });

  // ID-455. Like the Play listing's: checked before anything is sent, and a check-only run sends nothing.
  test('the App Store listing workflow checks first, pins its packages, and keeps the key out of the log', () {
    final yaml = File('.github/workflows/app_store_listing.yml').readAsStringSync();
    expect(yaml, contains('scripts/app_store_connect.py listing --check'));
    expect(yaml, contains('PyJWT==2.10.1 cryptography==44.0.2 requests==2.34.2'));
    final publish = yaml.substring(yaml.indexOf('- name: Publish the listing'));
    expect(publish.split('\n')[1], contains(r'if: ${{ !inputs.check_only }}'));
    expect(yaml.indexOf('listing --check'), lessThan(yaml.indexOf('- name: Publish the listing')));
    expect(RegExp(r'echo[^\n]*APP_STORE_CONNECT_API_KEY').hasMatch(yaml), isFalse);
    // The release's TestFlight upload gets its notes and testers the same way (ID-432, ID-465).
    final release = File('.github/workflows/release.yml').readAsStringSync();
    expect(release, contains('scripts/app_store_connect.py whats-new --build "\$BUILD" --notes play-store/whatsnew-en-AU'));
    expect(release, contains('scripts/app_store_connect.py testers'));
  });

  test("Dependabot's PRs go to dev, not straight to main", () {
    final config = File('.github/dependabot.yml').readAsStringSync();
    final ecosystems = RegExp(r'^\s+- package-ecosystem:', multiLine: true).allMatches(config).length;
    final toDev = RegExp(r'^\s+target-branch:\s*"?dev"?\s*$', multiLine: true).allMatches(config).length;
    expect(ecosystems, greaterThan(0));
    expect(toDev, ecosystems, reason: 'every update block needs target-branch: "dev"');
  });
}
