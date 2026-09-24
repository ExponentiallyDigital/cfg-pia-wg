// Runs the real, generated watchdog script under a POSIX shell against a fake stock router.
//
// BACKLOG ID-205. The script is ~800 lines of shell that until now was tested only by checking
// that its text contained certain lines - which is how ID-192 (a two-strike rule that could never
// fire) passed CI and was found by hand. Here it runs: every command it calls is a stand-in on the
// PATH that reads and writes a state folder, and every fixed path it touches (/tmp, /jffs, /etc) is
// moved into a private folder, so a test sets the router up, runs a check, and reads the result.
//
// What the stand-ins model, and only as far as the script needs it:
//
//   nvram    one file per key; get, set, unset, commit
//   ip       `ip rule` add/del/show kept in a file; `ip route get` answers from the priority-1000
//            and firmware `iif lo` rules the way the kernel would, and `-o link show up` from a list
//   wg       handshakes and peers per interface; genkey and pubkey
//   service  records each call; restart_vpnc brings the slot `vpnc_unit` names up on the key in
//            NVRAM - or drops the call, as the router does when it is busy (ID-214)
//   ping     per interface, and the WAN, on or off; server pings answer with a latency
//   nslookup answers, fails, or records which tunnel the lookup would have left by
//   curl, jq canned PIA answers: a token, a one-server list, an addKey reply
//   logger   appends to a syslog file; `sleep` returns at once unless a test asks for real time
//
// Skipped where no `sh` is on the PATH. The shell's own /usr/bin goes ahead of Windows' so that
// `sort`, `awk` and friends are the Unix ones (ID-216).
import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';

