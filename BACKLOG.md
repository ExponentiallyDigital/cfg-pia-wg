# BACKLOG.md

- [1. Backlog](#1-backlog)
  - [1.1. All](#11-all)
    - [1.1.1. DOC - documentation updates](#111-doc---documentation-updates)
    - [1.1.2. FTR - future implementation](#112-ftr---future-implementation)
  - [1.2. v0.9.xx freemium](#12-v09xx-freemium)
  - [1.3. Codebase cleanup](#13-codebase-cleanup)
  - [1.4. v1.0.0 iOS version](#14-v100-ios-version)

## 1. Backlog

### 1.1. All

#### 1.1.1. DOC - documentation updates

- DOC: **give each ARCHITECTURE section its own overview.** The document has one at the top, added in the build 430 rewrite, but the sections do not: most open with mechanism before saying what the thing is for or why a reader should care. `The router's service queue` was given one on 2026-09-12 and reads far better for it. Device assignment (section 6) and the SSH commands (section 4) are the two that need it most. Roughly fifteen minutes a section.
- DOC: Update `README.md` screenshots.
- DOC: Update `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app).
- DOC: Update Play Store description.
- DOC: Update Play Store screenshots.
- REL: Update version to 0.9 branch when first releasing stock support (and see the backlog item on performance profiling when sent to GPS alpha track).

#### 1.1.2. FTR - future implementation

- FTR: Add localisation strings: French, Spanish, Spanish (latin), after that decide which ones next. (Google auto transations break character limits of PS Description)
- FTR: edit a device's display name from the assignment screen, writing `custom_clientlist`. Two sharp edges make it more than a text field: `<` and `>` are the record and field delimiters, so an unvalidated name corrupts every device name on the router; and appending a record for a device that has none writes index 3, so a naive `0` downgrades that device's icon to generic in both the WebUI and the ASUS app - the detected type has to be carried over from `nmp_cl_json.js` first. Also needs the service call that makes it take effect, which is unknown.
- ADD: deploy a script like `.\scripts\showall.sh` to `jffs/cfg-pia-wg` that creates diagnostic information, decide what to do about secrets in the file

---

### 1.2. v0.9.xx freemium

**Moved out on 2026-09-12.** The implementation, including the product decision and the price still
to be set, is in [`.claude/plans/plan_revenuecat-implementation.md`](.claude/plans/plan_revenuecat-implementation.md).
The release chores that used to sit here - documentation, publicity, launch and store optimisation -
are in the CHANGELOG pending list, because they happen at release time rather than during the build.

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
