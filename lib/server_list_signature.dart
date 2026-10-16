// server_list_signature.dart - PIA's signature on its server list, checked before the list is used (ID-325).
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
// PIA signs the list at serverlist.piaservers.net, and its own desktop client refuses one that
// fails the check. Until build 497 this app threw the signature away. A forged list can't put a
// non-PIA server in the tunnel - addKey only trusts PIA's CA (ID-309) - but it can list real PIA
// servers from another country under the region the user chose, so traffic leaves from a country
// nobody chose. That is what this stops.
//
// Andrew's decision, 2026-10-13: refuse a list that fails, fall back to the last list that passed,
// and say so. The cost of refusing is on PIA's side - a key change, a change in how the list is
// signed, or a bug here - and the fallback takes most of it away. The watchdog does the same on the
// router, with the same key (`__PIALISTKEY__` in router_watchdog.dart).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'server_list_verify.dart';

export 'server_list_verify.dart' show kPiaServerListKeyPem, rsaPublicKeyFromPem;

/// The key the app checks with. Only a test changes it, to check lists it signed itself: PIA's
/// private key is PIA's, so a test can't make a list PIA's key accepts.
@visibleForTesting
String serverListKeyPem = kPiaServerListKeyPem;

/// The JSON of a server list download, or null when the download doesn't carry a valid signature.
///
/// The download is the JSON, a blank line, and the base64 of a signature over the JSON's bytes.
/// Split as PIA's client splits it (`JsonRefresher::readReply` in `common/src/jsonrefresher.cpp`):
/// after the last `}`. What comes back is exactly the bytes that were checked, so nothing else from
/// the download can be used. PIA's client also retries with `.piaproxy.net` put back to
/// `.privateinternetaccess.com`, for a proxy that rewrites the list in transit; this app doesn't
/// fetch through one, so a list rewritten that way fails here.
Uint8List? verifiedServerListJson(List<int> body, {String? keyPem}) =>
    verifySignedServerList(body, keyPem ?? serverListKeyPem);

/// Filename under the app-support directory for the last list that passed.
const String kServerListFile = 'pia_servers_verified.txt';

/// A list that passed, as it was downloaded, and when it was saved.
typedef SavedServerList = ({Uint8List body, DateTime savedAt});

/// The last server list that passed PIA's signature check, kept on the phone so a list that fails
/// can be refused without stopping the app (ID-325). Public PIA data and nothing about the user.
/// It is checked again every time it's used, so a file changed on the phone is refused like a
/// tampered download. SETTINGS -> REMOVE CACHED PIA SERVERS deletes it.
class ServerListStore {
  /// [directory] is a test seam, as in RouterPrefs: under `flutter test` the store is inert unless a
  /// test passes a directory, because the path_provider channel never answers there and an await on
  /// it hangs.
  ServerListStore({Future<Directory> Function()? directory})
      : _directory = directory ?? (Platform.environment.containsKey('FLUTTER_TEST') ? _inert : getApplicationSupportDirectory);

  static Future<Directory> _inert() async =>
      throw const FileSystemException('ServerListStore stores nothing under flutter test - pass `directory` to test it');

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File('${(await _directory()).path}/$kServerListFile');

  /// The saved list, or null when there is none or it can't be read.
  Future<SavedServerList?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return (body: await f.readAsBytes(), savedAt: await f.lastModified());
    } catch (_) {
      return null;
    }
  }

  /// Saves [body], a download that passed. Best effort: a failure here costs only the fallback.
  Future<void> write(List<int> body) async {
    try {
      await (await _file()).writeAsBytes(body, flush: true);
    } catch (_) {}
  }

  /// Deletes the saved list. True when one was there and is gone now, read back after the delete;
  /// false when there was nothing to delete. Throws if one is still there afterwards.
  Future<bool> remove() async {
    final File f;
    try {
      f = await _file();
    } catch (_) {
      return false;
    }
    if (!await f.exists()) return false;
    await f.delete();
    if (await f.exists()) throw FileSystemException('still there after the delete', f.path);
    return true;
  }
}
