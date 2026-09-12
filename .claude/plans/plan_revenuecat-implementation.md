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

**Product `lifetime_unlock`. Entitlement `router_features`.** Two names for what feels like one
thing, and the difference is worth holding on to: a **product** is what Google sells and takes money
for, an **entitlement** is what the app checks. They are separate so a second product - an iOS
purchase, a bundle, a promotional grant - can unlock the same capability without a line of code
changing. **The app never asks about a product id, only about the entitlement.**

The entitlement is named after what the money buys, so it reads correctly where it is used: does
this customer have router features. Get these two out of step and the failure is silent - a paying
customer stays locked and it looks like a purchase problem.

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

**A one-off purchase, never a subscription. Decided 2026-09-12.** Not on taste, though the taste
runs that way too: **a subscription cannot be enforced here.** The watchdog runs on the router with
the app out of the picture, so a lapsed subscriber keeps the whole benefit, and a subscription you
cannot revoke is a donation with worse reviews. There is a second reason underneath it - the pitch
is "you will never think about this again", and billing someone monthly for not thinking about
something is a contradiction they notice at renewal, which is when set-and-forget utilities churn
hardest. This also rules out a Play free trial, which is a subscription-only construct.

**No hand-built trial either. Decided 2026-09-12.** A timer would be app-side state on anonymous
users, so a reinstall resets it, and a watchdog deployed on day one is kept forever regardless. The
only way to close that would be an expiry inside the deployed script, which is forbidden for the
reasons above and would additionally be a time bomb on someone else's router. **Google Play's own
refund window is the de-facto trial** and costs nothing to build - but it only re-locks the app if
Play server notifications are wired to RevenueCat, so that is not optional. Do not advertise it:
the terms are Google's to change.

**Gated is CREATE or CHANGE. Free is REMOVE. Decided 2026-09-12.** The sharper form of "reads free,
writes gated", and it settles the edge cases in one line: a locked user can always undo, never
build. Free even without the entitlement - SETTINGS UNINSTALL, REBOOT ROUTER, DEL PIA CERT, FORGET
ROUTER IP, slot DELETE, watchdog DELETE and watchdog DISABLE. Trapping your software, or a script
you deployed, on a stranger's router behind a purchase turns a pricing decision into a complaint.

One consequence accepted knowingly: DISABLE is free and ENABLE is not, so a locked user can pause a
grandfathered watchdog and then need to pay to restart it. That is their choice to make.

**Reads are free.** A locked user can connect to their router
and SEE their own slots, devices, status and logs - their own data is far more persuasive than mock
data, and less work. Anything that writes NVRAM, deploys a script or changes a routing rule needs
the entitlement. Two carve-outs on principle: **SETTINGS UNINSTALL and REBOOT ROUTER stay free even
for someone who has never paid.** Trapping your software on a stranger's router behind a purchase
turns a pricing decision into a complaint.

**Locked controls stay live and open the paywall.** A greyed button teaches "this app is broken"; a
button that answers teaches "this is the paid part", at the moment they are most interested.

**Existing users are grandfathered. Decided 2026-09-12.** Anyone who already has the app keeps full
use. A previously-free app that gates its existing users gets punished in reviews, and ratings are
what decide whether anyone new ever finds a niche tool.

**Self-building is never gated.** `BUILDING.md` is deliberately detailed enough that a low-skill
user can produce their own build, and that stays true. The charge buys not having to.

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

- **The price.** Not set - see "Pricing" below. It blocks creating the Play product, and nothing else: the gating, the paywall and the restore can all be built and tested against a faked entitlement first.
- **Whether the once-per-session advice is a dialog, a banner, or the paywall itself.**
- **What the paywall says about the watchdog.** A locked user opening WATCHDOG sees a screen with nothing on it, because there is no watchdog yet. Slot management and device assignment demonstrate themselves in read-only; the watchdog cannot. The copy has to carry it alone, and showing an example reconfigure alert may do more than any description - that email IS the product.
- **Play Console Data safety form.** Needs completing to reflect RevenueCat, and the Privacy Policy needs a line. This is a store-rejection item rather than a nicety: the SDK sees a pseudonymous app-user id.
---

