// tunnel_status.dart - each tunnel's status from `wg show`, and a speed test through it, for the NETWORK
// screen (ID-600, ID-604).
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// The status is one read of the router, the same `wg show` the app already uses for handshake ages
// (kHandshakeAgesCommand), plus the watchdog's own log for its restarts. The speed test is the router's own
// throughput to a test server through one tunnel, which depends on the router's CPU (it does the WireGuard
// encryption), the PIA server's load and the distance; it is not the speed a device gets over Wi-Fi
// (plan_network-tunnel-status.md). It is aimed through the tunnel as NETWORK's lookup is, so a request is
// never sent by the WAN and counted as the tunnel's.

/// The marker that starts each tunnel's part of [tunnelStatusCommand]'s output.
const String kTunnelStatusMarker = '@@STATUS wgc';

/// What `wg show` and the watchdog's log say about one tunnel. A field is null when the router didn't say.
class TunnelStatus {
  const TunnelStatus({this.handshakeAgeSeconds, this.bytesIn, this.bytesOut, this.endpoint = '', this.restarts});

  /// Seconds since the latest handshake; null when there has been none, or the router's clock wasn't read.
  final int? handshakeAgeSeconds;

  /// Received and sent since the interface came up (`wg show wgcN transfer`).
  final int? bytesIn, bytesOut;

  /// The server's address and port (`wg show wgcN endpoints`), or ''.
  final String endpoint;

  /// The restarts in the watchdog's log for the slot, which the router empties each midnight; null when
  /// the slot has no watchdog log.
  final int? restarts;

  /// Whether the router said anything at all.
  bool get isEmpty => handshakeAgeSeconds == null && bytesIn == null && endpoint.isEmpty && restarts == null;
}

/// The log lines that say the watchdog restarted slot N: Merlin's stop of the tunnel, stock's restart through
/// VPN Fusion, and stock's restart of the interface on a slot with no VPN Fusion row. Read from the
/// watchdog's own script (`_kRestartMerlin`, `_kRestartStock`), not yet measured on a router.
List<String> restartLogPatterns(int slot) =>
    ['Stopping wgc$slot', 'Restarting wgc$slot through VPN Fusion', 'No vpnc_clientlist row for wgc$slot'];

/// One router command that reads each of [slots]' status. Read only.
///
/// For each slot it prints a marker, then `now` (the router's clock), `hs` (the latest handshake as epoch
/// seconds, 0 for none), `xfer` (bytes received and sent), `ep` (the server's address and port) and `rb` (the
/// watchdog log's restarts, empty when there is no log).
///
/// [logDir] is where the watchdog's logs are, the router's `/tmp`; a test points it at a folder of its own.
String tunnelStatusCommand(List<int> slots, {String logDir = '/tmp'}) {
  for (final s in slots) {
    if (s < 1 || s > 5) throw ArgumentError.value(s, 'slots');
  }
  if (!RegExp(r'^[A-Za-z0-9_./:-]+$').hasMatch(logDir)) throw ArgumentError.value(logDir, 'logDir');
  final patterns = [for (final s in slots) restartLogPatterns(s).map((p) => "-e '$p'").join(' ')];
  final perSlot = [
    for (var i = 0; i < slots.length; i++)
      '''
echo
echo "$kTunnelStatusMarker${slots[i]}"
echo "now \$(date +%s)"
echo "hs \$(wg show wgc${slots[i]} latest-handshakes 2>/dev/null | awk '{print \$2}' | head -1)"
echo "xfer \$(wg show wgc${slots[i]} transfer 2>/dev/null | awk '{print \$2, \$3}' | head -1)"
echo "ep \$(wg show wgc${slots[i]} endpoints 2>/dev/null | awk '{print \$2}' | head -1)"
echo "rb \$([ -f $logDir/watchdog_wgc${slots[i]}.log ] && grep -c ${patterns[i]} $logDir/watchdog_wgc${slots[i]}.log 2>/dev/null)"''',
  ];
  return perSlot.join('\n');
}

/// Each slot's [TunnelStatus] from [tunnelStatusCommand]'s output. A slot missing from it is an empty status.
Map<int, TunnelStatus> parseTunnelStatuses(String raw, List<int> slots) {
  final found = <int, TunnelStatus>{};
  for (final part in raw.split(kTunnelStatusMarker).skip(1)) {
    final slot = int.tryParse(part.isEmpty ? '' : part[0]);
    if (slot != null) found[slot] = _statusFrom(part.substring(1));
  }
  return {for (final s in slots) s: found[s] ?? const TunnelStatus()};
}

