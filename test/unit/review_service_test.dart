// test/unit/review_service_test.dart - asking Play for a review card.
//
// The flow is deliberately unobservable: Play answers `requestReview` immediately and decides for
// itself whether to draw anything, so the only thing worth asserting is which request was made.
// The cases that matter are the ones where nothing can be shown - a debug or sideloaded build has
// no review flow, and a tap that silently does nothing is worse than one that opens the listing.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kInAppReviewChannel);

  /// Answers the plugin channel, recording the methods asked of it. A null [available] leaves the
  /// handler absent, which is what a plain test - or a host with no Play Store - looks like.
  List<String> mockHost({bool? available}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
      channel,
      available == null
          ? null
          : (call) async {
              calls.add(call.method);
              return call.method == 'isAvailable' ? available : null;
            },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  test('an available flow is asked for the review card', () async {
    final calls = mockHost(available: true);
    expect(await requestAppReview(), isTrue);
    expect(calls, ['isAvailable', 'requestReview']);
  });

  test('an unavailable flow falls back to the store listing', () async {
    final calls = mockHost(available: false);
    // The host here is not Android, so the plugin refuses the listing and the caller reports it
    // could do nothing - on a real device this is the branch that opens Play.
    expect(await requestAppReview(), isFalse);
    expect(calls, ['isAvailable']);
    expect(calls, isNot(contains('requestReview')), reason: 'asking anyway would throw');
  });

  test('no plugin at all is a false, never an exception out of the tap handler', () async {
    mockHost();
    expect(await requestAppReview(), isFalse);
  });
}