## 3a. Pricing

Open, and stuck for weeks. What is settled is the SHAPE of the answer, which narrows it a long way.

**The price is not "what is this worth".** Enforcement is impossible and the source is public, so
the only question a motivated user asks is whether paying is cheaper than the alternative.

That alternative is dearer than it looks. The first draft of this section guessed "an hour with
`BUILDING.md`"; the maintainer, forty years in IT, reports the build environment took considerably
longer than that to stand up. Flutter, the Android SDK, signing keys and a locked dependency set is
most of a day for someone competent and doing it for the first time. **So this leg of the argument
points UP, not down**, and there is more headroom than a first look suggests.

**The market is small by construction:** PIA subscribers, who own an ASUS router, whose firmware
allows SSH, who have found the app. The brand that leads the market gives users no SSH at all. With
a market that size, the gap between two candidate prices is small in absolute revenue and large in
conversion - and every extra user is also a review, a bug report and a reason for the next person
to find it. **Optimise for adoption, not for revenue per user.**

**Too low is also wrong.** A router utility priced like a wallpaper app reads as a trinket to a
technical audience. The free tier already does real work, so this is an upgrade rather than a gate
on a shell, which supports a real number rather than a token one.

**The decision is reversible in one direction only.** Raising a one-off price later costs nothing:
existing owners keep what they bought and early buyers got a deal. Cutting it later tells everyone
who paid full price that they were wrong to. **So start at the low end of the plausible band and
raise it if conversion says to.**

Google takes 15% below USD 1M/year, so the take is 85%. Let Play convert regionally rather than
fixing one price.

**Decided 2026-09-12: USD 6.99**, which lands near AU$9.99, with Play converting the rest.

It moved up from 4.99 during the same conversation, for two reasons. The cost of self-building was
badly underestimated in the first draft - most of a day, not an hour - so there is headroom. And the
maintainer, who is squarely in the target market, would buy at AU$10 "without hesitation", which
means the threshold is above that rather than at it. Creator bias runs one way and is worth
discounting for, but being your own customer is better evidence than a guess.

The "start low and raise later" argument was dropped on inspection. It assumes a feedback loop that
will not exist: a trickle of installs in a niche never produces a signal clean enough to justify a
price change, so deferring the decision only means guessing again later with no better information.
Pick the number you believe in now.

### What the market actually looks like

Two calls for beta testers in 2026-07, on r/PrivateInternetAccess and r/WireGuard, drew **7,000
combined views and zero testers**.

That is worth reading carefully rather than gloomily. "Beta tester" is a far higher-friction ask
than "buy a finished thing for seven dollars": it wants an unfinished app, the exact hardware, and a
continuing relationship with a stranger. Zero on that funnel does not predict zero sales. Both posts
also predate stock firmware support, and **most ASUS owners run stock**, so the addressable hardware
has grown a long way since the measurement.

What it does say is that **discovery is the binding constraint, not price.** Seven thousand people
saw it and none acted, which is not a number problem. Concretely: the Play listing, its screenshots
and its keywords are worth more effort than any pricing decision, and a post that says "here is a
finished thing that fixes X" will do better than one asking for help testing. The router-enthusiast
forums are a better-targeted audience than either subreddit.

---

## 3b. The paywall, and where it appears

**Contextual, never interstitial.** The paywall opens when someone taps a control that writes -
DEPLOY, APPLY, CREATE, ENABLE - and at no other time. Not on launch, not on entering a screen. An
on-entry prompt fires at exactly the people the read-only view exists to welcome: they came to look
and the first thing that happens is a sales pitch. That is the placement that earns one-star
reviews from people who were browsing.

**A quiet line on entry, the paywall on action.** A small non-modal "read only - unlock to make
changes" marker in the header tells them the state once, without selling. The sell arrives when they
have shown they want the thing. No banners: banner blindness is real, and a persistent one reads as
advertising in an app whose whole character is that it does not behave like that.

