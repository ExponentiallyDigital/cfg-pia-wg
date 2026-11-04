// test/unit/widget_key_service_test.dart - installing and removing widget keys, against a fake router
// that keeps sshd_authkeys, the live file and the upload file (ID-376, ID-398, ID-407). No secure
// storage - see widget_key_test.dart for that.
import 'dart:typed_data';

import 'package:cfg_pia_wg/router_watchdog.dart' show kMaxSshCommandBytes;
import 'package:cfg_pia_wg/widget_key.dart';
import 'package:cfg_pia_wg/widget_key_service.dart';
import 'package:cfg_pia_wg/widget_status_service.dart' show kWidgetReadScript, kWidgetReadScriptPath, kWidgetStatusCommand;
import 'package:flutter_test/flutter_test.dart';

import '../widget_key_router_fake.dart';

/// A widget line as the app installs it, full length, for a device whose public key is [key].
String _line(Uint8List key) =>
    openSshPublicKeyLine(key, restriction: widgetKeyRestriction(kWidgetStatusCommand), comment: kWidgetKeyComment);
Uint8List _key(int n) => Uint8List.fromList(List.filled(32, n));
const String kTheirLine = 'ssh-ed25519 AAAAOTHER andrew@laptop';

void main() {
  group('install', () {
    test("adds this phone's key, keeping the user's own and another device's, and reads it back", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(9))}');
      await WidgetKeyRouterService(r.client).install(_line(_key(7)));
      expect(r.nv, '$kTheirLine\n${_line(_key(9))}\n${_line(_key(7))}');
      expect(r.live, r.nv);
      expect(r.client.commands.where((c) => c == 'nvram get sshd_authkeys'), hasLength(2), reason: 'read, then read back');
    });

    // ID-407: with 5 widget keys the single command was 9870 bytes, and Dropbear dropped it.
    test('no command it sends reaches the SSH limit, with ten widget keys already there', () async {
      final r = FakeKeysRouter([for (var i = 10; i < 20; i++) _line(_key(i))].join('\n'));
      await WidgetKeyRouterService(r.client).install(_line(_key(7)));
      expect(widgetKeyLineCount(r.nv), 11);
      for (final c in r.client.commands) {
        expect(c.length, lessThan(kMaxSshCommandBytes), reason: c.length > 60 ? c.substring(0, 60) : c);
      }
    });

    test("GENERATE on a phone that had a key replaces that key's line", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(5))}\n${_line(_key(9))}');
      await WidgetKeyRouterService(r.client).install(_line(_key(7)), replacing: _key(5));
      expect(r.nv, '$kTheirLine\n${_line(_key(9))}\n${_line(_key(7))}');
    });

    test('a router that did not keep the key is a plain failure, not a success', () async {
      final r = FakeKeysRouter(kTheirLine, keeps: false);
      await expectLater(
        WidgetKeyRouterService(r.client).install(_line(_key(7))),
        throwsA(isA<WidgetKeyRouterException>().having((e) => e.message, 'message', contains('nothing was saved on this phone'))),
      );
    });
  });

  // ID-467: the read lives in a script on the router, so each key's line is short.
  group('the read script', () {
    test('GENERATE writes the script before the key, and the line is short, with no inline read', () async {
      final r = FakeKeysRouter(kTheirLine);
      await WidgetKeyRouterService(r.client).install(widgetKeyLine(_key(7)));
      expect(r.files[kWidgetReadScriptPath], kWidgetReadScript);
      final script = r.client.commands.indexWhere((c) => c.contains("'$kWidgetReadScriptPath' <<"));
      final key = r.client.commands.indexWhere((c) => c.startsWith('nvram set sshd_authkeys'));
      expect(script, lessThan(key), reason: 'the key never points at a script that is not there');
      expect(widgetKeyLine(_key(7)).length, lessThan(250));
      expect(widgetKeyLine(_key(7)), isNot(contains('nvram get')), reason: 'the inline read is back');
      expect(widgetKeyLine(_key(7)), contains('command="/bin/sh $kWidgetReadScriptPath"'));
    });

    test("an old long line moves to the short form when its phone connects, and nobody else's changes", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(9))}\n${_line(_key(7))}');
      final changed = await WidgetKeyRouterService(r.client).keepCurrent(ownKey: _key(7));
      expect(r.nv, '$kTheirLine\n${_line(_key(9))}\n${widgetKeyLine(_key(7))}');
      expect(r.files[kWidgetReadScriptPath], kWidgetReadScript, reason: 'written first, since the new line uses it');
      expect(changed, hasLength(2));
    });

    test('a stale or missing script is put back wherever a key uses it, even with no key on this phone', () async {
      for (final script in [null, '#!/bin/sh\necho old\n']) {
        final r = FakeKeysRouter('$kTheirLine\n${widgetKeyLine(_key(9))}', script: script);
        final changed = await WidgetKeyRouterService(r.client).keepCurrent();
        expect(r.files[kWidgetReadScriptPath], kWidgetReadScript, reason: '$script');
        expect(r.nv, '$kTheirLine\n${widgetKeyLine(_key(9))}', reason: 'the keys are left alone');
        expect(changed, ["the home screen widget's read script"]);
      }
    });

    test('nothing to do writes nothing: a current script and line, or no widget key at all', () async {
      for (final r in [
        FakeKeysRouter('$kTheirLine\n${widgetKeyLine(_key(7))}', script: kWidgetReadScript),
        FakeKeysRouter(kTheirLine),
        FakeKeysRouter('$kTheirLine\n${_line(_key(9))}'),
      ]) {
        expect(await WidgetKeyRouterService(r.client).keepCurrent(ownKey: _key(7)), isEmpty);
        expect(r.client.commands.where((c) => c.contains('<<') || c.startsWith('nvram set')), isEmpty, reason: r.nv);
      }
    });
  });

  group('removeAll', () {
    test("takes every device's widget key off, leftovers included, and keeps the user's own", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(5))}\n${_line(_key(9))}\n${_line(_key(7))}');
      expect(await WidgetKeyRouterService(r.client).removeAll(), 3);
      expect(r.nv, kTheirLine);
      expect(r.live, kTheirLine);
    });

    test('none there is no write at all', () async {
      final r = FakeKeysRouter(kTheirLine);
      expect(await WidgetKeyRouterService(r.client).removeAll(), 0);
      expect(r.client.commands.where((c) => c.contains('nvram set')), isEmpty);
    });

    test('a key still there afterwards is a plain failure', () async {
      final r = FakeKeysRouter(_line(_key(5)), keeps: false);
      await expectLater(WidgetKeyRouterService(r.client).removeAll(), throwsA(isA<WidgetKeyRouterException>()));
    });
  });
}
