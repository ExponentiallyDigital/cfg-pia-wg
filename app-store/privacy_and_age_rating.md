# App Privacy and age rating: the answers

Drafts (ID-434), for App Store Connect's App Privacy section and its age rating questionnaire. Each answer says why, so it can be checked against the app rather than taken on trust.

## App Privacy

**Data collection: "Yes, we collect data from this app": one type, Purchases, Purchase History,** since RevenueCat came to iOS (ID-401). Changed 2026-10-21, Andrew's approval; until then the answer was "No, we do not collect data from this app".

- **Purchase History, the only type.** RevenueCat records each purchase against an anonymous ID it makes itself. Its guidance for Apple's questions, read 2026-10-21 (revenuecat.com, Apple App Privacy):
  - **Used for:** App Functionality (receipt checks, and the unlock itself) and Analytics (RevenueCat's own dashboard). RevenueCat says every app using it ticks both.
  - **Linked to the user: No.** The app never calls RevenueCat's `logIn`, so the ID can't be tied to anyone.
  - **Used for tracking: No.** RevenueCat doesn't track users across apps, and the app has no other SDK that does.
- **No other type applies:** no custom user ID, no advertising identifier, no customer attributes, no analytics SDK.

- **No analytics, crash reporting, advertising or tracking SDK.** Nothing in the app sends data to the developer.
- **The router login** goes only to the user's own router, over SSH. It is held in memory and never written to the iPhone.
- **The PIA login** goes only to PIA, the service the user signed up to, to fetch a WireGuard key. Held in memory, never stored, never sent to the developer.
- **The watchdog's email settings** go only to the user's router, which sends the alerts through the user's own mail account.
- **Stored on the iPhone, never sent anywhere:** the router's LAN address, its SSH host key fingerprint, and PIA's public server list (SECURITY.md, "Data handling & privacy").
- **Purchases:** RevenueCat's, above. Nothing else in the app sends anything to the developer.

## Age rating

Every question is answered **None** or **No**, which gives **4+**.

- No violence, sexual content, profanity, horror, drugs, alcohol, tobacco, gambling or contests.
- **Unrestricted web access: No.** Links open in Safari, outside the app; the app has no browser of its own.
- **User-generated content: No.** Nothing is shared between users.
- **Messaging and chat: No.**
- **Medical or treatment information: No.**

## Content rights

**"No, it does not contain, show, or access third-party content."** Andrew's answer, 2026-10-21, asked by App Store Connect before the first submission. Apple means content made by others that the app shows people, such as music, films, images or articles. The app shows the user's own router settings and logs, and PIA's list of server regions, fetched with the user's own PIA account: the user's data, not published content. `scripts/app_store_connect.py listing` sets it on each run.
