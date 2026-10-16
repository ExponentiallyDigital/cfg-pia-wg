// tool/flutter_pin.dart - the Flutter version pinned in pubspec.yaml, and whether a newer stable is out (ID-410).
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
// Run by weekly_updates.yml:
//   `dart run tool/flutter_pin.dart --check`  writes pinned=, latest= and newer= to $GITHUB_OUTPUT
//   `dart run tool/flutter_pin.dart --set 3.48.0`  moves the pin in pubspec.yaml
//
// The pin is the exact `flutter:` version under pubspec.yaml's `environment`. Every workflow installs
// it (subosito/flutter-action's `flutter-version-file`), and scripts/build.ps1 and build.sh warn when the
// local Flutter differs, so CI builds with what was tested locally. Pub itself enforces only the lower
// bound of that constraint, so a newer Flutter still runs `flutter pub get`.

import 'dart:convert';
import 'dart:io';

const String kFlutterReleases = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json';

final RegExp _pinLine = RegExp(r'^(\s+flutter:\s*)(\d+\.\d+\.\d+)\s*$', multiLine: true);

/// The exact version under `environment:`, or null when there isn't one.
String? pinnedFlutter(String pubspec) {
  final env = RegExp(r'^environment:[ \t]*$((?:\n[ \t]+.*)*)', multiLine: true).firstMatch(pubspec);
  if (env == null) return null;
  return _pinLine.firstMatch(env.group(1)!)?.group(2);
}

/// [pubspec] with the pin moved to [version]. Throws [StateError] when there is no pin to move.
String withFlutterPin(String pubspec, String version) {
  final old = pinnedFlutter(pubspec);
  if (old == null) throw StateError('pubspec.yaml has no exact flutter: version under environment');
  final env = RegExp(r'^environment:[ \t]*$((?:\n[ \t]+.*)*)', multiLine: true).firstMatch(pubspec)!;
  final block = env.group(0)!.replaceFirstMapped(_pinLine, (m) => '${m.group(1)}$version');
  return pubspec.replaceRange(env.start, env.end, block);
}

/// The current stable release's version in Flutter's release list, or null if the list doesn't name one.
String? stableVersion(Map<String, dynamic> releases) {
  final hash = (releases['current_release'] as Map?)?['stable'];
  for (final r in (releases['releases'] as List? ?? const [])) {
    if (r is Map && r['hash'] == hash && r['channel'] == 'stable') return r['version'] as String?;
  }
  return null;
}

/// Whether [a] is a later x.y.z than [b].
bool isNewer(String a, String b) {
  final x = a.split('.').map(int.parse).toList(), y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

Future<void> main(List<String> args) async {
  final file = File('pubspec.yaml');
  final setAt = args.indexOf('--set');
  if (setAt >= 0 && setAt + 1 < args.length) {
    file.writeAsStringSync(withFlutterPin(file.readAsStringSync(), args[setAt + 1]));
    stdout.writeln('pubspec.yaml now pins Flutter ${args[setAt + 1]}');
    return;
  }
  if (!args.contains('--check')) {
    stderr.writeln('usage: dart run tool/flutter_pin.dart --check | --set <version>');
    exit(2);
  }
  final pinned = pinnedFlutter(file.readAsStringSync());
  if (pinned == null) {
    stderr.writeln('pubspec.yaml has no exact flutter: version under environment');
    exit(1);
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final String latest;
  try {
    final response = await (await client.getUrl(Uri.parse(kFlutterReleases))).close();
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    latest = stableVersion(json) ?? (throw const FormatException('no current stable release in the list'));
  } finally {
    client.close(force: true);
  }
  final newer = isNewer(latest, pinned);
  stdout.writeln('pinned $pinned, latest stable $latest${newer ? ' - newer' : ''}');
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null && output.isNotEmpty) {
    File(output).writeAsStringSync('pinned=$pinned\nlatest=$latest\nnewer=$newer\n', mode: FileMode.append);
  }
}
