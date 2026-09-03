// clipboard_service.dart - Emptying the system clipboard without a system popup.
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
// The clipboard used to be emptied by copying an empty string to it. That works, but Android
// shows its clipboard preview for any copy, so exiting the app - or the 60-second countdown
// expiring - flashed a "copied"/"cleared" popup at a user who had not copied anything.
// ClipboardManager.clearPrimaryClip() empties it silently instead.

import 'package:flutter/services.dart';

/// The channel MainActivity.kt registers in `configureFlutterEngine`.
const MethodChannel clipboardChannel = MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/clipboard');

/// The method the channel answers.
const String kClearClipboardMethod = 'clearClipboard';

/// Empties the system clipboard, silently where the host can.
///
/// Falls back to writing an empty string - the old behaviour, popup and all - whenever the host
/// cannot answer: a platform without the handler, a widget test with no plugin registered, or
/// API 24..27, where `clearPrimaryClip()` does not exist and MainActivity says so.
Future<void> clearSystemClipboard() async {
  try {
    await clipboardChannel.invokeMethod<void>(kClearClipboardMethod);
  } on MissingPluginException {
    await _writeEmpty();
  } on PlatformException {
    await _writeEmpty();
  }
}

Future<void> _writeEmpty() => Clipboard.setData(const ClipboardData(text: ''));
