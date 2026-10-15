// test/unit/runner_host_table_test.dart - scripts/runner-host-table.sh against a fake router (ID-393).
//
// The script reads Broadcom's accelerator table of the router's own addresses with `bs`, and says
// whether an important address - the WAN, a LAN, the WireGuard server - has been left out; `wan`
// reconnects the WAN and reads it before and after. The stand-in `bs` prints the table as the real
// one did on 2026-10-14, from a file; the stand-in `service` can reconnect the WAN either leaving the
// table as it was, or with a tunnel taking the WAN's place, the order that would do harm.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

// The table in the format `bs /b/e system` printed it, with the lines around it. The first version of
// the script read every line of this and nothing on the router (2026-10-14), so the fake can also
// print it padded with a tab and ended with a carriage return ($STATE/bs_padded), or print the
// object with no table lines at all ($STATE/bs_empty).
const _bs = r'''#!/bin/sh
[ "$1 $2" = "/b/e system" ] || exit 1
echo "system object"
if [ ! -f "$STATE/bs_empty" ]; then
  i=0; while read -r a; do
    if [ -f "$STATE/bs_padded" ]; then printf '\tipv4_host_address_table[%s] : %s \r\n' "$i" "$a"; else echo "ipv4_host_address_table[$i] : $a"; fi
    i=$((i + 1))
  done < "$STATE/table"
fi
echo "              qm_cfg : {number_of_ds_queues=0}"
''';

const _ip = r'''#!/bin/sh
case "$*" in
  "-o -4 addr show") n=1; while read -r i a; do echo "$n: $i    inet $a/32 scope global $i\       valid_lft forever"; n=$((n + 1)); done < "$STATE/addrs" ;;
  "-o link show up") while read -r i a; do case "$i" in wgc*) [ -f "$STATE/down_$i" ] || echo "9: $i: <UP,LOWER_UP> mtu 1420" ;; esac; done < "$STATE/addrs" ;;
esac
exit 0
''';

// restart_wan_if: every tunnel handshakes again, unless $STATE/stays_down_<if>; with $STATE/steal,
// the WAN loses its place in the table to wgc4, as a tunnel coming up first would take it.
const _service = r'''#!/bin/sh
echo "$1" >> "$STATE/services"
case "$1" in
  "restart_wan_if 0")
    for i in 1 2 3 4 5; do [ -f "$STATE/stays_down_wgc$i" ] && touch "$STATE/down_wgc$i" || date +%s > "$STATE/hs_wgc$i"; done
    if [ -f "$STATE/steal" ]; then grep -v '^198\.51\.100\.7$' "$STATE/table" > "$STATE/t.new"; echo 10.0.0.4 >> "$STATE/t.new"; mv "$STATE/t.new" "$STATE/table"; fi
    echo "kernel: [ERROR pktrunner] runnerUcast_inetaddr_event,220: Could not rdpa_system_ipv4_host_address_table_add ret=-3" >> "$STATE/tmp/syslog.log" ;;
esac
''';

const _nvram = r'''#!/bin/sh
[ "$1 $2" = "get wan0_ifname" ] && printf eth0
exit 0
''';
const _ping = '#!/bin/sh\n[ -f "\$STATE/offline" ] && exit 1\nexit 0\n';
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

const _watchdogCru = '*/5 * * * * /jffs/cfg-pia-wg/watchdog_wgc1.sh #watchdog_wgc1#';

// The router as measured on 2026-10-14, with invented addresses: 8 places, wgc4 and wgc2 left out.
const _addrs = 'lo 127.0.0.1\nlo 127.0.1.1\neth0 198.51.100.7\nbr0 192.168.1.1\nbr1 192.168.101.1\n'
    'wgc1 10.0.0.1\nwgc5 10.0.0.5\nwgs1 10.6.0.1\nwgc3 10.0.0.3\nwgc4 10.0.0.4\nwgc2 10.0.0.2\n';