**Say what THIS action would have done.** A feature grid converts worse than one sentence about the
button they just pressed. "Deploy this and your Melbourne tunnel repairs itself when PIA rotates the
key, without you touching it."

### The honest story - lead with this

The audience is technical, and reacts badly to countdown timers, scarcity language and anything that
smells engineered. It reacts well to plain claims that happen to be true. Every line below is
literally true of this app, which is unusual enough to be the strongest conversion lever available:

- **One payment.** No subscription, ever.
- **It keeps working offline** once bought, and forever.
- **Nothing is tracked.** No analytics, no advertising id, no usage data. There is no server on our side to send it to.
- **Your credentials are never stored on the device.** The only thing written to your phone is the router address, and there is a button to forget it.
- **The source is on GitHub**, and the build instructions are good enough to follow. You are paying for not having to.
- **Generating standalone configs stays free**, for everyone, forever, with or without a router.
- **What you buy is the router side**: slot management, per-device VPN assignment, and a watchdog that repairs your tunnel unattended.

Say them plainly. Do not dress them up - the plainness is the point, and this audience can tell.

### Two implementation details that are easy to get wrong

- **Show the store's own localised price string** from the offering (`package.storeProduct.priceString`). Never hardcode a number: the wrong currency destroys trust instantly and silently.
- **A visible "already purchased?" restore link on the paywall.** It removes double-purchase anxiety and saves support mail, and Apple will require it when iOS lands anyway.

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

The console work is one sequence across three consoles, and it is easy to lose your place in it because you keep going back to Play. So it is written as a single run of numbered steps: do them in order, top to bottom, and treat the console names as headings telling you where to click rather than as sections to work through separately.

**WAIT** marks the place where you stop and let Google catch up. Nothing after it works until it clears, so that is a coffee, not a bug.

Everything after step 25 is code, and none of it needs you.

### 1. Google Play Console

**Play Console - set the product up**

1. [x] **Payments profile.** Identity and bank details verified. Days, not minutes, if it is not already done.
2. [x] **Upload a build that links the billing library.** Any track, internal is fine. See "why this order" below - this is the step the plan originally got wrong.
3. [x] **Monetise with Play, One-time products, create it.** Product ID `lifetime_unlock`, one buy purchase option, priced.
4. [x] **Activate it.** New products are inactive, and buying an inactive product fails with an unhelpful error.

**Google Cloud - create the identity**

5. [x] **APIs and services, Enable APIs.** Enable **Google Play Android Developer API**.
6. [x] Enable **Google Play Developer Reporting API**.
7. [x] Enable **Cloud Pub/Sub API**. Needed later, at step 23.
8. [x] **Create the service account**, and under IAM give it **Pub/Sub Editor** and **Monitoring Viewer**. Pub/Sub Admin only if Editor turns out to be too little.
    - **Pub/Sub Editor, NOT Pub/Sub Lite Editor.** Two different products with adjacent entries in the role picker, and Lite is a separate service that Google has since retired. Picked by mistake here on 2026-09-12; it grants nothing RevenueCat can use and the error message names only "the Google Cloud Pub/Sub API", which reads like the API is not enabled rather than like the wrong role.
    - **If "Connect to Google" then says it cannot CREATE a topic, escalate to Pub/Sub Admin.** RevenueCat's own docs offer that as the remedy for a permission error, and creating a topic is more than viewing one. Check two things first: that the Cloud Pub/Sub API is enabled on the SAME project the service account belongs to, and that a few minutes have passed - IAM is usually quick but not instant.
    - **Leave it on Admin afterwards.** Tempting to step back to Editor once the topic exists, but Editor already includes `pubsub.topics.create`, so creation alone should not have failed - which points at the other thing "Connect to Google" has to do: set the topic's IAM policy so Google's own notification account may publish to it. That needs Admin. Unproven, but it fits, and the cost of being wrong is one-sided: too little permission here means refund notifications stop arriving, in silence, and that notification is the entire mechanism behind treating Play's refund window as the trial. The account is dedicated to RevenueCat and scoped to a project holding one topic, so Admin on it is a small surface.
    - Remove the **Pub/Sub Lite Editor** role if it is still attached. It grants nothing here and it is the thing that will confuse the next person reading the IAM list.
    - **This is IAM and Admin, IAM, Grant access - NOT the Service Accounts page.** The role is granted on the PROJECT, with the service account as the principal. The Service Accounts page has its own permissions tab that controls who may act as the account, which is a different thing and does not grant it anything.
    - The symptom of getting this wrong is precise and worth recognising: RevenueCat shows **Valid credentials** for Play and separately reports *"your Google service account credentials do not have permissions to access the Google Cloud Pub/Sub API"*. Play access working while Pub/Sub is refused means the invite at step 10 succeeded and the project-level IAM grant did not.
