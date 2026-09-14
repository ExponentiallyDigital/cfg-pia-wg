Your ASUS router already has a WireGuard client built in. This app makes it effortless to use.

cfg-pia-wg puts every device on your network and every PIA VPN on your router onto one screen, from your phone.

Devices, not slots

Router VPN clients are organised by slot. This app is organised by device, which is how you actually think about your network. Tap the TV, put it on a UK server. Tap the work laptop, send it straight to the internet. Tap the kids' tablet, put it on the local exit. See at a glance which device is on which VPN without touching a running tunnel. Three taps, done.

Set up once, then forget it

PIA rotates its WireGuard keys and your tunnel dies. You find out a week later. Or never. The watchdog lives on your router, checks each tunnel at your chosen interval, and when a key rotates it fetches a new one, rebuilds the connection and emails you to say it did. You read the email over breakfast. The VPN never missed a beat.

Faster than what you have now

If you're on OpenVPN, your router's CPU is the bottleneck. On a 500 Mbps plan, the same mid-range hardware went from 136 Mbps under OpenVPN to 499 Mbps under WireGuard. That's not a tweak. That's the speed you're already paying your ISP for.

And a VPN on the router covers the whole house, including the TV and consoles that can't run a VPN app.

Everything else

▶ Fresh PIA config written straight into a router slot, fastest server in your region picked for you
▶ Tunnels verified with real traffic, not assumed
▶ Run more VPNs at once than the ASUS default of two
▶ Standalone .conf files for any WireGuard client, any router, free forever

No desktop. No laptop. No scripts. Tap a region, enter your PIA login, deploy. Done before you stand up from the couch.

What it costs

Looking is free. Slots, devices, status, logs: always visible, no unlock. Standalone config generation is free for everyone, forever.

Writing to your router is a one-time US$6.99. Less than a month of the VPN you already pay for, and it never renews. No subscription. No tracking, no analytics, no advertising ID. Works offline once bought and keeps working.

The source is on GitHub and the build instructions are good enough to follow. What you're paying for is not having to.

Built for people who read the privacy policy

Credentials and private keys live in RAM only. Never written to storage, never logged. Screenshots blocked, app blanked in Recent Apps, keyboard learning off in every sensitive field. Router writes take a snapshot first and roll back if verification fails. Every file the app puts on your router is marked as its own, and uninstall refuses to delete anything it didn't create.

Open source under GPL v3. Pinned dependencies, verifiable build provenance, automated security scanning on every release. Architecture and build steps are on GitHub. Audit it yourself.

You'll need

An active PIA subscription. An ASUS router with WireGuard client support and SSH enabled, stock or Merlin firmware. Device assignment needs stock ASUS firmware. Standalone config generation works with no router at all.

Not affiliated with, endorsed by or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. PIA and ASUS are trademarks of their respective owners.

Source: https://github.com/ExponentiallyDigital/cfg-pia-wg
© 2026 Andrew Newbury, Exponentially Digital