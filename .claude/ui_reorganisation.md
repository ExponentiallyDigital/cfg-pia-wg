# User interface reorganisation – architecture & requirements

## 1. Overview

This document defines the complete requirements for reorganising the user interface in the `cfg-pia-wg` Flutter app. The new UI will be more logical and easier to use splitting functions to defined user workflows.

Claude Code **must** review all existing modules in `./lib/` to understand how the app currently allows the user to execute the app's functions and to understand the code and logic that is invoked.

---

## 2. Functional Requirements

### 2.1 User interface reorganisation

Create a new main opening screen. On this main screen create these five buttons:

- "Generate standalone PIA WireGuard configuration"
- "Generate/modify and push PIA WireGuard configuration to router\*"
- "Watchdog management\*"
- "View app log"
- "Close app"

After the last menu button, add a vertical spacing widget that is equivalent to two lines of the default body text height (e.g., `height: 2 * Theme.of(context).textTheme.bodyMedium!.fontSize!`). On the line immediately below this spacer, add this text "\* requires SSH connectivity to an Asus router."

Each selected button will open in a new screen, not a modal window, except the "Close app" button which will immediately close the app.

Retain the existing header currently created by `Widget build` in `lib/main.dart` (this is two lines of formatted text), and will display at the top of every screen. The header must remain in a static location.

While the user is engaging with any screen, immediately show any errors. Put these error messages in an modal window with an "OK" button to close that modal window. For input errors (missing required fields), show all errors in the one dialogue box and for system errors only display one error at a time.

A hamburger menu will always be shown in the top left corner of each main menu screen and subsequent windows that open from those screens. See "3.1 Hamburger menu". It will be displayed on the main menu screen.

On each of the four screens provide a "CLOSE" button that returns the user to the main menu. When navigating via the hamburger menu, do not clear the route history stack down to the root main menu. indefinite stack growth is intentional to allow navigation tgo occur.

#### 2.1.1 "Generate standalone PIA WireGuard configuration"

- Runs the existing code which provides region selection, requests a PIA username, PIA password, and DNS servers. Once that information has been given, a button marked "GENERATE CONFIG" changes from grey to green and then executes the existing code which connects to PIA and gets a new WireGuard configuration. Reuse existing field validations.
- If the PIA username and PIA password have already been provided in "Generate/modify and push PIA WireGuard configuration to router" or in "Watchdog management" then it will be prefilled from device memory.
- Once a WireGuard configuration has been generated using the existing code, then on this screen display the generated config in a text box. The content is read only but can be selected. Underneath that make two buttons visible: "COPY" and "SHARE / SAVE", these buttons will invoke the existing logic.
- Per the existing code, the "SHARE / SAVE" button executes `_shareConfig` in `lib/main.dart`
- Remove the existing timer that clears credentials and config after 180 seconds of inactivity.
- If the "COPY" button is selected, retain the existing 60 second timer that clears the clipboard.
- If the user stays on this screen or exits it, then the clear clipboard timer will continue to run and the clipboard cleared when the timer expires.

#### 2.1.2 "Generate/modify and push PIA WireGuard configuration to router"

