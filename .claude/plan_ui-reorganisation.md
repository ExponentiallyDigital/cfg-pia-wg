# User interface reorganisation – architecture & requirements

## 1. Overview

This document defines the complete requirements for reorganising the user interface in the `cfg-pia-wg` Flutter app. The new UI will be more logical and easier to use splitting functions to defined user workflows.

Claude Code **must** review all existing modules in `./lib/` to understand how the app currently allows the user to execute the app's functions and to understand the code and logic that is invoked.

---

## 2. Functional Requirements

### 2.1 User interface reorganisation

Create a new main opening screen. On this main screen create these five buttons:

- "Generate standalone PIA WireGuard configuration"
- "Manage router PIA WireGuard configuration\*"
- "VPN watchdog management\*"
- "View app log"
- "Close app"

After the last menu button, add a vertical spacing widget that is equivalent to two lines of the default body text height (e.g., `height: 2 * Theme.of(context).textTheme.bodyMedium!.fontSize!`). On the line immediately below this spacer, add this text "\* requires SSH connectivity to an ASUS router."

Each selected button will open in a new screen, not a modal window, except the "Close app" button which will immediately close the app.

Retain the existing header currently created by `Widget build` in `lib/main.dart` (this is two lines of formatted text), and will display at the top of every screen. The header must remain in a static location.

While the user is engaging with any screen, immediately show any errors. Put these error messages in a modal window with an "OK" button to close that modal window. For input errors (missing required fields), show all errors in the one dialogue box and for system errors only display one error at a time.

A hamburger menu will always be shown in the top left corner of each main menu screen and subsequent windows that open from those screens. See "3.1 Hamburger menu". It will be displayed on the main menu screen.

On each of the four screens provide a "CLOSE" button that returns the user to the main menu. When navigating via the hamburger menu, do not clear the route history stack down to the root main menu. Indefinite stack growth is intentional to allow navigation to occur.

#### 2.1.1 "Generate standalone PIA WireGuard configuration"

- Runs the existing code which provides region selection, requests a PIA username, PIA password, and DNS servers. Once that information has been given, a button marked "GENERATE CONFIG" changes from grey to green and then executes the existing code which connects to PIA and gets a new WireGuard configuration. Reuse existing field validations.
- If the PIA username and PIA password have already been provided in "Manage router PIA WireGuard configuration" or in "VPN watchdog management" then it will be prefilled from device memory.
- Once a WireGuard configuration has been generated using the existing code, then on this screen display the generated config in a text box. The content is read only but can be selected. Underneath that make two buttons visible: "COPY" and "SHARE / SAVE", these buttons will invoke the existing logic.
- The "SHARE / SAVE" button currently executes `_shareConfig` in `lib/main.dart`. During refactoring the UI, you are allowed to move/rename this private method's location.
- Remove the existing timer that clears credentials and config after 180 seconds of inactivity.
- If the "COPY" button is selected, retain the existing 60 second timer that clears the clipboard.
- If the user stays on this screen or exits it, then the clear clipboard timer will continue to run and the clipboard cleared when the timer expires.

#### 2.1.2 "Manage router PIA WireGuard configuration"

