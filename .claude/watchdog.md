# Router Watchdog Module – Architecture & Requirements

This document defines the complete requirements for integrating a watchdog feature into the existing `pia-wireguard-cfga` Flutter app. The watchdog monitors VPN connectivity via ICMP pings and automatically reconfigures WireGuard using PIA’s API when a failure is detected. All router interactions are performed over the established SSH connection.

Claude Code **must** review the existing module `lib/router_push.dart` to understand how the app currently retrieves, creates, and applies a WireGuard configuration (via bash scripts). The watchdog will reuse that logic. In particular, the NVRAM variable assignments and the service restart commands **must** follow the pattern already used in `router_push.dart` – see the section “// ── Step 4: Write new config to NVRAM” in that file for the required values.

---

## 1. Overview

The **router_watchdog** module adds a user‑configurable watchdog that:

- Runs on a **Merlin‑firmware** router (detected via NVRAM).
- Periodically pings user‑supplied primary/secondary IP addresses.
- If both pings fail, it generates a new WireGuard configuration by negotiating with PIA servers replicating the PIA negotiation logic from pia_service.dart, implemented in Bash within the watchdog script.
- Applies the new config **using `wg setconf`** (since `wg‑quick` is unavailable) and restarts the interface using the same method as the app (e.g., `service "start_wgc $slot"; service restart_vpnrouting0` – see `router_push.dart` for details).
- Optionally sends email alerts via the router’s `sendmail` when a reconfiguration is attempted (successful or failed).
- Provides a UI for enabling/disabling, configuring, viewing status, and reading the watchdog log.

All watchdog‑related logs are stored in `/tmp/watchdog_wgcN.log` (where `N` is the slot number) and rotated daily via a cron job. The status (last successful ping timestamp) is stored in `/tmp/watchdog_last_ping_success_wgcN` (per slot).

**All configuration variables are stored exclusively in NVRAM**, never in files. The script reads them from NVRAM and writes them back when necessary (e.g., new private key, endpoint, etc.). The WireGuard private key is also stored only in NVRAM.

**User‑supplied configuration data** (while the Dart module is executing on the user’s device) **must only be stored in volatile Android memory** – never written to the device’s filesystem.

---

## 2. Functional Requirements

### 2.1 Core Features

- **Merlin Detection**: Execute `nvram get 3rd-party` over SSH to verify the router is running Merlin (`value == "merlin"`). If not, the watchdog feature is hidden.
- **JFFS Enablement**: When watchdog is activated, ensure `jffs2_scripts=1` and `jffs2_on=1` via `nvram set` and `nvram commit`. **Do not disable** these settings when the watchdog is disabled (leave JFFS as‑is).
- **Script Deployment**: Generate and upload Bash scripts to `/tmp/scripts/` with the slot name appended (e.g., `watchdog_wgc1.sh`) – all written via SSH commands (no SFTP/SCP).
- **Connectivity Test**: Ping the **primary** IP; if it fails, ping the **secondary**. Only if **both** fail will reconfiguration be triggered.
- **Flap Prevention & Retry**: If the router loses WAN connectivity (upstream outage), the watchdog must not repeatedly try to reconfigure. It will **retry every 2 minutes** after a failed reconfiguration attempt (instead of exponential backoff). Emails **must not be sent** on every ping failure – only when a reconfiguration is actually attempted (success or failure). This prevents alert fatigue.
- **WireGuard Reconfiguration**: When both pings fail and the retry timer allows, the watchdog script:
  - Generates a new private key (`wg genkey`) and computes the public key.
  - Fetches a server list from PIA, selects the **lowest‑latency** server.
  - Negotiates a WireGuard config (same algorithm as `pia_service.dart`).
  - Writes the new config parameters **directly to NVRAM** using `nvram set` for all the `wgcN_*` variables. The exact list of variables and the values to set **must** follow the pattern used in `lib/router_push.dart` – refer to the comment “// ── Step 4: Write new config to NVRAM” in that file for the required values.
  - Commits the changes (`nvram commit`).
  - Applies the config using **`wg setconf`** (not `syncconf`).
  - Restarts the interface using the same method as the app: `service "start_wgc $slot"; service restart_vpnrouting0` (or similar).
