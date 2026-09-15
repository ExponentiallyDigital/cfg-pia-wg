// test/unit/review_service_test.dart - sending the user to the Play Store listing.
//
// Reported in 407: the home-screen link did nothing, on debug and release alike. 406 had asked Play
// for its in-app rating card, and Play draws one only when it feels like it (quota-limited, and never
// on a build it did not install), while reporting success either way. Nothing could distinguish a
// shown card from a silent no-op.
//
// So the contract held here is the one the bug violated: a tap the user made on purpose asks for
// something that always happens, and says so when it cannot. Since ID-042 the listing opens through
// url_launcher rather than the in_app_review plugin, so these tests mock url_launcher's channel.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/review_service.dart';

/// Answers url_launcher's method channel for one test and records every call made on it.
///
/// [opens] is what `launch` answers; [failWith] makes it throw instead. Shared with the main menu
/// tests, which tap the real link.
List<MethodCall> installUrlLauncherMock({bool opens = true, Object? failWith}) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (failWith != null) throw failWith;
    return opens;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opens the store listing in the Play Store app, not an in-app browser', () async {
    final calls = installUrlLauncherMock();
    expect(await openPlayStoreReview(), isTrue);
    expect(calls.map((c) => c.method), ['launch'], reason: 'one launch, nothing gating it first');
    final args = calls.single.arguments as Map;
    expect(args['url'], kPlayStoreListingUrl);
    // platformDefault would open an https link in a browser tab inside the app, showing Play's web
    // page rather than handing the link to the Play Store app.
    expect(args['useWebView'], isFalse);
  });

  // The listing id is written out, not read from the running package, so hold it to the build's.
  test('the listing is the Play application id the build declares', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final id = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)!.group(1);
    expect(kPlayStoreListingUrl, 'https://play.google.com/store/apps/details?id=$id');
  });

  test('nothing to open it with returns false', () async {
    installUrlLauncherMock(opens: false);
    expect(await openPlayStoreReview(), isFalse);
  });

  test('a platform error returns false rather than throwing out of a tap handler', () async {
    installUrlLauncherMock(failWith: PlatformException(code: 'ACTIVITY_NOT_FOUND'));
    expect(await openPlayStoreReview(), isFalse);
  });

  test('with no url_launcher at all it is still a false, not an exception', () async {
    expect(await openPlayStoreReview(), isFalse);
  });
}
