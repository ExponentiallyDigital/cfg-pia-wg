// test/unit/runner_tunnel_speed_test.dart - scripts/runner-tunnel-speed.sh against a fake router (ID-393).
//
// The script times one tunnel in and out of Broadcom's accelerator table, switching it by stopping
// and starting it and a donor tunnel in turn. The fake table behaves as measured on 2026-10-14:
// 8 places, first come first served, a place given up when its tunnel stops. The stand-in curl
// downloads at $STATE/speed_in when the source address is in the table and $STATE/speed_out when it
// isn't, so the verdict can be checked both ways; everything that must be true afterwards - both
// tunnels up, the table as found, the watchdogs back - is checked too.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _nvram = r'''#!/bin/sh
case "$1" in
  get) cat "$STATE/nv/$2" 2>/dev/null; exit 0 ;;
  set) k="${2%%=*}"; v="${2#*=}"; printf '%s' "$v" > "$STATE/nv/$k"; exit 0 ;;
esac
''';

const _service = r'''#!/bin/sh
u="$(cat "$STATE/nv/vpnc_unit")"; s="$(cat "$STATE/unit_$u")"; a="$(cat "$STATE/addr_wgc$s")"
echo "$1 wgc$s" >> "$STATE/services"
case "$1" in
  stop_vpnc)
    grep -vx "wgc$s" "$STATE/up" > "$STATE/x"; mv "$STATE/x" "$STATE/up"
    grep -vx "$a" "$STATE/table" > "$STATE/x"; mv "$STATE/x" "$STATE/table" ;;
  restart_vpnc)
    grep -qx "wgc$s" "$STATE/up" || echo "wgc$s" >> "$STATE/up"
    date +%s > "$STATE/hs_wgc$s"
    if ! grep -qx "$a" "$STATE/table"; then
      if [ "$(grep -c . "$STATE/table")" -lt 8 ]; then echo "$a" >> "$STATE/table"; else echo "pktrunner ret=-3" >> "$STATE/errors"; fi
    fi ;;
esac
''';

// Rules are lines "to <ip> table <n>" in $STATE/rules. A route to an address follows its rule into
// table n, which is wgc(10 - n), as stock numbers them - unless $STATE/route_wan, where the rule has
// no effect and the route stays on the WAN.
const _ip = r'''#!/bin/sh
case "$*" in
  "-o link show up") while read -r i; do [ -n "$i" ] && echo "9: $i: <UP,LOWER_UP> mtu 1420"; done < "$STATE/up" ;;
  "-o -4 addr show wgc"*) n="${5#wgc}"; grep -qx "wgc$n" "$STATE/up" && echo "9: wgc$n    inet $(cat "$STATE/addr_wgc$n")/32 scope global wgc$n" ;;
  "rule add to "*) echo "to $4 table $8" >> "$STATE/rules" ;;
  "rule del to "*) grep -qx "to $4 table $8" "$STATE/rules" 2>/dev/null || exit 2
    grep -vx "to $4 table $8" "$STATE/rules" > "$STATE/r.new"; mv "$STATE/r.new" "$STATE/rules" ;;
  "route get "*)
    t="$(sed -n "s/^to $3 table \([0-9]*\)$/\1/p" "$STATE/rules" 2>/dev/null | head -1)"
    if [ -n "$t" ] && [ ! -f "$STATE/route_wan" ]; then echo "$3 dev wgc$((10 - t))  src $(cat "$STATE/addr_wgc$((10 - t))") "
    else echo "$3 via 198.51.100.1 dev eth0  src 198.51.100.7 "; fi ;;