/// One slot's [TunnelStatus] from its `now`, `hs`, `xfer`, `ep` and `rb` lines.
TunnelStatus _statusFrom(String body) {
  final fields = <String, String>{};
  for (final line in body.split('\n')) {
    final t = line.trim();
    final space = t.indexOf(' ');
    if (space > 0) fields[t.substring(0, space)] = t.substring(space + 1).trim();
  }
  final bytes = (fields['xfer'] ?? '').split(RegExp(r'\s+'));
  return TunnelStatus(
    handshakeAgeSeconds: _handshakeAge(int.tryParse(fields['now'] ?? ''), int.tryParse(fields['hs'] ?? '')),
    bytesIn: bytes.length == 2 ? int.tryParse(bytes[0]) : null,
    bytesOut: bytes.length == 2 ? int.tryParse(bytes[1]) : null,
    endpoint: _plainEndpoint(fields['ep'] ?? ''),
    restarts: int.tryParse(fields['rb'] ?? ''),
  );
}

/// Seconds from the latest handshake to [now]; null when there has been none or the clocks disagree.
int? _handshakeAge(int? now, int? handshake) =>
    now != null && handshake != null && handshake > 0 && now >= handshake ? now - handshake : null;

/// The endpoint as `wg show` prints it, or '' for "(none)" or anything that isn't an address and a port.
String _plainEndpoint(String text) => RegExp(r'^[0-9a-fA-F.:\[\]]+:\d{1,5}$').hasMatch(text) ? text : '';

/// "42 s ago", "5 min ago", "3 h ago", "2 days ago": how long since a handshake.
String formatAge(int seconds) {
  if (seconds < 120) return '$seconds s ago';
  if (seconds < 7200) return '${seconds ~/ 60} min ago';
  if (seconds < 172800) return '${seconds ~/ 3600} h ago';
  return '${seconds ~/ 86400} days ago';
}

/// "310 B", "1.2 KB", "310 MB", "1.2 GB": bytes in powers of 1000, as a speed is.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final number = value >= 100 ? value.round().toString() : value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$number ${units[unit]}';
}

// ---- the speed test (ID-604) ----

/// The server the speed test uses: Andrew's choice, Cloudflare's free speed test, which through a tunnel sees
/// only that tunnel's PIA address, never the home address (plan_network-tunnel-status.md).
class SpeedService {
  const SpeedService();
  String get name => 'Cloudflare';
  String get host => 'speed.cloudflare.com';
  String get sourceUrl => 'https://speed.cloudflare.com';

  /// An address to aim at when the phone's DNS gives none below 128.0.0.0, which stock's tunnel table
  /// needs. speed.cloudflare.com resolves to 162.159.x.x and 172.66.x.x, both above it (measured
  /// 2026-11-24), but Cloudflare's published 104.16.0.0/13 answers for it too, given the name as
  /// SNI and in the URL, which `--resolve` does.
  String get fallbackAddress => '104.16.0.1';

  /// Streams at once, in each direction, because one stream often falls short of a fast line.
  int get streams => 4;

  /// Bytes in each request. Cloudflare refuses a download of 100 MB or more (HTTP 403, measured 2026-11-25),
  /// so a stream repeats requests until the time is up. An upload is held in the router's memory while it
  /// is sent, so it is kept smaller.
  int get downBytesPerRequest => 90000000;
  int get upBytesPerRequest => 20000000;
  String get downPath => '/__down?bytes=$downBytesPerRequest';
  String get upPath => '/__up';

  /// A request that answers at once with nothing, for the latency (ID-703).
  String get pingPath => '/__down?bytes=0';
}

/// The service in use. Change this, and only this, to change server.
const SpeedService kSpeedService = SpeedService();

/// What the confirmation says about the data used, which depends on the speed: a test is a time, not an
/// amount. Cloudflare's own test in a browser is the same, and takes about 40 seconds.
String speedTestDataUse() =>
    'as much as the tunnel can carry in $kSpeedSeconds seconds each way, about ${formatBytes(125000 * kSpeedSeconds)} '
    'for each 1 Mbps, so a 100 Mbps tunnel uses about ${formatBytes(12500000 * kSpeedSeconds)} each way';

/// The marker that starts the speed test's reply for one tunnel.
const String kSpeedMarker = '@@SPEED wgc';

/// The policy rule priority the stock path uses, its own: 1000 is the watchdog's, 1002 ENABLE's and 1003
/// NETWORK's lookup.
const int kSpeedPriority = 1004;

/// Seconds each direction runs for. A tunnel's speed ramps up (Cloudflare's own graph shows it climbing for
/// seconds), so a short test reads low: 6 MB took a few seconds and gave a fraction of the line's speed.
const int kSpeedSeconds = 20;

