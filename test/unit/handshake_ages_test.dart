// test/unit/handshake_ages_test.dart - "up" and "answering" are different questions (ID-123).
//
// An expired PIA registration leaves an interface that exists, sends, and is never answered. `wg`
// reports 0 for a peer that has never completed a handshake, which is exactly that state, so a 0
// must never read as "just now".
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String output(List<String> lines, int now) => '${lines.join('\n')}\n---\n$now';

  test('an age per slot, measured against the ROUTER clock', () {
    final ages = parseHandshakeAges(output([
      'wgc1\tSGVsbG8gd29ybGQgdGhpcyBpcyBhIGtleQ==\t1000',
      'wgc5\tQW5vdGhlciBrZXkgZm9yIHRoZSB0ZXN0ISE=\t1200',
    ], 1300));

    expect(ages[1], 300);
    expect(ages[5], 100);
  });

  test('a peer that has never handshaked is absent, not fresh', () {
    final ages = parseHandshakeAges(output(['wgc3\tkey\t0'], 5000));
    expect(ages.containsKey(3), isFalse);
  });

  test('the newest peer wins when a slot has several', () {
    final ages = parseHandshakeAges(output([
      'wgc2\tkeyA\t900',
      'wgc2\tkeyB\t1000',
    ], 1100));
    expect(ages[2], 100);
  });

  test('a server interface is not a client slot', () {
    expect(parseHandshakeAges(output(['wgs1\tkey\t1000'], 1100)), isEmpty);
  });

  test('nothing usable gives nothing, rather than a wrong answer', () {
    expect(parseHandshakeAges(''), isEmpty);
    expect(parseHandshakeAges('wgc1\tkey\t1000'), isEmpty, reason: 'no clock, no ages');
    expect(parseHandshakeAges('---\nnot-a-number'), isEmpty);
  });

  test('the answering window is the watchdog\'s own', () {
    expect(kAnsweringWithinSeconds, 300);
  });
}
