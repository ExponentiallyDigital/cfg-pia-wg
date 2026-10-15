// test/unit/widget_key_service_test.dart - installing and removing the widget key, over a fake
// SSH client (ID-376). No router, no secure storage - see widget_key_test.dart for those.
import 'dart:typed_data';

import 'package:cfg_pia_wg/widget_key.dart';
import 'package:cfg_pia_wg/widget_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

// Two devices' widget keys, as each would install them, and the user's own key. Fixed bytes, so
// each line's key is known; any 32 bytes are an Ed25519 public key as far as the line is concerned.
final Uint8List kOurKey = Uint8List.fromList(List.filled(32, 7));
final Uint8List kTabletKey = Uint8List.fromList(List.filled(32, 9));
final String kOurLine = openSshPublicKeyLine(kOurKey, restriction: 'command="echo hi",no-pty', comment: kWidgetKeyComment);
final String kTabletLine = openSshPublicKeyLine(kTabletKey, restriction: 'command="echo hi",no-pty', comment: kWidgetKeyComment);
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

    test('installing the same key again replaces its line rather than adding a second one', () async {
      final already = '$kTheirLine\n$kOurLine';
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? already : '');
      await WidgetKeyRouterService(client).install(kOurLine);

      expect(client.commands.last, contains(shellSingleQuoteFor('$kTheirLine\n$kOurLine')));
    });

    // ID-398: until build 498 this took the tablet's line out, and the tablet's widget stopped.
    test("another device's widget key stays when this one installs", () async {
      final already = '$kTheirLine\n$kTabletLine';
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? already : '');
      await WidgetKeyRouterService(client).install(kOurLine);

      expect(client.commands.last, contains(shellSingleQuoteFor('$kTheirLine\n$kTabletLine\n$kOurLine')));
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
      final client = RecordingSSHClient(responder: (_) => '$kTheirLine\n$kTabletLine');
      await WidgetKeyRouterService(client).remove(kOurKey);

      expect(client.commands, ['nvram get sshd_authkeys']);
    });

    test("this device's key is taken out, and the rest - another device's widget key included - is kept", () async {
      final client = RecordingSSHClient(
          responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? '$kTheirLine\n$kTabletLine\n$kOurLine' : '');
      await WidgetKeyRouterService(client).remove(kOurKey);

      expect(client.commands.last, contains(shellSingleQuoteFor('$kTheirLine\n$kTabletLine')));
      expect(client.commands.last, isNot(contains(widgetKeyBlob(kOurKey))));
    });

    test('removing the only key leaves both the live file and the nvram value empty', () async {
      final client = RecordingSSHClient(responder: (cmd) => cmd == 'nvram get sshd_authkeys' ? kOurLine : '');
      await WidgetKeyRouterService(client).remove(kOurKey);

      expect(client.commands.last, contains("nvram set sshd_authkeys=''"));
      expect(client.commands.last, contains("printf '%s\\n' '' > ~/.ssh/authorized_keys"));
    });
  });
}

/// The same escaping `shellSingleQuote` (lib/router_watchdog.dart) applies, spelled out here so
/// each test's expectation is built the same way the service itself builds it, independent of
/// this file importing that private-ish helper by name.
String shellSingleQuoteFor(String s) => "'${s.replaceAll("'", "'\\''")}'";
