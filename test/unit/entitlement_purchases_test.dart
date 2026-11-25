// test/unit/entitlement_purchases_test.dart - Entitlement's calls to the store, against a stand-in for RevenueCat's
// platform channel (ID-717).
//
// SonarCloud showed entitlement.dart at 53% line coverage: everything that reaches `Purchases` was uncovered,
// since a test build has no API key and so never sells. A test can give it one (`Entitlement.debugReset`) and
// answer the channel with the records RevenueCat sends, so launch, restore and the offering checks run. The one
// path left out is a purchase that completes: its offering needs a whole store product record.
import 'dart:async';
import 'dart:io';

import 'package:cfg_pia_wg/entitlement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('purchases_flutter');

Map<String, dynamic> _info({required bool unlocked}) {
  final entitlement = {
    'identifier': Entitlement.entitlementId,
    'isActive': true,
    'willRenew': false,
    'latestPurchaseDate': '2026-01-01T00:00:00Z',
    'originalPurchaseDate': '2026-01-01T00:00:00Z',
    'productIdentifier': 'unlock',
    'isSandbox': false,
    'ownershipType': 'PURCHASED',
    'store': 'PLAY_STORE',
    'periodType': 'NORMAL',
    'verification': 'NOT_REQUESTED',
  };
  return {
    'entitlements': {
      'all': unlocked ? {Entitlement.entitlementId: entitlement} : <String, dynamic>{},
      'active': unlocked ? {Entitlement.entitlementId: entitlement} : <String, dynamic>{},
      'verification': 'NOT_REQUESTED',
    },
    'allPurchaseDates': <String, dynamic>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <dynamic>[],
    'firstSeen': '2026-01-01T00:00:00Z',
    'originalAppUserId': r'$RCAnonymousID:test',
    'allExpirationDates': <String, dynamic>{},
    'requestDate': '2026-01-01T00:00:00Z',
  };
}