esac
exit 0
''';

const _nslookup = r'''#!/bin/sh
printf 'Server:    127.0.0.1\nAddress 1: 127.0.0.1 localhost\n\nName:      %s\nAddress 1: 192.0.2.80\n' "$1"
''';

const _bs = r'''#!/bin/sh
[ "$1 $2" = "/b/e system" ] || exit 1
i=0; while read -r a; do printf '\tipv4_host_address_table[%s] : %s \r\n' "$i" "$a"; i=$((i + 1)); done < "$STATE/table"
''';

// Pinned to an address with --resolve host:443:<ip>. The download goes through the tunnel a rule for
// that address names, whose speed depends on whether its address is in the table, and the 25 MB is
// added to that tunnel's received bytes - unless $STATE/no_rx, where the tunnel's counter doesn't
// move, as if the download had gone some other way.
const _curl = r'''#!/bin/sh
ip=""; while [ $# -gt 0 ]; do [ "$1" = --resolve ] && ip="${2##*:}"; shift; done
echo "$ip" >> "$STATE/curl_to"
t="$(sed -n "s/^to $ip table \([0-9]*\)$/\1/p" "$STATE/rules" 2>/dev/null | head -1)"
i="wgc$((10 - ${t:-0}))"
a="$(cat "$STATE/addr_$i" 2>/dev/null)"
if grep -qx "$a" "$STATE/table"; then sp="$(cat "$STATE/speed_in")"; else sp="$(cat "$STATE/speed_out")"; fi
if [ -n "$t" ] && [ ! -f "$STATE/no_rx" ]; then
  f="$STATE/sys/class/net/$i/statistics/rx_bytes"; echo $(( $(cat "$f") + 25000000 )) > "$f"
fi
printf '200 %s.000 25000000' "$sp"
''';

const _wg = r'''#!/bin/sh
[ -f "$STATE/hs_$2" ] && printf 'KEY=\t%s\n' "$(cat "$STATE/hs_$2")"
exit 0
''';
const _cru = r'''#!/bin/sh
case "$1" in
  l) cat "$STATE/cru" 2>/dev/null ;;
  d) grep -v "#$2#" "$STATE/cru" > "$STATE/cru.new"; mv "$STATE/cru.new" "$STATE/cru" ;;
  a) echo "$3 #$2#" >> "$STATE/cru" ;;