/// Seconds read before each direction starts, for what other devices are already sending through the tunnel,
/// which is taken off the test's rates.
const int kSpeedBaselineSeconds = 2;

/// Samples (one a second) a direction needs before its figure is their 90th percentile; fewer, or counters
/// that gave nothing, and it is the bytes moved over the window.
const int kSpeedMinSamples = 5;

/// Requests timed for the latency, after one more that opens the connection and is dropped: on a reused
/// connection a request costs one round trip, and the first also pays for the connection (measured
/// 2026-11-25: 187 ms for the first, 62 to 73 ms for the rest).
const int kSpeedLatencyProbes = 10;

/// One router command that tests slot [slot]'s speed against [service] at [address] (an IPv4 address below
/// 128.0.0.0 on stock, where a tunnel's table carries only `0.0.0.0/1`).
///
/// Stock aims a rule for the one address into the tunnel's table (10 minus the slot), reads it back with
/// `ip route get`, and takes it out after, answering `@@NOROUTE` and sending nothing when the route isn't
/// through the tunnel. Merlin binds to the tunnel with `--interface`. Download is [SpeedService.streams]
/// curls at once, then upload the same with zeros piped in; each curl prints `D` or `U`, the bytes moved and
/// the seconds it took. Not yet measured on either router.
String tunnelSpeedCommand(int slot, String address, {required bool stock, SpeedService service = kSpeedService}) {
  if (slot < 1 || slot > 5) throw ArgumentError.value(slot, 'slot');
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(address)) throw ArgumentError.value(address, 'address');
  final h = service.host;
  final curl = 'curl -s -f -o /dev/null --max-time "\$REM" --resolve "$h:443:\$IP"';
  final bind = stock ? '' : ' --interface "wgc$slot"';
  // Each stream repeats its request until the window is over, the last one cut short at the end of it. A
  // curl that failed outright (exit 28 is only the cut, and --fail makes an HTTP error such as Cloudflare's 429 for too many tests one) ends its stream, so a dead or refused tunnel is not retried.
  // The router's ash (BusyBox 1.25) can't parse `$(( ... $(date) ... ))`, so the time is read on its own line.
  //
  // Each direction also reads the tunnel's own byte counter once a second, `Z` for the two seconds before the
  // streams start (what other devices are already sending through the tunnel) and `R` for each second of the
  // window, so the figure can be the 90th percentile of the per-second rates, as Cloudflare's is, and not an
  // average that the ramp-up drags down.
  String streams(String tag, String counter, String request) => '''
    F=/sys/class/net/wgc$slot/statistics/$counter
    J=0
    while [ \$J -lt $kSpeedBaselineSeconds ]; do
      LAST=\$(cat "\$F" 2>/dev/null)
      sleep 1
      CUR=\$(cat "\$F" 2>/dev/null)
      echo "Z $tag \$((CUR - LAST))"
      J=\$((J + 1))
    done
    NOW=\$(date +%s)
    END=\$((NOW + $kSpeedSeconds))
    K=0
    while [ \$K -lt ${service.streams} ]; do
      (
        while :; do
          NOW=\$(date +%s)
          REM=\$((END - NOW))
          [ "\$REM" -ge 1 ] || break
          $request
          ST=\$?
          [ "\$ST" -eq 0 ] || [ "\$ST" -eq 28 ] || break
        done
      ) &
      K=\$((K + 1))
    done
    LAST=\$(cat "\$F" 2>/dev/null)
    J=0
    while [ \$J -lt $kSpeedSeconds ]; do
      sleep 1
      CUR=\$(cat "\$F" 2>/dev/null)
      echo "R $tag \$((CUR - LAST))"
      LAST=\$CUR
      J=\$((J + 1))
    done
    wait''';
  final down = streams('D', 'rx_bytes', '$curl$bind -w \'D %{size_download} %{time_total}\\n\' "https://$h${service.downPath}"');
  final up = streams('U', 'tx_bytes', 'head -c ${service.upBytesPerRequest} /dev/zero | $curl$bind -X POST --data-binary @- '
      '-H \'Content-Type: application/octet-stream\' -w \'U %{size_upload} %{time_total}\\n\' "https://$h${service.upPath}"');
  // The latency comes first, while the tunnel is idle: run during the transfer it would measure the queue the
  // transfer builds. One curl, so the requests share a connection; each `-o` is for the URL after it.
  final ping = '-o /dev/null "https://$h${service.pingPath}"';
  final latency = '    curl -s -f --max-time 15 --resolve "$h:443:\$IP"$bind -w \'L %{time_starttransfer}\\n\' '
      '${List.filled(kSpeedLatencyProbes + 1, ping).join(' ')}';
  // A first request says whether Cloudflare will take the test at all. A refusal (HTTP 429 for too many tests
  // from one address, measured 2026-11-25, with `Retry-After: 1967`) has an empty body, so the status and the
  // wait are all there is to show, and nothing more is sent. `000` is no answer. It has to ask for the real
  // download: on that address 1 MB was answered and 10 MB refused, and a tiny request was answered either way.
  // The status comes with the headers, so the rate limit cuts the body at 100 KB/s and 2 s, about 200 KB.
  final gate = '''    HDR=/tmp/cfg_speed_hdr
    CODE=\$(curl -s -o /dev/null -D "\$HDR" --max-time 2 --limit-rate 100k --resolve "$h:443:\$IP"$bind -w '%{http_code}' "https://$h${service.downPath}")
    echo "H \$CODE"
    if [ "\$CODE" = 200 ]; then
$latency
$down
$up
    else
      echo "RA \$(grep -i '^retry-after:' "\$HDR" 2>/dev/null | tr -dc '0-9')"
    fi
    rm -f "\$HDR"''';
  final run = gate;
  final body = stock
      ? '''TBL=\$((10 - $slot))
  while ip rule del to "\$IP" iif lo lookup "\$TBL" priority $kSpeedPriority 2>/dev/null; do :; done
  ip rule add to "\$IP" iif lo lookup "\$TBL" priority $kSpeedPriority 2>/dev/null
  if ip route get "\$IP" 2>/dev/null | grep -qE " dev wgc$slot( |\\\$)"; then$run
  else
    echo "@@NOROUTE"
  fi
  while ip rule del to "\$IP" iif lo lookup "\$TBL" priority $kSpeedPriority 2>/dev/null; do :; done'''
      : run;
  return '''IP=$address
echo "$kSpeedMarker$slot"
$body''';
}

