// scripts/check-claims.sh's server list checks (ID-325), run here against the real watchdog script so
// the two can't drift apart: a renamed function in the watchdog would leave the hardware check
// reporting INFO, or passing, while proving nothing.
//
// Section 1b, read-only, lifts the deployed watchdog's own check out and runs it on PIA's list and on
// copies broken on purpose; here PIA's list is the fixture rather than a download. Section 8 builds
// copies of the watchdog for three real rebuilds; here they run against the fake router in
// test/watchdog_harness.dart. Neither replaces running check-claims.sh on the router: the router's
// own openssl and BusyBox are what it proves.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../server_list_test_key.dart' show kRealServerListFixture;
import '../watchdog_harness.dart';

final _cc = File('scripts/check-claims.sh').readAsStringSync();
String _fn(String name) => RegExp('^$name\\(\\) \\{[^\\n]*\\n[\\s\\S]*?\\n\\}\\n', multiLine: true).firstMatch(_cc)!.group(0)!;

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) h = WatchdogHarness.create(shell: shell)!;
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  group('section 1b, read-only', () {
    /// Section 1b as written, with D the harness's app directory holding [script] as the deployed
    /// watchdog, and the download answered from the fixture.
    Future<String> section1b(String script) async {
      final r = shPath(h.root.path);
      File('${h.root.path}/jffs/cfg-pia-wg/watchdog_wgc1.sh').writeAsStringSync(script);
      final section = RegExp(r'^# ---- 1b\.[\s\S]*?(?=^# ---- 2\. Mail)', multiLine: true).firstMatch(_cc)!.group(0)!;
      File('${h.root.path}/s1b.sh').writeAsStringSync('''
PASSN=0; FAILN=0; D="$r/jffs/cfg-pia-wg"
pass() { PASSN=\$((PASSN + 1)); echo "PASS \$1 \$2"; }
fail() { FAILN=\$((FAILN + 1)); echo "FAIL \$1 \$2: \$3"; }
info() { echo "INFO \$1 \$2"; }
bounded() { while [ \$# -gt 0 ]; do [ "\$1" = -o ] && cp "$r/state/serverlist" "\$2"; shift; done; RC=0; }
${section.replaceAll('/tmp/', '$r/tmp/')}''');
      final res = await runSh(shell!, ['${h.root.path}/s1b.sh']);
      return '${res.stdout}${res.stderr}';
    }

    test("PIA's list passes, and copies with a region moved or the signature off are refused", () async {
      h.savedServerList.writeAsBytesSync(File(kRealServerListFixture).readAsBytesSync());
      h.savedServerListDate.writeAsStringSync('2026-10-14 11:00 +1100\n');
      final out = await section1b(h.script());
      expect(out, contains("PASS SIGLIST-0 control: PIA's list as it arrives today passes"));
      expect(out, contains('PASS SIGLIST-moved'));
      expect(out, contains('PASS SIGLIST-nosig'));
      expect(out, contains("PASS SIGLIST-kept the router's kept list passes the check (kept 2026-10-14 11:00 +1100)"));
      expect(out, isNot(contains('FAIL')));
    });

    test('a kept list that fails is a FAIL: there is nothing to fall back on', () async {
      h.savedServerList.writeAsStringSync('{"regions":[]}\n');
      expect(await section1b(h.script()), contains('FAIL SIGLIST-kept'));
    });

    // The negative control, seen to fail: a watchdog whose check always passes.
    test('a watchdog whose check is taken out FAILs, rather than reading as an old one', () async {
      final broken = h.script().replaceFirst('list_verified() {\n', 'list_verified() { head -1 "\$1" > "\$SLDATA"; return 0\n');
      final out = await section1b(broken);
      expect(out, contains('FAIL SIGLIST-moved'));
      expect(out, contains('FAIL SIGLIST-nosig'));
    });

    test('a watchdog from before the check says so', () async {
      final old = h.script().replaceAll('list_verified()', 'old_name()');
      expect(await section1b(old), contains('INFO SIGLIST the deployed watchdog has no signature check'));
    });
  }, skip: skip);

  group('section 8, the rebuild variants', () {
    /// The copy of [h]'s watchdog that section 8's sig_variant makes, with the kept list at [kept].
    Future<String> variantOf(String kept, {bool nocheck = false}) async {
      final r = shPath(h.root.path);
      final tamper = RegExp(r"<<'TAMPEREOF'\n([\s\S]*?)TAMPEREOF").firstMatch(_cc)!.group(1)!;
      final dir = Directory('${h.root.path}/cc')..createSync();
      File('${dir.path}/tamper.sh').writeAsStringSync(tamper);
      File('${dir.path}/w1.sh').writeAsStringSync(h.script());
      File('${dir.path}/make.sh').writeAsStringSync('W1="$r/cc/w1.sh"; SLDIR="$r/cc"; DOHIP=""; SIGMAIL=0\n'
          '${_fn('variant').replaceAll('/tmp/', '$r/cc/')}${_fn('sig_variant').replaceAll('/tmp/', '$r/cc/')}'
          'sig_variant "$kept" "$kept.date"${nocheck ? ' nocheck' : ''}\n');
      final res = await runSh(shell!, ['${dir.path}/make.sh']);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      return File('${dir.path}/check-claims-wd.sh').readAsStringSync();
    }

    int count(String s) => h.log.where((l) => l.contains(s)).length;

    test("sig-fallback: the tampered list is refused and the router's kept list used", () async {
      final kept = '${shPath(h.root.path)}/jffs/cfg-pia-wg/kept.txt';
      File('${h.root.path}/jffs/cfg-pia-wg/kept.txt').writeAsBytesSync(File(kRealServerListFixture).readAsBytesSync());
      final v = await variantOf(kept);
      h.tunnelUp(handshakeAgo: null);
      await h.run(edit: (_) => v);
      expect(count("failed PIA's signature check, so it is not used"), 1);
      expect(count('Using the last server list that passed'), 1);
      expect(count('Reconfig SUCCESS'), 1);
    });

    test('sig-refused: with no kept list, nothing is used', () async {
      final v = await variantOf('${shPath(h.root.path)}/tmp/check-claims-nokept');
      h.tunnelUp(handshakeAgo: null);
      await h.run(edit: (_) => v);
      expect(h.log.where((l) => l.startsWith("ERROR: PIA's server list failed its signature check")).length, 1);
      expect(h.log.where((l) => l.startsWith('Selected server')), isEmpty);
      expect(count('Reconfig SUCCESS'), 0);
    });

    test('sig-nocheck, the control: with the check taken out, the tampered list is used', () async {
      final v = await variantOf('${shPath(h.root.path)}/tmp/check-claims-nokept', nocheck: true);
      h.tunnelUp(handshakeAgo: null);
      await h.run(edit: (_) => v);
      expect(count("failed PIA's signature check"), 0);
      expect(h.log.where((l) => l.startsWith('Selected server')).length, 1);
      expect(count('Reconfig SUCCESS'), 1);
      expect(File('${h.root.path}/tmp/check-claims-nokept').readAsStringSync(), contains('"country":"ZZ"'),
          reason: 'the tampered list was the one used, and it was kept in /tmp, not over the router\'s');
      expect(h.savedServerList.existsSync(), isFalse);
    });
  }, skip: skip);
}
