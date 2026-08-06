# CFG-PIA-WG<img src="./assets/icon/icon.png" alt="PIA WireGuard CFGA" width="150" />
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/releases" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/v/release/ExponentiallyDigital/cfg-pia-wg?color=0969DA" alt="Release"></a> 
<a href="https://www.android.com/" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/platform-Android-57606A?logo=android&logoColor=white" alt="Platform"></a> 
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/LICENSE" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/license/ExponentiallyDigital/cfg-pia-wg?color=0969DA" alt="License"></a> 
<a href="https://github.com/ExponentiallyDigital/ExponentiallyDigital/security/policy" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/security-policy-57606A" alt="Security Policy"></a> 
</br>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg/releases" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/github/downloads/ExponentiallyDigital/cfg-pia-wg/total?color=0969DA" alt="Downloads"></a>
<a href="https://github.com/ExponentiallyDigital/cfg-pia-wg" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/visitors-66-0969DA" alt="Visitor Count"></a>
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

- [1. Why use this?](#1-why-use-this)
  - [1.1. Why use WireGuard?](#11-why-use-wireguard)
- [2. Features](#2-features)
- [3. Pre-built release](#3-pre-built-release)
- [4. Prerequisites \& requirements](#4-prerequisites--requirements)
- [5. Using the app](#5-using-the-app)
  - [5.1. Generate a PIA WireGuard configuration](#51-generate-a-pia-wireguard-configuration)
  - [5.2. Manage router PIA WireGuard configuration](#52-manage-router-pia-wireguard-configuration)
  - [5.3. Watchdog WireGuard management](#53-watchdog-wireguard-management)
  - [5.4. View app log](#54-view-app-log)
  - [5.5. Exit app](#55-exit-app)
  - [5.6. Hamburger menu](#56-hamburger-menu)
  - [5.7. About](#57-about)
- [6. Notes](#6-notes)
- [7. What does the app do to my router?](#7-what-does-the-app-do-to-my-router)
- [8. App permissions](#8-app-permissions)
  - [8.1. Internet (android.permission.INTERNET)](#81-internet-androidpermissioninternet)
  - [8.2. Network state (android.permission.ACCESS\_NETWORK\_STATE)](#82-network-state-androidpermissionaccess_network_state)
  - [8.3. Storage access](#83-storage-access)
    - [8.3.1. Write external storage (android.permission.WRITE\_EXTERNAL\_STORAGE)](#831-write-external-storage-androidpermissionwrite_external_storage)
    - [8.3.2. Read external storage (android.permission.READ\_EXTERNAL\_STORAGE)](#832-read-external-storage-androidpermissionread_external_storage)
- [9. Security](#9-security)
- [10. Privacy](#10-privacy)
- [11. Bugs and feature requests](#11-bugs-and-feature-requests)
- [12. Donations](#12-donations)
- [13. Support](#13-support)
- [14. Trademark and affiliation notice](#14-trademark-and-affiliation-notice)
- [15. License](#15-license)

A native Android app that generates and optionally applies ready-to-use WireGuard (WG) configuration files for the Private Internet Access (PIA) VPN service. It authenticates with PIA's provisioning API, selects the lowest-latency server in your chosen region, generates a fresh WG keypair, and lets you copy the complete `.conf` to the clipboard, or share or save it to an app or location of your choice.

If you have an ASUS router running [Asuswrt-Merlin](https://www.asuswrt-merlin.net/) firmware, you can also **manage** WG configs directly on your router and deploy a **self-healing** watchdog with optional email alerting that makes your configuration truly "set and forget".

This app is based on my command line Windows/Linux app [cfg-pia-wg-cmd](https://github.com/ExponentiallyDigital/cfg-pia-wg-cmd).

## 1. Why use this?

Creating a valid PIA WG config by hand requires expertise in API authentication, WG key generation and correctly assembling connection metadata. **cfg-pia-wg** automates that work and adds router-side **slot management** (organising WG configs across the router's five WG VPN client configuration slots) and **self-healing** watchdog support for Merlin-firmware ASUS routers.

### 1.1. Why use WireGuard?

PIA's WG configs are ephemeral and expire without warning. While OpenVPN offers long-lived configs, the protocol is CPU-intensive, which on many routers becomes a bottleneck limiting throughput.

Switching to WG reduces overhead, allowing your hardware to operate closer to your actual ISP's provisioned speed. In a real-world test with a 500 Mbps plan (546 Mbps measured baseline), speeds jumped from a peak of 136 Mbps on OpenVPN to 499 Mbps with WG on the same hardware, a 75–81% throughput sacrifice under OpenVPN:

<p align="center">
  <img src="./images/vpn-protocol-comparison.png" alt="VPN protocol comparison" width="100%">
  <br>
  VPN protocol comparison
</p>

**cfg-pia-wg** makes the switch to high-performance WG effortless, no separate PC/CLI app required.

## 2. Features

- **Standalone PIA config generation:** choose a region, enter PIA username/password and DNS values, then generate a complete `.conf` file.
- **Secure clipboard handling:** when copying a generated config, a visible 60-second countdown starts, then clears the clipboard automatically at expiry.
- **Share/save support:** share generated `.conf` via the Android share function and save it to a file location of your choice.
- **Router slot management:** connect to an ASUS router over SSH and inspect `wgc1`–`wgc5` slots. Create, enable, edit, disable, or delete WG slot configurations directly.
- **Merlin watchdog management:** deploy a router-side watchdog that monitors and self-heals your WG VPN connection, with configurable checks, optional email alerts and access to the watchdog's log.
- **No persistent credential storage (app):** PIA credentials, router SSH credentials and generated configs are stored only in volatile application memory and are never written to your device's storage.
- **Watchdog credential storage (router):** deploying the watchdog stores the necessary PIA credentials in router NVRAM so it can monitor and self-heal independently of the app. This is a deliberate trade-off for "set and forget" operation, see [ARCHITECTURE.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/ARCHITECTURE.md) and [SECURITY.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/SECURITY.md) for details.
- **Automated lowest-latency server selection:** measures live latency across all available servers in your selected region, ensuring that you provision with the fastest node.
- **Native task-switcher protection:** `(FLAG_SECURE)` enforces native OS-level window flags to block third-party screenshot capturing and automatically obscures the app layout view inside the Android Recent Apps / Task Switcher interface.
- **Input field hardening:** user credential entry textboxes disable predictive text caching, auto-correction, and keyboard learning behaviours.
- **Exit app safety:** all exit paths prompt for confirmation then wipe in-memory credentials and the system clipboard.
- **Professional-grade build chain:** all releases undergo automated security and quality checks with
  - [SonarQube](https://docs.sonarsource.com/sonarqube-server) - code quality and test coverage;
  - [OSV](https://github.com/google/osv-scanner) - open-source dependency scanning against Google's vulnerability database flagging out-of-date third-party packages;
  - [Dependabot](https://docs.github.com/code-security/dependabot) - automates version updates to monitor and patch insecure or outdated dependencies;
  - [MobSF](https://github.com/MobSF/mobile-security-framework-mobsf) - performs static binary security analysis on the app's source code checking for platform-specific vulnerabilities;
  - [CodeQL](https://github.com/github/codeql-action) - static analysis of the code's structure to catch semantic gaps and injection risks; and
  - Pinned GitHub Action hashes across [release.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/release.yml), [promote.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/promote.yml), and [quality_and_security.yml](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/.github/workflows/quality_and_security.yml) ensure automated builds execute with specific, verified tool versions.

---

## 3. Pre-built release

This app is available from the Google Play Store -> [cfg-pia-wg](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga).

If you want to build your own, see [BUILDING.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/BUILDING.md).

---

## 4. Prerequisites & requirements

For anything more than basic copy/past config generation with **Generate PIA WireGuard configuration**, this app requires [Merlin Firmware](https://www.asuswrt-merlin.net/) on your ASUS router. Additionally:

1. Enable the SSH server. This is used by the **Manage** and **Watchdog** functions. Enable this on your router via

```text
Administration\System\Service -> "Enable SSH" (LAN only is recommended).
```

2. Enable the `JFFS` partition. Used by **Manage** and **Watchdog** functions (this _should_ be enabled by default on ASUS routers running firmware version 378.50 or newer). This allows the watchdog script and settings to survive reboots/power cycling:

```text
Administration\System\Basic Config -> "Enable JFFS custom scripts and config"
```

> [!TIP]
> Firmware flashing (upgrading the router's software) [may require redeployment](https://github-wiki-see.page/m/RMerl/asuswrt-merlin.ng/wiki/JFFS) of PIA WG configs. Test your VPN is active after applying a new firmware version.

3. Watchdog and tunnel verification use ICMP ping from the router's WAN and WG interfaces.

## 5. Using the app

The app opens to a main menu with five choices:

- Generate PIA WireGuard configuration
- Manage router PIA WireGuard configuration
- Watchdog WireGuard management
- View app log
- Exit app

<p align="center">
  <img src="./images/main-menu.png" alt="Main menu" width="300">
  <br>
  Main menu
</p>

### 5.1. Generate a PIA WireGuard configuration

1. Tap **Generate PIA WireGuard configuration**.
2. Choose a region from the filterable region list.
3. Enter your PIA username, password, and DNS values.
4. Tap **GENERATE CONFIG** once all required fields are filled.
5. The generated WG configuration is displayed in a selectable but read-only text area.

<p align="center">
  <img src="./images/standalone-config.png" alt="Standalone config generation" width="300">
  <br>
  Standalone config generation
</p>

1. Tap **COPY** to copy the config to the clipboard, or **SHARE / SAVE** to export the file via Android sharing. Copying a config to the clipboard starts a 60 second timer, displayed on screen, after which the clipboard is automatically cleared by copying an empty string to it, so you'll see a system dialogue like "copied" when the timer expires.

### 5.2. Manage router PIA WireGuard configuration

This enables full management of WG slots.

1. Tap **Manage router PIA WireGuard configuration**.
2. Enter router IP, SSH username, and SSH password (defaults are prefilled if available).
3. Tap **CONNECT TO ROUTER**.

<p align="center">
  <img src="./images/router-slot-management.png" alt="Router slot management" width="300">
  <br>
  Router slot management
</p>

1. Select a slot and choose one of the slot actions:

- **CREATE**:
  - first, select a region:
  <p align="center">
    <img src="./images/region-selection.png" alt="App log" width="250">
    <br>
    Region selection
  </p>
  - Then supply PIA credentials and preferred DNS server addresses:
  <p align="center">
    <img src="./images/pia-creds.png" alt="App log" width="250">
    <br>
    Supply credentials and DNS
  </p>
  - The slot's configuration is then generated and saved, but <u>**not**</u> enabled.
    <br>

- **ENABLE:** activates the slot and verifies the interface by using two ping targets over the new VPN interface, not the WAN interface. If the connectivity check fails, the slot is reverted to disabled. Recommended connectivity checking addresses are
  - `8.8.8.8` or `8.8.4.4` (Google primary and secondary DNS)
  - `1.1.1.1` or `1.0.0.1` (CloudFlare primary and secondary DNS)

<p align="center">
  <img src="./images/ping-targets.png" alt="App log" width="175">
  <br>
  Ping targets
</p>

- **EDIT:** allows updating WG slot parameters and saves them back to router NVRAM.

<p align="center">
  <img src="./images/editing-slot.png" alt="App log" width="300">
  <br>
  Editing a slot
</p>

- **DISABLE:** disable the selected slot.
- **DELETE:** remove the slot configuration and disable any associated watchdog.

### 5.3. Watchdog WireGuard management

This manages a self-healing watchdog. In the event that your WG configuration expires, it is automatically renewed and an optional email alert sent when connectivity has been restored.

1. Tap **Watchdog WireGuard management**.
2. Enter router IP, SSH username, and SSH password.
3. Tap **CONNECT TO ROUTER**.

<p align="center">
  <img src="./images/watchdog-management.png" alt="Watchdog management" width="300">
  <br>
  Watchdog management
</p>

1. Select a slot and use the watchdog actions:
   - **CREATE/EDIT:** deploy router-side watchdog scripts and cron jobs for the selected slot.

<p align="center">
  <img src="./images/configuring-watchdog.png" alt="App log" width="300">
  <br>
  Configuring a watchdog
</p>

> [!TIP]
> See [TESTING.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/TESTING.md) for email troubleshooting approaches.

- **DELETE:** remove the watchdog and clear the slot configuration.
- **VIEW WATCHDOG LOG:** inspect the router-side watchdog log. Logs are rotated at midnight retaining the current and previous logs and do not persist if the router is rebooted or a power loss occurs.

### 5.4. View app log

Use the **View app log** screen to inspect in-app log entries and clear them with **CLEAR LOG**.

<p align="center">
  <img src="./images/app-log.png" alt="App log" width="300">
  <br>
  App log
</p>

### 5.5. Exit app

The **Exit app** action confirms before closing the app, and it wipes all volatile session data plus the system clipboard. The clipboard is cleared by copying an empty string to it, so you'll see a system dialogue like "copied" when you exit the app.

### 5.6. Hamburger menu

You can quickly jump between functions via the hamburger menu, always shown in the <span style="color: green; font-weight: bold;">top left corner</span> of each screen:

<p align="center">
  <img src="./images/hamburger-menu.png" alt="App log" width="300">
<br>
Hamburger Menu
</p>

This can be useful to check the application's log during operations.

<p align="center">
  <img src="./images/hamburger-menu-details.png" alt="App log" width="300">
  <br>
  Hamburger Menu
</p>

### 5.7. About

Build information and documentation links live in the hamburger menu's **About** screen:

<p align="center">
  <img src="./images/about.png" alt="App log" width="300">
  <br>
  About
</p>

---

## 6. Notes

- **Pre-shared keys:** PIA WG does not use pre-shared keys. When pushing a config to the router, this field is always set to empty unless a push fails, then its original value is restored.
- **Time-to-live constraints:** PIA WG configs expire without warning per PIA's token handling, requiring you to regenerate a config file periodically (which is why this app exists!).
- **Key safety:** generated configs contains private encryption keys. Treat them like passwords and manage them securely.
- **PIA maintenance:** PIA occasionaly take regions offline for maintenance so you might be expecting to have an exit node in say Perth, but online tools may show you as existing from Adelaide.
- **Check your VPN is working:** with services like [PIA what is my ip](https://www.privateinternetaccess.com/what-is-my-ip), [ipaddress.my](https://ipaddress.my/?lang=en_US), [2ip.io](https://2ip.io), and [showmyip.com](https://www.showmyip.com). However, these sites may cache your location in the browser and they sometimes return a stale exit region if used multiple times. To be absolutely sure, close your browser rather than just refreshing the page.
- **Watchdog shortcut:** If you deploy a _watchdog_ on an empty slot, that will also create the config for that slot in one step.


> [!IMPORTANT]
> This app supports a maximum of one active WG VPN at any time.
>
> When you save a config to your router, that "slot" will become the active VPN **replacing** any previously active slot.
>
> Any slot with a kill switch will be **deactivated** and the kill switch, NAT, and firewalling (if enabled) will be applied to the **newly** enabled slot.

> [!WARNING]
> When manually adding a VPN via the router's web GUI, the watchdog function requires the VPN description match the PIA region name exactly eg `aus_melbourne`.

---

## 7. What does the app do to my router?

A great question to ask as anything that talks to your router programatically should be under extreme scrutiny. A great deal of thinking, research, analysis, and experimentation went into implementing the two features to manage your router's VPN configuration and deploy a watchdog. Please see [ARCHITECTURE.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md) for full details including a flow chart of user interactions and two diagrams showing network calls and representative IP traffic flows.

---

## 8. App permissions

The app uses the following Android permissions:

### 8.1. Internet (android.permission.INTERNET)

Required to:

- authenticate with Private Internet Access (PIA)
- retrieve VPN server information
- generate WG configuration profiles
- perform latency and connectivity tests

No user traffic is routed through this application. The app communicates only with PIA provisioning and API endpoints required to generate configuration files.

### 8.2. Network state (android.permission.ACCESS_NETWORK_STATE)

Required to:

- detect whether the device currently has network connectivity
- avoid unnecessary network requests when offline
- provide better error handling and diagnostics

### 8.3. Storage access

The application can export generated WG configuration files to the device.

#### 8.3.1. Write external storage (android.permission.WRITE_EXTERNAL_STORAGE)

- used only on legacy Android versions (Android 9 and earlier)
- allows exported configuration files to be written to the Downloads folder

#### 8.3.2. Read external storage (android.permission.READ_EXTERNAL_STORAGE)

- used only on older Android versions where required by the operating system
- allows the application to verify exported configuration files

---

## 9. Security

We take credential safety and application hardening seriously. Please see the [SECURITY.md](./SECURITY.md) for details on our secure development practices, data handling lifecycle, and instructions on how to privately report potential vulnerabilities.

---

## 10. Privacy

This application does not collect analytics, advertising identifiers, or personal usage data. Authentication credentials are used only to communicate with Private Internet Access services required to generate configuration files.

---

## 11. Bugs and feature requests

Found a bug or want to request a feature? [Open an issue here](https://github.com/ExponentiallyDigital/cfg-pia-wg/issues).

---

## 12. Donations

Kindly consider a [PayPal](https://www.paypal.com/donate/?hosted_button_id=QJYPGRLG2RPBS) or [Patreon](https://www.patreon.com/cw/ExponentiallyDigital) donation to help support development.

---

## 13. Support

This app is unsupported and may cause objects in mirrors to be closer than they appear. Batteries not included.

---

## 14. Trademark and affiliation notice

This is an independent, open-source utility released under the GNU General Public License v3.0. It requires an active Private Internet Access (PIA) account subscription to authenticate with the provisioning endpoints. This application is not affiliated with, endorsed by, sponsored by, or associated with Private Internet Access, WireGuard or ASUS. WireGuard® is a registered trademark of Jason A. Donenfeld. Private Internet Access and PIA are trademarks of their respective owner. ASUS is a trademark of ASUSTek Computer Inc.

---

## 15. License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

Copyright (C) 2026 Andrew Newbury.
