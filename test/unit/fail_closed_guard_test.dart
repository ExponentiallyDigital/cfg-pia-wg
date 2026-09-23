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
// show` does. Only the forms the guard uses are understood.
const String kIpStub = r'''#!/bin/sh
R="$STATE/rules"
[ "$1" = rule ] || exit 1
op="$2"
shift 2
case "$op" in
  show) [ -f "$R" ] && sort -s -t: -k1,1n "$R"; exit 0 ;;
esac
from=""; tbl=""; prio=""; bh=0; sup=""
while [ $# -gt 0 ]; do
  case "$1" in
    from) from="$2"; shift ;;
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
    if [ "$bh" = 1 ]; then
      printf '%s:\tfrom %s blackhole\n' "$prio" "$from" >> "$R"
    else
      printf '%s:\tfrom %s lookup %s%s\n' "$prio" "$from" "$tbl" "${sup:+ suppress_prefixlength $sup}" >> "$R"
    fi ;;
  del)
    [ -f "$R" ] || exit 2
    awk -v p="$prio:" -v f="$from" '!d && $1 == p && $3 == f {d = 1; next} {print} END {exit !d}' "$R" > "$R.new"
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

  Future<ProcessResult> run([List<String> args = const []]) {
    final sep = Platform.isWindows ? ';' : ':';
    return Process.run(shell!, [script.path, ...args], environment: {
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
    test('uses only priorities 90 and 91, which nothing else on the router uses', () {
      final prios = RegExp(r'priority (\d+)').allMatches(kGuardScript).map((m) => m.group(1)).toSet();
      expect(prios, {'90', '91'});
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
