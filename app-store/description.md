PIA's WireGuard keys expire, often in the small hours, and the tunnel can look connected while passing nothing. On stock ASUS firmware, a tunnel that's down sends its devices out through your ISP, showing your real IP.

cfg-pia-wg keeps PIA's WireGuard tunnels up on your ASUS router, stock or Merlin firmware, from your iPhone. A watchdog on the router renews a dead tunnel with a fresh key from PIA, and a kill switch holds while it does: Merlin's own, or on stock, one the app builds.

Set up once, then forget it

The watchdog lives on your router, checks each tunnel at your chosen interval, and when a key rotates it fetches a new one, rebuilds the connection and emails you to say it did. The VPN never missed a beat.

Devices, not slots

Router VPN clients are organised by slot. This app is organised by device, which is how you actually think about your network. Tap the TV, put it on a UK server. Tap the work laptop, send it straight to the internet. Tap the kids' tablet, put it on the local exit. See at a glance which device is on which VPN without touching a running tunnel. Rename a device while you're there, or take it off the internet altogether.

Pinned means pinned

A device pinned to a tunnel uses that tunnel or nothing. If the tunnel drops, expires or is being rebuilt, the device waits offline instead of slipping out unprotected. Stock ASUS firmware has no VPN kill switch, so this app builds one for IPv4. On Merlin, it also holds the device when you switch a tunnel off. No settings required; it just comes with the pin.

Faster than what you have now

If you're on OpenVPN, your router's CPU is the bottleneck. On a 500 Mbps plan, the same mid-range hardware went from 136 Mbps under OpenVPN to 499 Mbps under WireGuard.

And a VPN on the router covers the whole network, including TVs and consoles that can't run a VPN app.

Everything else

▶ Fresh PIA config written straight into a router slot, fastest server in your region picked for you
▶ Tunnels verified with real traffic, not assumed
▶ Run more than the ASUS default of two VPNs at once
▶ Standalone .conf files for any WireGuard client, any router

No desktop. No laptop. No scripts. Tap a region, enter your PIA login, deploy.

Built for people who read the privacy policy

No tracking, no advertising identifier, no adverts. Credentials and private keys stay in memory and are never logged. A copied config stays on this iPhone and clears itself after 60 seconds, and the app is covered when you switch away. Router writes take a snapshot first and roll back if verification fails. Every file the app puts on your router is marked as its own, and uninstall refuses to delete anything it didn't create.

Open source under GPL v3. Pinned dependencies, verifiable build provenance, automated security scanning on every release. Architecture and build steps are on GitHub. Audit it yourself.

You'll need

An active PIA subscription. An ASUS router with WireGuard client support and SSH enabled, stock or Merlin firmware. Standalone config generation works for any WireGuard-compatible router.

This app configures your router's own VPN client. It does not provide a VPN service itself, and nothing on your iPhone is routed through a VPN.

Not affiliated with, endorsed by or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. PIA and ASUS are trademarks of their respective owners.