9. [x] **Create a key, type JSON, download it.** This is a credential. It lives in a keysafe, never in this repo.

**Play Console - let the identity in.** Creating the account granted it nothing. This is where access actually happens.

10. [x] **Users and permissions, Invite new users.** The invitee is the `client_email` inside that JSON, ending `@<project>.iam.gserviceaccount.com`.
11. [x] **Grant four permissions, all at ACCOUNT level:** *View app information and download bulk reports (read-only)*, *View financial data, orders and cancellation survey responses*, *Manage orders and subscriptions*, and *Manage store presence*. The last one is under Store presence and is the one people miss; in-app products need it.
12. [x] **Edit and save any product description.** RevenueCat's documented nudge: it often validates the credentials immediately instead of overnight. **WAIT** - up to 36 hours otherwise. A user showing ACTIVE in Play Console means the invite landed, not that the API can use it yet.

### 2. RevenueCat dashboard

**RevenueCat - connect it up.** Renumbered 2026-09-12 to match the order RevenueCat's own interface asks for things, which is not the order this plan first guessed.

13. [x] **Create an account and a Project.**
14. [x] **Create the entitlement** `router_features`. The spelling matters: the app checks this exact string. RevenueCat asks for the entitlement before a product exists, so attaching one happens later, at step 19.
15. [x] **Add a new Play Store configuration.** RevenueCat defaults this to a test sandbox.
16. [x] **Add an app.** Platform Android, package name `com.exponentiallydigital.pia_wireguard_cfga` exactly, and upload the JSON from step 9.
17. [x] **Copy the public Android SDK key.** It starts `goog_`, and it is the **Public API Key** on the app's card under Apps. **This is the one value the code needs.** It appears as soon as the app exists, so it can be handed over while RevenueCat is still complaining about the Play connection.
    - **Not the Test configuration key** further down that same page. That one drives RevenueCat's sandbox, where every transaction is fake. Ship it by mistake and the app never talks to Play at all, while looking like it works.
18. [x] **Import the product** `lifetime_unlock` from Play, or create it. **Type: non-consumable.** The single most expensive setting to get wrong - see section 4 - and it only shows up when a real customer changes phone.
19. [*] **Attach the product to the `router_features` entitlement.** Created at step 14 with nothing in it. An entitlement with no product attached grants nobody anything, and it fails silently: purchases succeed and the app stays locked. AN: it's already attached.
    - **Expect TWO products and two attachments, not one.** RevenueCat creates a **Test Store** twin beside the Play Store product - `lifetime` next to `lifetime_unlock` - and attaches it to the same entitlement. That is correct and wanted: it is what lets the app be tested without Play. It also means the audit log shows `product_created` and `entitlement_products_attached` twice for what was one piece of work. The twin is inert in production, because the Test Store only grants anything to RevenueCat's own sandbox key.
