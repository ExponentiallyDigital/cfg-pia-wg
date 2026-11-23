// The "Did iOS change" job of quality_and_security.yml, its shell run for real against a fake `git` (ID-630).
//
// The iOS simulator build takes 14 to 19 minutes on the macOS runner that queues longest, so a pull request
// builds it only when something the iOS build reads has changed. The decision is a few lines of shell inside
// the workflow, so the test lifts them out of the YAML and runs them: a change to Dart alone must not start
// the build, and a change to ios/, the lockfiles or the workflow itself must.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

/// The `run: |` script of the step that compares with the base, as the shell gets it.
String filterScript() {
  final lines = File('.github/workflows/quality_and_security.yml').readAsLinesSync();
  final step = lines.indexWhere((l) => l.contains('- name: Compare with the base of the pull request'));
  expect(step, greaterThan(0), reason: 'the step is gone from the workflow');
  final run = lines.indexWhere((l) => l.trim() == 'run: |', step);
  final out = <String>[];
  for (var i = run + 1; i < lines.length && (lines[i].startsWith('          ') || lines[i].trim().isEmpty); i++) {
    out.add(lines[i].length >= 10 ? lines[i].substring(10) : '');
  }
  return out.join('\n');
}

/// A fake `git` that prints the file names the test set in `CHANGED`, one a line, for `git diff --name-only`.
const String _git = r'''#!/bin/sh
echo "$*" >> "$STATE/calls"
[ "$1 $2" = "diff --name-only" ] && { printf '%s\n' "$CHANGED"; exit 0; }
exit 1
''';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late Directory root;

  setUp(() {
    if (shell == null) return;
    root = Directory.systemTemp.createTempSync('ios_filter_');
    Directory('${root.path}/bin').createSync();
    File('${root.path}/bin/git').writeAsStringSync(_git);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${root.path}/bin/git']);
  });
  tearDown(() {
    if (shell != null) root.deleteSync(recursive: true);
  });

  /// Runs the step's script as [event], with [changed] the files the PR changed. Returns its `ios=` output.
  Future<String> decide(String event, List<String> changed) async {
    final script = File('${root.path}/filter.sh')..writeAsStringSync(filterScript());
    final out = File('${root.path}/out')..writeAsStringSync('');
    final sep = Platform.isWindows ? ';' : ':';
    final r = await runSh(
      shell!,
      [
        '-c',
        r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"',
        'sh',
        shPath(script.absolute.path),
      ],
      environment: {
        'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
        'STATE': root.path,
        'EVENT': event,
        'BASE_SHA': 'abc123',
        'CHANGED': changed.join('\n'),
        'GITHUB_OUTPUT': shPath(out.absolute.path),
      },
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    return out.readAsStringSync().trim();
  }

  test('the script was lifted whole from the workflow', () {
    final s = filterScript();
    expect(s, contains('git diff --name-only "\$BASE_SHA" HEAD'));
    expect(s, contains('ios=false'));
  });

  test('a pull request that changes only Dart, tests and documents leaves the iOS build out', () async {
    expect(await decide('pull_request', ['lib/router_watchdog.dart', 'test/unit/a_test.dart', 'README.md', '.github/workflows/release.yml']),
        'ios=false');
  }, skip: skip);

  for (final file in ['ios/Runner/Info.plist', 'ios/Podfile', 'pubspec.yaml', 'pubspec.lock', '.github/workflows/quality_and_security.yml']) {
    test('a pull request that changes $file builds iOS', () async {
      expect(await decide('pull_request', ['lib/a.dart', file]), 'ios=true');
    }, skip: skip);
  }

  test('files that only look like iOS ones do not count: a file named ios in lib, or a lock that is not the pubspec', () async {
    expect(await decide('pull_request', ['lib/ios/channel.dart', 'android/pubspec.lock', 'docs/pubspec.yaml']), 'ios=false');
  }, skip: skip);

  test('anything but a pull request builds iOS, without asking git', () async {
    for (final event in ['push', 'workflow_dispatch', 'workflow_call', 'schedule']) {
      expect(await decide(event, ['lib/a.dart']), 'ios=true', reason: event);
    }
    expect(File('${root.path}/calls').existsSync(), isFalse, reason: 'git was not asked');
  }, skip: skip);
}
