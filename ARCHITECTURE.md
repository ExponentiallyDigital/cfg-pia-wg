# ARCHITECTURE.md

- [1. How it works](#1-how-it-works)
- [2. App processing flow](#2-app-processing-flow)
  - [2.1. In summary...](#21-in-summary)
  - [2.2. In detail...](#22-in-detail)
  - [2.3. Router WireGuard NVRAM fields](#23-router-wireguard-nvram-fields)
    - [2.3.1. Field reference](#231-field-reference)
    - [2.3.2. Stock `vpnc_clientlist`](#232-stock-vpnc_clientlist)
  - [2.4 Wireguard SSH commands](#24-wireguard-ssh-commands)
  - [2.4.1 Merlin](#241-merlin)
  - [2.4.2 Stock](#242-stock)
    - [2.4.2.1 Create and enable a slot](#2421-create-and-enable-a-slot)
    - [2.4.2.2 Enable existing slot](#2422-enable-existing-slot)
    - [2.4.2.3 Stop](#2423-stop)
    - [2.4.2.4 Delete](#2424-delete)
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
  - [6.4. GNU licence text](#64-gnu-licence-text)

## 1. How it works

The provisioning logic in `lib/pia_service.dart` is a direct Dart translation of the command line version's [Go code](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/blob/main/main.go), implementing the same steps in the same order:

1. **Server discovery**: pulls the complete endpoints mapping directly from serverlist.piaservers.net/vpninfo/servers/v6. The payload splits at the first newline boundary to discard the payload block signature.
2. **Latency probes**: dispatches immediate TCP probes to port 1337 across regional candidate blocks to calculate routing latency.
3. **Session tokens**: challenges the central API through a standard POST request over TLS, securing an execution token from basic user parameters.
4. **Keypair issuance**: generate WireGuard (WG) keypair using X25519 with RFC 7748 scalar clamping  
   (k[0] &= 248, k[31] &= 127, k[31] |= 64)
5. **Secure registration**: submits the dynamic public key configuration to the chosen low-latency endpoint via an HTTPS API (port 1337). The step utilises the dynamically resolved PIA root certificate, matching the specific Common Name (CN) mapping fields rather than raw IP routing addresses. The certificate is not hardcoded, so that it stays current when PIA rotates it.
6. **Config assembly**: transforms payload metadata returns into localised .conf specifications utilising Unix line endings (\n) for cross-compatibility.

---

## 2. <a name='Appprocessingflow'></a>App processing flow

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

### 2.1. <a name='Insummary...'></a>In summary...

When you select a PIA region and push it to your router, the app connects directly to your router over your home network and switches your VPN tunnel to the new location. It first checks whether a VPN tunnel is already running, stops it cleanly, writes the new VPN server details into the router's permanent memory, and then starts the new tunnel. The app watches the router until it confirms the tunnel is active, then checks that internet traffic is actually flowing through it by verifying the public IP address your router is using. If anything goes wrong at any point, the app restores the router to exactly the state it was in before you started.

### 2.2. <a name='Indetail...'></a>In detail...

The push operation establishes an SSH session to the router and uses `wg show interfaces` to detect any currently active WireGuard client slot. If an existing slot config is present in NVRAM, the current `wgcN_*` keys are snapshotted as a backup before any changes are made. The active tunnel is stopped by disabling its `enforce` and `enable` NVRAM flags, committing, then issuing `service "stop_wgc N"; service start_vpnrouting0` targeted at that specific slot. The new configuration is written across the full set of NVRAM keys for the target slot, with `ep_addr_r` and `rip` explicitly cleared since these are populated dynamically by the firmware after tunnel establishment. After a single nvram commit, the new tunnel is started via `service "restart_wgc N"; service start_vpnrouting0`. The app then polls `wg show interfaces` for up to 60 seconds to confirm the interface is active, followed by pinging the user supplied ping targets (defaults to 8.8.8.8 & 1.1.1.1) through the tunnel to confirm routed connectivity. On any failure, independent recovery blocks restore the backed-up NVRAM keys and re-enable the previously active slot as appropriate to the failure scenario.

### 2.3. <a name='RouterWireGuardNVRAMfields'></a>Router WireGuard NVRAM fields

Merlin exposes 17 nvram fields per WireGuard slot, stock exposes 12.

#### 2.3.1. Field reference

| Field | Merlin | Stock | Default | Description |
|---|:-:|:-:|---|---|
| `wgcN_addr` | Yes | Yes | – | Local tunnel IP address assigned by the VPN server, in CIDR notation (e.g. `10.1.2.3`). |
| `wgcN_aips` | Yes | Yes | `0.0.0.0/0` | Allowed IP addresses. |
| `wgcN_alive` | Yes | Yes | `25` (seconds) | Persistent keepalive interval. |
| `wgcN_desc` | Yes | **No** | – | Slot's PIA region name. Must match the actual PIA region name for the watchdog function to operate. |
| `wgcN_dns` | Yes | Yes | `"9.9.9.9, 149.112.112.112"` | Two DNS servers to use, actual values are set in the cfg-pia-wg app. |
| `wgcN_enable` | Yes | Yes | – | `1` enables this slot, `0` disables it. |
| `wgcN_enforce` | Yes | **No** | – | `1` enables the killswitch on this slot, `0` disables it. Blocks routed clients if the tunnel goes down. Stock exposes no UI to alter this - when running on stock this field will be ignored. |
| `wgcN_ep_addr` | Yes | Yes | – | FQDN or public IP of the remote PIA WireGuard peer endpoint. |
| `wgcN_ep_addr_r` | Yes | Yes | – | Resolved numeric IP if `wgcN_ep_addr` is a DNS name (identical value if `wgcN_ep_addr` is already an IP). Set when the interface initialises. |
| `wgcN_ep_port` | Yes | Yes | `1337` | Endpoint port. |
| `wgcN_fw` | Yes | **No** | – | `1` enables the inbound firewall on this slot, `0` disables it. |
| `wgcN_mtu` | Yes | Yes | `1420` | Maximum transmission unit. |
| `wgcN_nat` | Yes | Yes | – | `1` enables NAT, `0` disables it. |
| `wgcN_ppub` | Yes | Yes | – | PIA VPN server public key. |
| `wgcN_priv` | Yes | Yes | – | PIA user's private key. |
| `wgcN_psk` | Yes | Yes | – | Reserved for a preshared key, not used by PIA. |
| `wgcN_rip` | Yes | **No** | – | Router's current external public IP address as seen by the internet. |

**Note: `wgcN_alive`:** Merlin sets this to 25 by default. Stock only defaults to 25 if the field is not explicitly set; the field itself is otherwise optional.

#### 2.3.2. Stock `vpnc_clientlist`

On stock firmware, several WireGuard slot parameters are consolidated into a single nvram setting, `vpnc_clientlist`, rather than being stored as individual `wgcN_` values. This setting is a delimited string holding up to five VPN profiles, one per slot.

**Delimiters:**

- Records (profiles) are separated by `<`. The first record has no leading delimiter; each subsequent record is prefixed by `<`.
- Fields within a record are separated by `>`.

**Field schema** (applies to every record):

| Index | Field        | Meaning                                   |
| :---: | ------------ | ----------------------------------------- |
|   1   | description  | slot description (set to PIA region name) |
|   2   | protocol     | always `WireGuard`                        |
|   3   | slot number  | maps to `wgcN_` (e.g. `5` = `wgc5_`)      |
|   4   | vpn username | ignore                                    |
|   5   | vpn password | ignore, WebUI sets to router admin pwd    |
|   6   | vpn state    | `1` = active, `0` = disabled              |
|   7   | vpnc_idx     | `10 - slot number`, maps to `vpncN_*`     |
|   8   | region?      | ignore, always empty, purpose unconfirmed |
|   9   | conn type?   | ignore, always empty, purpose unconfirmed |
|  10   | tunnel?      | always `0`, purpose unconfirmed           |
|  11   | wan index?   | always `0`, purpose unconfirmed           |
|  12   | caller       | Gui created = `Web`                       |

**Worked example:**

```text
$nvram show vpnc_clientlist
pia-aus_melbourne>WireGuard>5>>mel-pwd>1>5>>>0>0>Web<pia-aus>WireGuard>4>>aus-pwd>0>6>>>0>0>Web<pia-au_brisbane-pf>WireGuard>3>>bris-pwd>0>7>>>0>0>Web<pia-au_adelaide-pf>WireGuard>2>>adf-pwd>0>8>>>0>0>Web<pia-aus_perth>WireGuard>1>>perth-pwd>0>9>>>0>0>Web
```

| Index | Web UI slot 1     | Web UI slot 2 | Web UI slot 3      | Web UI slot 4      | Web UI slot 5 |
| :---: | ----------------- | ------------- | ------------------ | ------------------ | ------------- |
|   1   | pia-aus_melbourne | pia-aus       | pia-au_brisbane-pf | pia-au_adelaide-pf | pia-aus_perth |
|   2   | WireGuard         | WireGuard     | WireGuard          | WireGuard          | WireGuard     |
|   3   | 5                 | 4             | 3                  | 2                  | 1             |
|   4   | –                 | –             | –                  | –                  | –             |
|   5   | mel-pwd           | aus-pwd       | bris-pwd           | adf-pwd            | perth-pwd     |
|   6   | 1                 | 0             | 0                  | 0                  | 0             |
|   7   | 5                 | 6             | 7                  | 8                  | 9             |
|   8   | –                 | –             | –                  | –                  | –             |
|   9   | –                 | –             | –                  | –                  | –             |
|  10   | 0                 | 0             | 0                  | 0                  | 0             |
|  11   | 0                 | 0             | 0                  | 0                  | 0             |
|  12   | Web               | Web           | Web                | Web                | Web           |

### 2.4 Wireguard SSH commands

To manage Wireguard Merlin uses VPN Director, stock ASUS uses VPN Fusion. These are similar but different: using nvram settings to store configuration parameters, but differs in how these are applied and used. There's scant reference detail I could find on how stock officially manages things and a **lot** more by having access to Merlin's source code, so the below is my understanding which may be incorrect and have gaps.

I've used the below to examine WG on ASUS routers, and your best source of information is the system log `tail -f /tmp/syslog.log`. This shows calls to the `service` command wrapper with commands like `service restart_vpnc`. `service` command parameters are not user accessible files.

- Manipulate/see WG configs:

```bash
wg                  # get/set WG settings
wg show interfaces  # show WG device interface names
```

- Poll and display active WG interfaces (substitute `usleep 500000` for `sleep 1` for half-second logging; syslogd can't show microseconds):

```bash
i=1; while [ $i -le 60 ]; do echo "$(date +%H:%M:%S) - $(wg show interfaces)"; sleep 1; i=$((i+1)); done
```

- as above but for `vpnc_unit` whose content changes depending on which slot is being targetted:

```bash
i=1; while [ $i -le 9999 ]; do echo "$(date +%H:%M:%S) - $(nvram get vpnc_unit)"; usleep 500000; i=$((i+1)); done
```

- Show all commands run when a VPN comes up/down or is created/deleted, half second resolution:

 ```bash
 i=1; while [ $i -le 30000 ]; do echo "$(date +%H:%M:%S) - $(ps | grep -E "vpnc|vpn|openvpn|wg" | grep -v grep | head -5)"; usleep 200000; i=$((i+1)); done
 ```

> [!WARNING]
> Setting `usleep` to very low values will likely crash syslogd and/or your router.

- Show the contents of all WG slot settings stored in nvram:

```bash
nvram show | grep -E "wgc[1-9]_" | sort
```

- Display the contents of `vpnc_clientlist`:

```bash
nvram get vpnc_clientlist | tr "<" "\n"
```

- Clear all wgc5 values (the first WG VPN slot created in the WebUI is always named #5):

```bash
for v in wgc5_addr wgc5_aips wgc5_alive wgc5_dns wgc5_enable wgc5_ep_addr wgc5_ep_addr_r wgc5_ep_port wgc5_mtu wgc5_nat wgc5_ppub wgc5_priv wgc5_psk; do nvram unset "$v"; done; nvram commit
```

- Show `vpnc_` (where N is 5-9) for WireGuard:

 ```bash
 nvram show | grep -E "vpnc([1-9]|1[0-6])_" | sort
 ```

- Show `vpnc_`, this includes `vpnc_unit` (the unit being acted on) and `vpnc_max_conn` the maximum number of concurrent VPNs:

 ```bash
 nvram show | grep -E "vpnc_" | sort
 ```

### 2.4.1 Merlin

Operations are performed by setting nvram fields on specific slots and making calls with service commands...

`<************** PLACEHOLDER - add full details here **************>`

### 2.4.2 Stock

VPN Fusion abstracts the underlying WG calls to manipulate WG VPNs:

```text
        vpnc_clientlist
              │
              ├── profile
              │    ├── protocol = WireGuard
              │    ├── slot = 5
              │    └── active = ...
              │
        set vpnc_unit=0
              │
              ▼
   stop_vpnc OR restart_vpnc
              │
              ▼
            VPN Fusion
              │
              ▼
             wgc5
```

In the above, wgc5 is vpnc_unit 0 (wgc4 is unit 1, wgc3 is unit 2 etc).

#### 2.4.2.1 Create and enable a slot

Creating the first slot in the WebUI adds the below keys and populates settings.

The below examples are for `wgc5`, which is the first WG VPN created. **NB** the first slot created is numbered `5` and the last is `1`.

  1. set `wgcN_*` values:

  ```bash
  # Primary keys
  wgc5_addr=10.119.0.18/32          # local tunnel IP address assigned by the VPN server
  wgc5_aips=0.0.0.0/0               # allowed IP addresses
  wgc5_alive=25                     # tunnel keep alive in seconds
  wgc5_dns=9.9.9.9,149.112.112.112  # two DNS servers
  wgc5_enable=1                     # 1=enable, 0=disable
  wgc5_ep_addr=45.130.141.215       # FQDN or public IP of the remote PIA WireGuard peer endpoint
  wgc5_ep_addr_r=45.130.141.215     # resolved numeric IP if `wgcN_ep_addr` is a DNS name; set when the interface initialises
  wgc5_ep_port=1337                 # end point port; PIA WG uses port 1337
  wgc5_mtu=                         # maximum transmission unit, picked up from the conf file that created this slot (defaults to??)
  wgc5_nat=1                        # 1=enable, 0=disabled
  wgc5_ppub=PUBLIC_KEY              # PIA VPN server public key
  wgc5_priv=PRIVATE_KEY             # PIA user's private key
  wgc5_psk=                         # preshared key, not used by PIA.
  
  # VPN Fusion keys
  vpnc5_dns=9.9.9.9 149.112.112.112 # DNS servers, set when slot is enabled, unset when disabled
  vpnc5_dut_disc=5                  # unknown, unset when slot is enabled, when disabled this is the slot #
  vpnc5_sbstate_t=0                 # unknown
  vpnc5_state_t=2                   # unknown
  vpnc_unit=0                       # the unit being acted on where 0=wgc5, 1=wgc4, 2=wgc3, 3=wgc2, 4=wgc1; retains last set value.
  ```

  2. `vpnc_clientlist` is created and contains

  ```bash
  pia-aus_melbourne>WireGuard>5>>ROUTER_ADMIN_PWD>1>5>>>0>0>Web
  ```

  3. exec `service restart_vpnc`

#### 2.4.2.2 Enable existing slot

  1. set `wgc5_enable=1`
  2. set `vpnc_unit=0` where `N` is `0`=wgc5, `1`=wgc4, `2`=wgc3, `3`=wgc2, `4`=wgc1
  3. set `vpnc_clientlist` field 6 (vpn state) to `1` (active)
  4. exec `service restart_vpnc`

  `service restart_default_wan` is run by the UI when "apply to all devices" is enabled/disabled.

There is **no** `start_vpnc` command.

#### 2.4.2.3 Stop/Disable

  1. set `wgcN_enable=0`
  2. set `vpnc_unit=N` where `N` is `0`=wgc5, `1`=wgc4, `2`=wgc3, `3`=wgc2, `4`=wgc1
  3. set `vpnc_clientlist` field 6 (vpn state) to `0` (disabled)
  4. exec `service stop_vpnc`

#### 2.4.2.4 Delete

Deleting a slot set to `apply to all devices` executes

```bash
service restart_default_wan
service restart_vpnc_dev_policy
```

Deleting the last WG slot executes

```bash
service restart_vpnc_dev_policy
```

`<************** PLACEHOLDER **************>`
ARE THE BELOW SET BY VPN FUSION CALLS?

 `vpncN_*` values are

  ```bash
  vpnc5_dut_disc=5   # retained after reboot
  vpnc5_sbstate_t=0  # removed after reboot
  vpnc5_state_t=2    # removed after reboot

`wgcN_*` are **not** removed when a profile is deleted.
```

---

## 3. <a name='Watchdogdetails'></a>Watchdog details

On Merlin firmware routers, enabling the watchdog deploys

1. a slot-specific shell script `/jffs/scripts/watchdog_wgcN.sh`
2. cron entries via `/jffs/scripts/services-start`.

### 3.1. <a name='Shellscript'></a>Shell script

The shell script checks connectivity via the VPN tunnel on a periodic basis using two ping targets

- `8.8.8.8` (Google)
- `1.1.1.1` (Cloudflare)

If connectivity fails, the interface is reconfigured with back off.

### 3.2. <a name='Cronentries'></a>Cron entries

A `cru` (`crontab`) entry drives the configurable periodic health check. An additional job rotates the watchdog router log file at midnight. To avoid filling the JFFS partition, all logging is stored in `/tmp`. Watchdog logs do not persist after a reboot or power loss.

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

## 4. <a name='Networktraffic'></a>Network traffic

Below are detailed representations of the app's network calls, with illustrative, not real, IP addresses.

![cfg-pia-wg Network Traffic Flow](<./images/network-traffic-(representative).svg>)

![cfg-pia-wg Network Traffic Flow](<./images/network-traffic-(logical).svg>)

---

## 5. <a name='Outputsessiondestruction'></a>Output & session destruction

Generated configuration data is managed via:

- **Ephemeral verification:** displayed on-screen inside a text viewport for visual validation.
- **Transient streaming:** shareable using Android's system share sheet (e.g., via "Save to Files" or encrypted side-channels).
- **Clipboard sanitisation:** tapping **COPY** invokes a 60-second timer that clears the clipboard storage space automatically.
- **Application exit:** all application exit paths flush credentials and scrub configs from memory before application shutdown.

---

## 6. <a name='BuildprovenancetheAboutscreen'></a>Build provenance (the About screen)

`lib/screens/about_screen.dart` exists so a bug reportor can identify which binary is running. Displays the commit, branch/tag, CI run, build type, and install source.

### 6.1. <a name='Thechannel'></a>The channel

`com.exponentiallydigital.pia_wireguard_cfga/build_info`, registered in `MainActivity.configureFlutterEngine` and answering a single method, `getBuildInfo`, with a flat `Map<String, String>`.

Everything is a `String` deliberately: a uniform map crosses `StandardMessageCodec` without mixed-type surprises and needs no per-key casting in `lib/build_info_service.dart`. Any field the host cannot determine comes back as the literal `unknown` rather than null.

`loadBuildInfo()` handles `MissingPluginException` and `PlatformException`, returning `BuildInfo.unknown()`. With `flutter test` no native side is registered, so every test takes that path.

### 6.2. <a name='Whereeachfieldcomesfrom'></a>Where each field comes from

| Field | Source |
| --- | --- |
| `versionName`, `buildNumber` | `PackageManager` at runtime (`longVersionCode` on API 28+) |
| `installer` | `getInstallSourceInfo()` on API 30+, else `getInstallerPackageName()`; mapped to a friendly label, falling back to the raw package name |
| `buildType` | `BuildConfig.BUILD_TYPE` is AGP-generated; can be `debug`, `profile` (Flutter adds it) or `release` |
| `cpuAbi` | `Build.SUPPORTED_ABIS[0]` is the *device's* preferred ABI, since `flutter build apk` ships a universal APK |
| `osVersion` | `RELEASE_OR_CODENAME` on API 30+, else `RELEASE`, plus `SDK_INT` |
| `buildTimestamp`, `commitHash`, `commitDate`, `gitBranch`, `runnerId`, `compileSdk`, `kotlinVersion` | `BuildConfig`, injected by `android/app/build.gradle.kts` at configuration time |

### 6.3. <a name='Gradle-sidenotes'></a>Gradle-side notes

`buildFeatures { buildConfig = true }` is required, AGP 8+ defaults it to `false`, and AGP 9 removed the `android.defaults.buildfeatures.buildconfig` escape hatch. Once enabled, AGP generates `DEBUG`, `APPLICATION_ID`, `BUILD_TYPE`, `VERSION_CODE` and `VERSION_NAME` itself; only the seven custom fields are declared by hand.

- **git** runs through `providers.exec` (a raw `ProcessBuilder` would be a configuration-cache violation) as `git -C <android/>`, so it never depends on the daemon's working directory. Every failure path: git absent from `PATH`, no `.git` in a source tarball, degrades to `unknown` instead of failing the build.
- **`gitBranch`** prefers `GITHUB_REF_NAME` and rejects a literal `HEAD` from the git fallback: `release.yml` triggers on tag pushes, which leaves a detached HEAD where `rev-parse --abbrev-ref` returns `HEAD`, never the tag.
- **`buildTimestamp`** is wall-clock at configuration time, which means `GenerateBuildConfig` is never up to date and every build recompiles and repackages the app module. That is an accepted trade for exact build provenance; `GIT_COMMIT_DATE` is delivered alongside it as a reproducible cross-check.
- **`kotlinVersion`** comes from `getKotlinPluginVersion()`, falling back to `KotlinBasePlugin.pluginVersion`. The Kotlin plugin is deliberately *not* added to the app's `plugins {}` block as Flutter's Gradle plugin applies it, and declaring it again makes Flutter log an AGP-9 migration warning at error level on every build.
- **`buildConfigField`'s value is emitted verbatim** into `BuildConfig.java`, so `javaStringLiteral()` escapes every string. These values come from git and the environment: a branch named `foo"bar` would otherwise produce uncompilable generated Java.
- No new dependencies, so the STRICT `gradle.lockfile` set is untouched. This is also why the Kotlin side hand-rolls the `longVersionCode` branch rather than using `androidx.core`'s `PackageInfoCompat`.

### 6.4. <a name='Thelicencetext'></a>GNU licence text

`lib/license_text.dart` holds `./LICENSE` a verbatim raw-string constant, generated at development time, not loaded at runtime and not registered as an asset.

---
