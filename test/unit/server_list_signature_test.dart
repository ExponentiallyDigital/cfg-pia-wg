// PIA's signature on its server list (ID-325): the check, the fallback to the last list that
// passed, and the phone's copy of that list.
//
// The real list in test/fixtures is checked with PIA's real key, so a wrong reading of how PIA signs
// - which bytes, which hash, how the signature is encoded - fails here rather than every rebuild.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/server_list_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../http_test_helpers.dart';
import '../server_list_test_key.dart';

Uint8List _real() => File(kRealServerListFixture).readAsBytesSync();

/// [body] with the first [from] in its JSON changed to [to], the signature left as it was.
Uint8List _tampered(Uint8List body, String from, String to) {
  final text = latin1.decode(body);
  expect(text.contains(from), isTrue, reason: 'the fixture should contain $from');
  return Uint8List.fromList(latin1.encode(text.replaceFirst(from, to)));
}

Future<Directory> _tempDir() async {
  final d = await Directory.systemTemp.createTemp('serverlist_');
  addTearDown(() => d.delete(recursive: true));
  return d;
}

void main() {
  tearDown(usePiaServerListKey);

  group("PIA's key", () {
    test('is the 2048-bit RSA key from PIA\'s desktop client', () {
      final key = rsaPublicKeyFromPem(kPiaServerListKeyPem);
      expect(key.modulus!.bitLength, 2048);
      expect(key.exponent, BigInt.from(65537));
      // The first and last bytes of the modulus as PIA's PEM spells them, so a copying slip shows.
      expect(key.modulus!.toRadixString(16), startsWith('ccb607c17e54'));
      expect(key.modulus!.toRadixString(16), endsWith('3ac99421'));
    });

    test('anything but an RSA public key is refused', () {
      expect(() => rsaPublicKeyFromPem('-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----'),
          throwsA(isA<FormatException>()));
      // An Ed25519 key: right shape, wrong algorithm.
      expect(
          () => rsaPublicKeyFromPem(
              '-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=\n-----END PUBLIC KEY-----'),
          throwsA(isA<FormatException>()));
    });
  });

  group('the check', () {
    test("PIA's real list passes with PIA's key, and what comes back is the signed JSON", () {
      final body = _real();
      final json = verifiedServerListJson(body);
      expect(json, isNotNull);
      final firstLine = body.sublist(0, body.indexOf(10));
      expect(json, firstLine);
      expect((jsonDecode(utf8.decode(json!)) as Map)['regions'], isNotEmpty);
    });

    test('a list with one region moved to another country is refused', () {
      // The exposure this exists for: real PIA servers listed under the region the user chose.
      expect(verifiedServerListJson(_tampered(_real(), '"country":"AU"', '"country":"US"')), isNull);
    });

    test('one byte changed anywhere in the JSON is refused', () {
      final body = _real();
      for (final at in [0 + 1, body.length ~/ 3, body.indexOf(10) - 2]) {
        final b = Uint8List.fromList(body)..[at] ^= 0x01;
        expect(verifiedServerListJson(b), isNull, reason: 'byte $at changed');
      }
    });

    test('a changed, cut short or missing signature is refused', () {
      final body = _real();
      final nl = body.indexOf(10);
      final sigStart = nl + 2;
      // A different signature character.
      final changed = Uint8List.fromList(body);
      changed[sigStart + 5] = changed[sigStart + 5] == 0x41 ? 0x42 : 0x41;
      expect(verifiedServerListJson(changed), isNull);
      expect(verifiedServerListJson(body.sublist(0, body.length - 20)), isNull);
      expect(verifiedServerListJson(body.sublist(0, nl + 1)), isNull);
      expect(verifiedServerListJson(Uint8List.fromList([...body.sublist(0, nl + 1), ...ascii.encode('\n!!!!\n')])), isNull);
    });

    test('a list signed with any other key is refused', () {
      final ours = utf8.encode(signedServerList({'regions': []}));
      usePiaServerListKey();
      expect(verifiedServerListJson(ours), isNull);
      expect(verifiedServerListJson(ours, keyPem: kTestServerListKeyPem), isNotNull);
    });

    test('not a list at all is refused', () {
      expect(verifiedServerListJson([]), isNull);
      expect(verifiedServerListJson(ascii.encode('<html>502 Bad Gateway</html>')), isNull);
      expect(verifiedServerListJson(ascii.encode('{"regions":[]')), isNull);
    });
  });

  group("the phone's copy of the last list that passed", () {
    test('is written, read back with its date, and removed, read back again', () async {
      final dir = await _tempDir();
      final store = ServerListStore(directory: () async => dir);
      expect(await store.read(), isNull);
      expect(await store.remove(), isFalse);
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      await store.write([1, 2, 3]);
      final saved = await store.read();
      expect(saved!.body, [1, 2, 3]);
      expect(saved.savedAt.isAfter(before), isTrue);
      expect(await store.remove(), isTrue);
      expect(File('${dir.path}/$kServerListFile').existsSync(), isFalse);
      expect(await store.read(), isNull);
    });

    test('is inert under flutter test unless given a directory', () async {
      final store = ServerListStore();
      await store.write([1]);
      expect(await store.read(), isNull);
      expect(await store.remove(), isFalse);
    });
  });

  group('fetchRegions', () {
    final good = signedRegionList([
      (id: 'nz', wg: [(ip: '192.0.2.1', cn: 'nz401')]),
    ]);
    // The same list with the server moved to another region's address, signature unchanged.
    final forged = good.replaceFirst('192.0.2.1', '198.51.100.9');
    setUp(useTestServerListKey);

    // The service is made inside the fake's zone: its HttpClient is made with it, and one made
    // outside reaches the real PIA.
    Future<(PiaService, List<Region>)> fetch(Directory dir, String body, [List<String>? log]) =>
        withFakeHttpClient(() async {
          final service = PiaService(serverListStore: ServerListStore(directory: () async => dir));
          return (service, await service.fetchRegions(onProgress: log?.add));
        }, (u, m) => FakeHttpClientResponse(200, body));

    test('a list that passes is used, and kept on the phone', () async {
      final dir = await _tempDir();
      final log = <String>[];
      final (service, regions) = await fetch(dir, good, log);
      expect(regions.single.wgServers.single.ip, '192.0.2.1');
      expect(service.fallbackListDate, isNull);
      expect(log, contains("Server list verified: it carries PIA's signature."));
      expect(File('${dir.path}/$kServerListFile').readAsStringSync(), good);
    });

    test('a list that fails gives way to the last list that passed, and says so', () async {
      final dir = await _tempDir();
      await fetch(dir, good);
      final log = <String>[];
      final (service, regions) = await fetch(dir, forged, log);
      expect(regions.single.wgServers.single.ip, '192.0.2.1', reason: 'the forged server must not be offered');
      expect(service.fallbackListDate, isNotNull);
      expect(log, contains("The server list failed PIA's signature check, so it isn't used: it might have been tampered with."));
      expect(log.last, startsWith('Using the last server list that passed, verified on ${listDay(DateTime.now())}'));
      // The saved list is still the good one: a failed list never replaces it.
      expect(File('${dir.path}/$kServerListFile').readAsStringSync(), good);
      // And the next list that passes clears the fallback.
      final (again, _) = await fetch(dir, good);
      expect(again.fallbackListDate, isNull);
    });

    test('a list that fails with nothing earlier to fall back on is refused', () async {
      final dir = await _tempDir();
      await expectLater(fetch(dir, forged), throwsA(predicate((e) => e.toString().contains(kServerListRefused))));
      expect(File('${dir.path}/$kServerListFile').existsSync(), isFalse);
    });

    test('a saved list that no longer passes is refused too, as a tampered download is', () async {
      final dir = await _tempDir();
      File('${dir.path}/$kServerListFile').writeAsStringSync(forged);
      await expectLater(fetch(dir, forged), throwsA(predicate((e) => e.toString().contains(kServerListRefused))));
    });

    test("PIA's real list, checked with PIA's key, end to end", () async {
      usePiaServerListKey();
      final dir = await _tempDir();
      final text = utf8.decode(_real());
      final (_, regions) = await fetch(dir, text);
      expect(regions.map((r) => r.id), contains('aus_perth'));
      expect(File('${dir.path}/$kServerListFile').readAsBytesSync(), _real());
      // And PIA's list, one region moved to another country, gets nothing through.
      await expectLater(fetch(await _tempDir(), text.replaceFirst('"country":"AU"', '"country":"US"')),
          throwsA(predicate((e) => e.toString().contains(kServerListRefused))));
    });
  });

  test('the fallback notice gives the date and says why', () {
    final notice = serverListFallbackNotice(DateTime(2026, 10, 14, 9));
    expect(notice, contains('verified on 2026-10-14'));
    expect(notice, contains('might have been tampered with'));
    expect(notice, contains('added or moved since then'));
  });
}
