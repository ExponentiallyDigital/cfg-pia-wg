// test/unit/tunnel_status_test.dart - NETWORK's tunnel status from `wg show` (ID-600) and the speed test
// (ID-604): the router commands for each firmware, and the reading of what they print.
import 'package:cfg_pia_wg/tunnel_status.dart';
import 'package:flutter_test/flutter_test.dart';

const _status5 = '''

$kTunnelStatusMarker${5}
now 1000000
hs 999958
xfer 1200000000 310000000
ep 203.0.113.50:1337
rb 2
''';

void main() {
  group('tunnelStatusCommand', () {
    test('reads, for each slot, the clock, the handshake, the transfer, the endpoint and the watchdog log', () {
      final c = tunnelStatusCommand([5, 1]);
      for (final n in [5, 1]) {
        expect(c, contains('$kTunnelStatusMarker$n'));
        expect(c, contains('wg show wgc$n latest-handshakes'));
        expect(c, contains('wg show wgc$n transfer'));
        expect(c, contains('wg show wgc$n endpoints'));
        expect(c, contains('/tmp/watchdog_wgc$n.log'));
      }
      expect(c, contains('date +%s'));
    });

    test('reads only: nothing it sends changes the router', () {
      final c = tunnelStatusCommand([1, 2, 3, 4, 5]);
      expect(c, isNot(contains('nvram set')));
      expect(c, isNot(contains('ip rule')));
      expect(c, isNot(contains('rm ')));
      expect(c, isNot(contains('service ')));
    });

    test('counts the watchdog restarts of both firmwares', () {
      final c = tunnelStatusCommand([3]);
      expect(c, contains("-e 'Stopping wgc3'"));
      expect(c, contains("-e 'Restarting wgc3 through VPN Fusion'"));
      expect(c, contains("-e 'No vpnc_clientlist row for wgc3'"));
    });

    test('refuses a slot that is not 1 to 5', () {
      expect(() => tunnelStatusCommand([0]), throwsArgumentError);
      expect(() => tunnelStatusCommand([6]), throwsArgumentError);
    });
  });

  group('parseTunnelStatuses', () {
    test('reads the handshake age from the router\'s own clock, the bytes, the endpoint and the restarts', () {
      final s = parseTunnelStatuses(_status5, [5])[5]!;
      expect(s.handshakeAgeSeconds, 42);
      expect(s.bytesIn, 1200000000);
      expect(s.bytesOut, 310000000);
      expect(s.endpoint, '203.0.113.50:1337');
      expect(s.restarts, 2);
      expect(s.isEmpty, isFalse);
    });

    test('a handshake of 0 is none, and a slot the router said nothing of is empty', () {
      final s = parseTunnelStatuses('\n${kTunnelStatusMarker}2\nnow 100\nhs 0\nxfer 0 0\nep (none)\nrb \n', [2, 4]);
      expect(s[2]!.handshakeAgeSeconds, isNull);
      expect(s[2]!.endpoint, '');
      expect(s[2]!.restarts, isNull, reason: 'no watchdog log is no count, not none');
      expect(s[2]!.bytesIn, 0);
      expect(s[4]!.isEmpty, isTrue);
    });

    test('a clock behind the handshake gives no age rather than a negative one', () {
      final s = parseTunnelStatuses('\n${kTunnelStatusMarker}1\nnow 100\nhs 200\n', [1])[1]!;
      expect(s.handshakeAgeSeconds, isNull);
    });

    test('an IPv6 endpoint is kept, and text that is not an endpoint is not', () {
      expect(parseTunnelStatuses('\n${kTunnelStatusMarker}1\nep [2001:db8::1]:51820\n', [1])[1]!.endpoint, '[2001:db8::1]:51820');
      expect(parseTunnelStatuses('\n${kTunnelStatusMarker}1\nep wg: command not found\n', [1])[1]!.endpoint, '');
    });

    test('garbage gives an empty status, not an error', () {
      expect(parseTunnelStatuses('', [1])[1]!.isEmpty, isTrue);
      expect(parseTunnelStatuses('nonsense ${kTunnelStatusMarker}x', [1])[1]!.isEmpty, isTrue);
    });
  });

  group('formatting', () {
    test('formatAge', () {
      expect(formatAge(42), '42 s ago');
      expect(formatAge(119), '119 s ago');
      expect(formatAge(120), '2 min ago');
      expect(formatAge(7199), '119 min ago');
      expect(formatAge(7200), '2 h ago');
      expect(formatAge(172800), '2 days ago');
    });

    test('formatBytes', () {
      expect(formatBytes(310), '310 B');
      expect(formatBytes(1200), '1.2 KB');
      expect(formatBytes(310000000), '310 MB');
      expect(formatBytes(1200000000), '1.2 GB');
      expect(formatBytes(0), '0 B');
    });

    test('formatMbit', () {
      expect(formatMbit(87.4), '87 Mbps');
      expect(formatMbit(3.14), '3.1 Mbps');
    });
  });

  group('tunnelSpeedCommand', () {
    test('stock aims one rule at the tunnel, checks the route, sends nothing without it, and takes the rule out', () {
      final c = tunnelSpeedCommand(5, '104.18.40.93', stock: true);
      expect(c, contains('$kSpeedMarker${5}'));
      expect(c, contains('TBL=\$((10 - 5))'));
      expect(c, contains('priority $kSpeedPriority'));
      expect(c, contains('ip route get'));
      expect(c, contains('@@NOROUTE'));
      expect(c, contains(' dev wgc5( |\\\$)'));
      expect(c, isNot(contains('--interface')));
      expect(RegExp(r'ip rule del').allMatches(c).length, 2, reason: 'cleared before adding and again after');
      expect(c.lastIndexOf('ip rule del'), greaterThan(c.lastIndexOf('curl')), reason: 'the rule is removed after the last curl');
    });

    test('Merlin binds to the tunnel and adds no rule', () {
      final c = tunnelSpeedCommand(2, '104.18.40.93', stock: false);
      expect(c, contains('--interface "wgc2"'));
      expect(c, isNot(contains('ip rule')));
      expect(c, isNot(contains('@@NOROUTE')));
    });

    test('downloads and uploads at once on every stream, to the service, with the hostname for TLS and the address for the route', () {
      const s = kSpeedService;
      final c = tunnelSpeedCommand(1, '104.18.40.93', stock: false);
      expect(c, contains('IP=104.18.40.93'));
      expect(c, contains('--resolve "${s.host}:443:\$IP"'));
      expect(c, contains('https://${s.host}${s.downPath}'));
      expect(c, contains('https://${s.host}${s.upPath}'));
      expect(c, contains('-lt ${s.streams}'));
      expect(c, contains('head -c ${s.upBytesPerRequest} /dev/zero'));
      expect(RegExp(r'\bwait\b').allMatches(c).length, 2, reason: 'each direction is waited for before the next');
    });

    // ID-701: 6 MB took a few seconds and read a fraction of the line's speed, since a tunnel ramps up.
    test('each stream repeats its request for the window, and the last is cut at the end of it', () {
      final c = tunnelSpeedCommand(1, '104.18.40.93', stock: false);
      expect(RegExp(r'END=\$\(\(NOW \+ 20\)\)').allMatches(c).length, 2, reason: 'a 20 s window for each direction');
      expect(c, isNot(contains(r'$($(')), reason: "the router's ash can't parse a command substitution inside arithmetic");
      expect(c, isNot(contains(r'$((END - $(')));
      expect(c, contains('--max-time "\$REM"'));
      expect(c, contains('curl -s -f '), reason: 'an HTTP error such as 429 ends the stream, not a loop of refused requests');
      expect(c, contains('[ "\$ST" -eq 28 ]'), reason: 'the cut is how a request ends, not a failure');
      expect(kSpeedService.downBytesPerRequest, lessThan(100000000), reason: 'Cloudflare refuses 100 MB and over with a 403');
    });

    // ID-704: Cloudflare's figure is a 90th percentile, and the plain average over a window that ramps up reads low.
    test('each direction reads the tunnel\'s own byte counter every second, after two baseline seconds', () {
      final c = tunnelSpeedCommand(5, '104.18.40.93', stock: false);
      expect(c, contains('/sys/class/net/wgc5/statistics/rx_bytes'));
      expect(c, contains('/sys/class/net/wgc5/statistics/tx_bytes'));
      expect(c, contains('echo "Z D '));
      expect(c, contains('echo "R U '));
      expect(c, contains('-lt $kSpeedBaselineSeconds ]'));
      expect(RegExp(r'sleep 1').allMatches(c).length, 4, reason: 'one in each baseline and each sampling loop, two directions');
    });

    // ID-703: measured on a Merlin router, 2026-11-25: 187 ms for the first request, 62 to 73 ms for the rest.
    test('the latency is one curl of eleven requests, before the transfers, on the same route', () {
      final c = tunnelSpeedCommand(2, '104.18.40.93', stock: false);
      final ping = RegExp(r'__down\?bytes=0').allMatches(c).length;
      expect(ping, kSpeedLatencyProbes + 1, reason: 'one opens the connection and is dropped');
      expect(c, contains(r"-w 'L %{time_starttransfer}\n'"));
      expect(c.indexOf('bytes=0'), lessThan(c.lastIndexOf('bytes=90000000')), reason: 'while the tunnel is idle');
      final line = c.split('\n').firstWhere((l) => l.contains('time_starttransfer'));
      expect(line, contains('--interface "wgc2"'));
      expect(line, contains('--resolve "speed.cloudflare.com:443:\$IP"'));
      expect(RegExp(r'curl [^\n]*time_starttransfer').allMatches(c).length, 1, reason: 'a single curl, so the requests share a connection');
    });

    test('a first request checks the status, and the transfers run only on a 200', () {
      final c = tunnelSpeedCommand(2, '104.18.40.93', stock: false);
      expect(c, contains(r'-D "$HDR"'));
      expect(c, contains(r"-w '%{http_code}'"));
      expect(c, contains(r'echo "H $CODE"'));
      expect(c, contains(r'if [ "$CODE" = 200 ]; then'));
      expect(c, contains('retry-after'));
      expect(c.indexOf('echo "H '), lessThan(c.indexOf('time_starttransfer')));
      expect(RegExp('bytes=90000000').allMatches(c).length, 2, reason: 'the status request, and the streams');
      expect(c.indexOf(r'if [ "$CODE" = 200 ]'), lessThan(c.lastIndexOf('bytes=90000000')), reason: 'no stream runs on a refusal');
      expect(c, contains('--limit-rate 100k'), reason: 'the status request moves about 200 KB, not a download');
    });

    test('refuses a slot that is not 1 to 5 and an address that is not IPv4', () {
      expect(() => tunnelSpeedCommand(6, '104.18.40.93', stock: true), throwsArgumentError);
      expect(() => tunnelSpeedCommand(1, 'speed.cloudflare.com', stock: true), throwsArgumentError);
      expect(() => tunnelSpeedCommand(1, '1.2.3.4; reboot', stock: true), throwsArgumentError);
    });
  });

  group('parseSpeedResult', () {
    test('sums the bytes of every request and divides by the window', () {
      const raw = '''
@@SPEED wgc5
D 90000000 9.0
D 90000000 9.5
D 60000000 20.0
D 90000000 9.2
D 40000000 11.0
U 20000000 4.0
U 20000000 4.5
U 12000000 20.0
''';
      final r = parseSpeedResult(raw);
      expect(r.outcome, SpeedOutcome.done);
      expect(r.downMbit, closeTo(370000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
      expect(r.upMbit, closeTo(52000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
    });

    // The first second of a ramp-up is 188 Mbps and the rest 284 to 438: measured on a Merlin router, 2026-11-25.
    test('with a second-by-second rate the figure is its 90th percentile, less the baseline, per direction', () {
      final rates = [23.5, 52, 49.25, 49.25, 51.75, 54.75, 43.5, 40, 36.9, 46.6, 42.25, 49, 44.1, 35.5, 47.5, 47.6, 47.4, 41.25, 45.5, 41.9];
      final raw = StringBuffer('@@SPEED wgc1\nZ D 0\nZ D 1000000\nD 90000000 9.0\nD 1 0.1\n');
      for (final r in rates) {
        raw.write('R D ${(r * 1e6 / 8).round()}\n');
      }
      raw.write('Z U 0\nU 20000000 4.0\nR U 5000000\nR U 5000000\nR U 5000000\nR U 5000000\nR U 6250000\n');
      final r = parseSpeedResult('$raw');
      // 20 samples: the 90th percentile is the 18th smallest; the baseline averages 500000 B/s, 4 Mbps.
      final sorted = [...rates]..sort();
      expect(r.downMbit, closeTo(sorted[17] - 4.0, 0.01));
      expect(r.upMbit, closeTo(50.0, 0.01), reason: '5 samples: 40, 40, 40, 40, 50 Mbps, nearest rank 5 of 5');
    });

    test('a baseline above a second\'s rate leaves that second at 0, never negative', () {
      final r = parseSpeedResult('Z D 10000000\nD 9000000 1.0\n${'R D 1000000\n' * 5}U 1 1\n');
      expect(r.downMbit, 0);
    });

    test('too few samples, or counters that read nothing, fall back to the bytes moved over the window', () {
      final few = parseSpeedResult('D 50000000 5.0\nR D 9000000\nR D 9000000\nU 20000000 2.0\n');
      expect(few.downMbit, closeTo(50000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
      final zeros = parseSpeedResult('D 50000000 5.0\n${'R D 0\n' * 20}U 20000000 2.0\n${'R U 0\n' * 20}');
      expect(zeros.downMbit, closeTo(50000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
      expect(zeros.upMbit, closeTo(20000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
    });

    test('samples of one direction are not read as the other\'s, and a direction that moved no bytes fails whatever its counter said', () {
      final r = parseSpeedResult('${'R D 5000000\n' * 20}D 0 1.0\nU 20000000 2.0\n${'R U 1000000\n' * 20}');
      expect(r.outcome, SpeedOutcome.failed);
      expect(r.downMbit, isNull);
      expect(r.upMbit, closeTo(8.0, 1e-9));
    });

    test('latency is the median of the requests after the first, jitter the mean difference between neighbours', () {
      final (latency, jitter) = parseLatency('L 0.187593\nL 0.066768\nL 0.070875\nL 0.069671\nL 0.061969\nL 0.064615\nL 0.073440\n');
      // After the first: 66.768, 70.875, 69.671, 61.969, 64.615, 73.44; the median is the mean of 66.768 and 69.671.
      expect(latency, closeTo((66.768 + 69.671) / 2, 1e-6));
      expect(jitter, closeTo((4.107 + 1.204 + 7.702 + 2.646 + 8.825) / 5, 1e-6));
    });

    test('too few latency answers, or none that are figures, give null and leave the speed alone', () {
      expect(parseLatency('L 0.19\nL 0.07\nL 0.07\n'), (null, null));
      expect(parseLatency('L x\nL 0\nL -1\nL\n'), (null, null));
      expect(parseLatency(''), (null, null));
      final r = parseSpeedResult('D 90000000 9.0\nU 20000000 4.0\nL 0.19\n');
      expect(r.outcome, SpeedOutcome.done);
      expect(r.latencyMs, isNull);
      expect(r.jitterMs, isNull);
    });

    test('an odd number of answers has the middle one for its median', () {
      final (latency, _) = parseLatency('L 1\nL 0.010\nL 0.030\nL 0.020\nL 0.050\nL 0.040\n');
      expect(latency, closeTo(30, 1e-6));
    });

    test('formatMs', () {
      expect(formatMs(66.4), '66 ms');
      expect(formatMs(2.34), '2.3 ms');
    });

    // ID-705: measured on wgc5, 2026-11-25: HTTP 429, an empty body, and Retry-After: 1967.
    test('a refused status check is the status and the wait, whatever else was printed', () {
      final r = parseSpeedResult('@@SPEED wgc5\nH 429\nRA 1967\n');
      expect(r.outcome, SpeedOutcome.refused);
      expect(r.httpStatus, 429);
      expect(r.retryAfterSeconds, 1967);
      expect(r.downMbit, isNull);
    });

    test('a refusal without a Retry-After says to try later, and a 200 or no answer is not a refusal', () {
      final r = parseSpeedResult('H 403\nRA \n');
      expect(r.outcome, SpeedOutcome.refused);
      expect(r.retryAfterSeconds, isNull);
      expect(speedRefusedText(r), '403, forbidden, try again later');
      expect(parseSpeedResult('H 000\nRA \n').outcome, SpeedOutcome.failed, reason: 'no answer at all is the generic failure');
      expect(parseSpeedResult('H 200\nD 90000000 9.0\nU 20000000 4.0\n').outcome, SpeedOutcome.done);
    });

    test('speedRefusedText names the status, what it means and the wait', () {
      String text(int status, int? wait) => speedRefusedText(SpeedResult(SpeedOutcome.refused, httpStatus: status, retryAfterSeconds: wait));
      expect(text(429, 1967), '429, test limit exceeded, try again after about 33 minutes');
      expect(text(503, 30), '503, service unavailable, try again after 30 seconds');
      expect(text(502, 7200), '502, server error, try again after about 2 hours');
      expect(text(418, null), '418, try again later');
      expect(text(429, 1967), startsWith('429'), reason: 'the HTTP code comes first');
    });

    test('formatWait reads as a wait, not to the second', () {
      expect(formatWait(30), '30 seconds');
      expect(formatWait(89), '89 seconds');
      expect(formatWait(90), 'about 2 minutes');
      expect(formatWait(1967), 'about 33 minutes');
      expect(formatWait(5399), 'about 90 minutes');
      expect(formatWait(5400), 'about 2 hours');
    });

    test('percentile90 is the nearest rank', () {
      expect(percentile90([]), isNull);
      expect(percentile90([5]), 5);
      expect(percentile90([for (var i = 1; i <= 10; i++) i.toDouble()]), 9);
      expect(percentile90([for (var i = 20; i >= 1; i--) i.toDouble()]), 18);
    });

    test('no route is reported as such, whatever else it printed', () {
      expect(parseSpeedResult('@@SPEED wgc5\n@@NOROUTE\n').outcome, SpeedOutcome.noRoute);
    });

    test('a direction with no figure fails the test, and keeps the other\'s', () {
      final r = parseSpeedResult('D 6000000 4.0\nU 0 0.0\n');
      expect(r.outcome, SpeedOutcome.failed);
      expect(r.downMbit, isNotNull);
      expect(r.upMbit, isNull);
    });

    test('nothing at all, or lines that are not figures, fail', () {
      expect(parseSpeedResult('').outcome, SpeedOutcome.failed);
      expect(parseSpeedResult('D x y\nU 1\ncurl: (28) timed out\n').outcome, SpeedOutcome.failed);
    });

    test('a request that moved nothing is left out and the others still count', () {
      final r = parseSpeedResult('D 0 20.0\nD 60000000 4.0\nU 20000000 2.0\nU 0 20.0\n');
      expect(r.outcome, SpeedOutcome.done);
      expect(r.downMbit, closeTo(60000000 * 8 / kSpeedSeconds / 1e6, 1e-9));
    });
  });

  group('the speed service', () {
    test('is Cloudflare, and the confirmation says how much, to whom, and what they see', () {
      expect(kSpeedService.host, 'speed.cloudflare.com');
      expect(speedTestDataUse(), contains('20 seconds each way'));
      expect(speedTestDataUse(), contains('about 2.5 MB for each 1 Mbps'));
      expect(speedTestDataUse(), contains('a 100 Mbps tunnel uses about 250 MB each way'));
    });
  });
}