- Request the router IP, SSH username, and password. If this information has already been provided in "Generate standalone PIA WireGuard configuration" or in "VPN watchdog management" then it will be prefilled from device memory.
- Once that information has been provided, present the new parameterised slot modal, see 3.2 Parameterised slot modal. This screen allows selecting a slot and displays wgc1-5 slot configurations showing if a slot is active, has a kill switch enabled, and/or has a watchdog enabled. This is a modal window showing on top of the prior window. In this screen the user can select several buttons.
- When the "CREATE" button is pressed, always present the region list (this list of regions can be obtained prior to logging in to PIA servers) then request the PIA username, PIA password, and DNS addresses (these parameters are required to authenticate and generate the new WireGuard configuration), if this information has already been provided then it is prefilled. After this information is provided, the existing code executes to generate a WireGuard configuration and save it to the associated slot's NVRAM, the slot is not set to active though. This button was previously called "CONFIRM WRITE TO ROUTER".
- If CREATE is attempted on a slot which has a pre-existing configuration (this is determined by it having a description, the description is a region name), prompt the user to overwrite or cancel the operation. Provide the slot number and description in that prompt so that the user knows what is being overwritten.
- Once the slot has been created, advise the user in a popup that it has been created and remind them to enable it via the "ENABLE" button.
- Present an "ENABLE" button, this button executes `nvram set wgcN_enable=1` (where `N` is the selected slot number, 1-5) then commits this to NVRAM for the chosen slot. The ENABLE button is always active when a slot is selected which has a description, the description is a region name.
- When the "ENABLE" button is pressed and while enabling, check that the relevant interface comes up, this checks that a configuration has not expired. If it has expired, advise the user in a popup and do not set the enable NVRAM flag for this slot leaving it unchanged.
- When checking that the interface is up, use an ICMP ping (via the slot interface, not the WAN interface) with a five second timeout to both IP addresses stored in `wgcN_wd_primary_ip` and `wgcN_wd_secondary_ip` (where `N` is the slot number), these IP addresses are set when a watchdog is enabled for a slot. If these nvram parameters do not exist, prompt the user for these values. Display `8.8.8.8` and `1.1.1.1` as defaults that can be changed by the user and store them in `wgcN_wd_primary_ip` and `wgcN_wd_secondary_ip` (where `N` is the slot number). If either target fails to respond, alert the user and do not allow the slot to be enabled.
- Present an "EDIT" button. This button allows setting all WireGuard parameters for the slot's interface. See 3.3 Slot parameters for values and descriptions to be shown and set. All user editable fields as described in 3.3 Slot parameters, must be set before saving is allowed. If the user edits slot parameters, refresh the slot modal display.
- Present a "DISABLE" button, this button executes `nvram set wgcN_enable=0` (where `N` is the selected slot number, 1-5) then commits to NVRAM for the chosen slot. The DISABLE button is always active when a slot is selected which has a description, the description is a region name.
- Present a "DELETE" button which clears the selected slot’s configuration on the router. A confirmation dialog must be shown before deletion. The DELETE button is always active when a slot is selected which has a description, the description is a region name.
- After the "CREATE", "ENABLE", "DISABLE", or "DELETE", buttons have been pressed and the relevant code path has completed, refresh the current screen which is to be updated with all wgc1-5 slot configurations showing if a slot is active, has a kill switch enabled, and/or has a watchdog enabled. While processing the relevant code path, display an indicator icon over the slot modal showing processing activity is occurring.
- Note: setting the same NVRAM value twice is harmless, so no state-checking is required.

#### 2.1.3 "VPN watchdog management"

- This screen will ask for the router IP address, SSH username, and SSH password, if this information has already been provided in "Generate standalone PIA WireGuard configuration" or in "Manage router PIA WireGuard configuration", then it will be prefilled from device memory excepting that the router address, SSH username and password are not captured in "Generate standalone PIA WireGuard configuration".
- Underneath add a button marked "CONNECT TO ROUTER" which invokes the existing code, similar to "Manage router PIA WireGuard configuration" which gets the slots and displays them and the slot details in a modal window. The button will be greyed out until required fields are completed.
- In that modal window which displays the slots, show "ENABLE", "EDIT", "DISABLE", "DELETE", and "VIEW WATCHDOG LOG" buttons. All of these buttons will be greyed out until a slot has been selected and the "ENABLE" button will only be selectable (not greyed out) if a slot is selected and its watchdog is currently disabled.
- The "ENABLE" button will use the existing code/logic to deploy the watchdog shell script and cron/cru entries on the selected slot. NB do not increase the size of the shell script as there is a heredoc size limitation.
- The "EDIT" button will reuse the contents of the pre-existing screen which allows completing the required watchdog parameters eg. display the watchdog status and last successful ping timestamp, the check interval, primary and secondary ping IP addresses, and the slider to enable/disable email alerts. Prefill the PIA username and PIA password if they are in device memory.
- With the "EDIT" window, when checking the fields "Primary ping IP" and "Secondary ping IP" perform an ICMP ping to each host and if either return no response open a dialogue box and advise but allow saving. Reuse/extend the existing logic in `./lib/router_watchdog.dart` for this but ensure it is performed on the router and uses the WAN interface. The pings are executed when the user attempts to save the edit parameters.
- With the "EDIT" window, if a watchdog is not active on the chosen slot, and if the selected slot is empty, then the user will be presented with the region selection list in a modal window to choose a region. This region name is passed as `DESC` to `const String _kWatchdogScriptTemplate` to create the watchdog.
- With the "EDIT" window, if the watchdog is not active but the slot is not empty then the user will be presented with the region selection list in a modal window to choose a region. This region name is passed as `DESC` to `const String _kWatchdogScriptTemplate` to create the watchdog. In this situation the user should first, before the region list is presented, be warned that the current slot configuration will be overwritten and they will be given the option to continue or cancel the operation.
- With the "EDIT" window, you cannot have an active watchdog with an empty slot.
- "EDIT" opens a modal window. If an error fires while EDIT is open, the error should appear on top of EDIT.
- The "DISABLE" button will call the existing logic to disable the watchdog.
- The "VIEW WATCHDOG LOG" button will reuse the existing logic to display the watchdog log stored on the router.
- "DELETE" removes the watchdog script and clears the slot’s configuration, it also deletes the configuration from the router. A confirmation dialog must be shown before deletion.
- After the "DISABLE", "ENABLE", "EDIT", or "DELETE" buttons have been pressed refresh the current screen which is to be updated with all wgc1-5 slot configurations showing if a slot is active, has a kill switch enabled, and/or has a watchdog enabled.
- Button display logic:
  - ENABLE is active only if a slot is selected and its watchdog is currently disabled.
  - DISABLE is active only if a slot is selected and the watchdog is currently enabled.
  - EDIT is always active when a slot is selected.
  - DELETE is always active when a slot is selected.
  - VIEW WATCHDOG LOG is active only if a watchdog exists on the slot.

