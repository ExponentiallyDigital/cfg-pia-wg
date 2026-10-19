// The live DEVICES run's plan and the way it reads e2e.sh (ID-457). The run itself needs a router;
// everything it decides is here.
import 'dart:io';

import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../live/live_plan.dart';

const _t = '192.168.1.20', _d = '192.168.1.30';
const _i1 = 9, _i5 = 5;

const _env = {
  'CFG_LIVE_ROUTER': '192.168.1.1:22',
  'CFG_LIVE_USER': 'admin',
  'CFG_LIVE_PASS': 'pw',
  'CFG_LIVE_TABLET': _t,
  'CFG_LIVE_DESKTOP': _d,
};

final _config = LiveConfig.fromEnv(_env)!;

StartState _start({
  bool stock = true,
  bool e2e = true,
  String policies = '',
  int? defaultIndex,
  int? i1 = _i1,
  int? i5 = _i5,
  Set<String> up = const {'wgc1', 'wgc5'},
}) =>
    StartState(
      stock: stock,
      e2ePresent: e2e,
      devices: [LanDevice(mac: 'AA:BB:CC:00:00:20', ip: _t), LanDevice(mac: 'AA:BB:CC:00:00:30', ip: _d, reserved: true)],
      policies: parseDevicePolicyList(policies),
      defaultIndex: defaultIndex,
      i1: i1,
      i5: i5,
      upTunnels: up,
    );

/// TESTING.md's `e2e.sh <id> after` expectations, with the sheet's shell variables filled in.
Map<String, List<String>> _sheetExpectations() {
  final out = <String, List<String>>{};
  final line = RegExp(r'e2e\.sh ([A-Z]{3}-\d+[a-z]?) after ((?:"[^"]*" ?)+)');
  for (final m in line.allMatches(File('TESTING.md').readAsStringSync())) {
    out[m.group(1)!] = [
      for (final q in RegExp(r'"([^"]*)"').allMatches(m.group(2)!))
        q.group(1)!.replaceAll(r'$TMAC', 'unused').replaceAll(r'$T', _t).replaceAll(r'$D', _d).replaceAll(r'$I1', '$_i1').replaceAll(r'$I5', '$_i5'),
    ];
  }
  return out;
}

