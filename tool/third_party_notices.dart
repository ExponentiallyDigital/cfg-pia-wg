// tool/third_party_notices.dart - generates THIRD-PARTY-NOTICES.md (ID-007).
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
//   dart run tool/third_party_notices.dart            regenerate the file
//   dart run tool/third_party_notices.dart --check    warn when the committed file is stale
//   --dart-licenses <file>                            reuse dart_pubspec_licenses JSON already generated
//
// The file was maintained by hand and drifted: on 2026-09-15 it listed dev-only packages as shipped,
// missed a dependency, gave dartssh2 two major versions late, and had five licences wrong. So nothing
// in it is typed any more:
//
// - Dart packages are those the app ships: the closure of pubspec.yaml's direct dependencies from
//   `flutter pub deps --json`, not the dev dependencies' tree. Each licence is recognised from the
//   package's LICENSE text (dart_pubspec_licenses), preferring a licence the text names outright.
// - Android libraries are the `releaseRuntimeClasspath` entries of android/app/gradle.lockfile. Each
//   licence comes from the library's Maven POM - the Gradle cache first, then Google Maven and Maven
//   Central, following parent POMs - since the cache often holds only Gradle module metadata.
//
// A POM that cannot be fetched (offline) leaves the file unchanged and exits 3: better stale than
// wrong. The check never fails; it warns (ID-007: agreed 2026-09-15).

import 'dart:convert';
import 'dart:io';

const String kNoticesPath = 'THIRD-PARTY-NOTICES.md';
const String kGradleLockPath = 'android/app/gradle.lockfile';
const String kReleaseClasspath = 'releaseRuntimeClasspath';
const List<String> kMavenRepositories = ['https://dl.google.com/android/maven2', 'https://repo1.maven.org/maven2'];
const String kFlutterLicenceUrl = 'https://github.com/flutter/flutter/blob/main/LICENSE';

/// Exit code when a licence could not be looked up, so the file was left as it was.
const int kExitUnresolved = 3;

// ---------------------------------------------------------------------------------------------------------------
// Licence recognition
// ---------------------------------------------------------------------------------------------------------------

/// The licence a Dart package's LICENSE [text] is, as an SPDX id, or null when it is not recognised.
///
/// A licence the text names outright near the top wins over the wording: asn1lib's file names
/// BSD-3-Clause but carries only two of its clauses. Several licences in one text come back as
/// `Multiple: ...`, which is reported rather than guessed at.
String? recogniseLicence(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  final head = flat.length > 400 ? flat.substring(0, 400) : flat;
  final named = RegExp(r'(?:SPDX-License-Identifier:\s*|(?:opensource|spdx)\.org/licenses/)([A-Za-z0-9.+-]+)').firstMatch(head);
  if (named != null) return named.group(1)!.replaceFirst(RegExp(r'\.(?:html?|php|txt)$'), '');

  final found = <String>[];
  if (RegExp(r'Apache License,? Version 2\.0', caseSensitive: false).hasMatch(flat)) found.add('Apache-2.0');
  if (flat.contains('Permission is hereby granted, free of charge')) found.add('MIT');
  if (flat.contains('Redistribution and use in source and binary forms')) {
    final third = RegExp(r'Neither the name|names of its contributors|name of the copyright holder nor').hasMatch(flat);
    found.add(third ? 'BSD-3-Clause' : 'BSD-2-Clause');
  }
  if (flat.contains('Mozilla Public License')) found.add('MPL-2.0');
  if (flat.contains('Permission to use, copy, modify, and/or distribute this software for any purpose')) found.add('ISC');
  if (found.isEmpty) return null;
  return found.length == 1 ? found.single : 'Multiple: ${found.join(', ')}';
}

/// A Maven POM's licence name, with the common spellings of Apache 2.0 and MIT made SPDX ids.
String normaliseMavenLicence(String name) {
  if (RegExp('apache', caseSensitive: false).hasMatch(name) && name.contains('2.0')) return 'Apache-2.0';
  if (RegExp(r'\bMIT\b').hasMatch(name)) return 'MIT';
  return name.trim();
}

// ---------------------------------------------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------------------------------------------

/// A library in the Gradle lockfile.
class MavenCoordinate {
  final String group, artifact, version;
  const MavenCoordinate(this.group, this.artifact, this.version);
  String get id => '$group:$artifact';
  @override
  String toString() => '$id:$version';
}