20. [*] **Create the default offering**, one package, containing the product. AN: it's already created.
21. [x] **Project settings, General.** Confirm restore behaviour is **Transfer to new App User ID**, which is the default. Anonymous restore depends on it. AN: that is th defefault, it's under option "Transferring purchases seen on multiple App User IDs"
22. [x] **Copy the Pub/Sub topic name** RevenueCat gives you. It is not on the project page: go to the **Google Play app settings** for the app, and press **Connect to Google**, which lists the available topics and generates the id. **That list only appears once the service credentials from step 12 have validated**, so an empty or missing Pub/Sub section is the propagation wait showing itself, not a step you skipped.

**Play Console - close the loop**

23. [x] **Play Console, the app dashboard, Monetise, Monetisation setup.** Paste that topic id next to **Topic name** under Real-time developer notifications, choose the notification content, and save.
    - **Notification content: pick "subscriptions, voided purchases and all one-time products"**, the second option, not the default. The default covers voids but leaves out the rest of the one-time product lifecycle, and RevenueCat's guidance is to include them when you sell one-time products. A refund that arrives late, or not at all, leaves the app unlocked for someone who has had their money back - and the refund window IS the trial here.
    - **Grant Google itself publish rights on the topic**, or **Send test notification** fails with a message blaming the topic format, Google Cloud setup and permissions all at once. In Google Cloud, Pub/Sub, Topics, the topic, Permissions: add the principal `google-play-developer-notifications@system.gserviceaccount.com` with the role **Pub/Sub Publisher**. This is Google's own account, the same string for every developer, and it is separate from your service account - that one lets RevenueCat READ, this one lets Play WRITE.
    - **Then send the test notification.** RevenueCat calls it the way to verify Pub/Sub is connected to your account, and it costs nothing to find out today rather than from a customer whose refund never took effect.
    - **A pass looks like nothing.** A brief "notification sent" and no error is the whole of it. Play reports no delivery confirmation and RevenueCat surfaces no test event, so silence here is success. An actual failure is loud, and names topic format, Cloud setup and permissions all at once. **Not optional here:** without it a refund never reaches RevenueCat and the app stays unlocked, which is the whole mechanism behind using Play's refund window as the trial. This is also what clears RevenueCat's own "no Pub/Sub" warning, so seeing that warning before this step is expected rather than a mistake.
24. [x] **Licence testing.** In Google Play Console: Settings, Licence testing, add the tester Gmail accounts. Then opt those same accounts into the **internal** and **closed** testing tracks - two separate lists, and forgetting the second is the usual cause of "it just charged me".
    - Done 2026-09-12. The accounts, their licence response and their track membership are recorded in `.claude/testing/2026-09-12_purchase-test-accounts.md`, which is gitignored because it names real addresses. Nothing in the repo names a tester.
