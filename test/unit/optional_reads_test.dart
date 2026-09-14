// test/unit/optional_reads_test.dart - reading a file the watchdog may not have created yet.
//
// Opening a slot with a VPN running but no watchdog put two "router command failed (exit 1)" lines
// in the app log: `cat` of the last-ping marker and `sed` of the deployed script, neither of which
// exists until a watchdog does. The reads were already tolerated, but tolerated failures are still
// logged, and a user reading "failed" assumes something broke. The reads are now guarded by an
// existence test, so the shell answers 0 with nothing when the file is absent.
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

void main() {
  test('the last-ping marker and the script header are read only when they exist', () async {
    final ssh = RecordingSSHClient(responder: (_) => '');
    await RouterWatchdog(ssh).getWatchdogStatus(5);

    expect(ssh.ran("if [ -f '/tmp/watchdog_last_ping_success_wgc5' ]; then cat '/tmp/watchdog_last_ping_success_wgc5'; fi"),
        isTrue);
    expect(ssh.ran("then sed -n '2p' "), isTrue, reason: 'the script header read is guarded the same way');
    expect(ssh.ran('cat /tmp/watchdog_last_ping_success_wgc5 2>/dev/null'), isFalse,
        reason: 'the bare read exits 1 when the file is missing, which is what reached the app log');
  });
}
