# RevenueCat implementation plan

**What this is.** One document covering the paid tier: what is being sold, what has already been
decided, what RevenueCat actually does, and the order to build it in. Compiled from an advisory
session with Rico at RevenueCat on 2026-08-05, an app-specific review on 2026-09-05, and the backlog
items that were folded in on 2026-09-12.

**Status: nothing is built.** `lib/entitlement.dart` holds the seam - `Entitlement.isUnlocked`
returns `true` for everyone - and nothing else in the app knows about any of this.

---

## 1. What is being sold

- **Freemium using RevenueCat.** Everything except standalone config generation moves behind a one-off lifetime paid function. Locked screens stay accessible but READ ONLY, and entering a gated function advises once per session and explains how to unlock all capabilities.
- **Price: TBC.** A smaller user base against a higher investment.
- **Free:** standalone PIA config generation, and the app log.
- **Paid:** the router functions - manage slots, deploy a watchdog, assign devices.

Modelled as **one non-consumable product**, in **one offering**, attached to **one entitlement**.
No subscriptions, no tiers, no login. Android now; iOS later on the same entitlement.

---

## 2. Decided already - do not relitigate

**An unlocked watchdog cannot be re-locked, and that is accepted.** The watchdog runs on the router,
on cron, with the app nowhere in the picture. Once deployed it keeps re-negotiating PIA for as long
as the router has power, whatever the entitlement says afterwards.

Decided 2026-09-05: the paid tier is cashflow to cover development, not enforcement. The source is on
GitHub and anyone can build it themselves for nothing; the charge buys not having to. A refund that
leaves a working watchdog behind is a rounding error against that. Two consequences:

- **The gate belongs on DEPLOYING a watchdog, not on one working.** Offline entitlement checks are therefore nearly free here, because the thing being paid for does not run in the app at all.
- **Never build revocation, a phone-home, or a licence check into the deployed script.** It would be defeatable in a text editor, it would add a failure mode to the one thing that has to be reliable unattended, and it contradicts the decision above.

**The paywall comes AFTER the pre-flight check, never before.** Nobody should be sold an unlock for a
router that cannot run it, and nobody without the entitlement should be asked to install helper
binaries onto their router for a feature they cannot use. Ordering, strictly: entitlement, then
dependencies, then the offer to install them. A user without the entitlement who opens MANAGE or
WATCHDOG on stock must see the paywall, never "jq is missing". Worth a test that pins the order,
because a later refactor will reorder it without noticing.

**The donation buttons go.** PayPal and Patreon come off the home screen. Keep the "add a Play Store
app review" link: the watchdog alert emails say *"by tapping on the home screen link"*, so removing
it makes that wording stale. The `spacer` above the footer is sized for the donation block and will
need re-spacing.

**The security wording gets fixed in the same change that adds the dependency.** README and
SECURITY.md both say absolutely that nothing is written to device storage. An entitlement cache is
compatible with the intent but contradicts the sentence. Separate *credentials* (never stored, still
true) from *purchase state* (cached, not sensitive) when the dependency lands, not after. Being
caught overstating this would cost more than the feature is worth.

---

## 3. Open questions

- **The price.** Not set.
- **What "read only" means on each screen.** A locked MANAGE screen showing the slot list is useful; a locked DEVICE ASSIGNMENT screen showing every device and refusing to move one may be more irritating than showing nothing. Needs a decision per screen.
- **Whether the once-per-session advice is a dialog, a banner, or the paywall itself.**
- **Play Console Data safety form.** Needs completing to reflect RevenueCat, and the Privacy Policy needs a line. This is a store-rejection item rather than a nicety: the SDK sees a pseudonymous app-user id.
---

## 4. How RevenueCat works, where it changes what we build

Only the parts that affect a decision. The reference docs are at the end.

**It does not replace Google Play Billing, it sits on top.** Google still processes the payment,
remains merchant of record and takes their cut. The RevenueCat SDK wraps Google's `BillingClient`,
validates receipts, and becomes the single source of truth for entitlement status across platforms.
The Play Console account and the products configured in Play are still needed. RevenueCat's own
billing engine is web-only and is not an alternative on Android.

