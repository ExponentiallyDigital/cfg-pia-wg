// test/stock_router_model.dart - a stock ASUS router that behaves the way it was measured to (ID-206).
//
// The fake SSH clients elsewhere answer each command with canned text, so they prove the app SENDS
// the right commands. This one keeps state - NVRAM, `ip rule`, which tunnels are running - and
// changes it the way the firmware does, so a test can prove what the commands DO: where each
// device's traffic leaves after an assignment, a default change, a DISABLE or a reboot.
//
// Every behaviour below is one measured on hardware (ARCHITECTURE.md 6.8). A behaviour nobody has
// measured is not in here, and the model cannot find a fault that depends on one:
//
//   restart_vpnc_dev_policy  adds a priority-100 rule for EVERY enabled record whose tunnel is
//                            running, every time, duplicates and all, and never removes one (6.8.11,
//                            ID-183). An Internet pin gets `lookup main`.
//   stop_vpnc                stops the profile `vpnc_unit` names, and its per-device rules go with it.
//   restart_vpnc             starts the profile `vpnc_unit` names, whether or not it is switched on
//                            (ID-172), puts back its per-device rules, and installs the priority-10000
//                            pair when it is the default connection (6.8.8).
//   restart_default_wan      removes the 10000 pair, resets `vpnc_default_wan` to 0, and stops the
//                            tunnel that was the default. On 2026-09-08, with one tunnel, that was
//                            every tunnel; on 2026-09-24 the other running tunnel kept answering
//                            straight after it, so the model stops only the default's.
//   a busy router            a service call made while `rc_service` is set is dropped (ID-214).
//   a reboot                 clears every rule the kernel did not make, starts the tunnels that are
//                            switched on, and the boot hook puts the guard back (ID-213).
//
// The fail-closed guard is modelled from kGuardScript's rules, not run: its own tests
// (fail_closed_guard_test.dart) run the real script.
import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:cfg_pia_wg/fail_closed_guard.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/router_watchdog.dart' show writtenByteCount;

import 'watchdog_test_utils.dart';

/// Where a device's traffic leaves: `WAN`, `wgcN`, or [kBlocked].
typedef Exit = String;

const Exit kWan = 'WAN';
const Exit kBlocked = 'BLOCKED';

/// A tunnel's state. [expired] is up and carrying nothing: the server has stopped answering.
enum Tunnel { down, up, expired }

class Rule {
  Rule(this.priority, this.text);
  final int priority;
  final String text;

  List<String> get words => text.split(' ');
  String? after(String word) {
    final i = words.indexOf(word);
    return i < 0 || i + 1 >= words.length ? null : words[i + 1];
  }

  @override
  String toString() => '$priority:\t$text';
}

class StockRouterModel {
  StockRouterModel({required this.devices}) {
    nvram.addAll({
      'vpnc_clientlist': 'pia-nz>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
          '<pia-uk>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg',
      'vpnc_dev_policy_list': '',
      'vpnc_default_wan': '0',
      'vpnc_unit': '0',
      'wgc1_enable': '1',
      'wgc5_enable': '1',
      'wgc1_desc': 'pia-nz',
      'wgc5_desc': 'pia-uk',
      'dhcp_staticlist': [for (final d in devices) '<AA:BB:CC:DD:EE:${d.split('.').last}>$d>>'].join(),
      'rc_service': '',
      'rc_service_pid': '',
    });
    for (final p in profiles) {
      tunnels[p.slot!] = Tunnel.up;
    }
  }

  /// The devices on the LAN, by address. Each has a reservation, so no APPLY needs to create one.
  final List<String> devices;

  final Map<String, String> nvram = {};
  final List<Rule> rules = [];
  final Map<int, Tunnel> tunnels = {};
  final List<String> serviceLog = [];

  /// The next [n] service calls are dropped, as a busy router drops them.
  int dropServices = 0;

  bool guardInstalled = false;

  List<VpncRecord> get profiles => parseVpncClientlist(nvram['vpnc_clientlist'] ?? '');