const _table = '127.0.1.1\n192.168.1.1\n192.168.101.1\n10.6.0.1\n198.51.100.7\n10.0.0.5\n10.0.0.1\n10.0.0.3\n';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('runner_host_table_');
    state = '${dir.path}/state';
    Directory('$state/tmp').createSync(recursive: true);
    Directory('${dir.path}/bin').createSync();
    final stubs = {
      'bs': _bs, 'ip': _ip, 'service': _service, 'nvram': _nvram, 'ping': _ping,
      'wg': _wg, 'cru': _cru, 'logger': _logger, 'sleep': _sleep,
    };
    for (final e in stubs.entries) {
      File('${dir.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    File('$state/addrs').writeAsStringSync(_addrs);
    File('$state/table').writeAsStringSync(_table);
    File('$state/cru').writeAsStringSync('$_watchdogCru\n');
    File('$state/tmp/syslog.log').writeAsStringSync('kernel: [ERROR pktrunner] ... rdpa_system_ipv4_host_address_table_add ret=-3\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs the script with its /bin/bs and /tmp moved into the fake router. Returns (exit, output).
  Future<(int, String)> run([List<String> args = const []]) async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed -e "s#/tmp/#$STATE/tmp/#g" -e "s#BS=/bin/bs#BS=$P/bs#" "$1" > rht.sh && shift && exec sh rht.sh "$@"';
    final r = await runSh(shell!, ['-c', cmd, 'sh', '${Directory.current.path}/scripts/runner-host-table.sh', ...args],
        environment: env);
    return (r.exitCode, '${r.stdout}${r.stderr}');
  }

  List<String> lines(String name) {
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
  }

  group('check', () {
    test('as measured: every important address in, the two last tunnels out', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final (code, out) = await run();
      expect(code, 0, reason: out);
      expect(out, contains('table: 8 addresses in use'));
      expect(out, contains('in      eth0 198.51.100.7 (important, the WAN)'));
      expect(out, contains('NOT IN  wgc4 10.0.0.4 (tunnel)'));
      expect(out, contains('important addresses left out: 0'));
      expect(out, contains('tunnel addresses left out: wgc4 wgc2'));
      expect(out, contains('pktrunner errors in the log: 1'));
      expect(lines('services'), isEmpty, reason: 'check changes nothing');
    });

    test('the WAN left out is named, and is the exit status', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/table').writeAsStringSync(_table.replaceFirst('198.51.100.7\n', '10.0.0.4\n'));
      final (code, out) = await run(['check']);
      expect(code, 1, reason: out);
      expect(out, contains('NOT IN  eth0 198.51.100.7 (important, the WAN)'));
      expect(out, contains('important addresses left out: 1 - eth0'));
    });

    test('reads the table padded with a tab and ended with a carriage return', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/bs_padded').writeAsStringSync('');
      final (code, out) = await run();
      expect(code, 0, reason: out);
      expect(out, contains('table: 8 addresses in use'));
      expect(out, contains('in      eth0 198.51.100.7 (important, the WAN)'));
    });

    // 2026-10-14: the first version read no addresses on the router and called every one left out.
    test('a table it cannot read is said, never taken as empty', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/bs_empty').writeAsStringSync('');
      final (code, out) = await run();
      expect(code, 3, reason: out);
      expect(out, contains('UNREADABLE'));
      expect(out, contains("the table couldn't be read, so nothing is known about it"));
      expect(out, isNot(contains('NOT IN')));
    });

    test('refuses without bs, and refuses nonsense', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/bin/bs').deleteSync();
      expect((await run()).$2, contains('REFUSED: no '));
      expect((await run(['other'])).$2, contains('usage'));
    });
  });

  group('wan', () {
    test('a reconnect that keeps every important address in says so, and puts the watchdogs back', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      final (code, out) = await run(['wan']);
      expect(code, 0, reason: out);
      expect(lines('services'), ['restart_wan_if 0']);
      expect(out, contains('VERDICT: the reconnect left every important address in the table'));
      expect(out, contains('tunnels back with a fresh handshake: wgc1 wgc5 wgc3 wgc4 wgc2'));
      expect(out, contains('pktrunner errors during the reconnect: 1'));
      expect(lines('cru'), [_watchdogCru]);
      expect(lines('logger'), ['**RUNNER-HOST-TABLE START** wan', '**RUNNER-HOST-TABLE END**']);
      expect(Directory('$state/tmp/runner-host-table.lock').existsSync(), isFalse);
    });

    test('a tunnel taking the WAN\'s place is HARMFUL ORDER, named, and the exit status', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/steal').writeAsStringSync('');
      final (code, out) = await run(['wan']);
      expect(code, 1, reason: out);
      expect(out, contains('important addresses left out before: 0; after: 1 - eth0'));
      expect(out, contains('VERDICT: HARMFUL ORDER - after the reconnect, an important address is left out: eth0'));
      expect(lines('cru'), [_watchdogCru]);
    });

    test('reconnects nothing when it cannot read the table first', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/bs_empty').writeAsStringSync('');
      final (code, out) = await run(['wan']);
      expect(code, 3, reason: out);
      expect(out, contains('the WAN was NOT reconnected'));
      expect(lines('services'), isEmpty);
      expect(lines('cru'), [_watchdogCru], reason: 'the watchdogs put back');
    });

    test('a tunnel that does not come back is said', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/stays_down_wgc3').writeAsStringSync('');
      final (_, out) = await run(['wan']);
      expect(out, contains('; NOT back: wgc3'));
    });

    test('refuses offline, and when another copy is running, touching nothing', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/offline').writeAsStringSync('');
      expect((await run(['wan'])).$2, contains("REFUSED: the router isn't online"));
      File('$state/offline').deleteSync();
      Directory('$state/tmp/runner-host-table.lock').createSync();
      expect((await run(['wan'])).$2, contains('REFUSED: already running'));
      expect(lines('services'), isEmpty);
      expect(lines('cru'), [_watchdogCru]);
    });
  });
}
