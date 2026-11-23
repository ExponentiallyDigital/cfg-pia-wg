// test/unit/changelog_current_hook_test.dart - the hooks that keep CHANGE-PROCESS.md section 1 from being
// forgotten (ID-649).
//
// Rule: as soon as source code or markdown that relates to a work item changes, the item moves to CHANGELOG.md's
// current block. scripts/check-changelog-current.sh is what the two Claude Code hooks run: `edit` after an Edit
// or a Write, `stop` at the end of a turn. These run it in a throwaway git repository, as the hooks do.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kScript = 'scripts/check-changelog-current.sh';
const String kChangelog = 'CHANGELOG.md';
const String kReminder = 'CHANGE-PROCESS CHECK';
const String kBlock = '"decision":"block"';

bool _toolsPresent() {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0 &&
        Process.runSync('jq', ['--version']).exitCode == 0 &&
        Process.runSync('sh', ['-c', 'true']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// A repository with one commit holding CHANGELOG.md, BACKLOG.md, a plan file, a source file and a document.
Directory _repo() {
  // The canonical path: Windows can hand back a short 8.3 temp name that git then spells another way.
  final dir = Directory(Directory.systemTemp.createTempSync('changelog_hook_').resolveSymbolicLinksSync());
  void write(String path, String text) {
    final f = File('${dir.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  write(kChangelog, '# CHANGELOG.md\n');
  write('BACKLOG.md', '# BACKLOG.md\n');
  write('.claude/plans/plan_x.md', '# plan\n');
  write('lib/a.dart', '// a\n');
  write('README.md', '# readme\n');
  for (final args in [
    ['init', '-q'],
    ['config', 'user.email', 'test@example.com'],
    ['config', 'user.name', 'Test'],
    ['add', '-A'],
    ['commit', '-q', '-m', 'first'],
  ]) {
    final r = Process.runSync('git', args, workingDirectory: dir.path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }
  return dir;
}

void _touch(Directory repo, String path) =>
    File('${repo.path}/$path').writeAsStringSync('changed ${DateTime.now().microsecondsSinceEpoch}\n', mode: FileMode.append);

/// The script's stdout for [mode], run inside [repo] with [stdin] on its standard input.
String _run(Directory repo, String mode, {String stdin = '{}'}) {
  final script = File(kScript).absolute.path.replaceAll(r'\', '/');
  // Process.runSync has no stdin, and a JSON argument with backslashes does not survive a Windows command
  // line: put it in a file outside the repository and redirect that.
  final input = File('${repo.parent.path}/${repo.uri.pathSegments.where((s) => s.isNotEmpty).last}.stdin')..writeAsStringSync(stdin);
  try {
    final inputPath = input.path.replaceAll(r'\', '/');
    final r = Process.runSync('sh', ['-c', 'sh "\$1" "\$2" < "\$3"', 'x', script, mode, inputPath], workingDirectory: repo.path, stdoutEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return '${r.stdout}';
  } finally {
    input.deleteSync();
  }
}

String _editJson(Directory repo, String relative) => jsonEncode({
      'tool_input': {'file_path': '${repo.path.replaceAll(r'\', '/')}/$relative'}
    });

void main() {
  final ok = _toolsPresent();
  final skip = ok ? false : 'needs git, jq and sh';
  late Directory repo;

  setUp(() {
    if (ok) repo = _repo();
  });
  tearDown(() {
    if (ok) repo.deleteSync(recursive: true);
  });

  group('the stop hook', () {
    test('says nothing when nothing has changed', () {
      expect(_run(repo, 'stop'), isEmpty);
    });

    test('blocks when source changed and CHANGELOG.md did not, naming the file', () {
      _touch(repo, 'lib/a.dart');
      final out = _run(repo, 'stop');
      expect(out, contains(kBlock));
      expect(out, contains('a.dart'));
    });

    test('blocks for a changed document too, but not for BACKLOG.md or a plan file', () {
      _touch(repo, 'README.md');
      expect(_run(repo, 'stop'), contains(kBlock));
    });

    test('is satisfied once CHANGELOG.md has changed', () {
      _touch(repo, 'lib/a.dart');
      _touch(repo, kChangelog);
      expect(_run(repo, 'stop'), isEmpty);
    });

    test('ignores BACKLOG.md and plan files, which create and move no item', () {
      _touch(repo, 'BACKLOG.md');
      _touch(repo, '.claude/plans/plan_x.md');
      expect(_run(repo, 'stop'), isEmpty);
    });

    test('lets the turn end the second time, so it can never loop', () {
      _touch(repo, 'lib/a.dart');
      expect(_run(repo, 'stop', stdin: '{"stop_hook_active":true}'), isEmpty);
    });
  }, skip: skip);

  group('the edit hook', () {
    test('reminds Claude after a source file or a document is edited', () {
      expect(_run(repo, 'edit', stdin: _editJson(repo, 'lib/a.dart')), contains(kReminder));
      expect(_run(repo, 'edit', stdin: _editJson(repo, 'README.md')), contains(kReminder));
      expect(_run(repo, 'edit', stdin: _editJson(repo, 'lib/a.dart')), contains('add it at the bottom of the block'), reason: 'the reminder says where the item goes');
    });

    test('stays quiet for BACKLOG.md, CHANGELOG.md, a plan file and a file outside the repository', () {
      for (final f in ['BACKLOG.md', kChangelog, '.claude/plans/plan_x.md']) {
        expect(_run(repo, 'edit', stdin: _editJson(repo, f)), isEmpty, reason: f);
      }
      expect(_run(repo, 'edit', stdin: jsonEncode({'tool_input': {'file_path': '/somewhere/else/notes.md'}})), isEmpty);
    });

    test('reads a Windows path, backslashes and either case of the drive letter', () {
      if (!Platform.isWindows) return;
      final win = repo.path.replaceAll('/', r'\');
      final flipped = win[0].toLowerCase() == win[0] ? win[0].toUpperCase() + win.substring(1) : win[0].toLowerCase() + win.substring(1);
      for (final base in [win, flipped]) {
        final out = _run(repo, 'edit', stdin: jsonEncode({'tool_input': {'file_path': '$base\\lib\\a.dart'}}));
        expect(out, contains(kReminder), reason: base);
      }
    });
  }, skip: skip);
}