#### 2.1.4 "View log"

- This is as per the existing logic: a scrollable display of the application log.
- Retain the existing "CLEAR LOG" button that erases the in-memory application log from the Android device.
- This opens as a new screen, not a modal window.

## 3. UI Style & Security Requirements

- Be consistent across all UI elements and screens with the colour scheme and placement of windows, buttons, text input fields, and dialogue boxes including buttons which are not able to be selected because required information has not yet been given.
- At no time will the SSH username, password, or IP address be written to the device, as before it is retained in memory and wiped when the application is exited or killed.
- The PIA username and password are similarly never written to device storage and only retained in memory.
- You are explicitly permitted to restructure files and modules where the result is clearer, renaming functions and classes to reflect purpose, and rewriting build methods into separate widgets — provided the underlying logic is preserved unchanged.
- Where logic is reused unchanged, prefer extracting it rather than duplicating it.
- If there is 10 minutes of inactivity (no tap, scroll, or other interaction) by the user then all credentials and WireGuard configuration is to be wiped from memory, including the clipboard (which has a separate 60 second clear timer so it should also be cleared), and noted to the application log automatically and redirect the user back to the main opening screen, any open modals are closed. Use a global `GestureDetector` or `Listener` wrapped around the main app widget. A countdown timer must be shown in the top right hand corner of all screens, this countdown timer is not visible when modal windows are open.
- If the "Close app" menu option is selected then all credentials and WireGuard configuration are to be wiped from memory and the application closed.
- If the Android "back" button is pressed on the main menu, back exits; on other screens, back goes to prior window (or closes modals first). If the back button exits the application, credentials are wiped before exiting.
- Where necessary, refactor existing build methods into reusable widgets and move state logic into separate controllers/services, minimising changes to core functionality. Examine the existing code and match the predominant pattern already in use.
- When writing via `heredoc`, create a 30 second timeout and throw an error as a popup (and log it to the application log) if the timeout is reached, include details in the popup to assist with troubleshooting.
- All SSH communication must be error checked. If errors are thrown, advise the user via a popup (and log it to the application log).
- Parameterise the slot display modal (e.g., passing a mode) in 2.1.2 and 2.1.3 to show appropriate buttons and actions, rather than duplicating code.
- Only one error modal window is shown at a time (dismiss the previous before showing a new one).
- If the SSH connection is terminated while interacting with the application, open a new connection using the preexisting credentials.
- If/when the application is closed, the clipboard must also be cleared.

### 3.1 Hamburger menu

This enables fast navigation between different parts of the application eg. when using the "VPN watchdog management" screen you can quickly switch to the application log and return to the "VPN watchdog management" screen.

If the user selects the current screen from the hamburger menu, do nothing. It is intentional that the hamburger menu is shown on the main window, this is for UI consistency.

The hamburger menu is visible and selectable when modal windows are shown. If a user navigates away from a modal via the hamburger while a modal is open, the user can return to the modal window via the Android back button.

It will contain the following entries:

- "Generate standalone PIA WireGuard configuration" - see 2.1.1 "Generate standalone PIA WireGuard configuration"
- "Manage router PIA WireGuard configuration" - see 2.1.2 "Manage router PIA WireGuard configuration"
- "VPN watchdog management" - see 2.1.3 "VPN watchdog management"
- "View app log" - see 2.1.4 "View log"
- "Close app" - all credentials and WireGuard configuration is to be wiped from memory, then the application is closed

### 3.2 Parameterised slot modal

Show these button for "Manage router PIA WireGuard configuration" and in this sequence:

- CREATE
- ENABLE
- EDIT
- DISABLE
- DELETE

Show these buttons for "VPN watchdog management" and in this sequence:

- ENABLE
- EDIT
- DISABLE
- DELETE
- VIEW WATCHDOG LOG

### 3.3 Slot parameters

These are the descriptions and values that a WireGuard client slot NVRAM entry may take:

- **`wgcN_addr`** - This is the local tunnel IP address assigned to the router by the VPN server in CIDR notation (e.g., `10.x.x.x/32`). This field is user editable.
- **`wgcN_alive`** - The persistent keepalive interval, set to 25 (seconds) by default. This field is user editable.
- **`wgcN_desc`** - The slot's PIA region name. This must match the actual PIA region name for the watchdog function to operate. _(include that as a comment next to this field)_. This field is user editable.
- **`wgcN_dns`** - The two DNS servers to use. Optional, but defaults to `"9.9.9.9, 149.112.112.112"`. This field is user editable.
- **`wgcN_enable`** - When set to `1` this enables this slot; when set to `0` this slot is disabled. This field is not user editable and its value is set by the ENABLE and DISABLE buttons in 2.1.2.
- **`wgcN_enforce`** - When set to `1` this enables the killswitch on this slot; when set to `0` it is disabled. The killswitch blocks routed clients if the tunnel goes down. This field is user editable.
- **`wgcN_ep_addr`** - The domain name (FQDN) or public IP address of the remote PIA WireGuard server (peer endpoint) you are connecting to. This field is user editable.
- **`wgcN_ep_addr_r`** - If `wgcN_ep_addr` contains either a DNS name or an IP address, this is the resolved numeric IP address; if `wgcN_ep_addr` contains a direct IP address, this field will hold an identical value. This field is not user editable and is set when the interface is initialised.
- **`wgcN_ep_port`** - The endpoint port, defaulting to `1337` for PIA. This field is user editable.
- **`wgcN_fw`** - Set to `1` to enable the inbound firewall on this slot; set to `0` to disable it. This field is user editable.
- **`wgcN_mtu`** - The MTU (Maximum Transmission Unit), set to `1420` by default. This field is user editable.
- **`wgcN_nat`** - Set to `1` to enable network address translation (NAT); set to `0` to disable NAT. This field is user editable.
- **`wgcN_ppub`** - The PIA VPN server public key. This field is user editable.
- **`wgcN_priv`** - The PIA user's private key. This field should be rendered as an obscured input (like a password field) with a show/hide toggle, consistent with how SSH and PIA credentials are handled elsewhere in the app. This field is user editable.
- **`wgcN_psk`** - This value is not used by PIA and is read-only for the user (reserved for a preshared key). This field is not user editable.
- **`wgcN_rip`** - Stores the router's current external public IP address as seen by the internet. This field is not user editable.
- **`wgcN_aips`** - The allowed IP addresses, defaults to `0.0.0.0/0`. This field is user editable.
- **`wgcN_wd_primary_ip`** - This is managed by the application (not free-form user fields) and used by both the ENABLE check in 2.1.2 and the watchdog ping check in 2.1.3.
- **`wgcN_wd_secondary_ip`** - This is managed by the application (not free-form user fields) and used by both the ENABLE check in 2.1.2 and the watchdog ping check in 2.1.3.

In the above, `N` refers to the slot number (1-5).

## 4. Testing Requirements

- All existing files in `./test` must be updated to account for the UI changes.
- New screens must have tests created for them.
- Generate comprehensive widget tests for all new screens, ensuring all UI elements, state changes, timers, and error modals are fully covered. Aim for 90% coverage.

## 5. Deliverables & Acceptance Criteria

- The UI is updated per this specification document.
- All new or modified code passes analyze and builds without error.
- All new/modified tests pass.
- `.claude/CONTEXT.md` is updated to account for the new UI.

## 6. Glossary

- `device memory` this is the Android device on which the cfg-pia-wg application is executing.
- `slot` this is the WireGuard configuration entry `wgcN` where `N` is 1-5.

_End of requirements document._

## Prompt used

Read .claude/context.md to understand the app, then read `.claude/ui_reorganisation.md` in full. Before writing any code, open and examine all existing modules in `lib` and tests in `test`. Then produce an implementation plan for the entire scope defined in `.claude/ui_reorganisation.md`. Wait for my approval before writing any code.

Clarifications needed:

1. **Watchdog screen — EDIT saves, ENABLE deploys.** EDIT writes watchdog params + region (`wgcN_desc`)
   to NVRAM and runs the pre-save WAN ping warning, but does **not** deploy. The slot-modal ENABLE
   button deploys the script + cron (`startWatchdog`) from saved NVRAM config + in-memory PIA creds.
   DISABLE removes (`stopWatchdog`). A **new region picker inside the EDIT dialog** is added (spec 2.1.3).
2. **Manage-router ENABLE — revert on failed check.** Set `enable=1` + start interface, wait until it
   appears in `wg show interfaces`, ping both `wgcN_wd_*_ip` via the slot interface (5s). On any
   failure: `enable=0` (revert), stop interface, alert — persisted flag left unchanged.
3. **"Close app" (hamburger entry) wipes clipboard + all in-memory credentials/config, then exits.**
   Confirmed. The separate per-screen **CLOSE** button "returns to the main menu" — implemented as
   pushing a fresh `MainMenuScreen` (consistent with the "stack growth is intentional" rule).
   _(Flagged for review — change to pop-to-menu if that was the intent.)_