- Per the existing code allow region selection, request a PIA username, PIA password, DNS servers, router IP, SSH username, and password. If this information has already been provided in "Generate standalone PIA WireGuard configuration" or in "Watchdog management" then it will be prefilled from device memory.
- Once that information has been provided, a button marked "GENERATE CONFIG" changes from grey to green and then executes the existing code which connects to PIA and gets a new WireGuard configuration.
- Once a WireGuard configuration has been generated using the existing code, then the user is presented with the existing screen (but now parameterised) which allows selecting a slot to write the configuration to, this screen, as before, is a modal window showing on top of the prior window. As before, this screen will show if a slot is already active, has a kill switch enabled, and has a watchdog. In this screen the user can select a "SAVE" button, the button is visible but greyed out until a slot is selected. This button was previously called "CONFIRM WRITE TO ROUTER".
- When the "SAVE" button is pressed, the configuration is written to the selected slot using the existing code.
- Present a "DELETE" button which clears the selected slot’s configuration on the router. A confirmation dialog must be shown before deletion. The DELETE button is always active when a slot is selected which has a description, the description is a region name.
- Present a "DISABLE" button, this button executes `nvram set wgcN_enforce=0` and `nvram set wgcN_enable=0` (where `N` is the selected slot number, 1-5) then commits to NVRAM for the chosen slot. The DISABLE button is always active when a slot is selected which has a description, the description is a region name.
- Present an "ENABLE" button, this button executes `nvram set wgcN_enforce=1` and `nvram set wgcN_enable=1` (where `N` is the selected slot number, 1-5) then commits to NVRAM for the chosen slot. The ENABLE button is always active when a slot is selected which has a description, the description is a region name.
- After the "SAVE", "DELETE", "DISABLE", or "ENABLE" buttons have been pressed refresh the current screen which is to be updated with al wgc1-5 slot configurations showing if a slot is active, has a kill switch enabled, and/or has a watchdog enabled.
- Note: setting the same NVRAM value twice is harmless, so no state-checking is required.

#### 2.1.3 "Watchdog management"

- This screen will ask for the router IP address, SSH username, and SSH password, if this information has already been provided in "Generate standalone PIA WireGuard configuration" or in "Generate/modify and push PIA WireGuard configuration to router", then it will be prefilled from device memory excepting that the router address, SSH username and password are not captured in "Generate standalone PIA WireGuard configuration".
- Underneath add a button marked "CONNECT TO ROUTER" which invokes the existing code, similar to "Generate/modify and push PIA WireGuard configuration to router" which gets the slots and displays them and the slot details in an modal window. The button will be greyed out until required fields are completed.
- In that modal window which displays the slots, show "ENABLE", "EDIT", "DISABLE", "DELETE", and "VIEW WATCHDOG LOG" buttons. All of these buttons will be greyed out until a slot has been selected.
- The "ENABLE" button will only be selectable (not greyed out) if a slot is selected and its watchdog is currently disabled.
- The "EDIT" button will reuse the contents of the pre-existing screen which allows completing the required watchdog parameters eg. display the watchdog status and last successful ping timestamp, the check interval, primary and secondary ping IP addresses, and the slider to enable/disable email alerts. Prefill the PIA username and PIA password if they are in device memory.
- With the "EDIT" window, when checking the fields "Primary ping IP" and "Secondary ping IP" perform an ICMP ping to each host and if either return no response open a dialogue box and advise but allow saving. Reuse/extend the existing logic in `./lib/router_watchdog.dart` for this but ensure it is performed on the router and uses the WAN interface. The pings are executed when the user attempts to save the edit parameters.
- With the "EDIT" window, if a watchdog is not active on the chosen slot, and if the selected slot is empty, then the user will be presented with the region selection list in an modal window to choose a region. This region name is passed as `DESC` to `const String _kWatchdogScriptTemplate` to create the watchdog.
- With the "EDIT" window, if the watchdog is not active but the slot is not empty then the user will be presented with the region selection list in an modal window to choose a region. This region name is passed as `DESC` to `const String _kWatchdogScriptTemplate` to create the watchdog. In this situation the user should first, before the region list is presented, be warned that the current slot configuration will be overwritten and they will be given the option to continue or cancel the operation.
- With the "EDIT" window, you cannot have an active watchdog with an empty slot.
- "EDIT" opens a modal window. If an error fires while EDIT is open, the error should appear on top of EDIT.
- The "DISABLE" button will call the existing logic to disable the watchdog.
- The "VIEW WATCHDOG LOG" button will reuse the existing logic to display the watchdog log stored on the router.
- "DELETE" removes the watchdog script and clears the slot’s configuration, it also deletes the configuration from the router. A confirmation dialog must be shown before deletion.
- After the "DISABLE", "EDIT", or "DELETE" buttons have been pressed refresh the current screen which is to be updated with al wgc1-5 slot configurations showing if a slot is active, has a kill switch enabled, and/or has a watchdog enabled.
- Button display logic:
  - DISABLE is active only if the watchdog is currently enabled
  - EDIT is always active when a slot is selected
  - DELETE is always active when a slot is selected
  - VIEW WATCHDOG LOG is active only if a watchdog exists on the slot

