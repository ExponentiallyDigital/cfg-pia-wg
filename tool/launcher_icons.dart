// tool/launcher_icons.dart - runs flutter_launcher_icons without letting it damage the Xcode project (ID-374).
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
// Run instead of the tool itself: `dart run tool/launcher_icons.dart`, as scripts/build.ps1,
// scripts/build.sh and the workflows do. Any arguments are passed on to the tool.
//
// flutter_launcher_icons 0.14.4 sets every line of ios/Runner.xcodeproj/project.pbxproj that
// contains ASSETCATALOG to the icon set's name, whenever it writes iOS icons. The one it means is
// ASSETCATALOG_COMPILER_APPICON_NAME; it also turns the yes/no setting
// ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS into "AppIcon". Unfixed upstream:
// the fix, https://github.com/fluttercommunity/flutter_launcher_icons/pull/549, has been open since
// March 2024. So this keeps the project file as it was, less the tool's one intended change.

import 'dart:io';

/// The Xcode project the tool edits.
const String kXcodeProjectPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// The setting the tool is meant to change: which icon set the app uses.
const String kAppIconSetting = 'ASSETCATALOG_COMPILER_APPICON_NAME';

/// [after], the project file as the tool left it, with every line it changed put back as it was in
/// [before], except a line setting [kAppIconSetting], and the number of lines put back.
///
/// The tool only ever replaces lines in place, so the two have the same number of lines. If they
/// don't, something else rewrote the file, and [before] is returned whole rather than guessing.
(String, int) repairProjectFile(String before, String after) {
  final was = before.split('\n'), now = after.split('\n');
  if (was.length != now.length) return (before, -1);
  var restored = 0;
  for (var i = 0; i < now.length; i++) {
    if (now[i] == was[i] || was[i].contains(kAppIconSetting)) continue;
    now[i] = was[i];
    restored++;
  }
  return (now.join('\n'), restored);
}

Future<void> main(List<String> args) async {
  final project = File(kXcodeProjectPath);
  final before = project.existsSync() ? project.readAsStringSync() : null;

  // The Dart that is running this, so the tool runs on the same SDK with no shell in between.
  final tool = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'flutter_launcher_icons', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await tool.exitCode;

  if (before != null && project.existsSync()) {
    final after = project.readAsStringSync();
    if (after != before) {
      final (repaired, restored) = repairProjectFile(before, after);
      project.writeAsStringSync(repaired);
      stdout.writeln(restored < 0
          ? 'launcher_icons: $kXcodeProjectPath was rewritten beyond recognition, so it is put back whole.'
          : 'launcher_icons: put back $restored line(s) of $kXcodeProjectPath that flutter_launcher_icons '
              'should not have changed.');
    }
  }
  exit(code);
}
