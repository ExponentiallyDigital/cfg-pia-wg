// scripts/wait-for-release.sh, run for real against a fake `gh` (ID-624).
//
// The iOS job of release.yml waits for the release the Android job creates. When the Android job
// failed on 2026-11-17 it waited out all 30 minutes on a macOS runner for a release that was never
// coming, and a cancel did not stop it. The wait now ends at once when that job has failed.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

/// A fake `gh`: `release view` succeeds once it has been asked more than `appear_after` times, and
/// `api` answers with whatever the `job` file holds, as the script's jq would print it.
const String _gh = r'''#!/bin/sh
echo "$*" >> "$STATE/calls"
case "$1 $2" in
  "release view")
    N=0; [ -f "$STATE/views" ] && N="$(cat "$STATE/views")"
    N=$((N + 1)); echo "$N" > "$STATE/views"
    AFTER=999; [ -f "$STATE/appear_after" ] && AFTER="$(cat "$STATE/appear_after")"
    [ "$N" -gt "$AFTER" ] && exit 0
    exit 1 ;;
esac
case "$1" in
  api) [ -f "$STATE/job" ] && cat "$STATE/job"; exit 0 ;;
esac
exit 1
''';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late Directory root;
  late Directory state;

  setUp(() {
    if (shell == null) return;
    root = Directory.systemTemp.createTempSync('wait_release_');
    state = Directory('${root.path}/state')..createSync();
    Directory('${root.path}/bin').createSync();
    File('${root.path}/bin/gh').writeAsStringSync(_gh);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${root.path}/bin/gh']);
  });
  tearDown(() {
    if (shell != null) root.deleteSync(recursive: true);
  });

  /// Runs the script for v1.2.3 with [tries] looks, no pause between them, and the fake gh.
  Future<ProcessResult> wait({int tries = 4, String script = 'scripts/wait-for-release.sh'}) {
    final sep = Platform.isWindows ? ';' : ':';
    return runSh(
      shell!,
      [
        '-c',
        r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"',
        'sh',
        shPath(File(script).absolute.path),
        'v1.2.3',
        '$tries',
        '0',
      ],
      environment: {
        'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
        'STATE': state.path,
        'GITHUB_REPOSITORY': 'owner/repo',
        'GITHUB_RUN_ID': '42',
      },
    );
  }

  void set(String name, String value) => File('${state.path}/$name').writeAsStringSync(value);
  List<String> calls() => File('${state.path}/calls').existsSync() ? File('${state.path}/calls').readAsLinesSync() : [];
  int looks() => calls().where((c) => c.startsWith('release view')).length;

  test('a release that is already there ends the wait with the first look', () async {
    set('appear_after', '0');
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 1);
  }, skip: skip);

  test('a release that turns up after a few looks ends the wait, while the Android job is still running', () async {
    set('appear_after', '2');
    set('job', 'running\n');
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 3);
  }, skip: skip);

  for (final ended in ['failure', 'cancelled', 'skipped', 'timed_out']) {
    test('the Android job having ended as $ended stops the wait at the first look, not after every try', () async {
      set('job', '$ended\n');
      final r = await wait(tries: 60);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('::error::the Android release job ended as $ended'));
      expect(looks(), 1, reason: 'one look, then it knew no release was coming');
    }, skip: skip);
  }

  test('the job is looked up in this run, by its name', () async {
    set('job', 'failure\n');
    await wait();
    final api = calls().firstWhere((c) => c.startsWith('api '));
    expect(api, contains('repos/owner/repo/actions/runs/42/jobs'));
    expect(api, contains('Build and release'));
  }, skip: skip);

  test('a job that is still running, with no release, waits out every try and then says so', () async {
    set('job', 'running\n');
    final r = await wait(tries: 3);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 3);
    expect('${r.stdout}', contains('::error::no release v1.2.3 after'));
  }, skip: skip);

  test('a job that succeeded with no release yet is waited for, since the release is made last', () async {
    set('job', 'success\n');
    set('appear_after', '1');
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 2);
  }, skip: skip);

  test('an answer it cannot get is treated as still running, never as a failure', () async {
    // No `job` file: the fake prints nothing, as gh does when the call fails.
    set('appear_after', '1');
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: skip);

  test('the workflow calls the script, and no longer carries its own loop', () {
    final yml = File('.github/workflows/release.yml').readAsStringSync();
    expect(yml, contains('sh scripts/wait-for-release.sh "\$TAG"'));
    expect(yml, isNot(contains('seq 1 60')));
  });

  test('the iOS job may read the run, which the check needs, and no more than that', () {
    final yml = File('.github/workflows/release.yml').readAsStringSync();
    final ios = yml.substring(yml.indexOf('  ios-release:'));
    final permissions = ios.substring(ios.indexOf('    permissions:'), ios.indexOf('    steps:'));
    expect(permissions, contains('actions: read'));
    expect(permissions, contains('contents: write'));
    expect(RegExp(r'^\s+[a-z-]+: write', multiLine: true).allMatches(permissions).length, 1,
        reason: 'contents: write is the only write');
  });
}