#### 2.1.4 "View log"

- This is as per the existing logic: a scrollable display of the application log.
- Retain the existing "CLEAR LOG" button that erases the in-memory application log from the Android device.
- This opens as a new screen, not an modal window.

## 3. UI Style & Security Requirements

- Be consistent across all UI elements and screens with the colour scheme and placement of windows, buttons, text input fields, and dialogue boxes including buttons which are not able to be selected because required information has not yet been given.
- At no time will the SSH username, password, or IP address be written to the device, as before it is retained in memory and wiped when the application is exited or killed.
- The PIA username and password are similarly never written to device storage and only retained in memory.
- Avoid creating new application code, instead reuse the existing code and logic where ever possible.
- If existing code must be altered to accommodate the new UI then modify it sparingly.
- If there is 10 minutes of inactivity (no tap, scroll, or other interaction) by the user then all credentials and WireGuard configuration is to be wiped from memory, including the clipboard (which has a separate 60 second clear timer so it should also be cleared), and noted to the application log automatically and redirect the user back to the main opening screen, any open modals are closed. Use a global `GestureDetector` or `Listener` wrapped around the main app widget. A countdown timer must be shown in the top right hand corner of all screens, this countdown timer is not visible when modal windows are open.
- If the "Close app" menu option is selected then all credentials and WireGuard configuration are to be wiped from memory and the application closed.
- If the Android "back" button is pressed on the main menu, back exits; on other screens, back goes to prior window (or closes modals first). If the back button exits the application, credentails are wiped before exiting.
- Where necessary, refactor existing build methods into reusable widgets and move state logic into separate controllers/services, minimising changes to core functionality. Examine the existing code and match the predominant pattern already in use.
- Parameterise the slot display modal (e.g., passing a mode) in 2.1.2 and 2.1.3 to show appropriate buttons and actions, rather than duplicating code.
- Only one error modal window is shown at a time (dismiss the previous before showing a new one).
- If the SSH connection is terminated while interacting with the application, open a new connection using the preexisting credentials.
- If/when the application is closed, the clipboard must also be cleared.

### 3.1 Hamburger menu

This enables fast navigation between different parts of the application eg. when using the "Watchdog management" screen you can quickly switch to the application log and return to the "Watchdog management" screen.

If the user selects the current screen from the hamburger menu, do nothing. It intentional that the hamburger menu is shown on the main window, this is for UI consistency.

The hambuger menu is visible and selectable when modal windows are shown. If a user navigates away from a modal via the hamburger while a modal is open, the user can return to the modal window via the Andoid back button.

It will contain the following entries:

- "Generate standalone PIA WireGuard configuration" - see 2.1.1 "Generate standalone PIA WireGuard configuration"
- "Generate/modify and push PIA WireGuard configuration to router" - see 2.1.2 "Generate/modify and push PIA WireGuard configuration to router"
- "Watchdog management" - see 2.1.3 "Watchdog management"
- "View app log" - see 2.1.4 "View log"
- "Close app" - all credentials and WireGuard configuration is to be wiped from memory, then the application is closed

### 3.2 Parameterised slot modal

Show these button for "Generate/modify and push PIA WireGuard configuration to router":

- SAVE
- DELETE
- DISABLE
- ENABLE

Show these buttons for "Watchdog management":

- DISABLE
- EDIT
- DELETE
- VIEW WATCHDOG LOG

## 4. Testing Requirements

- All existing files in `./test` must be updated to account for the UI changes.
- New screens must have tests created for them.
- Generate comprehensive widget tests for all new screens, ensuring all UI elements, state changes, timers, and error modals are fully covered. Aim for 90% coverage.

## 5. Deliverables & Acceptance Criteria

- The UI is updated per this specification document.
- All new or modified code passes analyze and builds without error.
- All new/modified tests pass.

## 6. Glossary

- `device memory` this is the Android device on which the cfg-pia-wg aplication is executing
- `slot` this is the WireGuard configuration entry `wgcN` where `N` is 1-5

_End of requirements document._
