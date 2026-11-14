// tool/android_tools.dart - Gradle, the Android Gradle plugin and Kotlin: what's pinned, what's out,
// and what the pinned Flutter knows (ID-576).
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
//   `dart run tool/android_tools.dart --check --gradle-json F --agp-xml F --kotlin-xml F --flutter-utils F`
//       writes changed=, gradle=, agp= and kotlin= to $GITHUB_OUTPUT, and the PR's explanation to
//       android_tools.md
//   `dart run tool/android_tools.dart --set --gradle V --gradle-sha S --agp V --kotlin V`
//       moves the three in android/gradle/wrapper/gradle-wrapper.properties and android/settings.gradle.kts
//
// Each moves to its latest release. Dependabot can't, as it can't rewrite the STRICT lockfiles (ID-411).
// The pinned Flutter's own known limits (flutter_tools' gradle_utils.dart) are reported, not obeyed:
// the project ran past them from ID-479 on with every build and release passing, so the job's analyze,
// tests and debug build are the gate, and the release dry run the check a debug build can't make
// (Andrew's decision, 2026-11-14).

import 'dart:convert';
import 'dart:io';

const String kWrapperPath = 'android/gradle/wrapper/gradle-wrapper.properties';
const String kSettingsPath = 'android/settings.gradle.kts';
const String kAgpId = 'com.android.application';
const String kKotlinId = 'org.jetbrains.kotlin.android';

/// The Gradle version in the wrapper's distribution URL.
String? gradleVersion(String props) => RegExp(r'gradle-([0-9.]+)-(?:all|bin)\.zip').firstMatch(props)?.group(1);

/// The version of the plugin [id] in settings.gradle.kts.
String? pluginVersion(String settings, String id) =>
    RegExp('id\\("${RegExp.escape(id)}"\\) version "([^"]+)"').firstMatch(settings)?.group(1);

/// [props] with Gradle moved to [version] and its checksum to [sha256]. Throws on a checksum that
/// isn't one: services.gradle.org answers it with a 301, whose HTML page is what a fetch that
/// doesn't follow redirects gets (found rehearsing the job, 2026-11-14).
String withGradle(String props, String version, String sha256) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
    throw ArgumentError.value(sha256.length > 40 ? '${sha256.substring(0, 40)}...' : sha256, 'sha256', 'not a SHA-256');
  }
  return props
      .replaceFirstMapped(RegExp(r'gradle-[0-9.]+-(all|bin)\.zip'), (m) => 'gradle-$version-${m.group(1)}.zip')
      .replaceFirst(RegExp(r'^distributionSha256Sum=.*$', multiLine: true), 'distributionSha256Sum=$sha256');
}

/// [settings] with the plugin [id] moved to [version].
String withPlugin(String settings, String id, String version) =>
    settings.replaceFirst(RegExp('(id\\("${RegExp.escape(id)}"\\) version ")[^"]+(")'), 'id("$id") version "$version"');

/// A `const name = 'x';` in flutter_tools' gradle_utils.dart, or null.
String? flutterLimit(String gradleUtils, String name) =>
    RegExp("const (?:String )?${RegExp.escape(name)} = '([^']+)';").firstMatch(gradleUtils)?.group(1);

