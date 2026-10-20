# App Review notes

Draft (ID-435), for App Store Connect's App Review Information, Notes. The text below the line goes in as it is, by `scripts/app_store_connect.py listing` (ID-455); the demo video (ID-456) is attached alongside it.

---

cfg-pia-wg is a configuration tool for ASUS home routers. It connects to the user's own router on their home network over SSH, and sets up and looks after the WireGuard VPN client that the router already has built in.

The app does not provide a VPN service, and nothing on the iPhone is routed through a VPN. It does not use NEVPNManager or any Network Extension. The VPN service is Private Internet Access (PIA), which the user subscribes to separately; the app uses PIA's public API to fetch a WireGuard configuration for the user's own PIA account. PIA is named in the app because it works only with PIA's servers. The app is not affiliated with or endorsed by PIA or ASUS, and says so in its description.

Reviewing without an ASUS router: almost every screen needs a router to connect to, and creating a VPN configuration needs a PIA account. The attached video shows the app working against a real router, from connecting to deploying the watchdog.

Without a router you can still see the main menu, ABOUT, SETTINGS' explanations, and each screen's connect form; a wrong router address is refused with a plain explanation. GENERATE needs no router, only a PIA account: it writes a WireGuard configuration file for any router or client.

The app's complete source code is public at https://github.com/ExponentiallyDigital/cfg-pia-wg, if you'd like to confirm any of the above.

Permissions: the app asks for local network access, because it reaches the router at its private address on the home network. It asks for nothing else.

There is no account with us, no sign-in to any service of ours, and no tracking or advertising.

In-app purchase: one non-consumable, "Router features" (lifetime_unlock), a one-time US$9.99 unlock of what writes to the router: creating, editing and enabling VPN tunnels, the watchdog, and assigning devices to a VPN. Everything that only looks at the router is free, as is GENERATE. Any of those buttons offers the purchase, and SETTINGS has RESTORE PURCHASE.
