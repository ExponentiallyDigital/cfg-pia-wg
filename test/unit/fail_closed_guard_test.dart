// Runs the real guard script under a POSIX shell, with stand-ins for `nvram`, `ip` and `logger`.
//
// The first behavioural test of router-side shell in this repo (BACKLOG ID-205 is the wider
// harness). String checks alone would have passed a script that re-added its rules on every run,
// which is exactly the kind of fault only running it finds. Skipped where no `sh` is on the PATH.
import 'dart:io';

import 'package:cfg_pia_wg/fail_closed_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// The two tunnels the fixtures use: wgc1 is table 9, wgc5 is table 5. Addresses are documentation
// ranges, never real ones.
const String kClientlist = 'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
    '<pia-aus_melbourne>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg'
    '<Work>OpenVPN>1>>password>1>3>>>0>0>';

const String kNvramStub = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/nv_$2" 2>/dev/null
exit 0
''';

const String kLoggerStub = r'''#!/bin/sh
shift 2
echo "$*" >> "$STATE/log"
''';

// Keeps rules as `<prio>:<TAB>from <ip> ...` lines and prints them in priority order, as `ip rule
// show` does. Also the three route forms the guard uses since ID-347: `ip route show table T`
// answers from $STATE/table_T, `ip route replace ... table T` appends there, and `ip -o link show
// up` lists $STATE/up. Only the forms the guard uses are understood.
const String kIpStub = r'''#!/bin/sh
R="$STATE/rules"
if [ "$1" = "-o" ] && [ "$2" = "link" ]; then
  n=2; while read -r i; do [ -n "$i" ] && { n=$((n + 1)); echo "$n: $i: <POINTOPOINT,UP,LOWER_UP> mtu 1420"; }; done < "$STATE/up" 2>/dev/null
  exit 0
fi
if [ "$1" = route ]; then
  case "$2" in
    show) [ "$3" = table ] && cat "$STATE/table_$4" 2>/dev/null; exit 0 ;;
    replace)
      dst="$3"; dev=""; t=""
      shift 3
      while [ $# -gt 0 ]; do case "$1" in dev) dev="$2"; shift ;; table) t="$2"; shift ;; esac; shift; done
      grep -qxF "$dst dev $dev scope link" "$STATE/table_$t" 2>/dev/null || echo "$dst dev $dev scope link" >> "$STATE/table_$t"
      exit 0 ;;
    flush) [ "$3" = table ] && rm -f "$STATE/table_$4"; exit 0 ;;
  esac
  exit 1
fi
[ "$1" = rule ] || exit 1
op="$2"
shift 2
case "$op" in
  show) [ -f "$R" ] && sort -s -t: -k1,1n "$R"; exit 0 ;;
esac
from=""; to=""; tbl=""; prio=""; bh=0; sup=""
while [ $# -gt 0 ]; do
  case "$1" in
    from) from="$2"; shift ;;
    to) to="$2"; shift ;;
    lookup) tbl="$2"; shift ;;
    priority) prio="$2"; shift ;;
    suppress_prefixlength) sup="$2"; shift ;;
    blackhole) bh=1 ;;
  esac
  shift
done
case "$op" in
  add)
    [ -f "$STATE/fail_add" ] && exit 2
    [ -f "$STATE/fail_add_$prio" ] && exit 2
    if [ "$bh" = 1 ]; then
      printf '%s:\tfrom %s%s blackhole\n' "$prio" "$from" "${to:+ to $to}" >> "$R"
    else
      printf '%s:\tfrom %s%s lookup %s%s\n' "$prio" "$from" "${to:+ to $to}" "$tbl" "${sup:+ suppress_prefixlength $sup}" >> "$R"
    fi ;;
  del)
    [ -f "$R" ] || exit 2
    awk -v p="$prio:" -v f="$from" -v to="$to" '!d && $1 == p && $3 == f && (to == "" || ($4 == "to" && $5 == to)) {d = 1; next} {print} END {exit !d}' "$R" > "$R.new"
    rc=$?
    mv "$R.new" "$R"
    exit $rc ;;
