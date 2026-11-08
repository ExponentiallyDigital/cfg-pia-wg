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

  // The text below review_notes.md's first `---` line, as scripts/app_store_connect.py sends it (ID-509):
  // the notes have a `---` line of their own (ID-541).
  final notesFile = File('app-store/review_notes.md').readAsStringSync();
  final notesStart = RegExp(r'^---\s*$', multiLine: true).firstMatch(notesFile)!.end;
  final notes = notesFile.substring(notesStart).trim();

  test('the review notes are within 4,000 characters', () {
    expect(length(notes), lessThanOrEqualTo(4000));
  });

  // App Review couldn't find the purchase on 2026-11-02: the notes name the way to it without a router.
  test('the review notes say how to reach the purchase without a router', () {
    for (final step in ['SETTINGS', 'MAX ACTIVE VPNS', 'UNLOCK FOR LIFE', 'RESTORE PURCHASE']) {
      expect(notes, contains(step), reason: step);
    }
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
