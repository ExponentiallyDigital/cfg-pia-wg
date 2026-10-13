// test/unit/posix_shell_test.dart - the script tests' shell, in WSL or not (ID-355). These hold
// whichever shell this machine uses: WSL on Windows when there is one, Git Bash otherwise, and the
// plain shell everywhere else.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

void main() {
  final shell = findShell();

  group('shPath', () {
    test('a Windows path is translated for WSL, and only given forward slashes otherwise', () {
      expect(shPath(r'C:\Users\a\b.sh'), usesWsl ? '/mnt/c/Users/a/b.sh' : 'C:/Users/a/b.sh');
    });

    test('mixed separators, as a test builds them from a temp folder, come out whole', () {
      expect(shPath(r'D:\tmp\guard_x/bin/service'), usesWsl ? '/mnt/d/tmp/guard_x/bin/service' : 'D:/tmp/guard_x/bin/service');
    });

    test('a path that is already a shell path is left alone', () {
      expect(shPath('/tmp/x'), '/tmp/x');
    });
  });

  group('runSh', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('posix_shell_');
      Directory('${dir.path}/bin').createSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a file named by its path on this machine is found by the shell', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final f = File('${dir.path}/note.txt')..writeAsStringSync('hello');
      final r = await runSh(shell, ['-c', r'cat "$1"', 'sh', f.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}', 'hello');
    });

    test('a variable holding a path crosses over, and points at the same folder', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/nv_x').writeAsStringSync('42');
      final r = await runSh(shell, ['-c', r'cat "$STATE/nv_x"'], environment: {'STATE': dir.path});
      expect('${r.stdout}', '42', reason: '${r.stderr}');
    });

    test('a value that is not a path crosses over unchanged', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final r = await runSh(shell, ['-c', r'printf %s "$LW_WAIT"'], environment: {'LW_WAIT': '1'});
      expect('${r.stdout}', '1');
    });

    test('the fake commands, first on the PATH given, are found ahead of the real ones', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/bin/nvram').writeAsStringSync('#!/bin/sh\necho fake-nvram\n');
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/nvram']);
      final sep = Platform.isWindows ? ';' : ':';
      // The command line every harness uses: the PATH's first entry, then the shell's own tools.
      final r = await runSh(shell, ['-c', r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; nvram get x'],
          environment: {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}'});
      expect('${r.stdout}'.trim(), 'fake-nvram', reason: '${r.stderr}');
    });

    test('a started shell can be waited on, as the two-watchdogs tests do', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final p = await startSh(shell, ['-c', 'echo started']);
      final out = await p.stdout.transform(const SystemEncoding().decoder).join();
      expect(await p.exitCode, 0);
      expect(out.trim(), 'started');
    });
  });
}
