// tool/runsheet.dart - the part of TESTING.md a person has to do, top to bottom (ID-204, ID-210).
//
//   dart run tool/runsheet.dart [--set T=192.168.1.20 ...] > .claude/testing/<date>_e2e.md
//
// TESTING.md tags every test with where it runs: [hand], [script] (e2e.sh does the checking and
// you press the buttons), [ci] (an automated test covers it) or [retired]. This keeps Part 1's group
// headings and their start states, and every [hand] and [script] test, in order, each with a Result
// line to fill in. Everything [ci] or [retired], and Part 2, is left out, so nothing in the output
// is something a machine already does. --set fills in the router shell variables.
import 'dart:io';

/// Where a test runs, from the tag at the end of its title line.
enum Tier { hand, script, ci, retired }

final RegExp kTestTitle = RegExp(r'^\*\*([A-Z]{2,3}-\d+)\*\* (.*?)\s*\[(hand|script|ci|retired)\]\s*$');
final RegExp _anyTitle = RegExp(r'^\*\*([A-Z]{2,3}-\d+)\*\*');

class TestEntry {
  TestEntry(this.label, this.title, this.tier);
  final String label, title;
  final Tier tier;
}

/// Every test title in Part 1, with its tier. A title without exactly one tag is an error, and so is
/// a label used twice: both are how a run sheet quietly loses a test.
List<TestEntry> readTests(String md) {
  final out = <TestEntry>[];
  final seen = <String>{};
  for (final line in _part1(md).split('\n')) {
    if (!_anyTitle.hasMatch(line)) continue;
    final m = kTestTitle.firstMatch(line);
    final label = _anyTitle.firstMatch(line)!.group(1)!;
    if (m == null) throw FormatException('$label has no [hand], [script], [ci] or [retired] tag: $line');
    if (!seen.add(label)) throw FormatException('$label is used twice');
    out.add(TestEntry(label, m.group(2)!, Tier.values.byName(m.group(3)!)));
  }
  return out;
}

String _part1(String md) {
  final start = md.indexOf('# Part 1. Run sheet');
  final end = md.indexOf('# Part 2. Reference');
  if (start < 0) throw const FormatException('no "# Part 1. Run sheet" heading');
  return md.substring(start, end < 0 ? md.length : end);
}

/// The run sheet: the shell variables (with [vars] filled in), then each group's heading and
/// introduction, and its [hand] and [script] tests with a Result line under each.
String extractRunsheet(String md, {Map<String, String> vars = const {}, String title = 'Run sheet'}) {
  readTests(md); // fails loudly on a missing tag or a repeated label
  final part1 = _part1(md);
  final out = StringBuffer('# $title\n\nGenerated from TESTING.md by `dart run tool/runsheet.dart`. Only what you do: tests a machine already runs are left out. Write PASS, FAIL or SKIP on each Result line.\n\n');

  final varsBlock = RegExp(r'```bash\n(T=[\s\S]*?)```').firstMatch(part1);
  if (varsBlock != null) {
    var body = varsBlock.group(1)!;
    vars.forEach((k, v) {
      body = body.replaceAllMapped(RegExp('^$k=\\S+', multiLine: true), (_) => '$k=$v');
    });
    out.write('## Router shell variables\n\nSet these in every new SSH session to the router.\n\n```bash\n$body```\n\n');
  }

  // Groups start at "## <a name=...>". Within one, everything before the first test is its
  // introduction; each test runs from its title to the next title or the end of the group.
  final groups = part1.split(RegExp(r'\n(?=## <a name=)'));
  for (final group in groups.skip(1)) {
    final heading = group.split('\n').first;
    if (heading.contains("name='how-to-use'")) continue;
    final lines = group.trimRight().split('\n');
    final firstTest = lines.indexWhere(_anyTitle.hasMatch);
    final kept = <String>[];
    for (var i = firstTest < 0 ? lines.length : firstTest; i < lines.length;) {
      var j = i + 1;
      while (j < lines.length && !_anyTitle.hasMatch(lines[j])) {
        j++;
      }
      final m = kTestTitle.firstMatch(lines[i])!;
      final tier = Tier.values.byName(m.group(3)!);
      if (tier == Tier.hand || tier == Tier.script) {
        final body = lines.sublist(i, j).join('\n').trimRight().replaceAll(RegExp(r'\n---\s*$'), '').trimRight();
        kept.add('$body\n\n- Result:');
      }
      i = j;
    }
    if (kept.isEmpty) continue;
    final intro = lines.sublist(0, firstTest < 0 ? lines.length : firstTest).join('\n').trim();
    out.write('$intro\n\n${kept.join('\n\n')}\n\n---\n\n');
  }
  return out.toString();
}

void main(List<String> args) {
  final vars = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--set' && i + 1 < args.length) {
      final kv = args[++i].split('=');
      if (kv.length == 2) vars[kv[0]] = kv[1];
    }
  }
  stdout.write(extractRunsheet(File('TESTING.md').readAsStringSync(), vars: vars));
}
