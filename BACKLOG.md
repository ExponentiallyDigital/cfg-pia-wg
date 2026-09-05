# BACKLOG.md

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
- DOC: Add to `README.md` requirements section, `jq` and `sendmail-go` on stock firmware.
- DOC: Add to `README.md` requirements section, how to install `DownloadMaster` in ASUS WebUI.
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

- Implementation plan, see (and update) detailed plan stored in `.claude\plans\plan_revenuecat-implementation.md`, below are high level steps only:

  #### 1.2.1. Accounts & Play Console setup

  - **In-app product creation:** Create a **Non-consumable** in-app product (e.g., `cfg-pia-wg_pro_unlock`) set to US$x.yy.
  - **Play Store compliance:** Complete **Data safety form** to reflect RevenueCat, and add to Privacy Policy. Store-rejection item, not a nicety - the SDK sees a pseudonymous app-user id.

  #### 1.2.2. RevenueCat dashboard setup

  - **Link accounts:** Connect Google Play Console credentials to RevenueCat via service account keys.
  - **Configure entitlements:** Create an **Entitlement** named `pro_feature` and map to `cfg-pia-wg_pro_unlock`.

  #### 1.2.3. Codebase integration

  - **Flutter dependencies:** Add `purchases_flutter` and `flutter_secure_storage` to `pubspec.yaml`.
  - **Billing service singleton:** Implement RevenueCat initialisation, real-time entitlement status updates, purchase triggers, and purchase restoration.
  - **Paywall UI modal:** Build a `PaywallBottomSheet` highlighting watchdog's zero-touch automation, PIA key renewal fix, and lifetime access model.
  - **PayPal/Patreon:** remove links from main app screen. Re-space the home-screen footer afterwards - the `spacer` above it is sized for the donation block. Keep the "add a Play Store app review" link: the watchdog alert emails say "by tapping on the home screen link", so removing it makes that wording stale.

  #### 1.2.4. Security & router diagnostics

  - **Pre-flight diagnostic:** Verify SSH connectivity and JFFS script execution readiness *before* displaying unlock feature to prevent purchases on incompatible setups. Most of this already exists - see the table in the plan addendum. The one missing check is `/opt` on stock (DownloadMaster installed): without it the watchdog deploys, works, and then silently loses its cron entries at the next reboot. **Worth adding regardless of freemium.**
  - **Do not build revocation into the deployed watchdog script.** A deployed watchdog runs on the router with the app nowhere in the picture, so entitlement cannot be enforced after the fact - accepted deliberately (see plan addendum). A licence check inside the script would be defeatable in a text editor and would add a failure mode to the one thing that has to be reliable unattended.
  - **`flutter_secure_storage` versus the stated posture:** `README.md` and `SECURITY.md` both say absolutely that nothing is written to device storage. Caching an entitlement is compatible with the intent but contradicts the wording. Reword "Secret management" to separate *credentials* (never stored) from *purchase state* (cached, not sensitive) in the same change that adds the dependency.

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

---

### 1.3. Codebase cleanup

Early thinking, with measurements: `.claude/plans/plan_firmware-abstraction.md`.

> [!IMPORTANT]
> Do not start the firmware abstraction until stock support has soaked in release. It touches every path stock support just landed on, and a regression here would be indistinguishable from a stock-support bug - the same reasoning that gave SSH connection reuse its own build number.

- Map codebase
  - By file and by function (done 2026-09-01, now in `CONTEXT.md`)
  - Identify redundant or duplicated code
- Optimise and simplify
  - nvram statements
  - Duplication of variables
  - Complexity reduction/reduce lines of code
    - audit large/long/complex source files
    - audit naming of source code files
- Abstract firmware from Manage and watchdog. Measured 2026-09-05: 27 `isStockFirmware` branches across six files, 21 of them in `router_slot_service.dart` (14) and `router_watchdog.dart` (7). Both stock bugs found this session were "the stock branch does not match the Merlin branch's intent".
  - Create functions to act on classes of activities
  - Split out to functions
  - Model on `buildWatchdogScript`, which already resolves firmware once and substitutes the differences (`__KILLSW__`, `__MAILHDR__`, `__MAILCMD__`) rather than branching at runtime
  - Take it in slices, each on its own build: start/stop first, then slot reading, then cron persistence, then delete
- Largest files, measured 2026-09-05: `router_watchdog.dart` 1,554 lines, `router_slot_service.dart` 842, `slot_modal.dart` 767. The email layout in `router_watchdog.dart` (`buildEmailBody`, `RouterEmailFacts`, the section constants) is self-contained and would move out with no behaviour change.

### 1.4. v1.0.0 iOS version

**Parked** - US$99/year Apple Developer Program against an unknown iOS user base. Early thinking, and what actually blocks it: `.claude/plans/plan_ios-port.md`.

- The router half ports for free: `dartssh2` is pure Dart, and the watchdog script runs on the router, which does not care what phone deployed it.
- The platform hardening does not. `FLAG_SECURE` has **no iOS equivalent** - screenshots cannot be blocked, only the task-switcher snapshot can be covered. `README.md` and `SECURITY.md` state that guarantee unconditionally today and would need to state it per-platform.
- The silent clipboard clear is an Android method channel (`ClipboardManager.clearPrimaryClip()`); iOS needs `UIPasteboard.general.items = []` or the 60-second auto-clear regresses to the system copy popup that 403 removed.
- Non-code costs: a Mac or hosted runner for signing, a materially stricter App Store review, and a release pipeline (`release.yml`, SBOM, Gradle lockfiles) that is Android-shaped throughout.

**Worth doing whether or not iOS ever happens:**

- FIX: `openPlayStoreReview()` fails **silently** on iOS today - `openStoreListing()` needs an `appStoreId` there and throws without one, which the catch swallows into a `false`. Latent now, on a platform we do not ship to, but it is still a silent catch.
- DOC: phrase the hardening claims in `README.md` and `SECURITY.md` as "on Android" rather than absolutely, so an iOS build cannot quietly make them untrue.

---
