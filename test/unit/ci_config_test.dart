// test/unit/ci_config_test.dart - settings in .github that are easy to undo by accident: every workflow
// builds with the Flutter pinned in pubspec.yaml (ID-410), and Dependabot's PRs go to dev (ID-412).
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

  test("Dependabot's PRs go to dev, not straight to main", () {
    final config = File('.github/dependabot.yml').readAsStringSync();
    final ecosystems = RegExp(r'^\s+- package-ecosystem:', multiLine: true).allMatches(config).length;
    final toDev = RegExp(r'^\s+target-branch:\s*"?dev"?\s*$', multiLine: true).allMatches(config).length;
    expect(ecosystems, greaterThan(0));
    expect(toDev, ecosystems, reason: 'every update block needs target-branch: "dev"');
  });
}
