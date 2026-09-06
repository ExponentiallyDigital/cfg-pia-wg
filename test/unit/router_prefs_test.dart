// test/unit/router_prefs_test.dart - the app's only persisted value, and the rules around it.
//
// Storing anything at all is a departure for this app, so the tests are less about "does the write
// work" and more about the promises that make the departure acceptable:
//
//   - only a value that looks like a LAN address is ever accepted, in either direction, because
//     the file is hand-editable on a rooted device and its contents end up in an SSH connect;
//   - a failed or rejected write leaves the previous value alone rather than half-clearing it;
//   - wipeAll does NOT delete it - that is deliberate, and a future "tidy up wipeAll" change that
//     quietly adds it should fail here rather than silently break the feature;
//   - nothing but the address is ever written, enforced by reading router_prefs.dart itself.
import 'dart:io';

import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late RouterPrefs prefs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('router_prefs_test');
    prefs = RouterPrefs(directory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('RouterPrefs', () {
    test('nothing stored yet reads as empty', () async {
      expect(await prefs.load(), '');
    });

    test('a remembered address survives a round trip', () async {
      expect(await prefs.remember('192.168.1.1'), '192.168.1.1');
      expect(await prefs.load(), '192.168.1.1');
      expect(File('${dir.path}/$kRouterPrefsFile').existsSync(), isTrue);
    });

    test('surrounding whitespace is trimmed on the way in and the way out', () async {
      await prefs.remember('  192.168.1.1  ');
      expect(await prefs.load(), '192.168.1.1');
      File('${dir.path}/$kRouterPrefsFile').writeAsStringSync('192.168.1.1\n');
      expect(await prefs.load(), '192.168.1.1');
    });

    test('a hostname is accepted - not everyone connects by address', () async {
      expect(await prefs.remember('my-router.lan'), 'my-router.lan');
      expect(await prefs.load(), 'my-router.lan');
    });

    test('forget deletes the file, and forgetting nothing is not an error', () async {
      await prefs.remember('192.168.1.1');
      await prefs.forget();
      expect(await prefs.load(), '');
      expect(File('${dir.path}/$kRouterPrefsFile').existsSync(), isFalse);
      await prefs.forget(); // second call must not throw
    });

    // The file is plain text on disk. A value that reaches a shell command must not be able to
    // carry anything but an address, so both the write and the read reject the same shapes.
    for (final bad in <String>[
      '',
      '   ',
      '192.168.1.1; rm -rf /',
      r'$(reboot)',
      '192.168.1.1 && reboot',
      'host name',
      '-starts-with-a-dash',
      'a/b',
      "1.1.1.1'",
    ]) {
      test('rejects ${bad.isEmpty ? '(empty)' : bad}', () async {
        expect(await prefs.remember(bad), '', reason: 'remember must refuse it');
        File('${dir.path}/$kRouterPrefsFile').writeAsStringSync(bad);
        expect(await prefs.load(), '', reason: 'load must refuse it even if it is already on disk');
      });
    }

    test('an over-long value is refused rather than truncated', () async {
      expect(await prefs.remember('a' * 64), '');
    });

    test('a read from an unreachable directory is empty, not an exception', () async {
      final broken = RouterPrefs(directory: () async => throw const FileSystemException('no such volume'));
      expect(await broken.load(), '');
      expect(await broken.remember('192.168.1.1'), '');
      await broken.forget(); // must not throw
    });
  });

  group('SessionController', () {
    // clipboardWriter: wipeAll clears the clipboard, and the real writer needs a platform channel.
    SessionController make() => SessionController(routerPrefs: prefs, clipboardWriter: (_) async {});

    test('prefill is session value, then remembered, then the factory default', () async {
      final c = make();
      expect(c.routerIpPrefill, kDefaultRouterIp);

      await prefs.remember('192.168.1.1');
      await c.loadRememberedRouterIp();
      expect(c.routerIpPrefill, '192.168.1.1');

      c.routerIp = '192.168.1.2';
      expect(c.routerIpPrefill, '192.168.1.2');
    });

    test('the shipped default is the ASUS factory address, not anyone real', () {
      // Guards the privacy fix in build 410: a maintainer's own router address must not be the
      // value the app ships with. See .claude/CONTEXT.md.
      expect(kDefaultRouterIp, '192.168.50.1');
    });

    test('remembering logs it once, and re-remembering the same address stays quiet', () async {
      final c = make();
      await c.rememberRouterIp('192.168.1.1');
      expect(c.rememberedRouterIp, '192.168.1.1');
      final logged = c.log.where((e) => e.message.contains('remembered')).length;
      expect(logged, 1);

      await c.rememberRouterIp('192.168.1.1');
      expect(c.log.where((e) => e.message.contains('remembered')).length, 1);
    });

    test('a rejected address leaves the previous one in place', () async {
      final c = make();
      await c.rememberRouterIp('192.168.1.1');
      await c.rememberRouterIp('not a host');
      expect(c.rememberedRouterIp, '192.168.1.1');
      expect(await prefs.load(), '192.168.1.1');
    });

    test('forgetRouterIp clears both the field and the file', () async {
      final c = make();
      await c.rememberRouterIp('192.168.1.1');
      await c.forgetRouterIp();
      expect(c.rememberedRouterIp, '');
      expect(await prefs.load(), '');
    });

    test('wipeAll clears every credential but NOT the remembered address', () async {
      final c = make()
        ..piaUsername = 'p1234567'
        ..piaPassword = 'secret'
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'secret';
      await c.rememberRouterIp('192.168.1.1');

      await c.wipeAll();

      expect(c.piaUsername, '');
      expect(c.piaPassword, '');
      expect(c.routerIp, '');
      expect(c.sshUsername, '');
      expect(c.sshPassword, '');
      // Deliberate: wiping it on every exit would make storing it pointless. It is not a credential.
      expect(c.rememberedRouterIp, '192.168.1.1');
      expect(await prefs.load(), '192.168.1.1');
      // ...and it is what the form comes back with.
      expect(c.routerIpPrefill, '192.168.1.1');
    });
  });

  // The whole security argument for persisting anything rests on it being ONE non-secret value.
  // A password written here would survive wipeAll, survive an app close, and sit in plain text -
  // so the source itself is checked rather than trusting the next author to remember.
  test('router_prefs.dart persists the address and nothing else', () {
    // The prose in that file explains at length why a password must never go in it, so scan the
    // code and not the comments.
    final src = File('lib/router_prefs.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final writes = RegExp(r'writeAsString\w*\(([^)]*)\)').allMatches(src).map((m) => m.group(1)!).toList();
    expect(writes, ['value, flush: true'], reason: 'the only write must be the validated address');

    for (final forbidden in ['assword', 'sshUsername', 'piaUsername', 'secret', 'token', 'priv']) {
      expect(src.contains(forbidden), isFalse, reason: 'router_prefs.dart must never touch $forbidden');
    }
  });
}
