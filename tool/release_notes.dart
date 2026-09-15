// tool/release_notes.dart - both release notes for a tag, out of CHANGELOG.md (ID-044).
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
// Run by release.yml: `dart run tool/release_notes.dart --tag v0.8.77`.
//
// ONE source, TWO audiences. Everything in the release's CHANGELOG blocks except the ```play fence
// becomes the GitHub release body, for someone reading a repository. The contents of that fence become
// the Google Play "what's new", for someone deciding whether to tap Update. They cannot be the same
// text: Play allows 500 Unicode characters per language, renders NO markdown, and does not make a URL
// tappable. Neither note is sorted - the order a block is written in carries meaning.
//
// A release covers every block since the PREVIOUS TAG, not only its own. Not every build is tagged:
// v0.8.77 followed v0.8.74, and when this took only the tagged block (commit 58fb480), the notes for
// v0.8.77 left out everything in v0.8.75 and v0.8.76. The previous tag is the highest version tag
// below the one being released, taken from git.

import 'dart:io';

/// Google Play's limit for the "what's new" text, in Unicode characters per language.
const int kPlayNoteLimit = 500;

/// What Play shows when no block in the release carries a ```play fence.
const String kPlayNoteFallback = 'Please see https://exponentiallydigital.com/cfg-pia-wg/changelog';

final RegExp _versionHeader = RegExp(r'^\d{4}-\d{2}-\d{2}\s+v\d+\.\d+\.\d+');
final RegExp _version = RegExp(r'v(\d+)\.(\d+)\.(\d+)');

/// One release block of the implemented history.
class ChangelogBlock {
  final String header;
  final String version;
  final List<String> body;
  final List<String> play;

  ChangelogBlock(this.header, this.version, this.body, this.play);
}

/// Both notes for a release, and what went wrong making them.
class ReleaseNotes {
  final String github;
  final String play;

  /// The blocks the release covers, newest first.
  final List<ChangelogBlock> blocks;

  /// The tag the release follows, or null when there is none below it.
  final String? previousTag;

  /// Worth a look, but the release can go ahead.
  final List<String> warnings;

  /// The release must not go ahead.
  final List<String> errors;

  ReleaseNotes(this.github, this.play, this.blocks, this.previousTag, this.warnings, this.errors);
}

