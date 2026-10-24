// test/unit/gradle_wrapper_test.dart - the Gradle wrapper stays on a version that builds without
// Java's native-access warning, and checks what it downloads (ID-408).
//
// Gradle 9.1.0 on Android Studio's Java 25 printed "A restricted method in java.lang.System has been
// called" on every build; 9.8.1 doesn't (measured 2026-10-16). The checksum makes the wrapper refuse a
// distribution that isn't Gradle's: with one digit changed, a fresh download stopped with
// "Verification of Gradle distribution failed!".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _properties() => {
      for (final line in File('android/gradle/wrapper/gradle-wrapper.properties').readAsLinesSync())
        if (line.contains('=') && !line.startsWith('#')) line.substring(0, line.indexOf('=')): line.substring(line.indexOf('=') + 1),
    };

/// The wrapper's Gradle version as [major, minor, patch], from its distribution URL.
List<int> _version(String url) {
  final m = RegExp(r'gradle-(\d+)\.(\d+)(?:\.(\d+))?-(?:all|bin)\.zip$').firstMatch(url);
  expect(m, isNotNull, reason: 'not a Gradle distribution URL: $url');
  return [int.parse(m!.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3) ?? '0')];
}

bool _atLeast(List<int> v, List<int> min) {
  for (var i = 0; i < 3; i++) {
    if (v[i] != min[i]) return v[i] > min[i];
  }
  return true;
}

void main() {
  test('the version reader takes the version from a distribution URL', () {
    expect(_version(r'https\://services.gradle.org/distributions/gradle-9.1.0-all.zip'), [9, 1, 0]);
    expect(_version(r'https\://services.gradle.org/distributions/gradle-10.0-bin.zip'), [10, 0, 0]);
    expect(_atLeast([9, 1, 0], [9, 8, 1]), isFalse);
    expect(_atLeast([9, 8, 1], [9, 8, 1]), isTrue);
    expect(_atLeast([10, 0, 0], [9, 8, 1]), isTrue);
  });

  test('the wrapper is Gradle 9.8.1 or newer, from Gradle\'s own server', () {
    final url = _properties()['distributionUrl']!;
    expect(url, startsWith(r'https\://services.gradle.org/distributions/'));
    expect(_atLeast(_version(url), [9, 8, 1]), isTrue, reason: '$url - 9.1.0 printed the native-access warning');
  });

  // ID-473: on a Mac 9.8.1 still printed it, from the launcher gradlew starts, not the daemon. gradlew
  // is Flutter's and git ignores it, so the build scripts pass the option instead.
  test('the build scripts start Gradle with native access allowed on macOS and Linux', () {
    expect(File('scripts/build.ps1').readAsStringSync(),
        contains(r'$env:GRADLE_OPTS = "--enable-native-access=ALL-UNNAMED $env:GRADLE_OPTS"'));
    expect(File('scripts/build.sh').readAsStringSync(),
        contains(r'export GRADLE_OPTS="--enable-native-access=ALL-UNNAMED${GRADLE_OPTS:+ $GRADLE_OPTS}"'));
  });

  test('the wrapper checks its download against a SHA-256', () {
    expect(_properties()['distributionSha256Sum'], matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: 'when moving Gradle, take the new sum from the .sha256 file beside the distribution');
  });
}
