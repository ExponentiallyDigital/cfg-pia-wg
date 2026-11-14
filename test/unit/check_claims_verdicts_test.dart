// test/unit/check_claims_verdicts_test.dart - check-claims.sh's verdicts name the safe answer exactly
// (ID-580).
//
// CONTEXT.md section 1: a check names what is safe by matching it exactly, and "anything but the bad
// value" is never safe. check-reboot.sh broke that rule and an 8-second leak passed (ID-578). The audit
// of check-claims.sh found five checks with the same shape; their judgements now live in one block of
// small functions, which these run on their own, each with the input that used to pass wrongly.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

/// The verdict functions, as check-claims.sh defines them.
String _verdicts() {
  final s = File('scripts/check-claims.sh').readAsStringSync();
  final m = RegExp(r'^# ---- verdicts[\s\S]*?^# ---- end of verdicts', multiLine: true).firstMatch(s);
  expect(m, isNotNull, reason: 'check-claims.sh has a verdicts block');
  return m!.group(0)!;
}

void main() {
  final shell = findShell();

  Future<String> verdict(String call) async {
    final r = await runSh(shell!, ['-c', '${_verdicts()}\n$call']);
    return '${r.stdout}${r.stderr}'.trim();
  }

  test("DNS-pinned: a pinned device's DNS through its own tunnel, or refused; another tunnel is a leak", () async {
    if (shell == null) return markTestSkipped(_noShell);
    expect(await verdict('dns_verdict 1 "9.9.9.9 from 192.168.1.55 dev wgc1 table 9 uid 0"'), 'ok');
    expect(await verdict('dns_verdict 1 "RTNETLINK answers: Network is unreachable"'), 'ok');
    expect(await verdict('dns_verdict 1 "9.9.9.9 from 192.168.1.55 dev wgc5 table 5 uid 0"'), 'leak',
        reason: 'another tunnel used to count as safe');
    expect(await verdict('dns_verdict 1 "9.9.9.9 from 192.168.1.55 dev wgc10"'), 'leak', reason: 'wgc1 is not wgc10');
    expect(await verdict('dns_verdict gone "9.9.9.9 from 192.168.1.55 dev wgc1"'), 'leak', reason: 'a deleted profile has no tunnel');
  });

  test("TLS: only curl's certificate refusals pass; 35 is a handshake that failed before the certificate", () async {
    if (shell == null) return markTestSkipped(_noShell);
    expect(await verdict('tls_verdict 60; tls_verdict 51'), 'refused\nrefused');
    expect(await verdict('tls_verdict 35; tls_verdict 7; tls_verdict 28'), 'unanswered\nunanswered\nunanswered');
    expect(await verdict('tls_verdict 0; tls_verdict 6'), 'other\nother');
  });

  test("ENABLE-broken: the app's ping must say FAIL; NOROUTE couldn't be aimed, and nothing isn't a failure", () async {
    if (shell == null) return markTestSkipped(_noShell);
    expect(await verdict('enable_broken_verdict FAIL'), 'pass');
    expect(await verdict('enable_broken_verdict NOROUTE'), 'unchecked', reason: 'used to pass');
    expect(await verdict('enable_broken_verdict ""'), 'fail', reason: 'used to pass');
    expect(await verdict('enable_broken_verdict OK'), 'fail');
  });

  test("GUARD-planted: gone only when the table was read and holds its tunnel", () async {
    if (shell == null) return markTestSkipped(_noShell);
    expect(await verdict('planted_verdict "default dev wgc1 scope link" 1 eth0'), 'gone');
    expect(await verdict('planted_verdict "default dev wgc1 scope link\n1.1.1.2 via 203.0.113.1 dev eth0" 1 eth0'), 'still');
    expect(await verdict('planted_verdict "" 1 eth0'), 'unread', reason: 'an unread table used to pass');
    expect(await verdict('planted_verdict "Error: ipv4: FIB table does not exist." 1 eth0'), 'unread');
  });

  test("GUARD-no91: with rule 91 gone, the device must be seen going out, by the WAN or a tunnel", () async {
    if (shell == null) return markTestSkipped(_noShell);
    expect(await verdict('no91_verdict WAN; no91_verdict wgc5'), 'out\nout');
    expect(await verdict('no91_verdict BLOCKED'), 'refused');
    expect(await verdict('no91_verdict "1.1.1.1_from_192.168.1.55_garbage"'), 'other', reason: 'anything else used to pass');
  });

  // ID-585: the block sat after the TLS checks that call tls_verdict, so on the router each said
  // "tls_verdict: not found" and failed (2026-11-14). The functions above pass on their own either way.
  test('each verdict is defined before the script first calls it', () {
    final lines = File('scripts/check-claims.sh').readAsLinesSync();
    final defined = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^(\w+_verdict)\(\)').firstMatch(lines[i]);
      if (m != null) defined[m.group(1)!] = i;
    }
    expect(defined, isNotEmpty);
    for (final MapEntry(key: name, value: at) in defined.entries) {
      final first = lines.indexWhere((l) => l.contains('$name ') && !l.startsWith('$name()') && !l.trimLeft().startsWith('#'));
      expect(first, greaterThan(at), reason: '$name is called on line ${first + 1}, before it is defined on line ${at + 1}');
    }
  });

  test("GUARD-merlin-start (ID-582): exactly the guard's rules back after a tunnel start; one short is missing", () async {
    if (shell == null) return markTestSkipped(_noShell);
    const before = '11409: from 192.168.1.55 prohibit\n9990: from 192.168.1.254 lookup main';
    expect(await verdict('merlin_back_verdict "$before" "$before"'), 'back');
    expect(await verdict('merlin_back_verdict "$before" "9990: from 192.168.1.254 lookup main"'), 'missing');
    expect(await verdict('merlin_back_verdict "$before" ""'), 'missing', reason: 'as the old wgclient-start left them');
    expect(await verdict('merlin_back_verdict "" ""'), 'unchecked', reason: 'nothing to check is not a pass');
  });
}