/// The store's channel, answering [answers] by method name; anything else with nothing. Returns the calls it got.
List<String> _store(Map<String, Object? Function()> answers) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call.method);
    return answers[call.method]?.call();
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Entitlement.debugReset(apiKey: 'test_key'));
  tearDown(Entitlement.debugReset);

  group('configure', () {
    test('a first run that holds nothing asks the store what this account owns, and unlocks on its answer', () async {
      final calls = _store({
        'getCustomerInfo': () => _info(unlocked: false),
        'syncPurchasesForResult': () => _info(unlocked: true),
      });
      final changes = <bool>[];
      await Entitlement.configure(onChanged: changes.add);

      expect(calls, containsAllInOrder(['getCustomerInfo', 'syncPurchasesForResult']));
      expect(calls, isNot(contains('restorePurchases')), reason: 'restore stays on a button the user presses');
      expect(changes, [true]);
      expect(Entitlement.isUnlocked, isTrue);
    });

    test('a customer the store already knows is not synced again, and is told once', () async {
      final calls = _store({'getCustomerInfo': () => _info(unlocked: true)});
      final changes = <bool>[];
      await Entitlement.configure(onChanged: changes.add);
      expect(calls, isNot(contains('syncPurchasesForResult')));
      expect(changes, [true]);
    });

    test('nothing owned anywhere stays locked, and says nothing changed', () async {
      _store({'getCustomerInfo': () => _info(unlocked: false), 'syncPurchasesForResult': () => _info(unlocked: false)});
      final changes = <bool>[];
      await Entitlement.configure(onChanged: changes.add);
      expect(changes, isEmpty);
      expect(Entitlement.isUnlocked, isFalse);
    });

    test('a store that cannot be reached is logged and never stops the app starting', () async {
      _store({'getCustomerInfo': () => throw PlatformException(code: '1', message: 'no store')});
      final logged = <String>[];
      await Entitlement.configure(onChanged: (_) {}, onLog: logged.add);
      expect(logged.single, startsWith('Store unavailable: '));
    });

    test('with no key it does nothing at all', () async {
      Entitlement.debugReset();
      final calls = _store({});
      await Entitlement.configure(onChanged: (_) => fail('no key, no store'));
      expect(calls, isEmpty);
    });
  });

  // The check made before a purchase or a restore: can the store's servers be found at all (LCK-7).
  group('whether the store can be reached', () {
    test('a name that resolves is reachable, one that gives no address is not', () async {
      Entitlement.hostLookup = (_) async => [InternetAddress('142.250.0.1')];
      expect(await Entitlement.storeReachable(), isTrue);
      Entitlement.hostLookup = (_) async => [];
      expect(await Entitlement.storeReachable(), isFalse);
    });

    test('a lookup that fails, or takes too long, is offline and not an error', () async {
      Entitlement.hostLookup = (_) async => throw const SocketException('no route');
      expect(await Entitlement.storeReachable(), isFalse);
      Entitlement.hostLookup = (_) async => throw TimeoutException('too slow');
      expect(await Entitlement.storeReachable(), isFalse);
    });

    test('it asks for the store of this platform by name', () async {
      String? asked;
      Entitlement.hostLookup = (host) async {
        asked = host;
        return [InternetAddress('142.250.0.1')];
      };
      await Entitlement.storeReachable();
      expect(asked, Entitlement.storeHost);
    });
  });

  group('restore', () {
    test('unlocks when the account owns the unlock, and says whether it does', () async {
      Entitlement.storeReachable = () async => true;
      _store({'restorePurchases': () => _info(unlocked: true)});
      expect(await Entitlement.restore(), isTrue);
      _store({'restorePurchases': () => _info(unlocked: false)});
      expect(await Entitlement.restore(), isFalse, reason: 'it lost it, or never had it');
    });

    test('an unreachable store is said at once, and the store is not asked', () async {
      Entitlement.storeReachable = () async => false;
      final calls = _store({'restorePurchases': () => _info(unlocked: true)});
      await expectLater(Entitlement.restore(), throwsA(isA<StoreUnreachableException>()));
      expect(calls, isEmpty);
    });
  });

  group('the offering', () {
    Map<String, Object?> offerings({Map<String, Object?>? current}) =>
        {'all': <String, dynamic>{}, 'current': current};
    Map<String, Object?> offering(String id) =>
        {'identifier': id, 'serverDescription': 'd', 'metadata': <String, dynamic>{}, 'availablePackages': <dynamic>[]};

    test('no current offering is logged, with how many exist, and there is nothing to sell', () async {
      _store({'getOfferings': () => offerings()});
      final logged = <String>[];
      Entitlement.debugReset(apiKey: 'test_key');
      await Entitlement.configure(onChanged: (_) {}, onLog: logged.add); // sets the log
      logged.clear();
      expect(await Entitlement.price(), isNull);
      expect(logged.single, contains('No current offering'));
      expect(logged.single, contains('(0 exist)'));
    });

    test('an offering with no packages names it, and says a new product may not have propagated', () async {
      _store({'getCustomerInfo': () => _info(unlocked: false), 'syncPurchasesForResult': () => _info(unlocked: false),
        'getOfferings': () => offerings(current: offering('default'))});
      final logged = <String>[];
      await Entitlement.configure(onChanged: (_) {}, onLog: logged.add);
      logged.clear();
      expect(await Entitlement.price(), isNull);
      expect(logged.single, contains('Offering "default" has no packages'));
    });

    test('a store that fails when asked for its offerings is logged, and there is nothing to sell', () async {
      _store({'getCustomerInfo': () => _info(unlocked: false), 'syncPurchasesForResult': () => _info(unlocked: false),
        'getOfferings': () => throw PlatformException(code: '1', message: 'down')});
      final logged = <String>[];
      await Entitlement.configure(onChanged: (_) {}, onLog: logged.add);
      logged.clear();
      expect(await Entitlement.price(), isNull);
      expect(logged.single, startsWith('Could not read the store offerings: '));
    });

    test('a purchase with nothing to buy throws, and a build with no key never reaches the store', () async {
      Entitlement.storeReachable = () async => true;
      _store({'getOfferings': () => offerings()});
      await expectLater(Entitlement.purchase(), throwsA(predicate((e) => '$e'.contains('nothing to buy'))));

      Entitlement.debugReset();
      final calls = _store({});
      await expectLater(Entitlement.purchase(), throwsA(predicate((e) => '$e'.contains('nothing to buy'))));
      expect(calls, isEmpty);
    });

    // A package, as RevenueCat sends one: the store's own price string is what the paywall shows.
    Map<String, Object?> package() => {
          'identifier': r'$rc_lifetime',
          'packageType': 'UNKNOWN',
          'product': {
            'identifier': 'unlock',
            'description': 'd',
            'title': 'Unlock',
            'price': 12.99,
            'priceString': 'A\$12.99',
            'currencyCode': 'AUD',
          },
          'presentedOfferingContext': {'offeringIdentifier': 'default'},
        };
    Map<String, Object?> withPackage() => offerings(current: {...offering('default'), 'availablePackages': [package()]});

    test("the price is the store's own string for the first package", () async {
      _store({'getOfferings': withPackage});
      expect(await Entitlement.price(), r'A$12.99');
    });

    test('a purchase that clears unlocks, and is told to the screen', () async {
      Entitlement.storeReachable = () async => true;
      final changes = <bool>[];
      _store({'getCustomerInfo': () => _info(unlocked: false), 'syncPurchasesForResult': () => _info(unlocked: false)});
      await Entitlement.configure(onChanged: changes.add); // registers the screen's callback
      _store({
        'getOfferings': withPackage,
        'purchasePackage': () => {
              'customerInfo': _info(unlocked: true),
              'transaction': {'transactionIdentifier': 't1', 'productIdentifier': 'unlock', 'purchaseDate': '2026-01-01T00:00:00Z'},
            },
      });
      expect(await Entitlement.purchase(), isTrue);
      expect(changes, [true]);
      expect(Entitlement.isUnlocked, isTrue);
    });

    test('a purchase the user cancels is not an error, and returns false', () async {
      Entitlement.storeReachable = () async => true;
      _store({'getOfferings': withPackage, 'purchasePackage': () => throw PlatformException(code: '1', message: 'cancelled')});
      expect(await Entitlement.purchase(), isFalse);
    });

    test('any other store error is thrown for the paywall to explain', () async {
      Entitlement.storeReachable = () async => true;
      _store({'getOfferings': withPackage, 'purchasePackage': () => throw PlatformException(code: '2', message: 'store problem')});
      await expectLater(Entitlement.purchase(), throwsA(isA<PlatformException>()));
    });

    test('a purchase on an unreachable store says so before the store is asked', () async {
      Entitlement.storeReachable = () async => false;
      final calls = _store({'getOfferings': () => offerings()});
      await expectLater(Entitlement.purchase(), throwsA(isA<StoreUnreachableException>()));
      expect(calls, isEmpty);
    });
  });
}
