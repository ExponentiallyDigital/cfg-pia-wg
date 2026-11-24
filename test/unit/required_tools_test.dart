// test/unit/required_tools_test.dart - a local run that can't run the shell tests fails, it does not skip them (ID-709).
//
// About 80 tests run the router scripts and Claude Code's hooks in a shell, and each skips itself when its
// tools are missing, since a skip is the right thing on a machine nobody has set up. But a run that skips
// them still says "All other tests passed", and on 2026-11-24 a plain PowerShell on the Windows machine ran
// 27 fewer tests than CI without a word, because `jq` was not installed (Git for Windows ships git and sh,
// not jq). CI is ubuntu-latest, which has all of them, so it skips none of these. This is the one test that
// fails for a machine that would, with what to install, so a green local run is the same run as CI's.
//
// The screenshot tests are different: they skip on every machine, CI included, unless asked for with a
// define, so they are not counted here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart' show runSh, shPath, usesWsl;
import '../watchdog_harness.dart' show findShell;

/// Whether [tool] runs from this process, as the hook tests start it (straight from the PATH, not in WSL).
bool _runs(String tool, List<String> args) {
  try {
    return Process.runSync(tool, args).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// What to do about each missing tool, per platform, for the message.
String _fix(String tool) {
  if (Platform.isWindows) {
    return switch (tool) {
      'jq' => 'run `winget install jqlang.jq`, then open a new terminal',
      'git' => 'install Git for Windows, so that `git` is on the PATH',
      _ => 'install Git for Windows and add its `usr\\bin` folder to the PATH, or run the tests from Git Bash',
    };
  }
  if (Platform.isMacOS) return 'run `brew install $tool`';
  return 'run `sudo apt-get install $tool`';
}

void main() {
  const fix = 'Install WSL with a Linux (the tests use it, and it is faster), or put Git Bash on the PATH.';

  test('a POSIX shell is found for the script tests, so they run and are not skipped', () {
    expect(
      findShell(),
      isNotNull,
      reason: 'No `sh` or `bash` runs from here and there is no working WSL, so the watchdog, guard and '
          'command tests would skip themselves and this run would not be CI\'s. '
          '${Platform.isWindows ? fix : 'Install sh.'}',
    );
  });

  // Finding a shell is not having one that works: on Windows `bash.exe` is also the WSL launcher in WindowsApps,
  // which answers `exit 0` and then can't open the test folders, as it is given `C:/...` paths. So the shell the
  // tests will use is made to do what they make it do: open a file on a real path, and find the tools the
  // scripts call (the list the WSL probe in posix_shell.dart checks).
  test('the shell the script tests will use opens a file by its path and has the tools the scripts call', () async {
    final shell = findShell();
    if (shell == null) return; // The test above says so.
    final dir = Directory.systemTemp.createTempSync('required_tools_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/probe.txt')..writeAsStringSync('probe-ok');
    final r = await runSh(shell, [
      '-c',
      r'for T in awk sed grep sort tr od base64 sleep; do command -v "$T" >/dev/null || { echo "no $T" >&2; exit 1; }; done; cat "$1"',
      'sh',
      shPath(file.path),
    ]);
    expect(
      r.exitCode == 0 && '${r.stdout}'.trim() == 'probe-ok',
      isTrue,
      reason: 'The shell `$shell` (WSL: $usesWsl) did not run the probe: exit ${r.exitCode}, stdout "${r.stdout}", '
          'stderr "${r.stderr}". The script tests would fail or skip on it, and this run would not be CI\'s. '
          '${Platform.isWindows ? fix : 'Install the tools it names.'}',
    );
  });

  test('git, jq and sh run on the PATH, so the hook tests run and are not skipped', () {
    final missing = [
      if (!_runs('git', ['--version'])) 'git',
      if (!_runs('jq', ['--version'])) 'jq',
      if (!_runs('sh', ['-c', 'true'])) 'sh',
    ];
    expect(
      missing,
      isEmpty,
      reason: 'Missing from the PATH: ${missing.join(', ')}. The tests of the Claude Code hooks '
          '(bash_rules_hook_test.dart, changelog_current_hook_test.dart) would skip themselves, and this run '
          'would not be CI\'s. To fix: ${missing.map((t) => '$t: ${_fix(t)}').join('; ')}.',
    );
  });
}
