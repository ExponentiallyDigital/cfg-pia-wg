App Name: Configure PIA WireGuard

Short name: The simplest way to manage & maintain PIA WireGuard configs on your router.

Full description: Automated WireGuard configuration utility for Private Internet Access (PIA) users.

Now features a _self-healing_ watchdog that maintains a persistent VPN with email alerting!

When your VPN configurations expire, PIA WireGuard Config App replaces manual scripts with a streamlined workflow. It connects to PIA's provisioning API, benchmarks latency, and exports a .conf payload in seconds. For compatible home networks, write configurations directly into Asuswrt-Merlin router client slots seamlessly, no computer required.

The simplicity breakthrough: couch-to-router in seconds

Generating PIA WireGuard configurations by hand requires significant expertise. Official scripts require a steep learning curve and a desktop terminal. Other workarounds require running desktop software to capture keys from local storage. This utility makes the migration to high-speed WireGuard completely effortless without needing a computer. The app wraps enterprise-grade automation into a simple mobile interface: tap your desired region from a live latency list, enter your credentials, and deploy directly to your router. Your encrypted tunnel is active before you can even stand up from the couch. Optionally, deploy a self-healing script and never touch your WireGuard config ever again!

Why run a VPN on your router?

Configuring a VPN at the router level secures your entire household at the source, instantly protecting devices like smart TVs and consoles that cannot run VPN software. While OpenVPN offers stability, it is resource-intensive, capping speeds at around 100 Mbps on mid-range hardware and pinning the router CPU at 100%. Switching your router to WireGuard reduces overhead, allowing your hardware to operate closer to actual ISP speed. Testing on a 500 Mbps HFC connection saw speeds jump from 154 Mbps under OpenVPN to 323 Mbps under WireGuard on identical hardware.

Core functionality and security

The app measures live TCP latency across available target nodes to ensure your profile targets the fastest path. It safely pushes configurations directly into router slots wgc1 to wgc5 with automated snapshot backups and state rollback recovery if verification fails. Because PIA WireGuard tokens expire periodically, this tool simplifies recurring file regeneration down to a few taps.

Built with a strict zero-persistence footprint to protect credentials and private keys, volatile variables reside exclusively in system RAM and are never written to storage or logged. The app enforces the native Android FLAG_SECURE flag to block screenshots and blank the app view in the Recent Apps interface. Interactive textboxes explicitly disable predictive dictionary caching, auto-correction tracking, and keyboard learning behaviours.

Open source and disclaimers

This application features verifiable build provenance, pinned dependencies to mitigate vulnerabilities, and open source code available for public audit. Comprehensive deployment flows, local build steps, architecture and diagrams are available for review on GitHub.

Requires an active PIA subscription. Router push requires an ASUS router running Asuswrt-Merlin firmware with WireGuard client support and SSH access enabled. Speeds depend on your router CPU and ISP plan.

This is an independent, open-source utility released under the GNU General Public License v3.0. It requires an active Private Internet Access (PIA) account subscription to authenticate with the provisioning endpoints. This application is not affiliated with, endorsed by, sponsored by, or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. Private Internet Access and PIA are trademarks of their respective owner. ASUS is a trademark of ASUSTek Computer Inc.

GitHub repo: https://github.com/ExponentiallyDigital/cfg-pia-wg

===================

## Play Store releases

340 (0.6.10) new UI, self-healing wd + router mgmt

<en-AU>
This release delivers a fundamental and extensive redesign of the entire user interface and, for ASUS Merlin-based routers, provides a *self-healing* watchdog with email alerting and full WireGuard client router management.

What's new
Rebuilt the entire interface with a focus on user workflows. Moved to three main workflows: standalone cfg, router-based WireGuard VPN mgmt, & self-healing watchdog with alerting.
Extensive updates to all documentation (README, ARCHITECTURE, BUILDING, TESTING)
</en-AU>
