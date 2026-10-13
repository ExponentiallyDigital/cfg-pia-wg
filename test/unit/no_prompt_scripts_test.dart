// test/unit/no_prompt_scripts_test.dart - a router script never asks for a password (ID-378).
//
// scripts/check-claims.sh runs an SSH client on the router. On 2026-10-13 that client's key was
// refused, so it fell back to asking for a password at the terminal of whoever ran the check - twice,
// with no sign whether what was typed was used - and what was typed after the check killed it landed
// on their command line, the router password among it. A script that runs unattended must have
// nowhere to ask: every SSH client call goes through setsid (no controlling terminal, written
// `$NOPROMPT` where the script checks setsid exists first) with its input from /dev/null.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A line that runs an SSH client: `"$CLIENT" -...`, or dbclient or ssh, by path or not, followed
/// by an option. Not a comment, and not the loop that looks for one (`[ -x "$C" ]`).
final _sshCall = RegExp(r'("\$CLIENT"|(^|[\s;&|(])(\S*/)?(dbclient|ssh))\s+-');

List<String> promptingCalls(Directory scripts) => [
      for (final f in scripts.listSync().whereType<File>().where((f) => f.path.endsWith('.sh')))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('#') &&
              _sshCall.hasMatch(line) &&
              !(RegExp(r'(\$NOPROMPT|setsid) +("\$CLIENT"|\S*(dbclient|ssh))').hasMatch(line) && line.contains('</dev/null')))
            '${f.uri.pathSegments.last}:${i + 1}: ${line.trim()}',
    ];

void main() {
  test('every SSH client call in scripts/ has no terminal to ask for a password on', () {
    expect(promptingCalls(Directory('scripts')), isEmpty);
  });

  test("check-claims.sh doesn't run its forwarding check where setsid is missing", () {
    final s = File('scripts/check-claims.sh').readAsStringSync();
    expect(s, contains('NOPROMPT=""; which setsid >/dev/null 2>&1 && NOPROMPT=setsid'));
    expect(s, contains('elif [ -z "\$NOPROMPT" ]; then'));
  });

  test('the scan finds one: a bare client call is caught, a guarded one is not', () {
    final dir = Directory.systemTemp.createTempSync('no_prompt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a.sh').writeAsStringSync('''
# "\$CLIENT" -y in a comment is fine
CLIENT=""; for C in /usr/bin/dbclient; do [ -x "\$C" ] && CLIENT="\$C" && break; done
"\$CLIENT" -y -i key user@host >out 2>&1 &
\$NOPROMPT "\$CLIENT" -y -i key user@host </dev/null >out 2>&1 &
/usr/bin/dbclient -y user@host
setsid /usr/bin/dbclient -y user@host </dev/null
''');
    expect(promptingCalls(dir), [contains('a.sh:3:'), contains('a.sh:5:')]);
  });
}
