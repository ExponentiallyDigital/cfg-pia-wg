// scripts/wait-for-checks.sh, run for real against a fake `gh` (ID-630).
//
// release.yml's two release jobs build and sign beside the quality and security checks and wait for them
// before they publish, so the gate is this script: it passes only when every check job of the run has ended
// well, fails at once when one has not, and never takes "nothing to see" for a pass.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

/// A fake `gh`: `api` prints what the script's jq would, one "conclusion name" line for each check job, from
/// the state file `jobsN` for the Nth look, or from `jobs` once there is no file for that look.
const String _gh = r'''#!/bin/sh
echo "$*" >> "$STATE/calls"
case "$1" in
  api)
    N=0; [ -f "$STATE/looks" ] && N="$(cat "$STATE/looks")"
    N=$((N + 1)); echo "$N" > "$STATE/looks"
    if [ -f "$STATE/jobs$N" ]; then cat "$STATE/jobs$N"
    elif [ -f "$STATE/jobs" ]; then cat "$STATE/jobs"; fi
    exit 0 ;;
esac
exit 1
''';

const String _script = 'scripts/wait-for-checks.sh';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late Directory root;
  late Directory state;

  setUp(() {
    if (shell == null) return;
    root = Directory.systemTemp.createTempSync('wait_checks_');
    state = Directory('${root.path}/state')..createSync();
    Directory('${root.path}/bin').createSync();
    File('${root.path}/bin/gh').writeAsStringSync(_gh);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${root.path}/bin/gh']);
  });
  tearDown(() {
    if (shell != null) root.deleteSync(recursive: true);
  });

  /// Runs the script with [tries] looks and no pause between them, with the fake gh.
  Future<ProcessResult> wait({List<String>? args, Map<String, String> env = const {}}) {
    final sep = Platform.isWindows ? ';' : ':';
    return runSh(
      shell!,
      [
        '-c',
        r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"',
        'sh',
        shPath(File(_script).absolute.path),
        ...(args ?? ['4', '0']),
      ],
      environment: {
        'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
        'STATE': state.path,
        'GITHUB_REPOSITORY': 'owner/repo',
        'GITHUB_RUN_ID': '42',
        ...env,
      },
    );
  }

  void set(String name, String value) => File('${state.path}/$name').writeAsStringSync(value);
  List<String> calls() => File('${state.path}/calls').existsSync() ? File('${state.path}/calls').readAsLinesSync() : [];
  int looks() => calls().where((c) => c.startsWith('api ')).length;

  const ok = 'success Quality & security checks / Quality & static analysis\n'
      'success Quality & security checks / CodeQL (java-kotlin)\n';

  test('every check having succeeded passes at the first look', () async {
    set('jobs', ok);
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 1);
  }, skip: skip);

  test('a skipped check counts as passed, for the builds the release run leaves out', () async {
    set('jobs', '${ok}skipped Quality & security checks / iOS simulator build\n');
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: skip);

  for (final ended in ['failure', 'cancelled', 'timed_out', 'action_required']) {
    test('a check that ended as $ended fails at the first look, while others are still running', () async {
      set('jobs', 'running Quality & security checks / CodeQL (java-kotlin)\n$ended Quality & security checks / Quality & static analysis\n');
      final r = await wait(args: ['60', '0']);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('::error::a check did not pass ($ended Quality & security checks / Quality & static analysis)'));
      expect(looks(), 1, reason: 'one look, then it knew nothing could be published');
    }, skip: skip);
  }

  test('checks still running are waited for, and the pass comes when the last one ends', () async {
    set('jobs1', 'running Quality & security checks / Quality & static analysis\n');
    set('jobs2', 'success Quality & security checks / Quality & static analysis\nrunning Quality & security checks / CodeQL (java-kotlin)\n');
    set('jobs', ok);
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 3);
  }, skip: skip);

  test('checks that never end use up every try and then say so, as a failure', () async {
    set('jobs', 'running Quality & security checks / Quality & static analysis\n');
    final r = await wait(args: ['3', '0']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 3);
    expect('${r.stdout}', contains('had not all ended after'));
  }, skip: skip);

  test('no check listed is not a pass: it looks again, and fails when none ever shows', () async {
    final r = await wait(args: ['3', '0']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 3);
  }, skip: skip);

  test('a call that answers nothing is treated as no check yet, never as a pass', () async {
    set('jobs1', '');
    set('jobs', ok);
    final r = await wait();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 2, reason: 'the empty answer was not a pass');
  }, skip: skip);

  test('the jobs are looked up in this run, by the name the release workflow gives the checks', () async {
    set('jobs', ok);
    await wait();
    final api = calls().firstWhere((c) => c.startsWith('api '));
    expect(api, contains('repos/owner/repo/actions/runs/42/jobs'));
    expect(api, contains('Quality & security checks'));
  }, skip: skip);

  test('a bad number, or no run to look in, is a bad call, not a pass', () async {
    set('jobs', ok);
    expect((await wait(args: ['x', '0'])).exitCode, 2);
    expect((await wait(env: {'GITHUB_RUN_ID': ''})).exitCode, 2);
    expect(looks(), 0, reason: 'nothing was asked of GitHub');
  }, skip: skip);

  test('checks recorded as passed for this tree (VERIFIED) need no waiting, and GitHub is not asked', () async {
    final r = await wait(env: {'VERIFIED': 'true'});
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('had already passed for this source tree'));
    expect(looks(), 0);
  }, skip: skip);

  test('VERIFIED is only "true" to count: anything else waits for the checks as usual', () async {
    set('jobs', 'failure Quality & security checks / Quality & static analysis\n');
    final r = await wait(env: {'VERIFIED': 'false'});
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(looks(), 1);
  }, skip: skip);

  test('the name it looks for is the name release.yml gives the call of the checks', () {
    final yml = File('.github/workflows/release.yml').readAsStringSync();
    expect(yml, contains('name: Quality & security checks'));
    expect(File(_script).readAsStringSync(), contains('startswith("Quality & security checks")'));
  });
}