/// Finds a POSIX shell, or null.
String? findShell() {
  for (final candidate in ['sh', 'bash']) {
    try {
      if (Process.runSync(candidate, ['-c', 'exit 0']).exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

const String _nvram = r'''#!/bin/sh
D="$STATE/nv"; mkdir -p "$D"
case "$1" in
  get) cat "$D/$2" 2>/dev/null; exit 0 ;;
  set) k="${2%%=*}"; v="${2#*=}"; printf '%s' "$v" > "$D/$k"; echo "set $2" >> "$STATE/nvram_writes"; exit 0 ;;
  unset) rm -f "$D/$2"; exit 0 ;;
  commit) echo commit >> "$STATE/nvram_writes"; exit 0 ;;
esac
exit 0
''';

const String _logger = r'''#!/bin/sh
shift 2
echo "$*" >> "$STATE/syslog"
''';

// A twentieth of a second, not nothing. The DNS probe waits for its background nslookup with up to
// six `sleep 1`s, and a sleep that returned at once gave the lookup no time at all: on a Linux runner,
// where starting a process is quick, the six "seconds" passed before it had run, and the probe killed
// it. Windows was slow enough to hide that. Every wait in the script is short in these tests anyway.
const String _sleep = r'''#!/bin/sh
[ -f "$STATE/realsleep" ] && exec "$REALSLEEP" "$@"
exec "$REALSLEEP" 0.05
''';

const String _cru = r'''#!/bin/sh
exit 0
''';

// Rules are kept as `<prio>:<TAB><text>`, the way `ip rule show` prints them.
const String _ip = r'''#!/bin/sh
R="$STATE/rules"; touch "$R"
if [ "$1" = "-o" ] && [ "$2" = "link" ]; then
  n=2; while read -r i; do [ -n "$i" ] && { n=$((n + 1)); echo "$n: $i: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420"; }; done < "$STATE/up" 2>/dev/null
  exit 0
fi
if [ "$1" = "route" ] && [ "$2" = "get" ]; then
  dst="$3"
  t="$(sort -s -t: -k1,1n "$R" | awk -v d="$dst" '{for (i = 2; i < NF; i++) if ($i == "to" && $(i + 1) == d) {for (j = 2; j < NF; j++) if ($j == "lookup") {print $(j + 1); exit}}}')"
  if [ -n "$t" ]; then echo "$dst dev wgc$((10 - t)) table $t src 10.0.0.2"; else echo "$dst via 192.0.2.1 dev eth0 src 192.0.2.10"; fi
  exit 0
fi
[ "$1" = "rule" ] || exit 1
op="$2"; shift 2
case "$op" in
  show) sort -s -t: -k1,1n "$R"; exit 0 ;;
esac
from="all"; to=""; iif=""; tbl=""; prio=""; bh=0; sup=""
while [ $# -gt 0 ]; do
  case "$1" in
    from) from="$2"; shift ;; to) to="$2"; shift ;; iif) iif="$2"; shift ;;
    lookup) tbl="$2"; shift ;; priority|pref) prio="$2"; shift ;;
    suppress_prefixlength) sup="$2"; shift ;; blackhole) bh=1 ;;
  esac
  shift
done
text="from $from"
[ -n "$to" ] && text="$text to $to"
[ -n "$iif" ] && text="$text iif $iif"
if [ "$bh" = 1 ]; then text="$text blackhole"; else text="$text lookup $tbl"; fi
[ -n "$sup" ] && text="$text suppress_prefixlength $sup"
case "$op" in
  add) printf '%s:\t%s\n' "$prio" "$text" >> "$R" ;;
  del)
    awk -v p="$prio:" -v f="$from" -v to="$to" -v t="$tbl" '
      !d && (p == ":" || $1 == p) && $3 == f {
        ok = 1
        if (to != "") { ok = 0; for (i = 2; i < NF; i++) if ($i == "to" && $(i + 1) == to) ok = 1 }
        if (ok && t != "") { ok = 0; for (i = 2; i < NF; i++) if ($i == "lookup" && $(i + 1) == t) ok = 1 }
        if (ok) { d = 1; next }
      }
      {print}
      END {exit !d}' "$R" > "$R.new"
    rc=$?; mv "$R.new" "$R"; exit $rc ;;
esac
''';

const String _wg = r'''#!/bin/sh
case "$1" in
  genkey) echo "priv-$$"; exit 0 ;;
  pubkey) read -r k; echo "pub-$k"; exit 0 ;;
esac
[ "$1" = "show" ] || exit 1
if [ "$2" = "interfaces" ]; then tr '\n' ' ' < "$STATE/up" 2>/dev/null; echo; exit 0; fi
IF="$2"
case "$3" in
  latest-handshakes) [ -f "$STATE/peer_$IF" ] && printf '%s\t%s\n' "$(cat "$STATE/peer_$IF")" "$(cat "$STATE/hs_$IF" 2>/dev/null || echo 0)"; exit 0 ;;
  peers) cat "$STATE/peer_$IF" 2>/dev/null; exit 0 ;;
esac
exit 0
''';

// restart_vpnc starts the slot vpnc_unit names, on the peer key now in NVRAM, and it handshakes -
// unless the test has asked for the router to be busy, when it drops the call, as stock does.
const String _service = r'''#!/bin/sh
echo "$*" >> "$STATE/services"
case "$1" in
  restart_vpnc)
    if [ -f "$STATE/skip_restarts" ]; then
      n="$(cat "$STATE/skip_restarts")"
      if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$STATE/skip_restarts"; echo "rc_service: skip the event: restart_vpnc." >> "$STATE/syslog"; exit 0; fi
    fi
    unit="$(cat "$STATE/nv/vpnc_unit" 2>/dev/null)"
    slot="$(tr '<' '\n' < "$STATE/nv/vpnc_clientlist" | awk -F'>' -v u="$unit" 'length($0) == 0 {next} {if (n == u) {print $3; exit} n++}')"
    [ -n "$slot" ] || exit 0
    IF="wgc$slot"
    cat "$STATE/nv/${IF}_ppub" > "$STATE/peer_$IF" 2>/dev/null
    if [ -f "$STATE/no_handshake" ]; then echo 0 > "$STATE/hs_$IF"; else date +%s > "$STATE/hs_$IF"; fi
    grep -qx "$IF" "$STATE/up" 2>/dev/null || echo "$IF" >> "$STATE/up"
    ;;
esac
exit 0
''';

const String _ping = r'''#!/bin/sh
IF=""; last=""
while [ $# -gt 0 ]; do
  case "$1" in -I) IF="$2"; shift ;; -c|-W) shift ;; *) last="$1" ;; esac
  shift
done
if [ -n "$IF" ]; then [ -f "$STATE/ping_$IF" ] && exit 0; exit 1; fi
[ -f "$STATE/wan" ] || exit 1
echo "64 bytes from $last: seq=0 ttl=58 time=12.0 ms"
exit 0
''';

// Records which way the lookup would leave, then answers according to the test.
const String _nslookup = r'''#!/bin/sh
echo "$(ip route get "$2")" >> "$STATE/lookups"
case "$(cat "$STATE/dns" 2>/dev/null)" in
  fail) exit 1 ;;
esac
echo "Name: $1"; echo "Address 1: 192.0.2.80"
exit 0
''';

const String _curl = r'''#!/bin/sh
out=""; fmt=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;; -w) fmt="$2"; shift ;;
    -u|--cacert|--resolve|--data-urlencode|--max-time|--connect-timeout) shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
echo "$url" >> "$STATE/curls"
case "$url" in
  *generateToken*)
    if [ -f "$STATE/pia_rejects" ]; then
      [ -n "$out" ] && echo '{"message":"authentication failed"}' > "$out"; [ -n "$fmt" ] && printf '403 exit=0 connects=1 err='; exit 0
    fi
    [ -n "$out" ] && echo '{"token":"tok123"}' > "$out"; [ -n "$fmt" ] && printf '200 exit=0 connects=1 err='; exit 0 ;;
  *serverlist*) [ -n "$out" ] && echo '{"regions":[]}' > "$out"; exit 0 ;;
  *addKey*) echo '{"status":"OK"}'; exit 0 ;;
esac
exit 0
''';

// Canned answers, chosen by the filter, for the four things the rebuild asks of jq.
const String _jq = r'''#!/bin/sh
IN="$(cat)"
case "$*" in
  *'.token'*) case "$IN" in *tok123*) echo tok123 ;; esac ;;
  *'.servers.wg'*) echo "192.0.2.51 server-51" ;;
  *'.regions[].id'*) echo nz ;;
  *'.status'*) echo OK ;;
  *'@tsv'*) printf '10.0.0.2\tNEWSERVERKEY\t1337\n' ;;
esac
exit 0
''';

/// One fake router and one generated script. Build a fresh one per test.
class WatchdogHarness {
  WatchdogHarness._(this.shell, this.root, this.slot);

  final String shell;
  final Directory root;
  final int slot;

  Directory get state => Directory('${root.path}/state');
  String get iface => 'wgc$slot';

  /// A stock router with [slot] configured, enabled, up and handshaking, a WAN, and a DNS server
  /// that answers. Tests change what they need from there.
  static WatchdogHarness? create({int slot = 1, String? shell}) {
    shell ??= findShell();
    if (shell == null) return null;
    final root = Directory.systemTemp.createTempSync('wd_harness_');
    final h = WatchdogHarness._(shell, root, slot);
    for (final d in ['state/nv', 'bin', 'tmp', 'jffs/cfg-pia-wg', 'etc']) {
      Directory('${root.path}/$d').createSync(recursive: true);
    }
    const stubs = {
      'nvram': _nvram,
      'logger': _logger,
      'sleep': _sleep,
      'cru': _cru,
      'ip': _ip,
      'wg': _wg,
      'service': _service,
      'ping': _ping,
      'nslookup': _nslookup,
      'curl': _curl,
    };
    for (final e in stubs.entries) {
      File('${root.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    File('${root.path}/jffs/cfg-pia-wg/jq').writeAsStringSync(_jq);
    File('${root.path}/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt').writeAsStringSync('cert');
    File('${root.path}/etc/hosts').writeAsStringSync('127.0.0.1 localhost\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod',
          ['+x', ...Directory('${root.path}/bin').listSync().map((f) => f.path), '${root.path}/jffs/cfg-pia-wg/jq']);
    }
    h
      ..set(
          'vpnc_clientlist',
          'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
              '<pia-uk>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg')
      ..set('vpnc_default_wan', '0')
      ..set('vpnc_dev_policy_list', '')
      ..set('${h.iface}_desc', 'pia-nz')
      ..set('${h.iface}_enable', '1')
      ..set('${h.iface}_dns', '9.9.9.9, 149.112.112.112')
      ..set('${h.iface}_ppub', 'OLDSERVERKEY')
      ..set('${h.iface}_wd_primary_ip', '8.8.8.8')
      ..set('${h.iface}_wd_secondary_ip', '1.1.1.1')
      ..set('${h.iface}_wd_check_interval', '5')
      ..set('cfg_pia_wg_user', 'p123456789')
      ..set('cfg_pia_wg_password', 'secret')
      ..tunnelUp(handshakeAgo: 30)
      ..wan(true)
      ..dns('ok');
    return h;
  }

  void dispose() => root.deleteSync(recursive: true);

  void set(String key, String value) => File('${state.path}/nv/$key').writeAsStringSync(value);
  String get(String key) {
    final f = File('${state.path}/nv/$key');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// The interface is up with [peer], last handshake [handshakeAgo] seconds ago (null: never).
  void tunnelUp({int? handshakeAgo, String peer = 'OLDSERVERKEY'}) {
    final up = _lines('up').toSet()..add(iface);
    File('${state.path}/up').writeAsStringSync('${up.join('\n')}\n');
    File('${state.path}/peer_$iface').writeAsStringSync(peer);
    File('${state.path}/hs_$iface').writeAsStringSync('${handshakeAgo == null ? 0 : _now - handshakeAgo}');
  }

  void tunnelDown() {
    final up = _lines('up').where((l) => l != iface);
    File('${state.path}/up').writeAsStringSync('${up.join('\n')}\n');
  }

  void wan(bool on) => _flag('wan', on);
  void dns(String mode) => File('${state.path}/dns').writeAsStringSync(mode);
  void skipRestarts(int n) => File('${state.path}/skip_restarts').writeAsStringSync('$n');

  /// PIA answers the token request with HTTP 403, as it does for a wrong username or password.
  void piaRejects() => _flag('pia_rejects', true);

  /// A restart brings the interface up on the new key, and the server never answers it.
  void neverHandshakes() => _flag('no_handshake', true);

  bool get isUp => _lines('up').contains(iface);
  void realSleep(bool on) => _flag('realsleep', on);
  void backoff(int count, int secondsAgo) =>
      File('${root.path}/tmp/watchdog_backoff_$iface').writeAsStringSync('$count\n${_now - secondsAgo}\n');
  void addRule(String rule) => File('${state.path}/rules').writeAsStringSync('$rule\n', mode: FileMode.append);

  void _flag(String name, bool on) {
    final f = File('${state.path}/$name');
    if (on) {
      f.writeAsStringSync('1');
    } else if (f.existsSync()) {
      f.deleteSync();
    }
  }

  List<String> _lines(String name) {
    final f = File('${state.path}/$name');
    return f.existsSync()
        ? [
            for (final l in f.readAsLinesSync())
              if (l.trim().isNotEmpty) l
          ]
        : [];
  }

  /// The watchdog's own log, without the timestamps.
  List<String> get log {
    final f = File('${root.path}/tmp/watchdog_$iface.log');
    if (!f.existsSync()) return [];
    return [
      for (final l in f.readAsLinesSync())
        if (l.length > 20) l.substring(20)
    ];
  }

  List<String> get services => _lines('services');
  List<String> get curls => _lines('curls');
  List<String> get lookups => _lines('lookups');
  List<String> get rules => [for (final l in _lines('rules')) l.replaceAll('\t', ' ')];
  String get backoffFile {
    final f = File('${root.path}/tmp/watchdog_backoff_$iface');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  String get dnsFailFile {
    final f = File('${root.path}/tmp/watchdog_dnsfail_$iface');
    return f.existsSync() ? f.readAsStringSync().trim() : '';
  }

  /// The script as deployed, with its fixed paths moved into this harness's folder.
  String script([WatchdogConfig? config]) {
    final body = buildWatchdogScript(
      config ??
          WatchdogConfig(
            slotIndex: slot,
            cronIntervalMinutes: 5,
            primaryIp: '8.8.8.8',
            secondaryIp: '1.1.1.1',
            piaUsername: 'p123456789',
            piaPassword: 'secret',
          ),
      firmware: RouterFirmware.stock,
    );
    final r = root.path.replaceAll('\\', '/');
    return body.replaceAll('/tmp/', '$r/tmp/').replaceAll('/jffs/', '$r/jffs/').replaceAll('/etc/', '$r/etc/');
  }

  /// Runs one check in the foreground and waits for it.
  Future<ProcessResult> run({String mode = 'foreground', WatchdogConfig? config}) async {
    final path = '${root.path}/watchdog_$iface.sh';
    File(path).writeAsStringSync(script(config));
    return Process.run(shell, ['-c', _unixToolsFirst, 'sh', path, mode], environment: _env);
  }

  /// Starts a run without waiting, for tests about two watchdogs at once.
  Future<Process> start({String mode = 'foreground'}) async {
    final path = '${root.path}/watchdog_$iface.sh';
    File(path).writeAsStringSync(script());
    return Process.start(shell, ['-c', _unixToolsFirst, 'sh', path, mode], environment: _env);
  }

  Map<String, String> get _env {
    final sep = Platform.isWindows ? ';' : ':';
    return {
      'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state.path,
      'REALSLEEP': 'sleep',
    };
  }

  // The stand-ins first, then the shell's own Unix tools, then everything else (ID-216). The real
  // `sleep` is reached by its path, for the one stand-in that sometimes needs it.
  static const _unixToolsFirst =
      r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; REALSLEEP=/usr/bin/sleep; [ -x "$REALSLEEP" ] || REALSLEEP=/bin/sleep; '
      r'export PATH REALSLEEP; exec sh "$@"';
}
