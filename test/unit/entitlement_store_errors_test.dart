// test/unit/entitlement_store_errors_test.dart - what the paywall says when the store says no (ID-189).
//
// A purchase that fails is the one moment a paying customer reads this app's words about money, so
// every store error has to come out as a sentence they can act on. And a build with no store key -
// every sideloaded and F-Droid-style build - must sell nothing and never reach the SDK.
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

PlatformException _store(PurchasesErrorCode code, {String? message}) =>
    PlatformException(code: '${code.index}', message: message);

void main() {
  group('describeStoreError', () {
    test('each store error the paywall can meet reads as a sentence, with the code for a bug report', () {
      const expected = {
        PurchasesErrorCode.paymentPendingError: 'Payment is pending.',
        PurchasesErrorCode.networkError: 'Could not reach the store.',
        PurchasesErrorCode.productAlreadyPurchasedError: 'already owns the unlock. Use Restore.',
        PurchasesErrorCode.purchaseNotAllowedError: 'Purchases are not allowed',
        PurchasesErrorCode.productNotAvailableForPurchaseError: 'not available to buy right now',
        PurchasesErrorCode.storeProblemError: 'Google Play could not complete the payment.',
      };
      expected.forEach((code, words) {
        final text = Entitlement.describeStoreError(_store(code));
        expect(text, contains(words), reason: code.name);
        expect(text, endsWith('(${code.name})'), reason: code.name);
      });
    });

    test("any other store error keeps the store's own message", () {
      expect(Entitlement.describeStoreError(_store(PurchasesErrorCode.invalidCredentialsError, message: 'Bad key')),
          'Bad key (invalidCredentialsError)');
      expect(Entitlement.describeStoreError(_store(PurchasesErrorCode.invalidCredentialsError)),
          'The store reported an error. (invalidCredentialsError)');
    });

    test('a code the plugin cannot read falls back to the message, then the code', () {
      expect(Entitlement.describeStoreError(PlatformException(code: 'not-a-number', message: 'odd')), 'odd');
      expect(Entitlement.describeStoreError(PlatformException(code: 'not-a-number')), 'not-a-number');
    });

    test('anything that is not a store error is shown without the Exception prefix', () {
      expect(Entitlement.describeStoreError(Exception('nothing to buy')), 'nothing to buy');
    });
  });

  group('isPaymentPending', () {
    test('only a pending payment counts', () {
      expect(Entitlement.isPaymentPending(_store(PurchasesErrorCode.paymentPendingError)), isTrue);
      expect(Entitlement.isPaymentPending(_store(PurchasesErrorCode.networkError)), isFalse);
      expect(Entitlement.isPaymentPending(PlatformException(code: 'not-a-number')), isFalse);
      expect(Entitlement.isPaymentPending(Exception('no')), isFalse);
    });
  });

  // Tests run without REVENUECAT_ANDROID_KEY, exactly like a build that has no store.
  group('a build with no store key', () {
    test('has nothing to sell and never touches the SDK', () async {
      expect(Entitlement.purchasingAvailable, isFalse);
      expect(await Entitlement.price(), isNull);
      await expectLater(Entitlement.purchase(), throwsA(isA<Exception>()));
    });

    test('configure returns at once and reports nothing', () async {
      var changed = 0;
      final logged = <String>[];
      await Entitlement.configure(onChanged: (_) => changed++, onLog: logged.add);
      expect(changed, 0);
      expect(logged, isEmpty);
    });

    test('is unlocked, unless a test pins it', () {
      expect(Entitlement.isUnlocked, isTrue);
      Entitlement.debugSetUnlocked(false);
      addTearDown(() => Entitlement.debugSetUnlocked(null));
      expect(Entitlement.isUnlocked, isFalse);
    });
  });
}