  VpncRecord? profileForTable(int table) {
    for (final p in profiles) {
      if (p.vpncStateIndex == table) return p;
    }
    return null;
  }

  RecordingSSHClient client() => RecordingSSHClient(responder: respond);

  // ── The router ─────────────────────────────────────────────────────────────────────

  String respond(String cmd) {
    // The app's batched reads: every part answered in turn, separators and all.
    if (cmd.startsWith('echo "')) {
      return cmd
          .split('; ')
          .map((part) => part.startsWith('echo "') ? '${part.substring(6, part.length - 1)}\n' : '${respond(part)}\n')
          .join();
    }
    if (cmd.startsWith('logger ') || cmd.contains('; logger ')) return '';
    if (cmd == 'nvram commit') return '';
    if (cmd.startsWith('nvram get ')) return nvram[cmd.substring(10).trim()] ?? '';
    if (cmd.startsWith('nvram set ')) {
      final kv = cmd.substring(10);
      final eq = kv.indexOf('=');
      nvram[kv.substring(0, eq)] = _unquote(kv.substring(eq + 1));
      return '';
    }
    if (cmd.startsWith('nvram unset ')) {
      nvram.remove(cmd.substring(12).trim());
      return '';
    }
    if (cmd.startsWith('printf ') && cmd.contains('rc_service')) {
      // kRcServiceCommand. No process is ever alive in the model, so a marker is always a ghost.
      final s = nvram['rc_service'] ?? '';
      return '$s@@${nvram['rc_service_pid'] ?? ''}@@dead';
    }
    if (cmd.startsWith('service ')) {
      service(cmd.substring(8).trim());
      return '';
    }
    if (cmd == kIpRuleCommand) return rules.map((r) => '$r').join('\n');
    if (cmd.startsWith('ip rule del ')) {
      _ruleDel(cmd.substring(12));
      return '';
    }
    if (cmd == kUpInterfacesCommand) {
      var n = 2;
      return [
        for (final e in tunnels.entries)
          if (e.value != Tunnel.down) '${++n}: wgc${e.key}: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420',
      ].join('\n');
    }
    if (cmd.startsWith('wg show wgc') && cmd.contains('latest-handshakes')) {
      final slot = int.parse(RegExp(r'wgc(\d)').firstMatch(cmd)!.group(1)!);
      return tunnels[slot] == Tunnel.up ? '$now' : '0';
    }
    if (cmd == 'date +%s') return '$now';
    if (cmd == "cat '$kGuardScriptPath' 2>/dev/null || true") return guardInstalled ? kGuardScript : '';
    if (cmd.startsWith("wc -c < '$kGuardScriptPath'")) return '${writtenByteCount(kGuardScript)}';
    if (cmd.contains(kGuardScriptPath) && cmd.contains('<<')) {
      guardInstalled = true;
      return '';
    }
    if (cmd == "'$kGuardScriptPath'") return guard();
    if (cmd == "[ -x '$kGuardScriptPath' ] && '$kGuardScriptPath' clear") {
      rules.removeWhere((r) => r.priority == 90 || r.priority == 91);
      return '';
    }
    return '';
  }

  final int now = 1790000000;

