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

  test("Dependabot's PRs go to dev, not straight to main", () {
    final config = File('.github/dependabot.yml').readAsStringSync();
    final ecosystems = RegExp(r'^\s+- package-ecosystem:', multiLine: true).allMatches(config).length;
    final toDev = RegExp(r'^\s+target-branch:\s*"?dev"?\s*$', multiLine: true).allMatches(config).length;
    expect(ecosystems, greaterThan(0));
    expect(toDev, ecosystems, reason: 'every update block needs target-branch: "dev"');
  });
}
