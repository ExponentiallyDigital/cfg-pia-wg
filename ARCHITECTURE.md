# ARCHITECTURE.md

- [1. How it works](#1-how-it-works)
- [2. App processing flow](#2-app-processing-flow)
  - [2.1. In summary...](#21-in-summary)
  - [2.2. In detail...](#22-in-detail)
  - [2.3. Router WireGuard NVRAM fields](#23-router-wireguard-nvram-fields)
- [3. Watchdog details](#3-watchdog-details)
  - [3.1. Shell script](#31-shell-script)
  - [3.2. Cron entries](#32-cron-entries)
  - [3.3. Watchdog NVRAM fields](#33-watchdog-nvram-fields)
  - [3.4. Sample `cfg-pia-wg` output](#34-sample-cfg-pia-wg-output)
- [4. Network traffic](#4-network-traffic)
- [5. Output \& session destruction](#5-output--session-destruction)
- [6. Build provenance (the About screen)](#6-build-provenance-the-about-screen)
  - [6.1. The channel](#61-the-channel)
  - [6.2. Where each field comes from](#62-where-each-field-comes-from)
  - [6.3. Gradle-side notes](#63-gradle-side-notes)
  - [6.4. The licence text](#64-the-licence-text)



 ## 1. How it works

The provisioning logic in `lib/pia_service.dart` is a direct Dart translation of the command line version's [Go code](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/blob/main/main.go), implementing the same steps in the same order:

1. **Server discovery**: pulls the complete endpoints mapping directly from serverlist.piaservers.net/vpninfo/servers/v6. The payload splits at the first newline boundary to discard the payload block signature.
2. **Latency probes**: dispatches immediate TCP probes to port 1337 across regional candidate blocks to calculate routing latency.
3. **Session tokens**: challenges the central API through a standard POST request over TLS, securing an execution token from basic user parameters.
4. **Keypair issuance**: generate WireGuard keypair using X25519 with RFC 7748 scalar clamping  
   (k[0] &= 248, k[31] &= 127, k[31] |= 64)
5. **Secure registration**: submits the dynamic public key configuration to the chosen low-latency endpoint via an HTTPS API (port 1337). The step utilises the dynamically resolved PIA root certificate, matching the specific Common Name (CN) mapping fields rather than raw IP routing addresses. The certificate is not hardcoded, so that it stays current when PIA rotates it.
6. **Config assembly**: transforms payload metadata returns into localised .conf specifications utilising Unix line endings (\n) for cross-compatibility.

##  2. <a name='Appprocessingflow'></a>App processing flow

```mermaid
graph TD
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'fontSize': '24px'
  },
  'flowchart': {
    'subGraphTitleMargin': { 'top': 1,
    'bottom': 15}
  }
}}%%
    A["Start app"] --> B["Main menu"]
    B --> C["Generate standalone PIA WireGuard configuration"]
    B --> D["Manage router PIA WireGuard configuration*"]
    B --> E["Watchdog WireGuard management*"]
    B --> F["View app log"]
    B --> G["Exit app"]

    C --> H["Enter region, PIA username/password, DNS"]
    H --> I{"Tap GENERATE CONFIG"}
    I -->|"required field empty"| H
    I -->|"valid input"| J["PiaService.generateConfig"]

    subgraph GEN["Config generation: lib/pia_service.dart"]
        J --> J1["fetchRegions: pull PIA server list"]
        J1 --> J2["probeLatency: TCP port 1337, pick fastest server"]
        J2 --> J3["getToken: HTTP Basic Auth provisioning token"]
        J3 --> J4["generateWgKeypair: X25519 with RFC 7748 clamping"]
        J4 --> J5["registerKey: HTTPS register pubkey, CA-pinned"]
        J5 --> J6["buildConfig: assemble .conf"]
    end

    J6 --> K["Display GENERATED CONFIG"]
    K --> L["COPY to clipboard (auto-clear 60s)"]
    K --> M["SHARE / SAVE via Android share sheet"]

    D --> D1["Enter router IP, SSH user/password"]
    D1 --> D2["CONNECT TO ROUTER"]
    D2 --> D3["fetchSlots: read wgc1–5 metadata, active slot, Merlin detection"]
    D3 --> D4["Open SlotModal (manage mode)"]

    subgraph MGR["Manage router flow"]
      D4 --> D5["Select slot + action"]
      D5 --> D5a["CREATE: pick region, enter PIA creds, generateConfig, createConfigToSlot (write NVRAM disabled)"]
      D5 --> D5b["ENABLE: read watchdog targets, disable other active slot, enableSlot with connectivity check, revert on failure"]
      D5 --> D5c["EDIT: readSlotParams, edit parameters, writeSlotParams"]
      D5 --> D5d["DISABLE: stop watchdog if present, disableSlot"]
      D5 --> D5e["DELETE: stop watchdog if present, deleteSlot"]
      D5a --> D5f["Refresh slots after action"]
      D5b --> D5f
      D5c --> D5f
      D5d --> D5f
      D5e --> D5f
    end

    E --> E1["Enter router IP, SSH user/password"]
    E1 --> E2["CONNECT TO ROUTER"]
    E2 --> E3["fetchSlots: read wgc1–5 metadata, active slot, Merlin required"]
    E3 --> E4["Open SlotModal (watchdog mode)"]

    subgraph WD["Watchdog flow"]
      E4 --> E5["Select slot + action"]
      E5 --> E5a["ENABLE: stop other watchdogs, loadConfig, sync PIA creds, validate, startWatchdog (deploy scripts, cron, services-start)"]
      E5 --> E5b["EDIT: open WatchdogDialog, save watchdog config to NVRAM"]
      E5 --> E5c["DISABLE: stopWatchdog"]
      E5 --> E5d["DELETE: stopWatchdog, deleteSlot"]
      E5 --> E5e["VIEW WATCHDOG LOG: getWatchdogLog"]
      E5a --> E5f["Refresh slots after action"]
      E5b --> E5f
      E5c --> E5f
      E5d --> E5f
      E5e --> E5f
    end

    G --> R["Confirm exit and wipe credentials + config + clipboard"]
```

> [!NOTE]
> WireGuard configuration is backed up before any destructive/configuration activity, and restored if any issue is detected.

###  2.1. <a name='Insummary...'></a>In summary...

When you select a PIA region and push it to your router, the app connects directly to your router over your home network and switches your VPN tunnel to the new location. It first checks whether a VPN tunnel is already running, stops it cleanly, writes the new VPN server details into the router's permanent memory, and then starts the new tunnel. The app watches the router until it confirms the tunnel is active, then checks that internet traffic is actually flowing through it by verifying the public IP address your router is using. If anything goes wrong at any point, the app restores the router to exactly the state it was in before you started.

###  2.2. <a name='Indetail...'></a>In detail...

The push operation establishes an SSH session to the router and uses `wg show interfaces` to detect any currently active WireGuard client slot. If an existing slot config is present in NVRAM, the current `wgcN_*` keys are snapshotted as a backup before any changes are made. The active tunnel is stopped by disabling its `enforce` and `enable` NVRAM flags, committing, then issuing `service "stop_wgc N"; service start_vpnrouting0` targeted at that specific slot. The new configuration is written across the full set of NVRAM keys for the target slot, with `ep_addr_r` and `rip` explicitly cleared since these are populated dynamically by the firmware after tunnel establishment. After a single nvram commit, the new tunnel is started via `service "restart_wgc N"; service start_vpnrouting0`. The app then polls `wg show interfaces` for up to 60 seconds to confirm the interface is active, followed by polling `ipv4.icanhazip.com` (a service run and hosted by [Cloudflare](https://www.cloudflare.com/)) via curl through the tunnel to confirm routed connectivity. On any failure, independent recovery blocks restore the backed-up NVRAM keys and re-enable the previously active slot as appropriate to the failure scenario.

###  2.3. <a name='RouterWireGuardNVRAMfields'></a>Router WireGuard NVRAM fields

```text
wgcN_addr=the local tunnel IP address assigned to the router by the VPN server in CIDR notation (e.g., `10.x.x.x/32`).
wgcN_alive=the persistent keepalive interval, set to 25 (seconds) by default. This field is user editable.
wgcN_desc=the slot's PIA region name. This must match the actual PIA region name for the watchdog function to operate.
wgcN_dns=two DNS servers to use. Optional, but defaults to `"9.9.9.9, 149.112.112.112"`.
wgcN_enable=set to `1` this enables this slot; when set to `0` this slot is disabled.
wgcN_enforce=set to `1` this enables the killswitch on this slot; when set to `0` it is disabled. The killswitch blocks routed clients if the tunnel goes down.
wgcN_ep_addr=the domain name (FQDN) or public IP address of the remote PIA WireGuard server (peer endpoint) you are connecting to.
wgcN_ep_addr_r=if `wgcN_ep_addr` contains either a DNS name or an IP address, this is the resolved numeric IP address; if `wgcN_ep_addr` contains a direct IP address, this field will hold an identical value. This field is set when the interface is initialised.
wgcN_ep_port=the endpoint port, defaulting to `1337` for PIA.
wgcN_fw=set to `1` to enable the inbound firewall on this slot; set to `0` to disable it.
wgcN_mtu=the MTU (Maximum Transmission Unit), set to `1420` by default.
wgcN_nat=set to `1` to enable network address translation (NAT); set to `0` to disable NAT.
wgcN_ppub=The PIA VPN server public key.
wgcN_priv=the PIA user's private key. This field should be rendered as an obscured input (like a password field) with a show/hide toggle, consistent with how SSH and PIA credentials are handled elsewhere in the app.
wgcN_psk=this value is not used by PIA and is read-only for the user (reserved for a preshared key).
wgcN_rip=stores the router's current external public IP address as seen by the internet.
wgcN_aips=allowed IP addresses, defaults to `0.0.0.0/0`.
```

---

##  3. <a name='Watchdogdetails'></a>Watchdog details

On Merlin firmware routers, enabling the watchdog deploys

1. a slot-specific shell script `/jffs/scripts/watchdog_wgcN.sh`
2. cron entries via `/jffs/scripts/services-start`.

###  3.1. <a name='Shellscript'></a>Shell script

The shell script checks connectivity via the VPN tunnel on a periodic basis using two ping targets

- `8.8.8.8` (Google)
- `1.1.1.1` (Cloudflare)

If connectivity fail, the interface is reconfigured with back off.

### 3.2. <a name='Cronentries'></a>Cron entries

A `crontab`/`cru` entry drives the configurable periodic health check. An additinal job rotates the watchdog router log file at midnight, retaining the prior log. To avoid filling the JFFS partition, all logging is stored in `/tmp`. Watchdog logging does not persist after a reboot or power loss.

```bash
*/5 * * * * /jffs/scripts/watchdog_wgc1.sh #watchdog_wgc1#
0 0 * * * mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old && touch /tmp/watchdog_wgc1.log #watchdog_log_rotate_wgc1#
```

### 3.3. <a name='WatchdogNVRAMfields'></a>Watchdog NVRAM fields

All watchdog configuration is stored on your router's NVRAM. Defaults are as follows:

```bash
# slot specific
wgcN_wd_check_interval=5
wgcN_wd_email_enabled=0
wgcN_wd_email_from=
wgcN_wd_email_subject=cfg-pia-wg alert
wgcN_wd_email_to=
wgcN_wd_primary_ip=8.8.8.8
wgcN_wd_secondary_ip=1.1.1.1
wgcN_wd_smtp_pass=
wgcN_wd_smtp_server=
wgcN_wd_smtp_user=
# global
cfg-pia-wg_password=
cfg-pia-wg_user=
```

(where `N` is the slot number 1-5)

---

### 3.4. Sample `cfg-pia-wg` output

Standalone configuration file, suitable for importing into various WireGuard clients/routers:

```none
[Interface]
PrivateKey = <freshly generated private key>
Address    = <client IP/32 assigned by PIA>
DNS        = 9.9.9.9, 149.112.112.112
MTU        = 1420

[Peer]
PublicKey           = <server public key from PIA>
Endpoint            = <server IP:port from PIA>
PersistentKeepalive = 25
AllowedIPs          = 0.0.0.0/0
```

---

##  4. <a name='Networktraffic'></a>Network traffic

Below are detailed representations of the app's network calls, with illustrative, not real, IP addresses.

![cfg-pia-wg Network Traffic Flow](<./images/network-traffic-(representative).svg>)

![cfg-pia-wg Network Traffic Flow](<./images/network-traffic-(logical).svg>)

---

##  5. <a name='Outputsessiondestruction'></a>Output & session destruction

Generated configuration data is managed via:

- **Ephemeral verification:** displayed on-screen inside a text viewport for visual validation.
- **Transient streaming:** shareable using Android's system share sheet (e.g., via "Save to Files" or encrypted side-channels).
- **Clipboard sanitisation:** tapping **COPY** invokes a 60-second timer that clears the clipboard storage space automatically.
- **Application exit:** all applicaation exit paths flush credentials and scrub configs from memory before application shutdown.

---

##  6. <a name='BuildprovenancetheAboutscreen'></a>Build provenance (the About screen)

`lib/screens/about_screen.dart` exists so a bug report can identify exactly which binary the reporter is running. Once an APK ships, the commit, branch/tag, CI run, build type and install source are otherwise invisible.

###  6.1. <a name='Thechannel'></a>The channel

`com.exponentiallydigital.pia_wireguard_cfga/build_info`, registered in `MainActivity.configureFlutterEngine` and answering a single method, `getBuildInfo`, with a flat `Map<String, String>`.

Everything is a `String` deliberately: a uniform map crosses `StandardMessageCodec` without mixed-type surprises and needs no per-key casting in `lib/build_info_service.dart`. Any field the host cannot determine comes back as the literal `unknown` rather than null.

`loadBuildInfo()` swallows `MissingPluginException` and `PlatformException`, returning `BuildInfo.unknown()`.
This is load-bearing, not defensive padding: under `flutter test` no native side is registered at all, so every full-app widget test takes that path.

###  6.2. <a name='Whereeachfieldcomesfrom'></a>Where each field comes from

| Field | Source |
| --- | --- |
| `versionName`, `buildNumber` | `PackageManager` at runtime (`longVersionCode` on API 28+) |
| `installer` | `getInstallSourceInfo()` on API 30+, else `getInstallerPackageName()`; mapped to a friendly label, falling back to the raw package name |
| `buildType` | `BuildConfig.BUILD_TYPE` is AGP-generated; can be `debug`, `profile` (Flutter adds it) or `release` |
| `cpuAbi` | `Build.SUPPORTED_ABIS[0]` is the *device's* preferred ABI, since `flutter build apk` ships a universal APK |
| `osVersion` | `RELEASE_OR_CODENAME` on API 30+, else `RELEASE`, plus `SDK_INT` |
| `buildTimestamp`, `commitHash`, `commitDate`, `gitBranch`, `runnerId`, `compileSdk`, `kotlinVersion` | `BuildConfig`, injected by `android/app/build.gradle.kts` at configuration time |

###  6.3. <a name='Gradle-sidenotes'></a>Gradle-side notes

`buildFeatures { buildConfig = true }` is required, AGP 8+ defaults it to `false`, and AGP 9 removed the
`android.defaults.buildfeatures.buildconfig` escape hatch. Once enabled, AGP generates `DEBUG`,
`APPLICATION_ID`, `BUILD_TYPE`, `VERSION_CODE` and `VERSION_NAME` itself; only the seven custom fields are
declared by hand.

- **git** runs through `providers.exec` (a raw `ProcessBuilder` would be a configuration-cache violation) as
  `git -C <android/>`, so it never depends on the daemon's working directory. Every failure path: git absent
  from `PATH`, no `.git` in a source tarball, degrades to `unknown` instead of failing the build.
- **`gitBranch`** prefers `GITHUB_REF_NAME` and rejects a literal `HEAD` from the git fallback: `release.yml`
  triggers on tag pushes, which leaves a detached HEAD where `rev-parse --abbrev-ref` returns `HEAD`, never
  the tag.
- **`buildTimestamp`** is wall-clock at configuration time, which means `GenerateBuildConfig` is never up to
  date and every build recompiles and repackages the app module. That is an accepted trade for exact build
  provenance; `GIT_COMMIT_DATE` is delivered alongside it as a reproducible cross-check.
- **`kotlinVersion`** comes from `getKotlinPluginVersion()`, falling back to `KotlinBasePlugin.pluginVersion`.
  The Kotlin plugin is deliberately *not* added to the app's `plugins {}` block as Flutter's Gradle plugin
  applies it, and declaring it again makes Flutter log an AGP-9 migration warning at error level on every
  build.
- **`buildConfigField`'s value is emitted verbatim** into `BuildConfig.java`, so `javaStringLiteral()` escapes
  every string. These values come from git and the environment: a branch named `foo"bar` would otherwise
  produce uncompilable generated Java.
- No new dependencies, so the STRICT `gradle.lockfile` set is untouched. This is also why the Kotlin side
  hand-rolls the `longVersionCode` branch rather than using `androidx.core`'s `PackageInfoCompat`.

###  6.4. <a name='Thelicencetext'></a>The licence text

`lib/license_text.dart` holds `./LICENSE` verbatim as a raw-string constant, and is generated at development time, not loaded at runtime and not registered as an asset. The About screen therefore has no I/O path and no way to
display a licence that differs from the one in the repository.

**If `./LICENSE` changes, regenerate that constant.**

---
