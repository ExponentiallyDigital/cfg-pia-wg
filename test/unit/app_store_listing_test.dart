// test/unit/app_store_listing_test.dart - the App Store listing drafts stay within Apple's limits (ID-434),
// and name no other platform, which App Review refuses (guideline 2.3.10).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The value under `## <name> (...)` in app-store/listing.md.
String field(String listing, String name) {
  final m = RegExp('^## ${RegExp.escape(name)}[^\n]*\n\n(.*)\$', multiLine: true).firstMatch(listing);
  if (m == null) throw StateError('no "$name" in app-store/listing.md');
  return m.group(1)!;
}

void main() {
  final listing = File('app-store/listing.md').readAsStringSync();
  final description = File('app-store/description.md').readAsStringSync().trimRight();

  // Counted as Apple counts them: characters, not bytes.
  int length(String s) => s.runes.length;

  for (final (name, limit) in const [('Name', 30), ('Subtitle', 30), ('Promotional text', 170), ('Keywords', 100)]) {
    test('$name is within $limit characters', () {
      final value = field(listing, name);
      expect(value, isNotEmpty);
      expect(length(value), lessThanOrEqualTo(limit), reason: value);
    });
  }

  test('the description is within 4,000 characters', () {
    expect(length(description), lessThanOrEqualTo(4000));
  });

  test('keywords are separated by commas with no spaces after them', () {
    expect(field(listing, 'Keywords'), isNot(contains(', ')));
  });

  // Andrew's decision, 2026-10-20: one name on both stores, and the same under the icon.
  test('the App Store name is cfg-pia-wg, as on Play and under the icon', () {
    expect(field(listing, 'Name'), 'cfg-pia-wg');
    expect(File('ios/Runner/Info.plist').readAsStringSync(), contains('<string>cfg-pia-wg</string>'));
  });

  test('no other platform is named', () {
    for (final word in ['Android', 'Google', 'Play Store', 'Recent Apps']) {
      expect(description.contains(word) || listing.contains(word), isFalse, reason: word);
    }
  });
}
