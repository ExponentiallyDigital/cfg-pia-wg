// test/unit/app_shell_launch_test.dart - the app shell's navigator observer, and the store at launch (ID-717).
//
// SonarCloud showed app_shell.dart at 83% line coverage: the observer's handling of a route removed or replaced
// (the pages a `pushReplacement` and a `removeRoute` leave behind) and the launch-time purchasing step were not
// run by any test. The first is plain navigator calls; the second needs a store key, which a test build lacks, so
// a test gives it one and answers RevenueCat's channel.
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../app_test_harness.dart';

PageRoute<void> _page(AppDestination d) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: d.routeName), builder: (_) => const SizedBox());

/// A dialog is a route but not a page, and the observer must ignore it.
Route<void> _dialog() => RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DestinationObserver', () {
    late SessionController c;
    late DestinationObserver observer;

    setUp(() {
      c = SessionController(tickInterval: const Duration(hours: 1));
      observer = DestinationObserver(c);
      addTearDown(c.dispose);
    });

    test('a page removed from under the top is forgotten, as a pop forgets it', () {
      final network = _page(AppDestination.network), log = _page(AppDestination.log);
      observer
        ..didPush(network, null)
        ..didPush(log, network);
      expect(c.currentDestination, AppDestination.log);
      observer.didRemove(log, network);
      expect(c.currentDestination, AppDestination.network);
      observer.didRemove(network, null);
      expect(c.currentDestination, AppDestination.menu, reason: 'nothing is left, so the main menu');
    });

    test('removing a route in the middle leaves the one on top current', () {
      final network = _page(AppDestination.network), log = _page(AppDestination.log), about = _page(AppDestination.about);
      observer
        ..didPush(network, null)
        ..didPush(log, network)
        ..didPush(about, log)
        ..didRemove(log, network);
      expect(c.currentDestination, AppDestination.about);
    });

    test('a dialog neither changes the destination nor is remembered', () {
      final network = _page(AppDestination.network);
      observer.didPush(network, null);
      final dialog = _dialog();
      observer
        ..didPush(dialog, network)
        ..didRemove(dialog, network);
      expect(c.currentDestination, AppDestination.network);
    });

    test('a page replaced by another takes its place in the stack', () {
      final network = _page(AppDestination.network), log = _page(AppDestination.log), about = _page(AppDestination.about);
      final settings = _page(AppDestination.settings);
      observer
        ..didPush(network, null)
        ..didPush(log, network)
        ..didPush(about, log)
        ..didReplace(newRoute: settings, oldRoute: log);
      expect(c.currentDestination, AppDestination.about, reason: 'the one on top is unchanged');
      observer.didRemove(about, settings);
      expect(c.currentDestination, AppDestination.settings, reason: 'it was put where the replaced one was, not at the end');
    });

    test('replacing the page on top changes the destination', () {
      final network = _page(AppDestination.network);
      observer
        ..didPush(network, null)
        ..didReplace(newRoute: _page(AppDestination.about), oldRoute: network);
      expect(c.currentDestination, AppDestination.about);
    });

    test('replacing a route it never saw adds the new page on top', () {
      observer.didReplace(newRoute: _page(AppDestination.log), oldRoute: _dialog());
      expect(c.currentDestination, AppDestination.log);
      observer.didReplace(newRoute: _page(AppDestination.about));
      expect(c.currentDestination, AppDestination.about, reason: 'no old route at all');
    });

    test('a page replaced by a dialog is just removed', () {
      final network = _page(AppDestination.network), log = _page(AppDestination.log);
      observer
        ..didPush(network, null)
        ..didPush(log, network)
        ..didReplace(newRoute: _dialog(), oldRoute: log);
      expect(c.currentDestination, AppDestination.network);
    });
  });

  group('the store at launch', () {
    const channel = MethodChannel('purchases_flutter');

    Map<String, dynamic> info({required bool unlocked}) {
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

    void answer(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => handler(call));
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    }

    setUp(() => Entitlement.debugReset(apiKey: 'test_key'));
    tearDown(Entitlement.debugReset);

    testWidgets('a customer the store says paid is unlocked as the app opens, with nothing to offer if there is no offering', (tester) async {
      final asked = <String>[];
      answer((call) {
        asked.add(call.method);
        return switch (call.method) {
          'getCustomerInfo' => info(unlocked: true),
          'getOfferings' => {'all': <String, dynamic>{}, 'current': null},
          _ => null,
        };
      });
      final c = quietController();
      await pumpApp(tester, c);
      expect(c.isUnlocked, isTrue);
      expect(asked, containsAllInOrder(['getCustomerInfo', 'getOfferings']), reason: 'the price is fetched once, here');
      await disposeApp(tester, c);
    });

    testWidgets('a store that cannot be reached is logged as a warning and the app opens locked', (tester) async {
      answer((call) => call.method == 'getCustomerInfo' ? throw PlatformException(code: '1', message: 'down') : null);
      final c = quietController();
      await pumpApp(tester, c);
      expect(c.isUnlocked, isFalse);
      final warning = c.log.where((e) => e.message.contains('Store unavailable'));
      expect(warning, hasLength(1));
      expect(warning.single.isWarning, isTrue);
      await disposeApp(tester, c);
    });
  });
}
