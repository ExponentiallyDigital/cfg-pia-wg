// share_plus's copy of a shared config is deleted (ID-312).
//
// The unit half: the folder share_plus copies into is removed, with what is in it. That the real
// share_plus writes there, and that leaving the screen clears it, is checked on an emulator
// (scripts/check-claims.sh's app half; CHANGELOG ID-312).
import 'dart:io';

import 'package:cfg_pia_wg/share_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('share_cache_'));
  tearDown(() => cache.deleteSync(recursive: true));

  test('share_plus\'s copy of a config is deleted, private key and all', () async {
    final copy = File('${cache.path}/$kSharePlusCacheFolder/pia-nz.conf')
      ..createSync(recursive: true)
      ..writeAsStringSync('[Interface]\nPrivateKey = test\n');
    final other = File('${cache.path}/other.txt')..writeAsStringSync('not ours');
    expect(await clearShareCache(cacheDir: () async => cache), isTrue);
    expect(copy.existsSync(), isFalse);
    expect(Directory('${cache.path}/$kSharePlusCacheFolder').existsSync(), isFalse);
    expect(other.existsSync(), isTrue, reason: 'only share_plus\'s folder is touched');
  });

  test('nothing to clear is not a failure', () async {
    expect(await clearShareCache(cacheDir: () async => cache), isTrue);
  });

  test('under flutter test with no directory it does nothing, rather than hang on path_provider', () async {
    expect(await clearShareCache(), isFalse);
  });
}
