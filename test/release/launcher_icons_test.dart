// test/release/launcher_icons_test.dart - the repair that keeps flutter_launcher_icons from damaging
// the Xcode project (ID-374).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/launcher_icons.dart';

/// What flutter_launcher_icons 0.14.4 does to the project file, line for line: inside the build
/// configurations, every line containing ASSETCATALOG is set to the icon name (its ios.dart,
/// changeIosLauncherIcon). Reproduced here so the test needs no Flutter project of its own.
String toolEdit(String project, String iconName) {
  var inConfig = false;
  String? config;
  final lines = project.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.contains('/* Begin XCBuildConfiguration section */')) inConfig = true;
    if (line.contains('/* End XCBuildConfiguration section */')) inConfig = false;
    if (!inConfig) continue;
    final m = RegExp(r'.*/\* (.*)\.xcconfig \*/;').firstMatch(line);
    if (m != null) config = m.group(1);
    if (config != null && line.contains('ASSETCATALOG')) {
      lines[i] = line.replaceAll(RegExp(r'=(.*);'), '= $iconName;');
    }
  }
  return lines.join('\n');
}

void main() {
  final real = File(kXcodeProjectPath).readAsStringSync();

  test('the real project file has the setting the tool breaks, so the test below means something', () {
    expect(real, contains('ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;'));
    final damaged = toolEdit(real, 'AppIcon');
    expect(damaged, contains('ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;'),
        reason: 'the damage seen on 2026-10-09');
  });

  test('puts back what the tool broke, and leaves the file exactly as it was when the icon name is unchanged', () {
    final (repaired, restored) = repairProjectFile(real, toolEdit(real, 'AppIcon'));
    expect(repaired, real);
    expect(restored, greaterThan(0));
  });

  test("keeps the tool's own change: a new icon set's name", () {
    final (repaired, _) = repairProjectFile(real, toolEdit(real, 'AppIcon-dev'));
    expect(repaired, contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-dev;'));
    expect(repaired, isNot(contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')));
    expect(repaired, isNot(contains('EXTENSIONS = AppIcon')));
    expect('\n'.allMatches(repaired).length, '\n'.allMatches(real).length);
  });

  test('a file rewritten beyond line-for-line changes is put back whole', () {
    final (repaired, restored) = repairProjectFile(real, '$real\nsomething added\n');
    expect(repaired, real);
    expect(restored, -1);
  });

  test('an untouched file is left alone', () {
    expect(repairProjectFile(real, real), (real, 0));
  });
}
