// test/unit/backoff_test.dart - growing the wait when PIA refuses.
//
// PIA answers HTTP 403 after sustained re-registration and clears on its own after tens of
// minutes. The script used to retry every 120 s forever, which is what provoked and prolonged the
// block - with two watchdogs, a request a minute between them. The wait now climbs 2, 4, 8, 16,
// 30, 60 minutes and caps at 90, resetting the moment a reconfigure succeeds.
//
// Two properties are load-bearing and easy to lose. The ladder lives in Dart and is emitted into
// the shell, so the two cannot disagree. And the counter must track attempts actually MADE, never
// checks that found a fault - counting checks made the growth rate depend on the check interval,
// so a 1-minute watchdog escalated twice as fast as a 2-minute one.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';

const WatchdogConfig _cfg = WatchdogConfig(slotIndex: 1, primaryIp: '9.9.9.9', secondaryIp: '1.1.1.1');

void main() {
  group('backoffSeconds', () {
    test('climbs 2, 4, 8, 16, 30, 60 minutes', () {
      expect([1, 2, 3, 4, 5, 6].map(backoffSeconds).toList(), [120, 240, 480, 960, 1800, 3600]);
    });

    test('caps at 90 minutes and stays there', () {
      expect(backoffSeconds(7), 5400);
      expect(backoffSeconds(8), 5400);
      expect(backoffSeconds(500), 5400);
      expect(kBackoffLadder.last, 5400, reason: 'the cap is a ceiling, not a tuning knob');
    });

    // The common case is a single failure, which has to stay exactly as responsive as it was
    // before the ladder existed.
    test('the first failure still waits the original two minutes', () {
      expect(backoffSeconds(1), 120);
      expect(backoffSeconds(0), 120, reason: 'no failures yet answers the first rung, not zero');
    });

    test('every rung is longer than the one before it', () {
      for (var i = 1; i < kBackoffLadder.length; i++) {
        expect(kBackoffLadder[i], greaterThan(kBackoffLadder[i - 1]));
      }
    });
  });

  group('buildBackoffCase', () {
    test('emits the ladder as a POSIX case, cap as the default arm', () {
      expect(buildBackoffCase(), '''
backoff_for() {
  case "\$1" in
    0|1) echo 120 ;;
    2) echo 240 ;;
    3) echo 480 ;;
    4) echo 960 ;;
    5) echo 1800 ;;
    6) echo 3600 ;;
    *) echo 5400 ;;
  esac
}''');
    });

    // The anti-drift check: the shell is generated from the same list backoffSeconds reads, so a
    // rung changed in one place cannot be left behind in the other.
    test('every rung in the shell matches the Dart function', () {
      final shell = buildBackoffCase();
      for (var failures = 1; failures <= kBackoffLadder.length; failures++) {
        final arm = failures < kBackoffLadder.length ? '$failures) echo ${backoffSeconds(failures)} ;;' : null;
        if (arm != null) expect(shell, contains(arm.replaceFirst('1)', '0|1)')));
      }
      expect(shell, contains('*) echo ${backoffSeconds(99)} ;;'));
    });
  });

  group('the deployed script', () {
    String script([RouterFirmware fw = RouterFirmware.merlin]) => buildWatchdogScript(_cfg, firmware: fw);

    test('the fixed COOLDOWN constant is gone, replaced by the ladder', () {
      final s = script();
      expect(s, isNot(contains('COOLDOWN=120')));
      expect(s, isNot(contains(r'$COOLDOWN')));
      expect(s, contains(buildBackoffCase()));
    });

    test('the wait is looked up before the gate, and the gate compares against it', () {
      final s = script();
      expect(s, contains(r'WAIT="$(backoff_for "$CNT")"'));
      expect(s, contains(r'if [ "$LAST" -ne 0 ] && [ "$ELAPSED" -lt "$WAIT" ]; then'));
    });

    // A run turned away by the backoff must leave the counter alone. Incrementing there is what
    // made the growth rate depend on the check interval.
    test('the counter rises only when an attempt is actually made', () {
      final s = script();
      final gate = s.indexOf(r'if [ "$LAST" -ne 0 ] && [ "$ELAPSED" -lt "$WAIT" ]');
      final bump = s.indexOf(r'CNT=$((CNT + 1))');
      expect(bump, greaterThan(gate), reason: 'the increment belongs after the early exit');
      expect(s, contains('log "Backing off after \$CNT failed attempts'),
          reason: 'a long quiet gap otherwise reads as a stopped watchdog');
    });

    test('a success resets the counter', () {
      expect(script(), contains(r"printf '0\n0\n' > " '"\$BACKOFFFILE"'));
    });

    // The alert used to promise the bare check interval, which is a lie once the wait exceeds it.
    test('the alert names whichever of the backoff and the next tick comes later', () {
      final s = script();
      expect(s, contains(r'NEXTWAIT="$(backoff_for "${CNT:-1}")"'));
      expect(s, contains(r'[ "$NEXTWAIT" -ge "$TICK" ] || NEXTWAIT="$TICK"'));
      expect(s, contains(r'retrying per schedule, $((NEXTWAIT / 60)) minutes'));
      // An unset or junk interval must not make the arithmetic fail.
      expect(s, contains(r"case " '"\$INTERVAL" in ' r"''|*[!0-9]*) TICK=300 ;;"));
    });

    test('a non-numeric backoff file is read as zero rather than crashing the arithmetic', () {
      final s = script();
      expect(s, contains(r'case "$CNT" in ' "''" r'|*[!0-9]*) CNT=0 ;; esac'));
      expect(s, contains(r'case "$LAST" in ' "''" r'|*[!0-9]*) LAST=0 ;; esac'));
    });
  });
}
