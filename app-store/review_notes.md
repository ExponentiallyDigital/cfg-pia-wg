# App Review notes

Draft (ID-435), for App Store Connect's App Review Information, Notes. The text below the line goes in as it is, by `scripts/app_store_connect.py listing` (ID-455); the demo video (ID-456) is attached alongside it. The user information and the way to the purchase without a router were added after App Review asked for both on 2026-11-02 (ID-509). On 2026-11-08 Andrew's reply of 2026-11-03 was added in full below a second `---` line, the top half cut to fit Apple's 4,000 characters (ID-541).

---

cfg-pia-wg is a configuration tool for ASUS home routers. PIA is named in the app because it works only with PIA's servers. The app is not affiliated with or endorsed by PIA or ASUS, and says so in its description.

Reviewing without an ASUS router: almost every screen needs a router to connect to, and creating a VPN configuration needs a PIA account. The attached video shows the app working against a real router, from connecting to deploying the watchdog. Without a router you can still see the main menu, ABOUT, SETTINGS' explanations, and each screen's connect form. GENERATE needs no router, only a PIA account.

Permissions: the app asks only for local network access, because it reaches the router at its private address on the home network.

In-app purchase: one non-consumable, "Router features" (lifetime_unlock), a one-time US$9.99 unlock of what writes to the router: creating, editing and enabling VPN tunnels, the watchdog, and assigning devices to a VPN. Everything that only looks at the router is free, as is GENERATE.

---

1. VPN functionality (Guideline 2.1)

cfg-pia-wg is not a VPN app and does not use a VPN on the iPad or iPhone. It does not use NEVPNManager or any Network Extension, and none of the device's traffic goes through a VPN. The app is a configuration tool for ASUS home routers. Over SSH on the home network, it sets up the WireGuard VPN client that is built into the user's own router. The VPN service is Private Internet Access (PIA), which the user subscribes to separately.

What user information is the app collecting using VPN?
None. The app collects no user information through a VPN. Nothing is sent to us, the developer. There are no analytics, crash reporting, advertising or tracking SDKs, and there is no account with us.

What does the app handle, and where does it go?
- The router's login: sent only to the user's own router, over SSH on the local network. It is held in memory and never stored on the device.
- The PIA login: sent only to PIA over HTTPS, to get a WireGuard key for the user's own PIA account. It is held in memory and never stored on the device. If the user chooses to set up the optional "watchdog", the PIA login, and the user's own email login for alerts, are written to the user's own router so the router can renew the key on its own. They are not sent anywhere else, and they are removed when the watchdog is deleted.
- Stored on the device: the router's local network address, its SSH host key fingerprint, and PIA's public server list. None of these is a credential, and none is sent anywhere.
- Purchases: RevenueCat processes the In-App Purchase receipt against an anonymous ID it creates. The ID is not linked to the user. This is declared in App Privacy as Purchase History.

Will the data be shared with any third parties?
No user data is shared with anyone for any purpose. The only services the app talks to are the user's own router, PIA (with the user's own PIA account, for the user's own VPN) and Apple's StoreKit through RevenueCat (for the purchase).

The full source code is public, if you would like to check any of this: https://github.com/ExponentiallyDigital/cfg-pia-wg

2. Locating the In-App Purchase (Guideline 2.1(b))

Almost every paid feature needs an ASUS router, but one opens the purchase without one:

1. Open the app. On the main menu, tap SETTINGS.
2. Scroll down and tap MAX ACTIVE VPNS. It is shown in red because it changes an ASUS setting, but nothing is changed without a router.
3. The purchase screen opens. Tap "UNLOCK FOR LIFE - $9.99" to buy "Router features" with your sandbox account.
4. To check restoring: tap SETTINGS, then RESTORE PURCHASE.

The same purchase screen also opens from CREATE, ENABLE and EDIT on a VPN slot, and from the watchdog and DEVICES APPLY, but those need a connected router. The purchase is not restricted by storefront or device. The Paid Apps Agreement is active.

If you get a crash when testing, please include the crash log in any reply.
