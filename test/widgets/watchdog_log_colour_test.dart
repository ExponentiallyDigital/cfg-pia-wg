// test/widgets/watchdog_log_colour_test.dart - the watchdog log is coloured by outcome (ID-117).
//
// The wording here is copied from the `log "..."` calls in router_watchdog.dart. If a message is
// reworded there and not here, the line quietly loses its colour - which is what these cases catch.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/widgets/slot_modal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stamp = '2026-09-19 06:12:01 ';

  test('a fault is red', () {
    for (final line in [
      'ERROR: PIA username is not set',
      'Connectivity lost; reconfiguring (attempt #3)',
      'No handshake and both pings failed (10.0.0.1, 10.0.0.2)',
      'Not connected yet: no handshake, and no answer from 10.0.0.1 or 10.0.0.2',
      'no Internet on WAN interface, exiting.',
      'Email FAILED (mailer exit=1) stderr=[none]',
      'Alert email sent (FAILED)',
    ]) {
      expect(watchdogLogLineColour('$stamp$line'), kError, reason: line);
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

  test('the steps of a rebuild are amber', () {
    for (final line in [
      'Deploying: bringing wgc5 up for the first time [script 0.8.83]',
      'CA cert not cached; downloading',
      'Using cached CA cert',
      'PIA token obtained (len=256)',
      'Servers: 14 candidates',
      'Latency to 203.0.113.9 (perth401): 31ms',
      'CA cert cached at /jffs/cfg-pia-wg/ca.rsa.4096.crt',
      'WAN has internet connectivity',
    ]) {
      expect(watchdogLogLineColour('$stamp$line'), kWarn, reason: line);
    }
    // "Backing off after N failed attempts" carries the word failed, so red wins there - correct,
    // because the tunnel is still down and the run is doing nothing about it yet.
    expect(watchdogLogLineColour('${stamp}Backing off after 3 failed attempts: 120s of 240s elapsed'), kError);
  });

  test('the routine check keeps the plain text colour', () {
    for (final line in [
      'Checking wgc5 aus_perth connectivity',
      'Handshake 25s ago',
      'Primary ping OK (10.0.0.1)',
      'Secondary ping OK (10.0.0.2)',
      'wgc5 is disabled in the router; standing down until it is enabled again',
    ]) {
      expect(watchdogLogLineColour('$stamp$line'), line.contains('standing down') ? kWarn : isNull, reason: line);
    }
  });
}