void main() {
  group('the configuration', () {
    test('names every variable that is missing, and nothing else', () {
      expect(LiveConfig.missing(const {}), LiveConfig.requiredNames);
      expect(LiveConfig.missing({..._env, 'CFG_LIVE_PASS': ' '}), ['CFG_LIVE_PASS']);
      expect(LiveConfig.fromEnv({..._env}..remove('CFG_LIVE_DESKTOP')), isNull);
    });

    test('changes nothing unless CFG_LIVE_GO is exactly 1', () {
      expect(_config.go, isFalse);
      expect(LiveConfig.fromEnv({..._env, 'CFG_LIVE_GO': 'yes'})!.go, isFalse);
      expect(LiveConfig.fromEnv({..._env, 'CFG_LIVE_GO': '1'})!.go, isTrue);
    });
  });

  group('the plan', () {
    final plan = buildPlan(t: _t, d: _d, i1: _i1, i5: _i5);

    test('runs the sheet\'s tests in the sheet\'s order', () {
      expect([for (final s in plan) s.id],
          ['DEV-4', 'DEV-5', 'DEV-6a', 'DEV-6b', 'DEV-7', 'DEV-8', 'DEV-11', 'DEV-11b', 'DEF-1', 'DEF-3', 'DEF-4', 'DEF-6', 'DEF-7', 'DEF-8']);
    });

    test('checks exactly what TESTING.md checks, for every test the sheet has', () {
      final sheet = _sheetExpectations();
      for (final s in plan) {
        if (s.id == 'DEV-11b' || s.id == 'DEF-4') continue; // the run's own; the sheet checks these by hand
        expect(sheet[s.id], s.expect, reason: '${s.id} has drifted from TESTING.md');
      }
    });

    test('ENABLEs every slot it DISABLEs, before the next step', () {
      final down = <int>{};
      for (final s in plan) {
        for (final a in [...s.setup, ...s.actions, ...s.cleanup]) {
          if (a is Disable) down.add(a.slot);
          if (a is Enable) down.remove(a.slot);
        }
        if (s.id != 'DEV-11') expect(down, isEmpty, reason: '${s.id} leaves a slot down');
      }
    });

    test('ends with the default on Internet', () {
      expect(plan.last.actions, [isA<SetDefault>().having((a) => a.index, 'index', 0)]);
    });
  });

  group('e2e.sh', () {
    test('before and after, each expectation one argument', () {
      expect(e2eCommand('DEV-4', 'before'), 'sh /jffs/cfg-pia-wg/e2e.sh DEV-4 before');
      expect(e2eCommand('DEV-4', 'after', ['rule $_t 9', 'exit $_t wgc1']),
          'sh /jffs/cfg-pia-wg/e2e.sh DEV-4 after "rule $_t 9" "exit $_t wgc1"');
    });

    test('refuses anything that would be shell', () {
      for (final bad in [r'exit $(reboot) WAN', 'rule 1;reboot', 'a"b', 'x`y`']) {
        expect(() => e2eCommand('DEV-4', 'after', [bad]), throwsArgumentError, reason: bad);
      }
    });

    test('a pass is its own PASS line, and nothing else', () {
      expect(e2ePassed('DEV-4', 'changes...\n== DEV-4: PASS\n'), isTrue);
      expect(e2ePassed('DEV-4', '== DEV-4: FAIL (1)'), isFalse);
      expect(e2ePassed('DEV-4', '== DEV-5: PASS'), isFalse);
      expect(e2ePassed('DEV-6', '== DEV-6a: PASS'), isFalse);
      expect(e2ePassed('DEV-4', 'usage: sh e2e.sh <test-id> before|after'), isFalse);
      expect(e2ePassed('DEV-4', ''), isFalse);
    });
  });

  group('reservations, as APPLY makes them', () {
    final devices = [
      LanDevice(mac: 'M1', ip: _t),
      LanDevice(mac: 'M2', ip: _d, reserved: true),
      LanDevice(mac: 'M3', ip: '192.168.1.40'),
    ];

    test('only for a device moved off the default that has none', () {
      expect(reservationsFor(devices, {_t: _i1, _d: _i5}), {'M1': _t});
      expect(reservationsFor(devices, {_t: 0}), {'M1': _t});
      expect(reservationsFor(devices, {_t: null}), isEmpty);
      expect(reservationsFor(devices, {}), isEmpty);
    });
  });

  group('the start state', () {
    test('the sheet\'s start state goes', () {
      expect(preflightProblems(_start(), _config), isEmpty);
      expect(preflightProblems(_start(defaultIndex: 0, policies: '0>$_t>>0>'), _config), isEmpty);
    });

    test('anything else stops, saying why', () {
      final cases = <String, StartState>{
        'not stock': _start(stock: false),
        'is not on the router': _start(e2e: false),
        'TABLET ($_t) is pinned': _start(policies: '1>$_t>>0>'),
        'DESKTOP ($_d) is pinned': _start(policies: '1>$_d>>9>'),
        'wgc1 has no VPN profile': _start(i1: null),
        'wgc5 is not running': _start(up: {'wgc1'}),
        'not Internet': _start(defaultIndex: _i1),
      };
      cases.forEach((why, s) {
        final stops = preflightProblems(s, _config);
        expect(stops, [allOf(startsWith('STOP: '), contains(why))], reason: why);
      });
    });

    test('a device the router does not list stops', () {
      final c = LiveConfig.fromEnv({..._env, 'CFG_LIVE_DESKTOP': '192.168.1.99'})!;
      expect(preflightProblems(_start(), c), [contains('DESKTOP (192.168.1.99) is not in')]);
    });

    test('the same address twice stops', () {
      final c = LiveConfig.fromEnv({..._env, 'CFG_LIVE_DESKTOP': _t})!;
      expect(preflightProblems(_start(), c), contains(contains('are the same address')));
    });
  });

  group('putting the router back', () {
    test('nothing to do in the start state', () {
      expect(restoreFor(policies: parseDevicePolicyList('0>$_t>>0>'), defaultIndex: 0, ips: [_t, _d]), isNull);
      expect(restoreFor(policies: const [], defaultIndex: null, ips: [_t, _d]), isNull);
    });

    test('every pinned device back to the default, Internet pin included, and the default to Internet', () {
      final undo = restoreFor(policies: parseDevicePolicyList('1>$_t>>0><1>$_d>>5><1>192.168.1.40>>9>'), defaultIndex: _i5, ips: [_t, _d])!;
      expect(undo.changes, {_t: null, _d: null});
      expect(undo.newDefault, 0);
    });
  });
}