  static String _unquote(String v) {
    if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
      return v.substring(1, v.length - 1).replaceAll("'\\''", "'");
    }
    // `nvram set rc_service=""`, as RouterServiceQueue clears a ghost.
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) return v.substring(1, v.length - 1);
    return v;
  }

  void _ruleDel(String args) {
    final w = args.split(' ');
    String? arg(String k) {
      final i = w.indexOf(k);
      return i < 0 || i + 1 >= w.length ? null : w[i + 1];
    }

    final prio = int.tryParse(arg('priority') ?? arg('pref') ?? '');
    final from = arg('from');
    final table = arg('lookup');
    // The kernel removes the FIRST rule that matches everything named.
    final i = rules.indexWhere((r) =>
        (prio == null || r.priority == prio) &&
        (from == null || r.after('from') == from) &&
        (table == null || r.after('lookup') == table));
    if (i >= 0) rules.removeAt(i);
  }

  void _addRule(int priority, String text) {
    // `ip rule add` goes in after every rule of the same priority.
    final at = rules.indexWhere((r) => r.priority > priority);
    rules.insert(at < 0 ? rules.length : at, Rule(priority, text));
  }

  VpncRecord? get _unitProfile {
    final unit = int.tryParse(nvram['vpnc_unit'] ?? '');
    final p = profiles;
    return unit == null || unit < 0 || unit >= p.length ? null : p[unit];
  }

  void service(String name) {
    if ((nvram['rc_service'] ?? '').isNotEmpty || dropServices > 0) {
      if (dropServices > 0) dropServices--;
      serviceLog.add('skipped $name');
      return;
    }
    serviceLog.add(name);
    switch (name) {
      case 'restart_vpnc_dev_policy':
        for (final p in parseDevicePolicyList(nvram['vpnc_dev_policy_list'] ?? '')) {
          if (!p.enabled || p.ip.isEmpty || p.vpncIndex == null) continue;
          if (p.vpncIndex == 0) {
            _addRule(100, 'from ${p.ip} lookup main');
            continue;
          }
          final profile = profileForTable(p.vpncIndex!);
          if (profile != null && tunnels[profile.slot] != Tunnel.down) {
            _addRule(100, 'from ${p.ip} lookup ${p.vpncIndex}');
          }
        }
      case 'stop_vpnc':
        final p = _unitProfile;
        if (p != null) _stop(p);
      case 'restart_vpnc':
        final p = _unitProfile;
        if (p != null) _start(p);
      case 'restart_default_wan':
        final table = int.tryParse(nvram['vpnc_default_wan'] ?? '') ?? 0;
        rules.removeWhere((r) => r.priority == 10000);
        nvram['vpnc_default_wan'] = '0';
        final p = table == 0 ? null : profileForTable(table);
        if (p != null) _stop(p);
      default:
        break;
    }
  }

  void _stop(VpncRecord p) {
    tunnels[p.slot!] = Tunnel.down;
    rules.removeWhere((r) => r.priority == 100 && r.after('lookup') == '${p.vpncStateIndex}');
  }

  void _start(VpncRecord p) {
    tunnels[p.slot!] = Tunnel.up;
    final table = '${p.vpncStateIndex}';
    for (final d in parseDevicePolicyList(nvram['vpnc_dev_policy_list'] ?? '')) {
      if (!d.enabled || d.vpncIndex != p.vpncStateIndex) continue;
      if (!rules.any((r) => r.priority == 100 && r.after('from') == d.ip && r.after('lookup') == table)) {
        _addRule(100, 'from ${d.ip} lookup $table');
      }
    }
    if (nvram['vpnc_default_wan'] == table) {
      rules.removeWhere((r) => r.priority == 10000);
      _addRule(10000, 'from all iif br0 lookup $table');
      _addRule(10000, 'from all iif br1 lookup $table');
    }
  }

  /// kGuardScript, as rules: priorities 90 and 91 for every enabled record naming a WireGuard
  /// table, and nothing else at either.
  String guard() {
    final tables = {
      for (final p in profiles)
        if (p.protocol == 'WireGuard' && p.vpncStateIndex != null) p.vpncStateIndex
    };
    final want = <String, int>{
      for (final d in parseDevicePolicyList(nvram['vpnc_dev_policy_list'] ?? ''))
        if (d.enabled && d.ip.isNotEmpty && tables.contains(d.vpncIndex)) d.ip: d.vpncIndex!,
    };
    rules.removeWhere((r) => r.priority == 90 || r.priority == 91);
    want.forEach((ip, t) {
      _addRule(91, 'from $ip blackhole');
      _addRule(90, 'from $ip lookup $t suppress_prefixlength 0');
    });
    return 'guarded ${want.length}';
  }

  // ── Things that happen to the router, not from the app ────────────────────────────

  /// The server stops answering: the interface stays up and carries nothing.
  void expire(int slot) => tunnels[slot] = Tunnel.expired;

  /// A watchdog rebuild: the firmware restarts the tunnel on a new key, then the guard runs, as it
  /// does at the start of every watchdog run.
  void rebuild(int slot) {
    nvram['vpnc_unit'] = '${profiles.indexWhere((p) => p.slot == slot)}';
    service('restart_vpnc');
    if (guardInstalled) guard();
  }

  /// A reboot, then the boot hook.
  void reboot() {
    rules.clear();
    nvram['rc_service'] = '';
    for (final p in profiles) {
      tunnels[p.slot!] = Tunnel.down;
    }
    for (final p in profiles) {
      if (p.active) _start(p);
    }
    service('restart_vpnc_dev_policy');
    if (guardInstalled) guard();
  }

  // ── Where traffic goes ─────────────────────────────────────────────────────────────

  Exit _viaTable(int table, {required bool suppressDefault}) {
    final p = profileForTable(table);
    final t = p == null ? Tunnel.down : tunnels[p.slot] ?? Tunnel.down;
    if (t == Tunnel.up) return 'wgc${p!.slot}';
    if (t == Tunnel.expired) return kBlocked;
    // A stopped tunnel's table holds a copy of main, WAN default route and all (6.8.10).
    return suppressDefault ? '' : kWan;
  }

  /// Where [ip]'s internet traffic leaves, walking `ip rule` top down as the kernel does.
  Exit actualExit(String ip) {
    for (final r in rules) {
      // The device's own rules, and the default connection's rule for the LAN bridge it is on.
      final from = r.after('from');
      if (from != ip && !(from == 'all' && r.after('iif') == 'br0')) continue;
      if (r.words.contains('blackhole')) return kBlocked;
      final table = r.after('lookup');
      if (table == 'main') return kWan;
      final n = int.tryParse(table ?? '');
      if (n == null) continue;
      final out = _viaTable(n, suppressDefault: r.words.contains('suppress_prefixlength'));
      if (out.isNotEmpty) return out;
    }
    return kWan;
  }

  /// Where [ip]'s traffic SHOULD leave, or null where the app makes no promise.
  ///
  /// Pinned to a tunnel: that tunnel, or nowhere. Pinned to Internet: the WAN. Following the
  /// default: the default while its tunnel runs; when it does not, the device is not pinned and
  /// the guard does not cover it (README "What the guard does not cover").
  Exit? expectedExit(String ip) {
    DevicePolicy? rec;
    for (final d in parseDevicePolicyList(nvram['vpnc_dev_policy_list'] ?? '')) {
      if (d.ip == ip) rec = d;
    }
    if (rec != null && rec.enabled) {
      if (rec.vpncIndex == 0) return kWan;
      final p = profileForTable(rec.vpncIndex ?? -1);
      if (p == null) return null;
      return tunnels[p.slot] == Tunnel.up ? 'wgc${p.slot}' : kBlocked;
    }
    final def = int.tryParse(nvram['vpnc_default_wan'] ?? '') ?? 0;
    if (def == 0) return kWan;
    final p = profileForTable(def);
    return p != null && tunnels[p.slot] == Tunnel.up ? 'wgc${p.slot}' : null;
  }

  /// Every way the router's routing disagrees with its settings. Empty is correct.
  List<String> faults() => [
        for (final ip in devices)
          if (expectedExit(ip) case final want? when actualExit(ip) != want)
            '$ip should leave via $want but leaves via ${actualExit(ip)}',
        for (final p in profiles)
          if (p.active && tunnels[p.slot] == Tunnel.down)
            'wgc${p.slot} is switched on but not running'
          else if (!p.active && tunnels[p.slot] != Tunnel.down)
            'wgc${p.slot} is switched off but running',
      ];

  String describe() => 'rules:\n${rules.join('\n')}\ntunnels: $tunnels\n'
      'policy: ${nvram['vpnc_dev_policy_list']}\ndefault: ${nvram['vpnc_default_wan']}\n'
      'services: ${serviceLog.join(', ')}';
}