/// How one speed test ended.
enum SpeedOutcome {
  /// Both directions gave a figure.
  done,

  /// The router had no route through the tunnel, so nothing was sent.
  noRoute,

  /// Sent through the tunnel, and a direction gave no figure.
  failed,

  /// Cloudflare answered the first request with an HTTP error, such as 429 for too many tests, so no test was run.
  refused,
}

/// A speed test's figures. Mbps, or null for a direction that gave none.
class SpeedResult {
  const SpeedResult(this.outcome,
      {this.downMbit, this.upMbit, this.latencyMs, this.jitterMs, this.httpStatus, this.retryAfterSeconds});
  final SpeedOutcome outcome;
  final double? downMbit, upMbit;

  /// For [SpeedOutcome.refused]: the HTTP status Cloudflare gave, and how many seconds it said to wait, if it did.
  final int? httpStatus, retryAfterSeconds;

  /// The median time to the first byte of a request on a reused connection, and the mean difference between
  /// consecutive requests (ID-703). Null when the timing gave too few answers; the speed stands without them.
  final double? latencyMs, jitterMs;
}

/// The 90th percentile (nearest rank) of [values], which Cloudflare's own test reports so the ramp-up and the
/// odd slow second don't set the figure. Null for none.
double? percentile90(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[(sorted.length * 0.9).ceil() - 1];
}

/// The result from [tunnelSpeedCommand]'s output. A direction fails if no request moved a byte (a request
/// that moved nothing, or took no time, is left out). Otherwise its figure is the 90th percentile of the
/// tunnel counter's per-second rates in the window, less the average of the two baseline seconds (`Z`),
/// in Mbps; with fewer than [kSpeedMinSamples] samples, or every one of them 0, it is the bytes the requests
/// moved over the [kSpeedSeconds].
SpeedResult parseSpeedResult(String raw) {
  if (raw.contains('@@NOROUTE')) return const SpeedResult(SpeedOutcome.noRoute);
  final refused = _refusal(raw);
  if (refused != null) return refused;
  final down = _Direction.read(raw, 'D').figure(), up = _Direction.read(raw, 'U').figure();
  final (latency, jitter) = parseLatency(raw);
  return SpeedResult(down == null || up == null ? SpeedOutcome.failed : SpeedOutcome.done,
      downMbit: down, upMbit: up, latencyMs: latency, jitterMs: jitter);
}

/// A refusal by the status request's `H <code>` line, with the `RA <seconds>` wait if there is one; null otherwise.
SpeedResult? _refusal(String raw) {
  final status = int.tryParse(RegExp(r'^H (\d{3})$', multiLine: true).firstMatch(raw)?.group(1) ?? '');
  if (status == null || status < 400) return null;
  final wait = int.tryParse(RegExp(r'^RA (\d+)$', multiLine: true).firstMatch(raw)?.group(1) ?? '');
  return SpeedResult(SpeedOutcome.refused, httpStatus: status, retryAfterSeconds: wait);
}

