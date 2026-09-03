// build_info_service.dart - Build and runtime provenance, read from the Android host.
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
// The values originate in two places: android/app/build.gradle.kts bakes the git/CI/toolchain
// facts into BuildConfig at configuration time, and MainActivity.kt adds the device-side facts
// (installer, ABI, OS version) before handing the lot over this channel. The app's other
// platform channel is clipboard_service.dart's.

import 'package:flutter/services.dart';

/// The channel MainActivity.kt registers in `configureFlutterEngine`.
const MethodChannel buildInfoChannel =
    MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/build_info');

/// The method the channel answers.
const String kGetBuildInfoMethod = 'getBuildInfo';

/// Placeholder used for every field the host could not determine.
const String kUnknownBuildValue = 'unknown';

/// An immutable snapshot of how this binary was built and where it is running.
class BuildInfo {
  final String versionName;
  final String buildNumber;
  final String installer;
  final String buildTimestamp;
  final String buildType;
  final String commitHash;
  final String commitDate;
  final String gitBranch;
  final String runnerId;
  final String cpuAbi;
  final String osVersion;
  final String compileSdk;
  final String kotlinVersion;

  const BuildInfo({
    required this.versionName,
    required this.buildNumber,
    required this.installer,
    required this.buildTimestamp,
    required this.buildType,
    required this.commitHash,
    required this.commitDate,
    required this.gitBranch,
    required this.runnerId,
    required this.cpuAbi,
    required this.osVersion,
    required this.compileSdk,
    required this.kotlinVersion,
  });

  /// Every field defaults to [kUnknownBuildValue] so a host that grows a new key, or drops an
  /// old one, degrades one line at a time instead of throwing.
  factory BuildInfo.fromMap(Map<String, String> map) {
    String value(String key) => map[key]?.trim().isNotEmpty == true ? map[key]!.trim() : kUnknownBuildValue;

    return BuildInfo(
      versionName: value('versionName'),
      buildNumber: value('buildNumber'),
      installer: value('installer'),
      buildTimestamp: value('buildTimestamp'),
      buildType: value('buildType'),
      commitHash: value('commitHash'),
      commitDate: value('commitDate'),
      gitBranch: value('gitBranch'),
      runnerId: value('runnerId'),
      cpuAbi: value('cpuAbi'),
      osVersion: value('osVersion'),
      compileSdk: value('compileSdk'),
      kotlinVersion: value('kotlinVersion'),
    );
  }

  /// Used when the channel is unavailable (widget tests, or any non-Android host).
  const BuildInfo.unknown()
      : versionName = kUnknownBuildValue,
        buildNumber = kUnknownBuildValue,
        installer = kUnknownBuildValue,
        buildTimestamp = kUnknownBuildValue,
        buildType = kUnknownBuildValue,
        commitHash = kUnknownBuildValue,
        commitDate = kUnknownBuildValue,
        gitBranch = kUnknownBuildValue,
        runnerId = kUnknownBuildValue,
        cpuAbi = kUnknownBuildValue,
        osVersion = kUnknownBuildValue,
        compileSdk = kUnknownBuildValue,
        kotlinVersion = kUnknownBuildValue;
}

/// Fetches the host's build info, falling back to [BuildInfo.unknown] on any channel failure.
///
/// The catch is load-bearing rather than defensive padding: under `flutter test` no platform
/// implementation is registered, so the call raises [MissingPluginException]. Swallowing it here
/// keeps the About screen renderable in tests and on any host without the native side.
Future<BuildInfo> loadBuildInfo({MethodChannel channel = buildInfoChannel}) async {
  try {
    final map = await channel.invokeMapMethod<String, String>(kGetBuildInfoMethod);
    return map == null ? const BuildInfo.unknown() : BuildInfo.fromMap(map);
  } on MissingPluginException {
    return const BuildInfo.unknown();
  } on PlatformException {
    return const BuildInfo.unknown();
  }
}
