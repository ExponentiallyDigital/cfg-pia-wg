// test/unit/syslog_split_test.dart - the router log has to carry the whole message.
//
// Reported: the SMTP probe output stopped mid-word in the router syslog ("SSL handshake has read
// 4104 byt"). BusyBox syslogd truncates a long message, and the diagnostics that matter most are
// exactly the long ones - so a single `logger` call was losing the tail of the evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';

void main() {
  group('splitForSyslog', () {
    test('a short message is passed through untouched, with no part marker', () {
      expect(splitForSyslog('Enabled wgc1:pia-aus_melbourne'), ['Enabled wgc1:pia-aus_melbourne']);
    });

    test('a message at the limit is still one piece', () {
      final exact = 'x' * kSyslogChunkChars;
      expect(splitForSyslog(exact), [exact]);
    });

    test('a long message is numbered and nothing is dropped', () {
      final words = List.generate(120, (i) => 'word$i').join(' ');
      final parts = splitForSyslog(words);

      expect(parts.length, greaterThan(1));
      for (var i = 0; i < parts.length; i++) {
        expect(parts[i], startsWith('(${i + 1}/${parts.length}) '));
        expect(parts[i].length, lessThanOrEqualTo(kSyslogChunkChars + 12), reason: 'the marker is small');
      }
      // Strip the markers and the text must come back whole.
      final rejoined = parts.map((p) => p.replaceFirst(RegExp(r'^\(\d+/\d+\) '), '')).join(' ');
      expect(rejoined, words);
    });

    // The diagnostics join a command's output with '|', so that is the most useful break point.
    test('prefers a line boundary, keeping the separator with the part it ends', () {
      final lines = List.generate(20, (i) => 'diagnostic line number $i says something').join('|');
      final parts = splitForSyslog(lines);

      expect(parts.length, greaterThan(1));
      for (final p in parts.take(parts.length - 1)) {
        expect(p, endsWith('|'), reason: 'a part should end on a line boundary where one is near');
      }
      final rejoined = parts.map((p) => p.replaceFirst(RegExp(r'^\(\d+/\d+\) '), '')).join();
      expect(rejoined, lines);
    });

    test('splits between words, not through them', () {
      final parts = splitForSyslog(List.generate(60, (i) => 'alpha').join(' '));
      for (final p in parts) {
        expect(p, isNot(endsWith('alph')), reason: 'a word was cut in half');
      }
    });

    test('an unbroken run is cut square rather than growing past the limit', () {
      // A URL or a base64 blob has no spaces to break on; the limit still has to hold.
      final solid = 'a' * (kSyslogChunkChars * 3);
      final parts = splitForSyslog(solid);

      expect(parts.length, 3);
      for (final p in parts) {
        expect(p.replaceFirst(RegExp(r'^\(\d+/\d+\) '), '').length, lessThanOrEqualTo(kSyslogChunkChars));
      }
    });
  });

  group('buildLoggerCommand', () {
    test('one logger call for a short message', () {
      final cmd = buildLoggerCommand('Disabled wgc1');
      expect(cmd, "logger -t cfg-pia-wg 'Disabled wgc1'");
      expect(cmd, isNot(contains(';')));
    });

    test('a long message becomes several logger calls in ONE command', () {
      final cmd = buildLoggerCommand(List.generate(120, (i) => 'word$i').join(' '));

      expect('; '.allMatches(cmd).length, greaterThan(0));
      // One SSH round trip, however many parts - and every part goes to the same tag.
      expect('logger -t cfg-pia-wg '.allMatches(cmd).length, greaterThan(1));
      expect(cmd, contains("'(1/"));
    });

    test('quotes are escaped so a message can never break out of the command', () {
      final cmd = buildLoggerCommand("it's fine");
      expect(cmd, contains(r"'it'\''s fine'"));
    });
  });
}
