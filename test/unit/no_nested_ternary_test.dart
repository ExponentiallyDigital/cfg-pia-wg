// test/unit/no_nested_ternary_test.dart - no nested ternary in lib/ (ID-618).
//
// SonarCloud's S3358 flags a conditional expression inside another one. On release PR #80 it flagged
// one (build 581), and the pre-commit estimate of Sonar's rules had missed it before (ID-593); a
// regular expression can't tell nested from sequential, so this reads the code properly enough: it
// drops comments and the text of strings, keeps the code in a string's ${...}, and follows the
// brackets. Cognitive complexity over 15 stays a pre-commit check by hand: nothing here measures it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [s] with its comments dropped and its strings' text blanked. The code in an interpolation stays,
/// inside ( ), so a ternary in a string is read as code and not mistaken for the text around it.
String codeView(String s) {
  final out = StringBuffer();
  final stack = <List<Object>>[]; // ['s', quote, raw] for a string, ['i', braceDepth] for an interpolation
  var i = 0;
  bool at(String t) => s.startsWith(t, i);
  while (i < s.length) {
    final top = stack.isEmpty ? null : stack.last;
    if (top == null || top[0] == 'i') {
      if (at('//')) {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        continue;
      }
      if (at('/*')) {
        final end = s.indexOf('*/', i + 2);
        final stop = end < 0 ? s.length : end + 2;
        for (; i < stop; i++) {
          if (s[i] == '\n') out.write('\n');
        }
        continue;
      }
      var raw = false;
      var q = i;
      final startsString = s[i] == 'r' &&
          i + 1 < s.length &&
          (s[i + 1] == "'" || s[i + 1] == '"') &&
          (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[i - 1]));
      if (startsString) {
        raw = true;
        q = i + 1;
      }
      if (s[q] == "'" || s[q] == '"') {
        final c = s[q];
        final triple = s.startsWith(c * 3, q);
        stack.add(['s', triple ? c * 3 : c, raw]);
        i = q + (triple ? 3 : 1);
        out.write(' ');
        continue;
      }
      if (top != null) {
        if (s[i] == '{') {
          top[1] = (top[1] as int) + 1;
        } else if (s[i] == '}') {
          if ((top[1] as int) == 0) {
            stack.removeLast();
            out.write(')');
            i++;
            continue;
          }
          top[1] = (top[1] as int) - 1;
        }
      }
      out.write(s[i]);
      i++;
    } else {
      final quote = top[1] as String;
      final raw = top[2] as bool;
      if (!raw && s[i] == r'\') {
        if (i + 1 < s.length && s[i + 1] == '\n') out.write('\n');
        i += 2;
        continue;
      }
      if (!raw && at(r'${')) {
        stack.add(['i', 0]);
        out.write('(');
        i += 2;
        continue;
      }
      if (!raw && s[i] == r'$' && i + 1 < s.length && RegExp(r'[A-Za-z_]').hasMatch(s[i + 1])) {
        i++;
        while (i < s.length && RegExp(r'[A-Za-z0-9_]').hasMatch(s[i])) {
          i++;
        }
        continue;
      }
      if (at(quote)) {
        stack.removeLast();
        i += quote.length;
        out.write(' ');
        continue;
      }
      if (s[i] == '\n') out.write('\n');
      i++;
    }
  }
  return out.toString();
}

