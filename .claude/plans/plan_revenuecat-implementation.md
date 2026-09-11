# RevenueCat Implementation Plan — Lifetime Unlock App

Compiled from advisory session with Rico (RevenueCat) — 2026-08-05.

## App Context / Requirements

- **Framework:** Flutter / Dart
- **Platforms:** Android now; iOS to be added later
- **Functionality:** 3 main functions — 2 free, 1 paid
- **Monetization:** One-off **lifetime** fee for the third function
- **Auth:** No login system (anonymous users only)
- **Offline:** App must work without a connection during use; paid status must be cached

**The product decision, moved here from BACKLOG.md on 2026-09-12:**

- NEW: Freemium version using RevenueCat, move all but standalone conf generation to a one-off lifetime paid function, non-freemium makes screens accessible but read only, advise once per session when entering a freemium gated function, explain how to unlock all capabilities.
- TBC: Determine cost - smaller user base, higher investment.

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
---

## Addendum 2026-09-05 — app-specific notes

Everything above is RevenueCat mechanics from the advisory session. These are the things specific to *this* app, found while reviewing the backlog. Backlog item: `BACKLOG.md` section 1.2.

### An unlocked watchdog cannot be re-locked, and that is accepted

The watchdog runs **on the router**, on cron, with the app nowhere in the picture. Once deployed it keeps re-negotiating PIA for as long as the router is powered, whatever the entitlement says afterwards. There is no mechanism — and should be none — for the app to reach in and stop a watchdog because a purchase was refunded.

**Decision (2026-09-05): accepted.** The point of the paid tier is cashflow to cover development costs, not enforcement. The source stays on GitHub and anyone can build it themselves for nothing; the charge buys not having to. A refund path that leaves a working watchdog behind is a rounding error against that.

Two consequences worth keeping straight:

- Section 3 above (offline access) is nearly free for the watchdog specifically — it needs no entitlement check at run time because it does not run in the app at all. The gate belongs on **deploying** one, not on it working.
- Do not build revocation logic, a phone-home, or a licence check inside the deployed script. It would be defeatable in a text editor, it would add a failure mode to something whose whole job is to be reliable unattended, and it contradicts the decision above.

### Gate the purchase behind the pre-flight check that already exists

Section 1.2.4 of the backlog asks for a pre-flight diagnostic so nobody buys an unlock their router cannot use. Most of it is already written and running:

| Check | Where it lives now |
| --- | --- |
| SSH reachable and credentials accepted | `RouterSlotsScreen._onConnect` |
| Firmware identified (stock vs Merlin) | `RouterSlotService.readFirmwareTag` + `classifyFirmwareTag` |
| Stock: `jq` and `mailsend-go` present | `RouterSlotService.missingStockBinaries` |
| Merlin: JFFS custom scripts enabled | `RouterWatchdog.enableJffsScripts` reads `jffs2_scripts` / `jffs2_on` |
| Stock: `/opt` present for boot persistence | not checked today — DownloadMaster installed? |

The last row is the gap, and it is the one most likely to bite: without `/opt/etc/init.d/` the watchdog deploys and works, then silently loses its cron entries at the next reboot. Worth adding as a check regardless of freemium.

Sequence the paywall **after** the pre-flight passes, not before, so the purchase button only appears to someone whose router can actually run the thing.

### `flutter_secure_storage` versus the app's stated posture

README and SECURITY.md both say plainly that nothing is written to device storage. An entitlement token is not a credential, so caching one is compatible with the *intent* — but the sentences are currently absolute and would read as contradicted.

Fix the wording when the dependency lands, not after: SECURITY.md "Secret management" should distinguish *credentials* (never stored, still true) from *purchase state* (cached, not sensitive, and what it is used for). Getting caught overstating this would cost more than the feature is worth.

### The home screen after PayPal and Patreon go

Section 1.2.3 removes both donation buttons. That leaves the home screen's footer as just the two links — "how to use this app" and "add a Play Store app review" — with the `spacer` above them sized for a block that is no longer there. Small layout job, but do not forget the review link's own text: the alert emails say *"by tapping on the home screen link"*, so that link has to survive the redesign or the email wording goes stale.

### Play Console data safety

Adding RevenueCat means an SDK that sees a pseudonymous app-user id. The Data safety form and the privacy policy both need updating before the release that carries it — this is a store-rejection item, not a nicety.

