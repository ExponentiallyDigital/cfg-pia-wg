// test/widgets/watchdog_log_colour_test.dart - the watchdog log is coloured like ROUTER LOG (ID-117, ID-158).
//
// The wording here is copied from the `log "..."` calls in router_watchdog.dart. If a message is
// reworded there and not here, the line quietly loses its colour - which is what these cases catch.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/router_log_paging.dart';
import 'package:cfg_pia_wg/screens/router_log_screen.dart';
import 'package:cfg_pia_wg/widgets/slot_modal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stamp = '2026-09-19 06:12:01 ';

  const faults = [
    'ERROR: PIA username is not set',
    'Connectivity lost; reconfiguring (attempt #3)',
    'No handshake and both pings failed (10.0.0.1, 10.0.0.2)',
    'no Internet on WAN interface, exiting.',
    'Email FAILED (mailer exit=1) stderr=[none]',
    'Alert email sent (FAILED)',
    'Backing off after 3 failed attempts: 120s of 240s elapsed',
  ];

  test('a fault is red', () {
    for (final line in faults) {
      expect(watchdogLogLineColour('$stamp$line'), kError, reason: line);
    }
  });

  // The same line in ROUTER LOG carries the syslog prefix. Red on one screen and not the other was
  // the inconsistency ID-158 reported.
  test('a line is red here exactly when it is red in ROUTER LOG', () {
    for (final line in [...faults, 'Handshake 25s ago', 'Not connected yet: no handshake, and no answer from 8.8.8.8 or 1.1.1.1']) {
      final inRouterLog = 'Sep 19 06:12:01 cfg-pia-wg: wgc5: $line';
      expect(watchdogLogLineColour('$stamp$line') == kError, routerLogLineColour(inRouterLog) == kError, reason: line);
      expect(readsAsError(line), isRouterLogError(inRouterLog), reason: line);
    }
  });

  test('a rebuild that worked is teal', () {
    for (final line in [
      'Deploy SUCCESS: region aus_perth via 203.0.113.9:1337',
      'Reconfig SUCCESS: region aus_perth via 203.0.113.9:1337',
      'Alert email sent (SUCCESS)',
    ]) {
      expect(watchdogLogLineColour('$stamp$line'), kHighlight, reason: line);
    }
  });

  test('everything else is the watchdog lavender, as in ROUTER LOG', () {
    for (final line in [
      'Checking wgc5 aus_perth connectivity',
      'Handshake 25s ago',
      'Deploying: bringing wgc5 up for the first time [script 0.8.83]',
      'PIA token obtained (len=256)',
      'Latency to 203.0.113.9 (perth401): 31ms',
      'wgc5 is disabled in the router; standing down until it is enabled again',
      // What a first deploy says before its tunnel has come up. Not a fault (ID-158).
      'Not connected yet: no handshake, and no answer from 8.8.8.8 or 1.1.1.1',
    ]) {
      expect(watchdogLogLineColour('$stamp$line'), kWatchdogText, reason: line);
    }
  });
}
