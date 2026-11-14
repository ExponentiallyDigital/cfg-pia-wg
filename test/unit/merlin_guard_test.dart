// test/unit/merlin_guard_test.dart - merlin-guard.sh against a fake `ip` (ID-557, ID-567, ID-574).
//
// The script keeps each device VPN Director sends to a tunnel on that tunnel or nowhere, exempts the
// router's own address from a whole-network rule, and tidies each tunnel's table as Merlin starts
// it. That it holds on a real router was measured on 2026-11-14 (a `prohibit` at 11409 kept a device
// offline through DISABLE; at 12300, behind a whole-network rule, it didn't). What these check is
// what the script does with the rules file it's given: which rules it adds and takes out, in which
// order, and which routes it leaves. The fake `ip` keeps its rules and tables in files.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cfg_pia_wg/merlin_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

const _nvram = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/nv/$2" 2>/dev/null
exit 0
''';

// `ip rule show|add|del`, `ip route show|del ... table T` and `ip link show`, on files in $STATE.
const _ip = r'''#!/bin/sh
R="$STATE/rules"
parse() { S=""; P=""; A=""; T=""
  while [ $# -gt 0 ]; do
    case "$1" in from) S="$2"; shift 2 ;; priority) P="$2"; shift 2 ;; table) T="$2"; shift 2 ;; *) A="$A $1"; shift ;; esac
  done; A="${A# }"; }
case "$1 $2" in
  "rule show") cat "$R" 2>/dev/null ;;
  "rule add") shift 2; parse "$@"; printf '%s:\tfrom %s %s\n' "$P" "$S" "$A" >> "$R"; echo "add $P $S" >> "$STATE/log" ;;
  "rule del") shift 2; parse "$@"; printf '%s:\tfrom %s %s\n' "$P" "$S" "$A" > "$STATE/one"
    grep -vxF -f "$STATE/one" "$R" > "$R.n"; mv "$R.n" "$R"; echo "del $P $S" >> "$STATE/log" ;;
  "route show") cat "$STATE/table_$4" 2>/dev/null ;;
  "route del") D="$3"; shift 3; parse "$@"; grep -v "^$D " "$STATE/table_$T" > "$STATE/t.n"; mv "$STATE/t.n" "$STATE/table_$T" ;;
  "link show") [ -f "$STATE/link_$3" ] ;;