**The product must be NON-CONSUMABLE, and the SDK must be recent.** RevenueCat only treats one-time
products as non-consumable from **Android SDK 7.11.0**. On anything older the purchase is *consumed*,
which lets the user buy it twice and breaks restore permanently - Play Billing Library 8 removed the
ability to query consumed one-time products, so a consumed purchase cannot be restored on a new
device at all. Configure it as non-consumable in the dashboard AND ship a current SDK. This is the
single most expensive thing to get wrong, because it is only discovered when a real customer changes
phone.

**Offline works, through the cache, once the purchase has happened.** `CustomerInfo` is cached
on-device and `getCustomerInfo()` returns it even fully offline. For a lifetime entitlement that
cached status persists indefinitely. The cache refreshes after 5 minutes in the foreground, 25 hours
in the background, or on any purchase or restore.

**But the purchase itself needs connectivity, once.** RevenueCat's "Offline Entitlements" feature
sounds like it covers this and does not: it explicitly excludes one-time purchases. So the UI needs a
clear "connect to complete the purchase" state, and after that first success the user can be offline
forever.

**No login means anonymous ids, which means restore matters.** Each install gets a fresh anonymous
App User ID, so a new or wiped phone has no purchase history. Google Play ties the purchase to the
user's Google account, but RevenueCat is not told automatically - something has to go and ask, and
that something is `restorePurchases()`. Provide both a silent auto-restore on first launch and a
visible button. Apple requires the visible button for non-consumables, which matters when iOS lands.

**Restore behaviour must stay "Transfer to new App User ID"** (Project settings, General - it is the
default). Anonymous restore depends on it: two anonymous ids owning the same receipt get merged.

**Cross-platform restore is not possible without a login.** Bought on Android, restored on iOS, will
not work while ids are anonymous. If that ever matters, that is the moment an optional login earns
its place - not before.
---

## 5. Build order

One sequence. Each step says what it touches in this codebase. Steps 1 and 2 are console work with
no code, and they have to be first: the SDK cannot be tested against products that do not exist.

### 1. Google Play Console

- Create a **non-consumable** in-app product, `cfg-pia-wg_pro_unlock`, at the agreed price.
- Complete the **Data safety form** to reflect RevenueCat, and add the matching line to the Privacy Policy.

### 2. RevenueCat dashboard

- Add the Android app: link Play Console, add service-account credentials for server notifications.
- Create the lifetime IAP as **non-consumable**, mirroring the Play product.
- Create one entitlement, `pro_feature`, and attach the product.
- Create a default offering with one package containing it.
- Confirm restore behaviour is **Transfer to new App User ID**.

### 3. Add the SDK and configure it

- `purchases_flutter` in `pubspec.yaml`. **Check the current version at the time you add it** - it was 10.12.0 on 2026-09-12, and the floor that matters is Android SDK 7.11.0 for non-consumable handling.
- `BILLING` permission in `AndroidManifest.xml`. Check whether `README.md` section "App permissions" needs a new entry.
- Configure at launch with the Android key. **No `logIn` call** - anonymous throughout.
- This is a STRICT dependency-locked project: `gradle.lockfile` and `pubspec.lock` both need regenerating, and the lockfile set is part of the build.

### 4. Fill in the seam

- `lib/entitlement.dart` already exists and returns `true`. Give it a real implementation over `getCustomerInfo()`, returning false on any failure so a brand-new offline install is locked rather than crashing.
- Keep it the ONLY place the rest of the app asks. Every screen should call the seam, never the SDK.

### 5. Gate the three paid screens

- MANAGE, WATCHDOG and DEVICE ASSIGNMENT. Standalone generation and the app log stay free.
- **Order: entitlement, then dependencies, then the offer to install them.** See section 2.
- Locked screens are accessible but read only, with the once-per-session advice.

### 6. The paywall

- A modal offering the lifetime unlock. Lead on what it buys: a watchdog that renews PIA keys without anyone touching it, and device assignment.
- Shown only after the pre-flight passes.
- Needs an offline state: "connect to complete the purchase".

### 7. Restore

- Silent auto-restore on first launch, plus a visible button. Settings is the natural home for the button, beside the other one-off actions.

### 8. Home screen cleanup

- Remove PayPal and Patreon, keep the review link, re-space the footer.

