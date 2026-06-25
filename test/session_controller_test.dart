// test/session_controller_test.dart - unit tests for the shared SessionController.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';

void main() {
  group('logging', () {
    test('logEntry timestamps and stores the message; onLog is an adapter', () {
      final c = SessionController(clipboardWriter: (_) async {});
      var notifications = 0;
      c.addListener(() => notifications++);

      c.logEntry('hello');
      c.onLog('boom', isError: true);

      expect(c.log.length, 2);
      expect(c.log[0].message, matches(r'^\[\d{2}:\d{2}:\d{2}\] hello$'));
      expect(c.log[0].isError, isFalse);
      expect(c.log[1].isError, isTrue);
      expect(notifications, 2);
      c.dispose();
    });

    test('clearLog empties the log', () {
      final c = SessionController(clipboardWriter: (_) async {});
      c.logEntry('a');
      c.clearLog();
      expect(c.log, isEmpty);
      c.dispose();
    });
  });

  group('clipboard', () {
    test('copyToClipboard writes the text and arms the countdown', () async {
      final writes = <String>[];
      final c = SessionController(clipboardTimeout: const Duration(seconds: 3), clipboardWriter: (t) async => writes.add(t));
      await c.copyToClipboard('cfg-data');
      expect(writes, ['cfg-data']);
      expect(c.clipboardSeconds, 3);
      c.dispose();
    });

    test('clearClipboard writes empty and logs only when previously armed', () async {
      final writes = <String>[];
      final c = SessionController(clipboardWriter: (t) async => writes.add(t));

      // Not armed -> clears silently.
      await c.clearClipboard();
      expect(writes, ['']);
      expect(c.log, isEmpty);

      // Armed -> clears and logs.
      await c.copyToClipboard('secret');
      await c.clearClipboard();
      expect(writes, ['', 'secret', '']);
      expect(c.log.any((e) => e.message.contains('Clipboard auto cleared')), isTrue);
      c.dispose();
    });
  });

  group('wipeAll', () {
    test('clears all credentials, config and clipboard and logs', () async {
      final writes = <String>[];
      final c = SessionController(clipboardWriter: (t) async => writes.add(t));
      c
        ..piaUsername = 'u'
        ..piaPassword = 'p'
        ..dns = '8.8.8.8'
        ..routerIp = '192.168.0.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..generatedConfig = '[Interface]'
        ..generatedRegionId = 'aus_melbourne';

      await c.wipeAll();

      expect(c.piaUsername, isEmpty);
      expect(c.piaPassword, isEmpty);
      expect(c.routerIp, isEmpty);
      expect(c.sshUsername, isEmpty);
      expect(c.sshPassword, isEmpty);
      expect(c.generatedConfig, isNull);
      expect(c.generatedRegionId, isEmpty);
      expect(c.dns, kDefaultDns);
      expect(writes, contains(''));
      expect(c.log.any((e) => e.message.contains('wiped from memory')), isTrue);
      c.dispose();
    });
  });

  group('inactivity timer', () {
    test('reset arms the countdown', () async {
      final c = SessionController(
        inactivityTimeout: const Duration(seconds: 10),
        tickInterval: const Duration(milliseconds: 20),
        clipboardWriter: (_) async {},
      );
      c.resetActivity();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(c.inactivitySeconds, inInclusiveRange(8, 10));
      c.dispose();
    });

    test('expiry wipes the session and fires the callback', () async {
      var fired = false;
      final c = SessionController(
        inactivityTimeout: const Duration(milliseconds: 60),
        tickInterval: const Duration(milliseconds: 20),
        clipboardWriter: (_) async {},
      );
      c.onInactivityExpire = () => fired = true;
      c.piaUsername = 'u';
      c.resetActivity();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(fired, isTrue);
      expect(c.piaUsername, isEmpty);
      expect(c.log.any((e) => e.message.contains('inactivity')), isTrue);
      c.dispose();
    });
  });

  group('modal depth', () {
    test('enter/exit tracks depth and modalsOpen', () {
      final c = SessionController(clipboardWriter: (_) async {});
      expect(c.modalsOpen, isFalse);
      c.enterModal();
      c.enterModal();
      expect(c.modalDepth, 2);
      expect(c.modalsOpen, isTrue);
      c.exitModal();
      expect(c.modalDepth, 1);
      c.exitModal();
      c.exitModal(); // never goes negative
      expect(c.modalDepth, 0);
      expect(c.modalsOpen, isFalse);
      c.dispose();
    });
  });
}
