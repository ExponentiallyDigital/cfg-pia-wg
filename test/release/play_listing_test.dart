// test/release/play_listing_test.dart - the Play Store listing check in play_listing.yml (ID-045).
//
// The full description stops at 4,000 characters or more, deliberately one under Google Play's limit;
// the short description accepts Play's 80 in full, because every character counts in that field.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/play_listing.dart';

String _chars(int n) => 'a' * n;

void main() {
  group('the full description', () {
    test('passes at 3,999 characters', () {
      expect(checkListing(full: _chars(3999), short: 'ok'), isEmpty);
    });

    test('stops at 4,000, saying why, how long it is and how far over', () {
      final errors = checkListing(full: _chars(4000), short: 'ok');
      expect(errors, hasLength(1));
      expect(errors.single, contains(kFullDescriptionPath));
      expect(errors.single, contains('is 4,000 characters'));
      expect(errors.single, contains('stops at 4,000 or more'));
      expect(errors.single, contains('this is 1 over'));
      expect(errors.single, contains('Nothing was sent to Google Play'));
    });

    test('reports the real distance over', () {
      expect(checkListing(full: _chars(4012), short: 'ok').single, contains('this is 13 over'));
    });

    test('an empty file is refused', () {
      expect(checkListing(full: '', short: 'ok').single, contains('$kFullDescriptionPath is empty'));
    });
  });

  group('the short description', () {
    test('passes at exactly 80 characters', () {
      expect(checkListing(full: 'ok', short: _chars(80)), isEmpty);
    });

    test('stops at 81, saying why, how long it is and how far over', () {
      final errors = checkListing(full: 'ok', short: _chars(81));
      expect(errors.single, contains(kShortDescriptionPath));
      expect(errors.single, contains('is 81 characters'));
      expect(errors.single, contains('at most 80'));
      expect(errors.single, contains('this is 1 over'));
    });

    test('both failing report both', () {
      expect(checkListing(full: _chars(5000), short: _chars(100)), hasLength(2));
    });
  });

  group('what is counted is what is sent', () {
    test('counts characters, not UTF-16 units', () {
      expect(characterCount('🙂🙂'), 2);
      expect(checkListing(full: 'ok', short: '🙂' * 80), isEmpty);
    });

    test('an editor\'s line endings and final newline are neither counted nor sent', () {
      expect(listingText('line one\r\nline two\r\n'), 'line one\nline two');
      expect(characterCount(listingText('${_chars(80)}\n')), 80);
    });

    test('the request body carries the language and both descriptions exactly', () {
      final body = jsonDecode(listingRequestBody(full: 'Full text.\nSecond line.', short: 'Short.')) as Map;
      expect(body, {'language': 'en-AU', 'fullDescription': 'Full text.\nSecond line.', 'shortDescription': 'Short.'});
    });
  });

  // The files as they stand, ready to upload (2026-09-15: 3,408 and 78 characters).
  test('the real listing files pass', () {
    final full = listingText(File(kFullDescriptionPath).readAsStringSync());
    final short = listingText(File(kShortDescriptionPath).readAsStringSync());
    expect(checkListing(full: full, short: short), isEmpty);
  });
}