### 9. Documentation, in the same commit as the dependency

- `SECURITY.md` "Secret management": separate credentials from purchase state.
- `README.md`: the same, plus the permission if one was added.

### 10. The pre-flight gap - worth doing regardless of freemium

`RouterSlotService.missingStockBinaries` checks `jq` and `mailsend-go`. Nothing checks that
`/opt/etc/init.d` exists, which is what Download Master provides and what boot persistence depends
on. See section 7 for what actually happens today, which is not what the old backlog said.

---

## 6. Testing

**This is the slow part, and it cannot be done from a local build.** A purchase flow needs a signed
build on a Play track and a licence-tester account. Budget for the loop being minutes rather than
seconds, and sequence the code so that as much as possible is verifiable without it.

Setup:

- Add the developer Gmail under **Play Console -> Licence testing**.
- Upload an `.aab` to the **internal** track. `release.yml` does this on a tag push; `promote.yml` moves a build between tracks afterwards without rebuilding.

The runs that matter:

- **Entitlement gating:** generation and the app log work untouched; the three router screens show the paywall.
- **Ordering:** a locked user on stock sees the paywall, NOT "jq is missing", and is never offered a binary install.
- **Purchase:** complete one with Google's *"Test card, always approves"*.
- **Declined:** repeat with *"Test card, always declines"* and check the error path.
- **The one that finds the expensive bug:** purchase, uninstall, reinstall, restore, and confirm the unlock comes back. This is what proves the product was configured non-consumable.
- **Offline:** disconnect, confirm the cached entitlement still unlocks.
- **Offline purchase:** disconnect BEFORE buying and confirm the "connect to complete" state appears rather than a crash or a silent failure.

Before merging to main: run Quality & security on the branch.

---

## 7. What already exists in this app

The pre-flight the backlog asked for is mostly written and running:

| Check | Where it lives |
| --- | --- |
| SSH reachable, credentials accepted | `RouterSlotsScreen._onConnect` |
| Firmware identified, stock or Merlin | `RouterSlotService.readFirmwareTag` + `classifyFirmwareTag` |
| Stock: `jq` and `mailsend-go` present | `RouterSlotService.missingStockBinaries` |
| Merlin: JFFS custom scripts enabled | `RouterWatchdog.enableJffsScripts` |
| The entitlement seam | `lib/entitlement.dart`, returns `true` today |
| Stock: `/opt` present for boot persistence | **not checked** |

**On that last row, the old backlog wording was stronger than the evidence.** It said the watchdog
"deploys, works, and then silently loses its cron entries at the next reboot". Reading the code on
2026-09-12, what actually happens depends on the router:

- **If `/opt/etc/init.d` does not exist**, the heredoc write fails, `_writeFile` compares `wc -c` against the expected byte count, and the deploy throws. So it is not silent. But the message says *"check free space on the router filesystem"*, which is the wrong diagnosis and would send someone hunting in the wrong place.
- **If `/opt/etc/init.d` exists but is not a working Download Master install**, the write succeeds, the cron entries install, and nothing runs the script at the next boot. That case IS silent, and matches what the backlog described.

Either way the fix is the same and cheap: probe for the directory during the pre-flight and say what
is missing in the user's terms. Worth doing whether or not the paid tier ever ships.

---

## 8. Reference docs

- Flutter installation: <https://www.revenuecat.com/docs/getting-started/installation/flutter>
- Google Play product setup: <https://www.revenuecat.com/docs/getting-started/entitlements/android-products>
- Non-subscription purchases: <https://www.revenuecat.com/docs/platform-resources/non-subscriptions>
- Customer info and entitlements: <https://www.revenuecat.com/docs/customers/customer-info>
- Caching: <https://www.revenuecat.com/docs/test-and-launch/debugging/caching>
- Restore behaviour: <https://www.revenuecat.com/docs/projects/restore-behavior>
- Implementation responsibilities: <https://www.revenuecat.com/docs/platform-resources/implementation-responsibilities>

---

## 9. Sample code from the advisory session

Kept as written on 2026-08-05. Treat as illustrative: check it against the current SDK before using
any of it, and note that all of it belongs behind `lib/entitlement.dart` rather than in a screen.

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