- **Email Alerts (Optional)**: If enabled, `sendmail` is used to notify the user **when a reconfiguration attempt is made**, regardless of success or failure. The email subject should indicate whether the reconfiguration succeeded or failed. Emails **must not be sent** on repeated ping failures; only on actual reconfiguration attempts (and at most one email per attempt).
- **Logging**: All watchdog actions are logged to `/tmp/watchdog_wgcN.log` (per slot). The log rotates daily, handled by a **cron job** (the script only creates the cron entry for rotation).
- **Status Display**: The app shows the timestamp of the last successful ICMP response, read from `/tmp/watchdog_last_ping_success_wgcN` (per slot).
- **User Configuration**: User can set:
  - **Primary and secondary IPs** (defaults: 8.8.8.8 / 8.8.4.4 and 1.1.1.1 / 1.0.0.1 – user may choose any valid IP). **Both IPs are required**; the user cannot leave either empty.
  - **Check interval** (minutes) – how often the watchdog runs (default 5).
  - Email alert settings (From, To, Subject, SMTP server, username, password). **These are stored in NVRAM** on the router, not on the device.

**All ICMP tests must be performed through the router’s currently active VPN interface** (e.g., `wgc1`–`wgc5`), **not** the WAN interface. The script must also explicitly check if the interface exists and is up (ip link show wgcN or ifconfig wgcN) before executing the ping. This ensures that the watchdog verifies VPN connectivity specifically. In the Bash script, use `ping -I wgcN <target>` (where `N` is the slot number) to bind the ping to the VPN interface. If the interface is down or the ping fails, the watchdog will treat this as a connectivity failure and trigger reconfiguration.

### 2.2 Validation

- **ICMP Reachability**: Before saving configuration, the app will ping **both** the provided primary and secondary IPs via the router's WAN interface to verify they are reachable from the router (via SSH). If **either** is unreachable, the user is warned.
- **Test Email**: A button allows the user to send a test email with subject **“config test”** to verify SMTP settings.

---

## 3. UI Requirements

### 3.1 Integration Point

A new **“Watchdog”** button is added at the bottom of the screen in `lib/router_push.dart` (where the user selects a slot and sees killswitch status). This button is **always visible** (if the router is Merlin). Pressing it opens a new **dialogue** containing the watchdog configuration and status.

### 3.2 Watchdog Dialogue

The dialogue includes:

- **Current status**:
  - Enabled/Disabled state.
  - **“Last successful ping”** timestamp (fetched from router).
- **Configuration section** (editable):
  - **Check interval** (minutes, default 5).
  - **Primary ping IP** (required).
  - **Secondary ping IP** (required).
  - **Enable Email Alerts** (switch/checkbox).
    - If enabled, show: From, To, Subject, SMTP server (host:port), SMTP username, SMTP password (all required if email enabled).
- **Actions**:
  - **“Save & Enable”** – validates all inputs, performs a reachability check on both both IPs, and if successful, saves and deploys the watchdog.
  - **“Disable”** – removes scripts and cron, disables watchdog (leaves JFFS enabled).
  - **“Test Email”** – sends a test email using the current SMTP settings.
  - **“View Log”** – opens a view of `/tmp/watchdog_wgcN.log` (fetched via SSH).
- **Validation**: The dialogue validates all inputs (IP format, positive numbers, email format). Both primary and secondary IPs are required. The test email button validates SMTP connectivity by sending a test email.

Check that `jq` is installed via `which jq`, if it is not installed report it to the user and do not proceed with configuring the watchdog.

### 3.3 Main Screen Status Indicator

In the existing slot list (where the active WireGuard slot and killswitch status are shown), add a new label **“Watchdog active”** if a watchdog is enabled and running for that slot.

### 3.4 Interaction Flow

1. User opens the watchdog dialogue.
2. If watchdog is not yet configured, all fields show defaults; the “Enabled” status is “Disabled”.
3. User fills in configuration, saves. The app:
   - Via SSH: enables JFFS scripts (if not already), deploys watchdog scripts (with slot‑specific names), sets up **cron jobs** (both the watchdog check and log rotation).
   - Marks watchdog as enabled.