/// The Android libraries the release build packages, sorted by group and artifact.
List<MavenCoordinate> shippedAndroidLibraries(String gradleLock) {
  final out = <MavenCoordinate>[];
  for (final raw in gradleLock.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final eq = line.indexOf('=');
    if (line.isEmpty || line.startsWith('#') || eq < 0) continue;
    if (!line.substring(eq + 1).split(',').contains(kReleaseClasspath)) continue;
    final parts = line.substring(0, eq).split(':');
    if (parts.length == 3) out.add(MavenCoordinate(parts[0], parts[1], parts[2]));
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// The Dart packages the app ships: everything reachable from pubspec.yaml's direct dependencies.
///
/// [deps] is `flutter pub deps --json`. Its root `dependencies` includes the dev dependencies, so the
/// walk starts from `directDependencies` instead.
Set<String> shippedDartPackages(Map<String, dynamic> deps) {
  final packages = [for (final p in deps['packages'] as List) p as Map<String, dynamic>];
  final byName = {for (final p in packages) p['name'] as String: p};
  final root = packages.firstWhere((p) => p['kind'] == 'root');
  final seen = <String>{};
  final stack = [...(root['directDependencies'] as List).cast<String>()];
  while (stack.isNotEmpty) {
    final name = stack.removeLast();
    final package = byName[name];
    if (package == null || !seen.add(name)) continue;
    stack.addAll(((package['dependencies'] as List?) ?? const []).cast<String>());
  }
  return seen;
}

/// pubspec.yaml's dev dependencies, from `flutter pub deps --json`.
List<String> devDependencies(Map<String, dynamic> deps) {
  final root = (deps['packages'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['kind'] == 'root');
  return [...((root['devDependencies'] as List?) ?? const []).cast<String>()]..sort();
}

/// Reads JSON a command printed, skipping anything it wrote before the JSON began.
Map<String, dynamic> jsonFromOutput(String output) => jsonDecode(output.substring(output.indexOf('{'))) as Map<String, dynamic>;

// ---------------------------------------------------------------------------------------------------------------
// POMs
// ---------------------------------------------------------------------------------------------------------------

class PomLicence {
  final String name;
  final String? url;
  const PomLicence(this.name, this.url);
}

String? _tag(String xml, String tag) => RegExp('<$tag>\\s*(.*?)\\s*</$tag>', dotAll: true).firstMatch(xml)?.group(1);

/// The licences a POM declares itself.
List<PomLicence> pomLicences(String pom) {
  final block = RegExp(r'<licenses>(.*?)</licenses>', dotAll: true).firstMatch(pom);
  if (block == null) return const [];
  return [
    for (final m in RegExp(r'<license>(.*?)</license>', dotAll: true).allMatches(block.group(1)!))
      if (_tag(m.group(1)!, 'name') case final name?) PomLicence(name, _tag(m.group(1)!, 'url')),
  ];
}

/// The POM's parent, where an undeclared licence is inherited from.
MavenCoordinate? pomParent(String pom) {
  final own = pom.replaceAll(
    RegExp(r'<dependencyManagement>.*?</dependencyManagement>|<dependencies>.*?</dependencies>', dotAll: true),
    '',
  );
  final parent = RegExp(r'<parent>(.*?)</parent>', dotAll: true).firstMatch(own)?.group(1);
  if (parent == null) return null;
  final (g, a, v) = (_tag(parent, 'groupId'), _tag(parent, 'artifactId'), _tag(parent, 'version'));
  return g == null || a == null || v == null ? null : MavenCoordinate(g, a, v);
}

/// Where POMs come from.
typedef PomSource = Future<String?> Function(MavenCoordinate coordinate);

/// The licences of [coordinate], following parent POMs. Null when a POM could not be found at all;
/// empty when the POMs were found but declare none.
Future<List<PomLicence>?> resolveAndroidLicences(MavenCoordinate coordinate, PomSource source, {int depth = 0}) async {
  final pom = await source(coordinate);
  if (pom == null) return null;
  final licences = pomLicences(pom);
  if (licences.isNotEmpty || depth >= 5) return licences;
  final parent = pomParent(pom);
  if (parent == null) return const [];
  return resolveAndroidLicences(parent, source, depth: depth + 1);
}

/// The Gradle cache first, then Google Maven, then Maven Central.
PomSource gradleCacheThenMaven(HttpClient client) {
  final env = Platform.environment;
  final home = env['GRADLE_USER_HOME'] ?? '${env['HOME'] ?? env['USERPROFILE']}/.gradle';
  return (c) async {
    final dir = Directory('$home/caches/modules-2/files-2.1/${c.group}/${c.artifact}/${c.version}');
    if (dir.existsSync()) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('${c.artifact}-${c.version}.pom')) return f.readAsStringSync();
      }
    }
    for (final repo in kMavenRepositories) {
      final url = '$repo/${c.group.replaceAll('.', '/')}/${c.artifact}/${c.version}/${c.artifact}-${c.version}.pom';
      try {
        final response = await (await client.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) return await response.transform(const Utf8Decoder(allowMalformed: true)).join();
        await response.drain<void>();
      } catch (_) {
        // Try the next repository; nothing found anywhere comes back as null.
      }
    }
    return null;
  };
}

