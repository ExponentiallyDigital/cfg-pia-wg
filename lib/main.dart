// main.dart - Application entry point.
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
// The UI lives in app_shell.dart and the screens/ + widgets/ directories. PiaWgApp is re-exported
// here so `import 'package:cfg_pia_wg/main.dart'` keeps resolving the root widget.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_shell.dart';
import 'firmware.dart';
export 'app_shell.dart' show PiaWgApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(stampAppVersion());
  runApp(const PiaWgApp());
}

// Provenance for watchdog alert emails. Nothing reads it until a watchdog is deployed, minutes
// into a session at the earliest, so it is never worth holding the first frame for - and a
// platform that cannot answer just leaves the line off the email.
Future<void> stampAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appVersionLabel = 'v${info.version} build ${info.buildNumber}';
  } catch (_) {
    appVersionLabel = '';
  }
}
