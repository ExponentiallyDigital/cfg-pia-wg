# App Privacy and age rating: the answers

Drafts (ID-434), for App Store Connect's App Privacy section and its age rating questionnaire. Each answer says why, so it can be checked against the app rather than taken on trust.

## App Privacy

**Data collection: "No, we do not collect data from this app."** Apple shows it as "Data Not Collected".

- **No analytics, crash reporting, advertising or tracking SDK.** Nothing in the app sends data to the developer.
- **The router login** goes only to the user's own router, over SSH. It is held in memory and never written to the iPhone.
- **The PIA login** goes only to PIA, the service the user signed up to, to fetch a WireGuard key. Held in memory, never stored, never sent to the developer.
- **The watchdog's email settings** go only to the user's router, which sends the alerts through the user's own mail account.
- **Stored on the iPhone, never sent anywhere:** the router's LAN address, its SSH host key fingerprint, and PIA's public server list (SECURITY.md, "Data handling & privacy").
- **Purchases:** none on iOS yet. When RevenueCat comes to the App Store (ID-401), it receives purchase history against an anonymous identifier it makes itself; these answers must be revisited then, before that build is submitted.

## Age rating

Every question is answered **None** or **No**, which gives **4+**.

- No violence, sexual content, profanity, horror, drugs, alcohol, tobacco, gambling or contests.
- **Unrestricted web access: No.** Links open in Safari, outside the app; the app has no browser of its own.
- **User-generated content: No.** Nothing is shared between users.
- **Messaging and chat: No.**
- **Medical or treatment information: No.**
