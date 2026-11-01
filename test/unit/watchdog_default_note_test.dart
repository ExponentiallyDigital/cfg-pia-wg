// The alert email's note about the default connection, run for real against a fake stock router
// (test/watchdog_harness.dart).
//
// Added to the kill switch line, straight after the pinned devices' names, "This tunnel is also the
// default connection, and devices that only follow the default are not covered by the guard" read as
// doubt about those devices, on a router where every device was pinned (Andrew, 2026-11-01). It is its
// own paragraph now, below the WHAT HAPPENED rows, and says who it is about.

@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

const String kNote = "This tunnel is the router's default connection: a device not pinned to any tunnel, such as one that "
    'joins your network later, will use the default connection, so it can reach the internet without a VPN while this '
    'tunnel is down.';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) h = WatchdogHarness.create(shell: shell)!..captureMail();
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  test('when this tunnel is the default connection, the email says so in a paragraph of its own', () async {
    // wgc1's table in the harness's clientlist is 9.
    h.set('vpnc_default_wan', '9');
    final r = await h.run(mode: 'deploy');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final mail = h.mails.single;
    final lines = mail.split('\n');
    final note = lines.indexOf(kNote);
    expect(note, greaterThan(0), reason: mail);
    expect(lines[note - 1], '', reason: 'a paragraph of its own');
    expect(lines.indexWhere((l) => l.startsWith('Interval: ')), lessThan(note), reason: 'below the rows, not among them');
    final killSwitch = lines.firstWhere((l) => l.startsWith('Kill switch: '));
    expect(killSwitch, isNot(contains('default connection')), reason: 'the kill switch line is about the pinned devices only');
  }, skip: skip);

  test('control: when it is not, there is no such paragraph', () async {
    h.set('vpnc_default_wan', '0');
    await h.run(mode: 'deploy');
    expect(h.mails.single, isNot(contains("default connection")));
  }, skip: skip);
}
