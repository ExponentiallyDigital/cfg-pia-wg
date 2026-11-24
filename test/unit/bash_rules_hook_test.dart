// test/unit/bash_rules_hook_test.dart - the hooks that make CLAUDE.md's working rules impossible to skip (ID-691).
//
// scripts/check-bash-rules.sh is what three Claude Code hooks run: `pre` before a Bash command, `post` after one,
// and `prompt` with each request. Andrew's review of 2026-11-23 found rules that were in files and still broken:
// code in bash heredocs, a push to CI before the full tests had run, a release commit without its play block.
// These run the script in a throwaway git repository, as the hooks do, and each denial is also run with the
// protection taken out, so the test can tell.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kScript = 'scripts/check-bash-rules.sh';
const String kDeny = '"permissionDecision":"deny"';
const String kHeader = '2026-11-23 v0.8.221 build 591 - the guides are simpler';
const String kSubject = 'v0.8.221 build 591 - the guides are simpler';

bool _toolsPresent() {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0 &&
        Process.runSync('jq', ['--version']).exitCode == 0 &&
        Process.runSync('sh', ['-c', 'true']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String _changelog({String header = kHeader, bool play = true}) => '# CHANGELOG.md\n\n## 1. Implemented\n\n$header\n\n'
    '${play ? '```play\n• A thing.\n• Full changelog https://example.invalid\n```\n\n' : ''}- ID-1 DOC: x.\n\n'
    '2026-11-22 v0.8.220 build 590 - the older one\n\n```play\n• Old.\n```\n';

/// A repository with one commit and its CHANGELOG.md, the full tests recorded as passed afterwards.
Directory _repo({String? changelog}) {
  final dir = Directory(Directory.systemTemp.createTempSync('bash_rules_').resolveSymbolicLinksSync());
  void write(String path, String text) {
    final f = File('${dir.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  write('CHANGELOG.md', changelog ?? _changelog());
  write('lib/a.dart', '// a\n');
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

/// The script's stdout for [mode] in [repo] with [stdin] on its standard input.
String _run(Directory repo, String mode, {String stdin = '{}'}) {
  final script = File(kScript).absolute.path.replaceAll(r'\', '/');
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

String _command(String command) => jsonEncode({
      'tool_input': {'command': command}
    });

String _result(String command, String output) => jsonEncode({
      'tool_input': {'command': command},
      'tool_response': {'stdout': output, 'stderr': ''}
    });

String _pre(Directory repo, String command) => _run(repo, 'pre', stdin: _command(command));

/// Records the full tests as passed, as the `post` hook does.
void _recordTestsPassed(Directory repo) {
  _run(repo, 'post', stdin: _result('flutter test --coverage > out.txt 2>&1; tail -3 out.txt', '00:12 +2600: All tests passed!'));
}

/// Changes a source file after the tests were recorded, in a later second.
Future<void> _changeAfterTests(Directory repo) async {
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  File('${repo.path}/lib/a.dart').writeAsStringSync('// changed\n', mode: FileMode.append);
}

void main() {
  final skip = _toolsPresent() ? null : 'git, jq and sh are needed';
  late Directory repo;

  setUp(() {
    if (skip == null) repo = _repo();
  });
  tearDown(() {
    if (skip == null) repo.deleteSync(recursive: true);
  });

  group('code in a heredoc', () {
    test('Python and Dart in a heredoc are denied, whichever way they are run', () {
      expect(_pre(repo, "python - <<'EOF'\nprint('x')\nEOF"), contains(kDeny));
      expect(_pre(repo, "python3 <<EOF\nprint(1)\nEOF"), contains(kDeny));
      expect(_pre(repo, "cat > test/unit/x_test.dart <<'EOF'\nvoid main() {}\nEOF"), contains(kDeny));
      expect(_pre(repo, "cat > tool/x.py <<'EOF'\nprint(1)\nEOF"), contains(kDeny));
      expect(_pre(repo, "node <<'JS'\nconsole.log(1)\nJS"), contains(kDeny));
    }, skip: skip);

    test('the denial says to use the Write tool', () {
      expect(_pre(repo, "python - <<'EOF'\nprint(1)\nEOF"), contains('Write tool'));
    }, skip: skip);

    test('a commit message in a heredoc, a shell heredoc and python without a heredoc are allowed', () {
      expect(_pre(repo, "echo hi <<'EOF'\nplain text\nEOF"), isEmpty);
      expect(_pre(repo, "cat > notes.txt <<'EOF'\nplain text\nEOF"), isEmpty);
      expect(_pre(repo, 'python -c "print(1)"'), isEmpty);
      expect(_pre(repo, 'dart run tool/release_notes.dart --tag v1.0.0'), isEmpty);
    }, skip: skip);
  });

  group('the full tests before a commit, a push and a dry run', () {
    test('with none recorded, a commit, a branch push and a release dry run are denied', () {
      expect(_pre(repo, 'git commit -m "$kSubject"'), contains(kDeny));
      expect(_pre(repo, 'git push origin dev'), contains(kDeny));
      expect(_pre(repo, 'gh workflow run release.yml --ref dev -f dry_run=true -f tag_name=v0.8.221'), contains(kDeny));
    }, skip: skip);

    test('recorded after the last change, all three are allowed', () {
      _recordTestsPassed(repo);
      expect(_pre(repo, 'git commit -m "$kSubject"'), isEmpty);
      expect(_pre(repo, 'git push origin dev'), isEmpty);
      expect(_pre(repo, 'gh workflow run release.yml --ref dev -f dry_run=true -f tag_name=v0.8.221'), isEmpty);
    }, skip: skip);

    test('a file changed after the tests passed makes them stale again', () async {
      _recordTestsPassed(repo);
      await _changeAfterTests(repo);
      expect(_pre(repo, 'git commit -m "$kSubject"'), allOf(contains(kDeny), contains('full flutter test')));
      expect(_pre(repo, 'git push origin dev'), contains(kDeny));
      expect(_pre(repo, 'gh workflow run release.yml --ref dev'), contains(kDeny));
    }, skip: skip);

    test('a change under .claude/ does not, since the tests do not read it', () async {
      _recordTestsPassed(repo);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      File('${repo.path}/.claude/notes.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      expect(_pre(repo, 'git push origin dev'), isEmpty);
    }, skip: skip);

    test('a tag push, a deletion and a promote carry no new code, so they are not held', () {
      expect(_pre(repo, 'git push origin v0.8.221'), isEmpty);
      expect(_pre(repo, 'git push origin --delete ci-test'), isEmpty);
      expect(_pre(repo, 'git push origin :refs/tags/v0.8.78'), isEmpty);
      expect(_pre(repo, 'gh workflow run promote.yml --ref main -f build=591'), isEmpty);
    }, skip: skip);

    test('a partial test run does not count, and a failed one does not', () {
      _run(repo, 'post', stdin: _result('flutter test test/unit/a_test.dart', 'All tests passed!'));
      expect(File('${repo.path}/.claude/full-test-passed').existsSync(), isFalse, reason: 'one file is not the full run');
      _run(repo, 'post', stdin: _result('flutter test --coverage', '+2598 -2: Some tests failed.'));
      expect(File('${repo.path}/.claude/full-test-passed').existsSync(), isFalse);
      _run(repo, 'post', stdin: _result('flutter analyze', 'All tests passed!'));
      expect(File('${repo.path}/.claude/full-test-passed').existsSync(), isFalse, reason: 'only flutter test counts');
    }, skip: skip);

    test('a full run that passes is recorded, with or without flags and redirection', () {
      for (final cmd in ['flutter test', 'flutter test --coverage', 'flutter test --coverage > out.txt 2>&1; tail -2 out.txt']) {
        final marker = File('${repo.path}/.claude/full-test-passed');
        if (marker.existsSync()) marker.deleteSync();
        _run(repo, 'post', stdin: _result(cmd, '01:08 +2606: All tests passed!'));
        expect(marker.existsSync(), isTrue, reason: cmd);
      }
    }, skip: skip);
  });

  group('the commit: CHANGE-PROCESS.md section 8, steps 1 and 2', () {
    test('a header that still says in progress is denied', () {
      repo.deleteSync(recursive: true);
      repo = _repo(changelog: _changelog(header: '2026-11-23 v0.8.222 build 592 - in progress'));
      _recordTestsPassed(repo);
      expect(_pre(repo, 'git commit -m "v0.8.222 build 592 - in progress"'), allOf(contains(kDeny), contains('in progress')));
    }, skip: skip);

    test('a block with no play fence is denied', () {
      repo.deleteSync(recursive: true);
      repo = _repo(changelog: _changelog(play: false));
      _recordTestsPassed(repo);
      expect(_pre(repo, 'git commit -m "$kSubject"'), allOf(contains(kDeny), contains('play')));
    }, skip: skip);

    test('a play fence belonging to the older block does not count for the top one', () {
      repo.deleteSync(recursive: true);
      repo = _repo(changelog: _changelog(play: false));
      _recordTestsPassed(repo);
      expect(_pre(repo, 'git commit -m "$kSubject"'), contains(kDeny), reason: 'the older block has a fence, the top has none');
    }, skip: skip);

    test('a subject that differs from the header is denied, and the denial gives the right one', () {
      _recordTestsPassed(repo);
      final out = _pre(repo, 'git commit -m "v0.8.221 build 591 - something else"');
      expect(out, contains(kDeny));
      expect(out, contains(kSubject));
    }, skip: skip);

    test('the subject is read from a heredoc message too', () {
      _recordTestsPassed(repo);
      expect(_pre(repo, "git commit -m \"\$(cat <<'EOF'\nv0.8.221 build 591 - not the header\nEOF\n)\""), contains(kDeny));
      expect(_pre(repo, "git commit -m \"\$(cat <<'EOF'\n$kSubject\nEOF\n)\""), isEmpty);
    }, skip: skip);

    test('a commit with the right header, play fence and subject, after the tests, is allowed', () {
      _recordTestsPassed(repo);
      expect(_pre(repo, 'git commit -m "$kSubject"'), isEmpty);
    }, skip: skip);

    test('a throwaway commit for a CI run is not held to the release steps', () {
      repo.deleteSync(recursive: true);
      repo = _repo(changelog: _changelog(header: '2026-11-23 v0.8.222 build 592 - in progress', play: false));
      expect(_pre(repo, 'git commit -q -m "throwaway: ID-630 pipeline test, not for merging"'), isEmpty);
    }, skip: skip);
  });

  group('the rules no machine can see', () {
    test('each request carries them: restate, root cause first, look before asking, follow the rules', () {
      final out = _run(repo, 'prompt');
      for (final phrase in ['restate the outcome', 'root cause first', 'before asking', 'Follow every documented rule', 'finish all the work']) {
        expect(out, contains(phrase), reason: phrase);
      }
    }, skip: skip);
  });

  test('the hooks are wired in .claude/settings.json', () {
    final settings = File('.claude/settings.json').readAsStringSync();
    for (final mode in ['pre', 'post', 'prompt']) {
      expect(settings, contains('check-bash-rules.sh\\" $mode'), reason: mode);
    }
    expect(settings, contains('"PreToolUse"'));
    expect(settings, contains('"UserPromptSubmit"'));
  });

  test('the marker the hook writes is not committed', () {
    expect(File('.gitignore').readAsStringSync(), contains('.claude/full-test-passed'));
  });
}
