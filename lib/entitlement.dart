// entitlement.dart - one place that answers "has this user paid?".
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// The ONLY place the rest of the app asks about payment, and the only place that touches the
// RevenueCat SDK. Every gated screen reads [isUnlocked]; none of them import `purchases_flutter`.
//
// THE KEY IS NOT COMPILED IN. It arrives as `--dart-define=REVENUECAT_ANDROID_KEY=...`, which the
// release workflow supplies from a repository secret. That is not for secrecy - RevenueCat's public
// key is designed to be embedded and can be read out of any APK - it is so that a build WITHOUT the
// key behaves correctly. Google Play refuses purchases from an artifact it did not distribute, so a
// self-built copy could never complete a paywall. Rather than show one it cannot honour, a keyless
// build has no purchasing at all and everything is unlocked, which is exactly what the paywall
// itself promises: the source is on GitHub, and what you are paying for is not having to build it.
//
// The corollary is that a release build MUST carry the key or it ships the paid features to
// everyone. `.github/workflows/release.yml` fails the build when the secret is empty.

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Whether the paid features are available to this user.
abstract class Entitlement {
  /// Supplied at build time; empty in a local or self-built copy. See the file header.
  static const androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  /// The entitlement identifier configured in the RevenueCat dashboard. This string has to match
  /// exactly, and a mismatch fails in the worst way available: purchases succeed and unlock nothing.
  static const entitlementId = 'router_features';

  /// False when this build cannot take money, which is the honest state of a keyless build.
  static bool get purchasingAvailable => androidKey.isNotEmpty;

  /// True when the paid features are available.
  ///
  /// A build that cannot sell anything withholds nothing. Otherwise it is what RevenueCat last
  /// told us, which defaults to LOCKED: a first run that cannot reach the store has no evidence of
  /// a purchase, and inventing one would give the app away to anyone who turns off their wifi.
  /// A returning customer is covered by the SDK's own cache, so offline does not lock them out.
  static bool get isUnlocked => _override ?? (!purchasingAvailable || _held);

  static bool _held = false;
  static bool? _override;

  /// Test seam only - pins the answer for one test. `null` restores the real behaviour.
  static void debugSetUnlocked(bool? value) => _override = value;

  /// Starts the SDK and begins reporting entitlement changes to [onChanged].
  ///
  /// Called once, at launch. **Never throws**: a store that cannot be reached must not stop the app
  /// starting, because everything except the paid screens works without it.
  static Future<void> configure({
    required void Function(bool unlocked) onChanged,
    void Function(String message) onLog = _ignore,
  }) async {
    if (!purchasingAvailable) return;
    _onLog = onLog;
    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(androidKey));
      // Registered BEFORE the first fetch, so a purchase completing during startup cannot slip
      // between the two and leave a paying customer looking at a locked screen.
      _onChanged = onChanged;
      Purchases.addCustomerInfoUpdateListener(_apply);
      _apply(await Purchases.getCustomerInfo());
      // A reinstall, or a new phone, arrives as a brand-new anonymous id that RevenueCat has never
      // seen and which holds nothing. `syncPurchases` hands it whatever Google Play already knows
      // this account owns, and the listener above turns that into an unlocked app.
      //
      // NOT `restorePurchases`, which RevenueCat says must never be called programmatically: it can
      // raise an operating-system sign-in prompt, and one of those on a cold start, unasked, is
      // both alarming and inexplicable. Restore stays on a button the user presses.
      if (!_held) await Purchases.syncPurchases();
    } catch (e) {
      onLog('Store unavailable: ${_plain(e)}');
    }
  }

  /// The store's OWN localised price for the unlock, or null when there is nothing to sell.
  ///
  /// Never format a price locally. The wrong currency destroys trust instantly and silently.
  static Future<String?> price() async {
    final package = await _package();
    return package?.storeProduct.priceString;
  }

  /// Buys the unlock. True when the entitlement is held afterwards.
  ///
  /// A cancellation is a normal outcome, not an error, so it returns false rather than throwing.
  static Future<bool> purchase() async {
    final package = await _package();
    if (package == null) throw Exception('nothing to buy - the store did not return an offering.');
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _apply(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  /// Recovers a purchase made on another device or before a reinstall.
  ///
  /// **Only ever from a control the user pressed.** RevenueCat's own guidance: called
  /// programmatically it can raise an operating-system sign-in prompt, which is alarming when
  /// nobody asked for it. The launch path uses `syncPurchases` instead - see [configure].
  ///
  /// The app never calls `logIn`, so every customer is anonymous and their purchase is tied to
  /// their Google account rather than to anything this app stores. That is why restore works with
  /// no local state at all, and why `android:allowBackup="false"` costs nothing here.
  static Future<bool> restore() async => _apply(await Purchases.restorePurchases());

  /// The first package of the current offering, or null when there is nothing to sell.
  ///
  /// Says WHY in the app log. Three different faults all present as one disabled button reading
  /// "Not available right now", and they are fixed in three different places: the store being
  /// unreachable, no offering marked CURRENT in the RevenueCat dashboard, and an offering whose
  /// product Google Play would not return - which is what a newly activated product looks like
  /// before it has propagated. Guessing between those from the button alone wastes an evening.
  static Future<Package?> _package() async {
    if (!purchasingAvailable) return null;
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        _log('No current offering. In RevenueCat, mark an offering as Current (${offerings.all.length} exist).');
        return null;
      }
      final packages = current.availablePackages;
      if (packages.isEmpty) {
        _log('Offering "${current.identifier}" has no packages Play would return. A product activated in the last '
            'few hours may not have propagated yet.');
        return null;
      }
      return packages.first;
    } catch (e) {
      _log('Could not read the store offerings: ${_plain(e)}');
      return null;
    }
  }

  // One place applies a CustomerInfo, whether it came from the launch fetch, the SDK's own
  // listener, a purchase or a restore. Holding the callback here rather than passing it in means
  // no path can quietly update the entitlement without telling the UI.
  static void Function(bool)? _onChanged;
  static void Function(String)? _onLog;

  static void _log(String message) => _onLog?.call(message);

  static bool _apply(CustomerInfo info) {
    final held = info.entitlements.active.containsKey(entitlementId);
    if (held != _held) {
      _held = held;
      _onChanged?.call(held);
    }
    return held;
  }

  static void _ignore(String _) {}

  static String _plain(Object e) => e.toString().replaceAll('Exception: ', '');
}