List<int>? _parts(String tag) {
  final m = _version.firstMatch(tag);
  return m == null ? null : [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// The highest version tag in [tags] below [targetTag], or null when there is none.
String? previousTagOf(String targetTag, Iterable<String> tags) {
  final target = _parts(targetTag);
  if (target == null) return null;
  String? best;
  List<int>? bestParts;
  for (final tag in tags) {
    final parts = _parts(tag);
    if (parts == null || _compare(parts, target) >= 0) continue;
    if (bestParts == null || _compare(parts, bestParts) > 0) {
      best = tag;
      bestParts = parts;
    }
  }
  return best;
}

/// Every block under the implemented-history heading, newest first, as written.
List<ChangelogBlock> parseHistory(String changelog) {
  final blocks = <ChangelogBlock>[];
  var inHistory = false;
  var inPlay = false;
  for (final raw in changelog.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (!inHistory) {
      // Anchored to a HEADING and matched on its title, not its number: the number has changed once
      // already, and the table of contents carries the same words higher up the file.
      inHistory = line.startsWith('#') && line.contains('Implemented - chronological change history');
      continue;
    }
    if (_versionHeader.hasMatch(line.trim())) {
      final header = line.trim();
      blocks.add(ChangelogBlock(header, _version.firstMatch(header)!.group(0)!, [], []));
      inPlay = false;
      continue;
    }
    if (blocks.isEmpty) continue;
    final block = blocks.last;
    if (!inPlay && line.trim().startsWith('```play')) {
      inPlay = true;
    } else if (inPlay) {
      if (line.trim().startsWith('```')) {
        inPlay = false;
      } else {
        block.play.add(line);
      }
    } else {
      block.body.add(line);
    }
  }
  return blocks;
}

String _trimBlankEdges(List<String> lines) => lines.join('\n').trim();

/// Builds both notes for [targetTag] from [changelog], covering every block since the previous tag.
ReleaseNotes buildReleaseNotes({required String changelog, required String targetTag, required Iterable<String> tags}) {
  final warnings = <String>[];
  final errors = <String>[];
  final history = parseHistory(changelog);
  final previousTag = previousTagOf(targetTag, tags);
  final previous = previousTag == null ? null : _parts(previousTag);

  final start = history.indexWhere((b) => b.version == targetTag);
  final blocks = <ChangelogBlock>[];
  if (start >= 0) {
    blocks.add(history[start]);
    if (previous == null) {
      warnings.add('no version tag below $targetTag, so the notes carry its own CHANGELOG block only');
    } else {
      for (final block in history.skip(start + 1)) {
        final parts = _parts(block.version);
        // Older than or equal to the previous tag: that release has already said it.
        if (parts == null || _compare(parts, previous) <= 0) break;
        blocks.add(block);
      }
    }
  }

  // ---- GitHub release body ----
  final String github;
  if (blocks.isEmpty) {
    // Loud rather than quiet. A release with no notes is a mistake, and a bare "Release <tag>" made it
    // look deliberate.
    github = 'Release $targetTag\n\n> No CHANGELOG block was found for this tag. Check that CHANGELOG.md carries a '
        '`<date> $targetTag build <n> - <title>` heading under the implemented history.';
    warnings.add('no CHANGELOG block found for $targetTag');
  } else {
    github = blocks.map((b) => '${b.header}\n\n${_trimBlankEdges(b.body)}'.trimRight()).join('\n\n');
  }

  // ---- Google Play what's new ----
  // The release's own fence when it has one, since whoever wrote it could summarise every block the
  // release covers. Otherwise the fences of the older blocks it covers, newest first.
  var play = blocks.isEmpty ? '' : _trimBlankEdges(blocks.first.play);
  if (play.isEmpty) {
    play = blocks.skip(1).map((b) => _trimBlankEdges(b.play)).where((p) => p.isNotEmpty).join('\n');
  }
  if (play.isEmpty) {
    play = kPlayNoteFallback;
    warnings.add('no ```play block in the CHANGELOG blocks for $targetTag - Play gets the changelog link instead of real notes');
  } else if (play.runes.length > kPlayNoteLimit) {
    // Caught HERE rather than by Play rejecting the upload, or worse, silently truncating it.
    errors.add('the ```play note for $targetTag is ${play.runes.length} characters; Google Play allows $kPlayNoteLimit. '
        'Write one ```play block in the $targetTag block that covers the whole release.');
  }

  return ReleaseNotes(github, play, blocks, previousTag, warnings, errors);
}

List<String> _gitTags() {
  final result = Process.runSync('git', ['tag', '--list', 'v*']);
  if (result.exitCode != 0) return const [];
  return (result.stdout as String).split(RegExp(r'\r?\n')).where((t) => t.trim().isNotEmpty).toList();
}

void main(List<String> args) {
  final tagAt = args.indexOf('--tag');
  final targetTag = tagAt >= 0 && tagAt + 1 < args.length ? args[tagAt + 1] : '';
  if (targetTag.isEmpty) {
    stderr.writeln('usage: dart run tool/release_notes.dart --tag vX.Y.Z');
    exit(2);
  }

  final changelog = File('CHANGELOG.md');
  final notes = buildReleaseNotes(
    changelog: changelog.existsSync() ? changelog.readAsStringSync() : '',
    targetTag: targetTag,
    tags: _gitTags(),
  );

  File('github_release_notes.txt').writeAsStringSync(notes.github);
  Directory('distribution/whatsnew').createSync(recursive: true);
  File('distribution/whatsnew/whatsnew-en-AU').writeAsStringSync('${notes.play}\n');

  stdout.writeln('--- covers ${notes.blocks.map((b) => b.version).join(', ')} '
      '(since ${notes.previousTag ?? 'no earlier tag'}) ---');
  stdout.writeln('--- GitHub ---');
  stdout.writeln(notes.github);
  stdout.writeln('--- Google Play (${notes.play.runes.length}/$kPlayNoteLimit) ---');
  stdout.writeln(notes.play);
  for (final w in notes.warnings) {
    stdout.writeln('::warning::$w');
  }
  for (final e in notes.errors) {
    stdout.writeln('::error::$e');
  }
  if (notes.errors.isNotEmpty) exit(1);
}
