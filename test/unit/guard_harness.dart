// test/unit/guard_harness.dart - the fake stock router the guard.sh tests run against.
//
// Stand-ins for `nvram`, `ip`, `iptables`, `service` and `logger`, each behaving as a stock router was
// measured to, and the real guard script. Shared by fail_closed_guard_test.dart and the guard_*_test.dart
// files, which were one file until 2026-10-01: split so they run side by side, since the tests in
// one file run one after another and each runs real shell, which is slow on Windows.
import 'dart:io';

import 'package:cfg_pia_wg/fail_closed_guard.dart';

// The two tunnels the fixtures use: wgc1 is table 9, wgc5 is table 5. Addresses are documentation
// ranges, never real ones.
const String kClientlist = 'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
    '<pia-aus_melbourne>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg'
    '<Work>OpenVPN>1>>password>1>3>>>0>0>';

const String kNvramStub = r'''#!/bin/sh
case "$1" in
  get) cat "$STATE/nv_$2" 2>/dev/null ;;
  set) k="${2%%=*}"; printf '%s' "${2#*=}" > "$STATE/nv_$k" ;;
  unset) rm -f "$STATE/nv_$2" ;;
  commit) echo x >> "$STATE/commits" ;;
esac
exit 0
''';

// The firmware's firewall restart, as measured on stock 2026-09-30: the Network Services Filter's
// list, when the filter and the firewall are on and it is not an allow list, becomes one DROP rule
// per entry, out of the WAN only; ICMP types become one rule each for the whole LAN. A `drop_service`
// file makes the queue drop the call, as a busy notify_rc does.
const String kServiceStub = r'''#!/bin/sh
echo "$1" >> "$STATE/services"
[ -f "$STATE/drop_service" ] && exit 0
[ "$1" = restart_firewall ] || exit 0
nv() { cat "$STATE/nv_$1" 2>/dev/null; }
: > "$STATE/fw"
if [ "$(nv fw_enable_x)" = 1 ] && [ "$(nv fw_lw_enable_x)" = 1 ] && [ "$(nv filter_lw_default_x)" != DROP ]; then
  for E in $(nv filter_lwlist | tr '<' ' '); do
    ip="${E%%>*}"; pr="${E##*>}"
    echo "-A FORWARD -s $ip/32 -i br0 -o eth0 -p $(echo "$pr" | tr 'A-Z' 'a-z') -j DROP" >> "$STATE/fw"
  done
  for t in $(nv filter_lw_icmp_x); do echo "-A FORWARD -i br0 -o eth0 -p icmp -m icmp --icmp-type $t -j DROP" >> "$STATE/fw"; done
fi
exit 0
''';

const String kIptablesStub = r'''#!/bin/sh
[ "$1" = -S ] && cat "$STATE/fw" 2>/dev/null
exit 0
''';

const String kLoggerStub = r'''#!/bin/sh
shift 2
echo "$*" >> "$STATE/log"
''';

