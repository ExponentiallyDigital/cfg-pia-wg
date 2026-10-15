// test/unit/pktrunner_order_test.dart - scripts/pktrunner-order.sh against a fake stock router.
//
// The script stops two WireGuard tunnels and starts them in the other order, to see whether the
// kernel's pktrunner error follows the number of client tunnels up or particular slots. What matters
// most is what can't be checked on the router afterwards: that it refuses when it shouldn't touch
// anything, that it puts both tunnels, their watchdogs and vpnc_unit back however it ends, and that
// its verdict reads the counts the right way. The stand-in `service` starts and stops the tunnel
// vpnc_unit names, and logs the error when a start leaves [rule] client tunnels or more up.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _nvram = r'''#!/bin/sh
case "$1" in
  get) cat "$STATE/nv/$2" 2>/dev/null; exit 0 ;;
  set) k="${2%%=*}"; v="${2#*=}"; printf '%s' "$v" > "$STATE/nv/$k"; echo "$2" >> "$STATE/nvram_sets"; exit 0 ;;
esac
''';

// $STATE/rule holds the client-tunnel count from which a start logs the error; none, never.
// $STATE/ignore_wgcN makes a start of that tunnel do nothing, as a dropped call does.
const _service = r'''#!/bin/sh
u="$(cat "$STATE/nv/vpnc_unit")"; s="$(cat "$STATE/unit_$u")"
echo "$1 wgc$s" >> "$STATE/services"
case "$1" in
  stop_vpnc) grep -v "^wgc$s\$" "$STATE/up" > "$STATE/up.new"; mv "$STATE/up.new" "$STATE/up" ;;
  restart_vpnc)
    [ -f "$STATE/ignore_wgc$s" ] && exit 0
    grep -q "^wgc$s\$" "$STATE/up" || echo "wgc$s" >> "$STATE/up"
    date +%s > "$STATE/hs_wgc$s"
    n="$(grep -c . "$STATE/up")"
    if [ -f "$STATE/rule" ] && [ "$n" -ge "$(cat "$STATE/rule")" ]; then
      echo "Oct 14 17:19:36 kernel: [ERROR pktrunner] runnerUcast_inetaddr_event,220: Could not rdpa_system_ipv4_host_address_table_add ret=-3" >> "$STATE/tmp/syslog.log"
    fi ;;
esac
''';

const _ip = r'''#!/bin/sh
[ "$1 $2" = "-o link" ] && while read -r i; do [ -n "$i" ] && echo "9: $i: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420"; done < "$STATE/up"
exit 0
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

