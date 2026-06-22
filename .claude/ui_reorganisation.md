# User interface reorganisation – architecture & requirements

## 1. Overview

This document defines the complete requirements for reorganising the user interface in the `cfg-pia-wg` Flutter app. The new UI will be more logical and easier to use splitting functions to defined user workflows.

Claude Code **must** review all existing modules in `../lib/` to understand how the app currently allows the user to execute the app's functions.

---

## 2. Functional Requirements

### 2.1 User interface reorganisation

Create a new main opening screen. On this main screen create these buttons:

- "Generate PIA WireGuard configuration"
- "Push PIA WireGuard configuration to router\*" (displayed, but grey out until "Generate PIA WireGuard configuration" has executed)
- "Watchdog management\*"
- "View app log"
- "Close app"

On the third line after displaying these buttons, add this text "\* requires SSH connectivity to an Asus router."

Each selected button will open in a new screen, not an overlay window.
Retain the existing header currently created by `Widget build` in `lib\main.dart` (this is two lines of formatted text), and display this at the top of every screen. The header must remain in a static location.
When one of the buttons is selected, the relevant

add under the existing header the name of this menu button as a heading.

The buttons will perform these functions:

#### 2.1.1 "Generate PIA WireGuard configuration"

#### 2.1.2 "Push PIA WireGuard configuration to router"

- reuse the existing router login dialogue `ROUTER SSH LOGIN` which ask for these fields `Router IP`, `SSH Username`, `SSH Password`
- Per existing logic, once the above has been completed

#### 2.1.3 "Watchdog management"

#### 2.1.4 "View log" - scrollabler display of the application log, reain the "CLEAR LOG" button

=================

## 3. Technical Requirements

## 4. Testing Requirements

## 5. Deliverables

_End of requirements document._

=======================

- in `WATCHDOG CONFIG` when the `SAVE & ENABLE` button is selected, on input validation retain existing logging and add an overlay dialogue box with the field names that failed validation and their chosen values. When checking fields "Primary ping IP" and "Secondary ping IP" perform aN ICMP ping to each host via the WAN interface and if either return no response advise but allow saving.
- move the `WATCHDOG CONFIG` button from the `PUSH TO ROUTER` window to underneath the `PUSH CONFIG TO ROUTER...` button and use the same format (it fills the width of the window). Reuse the same display logic which shows/hides the `GENERATE` button for the `WATCHDOG CONFIG` button.
- Button to enable watchdog should not be able to be pressed unless a slot has been selected, it is greyed out and doesn't become lit until a slot is selected but it can still be pressed and activates the new feature defaults to wgc1 atm
- don't exit `PUSH TO ROUTER` when a config is written and a slot made active, we might want to set up the watchdog.Fix by moving watchdog button to initial app window, add logic to only show button if a config has been generated, mimics push to router button
- on selecting `WATCHDOG CONFIG`, if no slot is active, it should enable the interface (reuse existing code by calling that function)
- make it clear that the log in the WATCHDOG screen is from the wgcN log on the router
  Button names
  PUSH CONFIG TO ROUTER...
  WATCHDOG CONFIG
- rename watchdog view log to "VIEW WATCHDOG LOG", as it's not updated in real time, if it becomes realy big there will be a lot of scrolling needed... consider showing in reverse order, currently shows oldest to newest, could log file fill NVRAM? Store it on volatile partition? There are 288 five minute intervals in 24 hours. Fix by only showing last 20 entries,
