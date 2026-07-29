# App Name: cfg-pia-wg
Short name: The simplest way to manage and maintain PIA WireGuard configs on your router.
Full description (3,965/4000 characters):

WireGuard (WG) configuration application for Private Internet Access (PIA) users.

▶ Enjoy the peace of mind that comes from a persistent VPN on your router
▶ Deploy a self-healing watchdog to automatically re-create your VPN (Asuswrt-Merlin firmware)
▶ Send optional reconfig email alerts
▶ Manage ASUS router WG VPNs
▶ Create a standalone config file
▶ Extensive in-app and router-based logging

AUTOMATE

When your WG VPN config expires, as it periodically does, this app replaces manual scripts with a streamlined workflow. It connects to PIA's provisioning API, benchmarks latency, and exports a .conf payload in seconds. For Asuswrt-Merlin-based routers, write configs directly into client slots seamlessly, no computer required.

SIMPLICITY: couch-to-router in seconds

Generating configs by hand requires significant expertise. Official scripts require a steep learning curve. Other workarounds require running desktop software to capture keys. This app makes the migration to high-speed WG completely effortless without needing a computer. The app wraps enterprise-grade automation into a simple mobile interface: tap your desired region from a live latency list, enter your credentials, and deploy directly to your router. An encrypted tunnel is active before you can even stand up from the couch. Optionally, deploy a self-healing script and never touch your WG config again!

WHY RUN A VPN ON YOUR ROUTER?

Configuring a VPN at the router level secures your entire household, protecting devices like smart TVs and consoles that cannot run VPN software. While OpenVPN offers stability, it is resource-intensive, capping speeds at around 100 Mbps on mid-range hardware and pinning the router CPU at 100%. Switching to WG reduces overhead, allowing your hardware to operate closer to your actual ISP speed. Testing on a 500 Mbps connection saw speeds jump from 154 Mbps under OpenVPN to 323 Mbps with WG on identical hardware.

CORE FUNCTIONALITY & SECURITY

The app measures latency across available region nodes to ensure your profile targets the fastest path. It pushes configs directly into your router with automated snapshot backup and state rollback recovery if verification fails. Because PIA WG tokens expire, this app simplifies recurring regeneration down to a few taps or deploy the watchdog and make it set-and-forget!

Built with a strict zero-persistence footprint to protect credentials and private keys, volatile variables reside exclusively in system RAM and are never written to device storage or logged. Android FLAG_SECURE blocks screenshots and blanks the app view in the Recent Apps interface. Predictive dictionary caching, auto-correction tracking, and keyboard learning behaviours are disabled in interactive textboxes.

OPEN SOURCE & DISCLAIMERS

Verifiable build provenance, pinned dependencies to mitigate vulnerabilities, and open-source code are available for public audit. Comprehensive deployment flows, local build steps, architecture and diagrams are available on GitHub.

Requires an active PIA subscription. Router push requires an ASUS router running Asuswrt-Merlin firmware with WG client support and SSH access enabled. Speeds depend on your router CPU & ISP plan.

This is a free, independent, open-source app released under the GNU General Public License v3.0. It requires an active Private Internet Access (PIA) account subscription to authenticate with the provisioning endpoints. This app is not affiliated with, endorsed by, sponsored by, or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. Private Internet Access & PIA are trademarks of their respective owner. ASUS is a trademark of ASUSTek Computer Inc.

Source code & README: https://github.com/ExponentiallyDigital/cfg-pia-wg
Privacy Policy: https://exponentiallydigital.com/pia-wireguard-cfga/privacy.html
© 2026 Andrew Newbury, Exponentially Digital
===================

## Play Store releases

2. Open testing: 352 (0.6.22) Open testing for feedback
<en-AU>
This is the first Google Play Store public test release. Please provide feedback as necessary.
</en-AU>

1. Closed testing: 340 (0.6.10) new UI, self-healing wd + router mgmt
<en-AU>
This release delivers a fundamental & extensive redesign of the entire user interface and, for ASUS Merlin-based routers, provides a *self-healing* watchdog with email alerting & full WireGuard client router management.

What's new
Rebuilt the entire interface with a focus on user workflows. Moved to three main workflows: standalone cfg, router-based WireGuard VPN mgmt, & self-healing watchdog with alerting.
Extensive updates to all documentation (README, ARCHITECTURE, BUILDING, TESTING)
</en-AU>
