// test/unit/router_script_paths_test.dart - our scripts on the router live in /jffs/cfg-pia-wg.
//
// Andrew's rule, 2026-10-15 (CONTEXT.md section 1): anything we copy to the router, and anything it
// keeps there, goes in the app's own directory, never loose in /jffs among the firmware's files. Until
// then check-claims.sh, probe-claims.sh and three measuring scripts were run from /jffs itself, and
// check-claims kept its restore file there. This reads the scripts and the documents that tell anyone
// where to put one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A script or restore file of ours named directly under /jffs. The firmware's own hook directory,
/// Merlin's /jffs/scripts, is the firmware's, not ours, and is left alone.
final _loose = RegExp(r'/jffs/(?!cfg-pia-wg/|scripts/)[\w.-]+\.(sh|restore)\b');

void main() {
  test('the pattern finds a loose script, and passes ours and the firmware\'s', () {
    expect(_loose.hasMatch('/bin/sh /jffs/check-claims.sh quick'), isTrue);
    expect(_loose.hasMatch('RESTORE=/jffs/check-claims.restore'), isTrue);
    expect(_loose.hasMatch('/bin/sh /jffs/cfg-pia-wg/check-claims.sh quick'), isFalse);
    expect(_loose.hasMatch('/jffs/scripts/services-start.sh'), isFalse);
    expect(_loose.hasMatch('cat /jffs/nmp_cl_json.js'), isFalse);
  });

  test('no script, and no document that says where to put one, uses /jffs itself', () {
    final files = [
      ...Directory('scripts').listSync().whereType<File>().where((f) => f.path.endsWith('.sh')),
      for (final p in ['TESTING.md', 'ARCHITECTURE.md', 'CLAUDE.md', '.claude/CONTEXT.md']) File(p),
    ];
    final found = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in _loose.allMatches(lines[i])) {
          found.add('${f.path}:${i + 1}: ${m.group(0)}');
        }
      }
    }
    expect(found, isEmpty, reason: 'put it in /jffs/cfg-pia-wg instead:\n${found.join('\n')}');
  });
}
