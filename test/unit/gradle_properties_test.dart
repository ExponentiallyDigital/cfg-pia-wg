// test/unit/gradle_properties_test.dart - the Gradle JVM keeps room for R8 (ID-622).
//
// On 2026-11-17 the signed release build for v0.8.214 failed on CI in `:app:minifyReleaseWithR8` with
// `OutOfMemoryError: Metaspace`: android/gradle.properties capped Metaspace at 512m, as it had since the
// first commit. The same build passed on a larger machine, so nothing local would have said so. The cap
// is a ceiling, not memory taken, and an older commented-out line held 1g.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The MaxMetaspaceSize in [jvmargs], in megabytes, or null when there is none (no ceiling).
int? maxMetaspaceMegabytes(String jvmargs) {
  final m = RegExp(r'-XX:MaxMetaspaceSize=(\d+)([kKmMgG]?)').firstMatch(jvmargs);
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  switch (m.group(2)!.toLowerCase()) {
    case 'g':
      return n * 1024;
    case 'k':
      return n ~/ 1024;
    case 'm':
    case '':
      return n;
  }
  return null;
}

/// The value of `org.gradle.jvmargs` in a properties file's text, ignoring comment lines.
String? jvmargsOf(String properties) {
  for (final line in properties.split('\n')) {
    final t = line.trim();
    if (t.startsWith('#') || !t.startsWith('org.gradle.jvmargs=')) continue;
    return t.substring('org.gradle.jvmargs='.length);
  }
  return null;
}

void main() {
  test("android/gradle.properties leaves R8 at least 1g of Metaspace, or no ceiling (ID-622)", () {
    final jvmargs = jvmargsOf(File('android/gradle.properties').readAsStringSync());
    expect(jvmargs, isNotNull, reason: 'org.gradle.jvmargs is set');
    final mb = maxMetaspaceMegabytes(jvmargs!);
    expect(mb == null || mb >= 1024, isTrue, reason: 'MaxMetaspaceSize is ${mb}m; R8 ran out of memory at 512m on CI');
  });

  group('the reading of the file', () {
    test('sizes in k, m and g, and a bare number of megabytes, are converted', () {
      expect(maxMetaspaceMegabytes('-Xmx3g -XX:MaxMetaspaceSize=512m'), 512);
      expect(maxMetaspaceMegabytes('-XX:MaxMetaspaceSize=1g -Dx=y'), 1024);
      expect(maxMetaspaceMegabytes('-XX:MaxMetaspaceSize=2048k'), 2);
      expect(maxMetaspaceMegabytes('-XX:MaxMetaspaceSize=768'), 768);
    });

    test('no ceiling is null, and a commented line is not the setting', () {
      expect(maxMetaspaceMegabytes('-Xmx3g -XX:+UseG1GC'), isNull);
      expect(jvmargsOf('#org.gradle.jvmargs=-XX:MaxMetaspaceSize=1g\norg.gradle.jvmargs=-XX:MaxMetaspaceSize=512m\n'),
          '-XX:MaxMetaspaceSize=512m');
      expect(jvmargsOf('# nothing here\n'), isNull);
    });
  });
}
