// test/widgets/paywall_test.dart - the paywall's agreed words, and that everything it does is logged.
//
// A declined card or a slow approval used to flash a message at the foot of the screen and vanish,
// and Restore said nothing when the account held no purchase. These pin that every outcome now
// reaches the app log, and that Restore answers in the same words as the settings screen.
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() {
  late SessionController c;

  setUp(() => c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {}));
  tearDown(() {
    Paywall.offer = null;
    c.dispose();
  });

  PaywallOffer offer({Future<bool> Function()? purchase, Future<bool> Function()? restore}) => PaywallOffer(
        price: r'$9.99',
        purchase: purchase ?? () async => false,
        restore: restore ?? () async => false,
      );

  // A Scaffold ABOVE the navigator, as AppChrome provides in the app, so a snackbar raised on the paywall
  // page is on screen rather than behind it.
  Future<void> open(WidgetTester tester, PaywallOffer? o, {String pitch = Pitch.create}) async {
    Paywall.offer = o;
    await tester.pumpWidget(SessionScope(
      controller: c,
      child: MaterialApp(
        builder: (context, child) => Scaffold(body: child),
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(onPressed: () => Paywall.show(ctx, c, pitch: pitch), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Scrolls first: the watchdog pitch is long enough to push the buttons below the fold on the
  // 800x600 test surface, where a bare tap misses and only prints a warning.
  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  LogEntry? entry(String text) {
    for (final e in c.log) {
      if (e.message.contains(text)) return e;
    }
    return null;
  }

  group('wording', () {
    testWidgets('reads as agreed', (tester) async {
      await open(tester, offer());
      expect(find.text(r'UNLOCK FOR LIFE - $9.99'), findsOneWidget);
      expect(find.text('One lifetime payment. No subscription, ever.'), findsOneWidget);
      expect(find.textContaining('No desktop, no laptop, no unfathomable scripts.'), findsOneWidget);
      expect(find.textContaining('with or without a router'), findsNothing);
      expect(find.textContaining('configured VPNs are fully retained'), findsOneWidget);
    });

    test('the manage pitches speak of a tunnel and a slot', () {
      expect(Pitch.enable, startsWith('Enabling brings a tunnel up'));
      expect(Pitch.edit, "Editing writes a slot's settings back to your router.");
    });

    test('the watchdog pitch names the chosen interval and the worse case', () {
      expect(Pitch.watchdog, contains('at your chosen check interval'));
      expect(Pitch.watchdog, isNot(contains('every few minutes')));
      expect(Pitch.watchdog, endsWith('or worse, not knowing you were unprotected.'));
    });
  });

  group('logging', () {
    testWidgets('opening names the control, and closing without buying is logged', (tester) async {
      await open(tester, offer(), pitch: Pitch.watchdog);
      expect(entry('Paywall shown for watchdog CREATE/EDIT.'), isNotNull);

      await tapKey(tester, 'paywall_close');
      expect(entry('Paywall closed. Still locked.'), isNotNull);
    });

    testWidgets('a completed purchase logs success, unlocks and leaves the paywall', (tester) async {
      await open(tester, offer(purchase: () async => true));
      c.setUnlocked(false);

      await tapKey(tester, 'paywall_buy');

      expect(entry('Purchase started.'), isNotNull);
      expect(entry('Purchase complete. Router features unlocked.')?.isSuccess, isTrue);
      expect(c.isUnlocked, isTrue);
      expect(find.byKey(const Key('paywall_buy')), findsNothing);
    });

    testWidgets('a cancelled purchase is logged and stays on the paywall', (tester) async {
      await open(tester, offer(purchase: () async => false));
      await tapKey(tester, 'paywall_buy');

      expect(entry('Purchase cancelled.'), isNotNull);
      expect(find.byKey(const Key('paywall_buy')), findsOneWidget);
    });

    testWidgets('a declined payment is logged as an error, not only flashed on screen', (tester) async {
      await open(tester, offer(purchase: () async => throw Exception('card declined')));
      await tapKey(tester, 'paywall_buy');

      expect(find.text('Purchase failed: card declined'), findsOneWidget);
      expect(entry('Purchase failed: card declined')?.isError, isTrue);
    });

    testWidgets('a pending payment is a warning, not a failure', (tester) async {
      // The store's own error for a slow card.
      final pending = PlatformException(code: '${PurchasesErrorCode.paymentPendingError.index}', message: 'pending');
      await open(tester, offer(purchase: () async => throw pending));
      await tapKey(tester, 'paywall_buy');

      final e = entry('Payment is pending');
      expect(e, isNotNull);
      expect(e!.isWarning, isTrue);
      expect(e.isError, isFalse);
      expect(entry('Purchase failed'), isNull);
    });
  });

  group('restore', () {
    testWidgets('finding nothing says so on screen and in the log, in the settings wording', (tester) async {
      await open(tester, offer(restore: () async => false));
      await tapKey(tester, 'paywall_restore');

      expect(RestoreMessages.noneFound, 'No purchase found on this Google account.');
      expect(find.text(RestoreMessages.noneFound), findsOneWidget);
      expect(entry('Restore started.'), isNotNull);
      expect(entry(RestoreMessages.noneFound), isNotNull);
      expect(find.byKey(const Key('paywall_buy')), findsOneWidget, reason: 'still on the paywall');
    });

    testWidgets('a store that cannot be reached is an error in the log', (tester) async {
      await open(tester, offer(restore: () async => throw Exception('offline')));
      await tapKey(tester, 'paywall_restore');

      expect(find.text('Could not reach the store: offline'), findsOneWidget);
      expect(entry('Could not reach the store: offline')?.isError, isTrue);
    });
  });
}
