// live/live_plan.dart - what the live DEVICES run does, and how it reads the answers (ID-457).
//
// The pure half of live/devices_live_test.dart: the steps in order, the e2e.sh command for each,
// whether a run passed, what has to be true before anything is changed, and what puts the router
// back. Nothing here touches a router, so test/unit/live_plan_test.dart covers all of it.
import 'package:cfg_pia_wg/device_assignment.dart';

/// Where e2e.sh lives on the router (CONTEXT.md section 1: the app's own directory).
const String kE2ePath = '/jffs/cfg-pia-wg/e2e.sh';

/// What the run is told through the environment. Nothing is prompted for.
class LiveConfig {
  const LiveConfig({
    required this.router,
    required this.user,
    required this.pass,
    required this.tablet,
    required this.desktop,
    required this.go,
  });

  static const List<String> requiredNames = [
    'CFG_LIVE_ROUTER',
    'CFG_LIVE_USER',
    'CFG_LIVE_PASS',
    'CFG_LIVE_TABLET',
    'CFG_LIVE_DESKTOP',
  ];

  /// The names [requiredNames] that [env] leaves unset or empty.
  static List<String> missing(Map<String, String> env) =>
      [for (final n in requiredNames) if ((env[n] ?? '').trim().isEmpty) n];

  /// Null when any required name is missing. `CFG_LIVE_GO=1` is what lets the run change anything;
  /// without it the run checks the start state, prints the plan and stops.
  static LiveConfig? fromEnv(Map<String, String> env) {
    if (missing(env).isNotEmpty) return null;
    return LiveConfig(
      router: env['CFG_LIVE_ROUTER']!.trim(),
      user: env['CFG_LIVE_USER']!.trim(),
      pass: env['CFG_LIVE_PASS']!,
      tablet: env['CFG_LIVE_TABLET']!.trim(),
      desktop: env['CFG_LIVE_DESKTOP']!.trim(),
      go: env['CFG_LIVE_GO']?.trim() == '1',
    );
  }

  final String router, user, pass, tablet, desktop;
  final bool go;
}

/// One thing the run does to the router, the way the app does it.
sealed class LiveAction {
  const LiveAction();
}

/// DEVICES APPLY moving devices: IP to an index 6, 0 for Internet, null for the default.
class Pin extends LiveAction {
  const Pin(this.changes);
  final Map<String, int?> changes;
  @override
  String toString() => 'pin ${[for (final e in changes.entries) '${e.key} -> ${e.value ?? 'default'}'].join(', ')}';
}

/// DEVICES APPLY changing the default connection: an index 6, or 0 for Internet.
class SetDefault extends LiveAction {
  const SetDefault(this.index);
  final int index;
  @override
  String toString() => 'default -> $index';
}

/// MANAGE DISABLE, pausing a running watchdog first as MANAGE does.
class Disable extends LiveAction {
  const Disable(this.slot);
  final int slot;
  @override
  String toString() => 'disable wgc$slot';
}

/// MANAGE ENABLE, with the slot's stored check targets, resuming a watchdog the run paused.
class Enable extends LiveAction {
  const Enable(this.slot);
  final int slot;
  @override
  String toString() => 'enable wgc$slot';
}

/// One checked test: [setup] before `e2e.sh <id> before`, [actions] between it and `after`, and
/// [cleanup] once the check has passed.
class LiveStep {
  const LiveStep(this.id, {this.setup = const [], required this.actions, required this.expect, this.cleanup = const []});
  final String id;
  final List<LiveAction> setup, actions, cleanup;
  final List<String> expect;
}

/// TESTING.md's DEVICES and default connection tests that need no device in hand, in its order,
/// with its expectations. [t] and [d] are TABLET's and DESKTOP's addresses, [i1] and [i5] the index 6
/// of wgc1 and wgc5.
///
/// Two differ from the sheet. DEV-11b is DEV-11's last step, ENABLE wgc5 and TABLET moves to it
/// without reassigning, given an id of its own so it gets a check. DEF-4 is the router side only:
/// the sheet's DEF-4 is the exit IP on a device, which stays a hand check.
List<LiveStep> buildPlan({required String t, required String d, required int i1, required int i5}) => [
      LiveStep('DEV-4', actions: [Pin({t: i1})], expect: ['rule $t $i1', 'guard $t $i1', 'exit $t wgc1']),
      LiveStep('DEV-5', actions: [Pin({t: i5})], expect: ['rule $t $i5', 'guard $t $i5', 'exit $t wgc5']),
      LiveStep('DEV-6a', actions: [Pin({t: 0})], expect: ['rule $t main', 'noguard $t', 'exit $t WAN']),
      LiveStep('DEV-6b', actions: [Pin({t: i5})], expect: ['rule $t $i5', 'guard $t $i5', 'exit $t wgc5']),
      LiveStep('DEV-7', actions: [Pin({t: null})], expect: ['norule $t', 'noguard $t', 'exit $t WAN']),
      LiveStep('DEV-8', actions: [
        Pin({t: i1, d: i5}),
      ], expect: [
        'rule $t $i1', 'guard $t $i1', 'exit $t wgc1', //
        'rule $d $i5', 'guard $d $i5', 'exit $d wgc5',
      ]),
      LiveStep('DEV-11',
          setup: [const Disable(5)],
          actions: [Pin({t: i5})],
          expect: ['rule $t $i5', 'guard $t $i5', 'down wgc5', 'exit $t BLOCKED']),
      LiveStep('DEV-11b', actions: [const Enable(5)], expect: ['up wgc5', 'rule $t $i5', 'exit $t wgc5']),
      LiveStep('DEF-1',
          setup: [Pin({t: null})],
          actions: [SetDefault(i1)],
          expect: ['default $i1', 'up wgc1', 'up wgc5', 'exit $t wgc1', 'exit $d wgc5']),
      LiveStep('DEF-3', actions: [SetDefault(i5)], expect: ['default $i5', 'up wgc1', 'up wgc5', 'exit $t wgc5']),
      LiveStep('DEF-4',
          actions: [Pin({d: 0})],
          expect: ['rule $d main', 'noguard $d', 'exit $d WAN', 'exit $t wgc5'],
          cleanup: [Pin({d: i5})]),
      LiveStep('DEF-6',
          setup: [SetDefault(i1)],
          actions: [const Disable(1)],
          expect: ['down wgc1', 'noguard $t', 'exit $t WAN'],
          cleanup: [const Enable(1)]),
      LiveStep('DEF-7',
          setup: [Pin({d: i1})],
          actions: [const Disable(1)],
          expect: ['guard $d $i1', 'exit $d BLOCKED'],
          cleanup: [const Enable(1), Pin({d: i5})]),
      LiveStep('DEF-8', actions: [const SetDefault(0)], expect: ['default 0', 'up wgc1', 'up wgc5', 'exit $t WAN']),
    ];

