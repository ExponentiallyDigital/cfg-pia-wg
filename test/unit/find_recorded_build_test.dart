// scripts/find-recorded-build.sh, run for real against a fake `git` and `gh` (ID-685).
//
// A release run on dev records that the checks passed, and the signed iOS build Apple validated, against the
// source tree's hash. The tag run on the same tree reuses both, so it must find them only when they can be
// trusted: from a successful release.yml run on dev, main or a tag, unexpired, for exactly this tree, and only
// on a tag run. Anything else is "not found", never an error, so the release builds and checks as it always has.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

/// A fake `git` for `rev-parse HEAD^{tree}`, and a fake `gh`: `api .../artifacts?name=N` prints the state file
/// `artifacts-N` (lines of "RUN BRANCH", as the script's jq would), `api .../runs/ID` prints `run-ID`, and
/// `run download` writes an .ipa, and `validated.txt` unless the state says not to, into its `--dir`.
const String _fakes = r'''#!/bin/sh
echo "$*" >> "$STATE/calls"
case "$0" in
  */git) [ "$1 $2" = "rev-parse HEAD^{tree}" ] && { echo "$TREE"; exit 0; }; exit 1 ;;
esac
case "$1 $2" in
  "run download")
    [ -f "$STATE/download_fails" ] && exit 1
    while [ $# -gt 0 ]; do [ "$1" = "--dir" ] && DIR="$2"; shift; done
    mkdir -p "$DIR"; echo ipa > "$DIR/Runner.ipa"; echo sbom > "$DIR/cfg-pia-wg-ios-sbom.spdx.json"
    [ -f "$STATE/no_marker" ] || echo ok > "$DIR/validated.txt"
    exit 0 ;;
esac
if [ "$1" = "api" ]; then
  case "$2" in
    *artifacts?name=*) N="${2#*name=}"; N="${N%%&*}"; [ -f "$STATE/artifacts-$N" ] && cat "$STATE/artifacts-$N"; exit 0 ;;
    */actions/runs/*) ID="${2##*/}"; [ -f "$STATE/run-$ID" ] && cat "$STATE/run-$ID"; exit 0 ;;
  esac
fi
exit 1
''';

