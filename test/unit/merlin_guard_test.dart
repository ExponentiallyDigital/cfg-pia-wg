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
import 'package:cfg_pia_wg/router_script_integrity.dart' show scriptEndLine;
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

// Like the router's, `nvram get` ends its answer with a newline.
const _nvram = r'''#!/bin/sh
[ "$1" = get ] && { cat "$STATE/nv/$2" 2>/dev/null; echo; }
exit 0
''';

// `ip rule show|add|del`, `ip route show|del ... table T` and `ip link show`, on files in $STATE.
const _ip = r'''#!/bin/sh
R="$STATE/rules"
parse() { S=""; P=""; A=""; T=""
  while [ $# -gt 0 ]; do
    case "$1" in from) S="$2"; shift 2 ;; priority) P="$2"; shift 2 ;; table) T="$2"; shift 2 ;; *) A="$A $1"; shift ;; esac
  done; A="${A# }"; [ -n "$S" ] || S=all; }
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

// `iptables -t raw -S|-C|-I|-D OUTPUT -d <addr> ! -o wgc+ -j DROP`, on a file in $STATE, one rule a line as -S prints it.
// Anything but the raw table does nothing, so the script can't be seen to use another one.
const _iptables = r'''#!/bin/sh
F="$STATE/raw"
[ "$1 $2" = "-t raw" ] || { echo "other table: $*" >> "$STATE/iplog"; exit 0; }
shift 2
OP="$1"; CH="$2"; shift 2
[ -e "$STATE/refuse" ] && [ "$OP" = -I ] && exit 1
LINE="-A $CH -d $2/32 ! -o wgc+ -j DROP"
case "$OP" in
  -S) cat "$F" 2>/dev/null ;;
  -C) grep -qxF -- "$LINE" "$F" 2>/dev/null ;;
  -I) echo "$LINE" >> "$F"; echo "I $2" >> "$STATE/iplog" ;;
  -D) grep -qxF -- "$LINE" "$F" 2>/dev/null || exit 1; grep -vxF -- "$LINE" "$F" > "$F.n"; mv "$F.n" "$F"; echo "D $2" >> "$STATE/iplog" ;;
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
    File('${dir.path}/bin/iptables').writeAsStringSync(_iptables);
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
    final env = {
      'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state,
      // Where the script keeps its errors, and finds the watchdogs it reports through (ID-607).
      'GUARD_ERR': '$state/guard.err',
      'GUARD_APPDIR': '$state/app',
      ...extra,
    };
    // CUT=1 takes the script's last line off, as a write cut short would.
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed "s#/jffs/openvpn/vpndirector_rulelist#$STATE/rulelist#" "$1" > g.sh && shift && '
        r'{ [ -z "$CUT" ] || { sed "\$d" g.sh > g.cut && mv g.cut g.sh; }; } && exec sh g.sh "$@"';
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

  // ID-607: stock's guard.sh checks its own last line and keeps its errors for a watchdog to email
  // (ID-484, ID-485). merlin-guard.sh did neither, and the watchdog's list of slots to email about
  // was empty on Merlin, so a damaged or failing guard went unnoticed.
  group('its own faults', () {
    List<File> errFiles() => [
          for (final f in Directory(state).listSync().whereType<File>())
            if (f.uri.pathSegments.last.startsWith('guard.err.')) f,
        ];

    /// A watchdog for each of [slots] that records what it was run with.
    void watchdogs(List<int> slots) {
      Directory('$state/app').createSync();
      for (final s in slots) {
        final f = File('$state/app/watchdog_wgc$s.sh')..writeAsStringSync('#!/bin/sh\necho "wgc$s: \$*" >> "\$STATE/faults"\n');
        if (!Platform.isWindows) Process.runSync('chmod', ['+x', f.path]);
      }
    }

    List<String> faults() => File('$state/faults').existsSync() ? File('$state/faults').readAsLinesSync() : [];

    test('ends with the line it checks itself for', () {
      expect(kMerlinGuardScript.trimRight().split('\n').last, scriptEndLine('merlin-guard.sh'));
    });

    test('cut short, it changes nothing, says so in the log, and each guarded slot reports it', () async {
      if (shell == null) return markTestSkipped(_noShell);
      // wgc1 and wgc5 have a device of their own; wgc3 has only a switched-off rule, wgc2 a range.
      rulelist('<1>tablet>192.168.1.55>>WGC1<0>off>192.168.1.60>>WGC3<1>range>192.168.1.128/25>>WGC2'
          '<1>phone>192.168.1.94>>WAN<1>desktop>192.168.1.250>>WGC5');
      watchdogs([1, 2, 3, 5]);
      final before = rules();
      await run([], {'CUT': '1'});
      expect(rules(), before, reason: 'no rule added or taken out by half a script');
      expect(syslog().single, startsWith('ERROR: merlin-guard.sh is damaged ('));
      expect(faults(), hasLength(2));
      expect(faults()[0], startsWith('wgc1: fault merlin-guard.sh is damaged ('));
      expect(faults()[1], startsWith('wgc5: fault merlin-guard.sh is damaged ('));
    });

    test('whole, it reports nothing and leaves no error file', () async {
      if (shell == null) return markTestSkipped(_noShell);
      rulelist('<1>tablet>192.168.1.55>>WGC1');
      watchdogs([1]);
      final out = await run();
      expect(out, contains('guarded 1 of 1'));
      expect(faults(), isEmpty);
      expect(errFiles(), isEmpty);
    });

    test('a rule it could not add is kept as an error, for the next watchdog run to report', () async {
      if (shell == null) return markTestSkipped(_noShell);
      rulelist('<1>tablet>192.168.1.55>>WGC1');
      // An `ip` that refuses to add a rule, as a full rule table or a kernel error would.
      File('${dir.path}/bin/ip').writeAsStringSync(_ip.replaceFirst('"rule add") shift 2;', '"rule add") exit 2; shift 2;'));
      final out = await run();
      expect(out, contains('guarded 0 of 1'));
      expect(errFiles(), hasLength(1));
      expect(errFiles().single.readAsStringSync(), contains('holds 0 of 1'));
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
      for (final (path, line) in [
        ('/jffs/scripts/services-start', kMerlinGuardBootLine),
        (kWgclientStartPath, kMerlinGuardStartLine),
        (kServiceEventEndPath, kMerlinGuardEventLine),
      ]) {
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

    test('clear runs the script and takes the tagged lines out of each hook', () async {
      final (g, cmds, _) = guard('');
      await g.clear();
      expect(cmds.first, contains("'$kMerlinGuardScriptPath' clear"));
      expect(cmds.where((c) => c.contains("grep -vF '$kMerlinGuardHookTag'")), hasLength(3));
    });

    test("the service-event-end line runs the hold for a DNS change's events only, in the background", () {
      expect(kMerlinGuardEventLine, contains('"restart wan_if"|"restart wan_dns"|"restart stubby"|"restart dnsmasq"|"restart dnspriv"'));
      expect(kMerlinGuardEventLine, contains("'$kMerlinGuardScriptPath' hold </dev/null >/dev/null 2>&1 &"));
      expect(kMerlinGuardEventLine, endsWith(kMerlinGuardHookTag));
    });
  });

  // ID-636: when the slot that holds a DNS address the router also uses is stopped, the router's own lookups left by
  // the WAN (465 connections to each address in 30 s, measured 2026-11-20 and 2026-11-22). The hold is a rule in the raw
  // table, armed only once the clock is set, for the addresses both the router and a slot list. The fake `iptables`
  // keeps the raw table in a file; what these check is which addresses the script holds, and when.
  group('the hold on a DNS address a slot shares with the router (ID-636)', () {
    void nv(String key, String value) => File('$state/nv/$key').writeAsStringSync(value);
    List<String> raw() =>
        File('$state/raw').existsSync() ? File('$state/raw').readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
    String rule(String addr) => '-A OUTPUT -d $addr/32 ! -o wgc+ -j DROP';
    List<String> iplog() => File('$state/iplog').existsSync() ? File('$state/iplog').readAsLinesSync() : [];

    /// Quad9 on the router and on wgc1, Cloudflare on wgc5, DNS-over-TLS on, the clock set: the sharing is Quad9's.
    void sharedQuad9() {
      nv('dnspriv_enable', '1');
      nv('dnspriv_rulelist', '<9.9.9.9>853>dns.quad9.net><149.112.112.112>853>dns.quad9.net>');
      nv('wan0_dns', '1.1.1.2 1.0.0.2');
      nv('wgc1_ep_addr', '203.0.113.1');
      nv('wgc1_dns', '9.9.9.9, 149.112.112.112');
      nv('wgc5_ep_addr', '203.0.113.5');
      nv('wgc5_dns', '1.1.1.2, 1.0.0.2');
      nv('ntp_ready', '1');
    }

    test('every address both the router and a slot list is refused outside a tunnel, once, in the raw table', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      final out = await run(['hold']);
      expect(raw(), unorderedEquals([rule('9.9.9.9'), rule('149.112.112.112')]), reason: out);
      expect(out, contains('holding 2 address(es)'));
      expect(syslog().where((l) => l.contains('hold: the router')), hasLength(2), reason: 'each is said in the router log');
      await run(['hold']);
      expect(iplog().where((l) => l.startsWith('I ')), hasLength(2), reason: 'a second run adds nothing');
    });

    test('with DNS-over-TLS on only the DoT list counts: a slot that lists the DNS Server setting alone is not held', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      nv('wgc1_dns', '1.1.1.2, 1.0.0.2'); // the DNS Server setting's addresses, which nothing uses while DoT is on
      await run(['hold']);
      expect(raw(), isEmpty);
    });

    test('with DNS-over-TLS off only the DNS Server setting counts', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      nv('dnspriv_enable', '0');
      nv('wan0_dns', '9.9.9.9 149.112.112.112');
      await run(['hold']);
      expect(raw(), unorderedEquals([rule('9.9.9.9'), rule('149.112.112.112')]));
      nv('wan0_dns', '8.8.8.8 8.8.4.4'); // no slot lists these, and the DoT list's Quad9 is unused now
      await run(['hold']);
      expect(raw(), isEmpty, reason: 'and the hold on the old setting is let go');
    });

    test('never from boot: nothing is held until the clock is set', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      nv('ntp_ready', '0');
      await run(['hold']);
      expect(raw(), isEmpty);
      await run();
      expect(raw(), isEmpty, reason: "the guard's ordinary run holds nothing either");
      nv('ntp_ready', '1');
      await run(['hold']);
      expect(raw(), hasLength(2));
    });

    test('a slot with no server to connect to is not one that shares', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      File('$state/nv/wgc1_ep_addr').deleteSync();
      await run(['hold']);
      expect(raw(), isEmpty);
    });

    test('a slot that is stopped or disabled still counts: that is when its route is gone', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      nv('wgc1_enable', '0');
      await run(['hold']);
      expect(raw(), hasLength(2));
    });

    test('when no slot lists the address any more the hold is let go, and the router log says so', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      await run(['hold']);
      nv('wgc1_dns', '8.8.8.8, 8.8.4.4');
      final out = await run(['hold']);
      expect(raw(), isEmpty);
      expect(out, contains('holding 0 address(es)'));
      expect(syslog().where((l) => l.contains('is let go')), hasLength(2));
    });

    test('the ordinary run and `table N` both place it; the hold mode touches no ip rule', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      await run();
      expect(raw(), hasLength(2), reason: 'no argument');
      File('$state/raw').writeAsStringSync('');
      await run(['table', '1']);
      expect(raw(), hasLength(2), reason: '`table N`, as wgclient-start runs it');
      File('$state/raw').writeAsStringSync('');
      if (File('$state/log').existsSync()) File('$state/log').deleteSync();
      await run(['hold']);
      expect(log(), isEmpty, reason: '`hold` adds and takes out no rule of the ip rule kind');
    });

    test('the watch holds it as soon as the clock is set, which is after the watch began', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      // The fake clock is set in the middle of the watch: the third time the script asks for ntp_ready.
      File('${dir.path}/bin/nvram').writeAsStringSync(r'''#!/bin/sh
if [ "$1 $2" = "get ntp_ready" ]; then
  N=$(cat "$STATE/ntp_calls" 2>/dev/null || echo 0); echo $((N + 1)) > "$STATE/ntp_calls"
  [ "$N" -ge 2 ] && echo 1 || echo 0
  exit 0
fi
[ "$1" = get ] && cat "$STATE/nv/$2" 2>/dev/null
exit 0
''');
      await run(['watch'], {'GUARD_WATCH_STEP': '0', 'GUARD_WATCH_MAX': '6', 'GUARD_WATCH_AFTER_SYNC': '2'});
      expect(raw(), hasLength(2));
    });

    test('an address the router refused is reported, as an error for the next watchdog run', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      File('$state/refuse').writeAsStringSync('');
      final out = await run(['hold']);
      expect(raw(), isEmpty);
      final errors = Directory(state).listSync().where((f) => f.path.contains('guard.err')).toList();
      expect(errors, hasLength(1), reason: 'the error is kept for the next watchdog run, which reports it');
      expect(File(errors.single.path).readAsStringSync(), contains('could not hold 9.9.9.9'), reason: out);
    });

    test('GUARD_HOLD_ADDRS names the addresses outright, whatever the router uses, for check-claims.sh', () async {
      if (shell == null) return markTestSkipped(_noShell);
      await run(['hold'], {'GUARD_HOLD_ADDRS': '203.0.113.9'});
      expect(raw(), [rule('203.0.113.9')]);
      await run(['hold']);
      expect(raw(), isEmpty, reason: 'and the next ordinary run lets it go');
    });

    test('`clear` takes the hold out with the rest, for UNINSTALL', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      await run(['hold']);
      await run(['clear']);
      expect(raw(), isEmpty);
    });

    test('only the raw table is touched', () async {
      if (shell == null) return markTestSkipped(_noShell);
      sharedQuad9();
      await run(['hold']);
      expect(iplog().where((l) => l.startsWith('other table')), isEmpty);
    });
  });

  // ID-653: a rebuild by a watchdog with no DoH server of its own looks PIA's names up through the router's resolver,
  // which the hold refuses while the slot is down. The watchdog asks the guard to `lift` the hold on what its slot lists,
  // and to `restore` it when it has finished; the lift expires by itself after ten minutes.
  group("a rebuild's lift of the hold (ID-653)", () {
    void nv(String key, String value) => File('$state/nv/$key').writeAsStringSync(value);
    List<String> raw() =>
        File('$state/raw').existsSync() ? File('$state/raw').readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
    String rule(String addr) => '-A OUTPUT -d $addr/32 ! -o wgc+ -j DROP';
    Map<String, String> lifting() => {'GUARD_LIFT_FILE': '$state/lift'};
    int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    /// Quad9 on wgc1 and Cloudflare on wgc5, both also the router's DoT list, the clock set.
    void twoSlotsShare() {
      nv('dnspriv_enable', '1');
      nv('dnspriv_rulelist', '<9.9.9.9>853>a><149.112.112.112>853>a><1.1.1.2>853>b><1.0.0.2>853>b>');
      nv('wgc1_ep_addr', '203.0.113.1');
      nv('wgc1_dns', '9.9.9.9, 149.112.112.112');
      nv('wgc5_ep_addr', '203.0.113.5');
      nv('wgc5_dns', '1.1.1.2, 1.0.0.2');
      nv('ntp_ready', '1');
    }

    test("`lift N` lets go of the addresses slot N lists, and only those, and says so in the router log", () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      await run(['hold'], lifting());
      expect(raw(), hasLength(4));
      await run(['lift', '1'], lifting());
      expect(raw(), unorderedEquals([rule('1.1.1.2'), rule('1.0.0.2')]), reason: "wgc5's stay: only wgc1 is being rebuilt");
      expect(syslog().where((l) => l.contains("hold: lifted for wgc1's rebuild")), hasLength(1));
    });

    test('while it is lifted the ordinary run, `table N` and the watch do not put the hold back', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      await run(['lift', '1'], lifting());
      await run(['hold'], lifting());
      await run([], lifting());
      await run(['table', '1'], lifting());
      expect(raw(), unorderedEquals([rule('1.1.1.2'), rule('1.0.0.2')]), reason: 'a tunnel starting in the middle of the rebuild does not re-arm it');
    });

    test('`restore` puts the hold back and removes the lift, even if the rebuild failed', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      await run(['lift', '1'], lifting());
      await run(['restore'], lifting());
      expect(raw(), hasLength(4));
      expect(File('$state/lift').existsSync(), isFalse);
      expect(syslog().where((l) => l.contains('hold: back after the rebuild')), hasLength(1));
    });

    test('a lift older than ten minutes is ignored: a watchdog that died leaves the hold back on by itself', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      File('$state/lift').writeAsStringSync('${now() - 700} 1\n');
      await run(['hold'], lifting());
      expect(raw(), hasLength(4));
      File('$state/lift').writeAsStringSync('${now() - 30} 1\n');
      await run(['hold'], lifting());
      expect(raw(), hasLength(2), reason: 'a lift 30 seconds old holds');
    });

    test('a lift that is not "<epoch> <slot>" is ignored', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      for (final junk in ['', 'x y', '123', '${now()} ', '${now()} one']) {
        File('$state/lift').writeAsStringSync('$junk\n');
        await run(['hold'], lifting());
        expect(raw(), hasLength(4), reason: 'marker "$junk"');
      }
    });

    test('`lift` with no slot changes nothing, and `clear` takes the lift away with the rules', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoSlotsShare();
      await run(['hold'], lifting());
      await run(['lift'], lifting());
      expect(raw(), hasLength(4));
      await run(['lift', '1'], lifting());
      await run(['clear'], lifting());
      expect(raw(), isEmpty);
      expect(File('$state/lift').existsSync(), isFalse);
    });
  });

  // ID-652: with the hold on, a second running slot that lists the address must carry the router's lookups when the first
  // stops; Merlin gives only the first slot to start a route to it. One `ip rule` for each running slot that lists a held
  // address, at 1050 minus the slot, so the highest-numbered running slot wins, as on stock. Measured on the router with
  // throwaway slots (plan_dns.md); these check which rules the script holds, for which slots, and when.
  group('the second slot takes over the router\'s lookups (ID-652)', () {
    void nv(String key, String value) => File('$state/nv/$key').writeAsStringSync(value);
    void running(Iterable<int> slots) {
      for (var n = 1; n <= 5; n++) {
        final f = File('$state/link_wgc$n');
        if (slots.contains(n)) {
          f.writeAsStringSync('');
        } else if (f.existsSync()) {
          f.deleteSync();
        }
      }
    }

    List<String> takeovers() => rules().where((r) => RegExp(r'^104[5-9]:').hasMatch(r)).toList();
    String rule(int slot, String addr) => '${1050 - slot}:\tfrom all to $addr iif lo lookup wgc$slot';

    /// wgc1 and wgc3 both list Quad9, which is also the router's DoT list; wgc5 lists Cloudflare, which is not.
    void twoShare() {
      nv('dnspriv_enable', '1');
      nv('dnspriv_rulelist', '<9.9.9.9>853>a><149.112.112.112>853>a>');
      nv('wgc1_ep_addr', '203.0.113.1');
      nv('wgc1_dns', '9.9.9.9, 149.112.112.112');
      nv('wgc3_ep_addr', '203.0.113.3');
      nv('wgc3_dns', '9.9.9.9, 149.112.112.112');
      nv('wgc5_ep_addr', '203.0.113.5');
      nv('wgc5_dns', '1.1.1.2, 1.0.0.2');
      nv('ntp_ready', '1');
    }

    test('each running slot that lists a held address gets a rule, at 1050 minus its number, to its own table', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3, 5]);
      await run(['hold']);
      expect(
          takeovers(),
          unorderedEquals([
            rule(1, '9.9.9.9'),
            rule(1, '149.112.112.112'),
            rule(3, '9.9.9.9'),
            rule(3, '149.112.112.112'),
          ]),
          reason: 'wgc5 lists nothing the router uses');
    });

    test('the highest-numbered running slot is the first rule the kernel reaches, as on stock', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      await run(['hold']);
      final priorities = {for (final r in takeovers()) int.parse(r.split(':').first): r};
      expect(priorities[1047], contains('wgc3'));
      expect(priorities[1049], contains('wgc1'));
      expect(1047, lessThan(1049), reason: 'the lower number is looked at first');
    });

    test('a slot that stops loses its rule at the next run, and the other keeps its', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      await run(['hold']);
      running([1]);
      await run(['hold']);
      expect(takeovers(), unorderedEquals([rule(1, '9.9.9.9'), rule(1, '149.112.112.112')]));
      running([]);
      await run(['hold']);
      expect(takeovers(), isEmpty, reason: 'none running, none left: the lookup falls to the main table, where the hold refuses it');
    });

    test('a run twice adds nothing twice', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      await run(['hold']);
      File('$state/log').existsSync() ? File('$state/log').deleteSync() : null;
      await run(['hold']);
      expect(log().where((l) => l.startsWith('add 104')), isEmpty);
    });

    test('never before the clock is set, and let go with the hold', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      nv('ntp_ready', '0');
      await run(['hold']);
      expect(takeovers(), isEmpty);
      nv('ntp_ready', '1');
      await run(['hold']);
      expect(takeovers(), hasLength(4));
      nv('wgc1_dns', '8.8.8.8');
      nv('wgc3_dns', '8.8.8.8');
      await run(['hold']);
      expect(takeovers(), isEmpty, reason: 'no slot lists the address: the hold and the rules go together');
    });

    test('while the slot is being rebuilt its rules are lifted with the hold', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      await run(['hold']);
      await run(['lift', '1'], {'GUARD_LIFT_FILE': '$state/lift'});
      expect(takeovers(), isEmpty, reason: 'wgc1 and wgc3 list the same addresses, and wgc1 is the one being rebuilt');
    });

    test("another slot's rules are left alone", () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      File('$state/rules').writeAsStringSync('${File('$state/rules').readAsStringSync()}1000:\tfrom all to 9.9.9.9 iif lo lookup wgc1\n');
      await run(['hold']);
      expect(rules(), contains('1000:\tfrom all to 9.9.9.9 iif lo lookup wgc1'), reason: "the watchdog's own probe is not the guard's");
    });

    test('`clear` takes the rules out with the hold, and nothing else', () async {
      if (shell == null) return markTestSkipped(_noShell);
      twoShare();
      running([1, 3]);
      await run(['hold']);
      expect(takeovers(), isNotEmpty);
      await run(['clear']);
      expect(takeovers(), isEmpty);
      expect(rules(), contains('0:\tfrom all lookup local'));
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