/// Compares dotted versions number by number, a missing part counting as 0 (9.2 is 9.2.0).
int compareVersions(String a, String b) {
  final x = a.split('.').map((p) => int.tryParse(p) ?? 0).toList(), y = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// The highest release in a Maven metadata file: numbers only, so no alpha, beta, RC or milestone.
String? latestRelease(String mavenXml) {
  final versions = [
    for (final m in RegExp(r'<version>([0-9]+(?:\.[0-9]+)+)</version>').allMatches(mavenXml)) m.group(1)!,
  ]..sort(compareVersions);
  return versions.isEmpty ? null : versions.last;
}

/// Gradle's current release from services.gradle.org/versions/current.
String? latestGradle(String json) => (jsonDecode(json) as Map<String, dynamic>)['version'] as String?;

/// One tool: where it is, where it could go, and what the pinned Flutter knows.
class ToolMove {
  const ToolMove(this.name, this.current, this.latest, this.limit);
  final String name, current, latest;

  /// The pinned Flutter's highest known version, or null when it couldn't be read.
  final String? limit;

  bool get moves => compareVersions(latest, current) > 0;
  String get target => moves ? latest : current;
  bool get pastLimit => limit != null && compareVersions(target, limit!) > 0;

  String line() {
    final where = moves ? '$current → **$latest**' : '$current (latest $latest)';
    final known = limit == null
        ? "the pinned Flutter's known limit couldn't be read"
        : pastLimit
            ? "**past the pinned Flutter's known limit, $limit**"
            : "within the pinned Flutter's known limit, $limit";
    return '- $name: $where; $known';
  }
}

/// The PR's explanation of what moved and how it stands against the pinned Flutter.
String explanation(List<ToolMove> tools, String flutter) => [
      'Gradle, the Android Gradle plugin and Kotlin, each to its latest release (ID-576), with the Gradle lockfiles '
          'and THIRD-PARTY-NOTICES.md regenerated to match.',
      '',
      for (final t in tools) t.line(),
      '',
      if (tools.any((t) => t.pastLimit))
        "Flutter $flutter's own limits come from flutter_tools' `gradle_utils.dart`. Past one, Flutter hasn't been tested "
            "with that version; the gate is this run's analyze, tests and debug build, as it has been since ID-479 moved "
            'past them by hand.'
      else
        "Flutter $flutter's own limits come from flutter_tools' `gradle_utils.dart`.",
    ].join('\n');

String _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) {
    stderr.writeln('missing $name');
    exit(64);
  }
  return args[i + 1];
}

Future<void> main(List<String> args) async {
  final props = File(kWrapperPath).readAsStringSync(), settings = File(kSettingsPath).readAsStringSync();
  if (args.contains('--set')) {
    File(kWrapperPath).writeAsStringSync(withGradle(props, _arg(args, '--gradle'), _arg(args, '--gradle-sha')));
    File(kSettingsPath).writeAsStringSync(
        withPlugin(withPlugin(settings, kAgpId, _arg(args, '--agp')), kKotlinId, _arg(args, '--kotlin')));
    return;
  }
  if (!args.contains('--check')) {
    stderr.writeln('usage: --check --gradle-json F --agp-xml F --kotlin-xml F --flutter-utils F --flutter V | '
        '--set --gradle V --gradle-sha S --agp V --kotlin V');
    exit(64);
  }
  final utilsFile = File(_arg(args, '--flutter-utils'));
  final utils = utilsFile.existsSync() ? utilsFile.readAsStringSync() : '';
  final latest = [
    latestGradle(File(_arg(args, '--gradle-json')).readAsStringSync()),
    latestRelease(File(_arg(args, '--agp-xml')).readAsStringSync()),
    latestRelease(File(_arg(args, '--kotlin-xml')).readAsStringSync()),
  ];
  final current = [gradleVersion(props), pluginVersion(settings, kAgpId), pluginVersion(settings, kKotlinId)];
  if ([...latest, ...current].contains(null)) {
    stderr.writeln('a version could not be read: current $current, latest $latest');
    exit(1);
  }
  final tools = [
    ToolMove('Gradle', current[0]!, latest[0]!, flutterLimit(utils, 'maxKnownAndSupportedGradleVersion')),
    ToolMove('Android Gradle plugin', current[1]!, latest[1]!, flutterLimit(utils, 'maxKnownAgpVersion')),
    ToolMove('Kotlin', current[2]!, latest[2]!, flutterLimit(utils, 'maxKnownAndSupportedKgpVersion')),
  ];
  File('android_tools.md').writeAsStringSync('${explanation(tools, _arg(args, '--flutter'))}\n');
  stdout.writeln(File('android_tools.md').readAsStringSync());
  final out = [
    'changed=${tools.any((t) => t.moves)}',
    'gradle=${tools[0].target}',
    'agp=${tools[1].target}',
    'kotlin=${tools[2].target}',
  ];
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null) File(output).writeAsStringSync('${out.join('\n')}\n', mode: FileMode.append);
  stdout.writeln(out.join('\n'));
}
