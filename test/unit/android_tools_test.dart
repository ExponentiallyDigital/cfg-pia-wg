// test/unit/android_tools_test.dart - reading and moving Gradle, the Android Gradle plugin and Kotlin,
// and saying how each stands against the pinned Flutter's known limits (ID-576).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/android_tools.dart';

const String _props = 'distributionBase=GRADLE_USER_HOME\n'
    'distributionSha256Sum=aaaa\n'
    r'distributionUrl=https\://services.gradle.org/distributions/gradle-9.8.2-all.zip'
    '\nnetworkTimeout=10000\n';

const String _settings = 'plugins {\n'
    '    id("dev.flutter.flutter-plugin-loader") version "1.0.0"\n'
    '    id("com.android.application") version "9.4.1" apply false\n'
    '    id("org.jetbrains.kotlin.android") version "2.4.21" apply false\n'
    '}\n';

void main() {
  test('reads each version, from the real files too', () {
    expect(gradleVersion(_props), '9.8.2');
    expect(pluginVersion(_settings, kAgpId), '9.4.1');
    expect(pluginVersion(_settings, kKotlinId), '2.4.21');
    expect(gradleVersion(File(kWrapperPath).readAsStringSync()), isNotNull);
    expect(pluginVersion(File(kSettingsPath).readAsStringSync(), kAgpId), isNotNull);
    expect(pluginVersion(File(kSettingsPath).readAsStringSync(), kKotlinId), isNotNull);
  });

  test('moves each, with the Gradle checksum, and nothing else', () {
    final sha = 'b' * 64;
    final props = withGradle(_props, '9.9.0', sha);
    expect(props, contains('gradle-9.9.0-all.zip'));
    expect(props, contains('distributionSha256Sum=$sha'));
    expect(props.replaceAll('9.9.0', '9.8.2').replaceAll(sha, 'aaaa'), _props);
    final settings = withPlugin(withPlugin(_settings, kAgpId, '9.5.0'), kKotlinId, '2.5.0');
    expect(settings, contains('id("com.android.application") version "9.5.0" apply false'));
    expect(settings, contains('id("org.jetbrains.kotlin.android") version "2.5.0" apply false'));
    expect(settings, contains('id("dev.flutter.flutter-plugin-loader") version "1.0.0"'));
  });

  test("the latest release skips alpha, beta, RC and milestone builds, and compares by number", () {
    const xml = '<versions><version>9.4.1</version><version>9.10.0</version><version>9.11.0-alpha01</version>'
        '<version>9.9.2</version><version>10.0.0-rc01</version></versions>';
    expect(latestRelease(xml), '9.10.0', reason: '9.10 is newer than 9.9');
    expect(latestGradle('{"version" : "9.9.0", "buildTime" : "x"}'), '9.9.0');
    expect(compareVersions('9.2', '9.2.0'), 0);
  });

  test("Flutter's known limits are read, and a version past one is said to be, plainly", () {
    const utils = "const maxKnownAndSupportedGradleVersion = '9.3.1';\nconst maxKnownAgpVersion = '9.2';\n"
        "const maxKnownAndSupportedKgpVersion = '2.4.0';\n";
    expect(flutterLimit(utils, 'maxKnownAndSupportedGradleVersion'), '9.3.1');
    final gradle = ToolMove('Gradle', '9.8.2', '9.9.0', flutterLimit(utils, 'maxKnownAndSupportedGradleVersion'));
    expect(gradle.moves, isTrue);
    expect(gradle.line(), "- Gradle: 9.8.2 → **9.9.0**; **past the pinned Flutter's known limit, 9.3.1**");
    final kotlin = ToolMove('Kotlin', '2.3.0', '2.3.0', '2.4.0');
    expect(kotlin.moves, isFalse);
    expect(kotlin.line(), "- Kotlin: 2.3.0 (latest 2.3.0); within the pinned Flutter's known limit, 2.4.0");
    expect(explanation([gradle, kotlin], '3.47.9'), contains("Flutter 3.47.9's own limits"));
    expect(explanation([gradle, kotlin], '3.47.9'), contains("hasn't been tested"));
  });

  test("a checksum that isn't one is refused, not written", () {
    const sha = 'f20c816177c0ff192881874852260771b462903aef3e794b0dac4759d1fda284';
    expect(withGradle(_props, '9.9.1', sha), contains('distributionSha256Sum=$sha'));
    // What services.gradle.org's 301 gives curl without -L (seen 2026-11-14).
    expect(() => withGradle(_props, '9.9.1', '<html>\r\n<head><title>301 Moved Permanently</title>'), throwsArgumentError);
    expect(() => withGradle(_props, '9.9.1', ''), throwsArgumentError);
  });

  test('a version is never moved backwards', () {
    expect(const ToolMove('Gradle', '9.8.2', '9.8.1', '9.3.1').target, '9.8.2');
  });
}