esac
exit 0
''';
const _logger = '#!/bin/sh\necho "\$*" >> "\$STATE/logger"\n';
const _sleep = '#!/bin/sh\nexit 0\n';

const _watchdogCru = '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc3.sh #watchdog_wgc3#';
// Invented addresses; the table as measured: wgc4 and wgc2 left out.
const _fixed = ['127.0.1.1', '192.168.1.1', '192.168.101.1', '10.6.0.1', '198.51.100.7'];
String _addr(int n) => '10.0.0.$n';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('runner_tunnel_speed_');
    state = '${dir.path}/state';
    Directory('$state/nv').createSync(recursive: true);
    Directory('$state/tmp').createSync();
    Directory('${dir.path}/bin').createSync();
    final stubs = {
      'nvram': _nvram, 'service': _service, 'ip': _ip, 'bs': _bs, 'curl': _curl, 'nslookup': _nslookup,
      'wg': _wg, 'cru': _cru, 'logger': _logger, 'sleep': _sleep,
    };
    for (final e in stubs.entries) {
      File('${dir.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    const order = [1, 5, 3, 2, 4];
    File('$state/nv/vpnc_clientlist')
        .writeAsStringSync(order.map((s) => '<pia-x>WireGuard>$s>>password>1>${s + 5}>>>0>0>cfg-pia-wg').join());
    for (var i = 0; i < order.length; i++) {
      File('$state/unit_$i').writeAsStringSync('${order[i]}');
    }
    File('$state/nv/vpnc_default_wan').writeAsStringSync('0');
    File('$state/nv/vpnc_unit').writeAsStringSync('2');
    final then = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    for (final s in [1, 2, 3, 4, 5]) {
      File('$state/addr_wgc$s').writeAsStringSync(_addr(s));
      File('$state/hs_wgc$s').writeAsStringSync('$then');
      Directory('$state/sys/class/net/wgc$s/statistics').createSync(recursive: true);
      File('$state/sys/class/net/wgc$s/statistics/rx_bytes').writeAsStringSync('1000');
    }
    File('$state/up').writeAsStringSync('wgc1\nwgc5\nwgc3\nwgc2\nwgc4\n');
    File('$state/table').writeAsStringSync('${[..._fixed, _addr(5), _addr(1), _addr(3)].join('\n')}\n');
    File('$state/speed_in').writeAsStringSync('2048000');
    File('$state/speed_out').writeAsStringSync('2048000');
    File('$state/cru').writeAsStringSync('$_watchdogCru\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> run([List<String> args = const []]) async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed -e "s#/tmp/#$STATE/tmp/#g" -e "s#BS=/bin/bs#BS=$P/bs#" -e "s#/sys/#$STATE/sys/#g" "$1" > rts.sh && shift && exec sh rts.sh "$@"';
    final r = await runSh(shell!, ['-c', cmd, 'sh', '${Directory.current.path}/scripts/runner-tunnel-speed.sh', ...args],
        environment: env);
    return '${r.stdout}${r.stderr}';
  }

  List<String> lines(String name) {
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
  }

  void expectAsFound(String out) {
    expect(lines('up'), containsAll(['wgc3', 'wgc4']), reason: out);
    expect(lines('table'), contains(_addr(3)), reason: 'wgc3 back in the table');
    expect(lines('table'), isNot(contains(_addr(4))), reason: 'wgc4 back out of it');
    expect(lines('cru'), [_watchdogCru]);
    expect(File('$state/nv/vpnc_unit').readAsStringSync(), '2');
    expect(Directory('$state/tmp/runner-tunnel-speed.lock').existsSync(), isFalse);
    expect(lines('rules'), isEmpty, reason: 'every routing rule it added, taken out');
  }

  test('times wgc4 three times in the table and three out, alternating, and finds no difference', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final out = await run();
    expect(RegExp(r'round \d: wgc4 (in|out) the table').allMatches(out).map((m) => m.group(1)).toList(),
        ['in', 'out', 'out', 'in', 'in', 'out'], reason: out);
    expect(out, contains('wgc4 in the table:     average 2000 KB/s, runs: 2000 2000 2000'));
    expect(out, contains('wgc4 out of the table: average 2000 KB/s, runs: 2000 2000 2000'));
    expect(out, contains('VERDICT: no difference beyond noise'));
    expect(lines('curl_to').toSet(), {'192.0.2.80'}, reason: 'every download to the one address looked up');
    expectAsFound(out);
  });

  test('a tunnel half as fast out of the table is SLOWER, by 50%', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/speed_out').writeAsStringSync('1024000');
    final out = await run();
    expect(out, contains('out of the table vs in it: -50%'));
    expect(out, contains('VERDICT: SLOWER out of the table, by 50%'));
    expectAsFound(out);
  });

  // The rule that sends the download through the tunnel didn't take, and the route stayed on the WAN.
  test('a download whose route is not through the tunnel is not counted, and its rule is taken out', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/route_wan').writeAsStringSync('');
    final out = await run(['4', '3', '1']);
    expect(out, contains('not counted: the route to 192.0.2.80 is not through wgc4'));
    expect(out, contains('VERDICT: none'));
    expect(lines('curl_to'), isEmpty, reason: 'nothing downloaded');
    expectAsFound(out);
  });

  test('a download the tunnel did not carry is not counted', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/no_rx').writeAsStringSync('');
    final out = await run(['4', '3', '1']);
    expect(out, contains("not counted: wgc4 received only 0 bytes during a 25000000-byte download, so it didn't go through wgc4"));
    expect(out, contains('VERDICT: none'));
    expectAsFound(out);
  });

  test('an even number of rounds still ends with the table as found', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final out = await run(['4', '3', '2']);
    expect(out, contains('putting wgc4 back out of the table, as it was'));
    expectAsFound(out);
  });

  test('refuses, touching nothing, unless exactly one of the two is in the table', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final out = await run(['2', '4']);
    expect(out, contains('REFUSED: exactly one of wgc2 and wgc4 must be in the accelerator\'s table now'));
    expect(lines('services'), isEmpty);
    expect(lines('cru'), [_watchdogCru]);
  });

  test('refuses the default connection, and nonsense', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/nv/vpnc_default_wan').writeAsStringSync('8'); // wgc3's index 6
    expect(await run(), contains('REFUSED: wgc3 is the default connection'));
    expect(lines('services'), isEmpty);
    expect(await run(['4', '4']), contains('must be different'));
    expect(await run(['4', '3', '0']), contains('usage'));
  });
}
