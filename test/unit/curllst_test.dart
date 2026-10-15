// test/unit/curllst_test.dart - our router scripts leave nothing in ASUS's curl log, and check-claims
// looks for the PIA password in every copy of it (ID-400).
//
// ASUS's /usr/sbin/curl writes every command line it runs to /jffs/curllst and rotates it to
// curllst.1 and on. On 2026-10-15 both were found holding lines from our test scripts, and
// check-claims' SECRET-curllst looked in curllst only, so a password in a rotated copy passed. These
// run the scripts' own code, lifted out of them, against a /jffs of the test's own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

void main() {
  final shell = findShell();
  late Directory dir;
  late String jffs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('curllst_');
    jffs = '${dir.path}/jffs';
    Directory(jffs).createSync();
    Directory('${dir.path}/bin').createSync();
    // nvram: the PIA password the SECRET check looks for.
    File('${dir.path}/bin/nvram').writeAsStringSync('#!/bin/sh\n[ "\$2" = cfg_pia_wg_password ] && printf s3cr3t-pw\nexit 0\n');
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/nvram']);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs [body] with /jffs/ and /tmp/ moved into the test's folder, and pass/fail/info that print.
  Future<String> runShell(String body) async {
    final r = shPath(dir.path);
    final script = 'pass() { echo "PASS \$1 \$2"; }\nfail() { echo "FAIL \$1 \$2: \$3"; }\ninfo() { echo "INFO \$1 \$2"; }\n'
        '${body.replaceAll('/jffs/', '$r/jffs/').replaceAll('/tmp/', '$r/')}';
    File('${dir.path}/t.sh').writeAsStringSync(script);
    final sep = Platform.isWindows ? ';' : ':';
    final res = await runSh(shell!, ['-c', r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$1"', 'sh', '${dir.path}/t.sh'],
        environment: {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}'});
    return '${res.stdout}${res.stderr}';
  }

  String fn(String file) =>
      RegExp(r'^curllst_clear\(\) \{.*\}$', multiLine: true).firstMatch(File(file).readAsStringSync())!.group(0)!;

  for (final script in ['scripts/check-claims.sh', 'scripts/runner-tunnel-speed.sh']) {
    test('$script empties curllst and every rotated copy, and nothing else', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      for (final f in ['curllst', 'curllst.1', 'curllst.2', 'nmp_cl_json.js']) {
        File('$jffs/$f').writeAsStringSync('[1792027977](1)curl -s https://example.com/\n');
      }
      await runShell('${fn(script)}\ncurllst_clear\n');
      for (final f in ['curllst', 'curllst.1', 'curllst.2']) {
        expect(File('$jffs/$f').lengthSync(), 0, reason: f);
      }
      expect(File('$jffs/nmp_cl_json.js').lengthSync(), greaterThan(0), reason: "the firmware's own file is left alone");
    });
  }

  test('every script of ours that runs curl on the router empties the log', () {
    for (final f in ['scripts/check-claims.sh', 'scripts/runner-tunnel-speed.sh', 'scripts/get-bins.sh', 'scripts/check-reboot.sh']) {
      expect(File(f).readAsStringSync(), contains('for F in /jffs/curllst /jffs/curllst.[0-9]*; do'), reason: f);
    }
  });

  group("check-claims' SECRET-curllst", () {
    String section() {
      final s = File('scripts/check-claims.sh').readAsStringSync();
      return RegExp(r'^PW="\$\(nvram get cfg_pia_wg_password\)"[\s\S]*?^PW=""$', multiLine: true).firstMatch(s)!.group(0)!;
    }

    test('finds the password in a rotated copy, and names it', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$jffs/curllst').writeAsStringSync('clean\n');
      File('$jffs/curllst.1').writeAsStringSync('curl -u p1234567:s3cr3t-pw https://www.privateinternetaccess.com/\n');
      final out = await runShell(section());
      expect(out, contains('FAIL SECRET-curllst'), reason: out);
      expect(out, contains('curllst.1:1'));
    });

    test('passes when no copy holds it', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$jffs/curllst').writeAsStringSync('clean\n');
      File('$jffs/curllst.1').writeAsStringSync('also clean\n');
      final out = await runShell(section());
      expect(out, contains('PASS SECRET-curllst'), reason: out);
    });

    test('passes when there are none at all', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final out = await runShell(section());
      expect(out, contains('or a rotated copy (there are none)'), reason: out);
    });
  });
}