---

## Work breakdown

Moved here verbatim from `BACKLOG.md` section 1.2 on 2026-09-12, so the implementation lives in one
place. The release chores that used to sit alongside it - documentation, publicity, launch and ASO -
went to the CHANGELOG pending list instead, because they are not implementation.

This is the raw material for the WIP items, not the sequence itself. The order below is the order it
was written in, which is not necessarily the order to build in - see "Recommended build order" above,
and the sequencing decision still to be made.

### Accounts & Play Console setup

- **In-app product creation:** Create a **Non-consumable** in-app product (e.g., `cfg-pia-wg_pro_unlock`) set to US$x.yy.
- **Play Store compliance:** Complete **Data safety form** to reflect RevenueCat, and add to Privacy Policy. Store-rejection item, not a nicety - the SDK sees a pseudonymous app-user id.

### RevenueCat dashboard setup

- **Link accounts:** Connect Google Play Console credentials to RevenueCat via service account keys.
- **Configure entitlements:** Create an **Entitlement** named `pro_feature` and map to `cfg-pia-wg_pro_unlock`.

### Codebase integration

- **Flutter dependencies:** Add `purchases_flutter` and `flutter_secure_storage` to `pubspec.yaml`.
- **Billing service singleton:** Implement RevenueCat initialisation, real-time entitlement status updates, purchase triggers, and purchase restoration.
- **Paywall UI modal:** Build a `PaywallBottomSheet` highlighting watchdog's zero-touch automation, PIA key renewal fix, and lifetime access model.
- **PayPal/Patreon:** remove links from main app screen. Re-space the home-screen footer afterwards - the `spacer` above it is sized for the donation block. Keep the "add a Play Store app review" link: the watchdog alert emails say "by tapping on the home screen link", so removing it makes that wording stale.

### Entitlement check must precede every dependency check

- **Order: entitlement, then dependencies, then the offer to install them.** A user without `pro_feature` who opens MANAGE or WATCHDOG on stock must see the paywall, never "jq is missing". Telling someone to install a dependency for a feature they cannot use either way wastes their time and reads as a bug.
- Applies to the helper-binary install (`.claude/plans/plan_install-helper-binaries.md`) and to anything else that probes the router before the gate. **Never prompt to download binaries onto the router of a user who has not unlocked the feature** - it is work done on their hardware for something they cannot run.
- Worth a test that pins the ordering, because it is the kind of thing a later refactor reorders without noticing.

### Security & router diagnostics

- **Pre-flight diagnostic:** Verify SSH connectivity and JFFS script execution readiness *before* displaying unlock feature to prevent purchases on incompatible setups. Most of this already exists - see the table in the plan addendum. The one missing check is `/opt` on stock (DownloadMaster installed): without it the watchdog deploys, works, and then silently loses its cron entries at the next reboot. **Worth adding regardless of freemium.**
- **Do not build revocation into the deployed watchdog script.** A deployed watchdog runs on the router with the app nowhere in the picture, so entitlement cannot be enforced after the fact - accepted deliberately (see plan addendum). A licence check inside the script would be defeatable in a text editor and would add a failure mode to the one thing that has to be reliable unattended.
- **`flutter_secure_storage` versus the stated posture:** `README.md` and `SECURITY.md` both say absolutely that nothing is written to device storage. Caching an entitlement is compatible with the intent but contradicts the wording. Reword "Secret management" to separate *credentials* (never stored) from *purchase state* (cached, not sensitive) in the same change that adds the dependency.

### Sandbox testing & QA

- **Licence testing:** Add developer Gmail under *Google Play Console -> Licence testing*.
- **Internal test track:** Build and upload `flutter build appbundle` (`.aab`) to the Internal Testing track.
- **Sandbox verification:** Run `flutter run` on device to test:
- **E2E test:** Generate and Manage execute freely; watchdog invokes unlock feature.
- **Purchase flow:** complete test transaction via Google’s *"Test card, always approves"*.
- **Declined card handling:** Test error handling using *"Test card, always declines"*.
- **Restoration flow:** test "Restore Purchases" button.
- **Offline access:** disconnect internet and verify cached local entitlements allow watchdog to execute.
- Check if we need to update the list of Android permissions the app now uses, see `README.md` section "8. App permissions".
- Run a sonar scan on the Dev branch before merging to main.