esac
''';

void main() {
  final shell = _findShell();
  late Directory dir;
  late Directory state;
  late File script;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('guard_test_');
    state = Directory('${dir.path}/state')..createSync();
    final bin = Directory('${dir.path}/bin')..createSync();
    for (final e in {'nvram': kNvramStub, 'ip': kIpStub, 'logger': kLoggerStub}.entries) {
      File('${bin.path}/${e.key}').writeAsStringSync(e.value);
    }
    script = File('${dir.path}/guard.sh')..writeAsStringSync(kGuardScript);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...bin.listSync().map((f) => f.path)]);
    _set(state, 'vpnc_clientlist', kClientlist);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // The stand-ins first, then the shell's own Unix tools, then everything else. Without the middle
  // step, a test run from PowerShell or cmd found C:\Windows\System32\sort.exe before Git's `sort`:
  // it rejects `-u` and `-k`, prints nothing, and every rule the script had added read back as
  // missing (2026-09-24). The first PATH entry is the stand-ins' directory, already converted to
  // the shell's own form; `/usr/bin` is Git's tools on Windows and where they are anyway on Linux.
  const unixToolsFirst = r'PATH="${PATH%%:*}:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"';

  Future<ProcessResult> run([List<String> args = const []]) {
    final sep = Platform.isWindows ? ';' : ':';
    return Process.run(shell!, ['-c', unixToolsFirst, 'sh', script.path, ...args], environment: {
      'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state.path,
      'GUARD_LOCK': '${state.path}/lock',
    });
  }

  List<String> rules() {
    final f = File('${state.path}/rules');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (l.trim().isNotEmpty) l.replaceAll('\t', ' ')] : [];
  }

  List<String> log() {
    final f = File('${state.path}/log');
    return f.existsSync() ? f.readAsLinesSync() : [];
  }

  // wgc5's table as the firmware builds it, from a stock router 2026-09-30 with documentation
  // addresses: the tunnel's /1 routes and its DNS, and - via the WAN - the router's own DNS server,
  // the tunnel's PIA server, the ISP subnet and the default.
  void table5({String endpoint = '203.0.113.9'}) => File('${state.path}/table_5').writeAsStringSync('''
