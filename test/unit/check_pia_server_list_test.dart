// test/unit/check_pia_server_list_test.dart - the daily check that PIA's server list key hasn't
// changed (ID-409), run against PIA's real list and source as saved, never the network.
import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/server_list_verify.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_pia_server_list.dart';
import '../server_list_test_key.dart';

/// The definition as it stood in pia-foss/desktop's daemon/src/environment.cpp on 2026-10-16.
String _cpp(String pem) => '''
#include "environment.h"

const QByteArray Environment::defaultRegionsListPublicKey = QByteArrayLiteral(
${pem.split('\n').map((l) => '    "$l\\n"').join('\n').replaceFirst(RegExp(r'\\n"$'), '"')}
);

Environment::Environment(const StateModel &state)
''';

void main() {
  final realList = File(kRealServerListFixture).readAsBytesSync();
  // signedServerList points the app's check at the tests' key; this check passes keys explicitly,
  // but put PIA's back so no other test inherits it.
  tearDown(usePiaServerListKey);

  /// A fetch that answers from fixtures: PIA's source with [publishedPem], and [list] for the list.
  Future<List<int>?> Function(Uri) fetchFrom({String? publishedPem = kPiaServerListKeyPem, List<int>? list}) =>
      (uri) async => switch (uri.toString()) {
            kPublishedKeySource => publishedPem == null ? null : utf8.encode(_cpp(publishedPem)),
            kServerListUrl => list,
            _ => throw StateError('unexpected $uri'),
          };

  group('reading the published key', () {
    test('reads the key out of the source exactly as PIA writes it', () {
      expect(publishedKeyFromSource(_cpp(kPiaServerListKeyPem)), kPiaServerListKeyPem);
    });

    test('a source without the definition, or with only half a key, gives nothing', () {
      expect(publishedKeyFromSource('int main() {}'), isNull);
      expect(publishedKeyFromSource('defaultRegionsListPublicKey = QByteArrayLiteral("-----BEGIN PUBLIC KEY-----\\n");'), isNull);
    });

    test('line endings and armour make no difference to the comparison', () {
      expect(keyBody(kPiaServerListKeyPem.replaceAll('\n', '\r\n')), keyBody(kPiaServerListKeyPem));
      expect(comparePublished(_cpp(kPiaServerListKeyPem), kPiaServerListKeyPem), PublishedKey.matches);
      expect(comparePublished(_cpp(kTestServerListKeyPem), kPiaServerListKeyPem), PublishedKey.differs);
      expect(comparePublished(null, kPiaServerListKeyPem), PublishedKey.unavailable);
    });

    test('the swapped key is a different key, and PIA\'s real list fails with it', () {
      final swapped = swappedKey(kPiaServerListKeyPem);
      expect(keyBody(swapped), isNot(keyBody(kPiaServerListKeyPem)));
      expect(swapped.length, kPiaServerListKeyPem.length);
      expect(checkLive(realList, swapped), LiveList.fails);
    });
  });

  group('the live list', () {
    test("PIA's real list passes with our key; a list signed by another key fails; no download is neither", () {
      expect(checkLive(realList, kPiaServerListKeyPem), LiveList.passes);
      expect(checkLive(utf8.encode(signedServerList({'regions': []})), kPiaServerListKeyPem), LiveList.fails);
      expect(checkLive(null, kPiaServerListKeyPem), LiveList.unavailable);
      expect(checkLive([], kPiaServerListKeyPem), LiveList.unavailable);
    });
  });

  group('whether the key changed', () {
    test('a published key that differs is a change, whatever the list says', () {
      for (final live in LiveList.values) {
        expect(keyChanged(PublishedKey.differs, live, listFailedLastTime: false), isTrue, reason: live.name);
      }
    });

    test('a failing list is a change only when it failed last time too', () {
      expect(keyChanged(PublishedKey.matches, LiveList.fails, listFailedLastTime: false), isFalse);
      expect(keyChanged(PublishedKey.matches, LiveList.fails, listFailedLastTime: true), isTrue);
      expect(keyChanged(PublishedKey.unavailable, LiveList.fails, listFailedLastTime: true), isTrue);
    });

    test('nothing that could be read, or everything passing, is never a change', () {
      for (final published in [PublishedKey.matches, PublishedKey.unavailable]) {
        for (final live in [LiveList.passes, LiveList.unavailable]) {
          expect(keyChanged(published, live, listFailedLastTime: true), isFalse, reason: '${published.name} ${live.name}');
        }
      }
    });
  });

  group('the whole check', () {
    test("today's state - PIA's key and PIA's real list - is no change", () async {
      final r = await runCheck(fetch: fetchFrom(list: realList), listFailedLastTime: true);
      expect(r.changed, isFalse);
      expect(r.live, LiveList.passes);
    });

    test('both downloads failing is no change, even after a failure last time', () async {
      final r = await runCheck(fetch: fetchFrom(publishedPem: null), listFailedLastTime: true);
      expect(r.changed, isFalse);
      expect(r.live, LiveList.unavailable);
    });

    test('PIA publishing another key is a change, and the report carries the new key', () async {
      final r = await runCheck(fetch: fetchFrom(publishedPem: kTestServerListKeyPem, list: realList), listFailedLastTime: false);
      expect(r.changed, isTrue);
      expect(r.report, contains('DIFFERS from ours'));
      expect(r.report, contains(kTestServerListKeyPem));
      expect(r.report, isNot(contains('TEST RUN')));
    });

    test('the hand test: the swapped key fires on its first run, and says it is a test', () async {
      final r = await runCheck(fetch: fetchFrom(list: realList), listFailedLastTime: false, swapKey: true);
      expect(r.changed, isTrue);
      expect(r.live, LiveList.fails);
      expect(r.report, startsWith('TEST RUN'));
    });

    test('a list failing twice in a row is a change even with the source unreadable', () async {
      final other = utf8.encode(signedServerList({'regions': []}));
      final first = await runCheck(fetch: fetchFrom(publishedPem: null, list: other), listFailedLastTime: false);
      expect(first.changed, isFalse);
      expect(first.live, LiveList.fails);
      final second = await runCheck(fetch: fetchFrom(publishedPem: null, list: other), listFailedLastTime: true);
      expect(second.changed, isTrue);
      expect(second.report, contains('failed on the last run too'));
    });
  });
}
