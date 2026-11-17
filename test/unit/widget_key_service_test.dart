// test/unit/widget_key_service_test.dart - installing and removing widget keys, against a fake router
// that keeps sshd_authkeys, the live file and the upload file (ID-376, ID-398, ID-407). No secure
// storage - see widget_key_test.dart for that.
import 'dart:typed_data';

import 'package:cfg_pia_wg/router_watchdog.dart' show buildLoggerCommand, kMaxSshCommandBytes;
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

  // ID-616 (Andrew's rule, 2026-11-16): a widget key added, replaced or removed is logged to the app
  // log and to the router's, always, success or failure, and never with the key in it.
  group('every change is logged to both logs', () {
    // What the service sent to the app log, and the lines it sent to the router's `logger`.
    ({List<String> app, List<String> router}) logsOf(_AppLog log, FakeKeysRouter r) => (
          app: [for (final m in log.messages) if (m.startsWith('Widget key:')) m],
          router: [for (final c in r.client.commands) if (c.startsWith('logger -t ')) c],
        );

    // One line to each, the same words, and none of the key.
    void expectBothLogs(({List<String> app, List<String> router}) l, Object words, {Uint8List? key}) {
      expect(l.app, hasLength(1), reason: 'one app log line');
      expect(l.router, hasLength(1), reason: 'one router log line');
      expect(l.app.single, words);
      expect(l.router.single, buildLoggerCommand(l.app.single), reason: 'the router is told what the app log says');
      if (key != null) {
        final blob = sshKeyBlob(_line(key))!;
        expect(l.app.single, isNot(contains(blob)));
        expect(l.router.single, isNot(contains(blob)));
      }
    }

    test('GENERATE: the install, with how many keys the router holds now', () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(9))}');
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).install(_line(_key(7)));
      expectBothLogs(logsOf(log, r), 'Widget key: installed on the router; 2 widget keys there now', key: _key(7));
      expect(log.kinds['Widget key: installed on the router; 2 widget keys there now'], 'success');
    });

    test('GENERATE on a phone that had a key: the replacement', () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(5))}');
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).install(_line(_key(7)), replacing: _key(5));
      expectBothLogs(logsOf(log, r), 'Widget key: replaced this phone\'s previous key on the router; 1 widget key there now', key: _key(5));
    });

    test('GENERATE the router did not keep: the failure, with the reason', () async {
      final r = FakeKeysRouter(kTheirLine, keeps: false);
      final log = _AppLog();
      await expectLater(WidgetKeyRouterService(r.client, onLog: log.call).install(_line(_key(7))), throwsA(isA<WidgetKeyRouterException>()));
      final l = logsOf(log, r);
      expectBothLogs(l, startsWith('Widget key: install failed - '), key: _key(7));
      expect(log.kinds[l.app.single], 'error');
    });

    test('REMOVE: how many keys came off', () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(5))}\n${_line(_key(9))}\n${_line(_key(7))}');
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).removeAll();
      expectBothLogs(logsOf(log, r), 'Widget key: removed 3 widget keys from the router', key: _key(5));
    });

    test('REMOVE with none there is logged too, since it was asked for', () async {
      final r = FakeKeysRouter(kTheirLine);
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).removeAll();
      expectBothLogs(logsOf(log, r), 'Widget key: none on the router to remove');
    });

    test('REMOVE a key stayed on: the failure', () async {
      final r = FakeKeysRouter(_line(_key(5)), keeps: false);
      final log = _AppLog();
      await expectLater(WidgetKeyRouterService(r.client, onLog: log.call).removeAll(), throwsA(isA<WidgetKeyRouterException>()));
      expectBothLogs(logsOf(log, r), startsWith('Widget key: removal failed - '), key: _key(5));
    });

    test("a connection's housekeeping, when it changes something, is logged; when it changes nothing, it is not", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(7))}');
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).keepCurrent(ownKey: _key(7));
      expectBothLogs(logsOf(log, r), startsWith('Widget key: updated on the router - '), key: _key(7));

      final still = FakeKeysRouter(kTheirLine);
      final quiet = _AppLog();
      await WidgetKeyRouterService(still.client, onLog: quiet.call).keepCurrent(ownKey: _key(7));
      final l = logsOf(quiet, still);
      expect(l.app, isEmpty);
      expect(l.router, isEmpty);
    });

    test("a housekeeping check that fails goes to the router's log, and to the caller to put in the app log", () async {
      final r = FakeKeysRouter('$kTheirLine\n${_line(_key(7))}');
      r.client.failWith['nvram set sshd_authkeys'] = 'nvram: write failed';
      final log = _AppLog();
      await expectLater(WidgetKeyRouterService(r.client, onLog: log.call).keepCurrent(ownKey: _key(7)), throwsA(isA<Object>()));
      final l = logsOf(log, r);
      expect(l.app, isEmpty, reason: 'the caller logs the failure to the app log, so not twice');
      // A long reason goes to syslog in numbered pieces, in one command.
      expect(l.router.single, contains('Widget key: check failed - '));
      expect(l.router.single, isNot(contains(sshKeyBlob(_line(_key(7)))!)), reason: 'the error text has the key redacted');
    });

    test("a router that can't take the log line doesn't stop the change, and the app log still has it", () async {
      final r = FakeKeysRouter(kTheirLine);
      r.client.failWith['logger -t'] = 'logger: not found';
      final log = _AppLog();
      await WidgetKeyRouterService(r.client, onLog: log.call).install(_line(_key(7)));
      expect(widgetKeyLineCount(r.nv), 1, reason: 'the key is installed');
      expect(logsOf(log, r).app, hasLength(1));
    });
  });
}

/// What a service sent to its `onLog`, in order, and the kind of each message.
class _AppLog {
  final List<String> messages = [];
  final Map<String, String> kinds = {};

  void call(String message, {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    messages.add(message);
    if (isError) {
      kinds[message] = 'error';
    } else if (isSuccess) {
      kinds[message] = 'success';
    } else {
      kinds[message] = isWarning ? 'warning' : 'info';
    }
  }
}