const String _script = 'scripts/find-recorded-build.sh';
const String _tree = '3958eb179c8f6243240be631ad453f50bc410caa';
const String _ok = '.github/workflows/release.yml success';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late Directory root;
  late Directory state;

  setUp(() {
    if (shell == null) return;
    root = Directory.systemTemp.createTempSync('find_recorded_');
    state = Directory('${root.path}/state')..createSync();
    Directory('${root.path}/bin').createSync();
    for (final tool in ['git', 'gh']) {
      File('${root.path}/bin/$tool').writeAsStringSync(_fakes);
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${root.path}/bin/$tool']);
    }
  });
  tearDown(() {
    if (shell != null) root.deleteSync(recursive: true);
  });

  void set(String name, String value) => File('${state.path}/$name').writeAsStringSync(value);
  List<String> calls() => File('${state.path}/calls').existsSync() ? File('${state.path}/calls').readAsLinesSync() : [];

  /// Runs the script in [mode] (with [dir] if given) as a tag run unless [tag] is false; returns its result, with
  /// $GITHUB_OUTPUT and $GITHUB_ENV in the files `out` and `env` of the temp folder.
  Future<ProcessResult> run(String mode, {String? dir, bool tag = true}) {
    final sep = Platform.isWindows ? ';' : ':';
    File('${root.path}/out').writeAsStringSync('');
    File('${root.path}/env').writeAsStringSync('');
    return runSh(
      shell!,
      [
        '-c',
        r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"',
        'sh',
        shPath(File(_script).absolute.path),
        mode,
        if (dir != null) shPath(dir),
      ],
      environment: {
        'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
        'STATE': state.path,
        'TREE': _tree,
        'IS_TAG': '$tag',
        'GITHUB_REPOSITORY': 'owner/repo',
        'GITHUB_RUN_ID': '77',
        'GITHUB_OUTPUT': shPath('${root.path}/out'),
        'GITHUB_ENV': shPath('${root.path}/env'),
      },
    );
  }

  String output() => File('${root.path}/out').readAsStringSync();

  group('the tree', () {
    test('is git\'s hash of HEAD\'s tree', () async {
      final r = await run('tree');
      expect('${r.stdout}'.trim(), _tree);
    }, skip: skip);
  });

  group('verified: were the checks already passed for this tree', () {
    test('a recorded pass from a successful release.yml run on dev is found, and the checks are not run again', () async {
      set('artifacts-verified-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      final r = await run('verified');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(output(), contains('verified=true'));
    }, skip: skip);

    for (final branch in ['main', 'v0.8.221']) {
      test('a pass recorded on $branch is trusted too', () async {
        set('artifacts-verified-$_tree', '555 $branch\n');
        set('run-555', '$_ok\n');
        await run('verified');
        expect(output(), contains('verified=true'));
      }, skip: skip);
    }

    test('a pass from any other branch is not trusted, so the checks run', () async {
      set('artifacts-verified-$_tree', '555 feature/x\n556 ci-test-630d\n');
      set('run-555', '$_ok\n');
      set('run-556', '$_ok\n');
      await run('verified');
      expect(output(), contains('verified=false'));
    }, skip: skip);

    test('a pass from a run that did not succeed, or is another workflow, is not trusted', () async {
      set('artifacts-verified-$_tree', '555 dev\n556 dev\n');
      set('run-555', '.github/workflows/release.yml failure\n');
      set('run-556', '.github/workflows/quality_and_security.yml success\n');
      await run('verified');
      expect(output(), contains('verified=false'));
    }, skip: skip);

    test('an older trusted record is used when the newest is not trusted', () async {
      set('artifacts-verified-$_tree', '600 feature/x\n555 dev\n');
      set('run-600', '$_ok\n');
      set('run-555', '$_ok\n');
      await run('verified');
      expect(output(), contains('verified=true'));
    }, skip: skip);

    test('no record is not an error: the checks run', () async {
      final r = await run('verified');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(output(), contains('verified=false'));
    }, skip: skip);

    test('the record is looked for by this tree\'s hash, and for no other', () async {
      await run('verified');
      expect(calls().any((c) => c.contains('name=verified-$_tree')), isTrue);
    }, skip: skip);

    test('anything but a tag run never looks, so a dry run or a manual run always runs the checks', () async {
      set('artifacts-verified-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      await run('verified', tag: false);
      expect(output(), contains('verified=false'));
      expect(calls().where((c) => c.startsWith('api')), isEmpty, reason: 'GitHub was not asked');
    }, skip: skip);
  });

  group('record-verified', () {
    test('writes the record and names the artifact for this tree', () async {
      final dir = '${root.path}/rec';
      final r = await run('record-verified', dir: dir);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('$dir/verified.txt').readAsStringSync(), contains(_tree));
      expect(File('${root.path}/env').readAsStringSync(), contains('RECORD_NAME=verified-$_tree'));
    }, skip: skip);

    test('needs a folder to write in', () async {
      expect((await run('record-verified')).exitCode, 2);
    }, skip: skip);
  });

  group('signed-ios: a signed iOS build Apple already validated for this tree', () {
    test('is found and downloaded when it is trusted and carries its validated marker', () async {
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      final dir = '${root.path}/got';
      final r = await run('signed-ios', dir: dir);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(output(), allOf(contains('found=true'), contains('tree=$_tree')));
      expect(File('$dir/Runner.ipa').existsSync(), isTrue);
      expect(calls().any((c) => c.startsWith('run download 555') && c.contains('--name cfg-pia-wg-ios-signed-$_tree')), isTrue);
    }, skip: skip);

    test('a build without the marker that Apple validated it is not used', () async {
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      set('no_marker', 'x');
      await run('signed-ios', dir: '${root.path}/got');
      expect(output(), contains('found=false'));
    }, skip: skip);

    test('a download that fails means iOS is built, not that the release fails', () async {
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      set('download_fails', 'x');
      final r = await run('signed-ios', dir: '${root.path}/got');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(output(), contains('found=false'));
    }, skip: skip);

    test('an untrusted branch, an unsuccessful run, or no record at all is not found', () async {
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '555 ci-test\n');
      set('run-555', '$_ok\n');
      await run('signed-ios', dir: '${root.path}/got');
      expect(output(), contains('found=false'));
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '556 dev\n');
      set('run-556', '.github/workflows/release.yml cancelled\n');
      await run('signed-ios', dir: '${root.path}/got2');
      expect(output(), contains('found=false'));
      File('${state.path}/artifacts-cfg-pia-wg-ios-signed-$_tree').deleteSync();
      await run('signed-ios', dir: '${root.path}/got3');
      expect(output(), contains('found=false'));
    }, skip: skip);

    test('anything but a tag run builds iOS, and still says which tree it is', () async {
      set('artifacts-cfg-pia-wg-ios-signed-$_tree', '555 dev\n');
      set('run-555', '$_ok\n');
      await run('signed-ios', dir: '${root.path}/got', tag: false);
      expect(output(), allOf(contains('found=false'), contains('tree=$_tree')));
      expect(calls().where((c) => c.startsWith('run download')), isEmpty);
    }, skip: skip);
  });

  test('an unknown mode is a bad call', () async {
    expect((await run('nonsense')).exitCode, 2);
  }, skip: skip);
}