0.0.0.0/1 dev wgc5  scope link
default via 198.51.100.1 dev eth0
1.1.1.2 via 198.51.100.1 dev eth0  metric 1
$endpoint via 198.51.100.1 dev eth0
127.0.0.0/8 dev lo  scope link
128.0.0.0/1 dev wgc5  scope link
9.9.9.9 dev wgc5  scope link
198.51.100.0/24 dev eth0  proto kernel  scope link  src 198.51.100.36
192.168.1.0/24 dev br0  proto kernel  scope link  src 192.168.1.1
10.6.0.2 dev wgs1  scope link
''');
  void up(String iface) => File('${state.path}/up').writeAsStringSync('$iface\n');

  group('guard.sh: what the tunnel\'s table sends out the WAN (ID-347)', () {
    test('each such address is held to the tunnel, with a blackhole behind it', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      up('wgc5');
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 5 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
        for (final x in ['1.1.1.2', '203.0.113.9', '198.51.100.0/24']) ...[
          '88: from 192.0.2.50 to $x lookup 205',
          '89: from 192.0.2.50 to $x blackhole',
        ],
      ]));
      expect(File('${state.path}/table_205').readAsLinesSync(),
          unorderedEquals(['0.0.0.0/1 dev wgc5 scope link', '128.0.0.0/1 dev wgc5 scope link']));
    });

    test('a second run changes nothing', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      up('wgc5');
      await run();
      final before = rules();
      await run();
      expect(rules(), before);
    });

    test('with the tunnel down, its tunnel-only table stays empty, so the blackhole decides', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      await run();
      expect(rules(), contains('89: from 192.0.2.50 to 1.1.1.2 blackhole'));
      expect(File('${state.path}/table_205').existsSync(), isFalse);
    });

    test('a new PIA server replaces the old one\'s rules', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      up('wgc5');
      await run();
      table5(endpoint: '203.0.113.77');
      await run();
      expect(rules().where((r) => r.contains('203.0.113.9')), isEmpty);
      expect(rules(), contains('89: from 192.0.2.50 to 203.0.113.77 blackhole'));
    });

    test('a blackhole that cannot be added is counted as not guarded, and reported', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      File('${state.path}/fail_add_89').writeAsStringSync('1');
      final r = await run();
      expect('${r.stdout}', contains('guarded 0 of 1'));
      expect(r.exitCode, isNot(0));
    });

    test('clear removes them, and empties the tunnel-only table', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      table5();
      up('wgc5');
      await run();
      await run(['clear']);
      expect(rules(), isEmpty);
      expect(File('${state.path}/table_205').existsSync(), isFalse);
    });
  });

  // ID-320: a 90 rule without suppress_prefixlength 0 counted as guarded, though it hands the device
  // the WAN default the firmware copies into the tunnel's table.
  test('guard.sh replaces a 90 rule that lacks suppress_prefixlength 0', () async {
    _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
    File('${state.path}/rules').writeAsStringSync('90:\tfrom 192.0.2.50 lookup 9\n91:\tfrom 192.0.2.50 blackhole\n');
    final r = await run();
    expect('${r.stdout}', contains('guarded 1 of 1'));
    expect(rules(), unorderedEquals(['90: from 192.0.2.50 lookup 9 suppress_prefixlength 0', '91: from 192.0.2.50 blackhole']));
  });

  group('guard.sh', () {
    test('a device pinned to a WireGuard tunnel gets both rules', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1'));
      expect(rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 9 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
      expect(log(), ['Fail-closed guard on for 192.0.2.50 (wgc1)']);
    });

    // ID-262: ROUTER LOG gave the address alone, where DEVICE ASSIGNMENT shows a name.
    test('the log names the device, as DEVICE ASSIGNMENT does, before its address', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      _set(state, 'dhcp_staticlist', '<aa:bb:cc:00:00:50>192.0.2.50>>');
      _set(state, 'custom_clientlist', '<TABLET>AA:BB:CC:00:00:50>0>0>>>');
      await run();
      expect(log(), ['Fail-closed guard on for TABLET 192.0.2.50 (wgc1)']);
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      await run();
      expect(log().last, 'Fail-closed guard removed for TABLET 192.0.2.50');
    });

    test('a device with a reservation but no name of its own is named by its address', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      _set(state, 'dhcp_staticlist', '<AA:BB:CC:00:00:50>192.0.2.50>>');
      await run();
      expect(log(), ['Fail-closed guard on for 192.0.2.50 (wgc1)']);
    });

    test('a second run changes nothing and logs nothing', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await run();
      final before = rules();
      final r = await run();
      expect(r.exitCode, 0);
      expect(rules(), before, reason: 'the guard must not re-add rules it already holds');
      expect(log(), hasLength(1));
    });

    test('a device that stops being pinned loses its guard', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await run();
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      final r = await run();
      expect(r.exitCode, 0);
      expect(rules(), isEmpty);
      expect(log().last, 'Fail-closed guard removed for 192.0.2.50');
    });

    test('a device moved between tunnels is guarded for the new one only', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      await run();
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>5>');
      await run();
      expect(rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 5 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
    });

    test('no guard for a device on Internet, on the default, or on a VPN the app does not manage', () async {
      // Pinned to Internet (index 0), following the default (enabled 0), pinned to OpenVPN (3).
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.51>>0><0>192.0.2.52>>9><1>192.0.2.53>>3>');
      final r = await run();
      expect('${r.stdout}', contains('guarded 0'));
      expect(rules(), isEmpty);
    });

    test('duplicates are reduced to one of each', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      File('${state.path}/rules').writeAsStringSync(
        '90:\tfrom 192.0.2.50 lookup 9 suppress_prefixlength 0\n'
        '90:\tfrom 192.0.2.50 lookup 9 suppress_prefixlength 0\n'
        '91:\tfrom 192.0.2.50 blackhole\n'
        '91:\tfrom 192.0.2.50 blackhole\n',
      );
      await run();
      expect(rules(), unorderedEquals([
        '90: from 192.0.2.50 lookup 9 suppress_prefixlength 0',
        '91: from 192.0.2.50 blackhole',
      ]));
    });

    test("the firmware's own rules are never touched", () async {
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.50>>0>');
      const firmware = [
        '100: from 192.0.2.50 lookup 9',
        '1016: from all to 9.9.9.9 iif lo lookup 5',
        '10000: from all iif br0 lookup 5',
      ];
      File('${state.path}/rules').writeAsStringSync(firmware.map((l) => l.replaceFirst(': ', ':\t')).join('\n'));
      await run();
      await run(['clear']);
      expect(rules(), firmware);
    });

    test('clear removes every guard rule', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9><1>192.0.2.60>>5>');
      await run();
      expect(rules(), hasLength(4));
      final r = await run(['clear']);
      expect(r.exitCode, 0);
      expect(rules(), isEmpty);
    });

    test('a rule the router refuses is reported, not hidden', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.50>>9>');
      File('${state.path}/fail_add').writeAsStringSync('');
      final r = await run();
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}', contains('failed 2'));
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

  group('the script text', () {
    // 88 and 89 since ID-347. Measured free on a stock router 2026-09-30: the firmware uses 0, 90-91
    // (the guard's), 100, 1016-1029, 32766 and 32767.
    test('uses only priorities 88 to 91, which nothing else on the router uses', () {
      final prios = RegExp(r'priority (\d+)').allMatches(kGuardScript).map((m) => m.group(1)).toSet();
      expect(prios, {'88', '89', '90', '91'});
    });

    test('adds the drop rule before the tunnel rule, so a half-added guard fails closed', () {
      expect(kGuardScript.indexOf('blackhole priority 91 ||'),
          lessThan(kGuardScript.indexOf('suppress_prefixlength 0 priority 90; then')));
    });

    test('has LF line endings only', () => expect(kGuardScript.contains('\r'), isFalse));
  });
}

void _set(Directory state, String key, String value) => File('${state.path}/nv_$key').writeAsStringSync(value);

String? _findShell() {
  for (final candidate in ['sh', 'bash']) {
    try {
      if (Process.runSync(candidate, ['-c', 'exit 0']).exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}
