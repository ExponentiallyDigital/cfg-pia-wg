# CHANGELOG.md

- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. GUI - changes to the user interface](#112-gui---changes-to-the-user-interface)
    - [1.1.3. CHG - functional code changes](#113-chg---functional-code-changes)
    - [1.1.4. FIX - bug fixes](#114-fix---bug-fixes)
    - [1.1.5. FTR - future implementation](#115-ftr---future-implementation)
    - [1.1.6. TST - testing changes](#116-tst---testing-changes)
    - [1.1.7. REL - release process changes](#117-rel---release-process-changes)
  - [1.2. v0.8.xx freemium](#12-v08xx-freemium)
    - [1.2.1. Accounts \& Play Console setup](#121-accounts--play-console-setup)
    - [1.2.2. RevenueCat dashboard setup](#122-revenuecat-dashboard-setup)
    - [1.2.3. Codebase integration](#123-codebase-integration)
    - [1.2.4. Security \& router diagnostics](#124-security--router-diagnostics)
    - [1.2.5. Sandbox testing \& QA](#125-sandbox-testing--qa)
    - [1.2.6. Documentation and publicity](#126-documentation-and-publicity)
    - [1.2.7. Launch \& post-launch](#127-launch--post-launch)

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- DOC: Add README note that SBOM (build provenance) is for the aab pushed to the PS.
- DOC: add to TESTING.md: `wgcX_rip` is updated by the Web GUI via an unknown method (review Asus_WRT src), router log shows no `service` script(s) were run to display this in the web GUI. It is not the public IP address (which is served from a pool to external sites), it is the router's IP address on PIA's infrastructure (?) and always differs from `wgc1_ep_addr` and `wgcX_ep_addr_r` (except PIA's webiste shows the public IP address as `wgc1_ep_addr*` vs other sites which showed `wgcX_rip` as the public ip address).
- DOC: ASUS default router ip is 192.168.50.1 - code uses 192.168.0.254 as default
- DOC: describe how to test a reconfigure event: remove a slot's config via the Web UI, apply that, then enter a valid region name as the slot description and apply that, or the reconfigure won't occur. Add a warning about that to README.md as well as TESTING.md: leaving 'ghost' watchdogs. "Deleting a slot via the Web UI can leave a watchdog running that can't connect to anything as it has no region name as a title: "ERROR: wgc4_desc is empty". Fix by adding a valid region name e.g. "au_adelaide-pf" to that slot in the Web UI (only that field is needed) which enables the VPN to be reloaded at the next `cronIntervalMinutes`, then remove the watchdog via the app.
- DOC: NB factory restore does **not** remove custom NVRAM values! Exposure of credentials (PIA & smtp) if router is sold/given away.
- DOC: instead of calling them "slots", I should consider calling them "units" - that's a lot of risky search and replace though...

#### 1.1.2. GUI - changes to the user interface

- GUI: When switching back and forth to/from the app to copy/paste details into email alert config, the modal became reduced in size, could still enter and edit fields. Cosmetic, fixed by switching to another app then back again.

#### 1.1.3. CHG - functional code changes

- CHG: Watchdog email alert `SMTP username field` is finicky when pasting from the clipboard - increase size of input field/get smaller fingers?
- CHG: back off when PIA refuses a token request. It answers HTTP 403 after sustained re-registration and clears on its own after tens of minutes; retrying every 120s indefinitely is what prolongs it. Grow the cooldown on consecutive failures, cap at 30 minutes, reset on success. Design in `.claude/plans/plan_watchdog-token-backoff.md`.
- CHG: reuse the router SSH connection instead of opening one per action - removes a dropbear login line and a full handshake from every button press. Design in `.claude/plans/plan_ssh-connection-reuse.md`. Needs its own build number: a stale-connection bug would look like an intermittent action failure.

#### 1.1.4. FIX - bug fixes

- ...

#### 1.1.5. FTR - future implementation

Implement "kill switch" into stock firmware:

  1. menu changes:
    - "Generate PIA WireGuard config" rename to "Create PIA WireGuard config".
    - "Manage PIA WireGuard config" no change.
    - "Watchdog Wireguard management" no change.
    - "VPN device assignment" **<- new entry**.
    - "View app log" no change.
    - "Exit app" no change.
  2. ADD: additional menu item "VPN device assignment" functionality is
    - get the device names from nvram via "nvram get custom_clientlist" & allow devices to be assigned to VPN slots.
      - `<PLACEHOLDER - ADD dhcp_staticlist and custom_clientlist mappings>`
      - select a device the slot applies to
      - provide "apply to all devices"
      - sets XX then run "service restart_default_wan"

- FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)

#### 1.1.6. TST - testing changes

- TST: review opportunities to increase code base testing, examine `ftr` report for functions with low coverage

#### 1.1.7. REL - release process changes

- REL: (?) `./scripts/pin-actions-latest.*` chokes if comment missing
- REL: Check build-config/gradle.properties default values are still suitable.
- REL: Fix `.github/workflows/release.yml` "Warning: WARNING!! 'track' is deprecated and will be removed in a future release. Please migrate to 'tracks'".

---

### 1.2. v0.8.xx freemium

- NEW: RevenueCat set up.

- CHG: freemium version, move all but conf generation to a one-off lifetime paid function. Implementation plan:

  #### 1.2.1. Accounts & Play Console setup

  - **In-app product creation:** Create a **Non-consumable** in-app product (e.g., `cfg-pia-wg_pro_unlock`) set to US$x.yy.
  - **Play Store compliance:** Complete **Data safety form** to reflect RevenueCat, and add to Privacy Policy.

  #### 1.2.2. RevenueCat dashboard setup

  - **Link accounts:** Connect Google Play Console credentials to RevenueCat via service account keys.
  - **Configure entitlements:** Create an **Entitlement** named `pro_feature` and map to `cfg-pia-wg_pro_unlock`.

  #### 1.2.3. Codebase integration

  - **Flutter dependencies:** Add `purchases_flutter` and `flutter_secure_storage` to `pubspec.yaml`.
  - **Billing service singleton:** Implement RevenueCat initialisation, real-time entitlement status updates, purchase triggers, and purchase restoration.
  - **Paywall UI modal:** Build a `PaywallBottomSheet` highlighting watchdog's zero-touch automation, PIA key renewal fix, and lifetime access model.
  - **PayPal/Patreon:** remove links from main app screen.

  #### 1.2.4. Security & router diagnostics

  - **Pre-flight diagnostic:** Verify SSH connectivity and JFFS script execution readiness *before* displaying unlock feature to prevent purchases on incompatible setups.

  #### 1.2.5. Sandbox testing & QA

  - **Licence testing:** Add developer Gmail under *Google Play Console -> Licence testing*.
  - **Internal test track:** Build and upload `flutter build appbundle` (`.aab`) to the Internal Testing track.
  - **Sandbox verification:** Run `flutter run` on device to test:
  - **E2E test:** Generate and Manage execute freely; watchdog invokes unlock feature.
  - **Purchase flow:** complete test transaction via Google’s *"Test card, always approves"*.
  - **Declined card handling:** Test error handling using *"Test card, always declines"*.
  - **Restoration flow:** test "Restore Purchases" button.
  - **Offline access:** disconnect internet and verify cached local entitlements allow watchdog to execute.

  #### 1.2.6. Documentation and publicity

  - **Update screenshots:** create & upload phone and tablet screenshots x8.
  - **Trademark protection:** add to README that app name, logos, and branding are reserved trademarks.
  - **Transparency:** explain in README that pre-built convenience binaries are available via the Google Play Store to defray development costs and support ongoing app updates.
  - **Publicise**: update Play Store description. Post to SNB and Reddit (r/AsuswrtMerlin, r/PrivateInternetAccess, r/WireGuard).

  #### 1.2.7. Launch & post-launch

  - **Changelog:** Add to v0.8.00 changelog, explain why watchdog is monetised.
  - **Store optimisation (ASO):** include high-intent keywords: *Asuswrt-Merlin, PIA WireGuard token auto-renew, Asus router VPN, NVRAM SSH scripts*.
  - **Reconfigure review prompt:** add link to reconfigure email seeking an app review (add an NVRAM timestamp when watchdog first deployed and increment an NVRAM counter when a reconfigure occurs - see CHG backlog item).