bool _ws(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/// Whether the `(` at [i] groups an expression, as opposed to opening a call's arguments or a
/// parameter list: nothing that ends a name, a call or an index comes before it.
bool _grouping(String code, int i) {
  var j = i - 1;
  while (j >= 0 && _ws(code[j])) {
    j--;
  }
  if (j < 0) return true;
  final p = code[j];
  if (RegExp(r'[A-Za-z0-9_$)\]]').hasMatch(p)) return false;
  if (p == '>') return j > 0 && code[j - 1] == '=';
  return true;
}

/// The lines of a ternary that sits inside another one, or is chained after it, in the same
/// expression. A ternary's `?` and `:` have a space or a line break on each side, which a nullable
/// type (`String? x`), `?.`, `??`, a null-aware element (`?x`), a named argument and a `case` don't.
/// A grouping parenthesis doesn't end the expression; a call's arguments, a comma and a `;` do.
List<int> nestedTernaryLines(String source) {
  final code = codeView(source);
  final lines = <int>[];
  final pending = <int>[0];
  final inElse = <bool>[false];
  var line = 1;
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    if (c == '\n') {
      line++;
    } else if (c == '(' && _grouping(code, i)) {
      pending.add(pending.last);
      inElse.add(inElse.last);
    } else if (c == '(' || c == '[' || c == '{') {
      pending.add(0);
      inElse.add(false);
    } else if (c == ')' || c == ']' || c == '}') {
      if (pending.length > 1) {
        pending.removeLast();
        inElse.removeLast();
      }
    } else if (c == ',' || c == ';') {
      pending[pending.length - 1] = 0;
      inElse[inElse.length - 1] = false;
    } else if (c == '?' && i > 0 && i + 1 < code.length && _ws(code[i - 1]) && _ws(code[i + 1])) {
      if (pending.last > 0 || inElse.last) lines.add(line);
      pending[pending.length - 1]++;
      inElse[inElse.length - 1] = false;
    } else if (c == ':' && i > 0 && i + 1 < code.length && _ws(code[i - 1]) && _ws(code[i + 1]) && pending.last > 0) {
      pending[pending.length - 1]--;
      inElse[inElse.length - 1] = true;
    }
  }
  return lines;
}

void main() {
  test('no file in lib/ has a nested ternary', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = nestedTernaryLines(f.readAsStringSync());
      if (lines.isNotEmpty) found.add('${f.path.replaceAll(r'\', '/')} line${lines.length == 1 ? '' : 's'} ${lines.join(', ')}');
    }
    expect(found, isEmpty,
        reason: 'A ternary inside another is SonarCloud S3358. Use an if statement or a small method that returns early.');
  });

  group('the scanner', () {
    List<int> lines(String code) => nestedTernaryLines(code);

    test('finds a ternary in the then-branch, in the else-branch, and in a grouping parenthesis', () {
      expect(lines('final a = x ? (y ? 1 : 2) : 3;'), [1]);
      expect(lines('final a = x ? 1 : y ? 2 : 3;'), [1]);
      expect(lines('final a = x\n    ? 1\n    : (y\n        ? 2\n        : 3);'), [4], reason: 'the inner ? is on the fourth line');
      expect(lines("final a = x ? 'a' : (y || z) ? 'b' : 'c';"), [1]);
    });

    test('a ternary inside a string interpolation is read as code, and is nested if it is in a branch', () {
      expect(lines(r"final a = '${x ? 1 : 2}';"), isEmpty);
      expect(lines(r"final a = x ? '${y ? 1 : 2}' : 3;"), [1], reason: 'still inside the outer conditional, as the syntax tree has it');
      expect(lines(r"final a = '${x ? (y ? 1 : 2) : 3}';"), [1]);
    });

    test('separate ternaries are not nested: statements, arguments, list items, a call inside a branch', () {
      expect(lines('final a = x ? 1 : 2;\nfinal b = y ? 3 : 4;'), isEmpty);
      expect(lines('f(a: x ? 1 : 2, b: y ? 3 : 4);'), isEmpty);
      expect(lines('final l = [x ? 1 : 2, y ? 3 : 4];'), isEmpty);
      expect(lines('final a = x ? g(y ? 1 : 2) : 3;'), isEmpty, reason: 'a call is its own expression');
    });

    test('what only looks like a ternary is not one', () {
      expect(lines('String? a; int? b = c ?? d; final e = f?.g; final h = [i, ?j]; final k = l?[0];'), isEmpty);
      expect(lines("switch (x) {\n  case 1:\n    break;\n  default:\n    break;\n}"), isEmpty);
      expect(lines('f(name: x ? 1 : 2);'), isEmpty);
      expect(lines("final m = {'a': x ? 1 : 2, 'b': 3};"), isEmpty);
    });

    test('comments and the text of strings are ignored', () {
      expect(lines("// a ? b : c ? d : e\nfinal s = 'x ? y : z ? w : v';"), isEmpty);
      expect(lines("/* a ? b : c ? d : e */ final t = r'p ? q : r ? s : t';"), isEmpty);
      expect(lines("final u = '''\nx ? y : z ? w : v\n''';"), isEmpty);
    });

    test('line numbers are those of the source, through comments and multi-line strings', () {
      expect(lines("/* one\ntwo */\nfinal s = '''a\nb''';\nfinal a = x ? 1 : y ? 2 : 3;"), [5]);
    });
  });
}
