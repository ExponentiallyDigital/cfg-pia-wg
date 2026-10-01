<h1>
  <img src="./assets/icon/splash_detail.png" alt="cfg-pia-wg" width="150" align="middle" />
  &nbsp;CFG-PIA-WG
</h1>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/releases" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/v/release/ExponentiallyDigital/cfg-pia-wg?color=0969DA" alt="Release"></a> 
<a href="https://www.android.com/" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/platform-Android-57606A?logo=android&logoColor=white" alt="Platform"></a> 
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/LICENSE" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/license/ExponentiallyDigital/cfg-pia-wg?color=0969DA" alt="License"></a> 
<a href="https://github.com/ExponentiallyDigital/ExponentiallyDigital/security/policy" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/security-policy-57606A" alt="Security Policy"></a> 
</br>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/releases" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/downloads/ExponentiallyDigital/cfg-pia-wg/total?color=0969DA" alt="Downloads"></a>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://visitor-badge.laobi.icu/badge?page_id=ExponentiallyDigital.cfg-pia-wg" alt="Visitor Count"></a>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/commits/main" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/commit-activity/t/ExponentiallyDigital/cfg-pia-wg?color=D97706&label=commits" alt="Total Commits"></a>
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/languages/code-size/ExponentiallyDigital/cfg-pia-wg?color=57606A" alt="Code Size"></a>
<br>
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=security_rating" alt="Security Rating"></a> 
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=reliability_rating" alt="Reliability"></a> 
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=sqale_rating" alt="Maintainability"></a> 
<a href="https://sonarcloud.io/summary/new_code?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=alert_status" alt="Quality"></a> 
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=vulnerabilities" alt="Vulnerabilities"></a> 
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=bugs" alt="Bugs"></a> 
<a href="https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://sonarcloud.io/api/project_badges/measure?project=ExponentiallyDigital_cfg-pia-wg&metric=coverage" alt="Coverage"></a>

---

