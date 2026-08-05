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

- DOC: Add note that PIA sometimes takes regions offline for maintenance so you might be expecting to have a POP in Perth but online tools may show you coming from Adelaide.
- DOC: Add text about how to check your POP, but note that services like https://www.privateinternetaccess.com/what-is-my-ip, https://ipaddress.my/?lang=en_US, https://2ip.io/, and https://www.showmyip.com/ may cache your location in the browser (they sometimes return a stale POP if used multiple times). To be absolutely sure, close your browser rather than just refreshing the page.
- DOC: Add practical workflows to achieve specific outcomes.
- DOC: Note that you can create and apply a VPN slot by adding a watchdog in one step. If you do that the watchdog will immediately run and see that the VPN is not active and tell you that it failed to do a ping over the tunnel so it is reconfiguring the slot as though a periodic PIA renewal of the registration was needed. If you already have a VPN running on that slot the immediate deployment of the script will see the slot is active and the ICMP over the WG interface succeeds.
- DOC: describe how to test a reconfigure event - v0.6.20+ uses ping targets to check if a reconfigure can occur, i.e. do we have WAN Internet connectivity? If ping targets are set to TEST-NET-1, TEST-NET-2, or TEST-NET-3 you get "no Internet on WAN interface, exiting" from the shell script in `_kWatchdogScriptTemplate`. A working manual test scenario is: remove a slot's config via the Web UI, apply that, then enter a valid region name as the slot description and apply that, or the reconfigure won't occur. Add a warning about that to README.md as well as TESTING.md: leaving 'ghost' watchdogs. "Deleting a slot via the Web UI can leave a watchdog running that can't connect to anything as it has no region name as a title: "ERROR: wgc4_desc is empty". Fix by adding a valid region name e.g. "au_adelaide-pf" to that slot in the Web UI (only that field is needed) which enables the VPN to be reloaded at the next `cronIntervalMinutes`, then remove the watchdog via the app.
- DOC: Fix display of TIP, WARNING, and IMPORTANT in README.md after pandoc converts the file.
- DOC: Only for GitHub display, fix centring of images in examples for Main menu, Standalone config generation, Router slot management. Centres perfectly in README.html.
- DOC: Only for GitHub display, fix centring titles under images for Supply credentials and DNS, Ping targets, Editing a slot, Watchdog management, Configuring a watchdog, App log, Hamburger Menu. Centres perfectly in README.html.
- DOC: add to TESTING.md: `wgcX_rip` is updated by the Web GUI via an unknown method (review Asus_WRT src), router log shows no `service` script(s) were were run to display this in the web GUI. It is not the public IP address (which is served from a pool to external sites), it is the router's IP address on PIA's infrastructure (?) and always differs from `wgc1_ep_addr` and `wgcX_ep_addr_r` (except PIA's webiste shows the public IP address as `wgc1_ep_addr*` vs other sites which showed `wgcX_rip` as the public ip address).

#### 1.1.2. GUI - changes to the user interface

- GUI: Change colour of region name from GREY to WHITE in WG Config and Watchdog modals.
- GUI: Add text next to the "GENERATED CONFIG" with the region name the config is for.
- GUI: Make Manage and Watchdog deletion prompt messages consistent.
- GUI: Change info prompt after slot created "remember to enable it via the enable button".
- GUI: Watchdog, when creating on a slot which has an config, make the prompt more intelligible, also show the name of the pre-existing region that will be overwritten.
- GUI: App log has no carriage return/line feed when copied to clipboard. Text copied from Watchdog log has line terminators, as does the Router Config conf file.
- GUI: Can't copy/paste text from About screen (not required if implement GH issue creation from About, but that requires a GH account)
- GUI: When switching back and forth to/from the app to copy/paste details into email alert config, the modal became reduced in size, could still enter and edit fields. Cosmetic, fixed by switching to another app then back again.
- GUI: Edge-to-edge may not display for all users. From Android 15, apps targeting SDK 35 will display edge-to-edge by default. Apps targeting SDK 35 should handle insets to make sure that their app displays correctly on Android 15 and later. Investigate this issue and allow time to test edge-to-edge and make the required updates. Alternatively, call enableEdgeToEdge() for Kotlin or EdgeToEdge.enable() for Java for backward compatibility.

#### 1.1.3. CHG - functional code changes

- CHG: Remove 'WATCHDOG_EOF' text from test email:
         This is a test email from the cfg-pia-wg watchdog (slot wgcX).
         WATCHDOG_EOF
- CHG: rebuild test/reconfigure email: router DNS name, date and time, why it was sent (test/reconfigure), the region, and cronIntervalMinutes.
- CHG when you enable/disable/delete a slot, add to the router log the region that slot was previously using e.g.
        Enabled wgc1 -> 01 cfg-pia-wg: Enabled wgc1 (region-name)
        Disabled wgc1 -> Disabled wgc1 (region-name)
        Deleted wgc1 configuration -> Deleted wgc1 configuration (region-name)
- CHG: On disable, log lines are repeated (and needs the region name per above)
        cfg-pia-wg: Disabled wgc1
        cfg-pia-wg: Watchdog disabled for wgc1
        cfg-pia-wg: Disabled wgc1
- CHG: If a Conf slot is already disabled, grey out the DISABLE button (only gets logged once to router log though vs above).
- CHG: Creating writes the region name to router log, deleting/disabling does not, review code path for
        Deleted wgc1 configuration
        Created wgc1 configuration (aus_melbourne)
- CHG: Replace app exit and config clipboard copy timer expiration behaviours with clearPrimaryClip(), and remove the two associated comments in README.md.
- CHG: Add option to remove/update cached ca cert.
- CHG: Watchdog email alert `SMTP username field` is finicky when pasting from the clipboard - increase size of input field/get smaller fingers?

#### 1.1.4. FIX - bug fixes

- FIX: If editing an existing watchdog slot, at save you are asked if you want to overwrite, but if you create a watchdog on an empty slot you aren't prompted and that removes any existing watchdog. Add a prompt explaining that!
- FIX: "home" button is not in green text with a green button border, after activating any of the four main menu items - Manage and Watchdog screens have a modal on top so that's actually correct (for those two situations only).
- FIX: When viewing the router watchdog log, if you COPY the log and then enter the conf menu it will detect that and start the clear timer as it only knows that something from this app placed data in the clipboard.
- FIX: In generate, if you delete DNS entries then go to another screen then re-enter generate, the default DNS addresses are not displayed but are still used when generating a new conf file. Add a check that if that field is ever blank, then the quad 9 defaults are inserted.

#### 1.1.5. FTR - future implementation

- FTR: Consider adding back an idle app timeout of of XX minutes, if timer expires clear all credentials. This would defuse the ability to reveal passwords and copy/paste if app is left idle. Consider calling session destruction through exit path but don't actually exit when timer expires. Had originally implemented this in **pre 0.6.05 build 334**, was set to 10m.
- FTR: Enable creation of a GitHub issue from ABOUT screen, open on GitHub with build info of running app.
- FTR: Add localisation strings.
- FTR: iOS release...which requires a different license, move to GPL v2 or MIT/Apache 2?

#### 1.1.6. TST - testing changes

- TST: reiew opportunities to increase code base testing, examnine `ftr` report for functions with low coverage

#### 1.1.7. REL - release process changes

- REL: ./scripts/pin-actions-latest.* chokes if comment missing
- REL: check build-config/gradle.properties default values are still suitable.
- REL: Improve memory and performance with R8 optimisation, review: optimisation rate 41%, obfuscation rate 42%, shrinking rate 42%.
- REL: Fix `.github/workflows/quality_and_security.yml` warning "CodeQL (java-kotlin) Cannot build an overlay-base database because build-mode is set to "manual" instead of "none". Falling back to creating a normal full database instead."
- REL: Fix `.github/workflows/release.yml` "Warning: WARNING!! 'track' is deprecated and will be removed in a future release. Please migrate to 'tracks'".

### 1.2. v0.8.xx freemium

- CHG: freemium version, move Watchdog function to once-off lifetime paid function. Implementation plan:

  #### 1.2.1. Accounts & Play Console setup

  - **Google Merchant account:** Activate Payment Account in **Google Play Console**.
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
  - **Reconfigure review prompt:** add link to reconfigure email seeking an app review (add an NVRAM timestamp when watchdog first deployed and increment an NVRAM counter when a reconfigure occurs).