// Keeps rules as `<prio>:<TAB>from <ip> ...` lines and prints them in priority order, as `ip rule
// show` does. Also the route forms the guard uses since ID-364: `ip route show table T` answers
// from $STATE/table_T (main as well), `ip route replace ... table T` adds there as `<dst> dev <dev>
// scope link`, `ip route del <route as shown> table T` takes that line out, `ip route flush table T`
// empties it, and `ip -o link show up` lists $STATE/up. Only the forms the guard uses are understood.
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
    del)
      shift 2; t=""; spec=""
      while [ $# -gt 0 ]; do if [ "$1" = table ]; then t="$2"; shift; else spec="$spec${spec:+ }$1"; fi; shift; done
      [ -f "$STATE/table_$t" ] || exit 2
      # Spacing as `ip` prints it is not spacing as the arguments arrive, so lines compare normalised.
      awk -v s="$spec" '{ l = $0; $1 = $1 } !d && $0 == s { d = 1; next } { print l } END { exit !d }' "$STATE/table_$t" > "$STATE/table_$t.new"
      rc=$?
      mv "$STATE/table_$t.new" "$STATE/table_$t"
      exit $rc ;;
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
/// The fake stock router each guard.sh test runs against: a temporary folder holding the stand-ins
/// above, the state they read and write, and the real guard script. One per test, from [setUp].
class GuardRouter {
  /// A POSIX shell to run the script with, or null where there is none (the tests then skip).
  final String? shell = findGuardShell();
  late Directory dir;
  late Directory state;
  late File script;

  void setUp() {
    dir = Directory.systemTemp.createTempSync('guard_test_');
    state = Directory('${dir.path}/state')..createSync();
    final bin = Directory('${dir.path}/bin')..createSync();
    for (final e in {
      'nvram': kNvramStub,
      'ip': kIpStub,
      'logger': kLoggerStub,
      'service': kServiceStub,
      'iptables': kIptablesStub,
    }.entries) {
      File('${bin.path}/${e.key}').writeAsStringSync(e.value);
    }
    script = File('${dir.path}/guard.sh')..writeAsStringSync(kGuardScript);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...bin.listSync().map((f) => f.path)]);
    set('vpnc_clientlist', kClientlist);
    // The filter's settings as a stock router ships them (read 2026-09-30).
    set('fw_enable_x', '1');
    set('fw_lw_enable_x', '0');
    set('filter_lw_default_x', 'ACCEPT');
    set('filter_lw_date_x', '1111111');
    set('filter_lw_time_x', '00002359');
    set('filter_lw_time2_x', '00002359');
  }

  void tearDown() => dir.deleteSync(recursive: true);

  /// Writes an NVRAM key, as the router holds it.
  void set(String key, String value) => File('${state.path}/nv_$key').writeAsStringSync(value);

  // The stand-ins first, then the shell's own Unix tools, then everything else. Without the middle
  // step, a test run from PowerShell or cmd found C:\Windows\System32\sort.exe before Git's `sort`:
  // it rejects `-u` and `-k`, prints nothing, and every rule the script had added read back as
  // missing (2026-09-24). The first PATH entry is the stand-ins' directory, already converted to
  // the shell's own form; `/usr/bin` is Git's tools on Windows and where they are anyway on Linux.
  static const _unixToolsFirst = r'PATH="${PATH%%:*}:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"';

  /// How long `guard.sh soon` waits for a newer request; 10 s on the router.
  int soonSeconds = 1;

  Future<ProcessResult> run([List<String> args = const []]) {
    final sep = Platform.isWindows ? ';' : ':';
    return Process.run(shell!, ['-c', _unixToolsFirst, 'sh', script.path, ...args], environment: {
      'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state.path,
      'GUARD_LOCK': '${state.path}/lock',
      'GUARD_NEXT': '${state.path}/next',
      'GUARD_SOON': '$soonSeconds',
      'LW_WAIT': '1',
    });
  }

  String nv(String key) {
    final f = File('${state.path}/nv_$key');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  List<String> fw() {
    final f = File('${state.path}/fw');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (l.trim().isNotEmpty) l] : [];
  }

  List<String> services() {
    final f = File('${state.path}/services');
    return f.existsSync() ? f.readAsLinesSync() : [];
  }

  int commits() {
    final f = File('${state.path}/commits');
    return f.existsSync() ? f.readAsLinesSync().length : 0;
  }

  List<String> rules() {
    final f = File('${state.path}/rules');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (l.trim().isNotEmpty) l.replaceAll('\t', ' ')] : [];
  }

  /// The guard's own syslog lines. The filter's (ID-348) are [filterLog]'s, so a test of one isn't
  /// broken by the other.
  List<String> log() {
    final f = File('${state.path}/log');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (!l.startsWith('Network Services Filter')) l] : [];
  }

  List<String> filterLog() {
    final f = File('${state.path}/log');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (l.startsWith('Network Services Filter')) l] : [];
  }

  /// The main table of a stock router with documentation addresses, as read 2026-10-03: the default,
  /// host routes to the router's own DNS servers and its gateway, and the WAN subnet, all via the
  /// WAN; the LAN and a guest bridge; the router's WireGuard server's peers; loopback.
  void mainTable() => File('${state.path}/table_main').writeAsStringSync('''
default via 198.51.100.1 dev eth0
1.0.0.2 via 198.51.100.1 dev eth0  metric 1
1.1.1.2 via 198.51.100.1 dev eth0  metric 1
10.6.0.2 dev wgs1  scope link
127.0.0.0/8 dev lo  scope link
198.51.100.0/24 dev eth0  proto kernel  scope link  src 198.51.100.36
198.51.100.1 dev eth0  proto kernel  scope link
192.168.1.0/24 dev br0  proto kernel  scope link  src 192.168.1.1
192.168.101.0/24 dev br1  proto kernel  scope link  src 192.168.101.1
''');

  /// Table [t] as `ip route show table` prints it here; empty when it holds nothing.
  List<String> table(int t) {
    final f = File('${state.path}/table_$t');
    return f.existsSync() ? [for (final l in f.readAsLinesSync()) if (l.trim().isNotEmpty) l] : [];
  }

  /// The router restarting its firewall by itself, as it does when its connection changes: the
  /// Network Services Filter is rebuilt from NVRAM.
  Future<void> firewallRestart() async {
    final sep = Platform.isWindows ? ';' : ':';
    await Process.run(shell!, ['-c', _unixToolsFirst, 'sh', '${dir.path}/bin/service', 'restart_firewall'], environment: {
      'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state.path,
    });
  }

  void up(String iface) => File('${state.path}/up').writeAsStringSync('$iface\n');
}

String? findGuardShell() {
  for (final candidate in ['sh', 'bash']) {
    try {
      if (Process.runSync(candidate, ['-c', 'exit 0']).exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}