A native Android app for Private Internet Access (PIA) WireGuard VPNs on ASUS routers, stock firmware or [Asuswrt-Merlin](https://www.asuswrt-merlin.net/) (beta).

**Device assignment.** Which device is on which VPN? On stock firmware, your router can't easily tell you. It thinks in slots: five numbered WireGuard clients, and finding out which devices use one generally requires stopping it and seeing what breaks, or what goes out in the clear. `cfg-pia-wg` thinks in devices. One screen lists everything on your network and the VPN each device is using right now. Moving a device to a different VPN - or off VPN entirely - is taps away. No slot numbers, nothing to stop first, and no deciphering a multi-click WebUI apparently designed by a sadist.

**Tunnels that stay up on their own.** PIA WireGuard configurations expire without warning, anywhere from a day to a couple of weeks or anywhere in between; often in the small hours of the morning. A dead tunnel looks much like a working one until something you care about stops loading or silently traverses the Internet in the raw. The app can install a **self-healing** watchdog on the router itself. It checks tunnels on your chosen schedule, builds fresh configurations when the old ones inevitably stop working, and emails you what happened and how long a tunnel was down for. Meanwhile, fail-closed routing blocks traffic from the affected devices rather than letting it out unprotected: a kill switch that fixes itself. Batteries not included.

Underneath both is the plumbing: the app authenticates with PIA's provisioning API, selects the lowest-latency server in your chosen region, generates a fresh WireGuard keypair, and either writes the result into one of the router's five slots or hands you the complete `.conf` to copy, share, or save. Generating a `.conf` needs no router at all.

You'll need SSH enabled on the router, a PIA subscription, and firmware with WireGuard in VPN Fusion: stock 3.0.0.4.388 or later, or Asuswrt-Merlin (beta, tested on 388.11 & 12). See [Prerequisites](#4-prerequisites--requirements).

`cfg-pia-wg` is the evolution of my command-line Windows/Linux app [cfg-pia-wg-cmd](https://github.com/ExponentiallyDigital/cfg-pia-wg-cmd), in a functional, modern, and streamlined UI.

---

- [1. Why use this?](#1-why-use-this)
  - [1.1. Why use WireGuard?](#11-why-use-wireguard)
- [2. Features](#2-features)
- [3. Pre-built release](#3-pre-built-release)
- [4. Prerequisites \& requirements](#4-prerequisites--requirements)
  - [4.1. Enabling prerequisites](#41-enabling-prerequisites)
    - [4.1.1. Why Download Master is needed](#411-why-download-master-is-needed)
    - [4.1.2. Preparing the USB stick](#412-preparing-the-usb-stick)
    - [4.1.3. Installing Download Master](#413-installing-download-master)
    - [4.1.4. Installing the helper binaries](#414-installing-the-helper-binaries)
  - [4.2. Router DNS settings](#42-router-dns-settings)
- [5. Using the app](#5-using-the-app)
  - [5.1. STANDALONE - Generate a PIA WireGuard configuration](#51-standalone---generate-a-pia-wireguard-configuration)
  - [5.2. MANAGE - Manage router PIA WireGuard configuration](#52-manage---manage-router-pia-wireguard-configuration)
    - [5.2.1. Which slot should carry your main VPN?](#521-which-slot-should-carry-your-main-vpn)
    - [5.2.2. DNS: where your lookups go](#522-dns-where-your-lookups-go)
  - [5.3. WATCHDOG - Watchdog WireGuard configuration](#53-watchdog---watchdog-wireguard-configuration)
    - [5.3.1. Email alerts](#531-email-alerts)
  - [5.4. DEVICES - assign, rename and disable](#54-devices---assign-rename-and-disable)
    - [5.4.1. Pinned means pinned: the fail-closed guard](#541-pinned-means-pinned-the-fail-closed-guard)
    - [5.4.2. A practical `how to`](#542-a-practical-how-to)
    - [5.4.3. The `default connection`](#543-the-default-connection)
    - [5.4.4. Phones and random MAC addresses](#544-phones-and-random-mac-addresses)
    - [5.4.5. Where the device list comes from](#545-where-the-device-list-comes-from)
    - [5.4.6. Renaming a device, and disabling its internet](#546-renaming-a-device-and-disabling-its-internet)
  - [5.5. ROUTER LOG](#55-router-log)
  - [5.6. APP LOG](#56-app-log)
  - [5.7. Settings](#57-settings)
  - [5.8. About](#58-about)
  - [5.9. EXIT - Close the app](#59-exit---close-the-app)
  - [5.10. Hamburger menu](#510-hamburger-menu)
- [6. Notes](#6-notes)
- [7. What does the app do to my router?](#7-what-does-the-app-do-to-my-router)
- [8. App permissions](#8-app-permissions)
  - [8.1. Internet (android.permission.INTERNET)](#81-internet-androidpermissioninternet)
  - [8.2. Network state (android.permission.ACCESS\_NETWORK\_STATE)](#82-network-state-androidpermissionaccess_network_state)
  - [8.3. Storage access](#83-storage-access)
    - [8.3.1. Write external storage (android.permission.WRITE\_EXTERNAL\_STORAGE)](#831-write-external-storage-androidpermissionwrite_external_storage)
    - [8.3.2. Read external storage (android.permission.READ\_EXTERNAL\_STORAGE)](#832-read-external-storage-androidpermissionread_external_storage)
  - [8.4. Billing (com.android.vending.BILLING)](#84-billing-comandroidvendingbilling)
- [9. Security](#9-security)
  - [9.1. How to check the watchdog script yourself](#91-how-to-check-the-watchdog-script-yourself)
- [10. Privacy](#10-privacy)
- [11. Bugs and feature requests](#11-bugs-and-feature-requests)
- [12. Donations](#12-donations)
- [13. Support](#13-support)
- [14. Trademark and affiliation notice](#14-trademark-and-affiliation-notice)
- [15. License](#15-license)

## 1. Why use this?

Creating a valid PIA WireGuard config by hand requires expertise in API authentication, WireGuard key generation and correctly assembling connection metadata. **cfg-pia-wg** automates that work and adds router-side **slot management** (organising WireGuard configs across the router's five WireGuard VPN client configuration slots), **self-healing** watchdog support, and **per-device VPN assignment** - sending one device out through a VPN while another goes straight to the internet - for ASUS routers running either stock or Merlin firmware.

Per-device assignment changes how the router feels day to day. Instead of deciding which slot is the default and living with it, you decide per device: a work laptop through the closest region, the games console straight to the Internet for the lowest latency it can get, TVs through non geo-blocked regions, everything else wherever you choose. A change is one tap on the device itself, nothing has to be stopped first, and you can easily and simply see afterwards where each device is actually headed to.

### 1.1. Why use WireGuard?

PIA's WireGuard configs are ephemeral and expire without warning. While OpenVPN offers long-lived configs, the protocol is CPU-intensive, which on many routers becomes a bottleneck limiting throughput.

Switching to WireGuard reduces overhead, allowing your hardware to operate closer to your actual ISP's provisioned speed. In a real-world test with a 500/50 Mbps plan (546 Mbps measured baseline), speeds jumped from a peak of 136 Mbps on OpenVPN to 499 Mbps with WireGuard on the same hardware, a 75–81% throughput sacrifice under OpenVPN:

<p align="center">
  <img src="./images/vpn-protocol-comparison.png" alt="VPN protocol comparison" width="100%">
  <br>
  VPN protocol comparison
</p>

**cfg-pia-wg** makes the switch to high-performance WireGuard effortless, no separate PC/CLI app required.

## 2. Features

- **Watchdog management:** deploy a router-side watchdog that monitors and self-heals your WireGuard VPN connection, with configurable checks, optional email alerts and access to the watchdog's log. Works on stock and Merlin; on stock it additionally needs `jq`, `mailsend-go` and DownloadMaster (see [4. Prerequisites](#4-prerequisites--requirements)).
- **Email alerts worth reading:** each alert says how long the tunnel was down, whether the kill switch held while it was, which server it reconnected to and how fast, and - when it could not reconnect - what to try and the tail of the router's own log. Sent from your own SMTP account; see [5.3.1](#531-email-alerts) for examples.
- **Per-device VPN assignment:** pick, per device, whether it leaves through a VPN tunnel or straight out to the internet, from a list of everything on your network and what each one is using right now. One tap per device, nothing to stop first, and the list says where a device's traffic really goes when its tunnel is down. Stock firmware only: Merlin does the same job through VPN Director, which this app does not drive.
- **Rename a device, or switch its internet off:** give a device a name you recognise, or take it off the internet and every VPN with one tap, a simple parental control. Both are written exactly as your router's own web interface writes them, so they show there and in the ASUS Router app too, and can be undone in either place ([5.4.6](#546-renaming-a-device-and-disabling-its-internet)).
- **A kill switch on stock firmware:** Merlin has one. Stock doesn't. So the app builds its own, out of your router's routing rules and its own firewall filter. A device pinned to a tunnel uses that tunnel or nothing: if the tunnel's config expires, the watchdog is rebuilding it, you switch it off, or the router restarts, the device goes offline rather than out in the clear. Over IPv4 only: the app doesn't support IPv6, so switch IPv6 off in the router if you rely on this. Pinned devices only; [5.4](#54-devices---assign-rename-and-disable) has the detail and the limits.
- **Standalone PIA config generation:** choose a region, enter PIA username/password and DNS values, then generate a complete `.conf` file.
- **Secure clipboard handling:** a copied config is marked sensitive, so Android 13 and later show dots rather than your private key in the clipboard preview. A visible 60-second countdown then clears the clipboard. If Android closes the app before then, the app clears its own copy the next time it starts.
- **Share/save support:** share a generated `.conf` via the Android share function and save it to a file location of your choice.
- **Router slot management:** connect to an ASUS router over SSH and inspect `wgc1`–`wgc5` slots. Create, enable, edit, disable, or delete WireGuard slot configurations directly.
- **Two remembered settings:** a successful router connect stores the router's LAN address, so you don't retype it every session, and the fingerprint of its SSH key, so the app can refuse anything pretending to be your router. Both stay in the app's private storage. Clear both with **FORGET ROUTER IP** on the SETTINGS screen. See [SECURITY.md](SECURITY.md).
- **Your router is who it says it is:** the app records your router's SSH key the first time you connect, says so in APP LOG, and refuses to send your router password to anything with a different key. If you reset or reflash the router, tap **FORGET ROUTER IP** and connect again.
- **No persistent credential storage (app):** PIA credentials and router SSH credentials are held only in the app's memory, never written to your device's storage. A generated config is the same, until you SHARE it: then Android's sharing needs a file, which the app deletes when you leave the config screen.
- **Watchdog credential storage (router):** deploying the watchdog stores the necessary PIA credentials in router NVRAM so it can monitor and self-heal independently of the app. This is a deliberate trade-off for "set and forget" operation, see [ARCHITECTURE.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md) and [SECURITY.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/SECURITY.md) for details.
- **Automated lowest-latency server selection:** measures live latency across all available servers in your selected region, ensuring that you provision with the fastest node.
- **Native task-switcher protection:** `(FLAG_SECURE)` enforces native OS-level window flags to block third-party screenshot capturing and automatically obscures the app layout view inside the Android Recent Apps / Task Switcher interface. Debug builds skip the flag to enable screenshotting while testing; every release build sets it.
- **Password manager support:** every credential field accepts autofill from your device's password manager (KeePass, Bitwarden, Google Password Manager - whatever is registered as the autofill service). PIA, router SSH and SMTP logins are kept in separate autofill groups, so your manager can hold a different entry for each and you pick between them. A "save password?" prompt is offered only after credentials have actually worked, never when you back out of a form.
- **Type it once:** log in to your router on any screen and every other screen uses that login for the rest of the session. PIA credentials and email settings you've entered for one watchdog are offered for the next.
- **Encrypted lookups for the watchdog:** it looks up PIA's servers, and your mail provider's, over encrypted DNS (DoH), so whoever can see your router's DNS can't see who you use. It sends each query to your chosen DoH server itself. If that server doesn't answer, the watchdog looks the name up the ordinary way, says so in its log, and repairs your tunnel anyway: a tunnel that stays down is worse.
- **Logs you can read at a glance:** in ROUTER LOG the app's lines are teal, the watchdog's lavender, and faults red. The watchdog's own log uses the same colours, plus teal for a rebuild that worked.
- **Input field hardening:** every text field turns off suggestions and autocorrect, and asks your keyboard not to learn from what you type. Whether a keyboard honours that is up to the keyboard.
- **Exit app safety:** all exit paths prompt for confirmation then wipe in-memory credentials and the system clipboard.
- **Professional-grade build chain:** all releases undergo automated security and quality checks with
  - [SonarQube](https://docs.sonarsource.com/sonarqube-cloud) - code quality and test coverage;
  - [OSV](https://github.com/google/osv-scanner) - open-source dependency scanning against Google's vulnerability database flagging out-of-date third-party packages;
  - [Dependabot](https://docs.github.com/code-security/dependabot) - automates updates to monitor and patch insecure or outdated dependencies;
  - [MobSF](https://github.com/MobSF/mobile-security-framework-mobsf) - performs static binary security analysis on the app's source code checking for platform-specific vulnerabilities;
  - [CodeQL](https://github.com/github/codeql-action) - static analysis of the code's structure to catch semantic gaps and injection risks;
  - Testing: as at build 466, 1353 automated tests run on every build against a line-coverage target of 80% (the Coverage badge above has today's figure), and 136 manual end-to-end tests run on a real router - 17 of them with a script on the router doing the checking, and 13 needing a build distributed by Play. Another 20 that used to be manual are now automated, and TESTING.md says which test covers each. The manual run sheet is public, so you can see exactly what's tested by hand: [TESTING.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/TESTING.md); and
  - Pinned GitHub Action hashes across [release.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/release.yml), [promote.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/promote.yml), and [quality_and_security.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/quality_and_security.yml) ensure automated builds execute with specific, verified tool versions.

---

## 3. Pre-built release

This app is available from the Google Play Store -> [cfg-pia-wg](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga).

If you want to build your own, see [BUILDING.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/BUILDING.md).

---

## 4. Prerequisites & requirements

Since build 403 (5 September 2026), this app extends support to stock ASUS firmware; [Merlin Firmware](https://www.asuswrt-merlin.net/) continues to be supported.

> [!NOTE]
> **Merlin support is in beta.** Everything since then has been built and tested on stock firmware, on a real router, end to end. Merlin shares nearly all of the code, and the automated tests cover the watchdog script on both, but the parts that differ on Merlin - its kill switch, starting and stopping a tunnel, boot persistence and uninstall - haven't had the same hand testing on a Merlin router for this release. If something doesn't behave on Merlin, please [raise an issue](https://github.com/ExponentiallyDigital/cfg-pia-wg/issues).

If you don't have an ASUS router, you can still use the `Generate PIA WireGuard configuration` function to create standalone PIA configuration files from your phone/tablet. If that's you, you can skip to [5. Using the app](#5-using-the-app).

### 4.1. Enabling prerequisites

To manage WireGuard configs and/or deploy a watchdog, you'll need to do a one time setup:

1. With the ASUS WebUi, enable the SSH server - this setting is not available in the ASUS app - go to

```text
Advanced Settings\Administration\System\Service -> "Enable SSH" (LAN only is recommended).
```

If you change the SSH port from the default 22 - the router's own web interface suggests you do - enter the router address in the app as `address:port`, for example `192.168.50.1:2222`. A plain address means port 22.

2. If you're on recent stock firmware skip to the next step. If you're using Merlin, enable the `JFFS` partition. This _should_ be enabled by default on ASUS routers running firmware version 378.50 or newer. This allows the watchdog script and settings to survive reboots/power cycling:

```text
Advanced Settings\Administration\System\Basic Config -> "Enable JFFS custom scripts and config"
```

3. Install the `jq` and `mailsend-go` helper apps.

**On Merlin there is nothing more to do - skip the rest of this step.** Merlin already ships `jq`, and it sends alert emails using tools it already has.

**On stock firmware** both are needed, and there is one more thing to do first. It needs a USB stick.

#### 4.1.1. Why Download Master is needed

On stock firmware, scheduled tasks do not survive a reboot on their own. Download Master provides the `/opt` structure the app uses to keep a watchdog running across reboots and power cycles. It is a prerequisite, not something you will use.

> [!IMPORTANT]
> **Install Download Master, then leave it alone.** The app takes over part of its installation, so Download Master itself will not operate afterwards: this app's watchdog is not compatible with it on stock firmware. Reinstalling or updating DM will stop any deployed watchdogs from surviving reboots until you redeploy them from the app. It may also drop off your router's **USB Application** page. That's expected, nothing's broken: the app has replaced its start-up script with its own, and UNINSTALL in SETTINGS puts the original back.

#### 4.1.2. Preparing the USB stick

Download Master installs onto the stick, so it needs a writable partition with a few hundred MB free.

**Format it as NTFS, a single primary partition on an MBR table.** Windows makes NTFS natively. Don't use **exFAT** as it won't work - any stick over 32 GB that Windows formatted is exFAT by default, so check rather than assume. ext4 and FAT32 also work.

Full compatibility table and the reasons behind each of those constraints: [ARCHITECTURE.md, USB storage for Download Master](ARCHITECTURE.md#usb-storage-for-download-master).

#### 4.1.3. Installing Download Master

1. Insert the prepared USB stick into the router.
2. Log in to the router's web interface.
3. Go to **USB Application**.
4. Under **Download Master**, click **Install**.

<p align="center">
  <img src="./images/dm-install-1.png" alt="Download Master install button" width="300">
  <br>
</p>

5. Select the USB storage device to install onto.

<p align="center">
  <img src="./images/dm-install-2.png" alt="Selecting the USB device" width="300">
  <br>
</p>

6. The disk is checked, and DM packages are downloaded, installed and configured.

<p align="center">
  <img src="./images/dm-install-3.png" alt="Installation in progress" width="300">
  <br>
</p>

7. It looks like this when it finishes.

<p align="center">
  <img src="./images/dm-install-4.png" alt="Installation complete" width="300">
  <br>
</p>

8. **Do not launch Download Master**, and do not click **Disable** or **Check update**.

<p align="center">
  <img src="./images/dm-install-5.png" alt="Leave Download Master alone" width="300">
  <br>
</p>

#### 4.1.4. Installing the helper binaries

**On stock firmware the app does this for you.** Open **MANAGE** or **WATCHDOG** and, if either helper is missing, the app offers to install it. It shows what it is about to download, where it goes, and the SHA-256 checksum it will verify before anything is put in place. `mailsend-go` is only needed if you want email alerts.

<br>
<p align="center">
  <img src="./images/install-helper-programs.png" alt="Install helper programs" width="300">
  <br>
  Install helper programs
</p><br>

If your router uses an architecture there is no published build for, the app says so and you can fall back to installing them by hand over SSH with [`scripts/get-bins.sh`](scripts/get-bins.sh). That script is for stock only; Merlin needs neither binary.
> [!NOTE]
> Firmware flashing (upgrading your router's software) [_may_ require redeployment](https://github-wiki-see.page/m/RMerl/asuswrt-merlin.ng/wiki/JFFS) of PIA WireGuard configs. Always test your VPN is active after applying a new firmware version

- Watchdog and tunnel verification use ICMP ping from the router's WAN and WireGuard interfaces. You shouldn't need to do anything here, but it is required.

### 4.2. Router DNS settings

It's suggested that you set up your DNS something like the below. Why? This configuration sends every DNS query from your network to Cloudflare's malware-blocking resolvers over an encrypted, authenticated channel, and hardens the router against common DNS attacks. However, chose your own adventure - pick a configuration and DNS provider that works for you, see [ROUTER-DNS.md](ROUTER-DNS.md) for alternative suggestions.

A common `foot bomb` (an AI once gave me that in a reply, I guess they 'meant to say _"land mine"_) is using your ISP's DNS. That typically defeats the whole purpose of running a VPN, maintaining your privacy and not feeding the data guzzling machine. It's not highly obvious, but click on the ASSIGN button highlighted below in RED to set your router DNS. And then select "Preset servers" toward the bottom of the screen.
<br>
<p align="center">
  <img src="./images/WAN-DNS-settings.png" alt="Router DNS Settings" width="700">
  <br>
  Router DNS Settings
</p><br>

Suggested settings:

- **Filter mode:** 1.1.1.2 and 1.0.0.2 are Cloudflare's malware-blocking resolvers. Known malware, phishing and command-and-control domains are refused at the DNS layer, so every device on the network is protected, including smart TVs, IoT gear and guests that can't run their own security software.
- **Two servers:** the primary and secondary addresses sit on separate Cloudflare ranges. If one is unreachable, lookups fail over to the other.
- **DNS-over-TLS (DoT) on port 853:** plain DNS travels unencrypted on port 53, so your ISP or anyone on the path can read it and tamper with it. DoT encrypts every query between the router and Cloudflare. Your browsing destinations stay private and your answers can't be altered in transit.
- **TLS hostname `security.cloudflare-dns.com`:** the router checks the server's certificate against this name. This proves it's talking to Cloudflare's security resolver and not an impostor that has hijacked the IP address.
- **Strict DoT profile:** if the encrypted connection can't be established or verified, the router refuses to fall back to plain DNS. Opportunistic mode would quietly downgrade to unencrypted lookups, which defeats its purpose. The trade-off is that DNS stops working if port 853 is blocked, something you'd uncover rather quickly.
- **Manual server list matches the assigned service:** in the screenshot above, use the `PURPLE` row to add, `BLUE` are configured - the DoT list repeats the same IPs and hostname chosen through the `Assign` button. The GUI selection and the underlying DoT config then match, so the router doesn't end up using unmatched resolvers.
- **Forward local domain queries to upstream DNS: No:** lookups for local hostnames (for example `nas.lan`) stay inside your network. Internal device names never leak to Cloudflare, and there are no pointless failed external lookups.
- **DNS rebind protection: Yes:** this blocks public DNS answers that resolve to private IP ranges. It stops a malicious website from using DNS rebinding to reach your router's admin page or other devices on your LAN through your browser.
- **DNSSEC support: Yes:** DNSSEC signatures on responses are checked cryptographically, so a forged or poisoned record is rejected even if it somehow reaches the router.
- **Validate unsigned DNSSEC replies: Yes:** this goes further by checking that a response claiming to be unsigned really comes from an unsigned zone. It closes the downgrade attack where an attacker strips signatures. It's the strictest option: a few badly configured domains may occasionally fail to resolve, but that's a reasonable price for integrity.
- **Prevent client auto DoH: Auto:** browsers like as Firefox and Chrome can turn on their own DNS-over-HTTPS and bypass the router completely. With Auto, the router answers the browsers' "canary" checks (lookups browsers use to decide whether to switch DoH on), so they keep using the router. That means the Cloudflare filtering and DNSSEC checks still apply to them.
- **UPnP disabled:** this isn't a DNS setting, but it complements the rest. Devices and malware can't silently open inbound ports on the router, which keeps the security posture consistent.
- **Check the IPv6 page too:** if you use IPv6 (to be encouraged, but seldom used), set its DNS to Cloudflare's matching addresses (`2606:4700:4700::1112` and `2606:4700:4700::1002`). Otherwise IPv6 lookups can go to your ISP's resolver unfiltered, bypassing everything above.

## 5. Using the app

> [!NOTE]
> - Before using `MANAGE`, `WATCHDOG` or `DEVICES` for the first time, it's recommended that you make a backup of your router configuration via the WebUI -> Advanced Settings -> Administration -> Restore/Save/Upload Setting -> Save setting.
> - This app has an unusually strict testing regime, but it's always worth having a backup at hand. Just in case.
> - Keep that backup file somewhere safe. It's a copy of your router's settings, so it holds every password and key stored there: your router login, each tunnel's WireGuard private key, and, once a watchdog is deployed, its PIA and email passwords.

The app opens with thematic function groups:

<p align="center">
  <img src="./images/00.0-main-menu.png" alt="Main menu" width="300">
  <br>
  Main menu
</p>

With two handy links: **how to use this app**, which opens this README at [4. Prerequisites & requirements](#4-prerequisites--requirements), the place to start, and **add a Play Store app review**, which opens the app's Play Store listing - reviews are most welcome, all feedback is good feedback!

### 5.1. STANDALONE - Generate a PIA WireGuard configuration

1. Tap **STANDALONE**.
2. Choose a region from the filterable region list.
3. Enter your PIA username, password, and DNS values.
4. Tap **GENERATE CONFIG** once all required fields are filled.
5. The generated WireGuard configuration is displayed in a selectable but read-only text area.

<p align="center">
  <img src="./images/01.0-standalone-config.png" alt="Standalone config generation" width="300">
  <br>
  Standalone config generation
</p>

6. Tap **COPY** to copy the config to the clipboard, or **SHARE / SAVE** to export the file via Android sharing. Copying a config to the clipboard starts a 60 second timer, displayed on screen, after which the clipboard is automatically cleared.

### 5.2. MANAGE - Manage router PIA WireGuard configuration

This enables full management of WireGuard slots.

1. Tap **MANAGE**.
2. If prompted, enter router IP:port, SSH username, and SSH password. The **address** is filled in for you if you've successfully connected previously. Your username and password are _never_ stored. Tap **CONNECT TO ROUTER**.

> [!TIP]
> To fill the credentials from your preferred password manager, tap the username or password field and choose the entry offered. Typically, suggestions are only given for **empty** fields, by default these are empty, so they should prompt, but [YMMV](https://www.merriam-webster.com/slang/ymmv) with your particular password manager. And some can be _very_ particular!

3. Select a slot and choose one of the slot actions:
<br>
<p align="center">
  <img src="./images/02.0-router-slot-management.png" alt="Router slot management" width="300">
  <br>
  Router slot management
</p><br>

- **CREATE**
  - First, select a region:
  <br>
  <p align="center">
    <img src="./images/02.01-region-selection.png" alt="Region selection" width="250">
    <br>
    Region selection
  </p><br>

  - Then enter PIA credentials and preferred DNS server addresses. On stock firmware, assigned devices use only the **first** DNS server:
  <br>
  <p align="center">
    <img src="./images/02.02-pia-creds.png" alt="Supply credentials and DNS" width="250">
    <br>
    Supply credentials and DNS
  </p><br>

  - The slot's configuration is then created and saved, but _**not**_ enabled. If you're overwriting a previous region's slot it's stopped first; if there's a problem, the prior config is restored.
  <br>
  <p align="center">
    <img src="./images/02.03-slot-created.png" alt="Slot created" width="250">
    <br>
    Slot created
  </p><br>

- **ENABLE:** activates the slot and verifies the interface by using two ping targets over the new VPN interface, not the WAN interface. If the connectivity check fails, the slot is reverted to disabled. Recommended connectivity checking addresses are
  - `8.8.8.8` or `8.8.4.4` (Google primary and secondary DNS)
  - `1.1.1.1` or `1.0.0.1` (Cloudflare primary and secondary DNS)

<p align="center">
  <img src="./images/02.04-ping-targets.png" alt="Ping targets" width="250">
  <br>
  Ping targets
</p><br>

- **EDIT:** allows updating WireGuard slot parameters and saves them back to router NVRAM. A running tunnel only picks up new settings when it restarts, so SAVE on a running slot asks first ("Saving restarts wgcN. Anything using it drops for a few seconds."), then restarts it and checks it.
<p align="center">
  <img src="./images/02.05-slot-edit.png" alt="Editing a slot" width="300">
  <br>
  Editing a slot
</p><br>

- **DISABLE:** takes the tunnel down, with confirmation. A watchdog on the slot is **paused**, not removed: left running, it would rebuild the tunnel you just stopped. Its script and settings stay on the router, so ENABLE brings the tunnel and the watchdog back together. Devices pinned to the slot have no internet until you ENABLE it again or move them, and the confirmation names them.
- **DELETE:** removes the slot configuration and its watchdog entirely: the schedule, the script on the router and the watchdog settings, so there is nothing left to ENABLE. Devices pinned to the slot are moved to the Internet, and the prompt names them before you confirm; and if the slot was the default connection, the default goes back to the Internet ([5.4.3](#543-the-default-connection)).

> [!TIP]
> Merlin firmware also offers a kill switch and inbound firewall toggle.

#### 5.2.1. Which slot should carry your main VPN?

Short version: build the VPN you use for most things on **wgc5**, and work downwards from there.

The first reason is cosmetic. The router's own web interface creates `wgc5` first, and `cfg-pia-wg` lists slots the same way - `wgc5` at the top, down to `wgc1` - so the two agree about which slot is "the first one". Yes, that does my head in too; it's inverted but it is what it is :).

The second reason isn't cosmetic, and it applies if your VPN's DNS servers are the **same** as your **router** which it uses for its **own** encrypted DNS lookups. Yes, read that twice too. Quad9 and Cloudflare are the usual overlap, because they're a sensible solution to fully encrypted DNS with extra sauce (protection from malware, ads, adult filters etc). When these addresses match, the firmware sends the router's **_own_** lookups - the ones it makes for every device that has not been assigned to a tunnel - through the slot with the lowest routing table number. The tables are `wgc1` `#9` through to `wgc5` `#5`, so the lowest table belongs to the **highest-numbered** slot. Whichever slot that is, it carries name resolution for the whole network. Bear with me, it does get easier. Read on, intrepid traveller.

Two things follow, and both are useful to know before choosing:

- **A failure there is a failure everywhere.** If that tunnel dies and nothing rebuilds it, devices that resolve through the router stop resolving names, period, not just the ones you assigned to it. That's a prime candidate for putting a watchdog on, and for giving it an email address to send you love letters, sorry, alerts.
- **Moving a region between slots has an order.** Create the new slot, move the pinned devices to it, and only then delete the old one. Deleting a slot sends its devices to **Internet**, not to your default connection, so doing it the other way round quietly drops them out of the VPN per stock firmware design. What-the, yes, your router really does do that by design, buried in the WebUI and only "visible" by stopping tunnels, unless you have `cfg-pia-wg`!

If your VPN DNS and your router DNS use _different_ addresses, regional movements aren't a "[gotcha](https://www.merriam-webster.com/dictionary/gotcha)".

#### 5.2.2. DNS: where your lookups go

> [!IMPORTANT]
> Your **default connection** decides where a device's traffic goes. It does **not** decide where that device's **DNS** goes.

Yep, for real. That's a `seldom-known` feature of ASUS stock firmware. The short version:

- **Why should I care?** While your traffic can flow through an encrypted tunnel, your DNS lookups can travel in clear text.
- **Pin a device to a slot** with `DEVICES` and its DNS follows that slot, through that slot's tunnel. Safe, secure, and private.
- **A device that's not pinned** sends its lookups to the router, and the router answers using its own DNS settings - whatever your default connection is.
- **Keep your router's DNS addresses away from your slots' DNS addresses**, unless you are choosing to share one deliberately. When a slot uses the **same** address as the **router**, the router's own lookups travel through that slot's tunnel, and if that tunnel stops answering while still looking connected, every unpinned device loses name resolution until it is rebuilt. Read that twice, it's important. Read on for the [TL;DR](https://www.merriam-webster.com/dictionary/tl;dr).

So, what can I do about it?

**Pin devices you care about.** A _pinned device's_ traffic and its lookups leave from the same place, and nothing else on the router can move them - which is likely the setup you want. Everything encrypted. By contrast, using the _default connection_, with DNS supplied by your ISP, can "leak" PIA, watchdog DNS lookups and, anything else you throw at it. This is one reason why you _don't_ want to use your ISP's DNS servers, but hey, your call. `cfg-pia-wg` has been designed specifically to reduce your foot-print/surface area, but it's up to you. Your router, your setup, and that's A-OK.

> [!TIP]
> Suggestion: use encrypted lookups with a "no log" privacy DNS service.

On stock, `cfg-pia-wg` also highlights if a slot's DNS matches the addresses your router uses for its _own_ encrypted lookups via a note under the `MANAGE > EDIT` DNS field, naming the shared addresses. Why? Sharing is a reasonable choice. `cfg-pia-wg` never changes your router's DNS settings. That's your domain, but it can impact the watchdog's ability to do its job of keeping your tunnel(s) up.

Since build 477 (30 September 2026), `cfg-pia-wg`'s watchdog resolves **both** PIA and your mail server over encrypted DNS, to an address of your choice. (Build 454 set out to do this, but the router's own `curl` quietly ignores its encrypted-DNS option, so until 477 those lookups were ordinary DNS. No public release carried it.) This keeps your VPN provider and your email provider off the wire in the clear. On your phone/tablet, `cfg-pia-wg's` lookups go through your device's resolver like any other on-device app - turn on Private DNS in your device's settings if that's important to you.

See [ROUTER-DNS.md](ROUTER-DNS.md) for all the gory details: why the router answers for unpinned devices, two worked setups with juicy flow charts, how to use a slot for parental controls, a table of common DNS services, and the routing rules underneath it all for the technically inquisitive.

Right, with all that out the way, let's get you set up with watchdogging ;).

### 5.3. WATCHDOG - Watchdog WireGuard configuration

This manages a self-healing watchdog. When your WireGuard configurations inevitably expire, they are automatically renewed and an optional email alert sent when connectivity has been restored.

1. Tap **WATCHDOG**.
2. If prompted, enter router IP, SSH username, and SSH password and tap **CONNECT TO ROUTER**.
<br>
<p align="center">
  <img src="./images/03.0-watchdog-configuration.png" alt="Watchdog configuration" width="300">
  <br>
  Watchdog configuration
</p><br>

3. Select a slot and use the watchdog actions:
   <br>
   - **CREATE/EDIT:** pick a region and a check interval, defaulting to five minutes, then tap **SAVE & DEPLOY** to deploy router-side watchdog scripts and cron jobs for the selected slot. The region starts as the slot's own, so saving an active watchdog without changing it leaves its tunnel alone. Choosing a region for a slot that already holds a configuration asks before overwriting it. Changing the region rebuilds the tunnel on the new one: it is down while that happens, and devices pinned to it have no internet until it is up. Every deploy sends an alert email when email alerts are on; if that email can't be sent, a popup says so and gives the mail server's reason, and the form stays open so you can fix the email settings.
     The form also holds:
     - **Primary ping IP** and **Secondary ping IP**, the check targets, `8.8.8.8` and `1.1.1.1` by default. A target the router can't reach gets a warning, and saves anyway.
     - **DNS**, the slot's own DNS servers. It's here as well as in MANAGE because this form can build a slot from scratch.
     - **PIA username** and **PIA password**, checked with PIA before anything on the router is touched.
     - **The watchdog's own encrypted DNS**, how the watchdog looks up PIA while it repairs a tunnel. Pick one of six resolvers (Cloudflare, the default; Google; Quad9; Control D; AdGuard; Mullvad) or "Something else" and type one or two addresses. The note under it turns amber if an address is also a slot's DNS server: the router would send the watchdog's lookups through that tunnel, the one it may be trying to repair. [ROUTER-DNS.md](ROUTER-DNS.md) explains why.
     - The email settings, below, and **TEST EMAIL**.
<br>
<p align="center">
  <img src="./images/03.01-watchdog-editing.png" alt="Configuring a watchdog" width="300">
  <br>
  Configuring a watchdog
</p><br>

   - **ENABLE:** restart the watchdog, with all settings retained.
   - **DISABLE:** stop the watchdog running whilst retaining its settings. Disabled watchdogs show a **PAUSED** badge.
   - **DELETE:** remove the watchdog and clear this slot's configuration.
   - **VIEW ROUTER WATCHDOG LOG:** review the router-side watchdog log for this specific slot, including previous logs. **REFRESH** reads it again, to see a check that has just run. **CLEAR** empties this watchdog's log. Logs are rotated at midnight retaining the current and previous logs and do not persist if the router is rebooted or a power loss occurs. That's a conscious design decision to avoid filling your non-volatile router RAM.
     Two things you'll meet reading it:
     - **The times are staggered by slot.** Each watchdog waits 15 seconds per slot below it before checking, so wgc1 checks on the minute and wgc5 60 seconds after. Several watchdogs starting in the same second upset the router's own services, so they take turns.
     - **"Router resolver OK" or "Router resolver FAILED".** Every check also asks the router's own name lookups (dnsmasq, which your unpinned devices use) whether they work, and logs the answer. It's there so you know, and is never a reason to rebuild the tunnel: a FAILED line means devices that aren't pinned can't look names up, which is a router problem, not a VPN one. ROUTER RESOLVER STATUS in SETTINGS shows the detail.
  
<p align="center">
  <img src="./images/03.02-watchdog-log.png" alt="Watchdog log" width="300">
  <br>
  Watchdog log
</p>

#### 5.3.1. Email alerts

<br>
<p align="center">
  <img src="./images/03.03-watchdog-editing.png" alt="Email alerting" width="300">
  <br>
  Email alerting
</p><br>

If you elect to `enable email alerts`, the router will send you a plain-text email whenever it rebuilds a tunnel, and if it tries and fails. Alerts come from your own SMTP account, with nothing routed through a third party. When a watchdog is saved, these settings are stored in your router's non-volatile memory and prefilled when creating another watchdog - saves typing! **No** credentials are stored on your phone/tablet, see [ARCHITECTURE.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md) and [SECURITY.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/SECURITY.md) for details.

To set up email alerting, you'll need an **`app password`**, _not_ your "normal" one. Gmail and Outlook thankfully won't accept plain text passwords. How-to links below:

- **Gmail:** <https://myaccount.google.com/apppasswords>
- **Outlook / Microsoft:** <https://account.live.com/proofs/AppPassword>

> [!NOTE]
> **Sending alerts to yourself?** Gmail files a message you send from your own address to that same address under **Sent**, not your inbox, so an alert from and to one Gmail address looks like it never arrived. Look in **All Mail**, or send to a different address.

> [!TIP]
> Having email alerting issues? See [TESTING.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/TESTING.md) for a step-by-step walkthrough together with email troubleshooting approaches.

Use the **TEST EMAIL** button, per the screenshot above, before you save the watchdog. This helps ensure that you'll reliably receive alerts. The test email uses the same type of message and sends through the same path as alerts, so a test that arrives is a strong indication that alerts will too. But hey, I'm not a postmaster :-).

Every email has the same sections: what happened, what to do about it (failures only), which router this is, and a running count of how well the watchdog is earning its keep.

**When a tunnel is rebuilt:**

```text
Subject: cfg-pia-wg alert: SUCCESS - wgc1:pia-region_name

Connectivity was lost and the tunnel has been rebuilt.

WHAT HAPPENED
Event: reconfigured successfully on attempt 2
Reconnected to: region_name408 (45.134.140.101:1337), 9 ms
Tunnel was down for: 6m 12s (last seen good 2026-09-05 14:26:41 +1000)
Kill switch: ON in the router's settings; what Merlin blocked while the tunnel was down was not checked
Interval: 5 minutes

ROUTER
Name: my-router.asuscomm.com (192.168.50.1)
Model: <your router model>, firmware <your firmware version>
Time: 2026-09-05 14:32:53 +1000
Uptime: 14:32:53 up 19:21,  load average: 2.55, 2.39, 2.36
Watchdog: wgc1:pia-region_name, deployed by cfg-pia-wg <version> build <number>

HISTORY
Since 2026-09-01 this router has recorded 4 successful and 1 failed reconfigurations.

Email alerting can be disabled in the app via WATCHDOG, CREATE/EDIT, then deselecting "Enable email alerts".

If cfg-pia-wg is useful to you, please consider submitting a review by tapping on the home screen link or via https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true

Thank you,
cfg-pia-wg by Exponentially Digital
```

**When it cannot be rebuilt** two additional sections are populated: what to try, and a tail of the router's watchdog log so you can see the attempt rather than take the summary on trust:

```text
Subject: cfg-pia-wg alert: FAILED - wgc1:pia-region_name

Connectivity was lost and the tunnel could NOT be rebuilt.

WHAT HAPPENED
Event: PIA's login service isn't answering (HTTP 504). This is at PIA's end; the watchdog will try again.
Tunnel has been down for: 41m 09s (last seen good 2026-09-05 13:58:12 +1000)
Kill switch: the app's guard is keeping TABLET, PHONE pinned to this tunnel, and off the internet until it is back
Attempt: 8 since the last success, retrying per schedule, 5 minutes

WHAT TO DO
1. Check your PIA username and password in the app, under WATCHDOG, CREATE/EDIT.
2. Open VIEW ROUTER WATCHDOG LOG in the app for the full history.
3. PIA rate-limits repeated token requests; if the code above is 403, wait 30 minutes before intervening.
4. Review your router log.
5. Is your PIA user account active?

ROUTER
Name: my-router.asuscomm.com (192.168.50.1)
Model: <your router model>, firmware <your firmware version>
Time: 2026-09-05 14:39:02 +1000
Uptime: 14:39:02 up 19:27,  load average: 1.02, 1.15, 1.09
Watchdog: wgc1:pia-region_name, deployed by cfg-pia-wg <version> build <number>

HISTORY
Since 2026-09-01 this router has recorded 4 successful and 2 failed reconfigurations.

ROUTER LOG (last 10 lines)
2026-09-05 14:34:03 Alert email sent (FAILED)
2026-09-05 14:37:00 Watchdog started for wgc1 [script <version> build <number>]
2026-09-05 14:37:00 Checking wgc1 pia-region_name connectivity
2026-09-05 14:37:12 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-05 14:37:13 WAN has internet connectivity
2026-09-05 14:37:13 Connectivity lost; reconfiguring (attempt #8) [script <version> build <number>]
2026-09-05 14:37:13 Using cached CA cert
2026-09-05 14:37:13 Name lookups encrypted via security.cloudflare-dns.com (1.1.1.2)
2026-09-05 14:37:14 Requesting PIA token for user p123456789
2026-09-05 14:38:15 ERROR: PIA's login service isn't answering (HTTP 504). This is at PIA's end; the watchdog will try again.

Email alerting can be disabled in the app via WATCHDOG, CREATE/EDIT, then deselecting "Enable email alerts".

If cfg-pia-wg is useful to you, please consider submitting a review by tapping on the home screen link or via https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true

Thank you,
cfg-pia-wg by Exponentially Digital
```

How to interpret these emails:

- **Kill switch** answers the question that most often matters when a tunnel drops: did anything leave the router unprotected, in the raw, so to speak? The line reports the state your router was actually in, not a generic warning.
  - On **Merlin**, which has a kill switch: on, or available but not enabled.
  - On **stock**, which has none, it reports the app's own guard ([5.4.1](#541-pinned-means-pinned-the-fail-closed-guard)): the devices pinned to that tunnel it kept off the internet, by the names DEVICES shows, or that nothing is pinned there. If part of the guard is missing, say after a reboot before the app or a watchdog has put it back, it says so and tells you how to fix it.
- **Interval** is read from the router, so it can never claim a schedule that is not actually running.
- **Since `date`** counts every re-configuration this router has made, across all slots, from the day the app first configured itself.
- The router log excerpt includes your **PIA username** (never the password, and never the token). The email travels through your own mail provider, but bear that in mind before forwarding it on.

> [!NOTE]
> **An alert can only be sent if the router can still reach your chosen mail server.** If it cannot because its internet connection is down, or it cannot look up your mail server's name at that moment, then that alert never leaves the router. The attempt is always recorded in the router-side watchdog log, and the next email that does get through says how many were missed.

The first email you receive will be the deployment itself - `Event: watchdog deployed` - sent even though there was nothing to fix. That is deliberate: it confirms the whole alerting path works, at the moment you set it up rather than months later during an outage.

What about rate limiting? No one wants to wake up to an inbox full of alerts! `cfg-pia-wg` employs an intelligent rate limit with an exponential backoff between retries capped at 90 minutes per send interval. WAN down? Email alerts are held over until WAN connectivity is regained, and on resumption you get an alert per interval, again capped. See ARCHITECTURE.md's section on [email alerting](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md#email-alerting) and [the backoff process](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md#when-the-script-runs-and-when-it-does-nothing) for full details.

### 5.4. DEVICES - assign, rename and disable

**Stock firmware only.** Merlin does the same job through VPN Director, which this app does not drive.

Normally every device on your network follows the router's default connection. This capability lets you send particular devices through a particular VPN tunnel and leave everything else alone - a games console straight out to the internet, a laptop through Melbourne, everything else through Perth.

One simple, easy to use interface and your laptop can be globetrotting to anywhere in the world. Practical considerations do apply though as many organisations are actively enforcing geo-blocking via registered IP address blocks. That's never been the purpose of this app. It exists to do one thing extremely well. And that's stopping nominated devices from going out to the Internet in the clear, unprotected and naked, swinging in the breeze so to speak.

DEVICES gives you one list of all your devices and lets you decide which tunnel they should be "pinned" to. It also allows you, as we read earlier (you did read that bit didn't you :)?), to set the default connection simply, quickly, easily and have confidence that devices pinned to that will go where they're intended.

**What does it change on my router?** Its routing rules, the short list your router reads to decide which way each device's traffic goes, and one list in its firewall. Your router already writes one rule per pinned device, and the app doesn't replace it. It does three things on top. It deletes the stale rules your router leaves behind when you move a device, because the old one wins and your device would quietly keep using the tunnel you moved it off. It adds rules of its own for every pinned device, which are what keep that device offline, rather than out in the open, while its tunnel is down. And it lists every pinned device in your router's Network Services Filter (Firewall, Network Services Filter), so the router itself keeps it off your internet connection from the moment it starts ([5.4.1](#541-pinned-means-pinned-the-fail-closed-guard) says why). Only the app's own entries: anything you've put there yourself is left alone. Nothing else is touched: not your default connection's rules, not your router's own DNS, not your other devices. For the technically inquisitive, [ARCHITECTURE](ARCHITECTURE.md#every-routing-rule-the-app-touches) lists every rule, what the app does with each, and the hardware tests behind them.

**What it doesn't cover.** Devices that follow the default connection rather than being pinned: pin the ones you care about. Pings, for a few seconds while your router starts, unless you turn on **SECURE STARTUP** in SETTINGS ([5.4.1](#541-pinned-means-pinned-the-fail-closed-guard)). And IPv6, which isn't supported by this app.

<br>
<p align="center">
  <img src="./images/04.0-device-assignment.png" alt="Device assignment" width="300">
  <br>
  Device assignment
</p><br>

#### 5.4.1. Pinned means pinned: the fail-closed guard

If one thing sets this app apart, it's this.

**The problem.** A VPN protects a device only while its tunnel is up, and tunnels go down. A PIA configuration expires, the watchdog rebuilds one, you switch one off, the router restarts. So what happens to a device's traffic in that moment? On Merlin firmware, its kill switch blocks it. Stock ASUS firmware has no kill switch. Measured on a stock router, a device pinned to a tunnel slipped out while the tunnel was being rebuilt, for as long as the tunnel was switched off, and during a restart until the tunnels came back. Sometimes through another tunnel, sometimes straight out to the Internet in the clear. No warning, and nothing on the device to tell you.

**What the app does about it.** For every device you pin to a tunnel, the app adds a guard on the router: two small routing rules that say "this device goes through its tunnel, or nowhere". While the tunnel is up, nothing changes. When it goes down, for whatever reason, the device has no internet until the tunnel is back or you move it. Not even a second of leak. That's what fail closed means: when something fails, the door shuts rather than swinging open.

**And while the router restarts?** Those rules live in your router's memory, so a restart wipes them, and stock firmware doesn't let the app put them back until a few seconds after your internet connection is up. Measured on a stock router: a pinned device reached the internet directly for 3 to 6 seconds on four restarts out of six. The same gap opened for up to a minute whenever the router's DNS servers changed. So the guard has a second layer, and it's your router's own: the Network Services Filter. The app lists each pinned device there, and your router applies that list itself, before its internet connection comes up, blocking the device from your internet connection and only from that. Its tunnel still works. Measured with it: no leak across three restarts in a row, nor through the DNS change, nor with the device's rules taken away on purpose.

It holds everything except pings. Your router can only block pings for every device at once, not one at a time, so that part is your choice: **SECURE STARTUP**, in SETTINGS, off unless you turn it on. With it on, devices that aren't on a VPN can never ping anything on the internet. Devices on a VPN still ping through their tunnels, and the router's own checks aren't affected. One catch: a ping that's already running when you turn it on keeps getting replies, because the router lets an exchange it's already tracking carry on. Stop it, wait 30 seconds, and start it again.

The app won't use the filter if doing so would change something of yours: if you run it as an allow list (where listing a device would let it out), if you've switched it off with entries of your own in it, or if the router's firewall is off. It says so in APP LOG, and the guard works as before. If you give the filter a timetable, the app says that too: the filter only holds at the times you've set.

**Do I need to do anything?** No. Pin a device and the guard comes with it. The app keeps it in place for you: every time you APPLY an assignment, before a DISABLE, on every watchdog check, and when the router restarts. And if you pin a device, or move one to another tunnel, in the router's own web interface rather than in this app? Once it's done, the guard catches it, as long as a watchdog is running: each watchdog check brings the guard up to date, so the device is covered within one check interval. **But while you're doing it, it isn't covered.** The web interface won't move a device while its tunnels are running, so you stop them, move it, apply, and start them again, and part way through that the router has the device pinned to nothing at all. Its traffic can go straight out to the Internet until the tunnels are back and the guard catches up. Move devices in DEVICES instead: the app moves them without stopping anything, and the guard goes with them.

**How do I know it's working?**

- DISABLE on a slot names every device pinned to it, in amber, and says they'll have no internet until you ENABLE it again or move them. Nothing happens until you confirm.
- ROUTER LOG shows "Fail-closed guard on for" the device, by name and address, when the guard is added, and "Fail-closed guard removed for" it when the device no longer needs one. "Network Services Filter: N pinned device(s) kept off the internet connection outside their tunnel" says the second layer changed, and your router's Firewall, Network Services Filter page lists each pinned device twice, TCP and UDP.
- A watchdog's alert email has a **Kill switch** line naming the devices the guard kept off the internet while the tunnel was down, for example "the app's guard kept TABLET pinned to this tunnel, and off the internet while this tunnel was down". If part of the guard is missing, the same line says so, and how to put it back.

<br>
<p align="center">
  <img src="./images/04.03-assign-stopped-tunnel.png" alt="Choosing a stopped tunnel for a device" width="300">
  <img src="./images/04.031-assign-stopped-tunnel.png" alt="APPLY warns that the device will have no internet" width="300">
  <br>
  Pinning TABLET to wgc3, which isn't running: APPLY says it will have no internet until wgc3 is enabled, rather than letting it out another way
</p><br>

<br>
<p align="center">
  <img src="./images/05.02-router-log-guard.png" alt="ROUTER LOG with the fail-closed guard" width="300">
  <br>
  TABLET and LAPTOP pinned to wgc1 and guarded, then the watchdog rebuilding wgc1 overnight
</p><br>

And the email that rebuild sent. Alert emails are plain text:

```text
Subject: cfg-pia-wg alert: SUCCESS - wgc1:pia-nz

Connectivity was lost and the tunnel has been rebuilt.

WHAT HAPPENED
Event: reconfigured successfully on attempt 1
Reconnected to: auckland411 (192.0.2.52:1337), 29 ms
Tunnel was down for: 5m 29s (last seen good 2026-09-30 03:35:00 +1000)
Kill switch: the app's guard kept TABLET, LAPTOP pinned to this tunnel, and off the internet while this tunnel was down
Interval: 5 minutes

ROUTER
Name: my-router.asuscomm.com (192.168.1.1)
Model: <your router model>, firmware <your firmware version>
Time: 2026-09-30 03:40:33 +1000
Uptime: 03:40:33 up 6 days, 11:02,  load average: 0.41, 0.52, 0.49
Watchdog: wgc1:pia-nz, deployed by cfg-pia-wg v0.8.102 build 472

HISTORY
Since 2026-09-26 this router has recorded 3 successful and 4 failed reconfigurations.

Email alerting can be disabled in the app via WATCHDOG, CREATE/EDIT, then deselecting "Enable email alerts".

If cfg-pia-wg is useful to you, please consider submitting a review by tapping on the home screen link or via https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true

Thank you,
cfg-pia-wg by Exponentially Digital
```

**What it doesn't cover.**

- Devices that follow the default connection rather than being pinned. Pin the ones you care about.
- Pings, for a few seconds while your router starts, unless you turn on **SECURE STARTUP** in SETTINGS.
- IPv6 is not supported by this feature.
- A device while you move it in the router's web interface, as above. Use DEVICES.
- A phone's mobile data. A phone whose Wi-Fi has no internet usually falls back to its mobile network, so a phone the guard is keeping off the internet isn't offline: it's out through your carrier, with no VPN. If that matters, turn off mobile data on the phone, or turn off the phone's own setting that switches to mobile data when Wi-Fi has no internet.

> [!TIP] The guard's promise is no internet rather than unprotected internet. A tunnel that stays down keeps its devices offline. Getting the tunnel back is the watchdog's job ([5.3](#53-watchdog---watchdog-wireguard-configuration)).

For the technically inquisitive, [ARCHITECTURE 6.8.10](ARCHITECTURE.md#what-happens-when-the-tunnel-drops) has the measurements, the two rules, and every point at which the app puts them in place.

#### 5.4.2. A practical `how to`

1. Tap **DEVICES** on the main menu, or via the hamburger menu.
2. In-session credentials are cached, so if asked, enter your SSH username and password, then tap **CONNECT TO ROUTER**.
3. Every device the router's seen since its birth is listed, plus what network that device is set to use. Pull the list down to read it again; changes you haven't applied yet are kept. Which tunnels are running is also checked quietly every 15 seconds while the screen is open, and again when you come back to it, so the notes under each device stay current after a tunnel stops or a router restarts.
4. Tap a device to pick **Internet** or one of your WireGuard slots, or **Disabled** to take it off the internet altogether. Offline devices are listed too, greyed, at the bottom.
5. Tap a device's **name** to change it: type the new one and press Enter. It turns amber until you APPLY.
6. **APPLY** shows every change as `from -> to` and asks before touching anything. **DISCARD CHANGES** puts them all back. If a tunnel you are moving devices onto is not running, or its server has not answered for a few minutes, APPLY says so before you confirm.

<br>
<p align="center">
  <img src="./images/04.02-assign-device.png" alt="Device assignment detail" width="300">
  <br>
  Assigning a device
</p><br>

Assignment is as simple as tapping on a device in the previous menu, then deciding which of the five slots you want that device to use on its globetrotting journey. Select one, then APPLY CHANGES. Easy. What about those "other" three choices? They're special cases as we'll read below.  

- `Internet`, as its name implies is simply that. No tunnel, and as much privacy as your country gives you. Which isn't much sometimes :/.
- What about that `Default - pia-some_region` one that sits at the top of the screen? It handles every device you've *not* assigned to a specific slot.
- `Disabled`, in red at the bottom, takes the device off the internet and every VPN, and leaves it on your home network. More in [5.4.6](#546-renaming-a-device-and-disabling-its-internet).

#### 5.4.3. The `default connection`

<br>
<p align="center">
  <img src="./images/04.01-default-connection.png" alt="Default connection picker" width="300">
  <br>
  Default connection
</p><br>

Two things you should know about the `default connection`:

> [!IMPORTANT]
> - Changing it restarts **every** tunnel on the router, so anything using a VPN drops for up to a minute. Assigning _individual_ devices restarts nothing.
> - **Pinned means pinned.** A pinned device uses its tunnel or nothing. If that tunnel's config expires, the watchdog is rebuilding it, or you switch it off, the device waits with no internet rather than wandering out through the default connection. Devices that only _follow_ the default get no such promise, so pin the ones you care about. Over IPv4: the app doesn't support IPv6. Since build 480 this includes the few addresses your router's firmware sends straight out your internet connection from a tunnel's table, such as the router's own DNS servers: a pinned device reaches them through its tunnel, or not at all.

And six things that can catch you out:

1. **A device the router has never seen can't be assigned.** Connect it to your network and get it to exchange some traffic through your router, it'll then show up in the device list. There is a time delay, and it depends on things outside our control. But it will show up. Hopefully expeditiously, but sometimes in its own sweet time. Prodding it by talking through your router usually goads it into submission.
2. **Assigning a device pins its address permanently.** And that's the big one. It stops an assignment drifting onto a different device later on. A pinned device stays behind when you unassign - the router never removes it, and neither does this app.
3. **A randomised MAC address breaks assignment silently.** Those devices are tagged in the list with `random MAC`. Many phones randomise their MAC addresses per network by default, and the assignment stops working the next time the address rotates, with nothing to tell you. [5.4.4](#544-phones-and-random-mac-addresses) gives you the settings to change, per phone architecture.
4. **Switching a tunnel OFF takes its pinned devices offline.** They keep their assignment and have no internet until you switch it back ON or move them, and the app names them before you confirm. Deleting a slot is different: the app moves its devices to the Internet, tells you which ones, and puts the default connection back to Internet if that tunnel was it.
5. **Guest network devices never appear.** Typically they can't reach your LAN, so putting one on a VPN is a different use case.
6. **A device assigned to a VPN uses only that VPN's first DNS server.** The router sends every lookup from it to the first DNS server address listed in your slot config and never tries the second. The router's own lookups can use both. For real. That's by design. If the first stops answering through that tunnel, then devices typically reach IP addresses but not names. You can change the first server with MANAGE, then EDIT.

#### 5.4.4. Phones and random MAC addresses

An assignment is a pin to a MAC address, so a device that changes its MAC quietly stops being the device you assigned. It does not lose its connection: it leaves by the default connection instead, which is possibly something you'd not intended. This is unannounced, and why the main DEVICES screen tags devices like that with `random MAC`.

Many mobile phones do this by default with a per network setting, turning it off for a specific Wi-Fi network is straightforward:

- **iOS 27:** Settings > Wi-Fi > your network (the ⓘ) > Private Wi-Fi Address > off.
- **Android (Pixel):** Settings > Network & internet > Internet > your network (the gear) > Privacy > **Use device MAC**.

Two more ways an Android phone can rotate its address, worth knowing if one keeps coming back:

- Developer options has **Wi-Fi non-persistent MAC randomisation**. With it on, the address changes at a reboot or when the DHCP lease expires, not just when you join a new network.
- An app can ask for a randomised address through the network suggestion API, and an open network with no captive portal gets one, without Developer options even getting into the picture.

Laptops and desktops usually retain one address per adapter. If in doubt, the tag in the device list is your [Rosetta Stone](https://en.wikipedia.org/wiki/Rosetta_Stone).

#### 5.4.5. Where the device list comes from

The list is the router's own view of your network, not a scan this app runs. That has two consequences worth expecting rather than reporting:

- **Online and offline match the router's web interface, to the second.** The app reads the same source the web interface does. So when the two seem wrong, they are wrong together, and the most common case runs the other way to what you might expect: a device in standby can read online long after you switched it off. A games console that keeps its network up in standby stayed online in the web interface for almost an hour after it was powered off.
- **A device you no longer own can linger.** The router holds an entry until its DHCP lease expires, and a phone that rotates its address (see [5.4.4](#544-phones-and-random-mac-addresses)) leaves one behind every time it does. A "ghost" with a name you vaguely recognise is usually the same phone under a new random MAC.

#### 5.4.6. Renaming a device, and disabling its internet

**Renaming.** Tap a device's name, type a new one and press Enter. Names can be up to 32 characters and anything but `<` and `>`, which is what your router's own web interface allows. Leave it empty and the device goes back to the name your router detected for it. It's the same name the web interface and the ASUS Router app show, so a rename here shows up there too, and the other way round.

**Disabling.** Pick **Disabled** in a device's list and APPLY, and it has no internet and no VPN until you pick something else. It still reaches the rest of your home network: a disabled tablet can't load a web page, but can still open the NAS. It's the one-tap version of a parental control.

**Does the app invent its own blocking?** No. It uses your router's own Parental Controls, the "block" setting under Time Scheduling, and does exactly what the web interface does. So you'll see the device listed there, and you can switch it back on there instead of in the app. A block also survives your router restarting.

**What happens to its VPN?** Nothing. It keeps its assignment underneath, so picking **Internet**, a slot or `default` again brings it straight back to wherever you choose. The fail-closed guard isn't touched either.

Three things to know:

- **Time Scheduling has one on/off switch for every device in it.** If you've set up schedules there and left the switch off, disabling a device here turns it on, and your schedules with it. When that would happen, APPLY names them and asks first.
- **Disabling follows the device's MAC address.** A phone that randomises its MAC ([5.4.4](#544-phones-and-random-mac-addresses)) gets its internet back when its address changes, just as it slips out of a pin. APPLY warns you when a device you're disabling looks like one.
- **Disabling takes a device off your home internet, not off every internet.** A phone with mobile data falls back to it when its Wi-Fi has no internet, so a disabled phone carries on through your carrier. Turn its mobile data off too if you mean it.

### 5.5. ROUTER LOG

Your ASUS router's log, because we all love a great read. Seriously though, I've found my eye balls burning having hunted through the minuscule WebUI log panel. This one's colour coded, just like the APP LOG below. To make it really easy to see the stuff that you need to know about. Watchdog entries in lavender, errors in red, cfg-pia-wg in-app device operations in the app's signature teal. Everything else in fashionable white. Selectable or copy everything that's been pulled down to your phone/tablet over to your device's system clipboard. On scrolling, more of the router log is loaded as far back as it goes. And it does go on, and on, and on. **REFRESH** reads the router again for anything newer. There is no CLEAR here: the log is the router's, not the app's.
<br>
<p align="center">
  <img src="./images/05.01-router-log.png" alt="Router log" width="300">
  <br>
  Router log
</p><br>

### 5.6. APP LOG

`cfg-pia-wg` extensively logs everything it does. The author is a big fan of "observability" - being able to see what's been happening. Entries are colour coded to make it easy to see at a glance what's been going on. Within any of the "log" type views (APP / ROUTER / WATCHDOG) you can select text and copy it to the system clipboard, or **COPY** to grab everything. The APP LOG and the watchdog log can be zapped with **CLEAR**. ROUTER LOG and the watchdog log have **REFRESH**, to read the router again.
<br>
<p align="center">
  <img src="./images/06.0-app-log.png" alt="App log" width="300">
  <br>
  App log
</p><br>

### 5.7. Settings

All those things that you won't need until you do need them, and all in one place.

<p align="center">
  <img src="./images/06.01-settings.png" alt="Settings" width="300">
  <br>
  Settings
</p>

  - **REBOOT ROUTER** - surprisingly, this does precisely what it claims. It'll restart your router, after seeking confirmation. With a countdown.
  <p align="center">
  <img src="./images/06.02-reboot-countdown.png" alt="Reboot router" width="300">
  <br>
  Reboot router
</p><br>

  - **ROUTER RESOLVER STATUS** - is your router answering name lookups? It asks, there and then, through both of the router's own resolvers: dnsmasq, and stubby when DNS-over-TLS is on. You see every address that came back and how long it took, and if something didn't answer, what that means for your network. Below that are the files that decide how a lookup travels, each with when the router last wrote that configuration, and the DNS settings they're built from. All on-screen text is selectable, and COPY takes a copy and stores it on the system clipboard. **REFRESH** asks the router again, for example after you have changed a DNS setting in the web interface. `dnsmasq.conf` lists every reserved device's MAC and address, so review it before you share a copy. Informational read-only, no changes are made, do that in the WebUI or SSH etc. A wealth of detailed information is provided, not for the faint of heart!
  - **ROUTER DNS ROUTING** - where does each lookup actually go? Your devices', the router's own and each watchdog's, one line each, with one tag saying whether it goes through a tunnel or straight out to the Internet, and another saying whether anyone along the way can read it. COPY and REFRESH work as they do in ROUTER RESOLVER STATUS. Raw routing rules are at the bottom, for the technically inquisitive, and [ROUTER-DNS.md](ROUTER-DNS.md) explains why any of this matters. Again, informational read-only, no changes are made, do that in the WebUI or SSH etc. There's a _lot_ of information shown in here; helpful for troubleshooting and knowing precisely what goes where, and why.

<br>
<p align="center">
  <img src="./images/06.03-router-resolver-status.png" alt="ROUTER RESOLVER STATUS, the live check" width="250">
  <img src="./images/06.04-router-resolver-files.png" alt="ROUTER RESOLVER STATUS, the files and settings" width="250">
  <img src="./images/06.05-router-dns-routing.png" alt="ROUTER DNS ROUTING" width="250">
  <br>
  ROUTER RESOLVER STATUS, its files and settings further down, and ROUTER DNS ROUTING
</p><br>

  - **FORGET ROUTER IP** - removes the remembered router address and its SSH key fingerprint, the _**only**_ data retained on your device. No SSH credentials, no usernames, no PIA password, no tracking, no advertising ID, no ad cache, no in-app user journeys. Zip. Zilch. Nada.
  - **REMOVE CACHED PIA CERT** - deletes the cached PIA certificate from the router; the watchdog fetches a fresh one on its next run. Why? Just in case. The "Irish" approach - to be sure, to be sure. Try doing an Irish accent via a keyboard. Not easy. But why? In case it ever expires/gets updated by PIA, you'll have a way to get a fresh one straight from their official GitHub repo when you run any operation that authenticates with PIA's servers.
  - **MAX ACTIVE VPNS** - allows you to run more than two concurrent VPN clients on your router. Absolutely unsupported. You did read the license agreement didn't you? If not that's in ABOUT, because we all love reading legal documents.
  - **SECURE STARTUP** - closes the last gap in pinning on stock firmware. For a few seconds while your router starts, or up to a minute if its DNS servers ever change, devices on a VPN can ping the internet directly, which shows your real internet address to whatever they ping. Your router can only block pings for every device at once, so turning this on means devices that aren't on a VPN can never ping anything on the internet, which makes troubleshooting harder. Off by default, and for most people it should stay that way. It asks before it changes anything, and the whole story is in [5.4.1](#541-pinned-means-pinned-the-fail-closed-guard). Stock only: Merlin's own kill switch already covers it.
  - **RESTORE PURCHASE** - resurrects your Google Play Store entitlement for your one-off, lifetime purchase of `pia-cfg-wg`, you did buy a copy didn't you? If nothing matches, based on your device's current Play Store logged in account, you'll be told too.
  - **UNINSTALL FEATURES DEPLOYED TO ROUTER** - completely removes any watchdogs, their helper apps, and all app configuration deployed to your router; configured WireGuard VPNs are retained. See [What does the app do to my router?](#7-what-does-the-app-do-to-my-router). It asks twice. The "Irish" approach, alive and well. Everything really is removed, nothing's left behind, no stray filaments to clog up your device's storage. That's good software practice, I wish more folks did that.

### 5.8. About

All the details of what version you have, the provenance of who built it, and a bunch of stuff that geeks love, me included.
<br>
<p align="center">
  <img src="./images/07.01-about.png" alt="About" width="300">
  <br>
  About
</p><br>

- **Router firmware** - whether the router runs stock or Merlin firmware, and its version.
- **License status** - `licensed` when the one-off purchase is entitled per the currently logged in Google account (absolutely not something I have access to, track, or want to know),`unlicenced`, or `homegrown` for a self-built copy (go you, gratz!).
- **"Value"** history - counted across every slot since the first watchdog was deployed to this router.

- **COPY BUILD INFO** - copies the build info block as plain text, for pasting into a bug report or framing.
- **CREATE GITHUB ISSUE** - opens a new issue in the cfg-pia-wg repo via your browser, with pre-filled build and device information.
- **Open source licenses** - the full licence text for every third-party component. Lots of reading material!

<br>
<p align="center">
  <img src="./images/07.02-about-update-watchdog.png" alt="Update your watchdog script(s)" width="300">
  <br>
  Easily update your deployed watchdog script(s),
</p><br>

- **Update watchdog version** - if your on-router watchdog version is older than the current release, simply upgrade by tapping here. Button only appears if a version mismatch is detected.

### 5.9. EXIT - Close the app

**EXIT** prompts for confirmation before closing the app, wipes _**all**_ volatile session data, and clears the system clipboard.

### 5.10. Hamburger menu

You can quickly jump between functions via the hamburger menu, always shown in the <span style="color: green; font-weight: bold;">top left corner</span> of each screen:

<p align="center">
  <img src="./images/99.01-hamburger-off-main.png" alt="Hamburger shortcut" width="300">
<br>
Hamburger shortcut
</p>
<br>

This is particularly useful for looking through the application's log during operations without losing your place, simply use your device's back button afterwards and you're back to where you came from. Back-to-front?

<p align="center">
  <img src="./images/99.02-hamburger-menu.png" alt="Hamburger menu" width="300">
  <br>
  Hamburger Menu
</p>

---

## 6. Notes

- **Pre-shared keys** - PIA WireGuard does not use pre-shared keys. When pushing a config to the router, this field is always set to empty unless a push fails, then its original value is restored.
- **Time-to-live constraints** - PIA WireGuard configs expire without warning per PIA's token handling, requiring you to regenerate a config file periodically (which is why this app exists!).
- **Turn OFF battery optimisation** - for `cfg-pia-wg` otherwise Android may freeze the moment you switch away, and any work it was doing on your router will likely stop mid-action - an SSH session dropped during a watchdog deployment, an alert email abandoned halfway through. Nothing is damaged, but it fails for a reason you cannot see. On most phones: **Settings -> Apps -> cfg-pia-wg -> Battery -> Unrestricted**. Worth doing before you deploy your first watchdog.
- **Extra logins in the router's log are normal** - the router aggressively expires idle SSH sessions - well inside a session spent reading a screen and deciding what to do - so the app reconnects when it finds the connection's expired, and its next action carries on as though nothing happened. What you see afterwards is several `dropbear` logins from your phone for one sitting. That is the app picking the phone back up, not someone else picking the lock.
- **Key safety** - generated configs contain private encryption keys. Treat them like passwords and manage them securely.
- **When PIA's login service is down** - every new configuration starts with a login to PIA, and if that service stops answering while PIA's own apps keep working, the app gives it 20 seconds, then says "PIA's login service isn't answering ... This is at PIA's end, not the app or your router; try again later.". A watchdog that needs to rebuild a tunnel during an outage can't, so its failure email says the same thing, and it keeps trying on its schedule until the login service is available. Tunnels that are already up keep working meanwhile.
- **PIA maintenance** - PIA occasionally take regions offline for maintenance so you might be expecting to have an exit node in say pia-region_one, but online tools may show you as exiting from pia-region_two.
- **Check your VPN is working** - with services like [PIA what is my ip](https://www.privateinternetaccess.com/what-is-my-ip), [ipaddress.my](https://ipaddress.my/?lang=en_US), [2ip.io](https://2ip.io), and [showmyip.com](https://www.showmyip.com). However, these sites may cache your location in the browser and they sometimes return a stale exit region if used multiple times. To be absolutely sure, close your browser rather than just refreshing the page.
- **Watchdog shortcut** - if you deploy a _watchdog_ on an empty slot, that will also create the config for that slot in one step.
- **"Applying - do not leave this screen."** - while MANAGE, WATCHDOG or DEVICES is changing your router, it says so, and the back button does nothing until it has finished. Leaving part way through could leave a slot half-changed. A deploy can take a minute.
- **Change things in one place at a time** - the router's web interface writes the whole VPN list back when you press **Apply all settings**, using the copy it loaded when the page was opened - so a change made in this app can be overwritten by a web page that was open before you made it. If you use both, finish and apply in one before switching to the other, and reload the web page afterwards.
- **Maximum VPN count** - ASUS limits you to two concurrent VPNs on stock firmware, and the app keeps to whatever limit your router is set to. SETTINGS -> MAX ACTIVE VPNS raises it to as many as 5, which ASUS doesn't support ([5.7](#57-settings)). On Merlin, there is no VPN limit.
<br>

> [!NOTE]
> When manually adding a VPN via the router's web GUI, the watchdog function requires the VPN description match the PIA region name exactly eg `aus_melbourne`. If you use the watchdog function and manually set the slot description to something other than "pia-region_name", then the watchdog will fail to identify what region it should use when a reconfigure event occurs.
> 
<br>

> [!WARNING]
> If you sell or give away your router, clear it before it leaves your hands. The watchdog stores your PIA and SMTP passwords in NVRAM in plain text, and a router handed over as-is hands those over with it.
>
> **The way to do that is in the app: SETTINGS -> UNINSTALL FEATURES DEPLOYED TO ROUTER.** It removes every setting the app wrote, the watchdog schedules, the fail-closed guard and its entries in the Network Services Filter, the scripts and the whole `/jffs/cfg-pia-wg` folder, and puts back the two boot scripts it replaced. Then delete your VPN slots from the Manage screen, which is what removes the tunnels themselves. If you would rather check by hand, `scripts/showall.sh` prints everything that is stored and `scripts/clearall.sh` removes it; both are in the [GitHub repo](https://github.com/ExponentiallyDigital/cfg-pia-wg).
>
> **A factory reset does clear them.** Measured 2026-09-07 on stock firmware (RT-ABCD): marker values were written to NVRAM and committed, and neither the WebUI factory-default restore nor the WPS-button hard reset left any of them behind - including one shaped like `cfg_pia_wg_password` and one shaped like `wgcN_wd_smtp_pass`. Earlier releases of this page claimed the opposite; that claim was never tested and was wrong. Merlin has not been tested, so if you are on Merlin, use the scripts above rather than relying on the reset.

---

## 7. What does the app do to my router?

A fair question - anything that talks to your router on your behalf deserves scrutiny. Here is the whole list.

**When you manage a slot**, it writes that slot's WireGuard settings into the router's NVRAM, and restarts that one tunnel. Nothing else is touched, and nothing happens at all until you press a button.

**When you deploy a watchdog**, it also writes:

- a small shell script per watched slot, in a folder of its own on the router
- two scheduled entries per slot - the check itself, and a nightly rotate of that slot's log
- the watchdog's settings in NVRAM, **including your PIA and SMTP passwords in plain text**, because the router has to be able to re-authenticate with PIA while you are asleep
- on stock firmware only, the two helper programs from section 4, into the same folder
- enough to make those schedules survive a reboot: on Merlin, two lines in the router's own startup script; on stock, which has no equivalent, the startup area that Download Master provides. **Anything it replaces is kept beside the original and put back on uninstall.**

**When you pin a device in DEVICES** (stock only), it writes the pin itself, as the router's web interface would, and the fail-closed guard ([5.4.1](#541-pinned-means-pinned-the-fail-closed-guard)):

- routing rules at priorities 88 to 91 for each pinned device, which live in the router's memory and are put back by the guard script every minute, and at boot
- an entry per pinned device in the router's Network Services Filter, for TCP and UDP, and the filter switched on if it was off and empty. Only the app's own entries are ever changed, and the app remembers which they are
- if you turn on **SECURE STARTUP** in SETTINGS, ICMP echo requests are added to that filter's ICMP setting, for every device

**What it never does.** No firmware is modified. No packages are installed beyond the two helpers. No ports are opened. None of your traffic is routed anywhere by the app, and none of it goes to us - there is no server on our side to send it to.

**You can take it all off again.** The **SETTINGS** screen has **UNINSTALL FEATURES DEPLOYED TO ROUTER**, that removes the scripts, the schedules, the app's NVRAM settings and the folder, takes its entries out of the Network Services Filter, and restores the startup files it replaced. It deliberately leaves your **VPN slots and tunnels alone** - those are yours, and DELETE on the Manage screen is what removes them. Device assignments and the default connection are left in place for the same reason. That does mean devices pinned to a tunnel keep their pin but lose the fail-closed guard: whenever their tunnel is down, they reach the internet through the default connection. UNINSTALL says so before it starts.

**And you can read the script before you trust it** - see [9.1. How to check the watchdog script yourself](#91-how-to-check-the-watchdog-script-yourself).

Full technical detail, including a flow chart of user interactions and diagrams of network calls and traffic flows: [ARCHITECTURE.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md).

---

## 8. App permissions

In summary, the app requires only the following:

- Have full network access
- View network connections
- Google Play billing service
- Google Play license check

### 8.1. Internet (android.permission.INTERNET)

Required to:

- authenticate with Private Internet Access (PIA)
- retrieve VPN server information
- generate WireGuard configuration profiles
- perform latency and connectivity tests

No user traffic is routed through this application. The app communicates only with PIA provisioning and API endpoints required to generate configuration files.

### 8.2. Network state (android.permission.ACCESS_NETWORK_STATE)

Required to:

- detect whether the device currently has network connectivity
- avoid unnecessary network requests when offline
- provide error handling and process diagnostics

### 8.3. Storage access

The application can export generated WireGuard configuration files to the device.

#### 8.3.1. Write external storage (android.permission.WRITE_EXTERNAL_STORAGE)

- used only on legacy Android versions (Android 9 and earlier)
- allows exported configuration files to be written to the Downloads folder

#### 8.3.2. Read external storage (android.permission.READ_EXTERNAL_STORAGE)

- used only on older Android versions where required by the operating system
- allows the application to verify exported configuration files

### 8.4. Billing (com.android.vending.BILLING)

Required to offer the one-off in-app purchase through Google Play.

- it is a normal permission: nothing is requested at runtime and no dialog appears
- it grants no access to your device, your files or your network
- payment is handled entirely by Google Play. The app never sees a card number, and no payment detail reaches this app or its developer
- the app asks Google Play whether this installation holds the purchase, and nothing else

---

## 9. Security

We take credential safety and application hardening seriously. Please see the [SECURITY.md](./SECURITY.md) for details on our secure development practices, data handling lifecycle, and instructions on how to privately report potential vulnerabilities.

### 9.1. How to check the watchdog script yourself

This app asks a lot of you: it writes a script that holds your PIA password and runs as root on your router, on a schedule, indefinitely. You should not have to take that on trust, and you do not have to - the script is there to be read.

**Where it is.** `/jffs/cfg-pia-wg/watchdog_wgcN.sh`, one file per watched slot, where `N` is the slot number. SSH into the router and `less` it.

**It is plain shell.** Never obfuscated, never minified, never compressed or encoded. What you read is exactly what runs. It is a few hundred lines of POSIX `sh` with comments left in.

**It matches what is in this repository.** The script is generated from a template you can read in [`lib/router_watchdog.dart`](lib/router_watchdog.dart). The template's placeholders are filled in when the app writes the file: your slot number, the path to `jq`, the parts that differ by firmware (the kill switch, how a tunnel is restarted, and the mail command and its headers), the watchdog's own encrypted DNS resolver, the app version, and some fixed text kept elsewhere in the same source file, such as the email's wording and the backoff steps.

**The boot scripts are checked automatically, and there are two of them.** On stock the app installs `S50downloadmaster` and `S50asuslighttpd`, and the repo carries an exact copy of each - [`scripts/S50downloadmaster-TEMPLATE.sh`](scripts/S50downloadmaster-TEMPLATE.sh) and [`scripts/S50asuslighttpd-TEMPLATE.sh`](scripts/S50asuslighttpd-TEMPLATE.sh). The project has an automated test suite that has to pass before a release can be built. It refuses to pass if the copy shipped inside the app differs from the file in the repo by even one character, or if the watchdog script is built with any placeholder left unfilled. So a release cannot exist in which the published text and the deployed text disagree - not as a promise, but because the build stops.

**You can always tell our files from yours.** Every file the app writes to your router carries `auto-generated by cfg-pia-wg` on its second line, and the uninstall refuses to delete a file that does not have it.

**See everything it has stored.** [`scripts/showall.sh`](scripts/showall.sh) prints every NVRAM value the app has written, passwords included, so you can check for yourself what is on the router. [`scripts/clearall.sh`](scripts/clearall.sh) removes them.

---

## 10. Privacy

This application does not collect analytics, advertising identifiers, or personal usage data. Authentication credentials are used only to communicate with Private Internet Access services required to generate configuration files. See [Privacy Policy](https://exponentiallydigital.com/cfg-pia-wg/privacy.html).

---

## 11. Bugs and feature requests

Found a bug or want to request a feature? [Open an issue here](https://github.com/ExponentiallyDigital/cfg-pia-wg/issues).

The quickest route is from inside the app: **About** -> **CREATE GITHUB ISSUE** opens a new issue with your app version, build number and firmware already filled in. **COPY BUILD INFO** on the same screen gives you the same block to paste anywhere else.

---

## 12. Donations

Kindly consider a [PayPal](https://www.paypal.com/donate/?hosted_button_id=QJYPGRLG2RPBS) or [Patreon](https://www.patreon.com/cw/ExponentiallyDigital) donation to help support development.

---

## 13. Support

This app is unsupported and may cause objects in mirrors to be closer than they appear.

---

## 14. Trademark and affiliation notice

The "cfg-pia-wg" name, the app icon, and all associated branding are trademarks of Exponentially Digital. They are reserved in all cases and are not licensed under the GPLv3, which covers the source code only, not the name or the branding.

The GPLv3 licence permits anyone to copy, modify, and redistribute this code, including as a fork or derivative work. That permission does not extend to the trademarks. Any fork, derivative work, or redistribution must:

- Use a different name and app icon, one not confusingly similar to "cfg-pia-wg";
- Remove all Exponentially Digital branding, including from splash screens, store listings, and documentation;
- Not state or imply endorsement by, affiliation with, or sponsorship from Exponentially Digital; and 
- Not use the "cfg-pia-wg" name in its app store listing, package identifier, or repository name in a way that could mislead users into thinking it is the official release.

This is an independent, open-source utility released under the GNU General Public License v3.0. It requires an active Private Internet Access (PIA) account subscription to authenticate with the provisioning endpoints. This application is not affiliated with, endorsed by, sponsored by, or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. Private Internet Access and PIA are trademarks of their respective owner. ASUS is a trademark of ASUSTek Computer Inc.

---

## 15. License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

Copyright (C) 2026 Andrew Newbury.

---