/// One direction's lines from [parseSpeedResult]'s input: the bytes its requests moved (`D`/`U` lines), the
/// baseline seconds (`Z`) and the per-second samples (`R`) of the counter.
class _Direction {
  _Direction(this._tag);

  factory _Direction.read(String raw, String tag) {
    final d = _Direction(tag);
    for (final line in raw.split('\n')) {
      d._add(line.trim().split(RegExp(r'\s+')));
    }
    return d;
  }

  final String _tag;
  int _bytes = 0;
  final List<int> _baseline = [], _rates = [];

  void _add(List<String> p) {
    if (p.length != 3) return;
    if (p[0] == 'Z' || p[0] == 'R') {
      _sample(p);
    } else if (p[0] == _tag) {
      _request(p);
    }
  }

  void _sample(List<String> p) {
    final n = p[1] == _tag ? int.tryParse(p[2]) : null;
    if (n == null) return;
    (p[0] == 'Z' ? _baseline : _rates).add(n < 0 ? 0 : n);
  }

  /// A request that moved nothing, or took no time, is left out.
  void _request(List<String> p) {
    final b = int.tryParse(p[1]), t = double.tryParse(p[2]);
    if (b != null && t != null && b > 0 && t > 0) _bytes += b;
  }

  /// Null when no request moved a byte; the 90th percentile of the rates less the baseline when there are
  /// enough samples and some are not 0; otherwise the bytes moved over the window.
  double? figure() {
    if (_bytes == 0) return null;
    if (_rates.length < kSpeedMinSamples || !_rates.any((r) => r > 0)) return _bytes * 8 / kSpeedSeconds / 1e6;
    final idle = _baseline.isEmpty ? 0 : _baseline.reduce((a, b) => a + b) / _baseline.length;
    return percentile90([for (final r in _rates) (r - idle < 0 ? 0 : r - idle) * 8 / 1e6]);
  }
}

/// The latency and jitter, in milliseconds, from the `L <seconds>` lines (a request's time to the first byte).
/// The first line opened the connection and is dropped; the latency is the median of the rest and the jitter
/// the mean difference between consecutive ones, as Cloudflare's own test works it out. Both null with fewer
/// than [kSpeedMinSamples] left, since a median of two says little.
(double?, double?) parseLatency(String raw) {
  final times = <double>[];
  for (final line in raw.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final t = parts.length == 2 && parts[0] == 'L' ? double.tryParse(parts[1]) : null;
    if (t != null && t > 0) times.add(t * 1000);
  }
  if (times.isNotEmpty) times.removeAt(0);
  if (times.length < kSpeedMinSamples) return (null, null);
  final sorted = [...times]..sort();
  final mid = sorted.length ~/ 2;
  final median = sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  var gaps = 0.0;
  for (var i = 1; i < times.length; i++) {
    gaps += (times[i] - times[i - 1]).abs();
  }
  return (median, gaps / (times.length - 1));
}

/// What a refused test says, starting with the HTTP status, then what it means, then the wait Cloudflare
/// asked for in its `Retry-After`: "429, test limit exceeded, try again after about 33 minutes". Cloudflare's
/// body is empty, so there is no message of its own to quote.
String speedRefusedText(SpeedResult r) {
  const reasons = {403: 'forbidden', 429: 'test limit exceeded', 503: 'service unavailable'};
  final code = r.httpStatus ?? 0;
  final reason = reasons[code] ?? (code >= 500 ? 'server error' : '');
  final wait = r.retryAfterSeconds;
  return '$code${reason.isEmpty ? '' : ', $reason'}, '
      '${wait == null ? 'try again later' : 'try again after ${formatWait(wait)}'}';
}

/// "40 seconds", "about 33 minutes", "about 3 hours": a wait to read, not to the second.
String formatWait(int seconds) {
  if (seconds < 90) return '$seconds seconds';
  if (seconds < 5400) return 'about ${(seconds / 60).round()} minutes';
  return 'about ${(seconds / 3600).round()} hours';
}

/// "18 ms", or "2.3 ms" under 10.
String formatMs(double ms) => '${ms >= 10 ? ms.round().toString() : ms.toStringAsFixed(1)} ms';

/// "87 Mbps", or "3.1 Mbps" under 10.
String formatMbit(double mbit) => '${mbit >= 10 ? mbit.round().toString() : mbit.toStringAsFixed(1)} Mbps';
