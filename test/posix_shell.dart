// test/posix_shell.dart - where the script tests run their shell (ID-355).
//
// The script tests run the real router scripts against fake router commands, and almost all of
// their time is the shell starting processes. Git Bash does that slowly; WSL's Linux does it about
// ten times faster. Measured 2026-10-13, the whole suite, one run after another on one machine:
// 218 s with Git Bash, 34 s through WSL. Making the fake commands shell functions was tried first
// and was slower (CHANGELOG ID-355).
//
// So on Windows, when WSL has a working Linux, the shell runs there. The test folders stay where
// they are, on C:, which WSL sees under /mnt/c, so the tests read and write them as before; only
// paths handed to the shell are translated. Anywhere else - Linux CI, a Mac, Windows without WSL -
// nothing changes. CFG_TEST_SHELL=gitbash forces Git Bash on Windows, to compare the two or to rule
// WSL out when a test behaves differently.
//
// Under WSL the shell is the distribution's `sh` (dash on Ubuntu), the same as on Linux CI, and
// closer to the router's BusyBox ash than Git Bash's bash is.
import 'dart:io';

/// Whether the script tests' shell runs in WSL. Decided once per test file, on first use.
final bool usesWsl = _detectWsl();

bool _detectWsl() {
  if (!Platform.isWindows || Platform.environment['CFG_TEST_SHELL'] == 'gitbash') return false;
  try {
    // A WSL that starts but lacks a tool the scripts need is no use: Git Bash then.
    final r = Process.runSync('wsl.exe', [
      '-e',
      'sh',
      '-c',
      'for t in awk sed grep sort tr od base64 sleep; do command -v "\$t" >/dev/null || exit 1; done; echo ok',
    ]);
    return r.exitCode == 0 && '${r.stdout}'.trim() == 'ok';
  } catch (_) {
    return false; // No wsl.exe at all.
  }
}

final RegExp _windowsPath = RegExp(r'^([A-Za-z]):[\\/](.*)$');

/// [path], a path on this machine, as the shell sees it: `/mnt/c/...` under WSL, otherwise with
/// forward slashes, which Git Bash and every Unix shell accept.
String shPath(String path) {
  final m = _windowsPath.firstMatch(path);
  if (usesWsl && m != null) return '/mnt/${m.group(1)!.toLowerCase()}/${m.group(2)!.replaceAll('\\', '/')}';
  return path.replaceAll('\\', '/');
}

/// Runs `shell args...`, as Process.run would, but in WSL when [usesWsl].
Future<ProcessResult> runSh(String shell, List<String> args, {Map<String, String>? environment}) {
  final (exe, a, env) = _translate(shell, args, environment);
  return Process.run(exe, a, environment: env);
}

/// Starts `shell args...`, as Process.start would, but in WSL when [usesWsl].
Future<Process> startSh(String shell, List<String> args, {Map<String, String>? environment}) {
  final (exe, a, env) = _translate(shell, args, environment);
  return Process.start(exe, a, environment: env);
}

/// Unchanged unless [usesWsl]. Then: `wsl.exe -e sh ...`, every Windows path among the arguments
/// and variables translated, and the variables handed across with WSLENV, which passes only the
/// ones it names. PATH can't cross that way - WSL builds its own - so the first entry of the PATH
/// given, the fake commands' folder in every harness, goes across as STUBBIN and is put back at the
/// front of the shell's PATH, where each harness's own command line expects to find it.
(String, List<String>, Map<String, String>?) _translate(String shell, List<String> args, Map<String, String>? environment) {
  if (!usesWsl) return (shell, args, environment);
  final env = <String, String>{};
  for (final e in (environment ?? const <String, String>{}).entries) {
    if (e.key == 'PATH') {
      env['STUBBIN'] = shPath(e.value.split(';').first);
    } else {
      env[e.key] = _windowsPath.hasMatch(e.value) ? shPath(e.value) : e.value;
    }
  }
  final inherited = Platform.environment['WSLENV'] ?? '';
  env['WSLENV'] = [if (inherited.isNotEmpty) inherited, for (final k in env.keys) '$k/u'].join(':');
  final translated = [
    for (var i = 0; i < args.length; i++)
      if (i == 1 && args[0] == '-c' && env.containsKey('STUBBIN'))
        'PATH="\$STUBBIN:\$PATH"; export PATH; ${args[i]}'
      else if (_windowsPath.hasMatch(args[i]))
        shPath(args[i])
      else
        args[i],
  ];
  return ('wsl.exe', ['-e', 'sh', ...translated], env);
}
