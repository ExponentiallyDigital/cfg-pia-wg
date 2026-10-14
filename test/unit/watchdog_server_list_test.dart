// The watchdog checks PIA's signature on the server list before using it (ID-325), run for real
// against a fake stock router (test/watchdog_harness.dart). The list served is PIA's own, as PIA
// signed it, and the check is the real openssl with PIA's real key.
//
// Andrew's decision, 2026-10-13: a list that fails is refused; the last list that passed is used
// instead, and every run that does that says so in the log and the alert email; a router that has
// never had a list pass refuses outright.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cfg_pia_wg/router_watchdog.dart';

import '../server_list_test_key.dart' show kRealServerListFixture;
import '../watchdog_harness.dart';
import '../watchdog_test_utils.dart';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    if (shell != null) h = WatchdogHarness.create(shell: shell)!;
  });
  tearDown(() {
    if (shell != null) h.dispose();
  });

  final real = File(kRealServerListFixture).readAsBytesSync();
  const failed = "The server list failed PIA's signature check, so it is not used: it might have been tampered with";

  /// A good list kept by an earlier run, on [date].
  void savedEarlier([String date = '2026-10-01 09:30 +1000']) {
    h.savedServerList.writeAsBytesSync(real);
    h.savedServerListDate.writeAsStringSync('$date\n');
  }

  group("PIA's server list signature", () {
    test("PIA's list passes, is used, and is kept for a list that fails later", () async {
      h.tunnelUp(handshakeAgo: null);
      final r = await h.run();
      expect(r.exitCode, 0, reason: h.log.join('\n'));
      expect(h.log, contains("Server list verified: it carries PIA's signature"));
      expect(h.log.last, 'Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337');
      expect(h.savedServerList.readAsBytesSync(), real, reason: 'kept exactly as PIA sent it');
      expect(h.savedServerListDate.readAsStringSync(), startsWith(DateTime.now().toIso8601String().substring(0, 10)));
    });

    test('a tampered list is refused, and the last list that passed is used, said in the log and the email', () async {
      savedEarlier();
      h
        ..captureMail()
        ..tamperedServerList()
        ..tunnelUp(handshakeAgo: null);
      final r = await h.run();
      expect(r.exitCode, 0, reason: h.log.join('\n'));
      expect(h.log, contains(failed));
      expect(h.log, contains('Using the last server list that passed, verified on 2026-10-01 09:30 +1000'));
      expect(h.log.any((l) => l.contains('FORGED-SERVER')), isFalse, reason: 'the tampered list offered it');
      expect(h.log, contains('Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337'));
      expect(h.log.last, 'Alert email sent (SUCCESS)');
      expect(h.savedServerList.readAsBytesSync(), real, reason: 'a list that fails never replaces it');
      expect(h.savedServerListDate.readAsStringSync().trim(), '2026-10-01 09:30 +1000');
      final mail = h.mails.single;
      expect(mail, contains('\nSERVER LIST\n'));
      expect(mail, contains("PIA's server list failed its signature check on this run, so it was not used"));
      expect(mail, contains('verified on 2026-10-01 09:30 +1000'));
      expect(mail, contains('PIA servers added or moved since then are not seen'));
    });

    test('the email says nothing about the list when it passed', () async {
      h
        ..captureMail()
        ..tunnelUp(handshakeAgo: null);
      await h.run();
      expect(h.log, contains('Reconfig SUCCESS: region pia-nz via 192.0.2.51:1337'));
      expect(h.mails.single, isNot(contains('SERVER LIST')));
    });

    test('a router that has never had a list pass refuses a tampered one outright', () async {
      h
        ..captureMail()
        ..tamperedServerList()
        ..tunnelUp(handshakeAgo: null);
      final r = await h.run();
      expect(r.exitCode, 1);
      expect(h.log, contains(failed));
      final error = h.log.firstWhere((l) => l.startsWith('ERROR: '));
      expect(error, startsWith("ERROR: PIA's server list failed its signature check"));
      expect(error, contains('no earlier list that passed to fall back on'));
      expect(h.log.any((l) => l.startsWith('Selected server')), isFalse);
      expect(h.get('wgc1_ppub'), 'OLDSERVERKEY', reason: 'nothing was written');
      expect(h.savedServerList.existsSync(), isFalse);
      expect(h.mails.single, contains('could NOT be rebuilt'));
    });

    test('a list with no signature at all is refused', () async {
      h
        ..serverList('{"regions":[]}\n'.codeUnits)
        ..tunnelUp(handshakeAgo: null);
      final r = await h.run();
      expect(r.exitCode, 1);
      expect(h.log, contains(failed));
    });

    test('a kept list that no longer passes is refused too, as a tampered download is', () async {
      savedEarlier();
      final kept = String.fromCharCodes(real).replaceFirst('"cn":"', '"cn":"x');
      h.savedServerList.writeAsStringSync(kept);
      h
        ..tamperedServerList()
        ..tunnelUp(handshakeAgo: null);
      final r = await h.run();
      expect(r.exitCode, 1);
      expect(h.log.last, contains('no earlier list that passed to fall back on'));
    });

    test('a kept list with its date lost is still used, and says the date is unknown', () async {
      savedEarlier();
      h.savedServerListDate.deleteSync();
      h
        ..tamperedServerList()
        ..tunnelUp(handshakeAgo: null);
      await h.run();
      expect(h.log, contains('Using the last server list that passed, verified on an unknown date'));
      expect(h.log.last, startsWith('Reconfig SUCCESS'));
    });

    // The control: with the check taken out, the same tampered list gets its server chosen. Without
    // this, the tests above couldn't tell a check that works from one that never runs.
    test('control: with the check taken out, the tampered list is used', () async {
      h
        ..tamperedServerList()
        ..tunnelUp(handshakeAgo: null);
      final r = await h.run(edit: (s) => s.replaceFirst('list_verified() {\n', 'list_verified() {\n  head -1 "\$1" | tr -d \'\\n\' > "\$SLDATA"; return 0\n'));
      expect(r.exitCode, 0, reason: h.log.join('\n'));
      expect(h.log, contains('Selected server 198.51.100.66 (FORGED-SERVER) for region pia-nz'));
    });
  }, skip: skip);

  // REMOVE CACHED PIA SERVERS (ID-325): the command the app sends, run in a real shell.
  group('deleting the router copy', () {
    Future<(String, bool)> deleteVia(WatchdogHarness h) async {
      final ssh = RecordingSSHClient(responder: (_) => 'DELETED');
      await RouterWatchdog(ssh).deleteCachedServerList();
      final cmd = ssh.commands.firstWhere((c) => c.contains(kPiaServerListPath));
      final r = await h.runSnippet(cmd);
      return ((r.stdout as String).trim(), h.savedServerList.existsSync() || h.savedServerListDate.existsSync());
    }

    test('removes the list and its date, and reads back that they are gone', () async {
      savedEarlier();
      final (out, left) = await deleteVia(h);
      expect(out, 'DELETED');
      expect(left, isFalse);
    });

    test('says ABSENT when there is none, and clears a date left on its own', () async {
      h.savedServerListDate.writeAsStringSync('2026-10-01\n');
      final (out, left) = await deleteVia(h);
      expect(out, 'ABSENT');
      expect(left, isFalse);
    });
  }, skip: skip);
}