esac
''';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('merlin_guard_');
    state = '${dir.path}/state';
    Directory('$state/nv').createSync(recursive: true);
    Directory('${dir.path}/bin').createSync();
    File('${dir.path}/bin/nvram').writeAsStringSync(_nvram);
    File('${dir.path}/bin/ip').writeAsStringSync(_ip);
    File('${dir.path}/bin/logger').writeAsStringSync('#!/bin/sh\nshift 2; echo "\$*" >> "\$STATE/syslog"\n');
    File('${dir.path}/merlin-guard.sh').writeAsStringSync(kMerlinGuardScript);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    File('$state/nv/lan_ipaddr').writeAsStringSync('192.168.1.254');
    // Merlin's own rule for the tablet, which the script must never touch.
    File('$state/rules').writeAsStringSync('0:\tfrom all lookup local\n11210:\tfrom 192.168.1.55 lookup wgc1\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The rules file as the web page writes it: no trailing newline.
  void rulelist(String raw) => File('$state/rulelist').writeAsStringSync(raw);
  List<String> rules() => File('$state/rules').readAsLinesSync().where((l) => l.isNotEmpty).toList();
  List<String> log() => File('$state/log').existsSync() ? File('$state/log').readAsLinesSync() : [];

  List<String> syslog() => File('$state/syslog').existsSync() ? File('$state/syslog').readAsLinesSync() : [];

  Future<String> run([List<String> args = const [], Map<String, String> extra = const {}]) async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state, ...extra};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed "s#/jffs/openvpn/vpndirector_rulelist#$STATE/rulelist#" "$1" > g.sh && shift && exec sh g.sh "$@"';
    final r = await runSh(shell!, ['-c', cmd, 'sh', '${dir.path}/merlin-guard.sh', ...args], environment: env);
    return '${r.stdout}${r.stderr}';
  }

  test('each device sent to a tunnel gets a prohibit at the top of its slot, the last record included', () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('<1>tablet>192.168.1.55>>WGC1<0>off>192.168.1.60>>WGC1<1>phone>192.168.1.94>>WAN<1>desktop>192.168.1.250>>WGC5');
    final out = await run();
    expect(rules(), containsAll(['11409:\tfrom 192.168.1.55 prohibit', '12209:\tfrom 192.168.1.250 prohibit']), reason: out);
    expect(rules().where((r) => r.contains('192.168.1.60') || r.contains('192.168.1.94')), isEmpty,
        reason: 'a switched-off rule and a WAN pin need no hold');
    expect(out, contains('guarded 2 of 2'));
  });

  test("a whole-network rule exempts the router's own address", () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('<1>default>192.168.1.0/24>>WGC5');
    final out = await run();
    expect(rules(), contains('9990:\tfrom 192.168.1.254 lookup main'), reason: out);
    expect(out, contains('guarded 0 of 0'));
  });

  test('a device moved between slots gets its new hold before the old one goes', () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('<1>tablet>192.168.1.55>>WGC1');
    await run();
    File('$state/log').deleteSync();
    rulelist('<1>tablet>192.168.1.55>>WGC5');
    await run();
    expect(log(), ['add 12209 192.168.1.55', 'del 11409 192.168.1.55']);
    expect(rules(), containsAll(['12209:\tfrom 192.168.1.55 prohibit', '11210:\tfrom 192.168.1.55 lookup wgc1']));
    expect(rules().where((r) => r.startsWith('11409:')), isEmpty);
  });

  test("an unchanged file changes nothing, and Merlin's own rules are never touched", () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('<1>tablet>192.168.1.55>>WGC1');
    await run();
    File('$state/log').deleteSync();
    await run();
    expect(log(), isEmpty);
    rulelist('<0>tablet>192.168.1.55>>WGC1');
    await run();
    expect(rules(), ['0:\tfrom all lookup local', '11210:\tfrom 192.168.1.55 lookup wgc1']);
  });

  test("a running tunnel's table keeps its own, LAN and endpoint routes; another tunnel's and the WAN's go", () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('');
    File('$state/link_wgc5').writeAsStringSync('');
    File('$state/nv/wgc5_ep_addr_r').writeAsStringSync('198.51.100.20');
    File('$state/table_wgc5').writeAsStringSync([
      '0.0.0.0/1 dev wgc5 scope link',
      '9.9.9.9 dev wgc1 scope link',
      '1.1.1.2 via 203.0.113.1 dev eth0 metric 1',
      '192.168.1.0/24 dev br0 proto kernel scope link src 192.168.1.254',
      '198.51.100.20 via 203.0.113.1 dev eth0',
      'default via 203.0.113.1 dev eth0',
      '10.6.0.2 dev wgs1 scope link',
      '',
    ].join('\n'));
    final out = await run();
    expect(File('$state/table_wgc5').readAsLinesSync().where((l) => l.isNotEmpty), [
      '0.0.0.0/1 dev wgc5 scope link',
      '192.168.1.0/24 dev br0 proto kernel scope link src 192.168.1.254',
      '198.51.100.20 via 203.0.113.1 dev eth0',
      '10.6.0.2 dev wgs1 scope link',
    ], reason: out);
    expect(out, contains('tidied wgc5: 9.9.9.9'));
  });

  test("`table N` tidies only that tunnel's table, as wgclient-start asks", () async {
    if (shell == null) return markTestSkipped(_noShell);
    File('$state/table_wgc1').writeAsStringSync('9.9.9.9 dev wgc5 scope link\n0.0.0.0/1 dev wgc1 scope link\n');
    File('$state/table_wgc5').writeAsStringSync('9.9.9.9 dev wgc1 scope link\n');
    await run(['table', '1']);
    expect(File('$state/table_wgc1').readAsLinesSync().where((l) => l.isNotEmpty), ['0.0.0.0/1 dev wgc1 scope link']);
    expect(File('$state/table_wgc5').readAsStringSync(), contains('9.9.9.9 dev wgc1'), reason: 'not asked for');
  });

  // ID-582: Merlin clears every rule as the WAN comes up (`ip rule flush` in add_multi_routes), after
  // services-start and before any tunnel starts. Measured 2026-11-14: the rules there 21 s after boot,
  // gone at 31 s, and still gone after both tunnels started.
  group('after Merlin clears the rules', () {
    // The rules file, and the kernel's rules as the flush leaves them: Merlin's kill switch alone.
    void flushed() {
      rulelist('<1>tablet>192.168.1.55>>WGC1<1>default>192.168.1.0/24>>WGC5');
      File('$state/rules').writeAsStringSync('0:\tfrom all lookup local\n12215:\tfrom 192.168.1.55 prohibit\n');
    }

    test('`table N`, as each tunnel starts, puts them back and says so in the router log', () async {
      if (shell == null) return markTestSkipped(_noShell);
      flushed();
      final out = await run(['table', '1']);
      expect(rules(), containsAll(['11409:\tfrom 192.168.1.55 prohibit', '9990:\tfrom 192.168.1.254 lookup main']), reason: out);
      expect(syslog(), ['merlin-guard: wgc1 started: guarded 1 of 1']);
    });

    test('the watch after boot puts them back whenever they are found missing', () async {
      if (shell == null) return markTestSkipped(_noShell);
      flushed();
      File('$state/nv/ntp_ready').writeAsStringSync('0');
      final out = await run(['watch'], {'GUARD_WATCH_STEP': '0', 'GUARD_WATCH_MAX': '2'});
      expect(rules(), containsAll(['11409:\tfrom 192.168.1.55 prohibit', '9990:\tfrom 192.168.1.254 lookup main']), reason: out);
      expect(syslog(), ['merlin-guard: put back 2 rule(s) the router cleared: guarded 1 of 1'],
          reason: 'once: the second look finds nothing missing');
    });

    test('the watch stops once the clock has been set long enough for the tunnels to start', () async {
      if (shell == null) return markTestSkipped(_noShell);
      rulelist('');
      File('$state/nv/ntp_ready').writeAsStringSync('1');
      // Without the stop it would make its 900 looks a second apart.
      await run(['watch'], {'GUARD_WATCH_STEP': '1', 'GUARD_WATCH_AFTER_SYNC': '2'}).timeout(const Duration(seconds: 30));
    });

    test('`boot` holds them at once, and leaves the watch running behind it', () async {
      if (shell == null) return markTestSkipped(_noShell);
      flushed();
      final out = await run(['boot'], {'GUARD_WATCH_MAX': '0'});
      expect(rules(), contains('11409:\tfrom 192.168.1.55 prohibit'), reason: out);
      expect(syslog(), contains('merlin-guard: boot: guarded 1 of 1'));
      expect(kMerlinGuardScript, contains('watch </dev/null >/dev/null 2>&1 &'));
      expect(kMerlinGuardBootLine, contains("merlin-guard.sh' boot "), reason: 'services-start asks for the watch');
    });
  });

  group('MerlinGuard, the app side', () {
    /// A router with the script already in place, answering its run with [out] and recording every
    /// command. (Writing it is writeRouterFile's, tested with that.)
    (MerlinGuard, List<String>, List<String>) guard(String out) {
      final cmds = <String>[], logs = <String>[];
      Future<String> answer(String c) async {
        cmds.add(c);
        if (c.startsWith("cat '$kMerlinGuardScriptPath'")) return kMerlinGuardScript;
        if (c == "'$kMerlinGuardScriptPath'") return out;
        return '';
      }

      return (
        MerlinGuard(read: answer, run: answer, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m)),
        cmds,
        logs,
      );
    }

    test('says so when it holds fewer pinned devices than it should', () async {
      final (g, _, logs) = guard('guarded 1 of 2');
      expect(await g.ensure(), 1);
      expect(logs.single, contains('holds only 1 of 2 pinned devices'));
    });

    test("turns on Merlin's scripts, and puts its line in each hook, replacing an older one of its own", () async {
      final (g, cmds, _) = guard('guarded 0 of 0');
      await g.ensure(quiet: true);
      expect(cmds, contains(contains('nvram set jffs2_scripts=1')));
      for (final (path, line) in [('/jffs/scripts/services-start', kMerlinGuardBootLine), (kWgclientStartPath, kMerlinGuardStartLine)]) {
        final q = line.replaceAll("'", r"'\''");
        expect(
            cmds,
            contains(allOf(contains("grep -qxF '$q' '$path' ||"), contains("grep -vF '$kMerlinGuardHookTag' '$path' > '$path.tmp'"),
                contains(">> '$path'"))),
            reason: path);
      }
    });

    test('a failure is reported, not thrown, so the change it follows goes ahead', () async {
      final logs = <String>[];
      final g = MerlinGuard(
          read: (_) async => '',
          run: (_) async => throw Exception('no route to router'),
          onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => logs.add(m));
      expect(await g.ensure(), isNull);
      expect(logs.single, contains("couldn't be put in place"));
    });

    test('clear runs the script and takes the tagged lines out of both hooks', () async {
      final (g, cmds, _) = guard('');
      await g.clear();
      expect(cmds.first, contains("'$kMerlinGuardScriptPath' clear"));
      expect(cmds.where((c) => c.contains("grep -vF '$kMerlinGuardHookTag'")), hasLength(2));
    });
  });

  test("`clear` takes out every rule of the script's and nothing else", () async {
    if (shell == null) return markTestSkipped(_noShell);
    rulelist('<1>tablet>192.168.1.55>>WGC1<1>default>192.168.1.0/24>>WGC5');
    await run();
    expect(rules().length, 4);
    await run(['clear']);
    expect(rules(), ['0:\tfrom all lookup local', '11210:\tfrom 192.168.1.55 lookup wgc1']);
  });
}
