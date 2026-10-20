// The live DEVICES run's plan and the way it reads e2e.sh (ID-457). The run itself needs a router;
// everything it decides is here.
import 'dart:io';

import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../live/live_plan.dart';

const _t = '192.168.1.20', _d = '192.168.1.30';
const _i1 = 9, _i5 = 5;
const _tmac = 'AA:BB:CC:00:00:20';
const _runOwn = {'DEV-11b', 'DEF-4', 'DEV-18', 'DEV-18b', 'DEV-19', 'DEV-19b', 'DEV-20', 'DEV-20b'};

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
  bool clear = true,
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
      timeSchedulingClear: clear,
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
    final plan = buildPlan(t: _t, d: _d, i1: _i1, i5: _i5, tmac: _tmac, tabletName: 'Tablet');

    test('runs the sheet\'s tests in the sheet\'s order', () {
      expect([for (final s in plan) s.id],
          ['DEV-4', 'DEV-5', 'DEV-6a', 'DEV-6b', 'DEV-7', 'DEV-8', 'DEV-11', 'DEV-11b', 'DEF-1', 'DEF-3', 'DEF-4', 'DEF-6', 'DEF-7', 'DEF-8', //
           'DEV-18', 'DEV-18b', 'DEV-19', 'DEV-19b', 'DEV-20', 'DEV-20b']);
    });

    test('checks exactly what TESTING.md checks, for every test the sheet has', () {
      final sheet = _sheetExpectations();
      for (final s in plan) {
        if (_runOwn.contains(s.id)) continue; // the sheet checks these by hand, with no e2e.sh line
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

    test('DEF-8 puts the default back on Internet', () {
      expect(plan.firstWhere((s) => s.id == 'DEF-8').actions, [isA<SetDefault>().having((a) => a.index, 'index', 0)]);
    });

    test('TABLET gets its name back, and is enabled again, every time it is disabled', () {
      expect(plan.firstWhere((s) => s.id == 'DEV-18b').cleanup, [isA<Rename>().having((a) => a.name, 'name', 'Tablet')]);
      expect(buildPlan(t: _t, d: _d, i1: _i1, i5: _i5, tmac: _tmac).firstWhere((s) => s.id == 'DEV-18b').cleanup, isEmpty);
      var blocked = false;
      for (final s in plan) {
        for (final a in [...s.setup, ...s.actions, ...s.cleanup].whereType<Block>()) {
          blocked = a.on;
        }
        if (s.id.endsWith('b')) expect(blocked, isFalse, reason: '${s.id} leaves TABLET disabled');
      }
      expect(blocked, isFalse);
    });

    test('DEV-20 checks the pin is kept while TABLET is disabled', () {
      final s = plan.firstWhere((s) => s.id == 'DEV-20');
      expect(s.checks.whereType<PinKept>().single.index, _i1);
      expect(s.expect, ['rule $_t $_i1', 'guard $_t $_i1']);
    });
  });

  group('e2e.sh', () {
    test('before and after, each expectation one argument', () {
      expect(e2eCommand('DEV-4', 'before'), '/bin/sh /jffs/cfg-pia-wg/e2e.sh DEV-4 before');
      expect(e2eCommand('DEV-4', 'after', ['rule $_t 9', 'exit $_t wgc1']),
          '/bin/sh /jffs/cfg-pia-wg/e2e.sh DEV-4 after "rule $_t 9" "exit $_t wgc1"');
    });

    test('refuses anything that would be shell', () {
      for (final bad in [r'exit $(reboot) WAN', 'rule 1;reboot', 'a"b', 'x`y`']) {
        expect(() => e2eCommand('DEV-4', 'after', [bad]), throwsArgumentError, reason: bad);
      }
    });

    test('the after check is retried until it passes, and no longer', () async {
      final outs = ['== DEV-4: FAIL (1)', '== DEV-4: FAIL (1)', '== DEV-4: PASS', '== DEV-4: FAIL (1)'];
      var calls = 0;
      final waits = <Duration>[];
      final (out, tries) = await settle(() async => outs[calls++], (o) => e2ePassed('DEV-4', o),
          wait: (d) async => waits.add(d));
      expect((out, tries, calls), ('== DEV-4: PASS', 3, 3));
      expect(waits, [kSettleGap, kSettleGap]);
    });

    test('a check that never passes gives up after its tries, with the last output', () async {
      var calls = 0;
      final waits = <Duration>[];
      final (out, tries) = await settle(() async => 'FAIL ${++calls}', (o) => false,
          tries: 4, wait: (d) async => waits.add(d));
      expect((out, tries, calls, waits.length), ('FAIL 4', 4, 4, 3));
    });

    test('a before counts only when it took its snapshot', () {
      expect(e2eSnapshotTaken('DEV-4', 'DEV-4: snapshot taken. Do the step, then: sh e2e.sh DEV-4 after'), isTrue);
      expect(e2eSnapshotTaken('DEV-4', 'Error: Address /jffs/cfg-pia-wg/e2e.sh is invalid'), isFalse);
      expect(e2eSnapshotTaken('DEV-4', ''), isFalse);
      expect(e2eSnapshotTaken('DEV-4', 'DEV-5: snapshot taken.'), isFalse);
      expect(e2eSnapshotTaken('DEV-6', 'DEV-6a: snapshot taken.'), isFalse);
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
        'Time Scheduling is on': _start(clear: false),
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

  group('the router checks', () {
    test('a name: its record, with that name; or no record at all', () {
      const list = 'Phone>AA:BB:CC:00:00:40>0>2>><DN-Test Name>aa:bb:cc:00:00:20>0>21>>';
      expect(nameProblems(list, _tmac, 'DN-Test Name'), isEmpty);
      expect(nameProblems(list, _tmac, 'Tablet'), [contains('"DN-Test Name", not "Tablet"')]);
      expect(nameProblems(list, _tmac, ''), [contains('still has a record')]);
      expect(nameProblems('Phone>AA:BB:CC:00:00:40>0>2>>', _tmac, ''), isEmpty);
      expect(nameProblems('', _tmac, 'DN-Test Name'), [contains('no record')]);
    });

    final blockedKeys = ['MULTIFILTER_ALL=1', 'MULTIFILTER_BLOCK_ALL=0', 'MULTIFILTER_ENABLE=2', 'MULTIFILTER_MAC=$_tmac'].join('\n');
    // ARCHITECTURE's rules, measured on stock, with the MAC filled in. Lines made up here once
    // passed a check that wanted a DROP in FORWARD, which stock never writes (2026-10-20).
    final measured = RegExp(r'```text\n(-A FORWARD -i br0[^`]*)```').firstMatch(File('ARCHITECTURE.md').readAsStringSync())!;
    final dropLines = measured.group(1)!.trim().split('\n').map((l) => l.replaceAll('<mac>', _tmac.toLowerCase())).toList();
    final drops = dropLines.join('\n');

    test('the rules are ARCHITECTURE\'s three, FORWARD jumping and the other two dropping', () {
      expect(dropLines, hasLength(3));
      expect(dropLines.first, endsWith('-j PControls'));
      // A FORWARD rule that doesn't jump to PControls isn't the block.
      final noJump = [dropLines.first.replaceFirst('-j PControls', '-j ACCEPT'), ...dropLines.skip(1)].join('\n');
      expect(blockProblems(blockedKeys, noJump, _tmac, true), [contains('-A FORWARD ... -j PControls')]);
    });

    test('disabled: the four keys as the sheet has them, and a DROP in each of the three chains', () {
      expect(blockProblems(blockedKeys, drops, _tmac, true), isEmpty);
      expect(blockProblems(blockedKeys.replaceFirst('ENABLE=2', 'ENABLE=1'), drops, _tmac, true), [contains('not 2')]);
      expect(blockProblems(blockedKeys, dropLines.take(2).join('\n'), _tmac, true), [contains('-A WGNPControls ... -j DROP')]);
      expect(blockProblems(blockedKeys.replaceFirst('ALL=1', 'ALL=0'), drops, _tmac, true), [contains('not 1')]);
      final second = ['MULTIFILTER_ALL=1', 'MULTIFILTER_BLOCK_ALL=0', 'MULTIFILTER_ENABLE=0>2', 'MULTIFILTER_MAC=11:22:33:44:55:66>$_tmac'];
      expect(blockProblems(second.join('\n'), drops, _tmac, true), isEmpty, reason: 'the second entry');
    });

    test('enabled again: Time Scheduling off and empty, and no rule left', () {
      final clear = ['MULTIFILTER_ALL=0', 'MULTIFILTER_BLOCK_ALL=0', 'MULTIFILTER_ENABLE=', 'MULTIFILTER_MAC='];
      expect(blockProblems(clear.join('\n'), '', _tmac, false), isEmpty);
      expect(blockProblems(blockedKeys, drops, _tmac, false), hasLength(3));
    });

    test('a pin kept, and a step with no service call', () {
      expect(pinKeptProblems('1>$_t>>$_i1>', _t, _i1), isEmpty);
      expect(pinKeptProblems('0>$_t>>$_i1>', _t, _i1), [contains('no longer pinned')]);
      expect(serviceCallProblems(7, 7), isEmpty);
      expect(serviceCallProblems(7, 8), [contains('1 service call')]);
    });
  });

  group('watchdogs at the end', () {
    test('the same as at the start is nothing to report', () {
      expect(watchdogProblems(atStart: {1, 5}, now: {5, 1}), isEmpty);
    });

    test('one paused and never resumed is named, and so is one left scheduled', () {
      expect(watchdogProblems(atStart: {1, 5}, now: {1}), ["wgc5's watchdog was scheduled at the start and is not now."]);
      expect(watchdogProblems(atStart: {}, now: {3}), ["wgc3's watchdog is scheduled now and was not at the start."]);
    });
  });

  group('putting the router back', () {
    test('TABLET enabled again if disabled, and its own name back if it has another', () {
      expect(deviceRestoreFor(blocked: false, nameNow: 'Tablet', nameAtStart: 'Tablet'), (unblock: null, rename: null));
      expect(deviceRestoreFor(blocked: true, nameNow: 'DN-Test Name', nameAtStart: 'Tablet'), (unblock: true, rename: 'Tablet'));
      expect(deviceRestoreFor(blocked: false, nameNow: 'DN-Test Name', nameAtStart: ''), (unblock: null, rename: ''));
    });

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
