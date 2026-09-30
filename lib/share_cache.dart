// share_cache.dart - clears the copy of a shared config that share_plus keeps (ID-312).
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
// SHARE writes the config to a temp file and deletes it when the share sheet returns. But
// share_plus (13.3.0, Share.kt copyToShareCacheFolder) first COPIES the file into
// <cache>/share_plus/ and hands the other app that copy, and it clears the folder only at the
// NEXT share - so a config, private key and all, stayed on the phone indefinitely, while the docs
// promised it was wiped (claims audit #6). The copy cannot be deleted the moment the sheet closes:
// the app it went to may not have read it yet. So it goes when the config screen is left, when the
// app exits, and when it next starts.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// share_plus's folder under the app's cache directory.
const String kSharePlusCacheFolder = 'share_plus';

/// Deletes share_plus's cached copies. Never throws. [cacheDir] is a test seam: under
/// `flutter test` the real lookup never answers, so it does nothing unless a test passes one.
Future<bool> clearShareCache({Future<Directory> Function()? cacheDir}) async {
  if (cacheDir == null && Platform.environment.containsKey('FLUTTER_TEST')) return false;
  try {
    final d = Directory('${(await (cacheDir ?? getTemporaryDirectory)()).path}/$kSharePlusCacheFolder');
    if (!await d.exists()) return true;
    await d.delete(recursive: true);
    return !await d.exists();
  } catch (_) {
    return false;
  }
}