// An expectation is words, addresses and numbers. Anything else would be shell, and is refused
// rather than quoted.
final RegExp _safeWord = RegExp(r'^[A-Za-z0-9 .:_-]+$');

/// The command for one phase of one check: `sh e2e.sh <id> before`, or `after` with each
/// expectation as one quoted argument.
String e2eCommand(String id, String phase, [List<String> expect = const []]) {
  for (final w in [id, phase, ...expect]) {
    if (!_safeWord.hasMatch(w)) throw ArgumentError('not safe to pass to the router shell: "$w"');
  }
  final args = [for (final e in expect) '"$e"'].join(' ');
  return 'sh $kE2ePath $id $phase${args.isEmpty ? '' : ' $args'}';
}

/// Whether e2e.sh's output for [id] ends in its PASS line. Anything else - FAIL, a usage line, no
/// output at all - is not a pass.
bool e2ePassed(String id, String stdout) => stdout.split('\n').map((l) => l.trim()).contains('== $id: PASS');

/// The reservations DEVICES APPLY would create for [changes]: a device moved anywhere but the
/// default that has no reservation gets one, so its pin cannot drift to another device.
Map<String, String> reservationsFor(List<LanDevice> devices, Map<String, int?> changes) => {
      for (final d in devices)
        if (d.ip != null && changes.containsKey(d.ip) && changes[d.ip] != null && !d.reserved) d.mac: d.ip!,
    };

/// What the router reads before the run, as far as the start state goes.
class StartState {
  const StartState({
    required this.stock,
    required this.e2ePresent,
    required this.devices,
    required this.policies,
    required this.defaultIndex,
    required this.i1,
    required this.i5,
    required this.upTunnels,
  });

  final bool stock, e2ePresent;
  final List<LanDevice> devices;
  final List<DevicePolicy> policies;
  final int? defaultIndex;

  /// wgc1's and wgc5's index 6, or null when the slot has no profile.
  final int? i1, i5;

  /// The `wgcN` interfaces that are up.
  final Set<String> upTunnels;
}

/// Every reason the run must not start, each a line beginning STOP. Empty means go.
///
/// TESTING.md's start state for the DEVICES group: stock, wgc1 and wgc5 configured and running,
/// the default connection Internet, and neither device pinned. The run puts the router back to
/// exactly this, so it has to be this to begin with.
List<String> preflightProblems(StartState s, LiveConfig c) {
  final out = <String>[];
  if (!s.stock) out.add('STOP: the router is not stock firmware. DEVICES is stock only.');
  if (!s.e2ePresent) out.add('STOP: $kE2ePath is not on the router. Copy scripts/e2e.sh there first.');
  if (c.tablet == c.desktop) out.add('STOP: CFG_LIVE_TABLET and CFG_LIVE_DESKTOP are the same address.');
  for (final (name, ip) in [('TABLET', c.tablet), ('DESKTOP', c.desktop)]) {
    if (!s.devices.any((d) => d.ip == ip)) out.add('STOP: $name ($ip) is not in the router\'s device list.');
    if (assignedIndexFor(s.policies, ip) != null) out.add('STOP: $name ($ip) is pinned. Set it to default first.');
  }
  for (final (slot, index) in [(1, s.i1), (5, s.i5)]) {
    if (index == null) out.add('STOP: wgc$slot has no VPN profile.');
    if (!s.upTunnels.contains('wgc$slot')) out.add('STOP: wgc$slot is not running.');
  }
  if ((s.defaultIndex ?? 0) != 0) out.add('STOP: the default connection is not Internet.');
  return out;
}

/// What puts TABLET and DESKTOP back to following the default, and the default back to Internet,
/// from what the router holds now. Null when nothing needs doing.
({Map<String, int?> changes, int? newDefault})? restoreFor(
    {required List<DevicePolicy> policies, required int? defaultIndex, required List<String> ips}) {
  final changes = <String, int?>{
    for (final ip in ips)
      if (assignedIndexFor(policies, ip) != null) ip: null,
  };
  final newDefault = (defaultIndex ?? 0) == 0 ? null : 0;
  if (changes.isEmpty && newDefault == null) return null;
  return (changes: changes, newDefault: newDefault);
}
