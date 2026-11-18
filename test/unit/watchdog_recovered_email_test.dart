// A tunnel that mends itself after failed rebuilds says so, run for real against a fake stock router
// (test/watchdog_harness.dart).
//
// The watchdog emailed SUCCESS after a rebuild and FAILED after a failed one, and said nothing when a
// tunnel came back between two attempts, since nothing had been rebuilt. On 2026-11-18 wgc1 sent four
// FAILED emails while PIA's New Zealand servers did not answer, healed itself, and the four were never
// closed (ID-628). A RECOVERED email now follows, once.

@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) {
      h = WatchdogHarness.create(shell: shell)!..captureMail();
      h.tunnelUp(handshakeAgo: 30);
    }
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  /// The status file, as a check five minutes ago left it.
  void lastGoodFiveMinutesAgo() {
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 315;
    h.tmp('watchdog_last_ping_success_${h.iface}').writeAsStringSync('$epoch 2026-11-18 18:55:07\n');
  }

  test('a healthy check after failed attempts sends one RECOVERED email, saying how long it was down', () async {
    lastGoodFiveMinutesAgo();
    h.backoff(3, 120);
    final r = await h.run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final mail = h.mails.single;
    expect(mail, contains('Connectivity was lost and the tunnel is working again without a rebuild.'), reason: mail);
    expect(mail, contains('Tunnel was down for: 5m'), reason: mail);
    expect(mail, contains('Attempt: 3 failed since the last success'), reason: mail);
    expect(mail, contains('3 earlier attempts to rebuild it failed'), reason: mail);
    expect(mail, contains(RegExp(r'\(handshake 3\ds ago\)')), reason: 'the handshake age, a second or so after the 30 set');
    expect(h.syslog.join('\n'), contains('Alert email sent (RECOVERED)'));
    expect(h.backoffFile, '0\n0\n', reason: 'the failures are cleared');
  }, skip: skip);

  test('it reads as good news: no steps to take and no log of a failure', () async {
    lastGoodFiveMinutesAgo();
    h.backoff(2, 60);
    await h.run();
    final mail = h.mails.single;
    expect(mail, isNot(contains('WHAT TO DO')));
    expect(mail, isNot(contains('ROUTER LOG')));
    expect(mail, isNot(contains('could NOT')));
    expect(mail, contains('2 earlier attempts'));
  }, skip: skip);

  test('one failed attempt is "attempt", not "attempts"', () async {
    lastGoodFiveMinutesAgo();
    h.backoff(1, 60);
    await h.run();
    expect(h.mails.single, contains('1 earlier attempt to rebuild it failed'));
  }, skip: skip);

  test('it is sent once: the next healthy check finds nothing on record', () async {
    lastGoodFiveMinutesAgo();
    h.backoff(3, 120);
    await h.run();
    await h.run();
    expect(h.mails, hasLength(1));
  }, skip: skip);

  test('control: a healthy check with no failures on record sends nothing', () async {
    lastGoodFiveMinutesAgo();
    final r = await h.run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(h.mails, isEmpty);
  }, skip: skip);

  test('control: a deploy run sends its own email, not RECOVERED, even with failures on record', () async {
    lastGoodFiveMinutesAgo();
    h.backoff(3, 120);
    await h.run(mode: 'deploy');
    final mail = h.mails.single;
    expect(mail, contains('Watchdog deployed and the tunnel is up.'));
    expect(mail, isNot(contains('RECOVERED')));
  }, skip: skip);

  test('control: a tunnel that is still down sends FAILED or nothing, never RECOVERED', () async {
    h.tunnelDown();
    h.backoff(1, 10);
    await h.run();
    for (final m in h.mails) {
      expect(m, isNot(contains('RECOVERED')));
    }
  }, skip: skip);
}
