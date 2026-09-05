# RevenueCat Implementation Plan — Lifetime Unlock App

Compiled from advisory session with Rico (RevenueCat) — 2026-08-05.

## App Context / Requirements

- **Framework:** Flutter / Dart
- **Platforms:** Android now; iOS to be added later
- **Functionality:** 3 main functions — 2 free, 1 paid
- **Monetization:** One-off **lifetime** fee for the third function
- **Auth:** No login system (anonymous users only)
- **Offline:** App must work without a connection during use; paid status must be cached

---

## 1. Does RevenueCat replace Google Play Billing?

- **No — it sits on top of it.**
- Google Play Billing still processes the payment; Google remains merchant of record and takes their cut.
- RevenueCat's Android SDK **wraps** Google's `BillingClient`, validates receipts, and becomes the **single source of truth** for subscription/entitlement status across Android, iOS, and web.
- You still need your Google Play Console account and products configured in Play.
- **RevenueCat Billing** is a separate billing engine but is **web-only** (uses Stripe). It is NOT a replacement for Google Play on Android — in-app purchases on Android must still go through Google Play billing.

---

## 2. Product Model — Lifetime One-Off Unlock

- Model as a **non-consumable** in-app product.
- Add it to an **Offering** (as a package) and attach it to a single **Entitlement** (e.g. `pro`).
- The two free functions need no product and no entitlement gating.
- iOS later: create the equivalent non-consumable IAP in App Store Connect, attach to the same entitlement.

### Critical Android caveat

- RevenueCat only treats one-time products as non-consumable in **Android SDK 7.11.0+**.
- On older SDKs the purchase is **consumed**, letting the user buy again AND breaking restore.
- **Action:** configure the product as **non-consumable** in the RevenueCat dashboard AND use a recent SDK.

---

## 3. Offline Access

Two distinct mechanisms:

### Cached CustomerInfo (this is what covers you)

- Once entitled, `CustomerInfo` is cached on-device; `getCustomerInfo()` returns it synchronously, even fully offline.
- For a **lifetime (non-expiring) entitlement, cached "paid" status persists offline indefinitely** until the cache is invalidated.
- The 3-day offline grace period in the docs applies to *expiring subscriptions*, not lifetime unlocks.
- Cache refresh triggers: 5 min in foreground, 25 hrs in background, or on purchase/restore.
- `logOut()` clears the cache (not relevant to you since no logins).

### Offline Entitlements (does NOT help one-time purchases)

- Separate fallback for when RevenueCat servers are unreachable *at the moment of purchase*.
- **Does not work for one-time purchases (consumables/non-consumables).**
- **Implication:** the user needs connectivity ONCE, at purchase time, to activate the lifetime unlock. After a successful purchase, offline access is covered by the cache.
- UX: show a clear "connect to complete purchase" state when offline.

---

## 4. No Logins + Device Migration (new/wiped/upgraded handset)

- With no login, each install gets a fresh **anonymous App User ID**. A new device = new anonymous ID with no purchase history.
- Google Play natively ties the non-consumable purchase to the user's Google account, but **RevenueCat isn't told automatically** on a fresh install.
- A **restore call** (`restorePurchases()`) is what makes the SDK query the store, send receipts to RevenueCat, and re-attach the entitlement to the new anonymous ID.
- **Restore behavior:** keep the default **"Transfer to new App User ID"** (Project settings -> General). Required for anonymous restore; two anonymous IDs owning the same receipt are merged (aliased).

### Why a Restore button (if the store owns the receipt)?

- The store **has** the receipt, but something has to go **ask** for it — that's `restorePurchases()`.
- On a new anonymous install there's no cache to fall back on, and the SDK won't auto-claim store purchases for an unknown anonymous user.
- Options: **silent auto-restore** on first launch/paywall, AND a **visible button**.
- The visible button is **required by Apple's App Store review guidelines** for apps selling non-consumables (matters when you ship iOS).

### Billing Client 8 gotcha

