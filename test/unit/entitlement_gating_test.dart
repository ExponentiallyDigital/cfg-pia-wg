// test/unit/entitlement_gating_test.dart - what a locked user can and cannot do.
//
// The rule, from .claude/plans/plan_revenuecat-implementation.md: GATED is create or change, FREE
// is remove. A locked user can always undo, never build. The cases below are the ones a later
// refactor is most likely to get wrong, because each is a one-line change that looks harmless.
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SessionController controller() {
    final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});
    addTearDown(c.dispose);
    return c;
  }

  tearDown(() => Entitlement.debugSetUnlocked(null));

  group('the entitlement seam', () {
    // The key arrives as --dart-define at build time and is absent here, as it is in any local or
    // self-built copy. That is the case this asserts: no key, no purchasing, nothing withheld.
    test('a build with no store key sells nothing and withholds nothing', () {
      expect(Entitlement.androidKey, isEmpty);
      expect(Entitlement.purchasingAvailable, isFalse);
      expect(Entitlement.isUnlocked, isTrue);
      expect(controller().isUnlocked, isTrue,
          reason: 'Play refuses purchases from an artifact it did not distribute, so a keyed '
              'self-build would show a paywall its owner could never complete');
    });

    // Spelled wrong, purchases succeed and unlock nothing, and only a customer finds out.
    test('the entitlement id matches the RevenueCat dashboard', () {
      expect(Entitlement.entitlementId, 'router_features');
    });

    test('the controller mirrors the seam at construction', () {
      Entitlement.debugSetUnlocked(false);
      expect(controller().isUnlocked, isFalse);
    });

    test('a change NOTIFIES, because gated controls have to rebuild', () {
      final c = controller();
      var notified = 0;
      c.addListener(() => notified++);

      c.setUnlocked(false);
      expect(c.isUnlocked, isFalse);
      expect(notified, 1);

      // Idempotent: a purchase confirmed twice must not rebuild the tree twice.
      c.setUnlocked(false);
      expect(notified, 1);

      c.setUnlocked(true);
      expect(notified, 2);
    });

    test('wipeAll does not take the entitlement away', () async {
      // Exiting the app clears credentials and config. What someone bought is not session state,
      // and re-locking them on the way out would be an unpleasant surprise on the way back in.
      final c = controller()..setUnlocked(true);
      await c.wipeAll(reason: 'test');
      expect(c.isUnlocked, isTrue);
    });
  });
}
