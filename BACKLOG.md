# CHANGELOG.md

- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. CHG - functional code changes](#112-chg---functional-code-changes)
    - [1.1.3. FTR - future implementation](#113-ftr---future-implementation)
  - [1.2. v0.9.xx freemium](#12-v09xx-freemium)
    - [1.2.1. Accounts \& Play Console setup](#121-accounts--play-console-setup)
    - [1.2.2. RevenueCat dashboard setup](#122-revenuecat-dashboard-setup)
    - [1.2.3. Codebase integration](#123-codebase-integration)
    - [1.2.4. Security \& router diagnostics](#124-security--router-diagnostics)
    - [1.2.5. Sandbox testing \& QA](#125-sandbox-testing--qa)
    - [1.2.6. Documentation and publicity](#126-documentation-and-publicity)
    - [1.2.7. Launch \& post-launch](#127-launch--post-launch)
  - [1.3. Codebase cleanup](#13-codebase-cleanup)
  - [1.4. v1.0.0 iOS version](#14-v100-ios-version)

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- DOC: Update `README.md` screenshots.
- DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app).
- DOC: Add to `README.md` the expanded About screen functionality: build info, create GitHub issue, and clear PIA cached cert.
- DOC: Add to `README.md` requirements section, `jq` and `sendmail-go` on stock firmware.
- DOC: Add to `README.md` requirements section, how to install `DownloadMaster` in ASUS WebUI.
- DOC: Scan all `*.md` (`README.md`, and `ARCHITECTURE.md` + others) and remove references to Merlin firmware requirement.
- DOC: Update Play Store description.
- DOC: Update Play Store screenshots.
- REL: Update version to 0.9 branch when first releasing stock support (and see the backlog item on performance profiling when sent to GPS alpha track).
- DOC: Set MAIN branch to use default router ip 192.168.50.1 (ASUS default), DEV branch uses 192.168.0.254 as the default.
- DOC: instead of calling them "slots", I should consider calling them "units" - that's a lot of risky search and replace though :/

#### 1.1.2. CHG - functional code changes

- ADD: Automate updating `THIRD-PARTY-NOTICES.md`, add as part of `scripts\build.ps1/sh`. Add to GitHub actions script `.github\workflows\release.yml`.
- REL: after releasing **v8.x.y** to GPS alpha track, review [Play Console technical quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799), specifically:
  - [r8-analyzer/SKILL.md](https://github.com/android/skills/tree/main/performance/r8-analyzer)
  - [Perfetto Skills](https://github.com/google/perfetto/tree/main/ai/skills)
  - [profilers/android-profiler](https://github.com/android/skills/tree/main/profilers/android-profiler)

#### 1.1.3. FTR - future implementation

- FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)

---

### 1.2. v0.9.xx freemium

- NEW: Freemium version using RevenueCat, move all but conf generation to a one-off lifetime paid function, non-freemium makes screens accessible but read only, advise once per session when enterng a freemium gated function, explain how to unlock all capabilities.
- TBC: Determine cost - smaller user base, higher investment.

- Implementation plan, see (and update) detailed plan stored in `.claude\plans\pan_revenucat-implementation.md`, below are high level steps only:

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

  - **Changelog:** Add to v0.9.00 changelog, explain why watchdog is monetised.
  - **Store optimisation (ASO):** include high-intent keywords: *Asuswrt-Merlin, PIA WireGuard token auto-renew, Asus router VPN, NVRAM SSH scripts*.
  - **Reconfigure review prompt:** add link to reconfigure email seeking an app review (add an NVRAM timestamp when watchdog first deployed and increment an NVRAM counter when a reconfigure occurs - see CHG backlog item).

---

### 1.3. Codebase cleanup

- Map codebase
  - By file and by function (done 2026-09-01, now in `CONTEXT.md`)
  - Identify redundant or duplicated code
- Optimise and simplify
  - nvram statements
  - Duplication of variables
  - Complexity reduction/reduce lines of code
    - audit large/long/complex source files
    - audit naming of source code files
- Abstract firmware from Manage and watchdog
  - Create functions to act on classes of activities
  - Split out to functions

### 1.4. v1.0.0 iOS version

- ...

---
