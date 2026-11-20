// test/unit/dns_map_test.dart - the DNS map in .claude/plans/plan_dns.md names only items that exist (ID-642).
//
// The plan is the one place that shows the DNS work items together. It holds relationships, not status, so
// nothing in it goes stale as an item progresses, but an ID that was mistyped, renumbered or removed would
// leave the map pointing at nothing. The map's first column is checked against BACKLOG.md and CHANGELOG.md, and
// the two older DNS plans must still link up to it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kHubPath = '.claude/plans/plan_dns.md';

/// The IDs in the first column of the table under "## The map" in [plan], in order.
List<String> mapIds(String plan) {
  final lines = plan.split(RegExp(r'\r?\n'));
  final start = lines.indexWhere((l) => l.startsWith('## The map'));
  if (start < 0) return const [];
  final ids = <String>[];
  for (var i = start + 1; i < lines.length && !lines[i].startsWith('## '); i++) {
    final m = RegExp(r'^\| (ID-\d{3,}) \|').firstMatch(lines[i]);
    if (m != null) ids.add(m.group(1)!);
  }
  return ids;
}

/// Whether [id] starts a bullet in [text], as every work item in BACKLOG.md and CHANGELOG.md does.
bool hasItem(String text, String id) => RegExp('^- $id ', multiLine: true).hasMatch(text);

void main() {
  final plan = File(kHubPath).readAsStringSync();
  final backlog = File('BACKLOG.md').readAsStringSync();
  final changelog = File('CHANGELOG.md').readAsStringSync();

  test('the map lists the DNS items, and each exists in BACKLOG.md or CHANGELOG.md', () {
    final ids = mapIds(plan);
    expect(ids, containsAll(['ID-641', 'ID-640', 'ID-639', 'ID-636', 'ID-594', 'ID-621']), reason: 'the open DNS items are on the map');
    final missing = [for (final id in ids) if (!hasItem(backlog, id) && !hasItem(changelog, id)) id];
    expect(missing, isEmpty, reason: 'the map names an item that is in neither file: $missing');
  });

  test('ID-641 points at the hub, and the older DNS plans link up to it', () {
    expect(backlog, contains('[plan_dns.md](.claude/plans/plan_dns.md)'));
    for (final f in ['plan_router-dns-slot.md', 'plan_dns-modes.md']) {
      expect(File('.claude/plans/$f').readAsStringSync(), contains('[plan_dns.md](plan_dns.md)'), reason: '$f links to the map');
    }
  });

  group('the check itself', () {
    test('IDs are read from the first column of the map only', () {
      const text = '# P\n\n## The map\n\n| Item | What |\n| --- | --- |\n| ID-641 | see ID-999 |\n| ID-640 | x |\n\n## Next\n\n| ID-111 | y |\n';
      expect(mapIds(text), ['ID-641', 'ID-640']);
    });

    test('a plan with no map has no IDs', () {
      expect(mapIds('# P\n\n## Other\n'), isEmpty);
    });

    test('an item is found only at the start of a bullet', () {
      expect(hasItem('- ID-641 ARC: x\n', 'ID-641'), isTrue);
      expect(hasItem('text mentioning ID-641 in prose\n', 'ID-641'), isFalse);
      expect(hasItem('- ID-6410 ARC: x\n', 'ID-641'), isFalse);
    });
  });
}