const _watchdogCru = '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc2.sh #watchdog_wgc2#';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pktrunner_order_');
    state = '${dir.path}/state';
    for (final d in ['nv', 'tmp']) {
      Directory('$state/$d').createSync(recursive: true);
    }
    Directory('${dir.path}/bin').createSync();
    final stubs = {'nvram': _nvram, 'service': _service, 'ip': _ip, 'wg': _wg, 'cru': _cru, 'logger': _logger, 'sleep': _sleep};
    for (final e in stubs.entries) {
      File('${dir.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    // Five client tunnels, rows 0 to 4 in the order wgc1, 5, 3, 2, 4; index 6 is 9, 5, 6, 7, 8.
    const rows = [(1, 9), (5, 5), (3, 6), (2, 7), (4, 8)];
    File('$state/nv/vpnc_clientlist').writeAsStringSync(
        rows.map((r) => 'pia-x>WireGuard>${r.$1}>>password>1>${r.$2}>>>0>0>cfg-pia-wg').map((r) => '<$r').join());
    for (var i = 0; i < rows.length; i++) {
      File('$state/unit_$i').writeAsStringSync('${rows[i].$1}');
    }
    File('$state/nv/vpnc_default_wan').writeAsStringSync('0');
    File('$state/nv/vpnc_unit').writeAsStringSync('1');
    File('$state/up').writeAsStringSync('wgc1\nwgc5\nwgc3\nwgc2\nwgc4\n');
    final then = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    for (final s in [1, 2, 3, 4, 5]) {
      File('$state/hs_wgc$s').writeAsStringSync('$then');
    }
    File('$state/cru').writeAsStringSync('$_watchdogCru\n');
    File('$state/tmp/syslog.log').writeAsStringSync('Oct 14 17:00:00 rc_service: earlier\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs the script as it would run on the router, its /tmp moved into the state folder.
  Future<String> run([List<String> args = const []]) async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed "s#/tmp/#$STATE/tmp/#g" "$1" > po.sh && shift && exec sh po.sh "$@"';
    final r = await runSh(shell!, ['-c', cmd, 'sh', '${Directory.current.path}/scripts/pktrunner-order.sh', ...args],
        environment: env);
    return '${r.stdout}${r.stderr}';
  }

  List<String> lines(String name) {
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
  }

  void expectPutBack(String out) {
    expect(lines('up'), containsAll(['wgc2', 'wgc4']), reason: out);
    expect(lines('cru'), contains(_watchdogCru), reason: 'the watchdog it paused');
    expect(File('$state/nv/vpnc_unit').readAsStringSync(), '1', reason: 'vpnc_unit as it was');
    expect(Directory('$state/tmp/pktrunner-order.lock').existsSync(), isFalse, reason: 'the lock');
  }

  test('starts wgc4 as the 4th and wgc2 as the 5th, and reads two errors as following the count', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rule').writeAsStringSync('4');
    final out = await run();
    expect(lines('services'), ['stop_vpnc wgc2', 'stop_vpnc wgc4', 'restart_vpnc wgc4', 'restart_vpnc wgc2'], reason: out);
    expect(out, contains('wgc4 started as client tunnel 4: 1 pktrunner error(s)'));
    expect(out, contains('wgc2 started as client tunnel 5: 1 pktrunner error(s)'));
    expect(out, contains('VERDICT: it follows the count'));
    expect(out, contains('Both tunnels are up again.'));
    expect(lines('logger'), ['**PKTRUNNER-ORDER START** wgc2 and wgc4', '**PKTRUNNER-ORDER END**']);
    expectPutBack(out);
  });

  test('no errors at all reads as the count theory not supported', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final out = await run();
    expect(out, contains('VERDICT: neither logged it this time'));
    expectPutBack(out);
  });

  test('an error on the 5th only reads as following neither cleanly', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rule').writeAsStringSync('5');
    final out = await run();
    expect(out, contains('VERDICT: only one logged it'));
  });

  test('refuses, touching nothing, when either tunnel is the default connection', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/nv/vpnc_default_wan').writeAsStringSync('8'); // wgc4's index 6
    final out = await run();
    expect(out, contains('REFUSED: wgc4 is the default connection'));
    expect(lines('services'), isEmpty);
    expect(lines('cru'), contains(_watchdogCru));
  });

  test('refuses when a tunnel is not up, and when another copy is running', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/up').writeAsStringSync('wgc1\nwgc5\nwgc3\nwgc2\n');
    expect(await run(), contains("REFUSED: wgc4 isn't up and handshaking"));
    File('$state/up').writeAsStringSync('wgc1\nwgc5\nwgc3\nwgc2\nwgc4\n');
    Directory('$state/tmp/pktrunner-order.lock').createSync();
    expect(await run(), contains('REFUSED: already running'));
    expect(lines('services'), isEmpty);
  });

  test('takes other slots, and refuses nonsense', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rule').writeAsStringSync('4');
    final out = await run(['3', '2']);
    expect(lines('services'), ['stop_vpnc wgc3', 'stop_vpnc wgc2', 'restart_vpnc wgc2', 'restart_vpnc wgc3'], reason: out);
    expect(await run(['2', '2']), contains('must be different'));
    expect(await run(['2', '9']), contains('usage'));
  });

  test('a tunnel that does not come back is said plainly, and the other is still put back', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/ignore_wgc4').writeAsStringSync('');
    final out = await run();
    expect(out, contains("wgc4 didn't come up with a fresh handshake in 45 s"));
    expect(out, contains('wgc4 did NOT come back: start it in the app'));
    expect(out, isNot(contains('ANSWERS')));
    expect(lines('up'), contains('wgc2'), reason: 'wgc2 was put back');
    expect(lines('cru'), contains(_watchdogCru));
    expect(Directory('$state/tmp/pktrunner-order.lock').existsSync(), isFalse);
  });
}
