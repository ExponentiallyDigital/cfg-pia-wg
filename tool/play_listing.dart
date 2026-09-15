// tool/play_listing.dart - checks the Play Store listing text and writes what gets sent (ID-045).
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Run by play_listing.yml: `dart tool/play_listing.dart --out listing.json`.
//
// The same text is counted and sent: the check writes the request body, so nothing between the
// check and the upload can change a character. A failed check writes nothing and exits 1, which
// stops the workflow before it talks to Google Play.

import 'dart:convert';
import 'dart:io';

/// Where the listing text lives, as the maintainer edits it.
const String kFullDescriptionPath = 'play-store/description.md';
const String kShortDescriptionPath = 'play-store/description_short.md';

/// The store listing language the workflow updates.
const String kListingLanguage = 'en-AU';

/// Google Play's own limit on the full description.
const int kPlayFullDescriptionLimit = 4000;

/// The most this workflow accepts. Deliberately one under Play's limit: it stops at 4,000 or more.
const int kFullDescriptionMax = kPlayFullDescriptionLimit - 1;

/// Google Play's limit on the short description, accepted in full: every character counts there.
const int kShortDescriptionMax = 80;

/// The text as it is sent: line endings made LF and the file's leading and trailing blank space
/// dropped, so an editor's final newline is not counted or uploaded.
String listingText(String raw) => raw.replaceAll('\r\n', '\n').trim();

/// Characters as Google Play counts them: Unicode code points, not UTF-16 units.
int characterCount(String text) => text.runes.length;

String _n(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Why the listing must not be sent, or an empty list when it can be.
List<String> checkListing({required String full, required String short}) {
  final errors = <String>[];
  final fullCount = characterCount(full);
  final shortCount = characterCount(short);

  if (fullCount == 0) {
    errors.add('$kFullDescriptionPath is empty. Nothing was sent to Google Play.');
  } else if (fullCount > kFullDescriptionMax) {
    errors.add('$kFullDescriptionPath is ${_n(fullCount)} characters. This workflow stops at '
        '${_n(kPlayFullDescriptionLimit)} or more, to stay inside Google Play\'s ${_n(kPlayFullDescriptionLimit)}-character '
        'limit, so the most it accepts is ${_n(kFullDescriptionMax)} and this is ${_n(fullCount - kFullDescriptionMax)} '
        'over. Nothing was sent to Google Play.');
  }

  if (shortCount == 0) {
    errors.add('$kShortDescriptionPath is empty. Nothing was sent to Google Play.');
  } else if (shortCount > kShortDescriptionMax) {
    errors.add('$kShortDescriptionPath is ${_n(shortCount)} characters. Google Play allows at most '
        '${_n(kShortDescriptionMax)}, so this is ${_n(shortCount - kShortDescriptionMax)} over. '
        'Nothing was sent to Google Play.');
  }
  return errors;
}

/// The body for the Android Publisher API's `edits.listings.patch`.
String listingRequestBody({required String full, required String short}) => jsonEncode({
      'language': kListingLanguage,
      'fullDescription': full,
      'shortDescription': short,
    });

void main(List<String> args) {
  final outAt = args.indexOf('--out');
  final out = outAt >= 0 && outAt + 1 < args.length ? args[outAt + 1] : '';
  if (out.isEmpty) {
    stderr.writeln('usage: dart tool/play_listing.dart --out listing.json');
    exit(2);
  }

  String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('::error::$path does not exist. Nothing was sent to Google Play.');
      exit(1);
    }
    return listingText(file.readAsStringSync());
  }

  final full = read(kFullDescriptionPath);
  final short = read(kShortDescriptionPath);
  stdout.writeln('$kFullDescriptionPath: ${_n(characterCount(full))} of at most ${_n(kFullDescriptionMax)} characters');
  stdout.writeln('$kShortDescriptionPath: ${_n(characterCount(short))} of at most ${_n(kShortDescriptionMax)} characters');

  final errors = checkListing(full: full, short: short);
  if (errors.isNotEmpty) {
    for (final e in errors) {
      stdout.writeln('::error::$e');
    }
    exit(1);
  }
  File(out).writeAsStringSync(listingRequestBody(full: full, short: short));
  stdout.writeln('Listing text for $kListingLanguage is within the limits.');
}
