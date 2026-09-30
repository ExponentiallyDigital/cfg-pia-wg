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

/// The methods the channel answers. Mirrored in MainActivity.kt; a test fails if they drift apart.
const String kClearClipboardMethod = 'clearClipboard';
const String kCopySensitiveMethod = 'copySensitive';

/// Empties the system clipboard, silently where the host can.
///
/// Returns true when the host read the clipboard back and found it empty, false when it cleared it
/// but could not check - Android 10+ hides the clipboard from an app without focus, as when the
/// 60-second countdown ends with the app in the background - and null when it fell back to writing
/// an empty string, which leaves nothing on the clipboard to leak (ID-313).
///
/// Falls back to writing an empty string - the old behaviour, popup and all - whenever the host
/// cannot answer: a platform without the handler, a widget test with no plugin registered, or
/// API 24..27, where `clearPrimaryClip()` does not exist and MainActivity says so.
Future<bool?> clearSystemClipboard() async {
  try {
    return await clipboardChannel.invokeMethod<bool>(kClearClipboardMethod);
  } on MissingPluginException {
    await _writeEmpty();
  } on PlatformException {
    await _writeEmpty();
  }
  return null;
}

/// Copies [text] marked sensitive, so Android 13+ hides it in the clipboard preview (ID-313), and
/// labelled as this app's, so MainActivity can clear it at the next start if the app was killed first. Falls back to a plain copy.
Future<void> copySensitive(String text) async {
  try {
    await clipboardChannel.invokeMethod<void>(kCopySensitiveMethod, {'text': text});
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text));
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

Future<void> _writeEmpty() => Clipboard.setData(const ClipboardData(text: ''));
