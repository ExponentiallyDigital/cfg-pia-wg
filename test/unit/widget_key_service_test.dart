// test/unit/widget_key_service_test.dart - installing and removing the widget key, over a fake
// SSH client (ID-376). No router, no secure storage - see widget_key_test.dart for those.
import 'package:cfg_pia_wg/widget_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const String kOurLine = 'command="echo hi",no-pty ssh-ed25519 AAAAOURS cfg-pia-wg-widget';
const String kTheirLine = 'ssh-ed25519 AAAAOTHER andrew@laptop';

void main() {
  group('install', () {
    test('an empty sshd_authkeys is set to just the new line, in both places', () async {
      final client = RecordingSSHClient(responder: (_) => '');
      await WidgetKeyRouterService(client).install(kOurLine);

      expect(client.commands, [
        'nvram get sshd_authkeys',
        "nvram set sshd_authkeys='$kOurLine'; nvram commit; "
            "mkdir -p ~/.ssh; chmod 700 ~/.ssh; "
            "printf '%s\\n' '$kOurLine' > ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys",
      ]);
    });

    test("the user's own existing key is carried through, ours added after it", () async {
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? kTheirLine : '');
      await WidgetKeyRouterService(client).install(kOurLine);

      final write = client.commands.last;
      expect(write, contains(shellSingleQuoteFor('$kTheirLine\n$kOurLine')));
    });

    test('installing again replaces the previous widget line rather than adding a second one', () async {
      final already = '$kTheirLine\n$kOurLine';
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? already : '');
      const newer = 'command="echo bye",no-pty ssh-ed25519 AAAANEWER cfg-pia-wg-widget';
      await WidgetKeyRouterService(client).install(newer);

      expect(client.commands.last, contains(shellSingleQuoteFor('$kTheirLine\n$newer')));
      expect(client.commands.last, isNot(contains('AAAAOURS')));
    });

    test("embedded single quotes in the router's own existing keys do not break the write", () async {
      final tricky = "ssh-rsa AAAA it's-fine andrew";
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? tricky : '');
      await WidgetKeyRouterService(client).install(kOurLine);

      expect(client.commands.last, contains(shellSingleQuoteFor('$tricky\n$kOurLine')));
    });
  });

  group('remove', () {
    test('nothing installed is a true no-op - no write command is sent at all', () async {
      final client = RecordingSSHClient(responder: (_) => kTheirLine);
      await WidgetKeyRouterService(client).remove();

      expect(client.commands, ['nvram get sshd_authkeys']);
    });

    test('an installed key is taken out, and the rest is kept', () async {
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? '$kTheirLine\n$kOurLine' : '');
      await WidgetKeyRouterService(client).remove();

      expect(client.commands.last, contains(shellSingleQuoteFor(kTheirLine)));
      expect(client.commands.last, isNot(contains('AAAAOURS')));
    });

    test('removing the only key leaves both the live file and the nvram value empty', () async {
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? kOurLine : '');
      await WidgetKeyRouterService(client).remove();

      expect(client.commands.last, contains("nvram set sshd_authkeys=''"));
      expect(client.commands.last, contains("printf '%s\\n' '' > ~/.ssh/authorized_keys"));
    });
  });
}

/// The same escaping `shellSingleQuote` (lib/router_watchdog.dart) applies, spelled out here so
/// each test's expectation is built the same way the service itself builds it, independent of
/// this file importing that private-ish helper by name.
String shellSingleQuoteFor(String s) => "'${s.replaceAll("'", "'\\''")}'";
