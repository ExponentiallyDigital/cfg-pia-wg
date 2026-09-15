// test/session_controller_test.dart - unit tests for the shared SessionController.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/watchdog_email.dart';

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

  // ID-004: the log is kept, always, up to the most a user can both see and copy. Past that the oldest
  // lines go, and the first line says how many and why.
  group('the log cap', () {
    // Every line is exactly 101 characters with its separator: an 11-character timestamp, 89 of text.
    String line(int i) => 'line ${i.toString().padLeft(3, '0')} '.padRight(89, '.');
    SessionController capped() => SessionController(clipboardWriter: (_) async {}, logCapChars: 5000);
    bool isMarker(LogEntry e) => e.message.startsWith('Log truncated by');

    test('under the cap nothing is dropped and there is no marker', () {
      final c = capped();
      for (var i = 0; i < 49; i++) {
        c.logEntry(line(i));
      }
      expect(c.log, hasLength(49));
      expect(c.log.where(isMarker), isEmpty);
      c.dispose();
    });

    test('over the cap the oldest go in one chunk, under a first line that says how many and why', () {
      final c = capped();
      for (var i = 0; i < 50; i++) {
        c.logEntry(line(i));
      }
      // 5,050 characters: six lines go, taking it to 4,444, just under 90% of the cap.
      expect(isMarker(c.log.first), isTrue);
      expect(c.log.first.isWarning, isTrue, reason: 'amber, like any other line worth noticing');
      expect(c.log.first.message, logTruncatedMessage(6));
      expect(c.log.first.message, contains('Log truncated by 6 lines'));
      expect(c.log.first.message, contains('cannot be recovered'));
      expect(c.log[1].message, contains('line 006'), reason: 'the oldest six went, in order');
      expect(c.log.last.message, contains('line 049'), reason: 'the newest stays');
      expect(c.log, hasLength(1 + 44));
      c.dispose();
    });

    test('trims in chunks, and keeps one marker with a running count', () {
      final c = capped();
      for (var i = 0; i < 51; i++) {
        c.logEntry(line(i));
      }
      expect(c.log.first.message, logTruncatedMessage(6), reason: 'the line after a trim does not trim again');

      for (var i = 51; i < 54; i++) {
        c.logEntry(line(i));
      }
      expect(c.log.where(isMarker), hasLength(1), reason: 'one marker, not one per trim');
      expect(c.log.first.message, logTruncatedMessage(12));
      expect(c.log.last.message, contains('line 053'));
      c.dispose();
    });

    test('the newest line stays even when it alone is over the cap', () {
      final c = capped()..logEntry('x' * 6000);
      expect(c.log, hasLength(1));
      expect(c.log.single.message, endsWith('x' * 6000));

      c.logEntry(line(1));
      expect(c.log.first.message, logTruncatedMessage(1));
      expect(c.log.first.message, contains('by 1 line:'), reason: 'singular');
      expect(c.log.last.message, contains('line 001'));
      c.dispose();
    });

    test('clearLog starts again: no marker, and a fresh count', () {
      final c = capped();
      for (var i = 0; i < 50; i++) {
        c.logEntry(line(i));
      }
      c.clearLog();
      for (var i = 0; i < 49; i++) {
        c.logEntry(line(i));
      }
      expect(c.log.where(isMarker), isEmpty);
      c.logEntry(line(49));
      expect(c.log.first.message, logTruncatedMessage(6), reason: 'counted from the clear, not from before it');
      c.dispose();
    });

    test('a controller built without a cap uses the measured one', () {
      final c = SessionController(clipboardWriter: (_) async {});
      final long = line(0);
      final fits = kLogCapChars ~/ (long.length + 12);
      for (var i = 0; i < fits; i++) {
        c.logEntry(long);
      }
      expect(c.log.where(isMarker), isEmpty);
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

    test('a non-secret copy writes the text but arms nothing', () async {
      final writes = <String>[];
      final c = SessionController(
          clipboardTimeout: const Duration(seconds: 1),
          tickInterval: const Duration(milliseconds: 10),
          clipboardWriter: (t) async => writes.add(t));

      await c.copyToClipboard('watchdog log', armAutoClear: false);
      expect(writes, ['watchdog log']);
      expect(c.clipboardSeconds, 0);

      // Past the timeout: nothing wipes the clipboard and nothing is logged.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(writes, ['watchdog log'], reason: 'the log must still be on the clipboard');
      expect(c.log, isEmpty);
      c.dispose();
    });

    // The reported bug: copy a watchdog log, open the conf screen, and it counts down over text
    // that is not a secret - then clears it.
    test('a non-secret copy stands down a countdown left by a secret one', () async {
      final writes = <String>[];
      final c = SessionController(
          clipboardTimeout: const Duration(seconds: 1),
          tickInterval: const Duration(milliseconds: 10),
          clipboardWriter: (t) async => writes.add(t));

      await c.copyToClipboard('[Interface] secret');
      expect(c.clipboardSeconds, greaterThan(0));

      await c.copyToClipboard('watchdog log', armAutoClear: false);
      expect(c.clipboardSeconds, 0, reason: 'the secret is no longer on the clipboard');

      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(writes, ['[Interface] secret', 'watchdog log']);
      expect(c.log, isEmpty, reason: 'nothing was auto cleared');
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
        ..generatedRegionId = 'aus_melbourne'
        ..watchdogEmail = const EmailSettings(to: 't@x.com', smtpServer: 'mail.x.com:465', smtpPass: 'p');

      await c.wipeAll();

      expect(c.piaUsername, isEmpty);
      expect(c.piaPassword, isEmpty);
      expect(c.routerIp, isEmpty);
      expect(c.sshUsername, isEmpty);
      expect(c.sshPassword, isEmpty);
      expect(c.generatedConfig, isNull);
      expect(c.generatedRegionId, isEmpty);
      expect(c.dns, kDefaultDns);
      expect(c.watchdogEmail, isNull, reason: 'the SMTP password goes with the rest (ID-050)');
      expect(writes, contains(''));
      expect(c.log.any((e) => e.message.contains('wiped from memory')), isTrue);
      c.dispose();
    });
  });

  group('routerConnected', () {
    test('is reset by wipeAll', () async {
      final c = SessionController(clipboardWriter: (_) async {});
      c.routerConnected = true;
      await c.wipeAll();
      expect(c.routerConnected, isFalse);
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