// ---------------------------------------------------------------------------------------------------------------
// The file
// ---------------------------------------------------------------------------------------------------------------

/// One row of a table.
class NoticeRow {
  final String name, version, licence;
  final String? url;
  final String? type;
  const NoticeRow(this.name, this.version, this.licence, this.url, {this.type});
}

String _cell(String s) => s.replaceAll('|', r'\|');

String _licenceCell(NoticeRow r) => r.url == null ? _cell(r.licence) : '[${_cell(r.licence)}](${r.url})';

/// THIRD-PARTY-NOTICES.md. Deterministic: the same inputs give the same bytes, which is what lets the
/// release workflow tell a stale file from a current one.
String renderNotices({
  required List<NoticeRow> dart,
  required List<NoticeRow> android,
  required List<NoticeRow> dev,
  required List<String> sdkComponents,
  required String? flutterVersion,
}) {
  final b = StringBuffer()
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln('This application incorporates third-party software. The application\'s own source code is licensed under the '
        'GNU General Public License v3.0.')
    ..writeln()
    ..writeln('The components below remain subject to their own licences. The versions are those resolved in `pubspec.lock` '
        'and `android/app/gradle.lockfile` when this file was generated.')
    ..writeln()
    ..writeln('**Important:** this file is an index of the third-party components and their licences. The app shows the '
        'complete Dart and Flutter licence texts on its About screen, through Flutter\'s `LicenseRegistry`. The linked '
        'licence pages are the authoritative upstream sources.')
    ..writeln()
    ..writeln('## Dart packages in the app')
    ..writeln()
    ..writeln('Everything reachable from the direct dependencies in `pubspec.yaml`. Each licence is recognised from the '
        'package\'s own LICENSE file.')
    ..writeln()
    ..writeln('| Package | Version | Licence | Type |')
    ..writeln('| --- | ---: | --- | --- |');
  for (final r in dart) {
    b.writeln('| [`${r.name}`](https://pub.dev/packages/${r.name}) | ${r.version} | ${_licenceCell(r)} | ${r.type} |');
  }
  b
    ..writeln()
    ..writeln('## Android libraries in the app')
    ..writeln()
    ..writeln('The Java and Kotlin libraries the release build packages: the `releaseRuntimeClasspath` entries of '
        '`android/app/gradle.lockfile`. Each licence is the one the library\'s Maven POM declares. The Flutter engine '
        'and its Android embedding are covered under the Flutter SDK below.')
    ..writeln()
    ..writeln('| Library | Version | Licence |')
    ..writeln('| --- | ---: | --- |');
  for (final r in android) {
    b.writeln('| `${r.name}` | ${r.version} | ${_licenceCell(r)} |');
  }
  b
    ..writeln()
    ..writeln('## Development and test dependencies')
    ..writeln()
    ..writeln('The dev dependencies in `pubspec.yaml`, used to build and test the project and not included in the '
        'distributed app. Their own dependencies are in `pubspec.lock`.')
    ..writeln()
    ..writeln('| Package | Version | Licence |')
    ..writeln('| --- | ---: | --- |');
  for (final r in dev) {
    b.writeln('| [`${r.name}`](https://pub.dev/packages/${r.name}) | ${r.version} | ${_licenceCell(r)} |');
  }
  final version = flutterVersion == null ? '' : ' $flutterVersion';
  b
    ..writeln()
    ..writeln('## Flutter SDK components')
    ..writeln()
    ..writeln('The app also includes components of the Flutter SDK$version: ${sdkComponents.map((s) => '`$s`').join(', ')}. '
        'They are licensed under [the Flutter SDK\'s licence]($kFlutterLicenceUrl). The engine (`sky_engine`) bundles '
        'third-party code of its own, whose licences are listed in full on the app\'s licence page.')
    ..writeln()
    ..writeln('## Maintenance')
    ..writeln()
    ..writeln('Generated by `tool/third_party_notices.dart` - do not edit it by hand. `scripts/build.ps1` and '
        '`scripts/build.sh` regenerate it in `all` mode, and `release.yml` warns when the committed file no longer '
        'matches. To regenerate it directly: `dart run tool/third_party_notices.dart`.');
  return b.toString();
}

// ---------------------------------------------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------------------------------------------

ProcessResult _run(String exe, List<String> args) => Process.runSync(exe, args, runInShell: Platform.isWindows);