- Play Billing Library 8 removed the ability to query _consumed_ one-time products.
- If the product is ever treated as consumable, it **cannot be restored** on a new device.
- Fix is fully in your control: keep it **non-consumable** (SDK 7.11.0+).
- Recovery fallbacks if a purchase was consumed: manual transfer in dashboard by Order ID, or the Restore by Order ID API. Don't rely on these at scale.

### Cross-platform note

- Cross-platform recovery (bought on Android, restore on iOS) without a login is NOT possible — anonymous IDs are per-store. If needed later, that's when an optional login becomes worth considering.

---

## 5. Implementation Steps

### Dashboard setup (do first)

1. Add Android app (Play Console link + service account creds for server notifications). Add iOS app later.
2. Create lifetime IAP as **non-consumable**; mirror in Google Play Console.
3. Create one entitlement (e.g. `pro`); attach the lifetime product.
4. Create a default offering with one package containing the lifetime product.
5. Confirm restore behavior = **Transfer to new App User ID** (default).

### Install SDK

- Add `purchases_flutter` (latest at time of writing: **10.7.0**) to `pubspec.yaml`.
- Android: add `BILLING` permission to `AndroidManifest.xml`.
- iOS (later): enable **In-App Purchase** capability in Xcode.

### Configure at launch (no logIn call — anonymous)

```dart
await Purchases.setLogLevel(LogLevel.debug); // remove for production

final config = PurchasesConfiguration(
  Platform.isAndroid ? 'goog_YOUR_ANDROID_KEY' : 'appl_YOUR_IOS_KEY',
);
await Purchases.configure(config);
```

### Gate the paid function (offline-friendly)

```dart
Future<bool> hasPro() async {
  try {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('pro');
  } catch (_) {
    return false; // no cache yet (brand-new install, offline)
  }
}
```

The two free functions never call this.

### Show offering & purchase

```dart
final offerings = await Purchases.getOfferings();
final package = offerings.current?.availablePackages.first;

if (package != null) {
  try {
    final info = await Purchases.purchasePackage(package);
    final unlocked = info.entitlements.active.containsKey('pro');
    // reveal the paid function
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code != PurchasesErrorCode.purchaseCancelledError) {
      // show error
    }
  }
}
```

Purchase needs connectivity once; show a "connect to complete purchase" state if offline.

### Restore (device-migration safety net)

```dart
Future<void> restore() async {
  try {
    final info = await Purchases.restorePurchases();
    final unlocked = info.entitlements.active.containsKey('pro');
    // update UI
  } on PlatformException catch (e) {
    // show error
  }
}
```

Offer both silent auto-restore and a visible button.

### Faster/reliable status

- Enable **Google Play server notifications** (Pub/Sub) now; Apple Server Notifications with iOS.
- Add a **CustomerInfo listener** (`Purchases.addCustomerInfoUpdateListener`) to reactively update UI.

### Recommended build order

1. Dashboard: product (non-consumable) -> entitlement -> offering.
2. Install + configure SDK (Android key).
3. Gate paid function via `getCustomerInfo()`.
4. Wire purchase + restore.
5. Test in Play internal testing track with a license tester: purchase -> uninstall -> reinstall -> restore -> confirm unlock persists offline.
6. Add iOS: app, iOS key, non-consumable IAP on the same entitlement.

---

## Key Reference Docs

- Caching: https://www.revenuecat.com/docs/test-and-launch/debugging/caching
- Getting Subscription Status / Offline Entitlements: https://www.revenuecat.com/docs/customers/customer-info
- Non-Subscription Purchases: https://www.revenuecat.com/docs/platform-resources/non-subscriptions
- Google Play Product Setup: https://www.revenuecat.com/docs/getting-started/entitlements/android-products
- Restore Behavior: https://www.revenuecat.com/docs/projects/restore-behavior
- Flutter installation: https://www.revenuecat.com/docs/getting-started/installation/flutter
- Implementation Responsibilities: https://www.revenuecat.com/docs/platform-resources/implementation-responsibilities