25. [x] **Data safety form.** Submitted 2026-09-12. Select the app, then **Monitor and improve**, **Policy and programs**, **App content**, and the **ACTIONED** tab. Data safety is one of the sections there. (Measured 2026-09-12; Google's own help article says only "go to the App content page".) Declare what RevenueCat sees: a pseudonymous app user id, purchase history, device and diagnostic data. A store-rejection item, not a nicety. Keep it consistent with `SECURITY.md` and `README.md`.


**Data safety, drafted answers.** Play's wording shifts, so treat these as the position to hold rather than exact field names. The position is already written up in `SECURITY.md` under "Secret management" and "Data handling & privacy" - keep all three consistent, because a reviewer who finds them disagreeing has a reason to reject.

| Question | Answer | Why |
| --- | --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** | Only once purchasing is live. Before that the honest answer was no. |
| Is all collected data encrypted in transit? | **Yes** | |
| Does the app allow users to create an account? | **No** | |
| Can users log in with accounts created outside the app? | **No** | There is no login of any kind. |
| Do you provide a way to request data deletion? | **Leave the optional question unanswered** | Answering yes obliges a published deletion URL, and there is no account to delete. Nothing published claims otherwise. |
| **Financial info, purchase history** | **Collected**, not shared. Purposes: **App functionality AND Analytics**. Users can choose. | The ONLY data type to tick. RevenueCat's own guidance names it and nothing else. Analytics belongs there because the RevenueCat dashboard reports revenue back to the developer - that is analytics on purchases, and it is not usage tracking. "Users can choose" because the data exists only if someone buys, and the app is fully usable without buying. |
| Is the purchase history processed ephemerally? | **No** | Ephemeral means in memory, for one request, then gone. RevenueCat stores the record so the app can ask on every launch, so a purchase survives a reinstall, and so a refund can take the unlock away. Answering yes would be untrue and would hide the disclosure from the store listing. |
| Device or other IDs | **Do NOT tick** | RevenueCat says this applies only to integrations using an advertising identifier such as `gpsAdId` or `androidId`. There are none here, and the anonymous installation id does not trigger it. |
| App info and performance, diagnostics or crash logs | **Do NOT tick** | RevenueCat states plainly that it does not collect crash logs or diagnostics, and this app has no crash reporting of its own. |
| Shared, for anything | **No** | RevenueCat is a service provider acting for the developer, which Google does not count as sharing. It WOULD become sharing with custom app user ids or any personally identifiable value - which is one more reason the app never calls `logIn`. |

What must NOT be claimed: any location, contacts, messages, photos, personal identifiers, or advertising id. None of those are touched, and the app still carries no analytics and no usage tracking of any kind.

> [!IMPORTANT]
> Four things here are easy to get wrong, and three of them already went wrong once:
>
> - **Steps 1 to 4 are not "console work with no code".** Play will not let you create a one-time product until it has an artifact that can actually transact. See "why this order" below.
> - **Step 9 does not grant access.** A service account is an identity and nothing more. Until step 10 invites it, Play gives it nothing, and the error you get says nothing useful about which half is missing.
> - **Step 12 is a wait, not a failure.** ACTIVE in the user list is the invite, not the API.
> - **Step 18, non-consumable.** A consumable cannot be restored under Billing Client 8, and the customer finds that out, not you.
> - **Step 19, attaching the product to the entitlement.** RevenueCat lets you create an empty entitlement and never warns you it is empty. A purchase against one succeeds and unlocks nothing.

**What was entered, 2026-09-12**

- One-time product: Product ID `lifetime_unlock`, tags blank
- Product description: Name "cfg-pia-wg lifetime unlock"; Description "Router setup, watchdog and device assignment. One payment, no subscription."; Icon `assets/icon/icon.png`
- Tax and compliance: Digital app sales, all ages, no country or region restrictions
- Purchase option: ID `lifetime-unlock`, type Buy, tags blank
- Availability and pricing: all regions, US$6.99, landing at AU$9.99

**On the purchase option ID.** Nothing in this app's source will ever name it: the code asks RevenueCat for the entitlement and RevenueCat resolves the product and its option. Two reasons it still matters. **Keep it to ONE buy option** - RevenueCat only auto-imports a Google one-time product that is backwards compatible, and Google marks the FIRST buy option backwards compatible automatically, so one option keeps the import automatic and a second is something to configure by hand. And treat the ID as **permanent**, like the product ID. `lifetime-unlock` mirrors the product ID, which is what you want when it appears in a Play report beside other rows. Hyphens are legal here and illegal in the product ID, which is why the two are spelled differently.

**On the product ID `lifetime_unlock`.** Permanent, and it cannot be reused even if the product is deleted. Google's rule is start with a number or lowercase letter, then numbers, lowercase letters, underscores and periods only. **No hyphens** - the first name considered was `cfg-pia-wg_pro_unlock`, which Play would have rejected. No app-name prefix, because the product already lives inside the package and RevenueCat scopes it by project. "Lifetime" rather than "pro" names the MODEL, which is the thing being sold.

**Why this order, and what the plan had wrong**

This section used to say steps 1 to 4 were console work with no code. That is wrong, and it stops you dead at the first product you try to create. It took two attempts to find the real requirement:

1. The products page first says **"to add one-time products, you need to add the BILLING permission to your APK"**, and offers nothing else.
2. Adding the permission and uploading is still not enough. Play then reports **"your app currently uses Play Billing Library version AIDL and must be updated to at least version 8.0.0"**. Play judges an artifact by the billing library it LINKS, not by what it asks for, and an app with the permission and no library reads as the legacy AIDL interface.

So the real precondition is the SDK itself, which is section 3 below, and section 3 has to happen before section 1 can finish. **This is not blocked on the `goog_` key:** the key CONFIGURES RevenueCat, it does not link it, and Play only cares that the library is present.

Done: the manifest permission in build 442, and `purchases_flutter` 10.12.0, bringing Play Billing Library 8.3.0, in build 443. Nothing calls it. Build 442 was uploaded and its version code is spent, so 443 is the build that carries the library up to a track.

Two things worth knowing for next time. **R8 must not strip it** - a bare `com.android.billingclient` dependency with nothing referencing it would compile and then fail the console, because Play reads `billing.properties` and the classes out of the shipped artifact. Going through the Flutter plugin avoids that, since the generated registrant references it. And **dependency locking will refuse the build** until all three `gradle.lockfile`s are regenerated with `cd android && ./gradlew :generateLockfiles`.

Play's menu has also been relabelled. **Monetise with Play** now holds *App pricing*, *One-time products* and *Subscriptions*. What older docs call an "in-app product" is a **one-time product** in the current console.


### 3. Add the SDK and configure it

- `purchases_flutter` in `pubspec.yaml`. **Done in build 443 at 10.12.0**, pulled forward because Play would not accept an upload without a billing library - see "why this order, and what the plan had wrong" above. It resolves to RevenueCat Android 10.20.0 and Play Billing Library 8.3.0; the floor that matters for non-consumable handling is Android SDK 7.11.0, comfortably met.
- It also pulls `purchases-store-amazon`, which is dead weight for a Play-only app. Not removed: it has not been measured and an exclusion is the kind of thing that breaks a purchase months later. Worth a look if size becomes an issue.
- `BILLING` permission in `AndroidManifest.xml`. Done in 442, with `README.md` section 8.4 to match.
- Configure at launch with the Android key. **No `logIn` call** - anonymous throughout. Done in build 444, off the first frame in `app_shell.dart`, and it cannot fail loudly: a keyless build never starts the SDK, and an unreachable store logs a warning and leaves the paywall saying so.
- This is a STRICT dependency-locked project: `gradle.lockfile` and `pubspec.lock` both need regenerating, and the lockfile set is part of the build. Done in 443. The build fails with "resolved X which is not part of the dependency lock state" until `cd android && ./gradlew :generateLockfiles` has run.

### 3a. Where the key lives, and the GitHub APK question

**The key is NOT compiled in.** It arrives as `--dart-define=REVENUECAT_ANDROID_KEY=...`, supplied by `release.yml` from a repository secret of the same name. Not for secrecy: RevenueCat's public key is designed to be embedded and can be read out of any APK in a minute. The reason is what a build WITHOUT it should do.

Google Play refuses purchases from an artifact it did not distribute. So a self-built copy carrying a compiled-in key would show a paywall its owner could never complete - the worst of both worlds, and a direct contradiction of what the paywall says: the source is on GitHub, and what you are paying for is not having to build it. A keyless build therefore has **no purchasing at all and everything unlocked**, which is that promise made good.

The corollary is that the Play build must never be keyless, because it would ship the paid features to everyone while looking entirely normal. `release.yml` fails with an `::error::` when the secret is empty, before it builds anything.

**No binaries are published, so there is no free pre-built path.** A GitHub release here carries the SBOM and the licence manifest and nothing else; the `.aab` goes straight to Play. APK builds are opt-in via a workflow input, are never attached to a release, and exist as a diagnostic copy of what shipped - so they carry the same key, because a keyless one would behave differently from the artifact it is meant to represent.

This was briefly written up as an open question with three options. It is not one: the premise, that GitHub hands out a working binary, was wrong.

**Local builds are keyless too**, and that is fine - Play Billing cannot work from `flutter run` regardless. Real purchase testing happens against a build that went up to a track, with licence testers (step 24).

### 4. Fill in the seam

- `lib/entitlement.dart` already exists and returns `true`. Give it a real implementation over `getCustomerInfo()`, returning false on any failure so a brand-new offline install is locked rather than crashing. **Done in build 444.** It defaults to locked once a key is present, and a returning customer is covered by the SDK's own cache, so offline does not lock out someone who has paid.
- Keep it the ONLY place the rest of the app asks. Every screen should call the seam, never the SDK.

**Build 442 delivered sections 5, 6 and 8, against a stubbed offering.** The gates, the paywall page, the reactive seam and the home-screen cleanup are in and tested; `Paywall.offer` is null until something sets it, which the page renders as a disabled "Not available right now" button. What is left is sections 3, 4 and 7 - the SDK, the real seam implementation and restore - all of which need the `goog_` key.

### 5. Gate the three paid screens

- MANAGE, WATCHDOG and DEVICE ASSIGNMENT. Standalone generation and the app log stay free.
- **Order: entitlement, then dependencies, then the offer to install them.** Pinned by `test/widgets/router_slots_screen_test.dart`.
- Locked screens are accessible but read only, with the once-per-session advice.
- Done in 442. The device screen gates at APPLY rather than at entry, because looking at your own devices is the most persuasive thing that screen can do.

### 6. The paywall

- Done in 442, as a PAGE rather than a modal - the content grows, and an unbounded card is the bug this project shipped four times. A page offering the lifetime unlock. Lead on what it buys: a watchdog that renews PIA keys without anyone touching it, and device assignment.
- Shown only after the pre-flight passes.
- Needs an offline state: "connect to complete the purchase".

### 7. Restore

- **Corrected 2026-09-12: there is no silent auto-restore, and there must not be.** RevenueCat's own guidance is that `restorePurchases` must never be called programmatically, because it can raise an operating-system sign-in prompt - and one of those on a cold start, that nobody asked for, is alarming and inexplicable. Restore is only ever a button the user pressed.
- **The launch path uses `syncPurchases` instead**, which is the sanctioned programmatic call and raises no prompt. Done in build 444: after configure, and only when the entitlement is not already held, it hands the fresh anonymous id whatever Google Play already knows the account owns. That covers the reinstall and new-phone cases without anyone pressing anything.
- **The button is on the settings screen** (`settings_restore_purchase`), beside the other one-off actions, and it is hidden entirely in a build that cannot sell - there, it could only ever report "no purchase found". The paywall carries the same action. Done in build 444.
- Note what is NOT needed: no flag in `router_prefs.dart`, which `no_secret_prefs_test` would refuse anyway, and no local state of any kind. The purchase belongs to the Google account.
- **`android:allowBackup="false"` stays.** RevenueCat's own advice for Billing Client 8 is to enable app backups so their shared-preferences file survives a reinstall and the anonymous app user id comes back with it. Do not take that advice here. It exists for CONSUMED one-time products, which Billing Client 8 can no longer query; a non-consumable is still returned by Play for the signed-in Google account, so `restorePurchases()` recovers it with no local state at all. Backups are off in this app deliberately, because it holds router and PIA credentials, and buying that back for a restore path that already works would be a poor trade.
- The dependency to watch is the product staying **non-consumable**. If it were ever consumed, the reasoning above collapses and there is no way back for a customer who reinstalls.

### 8. Home screen cleanup

- Remove PayPal and Patreon, keep the review link, re-space the footer. Done in 442. The review link needed a fixed gap above it as well as the `Spacer`: on a screen short enough to scroll the Spacer collapses to nothing and the ask ends up crammed under the help line.

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
    return info.entitlements.active.containsKey('router_features');
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
    final unlocked = info.entitlements.active.containsKey('router_features');
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
    final unlocked = info.entitlements.active.containsKey('router_features');
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
