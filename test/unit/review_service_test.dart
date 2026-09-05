// test/unit/review_service_test.dart - sending the user to the Play Store listing.
//
// Reported in 407: the home-screen link did nothing, on debug and release alike. 406 had used
// `InAppReview.requestReview()`, which asks Play to draw its in-app rating card - and Play draws
// one only when it feels like it (quota-limited, and never on a build it did not install), while
// reporting success either way. Nothing could distinguish a shown card from a silent no-op.
//
// So the contract held here is the one the bug violated: a tap the user made on purpose asks for
// something that always happens, and says so when it cannot.
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:cfg_pia_wg/review_service.dart';

/// Records what was asked of the plugin. Mocking the method channel would not do: the plugin picks
/// its behaviour from the host platform in Dart before the channel is reached.
class FakeInAppReview implements InAppReview {
  final List<String> calls = [];
  final Object? failWith;

  FakeInAppReview({this.failWith});

  @override
  Future<bool> isAvailable() async {
    calls.add('isAvailable');
    return true;
  }

  @override
  Future<void> requestReview() async => calls.add('requestReview');

  @override
  Future<void> openStoreListing({String? appStoreId, String? microsoftStoreId}) async {
    calls.add('openStoreListing');
    if (failWith != null) throw failWith!;
  }
}

void main() {
  test('opens the store listing', () async {
    final fake = FakeInAppReview();
    expect(await openPlayStoreReview(review: fake), isTrue);
    expect(fake.calls, ['openStoreListing']);
  });

  // The regression itself. Play answers requestReview successfully whether or not it drew anything,
  // so a link built on it cannot tell the user it failed - it just sits there doing nothing.
  test('never asks for the in-app rating card', () async {
    final fake = FakeInAppReview();
    await openPlayStoreReview(review: fake);
    expect(fake.calls, isNot(contains('requestReview')));
    expect(fake.calls, isNot(contains('isAvailable')), reason: 'nothing left to gate on');
  });

  test('a host that cannot open it returns false rather than throwing out of a tap handler', () async {
    final fake = FakeInAppReview(failWith: UnsupportedError('Platform(linux) not supported'));
    expect(await openPlayStoreReview(review: fake), isFalse);
  });

  test('with no plugin at all it is still a false, not an exception', () async {
    expect(await openPlayStoreReview(), isFalse);
  });
}
