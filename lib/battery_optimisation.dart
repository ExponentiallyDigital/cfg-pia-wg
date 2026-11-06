// battery_optimisation.dart - Whether Android is optimising the app's battery use (ID-521).
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
// On a Galaxy Tab S10 FE (Android 16), 2026-11-05, the home screen widget refreshed only while the
// app was open: with battery optimisation on, Android held back its background refresh, and turning
// it off fixed it. HOME SCREEN WIDGET KEY says so, and offers the app's own page in Android's
// settings, where Battery -> Unrestricted is one tap away. That page needs no permission; asking
// Android to exempt the app directly needs one Google Play restricts.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel MainActivity.kt registers in `configureFlutterEngine`.
const MethodChannel batteryChannel = MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/battery');

/// True when Android is optimising the app's battery use: anything but Unrestricted.
const String kIsBatteryOptimisedMethod = 'isBatteryOptimised';

/// Opens the app's own page in Android's settings.
const String kOpenAppSettingsMethod = 'openAppSettings';

/// Shown in HOME SCREEN WIDGET KEY while it is on.
const String kBatteryOptimisedText = 'Battery optimisation is on for this app, so Android may only let the widget '
    'refresh while the app is open. In the settings, tap Battery, then Unrestricted.';

/// True only on Android, and only when it says the app is optimised. False wherever it cannot tell:
/// a missing warning costs less than a wrong one.
Future<bool> batteryOptimised() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await batteryChannel.invokeMethod<bool>(kIsBatteryOptimisedMethod) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Opens the app's page in Android's settings. Nothing happens anywhere else.
Future<void> openAppSettings() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await batteryChannel.invokeMethod<void>(kOpenAppSettingsMethod);
  } on PlatformException {
    // Nothing to show: the settings page simply did not open.
  } on MissingPluginException {
    // As above.
  }
}
