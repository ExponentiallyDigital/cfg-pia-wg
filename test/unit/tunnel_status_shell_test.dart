// test/unit/tunnel_status_shell_test.dart - NETWORK's status and speed commands (ID-600, ID-604), run for
// real in a shell against fake router tools.
//
// The command text can't show what matters: that the shell reads it at all, that a route the rule didn't
// change sends nothing (a speed test by the WAN would show the home line's speed as the tunnel's), that no
// rule is left behind, and that the eight curls' output reads as figures. The stand-in `ip` is
// network_lookup_test.dart's: rules in a file, table 10 - slot is wgc<slot>. Not a router: the real curl,
// wg and the watchdog's log lines are what ID-696 checks.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:cfg_pia_wg/tunnel_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _ip = r'''#!/bin/sh
case "$1 $2" in
  "rule add") echo "$4 $8" >> "$STATE/rules" ;;
  "rule del") grep -qx "$4 $8" "$STATE/rules" 2>/dev/null || exit 2
    grep -vx "$4 $8" "$STATE/rules" > "$STATE/r.new"; mv "$STATE/r.new" "$STATE/rules" ;;
  "route get")
    t="$(awk -v ip="$3" '$1 == ip {print $2; exit}' "$STATE/rules" 2>/dev/null)"
    if [ -n "$t" ] && [ ! -f "$STATE/rule_ignored_$((10 - t))" ]; then echo "$3 dev wgc$((10 - t))  src 10.0.0.4 "
    else echo "$3 via 198.51.100.1 dev eth0  src 198.51.100.7 "; fi ;;
esac
exit 0
''';

// Records each call with the rules in force, then prints what the -w format asks for, as curl does: 6 MB in
// 4 s for a download, 2.5 MB in 2 s for an upload. An upload's body is read, as curl reads it.
const _curl = r'''#!/bin/sh
printf '%s | rules: %s\n' "$*" "$(cat "$STATE/rules" 2>/dev/null | tr '\n' ' ')" > "$STATE/curl.$$"
[ -f "$STATE/curl_fails" ] && exit 28
fmt=""
N=0
HDRFILE=""
CODE=200
[ -f "$STATE/http_code" ] && CODE="$(cat "$STATE/http_code")"
while [ $# -gt 0 ]; do
  [ "$1" = "-w" ] && fmt="$2"
  [ "$1" = "-D" ] && HDRFILE="$2"
  case "$1" in *__up) cat > /dev/null ;; esac
  case "$1" in https://*) N=$((N + 1)) ;; esac
  shift
done
# The status check (-D, and a format of just the status): Cloudflare's answer, and for an error its Retry-After.
if [ -n "$HDRFILE" ]; then
  [ "$CODE" = 200 ] || printf 'HTTP/1.1 %s X\r\nRetry-After: 1967\r\n\r\n' "$CODE" > "$HDRFILE"
  printf '%s' "$CODE"
  exit 0
fi
# One answer for each URL, as curl gives with several on one command line; the latency is 20 ms and then 30.
I=0
while [ $I -lt $N ]; do
  I=$((I + 1))
  T=0.020; [ $((I % 2)) -eq 0 ] && T=0.030
  printf '%s\n' "$fmt" | sed -e 's/%{size_download}/6000000/' -e 's/%{time_total}/4.0/' -e 's/%{size_upload}/2500000/' -e "s/%{time_starttransfer}/$T/" -e 's/\\n$//'
done
''';

const _wg = r'''#!/bin/sh
[ "$1" = show ] || exit 1
case "$3" in
  latest-handshakes) printf 'PUBKEY=\t999958\n' ;;
  transfer) printf 'PUBKEY=\t1200000000\t310000000\n' ;;
  endpoints) printf 'PUBKEY=\t203.0.113.50:1337\n' ;;
esac
''';

// A fixed time for the status command. In a speed test (STATE/speed is there) every call is 1 s after the one
// before, counted by a file each call leaves, so the 20 s window ends after a few calls without the test
// waiting for it; appends from several processes to one file are not safe on every filesystem.
const _date = r'''#!/bin/sh
if [ -f "$STATE/speed" ]; then
  : > "$STATE/date.$$"
  echo $((1000000 + $(ls "$STATE" | grep -c '^date\.')))
