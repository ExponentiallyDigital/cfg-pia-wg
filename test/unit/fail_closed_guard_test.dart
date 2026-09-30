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
    _set(state, 'vpnc_clientlist', kClientlist);
    // The filter's settings as a stock router ships them (read 2026-09-30).
    _set(state, 'fw_enable_x', '1');
    _set(state, 'fw_lw_enable_x', '0');
    _set(state, 'filter_lw_default_x', 'ACCEPT');
    _set(state, 'filter_lw_date_x', '1111111');
    _set(state, 'filter_lw_time_x', '00002359');
    _set(state, 'filter_lw_time2_x', '00002359');
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

  // ID-348: the second layer, stock's Network Services Filter, which holds from boot.
  group('guard.sh: the Network Services Filter', () {
    const drop20Tcp = '-A FORWARD -s 192.0.2.20/32 -i br0 -o eth0 -p tcp -j DROP';
    const drop20Udp = '-A FORWARD -s 192.0.2.20/32 -i br0 -o eth0 -p udp -j DROP';

    test('a pinned device is listed for TCP and UDP, the filter turned on, and the firewall shows it', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(nv('fw_lw_enable_x'), '1');
      expect(nv('cfg_pia_wg_lw_on'), '1');
      expect(nv('cfg_pia_wg_lwlist'), '192.0.2.20/TCP 192.0.2.20/UDP');
      expect(fw(), [drop20Tcp, drop20Udp]);
      expect(commits(), 1, reason: 'it has to survive a reboot');
      expect('${r.stdout}', contains('filter held 1 of 1'));
      expect(filterLog(), ['Network Services Filter: 1 pinned device(s) kept off the internet connection outside their tunnel']);
    });

    test('an unchanged list costs no NVRAM write and no firewall restart', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      final c = commits(), s = services().length;
      final r = await run();
      expect(commits(), c);
      expect(services(), hasLength(s), reason: 'cron runs it every minute');
      expect('${r.stdout}', contains('filter held 1 of 1'));
    });

    test('an unpinned device is taken out, and the filter turned off again if the app turned it on', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      final r = await run();
      expect(nv('filter_lwlist'), '');
      expect(nv('fw_lw_enable_x'), '0');
      expect(nv('cfg_pia_wg_lw_on'), '');
      expect(nv('cfg_pia_wg_lwlist'), '');
      expect(fw(), isEmpty);
      expect('${r.stdout}', isNot(contains('filter')), reason: 'nothing pinned, nothing to say');
    });

    test("the user's own entries are kept, and a filter they turned on stays on", () async {
      _set(state, 'fw_lw_enable_x', '1');
      _set(state, 'filter_lwlist', '<192.0.2.99>>>>TCP');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      expect(nv('filter_lwlist'), '<192.0.2.99>>>>TCP<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(nv('cfg_pia_wg_lw_on'), '', reason: 'the app did not turn it on');
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      await run();
      expect(nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(nv('fw_lw_enable_x'), '1');
    });

    test("an entry the user made for a pinned device stays theirs", () async {
      _set(state, 'fw_lw_enable_x', '1');
      _set(state, 'filter_lwlist', '<192.0.2.20>>>>TCP');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      expect(nv('filter_lwlist'), '<192.0.2.20>>>>TCP<192.0.2.20>>>>UDP');
      expect(nv('cfg_pia_wg_lwlist'), '192.0.2.20/UDP');
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.20>>0>');
      await run();
      expect(nv('filter_lwlist'), '<192.0.2.20>>>>TCP');
    });

    test('an allow list is refused, and the app takes its own entries out of one', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      _set(state, 'filter_lw_default_x', 'DROP');
      final r = await run();
      expect('${r.stdout}', contains('filter refused: it is an allow list'));
      expect(nv('filter_lwlist'), '', reason: 'in an allow list, its entries would let the device out');
      expect(nv('cfg_pia_wg_lwlist'), '');
    });

    test("a filter that is off with the user's entries in it is not turned on", () async {
      _set(state, 'filter_lwlist', '<192.0.2.99>>>>TCP');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await run();
      expect('${r.stdout}', contains('filter refused: it is off, and turning it on would also apply the entries you made'));
      expect(nv('fw_lw_enable_x'), '0');
      expect(nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(commits(), 0);
    });

    test('a firewall with no filter at all is refused', () async {
      _set(state, 'fw_enable_x', '0');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await run();
      expect('${r.stdout}', contains("filter refused: the router's firewall is off"));
      expect(nv('filter_lwlist'), '');
    });

    test('pings are held only when the user asks, and the setting is put back as it was', () async {
      _set(state, 'filter_lw_icmp_x', '0');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      await run();
      expect(nv('filter_lw_icmp_x'), '0', reason: 'off by default');
      _set(state, 'cfg_pia_wg_lw_icmp', '1');
      await run();
      expect(nv('filter_lw_icmp_x'), '0 8');
      expect(fw(), contains('-A FORWARD -i br0 -o eth0 -p icmp -m icmp --icmp-type 8 -j DROP'));
      _set(state, 'cfg_pia_wg_lw_icmp', '0');
      await run();
      expect(nv('filter_lw_icmp_x'), '0');
      expect(nv('cfg_pia_wg_lw_icmp8'), '');
    });

    test('a restart the service queue dropped is asked for again', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      File('${state.path}/drop_service').writeAsStringSync('');
      final r1 = await run();
      expect('${r1.stdout}', contains('filter held 0 of 1'));
      File('${state.path}/drop_service').deleteSync();
      final r2 = await run();
      expect('${r2.stdout}', contains('filter held 1 of 1'), reason: 'the settings were right; the firewall was asked again');
      expect(services().where((s) => s == 'restart_firewall'), hasLength(2));
    });

    test('a timetable on the filter is reported', () async {
      _set(state, 'filter_lw_date_x', '0111110');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5>');
      final r = await run();
      expect('${r.stdout}', contains('filter scheduled'));
    });

    test('a pin to a deleted profile is listed too, and clear takes out only the app\'s entries', () async {
      _set(state, 'fw_lw_enable_x', '1');
      _set(state, 'filter_lwlist', '<192.0.2.99>>>>TCP');
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.20>>5><1>192.0.2.60>>7>');
      final r = await run();
      expect('${r.stdout}', contains('filter held 2 of 2'));
      expect(nv('filter_lwlist'), contains('<192.0.2.60>>>>UDP'));
      await run(['clear']);
      expect(nv('filter_lwlist'), '<192.0.2.99>>>>TCP');
      expect(nv('cfg_pia_wg_lwlist'), '');
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

  // Hostile review (ID-346): a profile deleted in the web interface leaves its pins behind, and the
  // guard used to drop those devices' rules, sending them to the default connection.
  group('guard.sh: a pin to a profile that no longer exists', () {
    test('is kept off the internet by rule 91 alone, counted, and logged once', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.60>>7>');
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(rules(), ['91: from 192.0.2.60 blackhole']);
      expect(log().where((l) => l.contains('no longer exists')), hasLength(1));
      await run();
      expect(rules(), ['91: from 192.0.2.60 blackhole'], reason: 'a second run adds nothing');
      expect(log().where((l) => l.contains('no longer exists')), hasLength(1), reason: 'and logs nothing more');
    });

    test('keeps its rule 91 when it had a full guard before its profile went', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.60>>5>');
      await run();
      expect(rules(), contains('91: from 192.0.2.60 blackhole'));
      _set(state, 'vpnc_clientlist', 'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg');
      final r = await run();
      expect('${r.stdout}', contains('guarded 1 of 1'));
      expect(rules(), ['91: from 192.0.2.60 blackhole'], reason: 'rule 90 goes with the profile; 91 stays');
    });

    test('pins to an OpenVPN profile and to Internet are left alone', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.61>>3><1>192.0.2.62>>0>');
      final r = await run();
      expect('${r.stdout}', contains('guarded 0 of 0'));
      expect(rules(), isEmpty);
    });

    test('its rule goes when the pin does', () async {
      _set(state, 'vpnc_dev_policy_list', '1>192.0.2.60>>7>');
      await run();
      _set(state, 'vpnc_dev_policy_list', '0>192.0.2.60>>0>');
      await run();
      expect(rules(), isEmpty);
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);

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