String _normalise(String s) => s.replaceAll('\r\n', '\n').trimRight();

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final dlAt = args.indexOf('--dart-licenses');
  final warnings = <String>[];

  // ---- Dart ----
  String licencesJson;
  if (dlAt >= 0 && dlAt + 1 < args.length) {
    licencesJson = File(args[dlAt + 1]).readAsStringSync();
  } else {
    final tmp = Directory.systemTemp.createTempSync('third_party_notices');
    final out = '${tmp.path}${Platform.pathSeparator}dart_licenses.json';
    final r = _run('dart', ['run', 'dart_pubspec_licenses:generate', '-o', out, '--json']);
    if (r.exitCode != 0) {
      stdout.writeln('::error::dart_pubspec_licenses failed: ${r.stderr}');
      exit(1);
    }
    licencesJson = File(out).readAsStringSync();
    tmp.deleteSync(recursive: true);
  }
  final depsRun = _run('flutter', ['pub', 'deps', '--json']);
  if (depsRun.exitCode != 0) {
    stdout.writeln('::error::flutter pub deps failed: ${depsRun.stderr}');
    exit(1);
  }
  final deps = jsonFromOutput(depsRun.stdout as String);
  final licences = {for (final p in jsonDecode(licencesJson) as List) (p as Map)['name'] as String: p};
  final root = (deps['packages'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['kind'] == 'root');
  final direct = ((root['directDependencies'] as List?) ?? const []).cast<String>().toSet();

  NoticeRow dartRow(String name, {String? type}) {
    final info = licences[name];
    final version = (info?['version'] as String?) ?? '?';
    final licence = recogniseLicence(info?['license'] as String?);
    if (licence == null) warnings.add('$name: licence not recognised from its LICENSE file');
    if (licence != null && licence.startsWith('Multiple')) warnings.add('$name: its LICENSE file carries several licences');
    return NoticeRow(name, version, licence ?? 'Unrecognised', 'https://pub.dev/packages/$name/license', type: type);
  }

  final shipped = shippedDartPackages(deps);
  final sdk = shipped.where((n) => licences[n]?['isSdk'] == true).toList()..sort();
  final dartRows = [
    for (final n in (shipped.difference(sdk.toSet()).toList()..sort())) dartRow(n, type: direct.contains(n) ? 'direct' : 'transitive'),
  ];
  final devRows = [
    for (final n in devDependencies(deps))
      if (licences[n]?['isSdk'] == true)
        NoticeRow(n, 'SDK', 'Flutter SDK', kFlutterLicenceUrl)
      else
        dartRow(n),
  ];

  // ---- Android ----
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final source = gradleCacheThenMaven(client);
  final androidRows = <NoticeRow>[];
  final unresolved = <String>[];
  for (final c in shippedAndroidLibraries(File(kGradleLockPath).readAsStringSync())) {
    final found = await resolveAndroidLicences(c, source);
    if (found == null) {
      unresolved.add('$c');
      continue;
    }
    if (found.isEmpty) warnings.add('$c: its POM declares no licence');
    androidRows.add(NoticeRow(
      c.id,
      c.version,
      found.isEmpty ? 'Not declared' : found.map((l) => normaliseMavenLicence(l.name)).join(' / '),
      found.isEmpty ? null : found.first.url,
    ));
  }
  client.close();

  for (final w in warnings) {
    stdout.writeln('::warning::$w');
  }
  if (unresolved.isNotEmpty) {
    stdout.writeln('::warning::${unresolved.length} Android licences could not be looked up (offline?), so '
        '$kNoticesPath was ${check ? 'not checked' : 'left unchanged'}: ${unresolved.take(5).join(', ')}'
        '${unresolved.length > 5 ? ', ...' : ''}');
    exit(check ? 0 : kExitUnresolved);
  }

  final flutterVersion = licences['flutter']?['version'] as String?;
  final rendered = renderNotices(
    dart: dartRows,
    android: androidRows,
    dev: devRows,
    sdkComponents: sdk,
    flutterVersion: flutterVersion,
  );
  final file = File(kNoticesPath);
  final current = file.existsSync() ? file.readAsStringSync() : '';
  final summary = '${dartRows.length} Dart packages, ${androidRows.length} Android libraries, ${devRows.length} dev dependencies';

  if (check) {
    if (_normalise(current) == _normalise(rendered)) {
      stdout.writeln('$kNoticesPath is current ($summary).');
    } else {
      final had = _normalise(current).split('\n').where((l) => l.startsWith('| ')).toSet();
      final now = _normalise(rendered).split('\n').where((l) => l.startsWith('| ')).toSet();
      stdout.writeln('::warning::$kNoticesPath is out of date: ${now.difference(had).length} rows would be added or changed '
          'and ${had.difference(now).length} removed. Regenerate it with `dart run tool/third_party_notices.dart` '
          '(or build.ps1/build.sh all) and commit it.');
    }
    exit(0);
  }

  if (_normalise(current) == _normalise(rendered)) {
    stdout.writeln('$kNoticesPath unchanged ($summary).');
  } else {
    file.writeAsStringSync(rendered);
    stdout.writeln('$kNoticesPath written ($summary).');
  }
}
