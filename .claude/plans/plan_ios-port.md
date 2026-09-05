# Plan: iOS port

**Status:** DRAFT, not started, and **not costed as worthwhile yet** — the Apple Developer Program is US$99/year against an unknown iOS user base, so this is deliberately parked. Backlog item: `BACKLOG.md` section 1.4 "v1.0.0 iOS version". Not current state — see `.claude/CONTEXT.md` for that.

## What ports for free

The router half is pure Dart and carries over untouched:

- `dartssh2` — no platform channels, no native code
- The PIA HTTP work, key generation (`x25519`), config assembly
- The entire watchdog: the script is generated as text and executed on the router, which does not care what phone deployed it
- `share_plus`, `path_provider`, `url_launcher` all have iOS implementations

So Generate, Manage and Watchdog are, in principle, a recompile.

## What does not port — the platform hardening

This is the whole of the work, and it is the part that carries the app's security claims.

### 1. `FLAG_SECURE` has no iOS equivalent

`MainActivity.kt` sets `FLAG_SECURE` on release builds, which blocks screenshots and obscures the app in the task switcher. iOS offers no API to prevent screenshots. The nearest equivalents are partial:

- Task-switcher snapshot: cover the window in `applicationWillResignActive` and uncover in `didBecomeActive` — this works and is the standard approach.
- Screenshots: **cannot be blocked.** `UIScreen.capturedDidChangeNotification` can tell you a recording is in progress, and `screenshotTaken` notifications fire *after* the fact.

**Consequence beyond code:** README's "Native task-switcher protection" bullet and SECURITY.md both state the guarantee unconditionally. On iOS it would be a weaker guarantee, and the docs must say so per-platform rather than quietly becoming untrue. `test/unit/clipboard_service_test.dart` also asserts the Kotlin source keeps `allowScreenCaptureInRelease = false`; an iOS equivalent needs its own guard or the claim goes untested there.

### 2. The clipboard clear is an Android method channel

`clipboard_service.dart` calls `clearClipboard` on a channel registered in `MainActivity.kt`, which runs `ClipboardManager.clearPrimaryClip()`. On iOS the channel is absent, so it falls back to `Clipboard.setData('')` — the behaviour that was deliberately removed in 403 because it triggers the system's copy notification.

iOS needs `UIPasteboard.general.items = []`, which does clear silently. Small piece of Swift, but it must exist or the 60-second auto-clear regresses to the popup behaviour on iOS only.

### 3. `openPlayStoreReview()` fails silently on iOS **today**

Already latent, not future work. `in_app_review`'s `openStoreListing()` requires an `appStoreId` on iOS and throws `ArgumentError` without one; `review_service.dart` catches everything and returns false, so the home-screen link would log "Could not open the Play Store listing" and do nothing.

Needs an App Store id passed through, and the label and the alert-email review line both say "Play Store" in text.

### 4. Autofill

`AutofillHints.username` / `.password` map to iOS Password AutoFill, which works, but iOS additionally wants an associated-domains entitlement for domain-scoped credentials. Plain username/password fill works without it. The empty-field gotcha documented in README 5.2 is Android-specific and may not apply.

## Non-code costs

- US$99/year Apple Developer Program, before a single install
- A Mac for builds and signing, or a hosted CI runner
- App Store review, which is materially stricter than Play's — an app that SSHes into a router and writes credentials to it should expect questions, and SECURITY.md's honesty about NVRAM plaintext is an asset there rather than a liability
- The release pipeline (`release.yml`, SBOM, lockfile pinning) is Android-shaped throughout

## Recommendation

Hold, as decided. The two items worth doing regardless of whether iOS ever happens:

1. **Fix `openPlayStoreReview()` for a null App Store id** so it fails loudly rather than silently — it is a latent bug on a platform we do not ship to, but it is still a silent catch.
2. When touching README/SECURITY hardening claims, phrase them as "on Android" rather than absolutely, so an iOS build does not silently make them false.
