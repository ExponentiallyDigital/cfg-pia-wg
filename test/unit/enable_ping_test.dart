// test/unit/enable_ping_test.dart - ENABLE's stock ping, run for real against a fake router (ID-396).
//
// kStockTunnelPingBody sends the router's own ping through a tunnel by adding a rule for the one
// target into the tunnel's routing table, reading the route back, and taking the rule out again.
// What matters can't be seen from the command text: that a route the rule didn't change is NOROUTE
// and no ping is sent at all - the old check's fault was a ping that answered by the WAN - and that
// no rule is ever left behind. The stand-in `ip` keeps the rules in a file and follows them the way
// stock's numbering does (table 10 - slot is wgc<slot>); the stand-in `ping` records each call.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:cfg_pia_wg/router_slot_service.dart' show kStockTunnelPingBody;
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

// Rules are lines "<ip> <table>" in $STATE/rules; $STATE/rule_ignored makes the rule have no effect.
const _ip = r'''#!/bin/sh
case "$1 $2" in
  "rule add") echo "$4 $8" >> "$STATE/rules" ;;
  "rule del") grep -qx "$4 $8" "$STATE/rules" 2>/dev/null || exit 2
    grep -vx "$4 $8" "$STATE/rules" > "$STATE/r.new"; mv "$STATE/r.new" "$STATE/rules" ;;
  "route get")
    t="$(awk -v ip="$3" '$1 == ip {print $2; exit}' "$STATE/rules" 2>/dev/null)"
    if [ -n "$t" ] && [ ! -f "$STATE/rule_ignored" ]; then echo "$3 dev wgc$((10 - t))  src 10.0.0.4 "
    else echo "$3 via 198.51.100.1 dev eth0  src 198.51.100.7 "; fi ;;
esac
exit 0
''';

const _ping = r'''#!/bin/sh
echo "$*" >> "$STATE/pings"
[ -f "$STATE/ping_fails" ] && exit 1
exit 0
''';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('enable_ping_');
    state = '${dir.path}/state';
    Directory(state).createSync();
    Directory('${dir.path}/bin').createSync();
    File('${dir.path}/bin/ip').writeAsStringSync(_ip);
    File('${dir.path}/bin/ping').writeAsStringSync(_ping);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/ip', '${dir.path}/bin/ping']);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The command the app sends for [slot] and [target], as the app builds it.
  Future<String> run(int slot, String target) async {
    File('${dir.path}/c.sh').writeAsStringSync("N=$slot; IP='$target'\n$kStockTunnelPingBody\n");
    final sep = Platform.isWindows ? ';' : ':';
    final r = await runSh(shell!, ['-c', r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$1"', 'sh', '${dir.path}/c.sh'],
        environment: {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state});
    return '${r.stdout}'.trim();
  }

  List<String> lines(String name) {
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
  }

  test('pings through the tunnel\'s table, answers OK, and leaves no rule', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    expect(await run(4, '8.8.8.8'), 'OK');
    expect(lines('pings'), ['-c 1 -w 5 8.8.8.8'], reason: 'no -I: the source is the route\'s');
    expect(lines('rules'), isEmpty);
  });

  test('a target that does not answer through it is FAIL, and leaves no rule', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/ping_fails').writeAsStringSync('');
    expect(await run(4, '8.8.8.8'), 'FAIL');
    expect(lines('rules'), isEmpty);
  });

  // The fault this replaces: a ping that would answer by the WAN.
  test('a route the rule did not change is NOROUTE, and no ping is sent', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rule_ignored').writeAsStringSync('');
    expect(await run(4, '8.8.8.8'), 'NOROUTE');
    expect(lines('pings'), isEmpty);
    expect(lines('rules'), isEmpty);
  });

  test('a rule left by a run that was killed is cleared first, and not left twice', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rules').writeAsStringSync('8.8.8.8 6\n8.8.8.8 6\n');
    expect(await run(4, '8.8.8.8'), 'OK');
    expect(lines('rules'), isEmpty);
  });

  // Stock numbers a tunnel's table 10 minus its slot, as the watchdog's DNS probe uses it.
  test('each slot pings through its own table: wgc1 by table 9, wgc5 by table 5', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    // A ping that records the route it was sent by, while the rule is in place.
    File('${dir.path}/bin/ping').writeAsStringSync('#!/bin/sh\nip route get "\$5" >> "\$STATE/routes"\nexit 0\n');
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${dir.path}/bin/ping']);
    await run(1, '1.1.1.1');
    await run(5, '1.1.1.1');
    expect(lines('routes').map((l) => RegExp(r'dev (\w+)').firstMatch(l)!.group(1)).toList(), ['wgc1', 'wgc5']);
    expect(lines('rules'), isEmpty);
  });
}
