// test/release/third_party_notices_test.dart - the generator behind THIRD-PARTY-NOTICES.md (ID-007).
//
// The hand-kept file had drifted: dev-only packages listed as shipped, a missing dependency, stale
// versions and five wrong licences. These hold the generator to what the app actually ships.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/third_party_notices.dart';

const _mit = 'MIT License\n\nCopyright (c) 2020 Someone\n\nPermission is hereby granted, free of charge, to any person '
    'obtaining a copy of this software...';
const _apache = 'Apache License\n                           Version 2.0, January 2004\n        http://www.apache.org/licenses/';
const _bsd3 = 'Copyright 2013 The Flutter Authors\n\nRedistribution and use in source and binary forms, with or without '
    'modification, are permitted... * Neither the name of Google LLC nor the names of its contributors may be used...';
const _bsd2 = 'Copyright (c) 2015\n\nRedistribution and use in source and binary forms, with or without modification, '
    'are permitted provided that the following conditions are met: - Redistributions of source code...';

void main() {
  group('recognising a Dart package\'s licence from its text', () {
    test('the common licences', () {
      expect(recogniseLicence(_mit), 'MIT');
      expect(recogniseLicence(_apache), 'Apache-2.0');
      expect(recogniseLicence(_bsd3), 'BSD-3-Clause');
      expect(recogniseLicence(_bsd2), 'BSD-2-Clause');
    });

    // asn1lib: its file names BSD-3-Clause but carries two clauses. The hand-kept file and the wording
    // disagreed; what the author wrote at the top is the answer.
    test('a licence named near the top wins over the wording', () {
      expect(recogniseLicence('http://opensource.org/licenses/BSD-3-Clause\n\n$_bsd2'), 'BSD-3-Clause');
      expect(recogniseLicence('SPDX-License-Identifier: MPL-2.0\n$_mit'), 'MPL-2.0');
    });

    test('several licences in one text are reported, not guessed', () {
      expect(recogniseLicence('$_mit\n\n$_apache'), 'Multiple: Apache-2.0, MIT');
    });

    test('nothing recognisable is null', () {
      expect(recogniseLicence('All rights reserved.'), isNull);
      expect(recogniseLicence(''), isNull);
      expect(recogniseLicence(null), isNull);
    });
  });

  test('Maven licence names become SPDX ids where they are the common ones', () {
    expect(normaliseMavenLicence('The Apache Software License, Version 2.0'), 'Apache-2.0');
    expect(normaliseMavenLicence('Apache License, Version 2.0'), 'Apache-2.0');
    expect(normaliseMavenLicence('The MIT License (MIT)'), 'MIT');
    expect(normaliseMavenLicence('Android Software Development Kit License'), 'Android Software Development Kit License');
  });

  group('the Android libraries in the app', () {
    test('are the releaseRuntimeClasspath entries of the Gradle lockfile, sorted', () {
      const lock = '# This is a Gradle generated file for dependency locking.\n'
          'org.jetbrains.kotlin:kotlin-stdlib:2.3.20=debugRuntimeClasspath,releaseRuntimeClasspath\n'
          'androidx.core:core:1.17.0=releaseCompileClasspath,releaseRuntimeClasspath\n'
          'junit:junit:4.13.2=debugUnitTestRuntimeClasspath\n'
          'androidx.test:runner:1.5.0=releaseRuntimeClasspathExtra\n'
          'empty=\n';
      expect(shippedAndroidLibraries(lock).map((c) => '$c'), ['androidx.core:core:1.17.0', 'org.jetbrains.kotlin:kotlin-stdlib:2.3.20']);
    });

    test('a POM\'s own licences, and its parent when it declares none', () {
      const pom = '<project><licenses><license><name>Apache-2.0</name><url>https://apache.org/l</url></license>'
          '<license><name>MIT</name></license></licenses></project>';
      final ls = pomLicences(pom);
      expect(ls.map((l) => l.name), ['Apache-2.0', 'MIT']);
      expect(ls.first.url, 'https://apache.org/l');
      expect(ls.last.url, isNull);

      const child = '<project><parent><groupId>com.example</groupId><artifactId>parent</artifactId>'
          '<version>7</version></parent><dependencies><dependency><groupId>x</groupId><artifactId>y</artifactId>'
          '<version>1</version></dependency></dependencies></project>';
      expect('${pomParent(child)}', 'com.example:parent:7');
      expect(pomParent('<project><dependencies><dependency><groupId>x</groupId></dependency></dependencies></project>'), isNull);
    });

    test('resolving follows the parent; a missing POM is null, one with no licence anywhere is empty', () async {
      final poms = {
        'a:child:1': '<project><parent><groupId>a</groupId><artifactId>parent</artifactId><version>2</version></parent></project>',
        'a:parent:2': '<project><licenses><license><name>The MIT License (MIT)</name></license></licenses></project>',
        'b:bare:1': '<project></project>',
      };
      Future<String?> source(MavenCoordinate c) async => poms['$c'];
      expect((await resolveAndroidLicences(const MavenCoordinate('a', 'child', '1'), source))!.single.name, 'The MIT License (MIT)');
      expect(await resolveAndroidLicences(const MavenCoordinate('b', 'bare', '1'), source), isEmpty);
      expect(await resolveAndroidLicences(const MavenCoordinate('c', 'gone', '1'), source), isNull);
    });
  });

  group('the Dart packages in the app', () {
    final deps = jsonFromOutput('Resolving dependencies...\n{"packages": ['
        '{"name": "app", "kind": "root", "dependencies": ["http", "flutter", "mocktail"], '
        '"directDependencies": ["http", "flutter"], "devDependencies": ["mocktail"]},'
        '{"name": "http", "kind": "direct", "dependencies": ["meta"]},'
        '{"name": "meta", "kind": "transitive", "dependencies": []},'
        '{"name": "flutter", "kind": "direct", "dependencies": ["meta"]},'
        '{"name": "mocktail", "kind": "dev", "dependencies": ["matcher"]},'
        '{"name": "matcher", "kind": "transitive", "dependencies": []}]}');

    test('are what the direct dependencies reach, not what the dev dependencies do', () {
      expect(shippedDartPackages(deps), {'http', 'meta', 'flutter'});
      expect(devDependencies(deps), ['mocktail']);
    });
  });

  test('renders every section, in a stable order, with licence links', () {
    String render() => renderNotices(
          dart: const [NoticeRow('http', '1.6.0', 'BSD-3-Clause', 'https://pub.dev/packages/http/license', type: 'direct')],
          android: const [NoticeRow('androidx.core:core', '1.17.0', 'Apache-2.0', 'https://www.apache.org/licenses/LICENSE-2.0.txt')],
          dev: const [NoticeRow('mocktail', '1.0.5', 'MIT', 'https://pub.dev/packages/mocktail/license')],
          sdkComponents: const ['flutter', 'sky_engine'],
          flutterVersion: '3.47.2',
        );
    final out = render();
    expect(out, render(), reason: 'the same inputs give the same bytes');
    for (final heading in ['## Dart packages in the app', '## Android libraries in the app', '## Development and test dependencies',
        '## Flutter SDK components', '## Maintenance']) {
      expect(out, contains(heading));
    }
    expect(out, contains('| [`http`](https://pub.dev/packages/http) | 1.6.0 | [BSD-3-Clause](https://pub.dev/packages/http/license) | direct |'));
    expect(out, contains('| `androidx.core:core` | 1.17.0 | [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0.txt) |'));
    expect(out, contains('Flutter SDK 3.47.2: `flutter`, `sky_engine`'));
    expect(out, contains('do not edit it by hand'));
  });

  // The committed file, held to pubspec.yaml: every shipped direct dependency is listed as direct, and
  // nothing removed from pubspec.yaml lingers. Regenerating keeps this true; hand edits will not.
  test('the committed file lists every direct dependency in pubspec.yaml, and nothing it no longer has', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final block = RegExp(r'^dependencies:\n((?:  .*\n)+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    final names = RegExp(r'^  ([a-z0-9_]+):', multiLine: true).allMatches(block).map((m) => m.group(1)!).where((n) => n != 'flutter');
    final notices = File(kNoticesPath).readAsStringSync();
    for (final n in names) {
      expect(notices, contains('| [`$n`](https://pub.dev/packages/$n) |'), reason: n);
      expect(RegExp('\\| \\[`$n`\\].*\\| direct \\|').hasMatch(notices), isTrue, reason: '$n is a direct dependency');
    }
    expect(notices, isNot(contains('in_app_review')), reason: 'removed in ID-042');
    expect(notices, contains('## Android libraries in the app'));
  });
}
