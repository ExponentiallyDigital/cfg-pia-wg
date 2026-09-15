// test/release/release_notes_test.dart - the release notes release.yml publishes (ID-044).
//
// Reported: the GitHub release for v0.8.77 left out every entry from v0.8.75 and v0.8.76. Not every
// build is tagged, and the notes took only the tagged block. A release covers every block since the
// previous tag.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_notes.dart';

const _changelog = '''
# 1. CHANGELOG.md

- [1.3. Implemented - chronological change history](#13-implemented---chronological-change-history)

### 1.2. WIP

- ID-100 CHG: not released, and not history either.

### 1.3. Implemented - chronological change history

2026-09-15 v0.8.79 build 449 - in progress

- CHG: still being built.

2026-09-14 v0.8.77 build 447 - the tagged one

- FIX: from 447.
- ADD: also 447, written second.

2026-09-13 v0.8.76 build 446 - untagged

```play
Play text from 446.
```
- CHG: from 446.

2026-09-13 v0.8.75 build 445 - untagged too

- CHG: from 445.

2026-09-12 v0.8.74 build 444 - the previous tag

```play
Play text from 444.
```
- CHG: from 444, already released.

2026-09-12 v0.8.73 build 443 - older still

- CHG: from 443.
''';

void main() {
  group('the previous tag', () {
    test('is the highest version tag below the one being released', () {
      expect(previousTagOf('v0.8.77', ['v0.7.12', 'v0.8.74', 'v0.8.70', 'v0.8.77', 'v0.8.80']), 'v0.8.74');
    });

    test('compares numbers, not strings', () {
      expect(previousTagOf('v0.8.10', ['v0.8.9', 'v0.8.09', 'v0.7.99']), anyOf('v0.8.9', 'v0.8.09'));
      expect(previousTagOf('v0.10.0', ['v0.9.0', 'v0.8.99']), 'v0.9.0');
    });

    test('is null when nothing is below it', () {
      expect(previousTagOf('v0.8.74', ['v0.8.74', 'v0.8.77']), isNull);
      expect(previousTagOf('not-a-version', ['v0.8.74']), isNull);
    });
  });

  group('the GitHub release body', () {
    // The bug itself.
    test('covers every block since the previous tag, not only the tagged one', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.77', tags: ['v0.8.74', 'v0.8.77']);
      expect(notes.blocks.map((b) => b.version), ['v0.8.77', 'v0.8.76', 'v0.8.75']);
      expect(notes.github, contains('from 447.'));
      expect(notes.github, contains('from 446.'));
      expect(notes.github, contains('from 445.'));
      expect(notes.github, isNot(contains('from 444')), reason: 'the previous release already said it');
      expect(notes.github, isNot(contains('still being built')), reason: 'a newer block is not part of this release');
      expect(notes.errors, isEmpty);
      expect(notes.warnings, isEmpty);
    });

    test('keeps each block under its own heading, newest first, in the order written', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      final g = notes.github;
      expect(g.indexOf('v0.8.77 build 447'), lessThan(g.indexOf('v0.8.76 build 446')));
      expect(g.indexOf('v0.8.76 build 446'), lessThan(g.indexOf('v0.8.75 build 445')));
      expect(g.indexOf('FIX: from 447.'), lessThan(g.indexOf('ADD: also 447')), reason: 'not sorted');
      expect(g, startsWith('2026-09-14 v0.8.77 build 447 - the tagged one\n\n- FIX: from 447.'));
    });

    test('a release straight after the previous tag carries its own block only', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.74', tags: ['v0.8.73', 'v0.8.74']);
      expect(notes.blocks.map((b) => b.version), ['v0.8.74']);
    });

    test('leaves the ```play fence out of the GitHub body', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      expect(notes.github, isNot(contains('Play text')));
      expect(notes.github, isNot(contains('```')));
    });

    test('with no earlier tag it carries the tagged block only, and says so', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.77', tags: ['v0.8.77']);
      expect(notes.blocks.map((b) => b.version), ['v0.8.77']);
      expect(notes.previousTag, isNull);
      expect(notes.warnings, contains(contains('no version tag below v0.8.77')));
    });

    test('a tag with no block is loud, not a bare "Release <tag>"', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.9.0', tags: ['v0.8.77']);
      expect(notes.github, contains('No CHANGELOG block was found for this tag'));
      expect(notes.warnings, contains('no CHANGELOG block found for v0.9.0'));
    });

    // The table of contents carries the heading's words higher up the file.
    test('ignores the history heading when it appears in the table of contents', () {
      final history = parseHistory(_changelog);
      expect(history.first.version, 'v0.8.79');
      expect(history.map((b) => b.header).join(), isNot(contains('ID-100')));
    });
  });

  group('the Google Play what\'s new', () {
    test('uses the tagged block\'s own fence when it has one', () {
      final changelog = _changelog.replaceFirst(
        '- FIX: from 447.',
        '```play\nThe whole release, summarised.\n```\n- FIX: from 447.',
      );
      final notes = buildReleaseNotes(changelog: changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      expect(notes.play, 'The whole release, summarised.');
    });

    test('otherwise takes the fences of the other blocks the release covers', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      expect(notes.play, 'Play text from 446.');
      expect(notes.play, isNot(contains('444')), reason: 'the previous release already had that note');
    });

    test('with no fence anywhere, the changelog link and a warning', () {
      final notes = buildReleaseNotes(changelog: _changelog, targetTag: 'v0.8.75', tags: ['v0.8.74']);
      expect(notes.play, kPlayNoteFallback);
      expect(notes.warnings.single, contains('no ```play block'));
    });

    test('over 500 characters is an error, not a truncation', () {
      final long = 'x' * (kPlayNoteLimit + 1);
      final changelog = _changelog.replaceFirst('Play text from 446.', long);
      final notes = buildReleaseNotes(changelog: changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      expect(notes.errors.single, contains('${kPlayNoteLimit + 1} characters'));
    });

    test('counts characters, not UTF-16 units', () {
      final exactly = '🙂' * kPlayNoteLimit;
      final changelog = _changelog.replaceFirst('Play text from 446.', exactly);
      final notes = buildReleaseNotes(changelog: changelog, targetTag: 'v0.8.77', tags: ['v0.8.74']);
      expect(notes.errors, isEmpty);
    });
  });

  // The real file, the real case: v0.8.77 was tagged after v0.8.74.
  test('the real CHANGELOG: v0.8.77 carries 447, 446 and 445', () {
    final notes = buildReleaseNotes(
      changelog: File('CHANGELOG.md').readAsStringSync(),
      targetTag: 'v0.8.77',
      tags: ['v0.8.70', 'v0.8.74', 'v0.8.77'],
    );
    expect(notes.blocks.map((b) => b.version), ['v0.8.77', 'v0.8.76', 'v0.8.75']);
    expect(notes.errors, isEmpty);
  });
}