else
  echo 1000000
fi
''';

// The sampler's one-second sleeps, which would make each speed test here take 44 s. The counters under /sys
// are not there either, so each direction's samples read 0 and the figure is the fallback, the bytes the
// requests moved over the window; the percentile is parseSpeedResult's, in tunnel_status_test.dart.
const _sleep = r'''#!/bin/sh
exit 0
''';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tunnel_status_');
    state = '${dir.path}/state';
    Directory(state).createSync();
    Directory('${dir.path}/bin').createSync();
    for (final (name, body) in [('ip', _ip), ('curl', _curl), ('wg', _wg), ('date', _date), ('sleep', _sleep)]) {
      File('${dir.path}/bin/$name').writeAsStringSync(body);
    }
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['+x', ...['ip', 'curl', 'wg', 'date', 'sleep'].map((n) => '${dir.path}/bin/$n')]);
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> run(String command) async {
    File('${dir.path}/c.sh').writeAsStringSync('$command\n');
    final sep = Platform.isWindows ? ';' : ':';
    final r = await runSh(shell!, ['-c', r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$1"', 'sh', '${dir.path}/c.sh'],
        environment: {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state});
    return '${r.stdout}';
  }

  // Each curl writes a file of its own, since the eight run at once and appends from several processes to
  // one file are not safe on every filesystem (WSL's view of C: loses some).
  List<String> lines(String name) {
    if (name == 'curls') {
      return [
        for (final f in Directory(state).listSync().whereType<File>().where((f) => f.path.contains('curl.')))
          ...f.readAsLinesSync().where((l) => l.isNotEmpty),
      ];
    }
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList() : [];
  }

  group('the status command', () {
    test('is read by the shell, and gives each slot its handshake age, data, server and restarts', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/watchdog_wgc5.log').writeAsStringSync(
          '1 Watchdog started for wgc5\n2 Stopping wgc5\n3 Starting wgc5\n4 Restarting VPN routing\n5 Stopping wgc5\n6 Stopping wgc4\n');
      final raw = await run(tunnelStatusCommand([5, 2], logDir: shPath(dir.path)));
      final s = parseTunnelStatuses(raw, [5, 2]);
      expect(s[5]!.handshakeAgeSeconds, 42);
      expect(s[5]!.bytesIn, 1200000000);
      expect(s[5]!.bytesOut, 310000000);
      expect(s[5]!.endpoint, '203.0.113.50:1337');
      expect(s[5]!.restarts, 2, reason: "the two \"Stopping wgc5\" lines, not wgc4's");
      expect(s[2]!.restarts, isNull, reason: 'wgc2 has no watchdog log');
    });

    test('counts stock\'s restart lines too', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/watchdog_wgc1.log').writeAsStringSync(
          'Restarting wgc1 through VPN Fusion (vpnc_unit=0)\nNo vpnc_clientlist row for wgc1; restarting the interface directly\nRestarting wgc3 through VPN Fusion (vpnc_unit=2)\n');
      final s = parseTunnelStatuses(await run(tunnelStatusCommand([1], logDir: shPath(dir.path))), [1]);
      expect(s[1]!.restarts, 2, reason: "wgc3's line is not wgc1's");
    });

    test('a log with no restart says 0, which is not the same as no log', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('${dir.path}/watchdog_wgc4.log').writeAsStringSync('Watchdog started for wgc4\n');
      final s = parseTunnelStatuses(await run(tunnelStatusCommand([4], logDir: shPath(dir.path))), [4]);
      expect(s[4]!.restarts, 0);
    });
  });

  group('the speed command', () {
    test('on stock, every stream repeats its request, each through the tunnel\'s own table, by name, and no rule is left', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/speed').writeAsStringSync('');
      final r = parseSpeedResult(await run(tunnelSpeedCommand(1, '104.18.40.93', stock: true)));
      expect(r.outcome, SpeedOutcome.done);
      final curls = lines('curls');
      final downs = curls.where((c) => c.contains('__down?bytes=90000000') && !c.contains(' -D ')).length;
      final ups = curls.where((c) => c.contains('https://speed.cloudflare.com/__up')).length;
      expect(downs, greaterThanOrEqualTo(4), reason: 'at least one request on each of the four streams');
      expect(ups, greaterThanOrEqualTo(4));
      final pings = curls.where((c) => c.contains('__down?bytes=0')).length;
      expect(pings, 1, reason: 'one curl for all the latency requests, so they share a connection');
      final gates = curls.where((c) => c.contains(' -D ')).length;
      expect(gates, 1, reason: 'one status request, before anything else');
      expect(downs + ups + pings + gates, curls.length);
      expect(RegExp(r'__down\?bytes=0').allMatches(curls.firstWhere((c) => c.contains('time_starttransfer'))).length, kSpeedLatencyProbes + 1);
      // The fake answers 20 ms then 30 ms alternately: the first is dropped, so ten left, five of each.
      expect(r.latencyMs, closeTo(25, 1e-6));
      expect(r.jitterMs, closeTo(10, 1e-6));
      // The fake curl moves 6 MB down or 2.5 MB up in each request, whatever the time.
      expect(r.downMbit, closeTo(downs * 6000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
      expect(r.upMbit, closeTo(ups * 2500000 * 8 / kSpeedSeconds / 1e6, 1e-9));
      for (final c in curls) {
        expect(c, contains('--resolve speed.cloudflare.com:443:104.18.40.93'));
        expect(c, contains('rules: 104.18.40.93 9'), reason: 'wgc1 is table 9, in force while each asks');
      }
      expect(lines('rules'), isEmpty);
    });

    // The fault this guards against: a test by the WAN, which would show the home line's speed as the tunnel's.
    test('on stock a tunnel the rule does not reach is NOROUTE, nothing is sent, and no rule is left', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/speed').writeAsStringSync('');
      File('$state/rule_ignored_2').writeAsStringSync('');
      final r = parseSpeedResult(await run(tunnelSpeedCommand(2, '104.18.40.93', stock: true)));
      expect(r.outcome, SpeedOutcome.noRoute);
      expect(lines('curls'), isEmpty);
      expect(lines('rules'), isEmpty);
    });

    test('on Merlin each curl binds to the tunnel, and no rule is added', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/speed').writeAsStringSync('');
      final r = parseSpeedResult(await run(tunnelSpeedCommand(3, '104.18.40.93', stock: false)));
      expect(r.outcome, SpeedOutcome.done);
      final curls = lines('curls');
      expect(curls.length, greaterThanOrEqualTo(8));
      for (final c in curls) {
        expect(c, contains('--interface wgc3'));
      }
      expect(lines('rules'), isEmpty);
    });

    // ID-705: Cloudflare answered wgc5 with HTTP 429 and Retry-After: 1967, and the card said only "no figure".
    test('a refusal by Cloudflare is its status and its Retry-After, sends nothing more, and leaves no rule', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/speed').writeAsStringSync('');
      File('$state/http_code').writeAsStringSync('429');
      final r = parseSpeedResult(await run(tunnelSpeedCommand(5, '104.18.40.93', stock: true)));
      expect(r.outcome, SpeedOutcome.refused);
      expect(r.httpStatus, 429);
      expect(r.retryAfterSeconds, 1967);
      expect(speedRefusedText(r), '429, test limit exceeded, try again after about 33 minutes');
      expect(lines('curls'), hasLength(1), reason: 'only the status request, no latency or transfers');
      expect(lines('rules'), isEmpty);
    });

    test('no answer through the tunnel is failed, and leaves no rule', () async {
      if (shell == null) return markTestSkipped('no POSIX shell');
      File('$state/speed').writeAsStringSync('');
      File('$state/curl_fails').writeAsStringSync('');
      final r = parseSpeedResult(await run(tunnelSpeedCommand(4, '104.18.40.93', stock: true)));
      expect(r.outcome, SpeedOutcome.failed);
      expect(lines('rules'), isEmpty);
    });
  });
}