4. If already enabled, the dialogue shows current values; user can modify and save (which updates scripts and cron) or disable (removes all, but leaves JFFS enabled).
5. The “Test Email” button triggers an immediate test email (via a one‑off SSH command).
6. The “View Log” button fetches the log file content and displays it in a scrollable view.

### 3.5 Logging in Android App

All interactions with the router (SSH commands, script deployments, errors) are logged to the existing app’s log screen using the `_LogEntry` and `_logEntry` functions defined in `lib/main.dart`.

---

## 4. Technical Requirements

### 4.1 New Dart Module

- reading `router_push.dart` is a prerequisite step before generating any code, and the NVRAM section content must be quoted back in the implementation plan before proceeding.
- File: `lib/router_watchdog.dart`
- Exported API (all use the existing SSH connection, provided by `package:dartssh2/dartssh2.dart`):
  - `Future<bool> isMerlinRouter()`
  - `Future<void> enableJffsScripts()` – sets JFFS on if not already, does NOT disable.
  - `Future<void> deployWatchdogScripts(WatchdogConfig config)` – generates and uploads slot‑specific scripts.
  - `Future<void> startWatchdog(WatchdogConfig config)` – sets up cron jobs.
  - `Future<void> stopWatchdog(int slotIndex)` – removes scripts and cron.
  - `Future<WatchdogStatus> getWatchdogStatus(int slotIndex)` – returns enabled flag and last ping timestamp. isEnabled is determined by checking whether the slot-specific watchdog cron entry exists via `cru l | grep -q watchdog_wgcN`. It is not stored in NVRAM or local state.
  - `Future<String> getWatchdogLog(int slotIndex)` – returns content of log file.
  - `Future<void> testEmail(WatchdogConfig config)` – sends test email.
  - `Future<bool> pingHostViaWan(String ip)` - used during pre-save validation; executes `ping -c 1 -W 2 <ip>` with no interface binding
  - `Future<bool> pingHostViaVpn(String ip, int slotIndex)` - used internally by any test-from-app functionality; executes `ping -I wgcN -c 1 -W 2 <ip>`
- the app must fetch everything from the router's NVRAM every time the dialogue opens.
- the SSH client must be injectable for all exported functions to allow automated testing to occur.

#### 4.1.1 Class field lists

**`WatchdogConfig`:**

- `slotIndex` (int) -- the WireGuard slot number (1-5), used to name scripts and NVRAM keys
- `cronIntervalMinutes` (int, default 5)
- `primaryIp` (String, required)
- `secondaryIp` (String, required)
- `emailAlertsEnabled` (bool, default false)
- `emailFrom` (String, required if email enabled)
- `emailTo` (String, required if email enabled)
- `emailSubject` (String, required if email enabled)
- `smtpServer` (String, host:port, required if email enabled)
- `smtpUsername` (String, required if email enabled)
- `smtpPassword` (String, required if email enabled)

**`WatchdogStatus`:**

- `isEnabled` (bool)
- `lastSuccessfulPing` (DateTime?, null if no successful ping has been recorded yet)

### 4.2 Communication with Router (SSH)

- The app already has an open SSH session (established before reaching this screen) using `dartssh2`.
- Operations are performed by executing commands:
  - `nvram get <key>`, `nvram set <key>=<value>`, `nvram commit`
  - use `cat <<'EOF'` syntax to write files
  - `chmod +x /tmp/scripts/watchdog_*.sh` – **only** for the scripts we create (to avoid touching existing scripts).
  - `cru` to manage cron jobs.
  - `ping -c 1 -W 2 <ip>` (`pingHostViaWan`) and `ping -I wgcN -c 1 -W 2 <ip>` (`pingHostViaVpn`) for reachability checks
  - `cat /tmp/watchdog_wgcN.log` to fetch logs.
  - `cat /tmp/watchdog_last_ping_success_wgcN` to read status.

### 4.3 Router‑Side Bash Scripts

#### 4.3.1 NVRAM parameter storage

The script reads all configuration values from NVRAM at startup before doing anything else.

#### 4.3.2 `/tmp/scripts/watchdog_wgcN.sh` (slot‑specific)

Performs the ping test for the region, triggers reconfiguration if needed (with a **2‑minute retry** after a failed attempt), updates the status file, and sends email via `sendmail`. Reconfiguration logic:

- Read configuration from NVRAM (check interval, IPs, email settings, slot number).
- Use `ping -I wgcN -c 3 -W 2 $PRIMARY_IP` and, if that fails, `ping -I wgcN -c 3 -W 2 $SECONDARY_IP`. The `-I` flag forces the ping to use the VPN interface, ensuring the watchdog is monitoring VPN‑path reachability, not just WAN connectivity.
- If both fail and the retry timer (2 minutes since last attempt) has elapsed, perform reconfiguration:
  - Generate new private key: `wg genkey` and store in NVRAM (`nvram set wgcN_priv=...`).
  - Compute public key and store in NVRAM.
  - Fetch PIA server list (via `curl`), parse JSON, select the server with **lowest latency** (using `ping` to measure).
  - **Targeted Region Extraction**: The script must determine the target PIA region by reading the slot's description from NVRAM using `nvram get wgcN_desc` (which will return a string format like `"aus_melbourne"`).
  - **Scoped JSON Filtering**: When fetching the global PIA server list via `curl`, the script must use `jq` to filter the JSON payload _exclusively_ for endpoints matching that specific region identifier.
  - **Optimized Ping Sweep**: Because each region contains an isolated pool of only 1–3 servers, the script will loop through and execute a latency `ping` test _only_ against these 1–3 endpoints. It will then configure the interface using the single lowest-latency server from that specific region.
  - **Error Handling**: If `wgcN_desc` is empty, or if `jq` cannot find a matching region block in the PIA API response, the script must log the error to `/tmp/watchdog_wgcN.log` and abort the reconfiguration to prevent a broken fallback configuration.
  - Update NVRAM with new endpoint, port, DNS, allowed IPs, etc. The exact variables and values **must** follow the pattern in `lib/router_push.dart` (see the comment “// ── Step 4: Write new config to NVRAM”).
  - Commit NVRAM changes.
  - Apply the new config using `wg setconf wgcN /tmp/wgcN.conf` (the script creates a temporary config from NVRAM values). You must delete the /tmp/wgcN.conf file immediately after the wg setconf command executes.
  - Restart the interface using `service "start_wgc $slot"; service restart_vpnrouting0` (as per `router_push.dart`).
- If reconfiguration succeeds or fails, send email if enabled (one email per attempt).
- Update log and status file.
- Maintain a failure counter in `/tmp/watchdog_backoff_wgcN` by a two-line file: the first line is the failure counter (integer), the second line is the Unix epoch timestamp of the last reconfiguration attempt (integer seconds, from date +%s). If the file does not exist, both values are treated as zero.

##### 4.3.2.1 `sendmail`

- **Native Authenticated TLS Emailing**: Email alerts must be sent using the built-in BusyBox `sendmail` with its connection helper (`-H`) and authentication flags (`-am`, `-au`, `-ap`).
- **Connection Helper**: The script must dynamically construct the `sendmail` command snd send via implicit TLS:

        ```bash
        /usr/sbin/sendmail -H"exec openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt -connect $SMTP_HOST:$SMTP_PORT" -amLOGIN -au"$SMTP_USER" -ap"$SMTP_PASS" -f"$SMTP_FROM" "$SMTP_TO" < /tmp/mail.txt
        ```

- the `/tmp/mail.txt` is to be deleted immediately after piped into sendmail
- the `/tmp/mail.txt` is to be constructed with a valid RFC 822 syntax

#### 4.3.3 Cron Jobs

- Add a cron entry for the watchdog check: `*/<check_interval> * * * * /tmp/scripts/watchdog_wgcN.sh` using `cru`.
- Add a daily log rotation cron: `0 0 * * * mv /tmp/watchdog_wgcN.log /tmp/watchdog_wgcN.log.old && touch /tmp/watchdog_wgcN.log`.
- **Persistence across reboots**: use the `cru` utility to manage cron entries as `crontab` is stored in volatile memory (`/var/spool/cron/`).
  - `cru` commands must be added to the startup script `/tmp/scripts/services-start`.
  - When the watchdog is disabled, the corresponding `cru` entries must be removed (e.g., `cru d watchdog_wgcN`) and the startup script lines should be removed.
  - if `/tmp/scripts/services-start` does not exist, it is to be created.

- `cru` job IDs:
  - `cru` job identifiers must follow this naming scheme, where N is the slot number:
    - Watchdog check job: `watchdog_wgcN`
    - Log rotation job: `watchdog_log_rotate_wgcN`
    - Example for slot 1: `cru a watchdog_wgc1 "*/5 * * * *" /tmp/scripts/watchdog_wgc1.sh`
    - These identifiers must be used consistently for `cru a`, `cru d`, and the `cru l | grep` check in `getWatchdogStatus()`.

### 4.4 NVRAM Variables Used

The watchdog script will read and set the NVRAM variables for the active slot. The **exact list of variables and the values to set** must follow the existing implementation in `lib/router_push.dart` – specifically, look for the section marked `// ── Step 4: Write new config to NVRAM`. That code shows which `wgcN_*` keys are set and with what values. The watchdog script must replicate that logic.

For reference, the variables are:

- wgcN_addr=local IP address, from JSON payload
- wgcN_alive=keep alive (25)
- wgcN_desc=slot name eg "aus_melbourne"
- wgcN_dns=two DNS addresses, do not overwrite these as they are set by the user
- wgcN_enable=set to "1" to enable this slot
- wgcN_enforce=set to "1" to enable the killswitch
- wgcN_ep_addr=public IP address, from JSON payload
- wgcN_ep_addr_r=VPN endpoint address, dynamically set by the router, set this to null when creating the slot config
- wgcN_ep_port=VPN endpoint port, from JSON payload
- wgcN_fw=set to "1" to enable the firewall on this interface
- wgcN_mtu=maximum transmissoion unit (1420)
- wgcN_nat=set to "1" to enable network address translation
- wgcN_ppub=public key, from JSON payload
- wgcN_priv=private key, from "wg genkey"
- wgcN_psk=not used, set to null
- wgcN_rip=public IP address, dynamically set by the router, set this to null when creating the slot config
- wgcN_aips=allowed IP addresses (0.0.0.0/0)

The script must set them exactly as the app does, including any additional variables used by the Merlin firmware.

### 4.4.1 Watchdog NVRAM Variable names

Watchdog Namespace: all watchdog-specific configuration parameters must be saved using a uniform slot prefix to maintain an organized NVRAM environment
e.g., wgcN_wd_check_interval, wgcN_wd_primary_ip, wgcN_wd_secondary_ip, wgcN_wd_smtp_server, wgcN_wd_smtp_user, wgcN_wd_smtp_pass etc.

### 4.5 Retry Mechanism

To avoid flapping when the WAN is down, the watchdog will:

- Maintain a failure counter in `/tmp/watchdog_backoff_wgcN` by a two-line file: the first line is the failure counter (integer), the second line is the Unix epoch timestamp of the last reconfiguration attempt (integer seconds, from date +%s). If the file does not exist, both values are treated as zero.
- On a failed ping attempt, increment the counter and write a timestamp to `/tmp/watchdog_backoff_wgcN`.
- Reconfigure on the first failure once the cooldown has passed.
- On a successful ping, reset the counter to 0.
- After a reconfiguration attempt (success or failure), reset the timer and allow another attempt only after 2 minutes.

Emails are sent **only** when a reconfiguration is attempted, not on every ping failure.

---

## 5. Integration Points with Existing App

### 5.1 `router_push.dart` Modifications

- Add the **“Watchdog”** button at the bottom.
- In the existing slot status area, add **“Watchdog active”** label when watchdog is enabled for that slot.
- The button opens a new dialogue (using `showDialog` or similar) that contains the watchdog UI.

### 5.2 Existing SSH Client

- The app uses `package:dartssh2/dartssh2.dart` for SSH connectivity. Extend the existing wrapper to provide methods for executing commands, reading/writing files via redirection, etc.

### 5.3 Persistence

- the Android app's UI state is ephemeral, re-fetch from NVRAM each time the watchdog dialogue opens

### 5.4 Logging

- Use the existing logging system: `_LogEntry` and `_logEntry` in `lib/main.dart` to record all SSH commands, outputs, and errors.

---

## 6. Testing Requirements

### 6.1 Unit Tests (Dart)

- Test the NVRAM key-to-field mapping logic
- Script generation functions – verify correct Bash code is produced (slot‑specific names, correct NVRAM variable usage, retry logic).
- Logic for cron management (building the cru line for both jobs).

### 6.2 Widget Tests

- Test that the “Watchdog” button appears only when router is Merlin.
- Test that the dialogue shows correct status and fields.
- Test validation (invalid IPs, negative check interval, missing required fields, both IPs required).
- Test “Test Email” button interaction.

### 6.3 Integration Tests (Mock SSH)

- Simulate SSH responses to test deployment, enable/disable, status fetch, log fetch.
- Test error handling (SSH failures, command failures).

### 6.4 Code Coverage Goal

- ≥ 95% for `router_watchdog.dart` and related helpers.

---

## 7. Security Considerations

- The watchdog script runs as root – ensure it does not accept external input or use `eval` on unsanitized data.
- All configuration variables (including private key, SMTP password) are stored **exclusively in NVRAM** on the router. They are never persisted in files on the router or on the device.
- While the Dart module is executing on the user’s device, **user‑supplied configuration data must only be stored in volatile Android memory** (e.g., in‑memory state), never written to the device’s filesystem.
- The SSH connection uses the app’s existing authentication (already secured).
- NVRAM is protected by the router’s own permissions; only root can read/write.

---

## 8. Deliverables

- `lib/router_watchdog.dart` – complete Dart module.
- Modifications to `router_push.dart` (button, status label, dialogue).
- Unit and widget tests.
- Embedded Bash script templates (as Dart strings) for deployment.
- Integration with existing logging system.

---

## 9. Acceptance Criteria

- [ ] The “Watchdog” button appears only when router is Merlin.
- [ ] Clicking the button opens a dialogue showing status, configuration, and actions.
- [ ] The dialogue validates user inputs (check interval, IPs, email fields) – both primary and secondary IPs are required.
- [ ] It performs a reachability check on both both ping IPs and advises if either is unreachable.
- [ ] It can send a test email with subject “config test”.
- [ ] Saving enables JFFS scripts (but does not disable on disable), deploys slot‑specific watchdog scripts, and sets up cron jobs (watchdog + log rotation).
- [ ] Disabling removes scripts and cron but leaves JFFS enabled.
- [ ] Status (last successful ping timestamp) is shown.
- [ ] The log file (`/tmp/watchdog_wgcN.log`) can be viewed within the app.
- [ ] The main screen shows “Watchdog active” label for slots with active watchdog.
- [ ] All SSH interactions are logged to the app’s log screen using `_logEntry`.
- [ ] Retry mechanism uses a 2‑minute delay between reconfiguration attempts; emails are sent only on reconfiguration attempts.
- [ ] All configuration is stored in NVRAM, not in files; user‑supplied data in the app is kept only in volatile memory.
- [ ] The script uses the exact NVRAM variables and values as defined in `router_push.dart` (the “Write new config to NVRAM” section).
- [ ] Only our own scripts (`watchdog_*.sh`) are made executable; existing scripts are untouched.
- [ ] Coverage >95% for new code.

---

_End of requirements document._

## Prompt

Read .claude/context.md to understand the app, then read .claude/watchdog.md in full. Before writing any code, open lib/router_push.dart and quote back the complete content of the // ── Step 4: Write new config to NVRAM section so I can verify you have read it correctly. Then produce an implementation plan covering module structure, Bash script templates, test strategy, and the integration points in router_push.dart. Wait for my approval before writing any code.

## Clarifications & new requirements for the plan

1. Store PIA credentials in NVRAM variables pia_wg_cfga_user pia_wg_cfga_password.
2. Once the user taps "Push to router", the 180 second wipe time is disabled.
3. Use the native logger function provided by the router (eg 'logger -t pia-wg-cfga "insert log message contents here"') to log activity caused by the scripts deployed to the router. This will include but not be limited to reconfiguration of a wireguard slot, if the ping host cannot be reached, an email is sent, when scripts are deployed and when scripts are deleted. Any errors generated by any of the scripts are to be sent to the router log.
4. The DNS addresses for the new slot config are obtained from the existing wgcN_dns values.
5. Delete all created files if watchdog is disabled.
