# Security Policy

## Reporting a vulnerability

**We use GitHub's Private Vulnerability Reporting feature.**

1. Go to the **Security** tab of this repository.
2. Click **Report a vulnerability**.
3. Fill out [this form](https://github.com/ExponentiallyDigital/cfg-pia-wg/security/advisories/new) with as much detail as possible.
4. Click **Submit report**.

We will be notified immediately and will respond to your report as soon as possible.

### Our disclosure process

1. **Receipt & validation:** upon receiving your report, we will validate the vulnerability against the current stable release.
2. **Coordinated resolution:** we will work to patch the vulnerability without exposing details publicly to ensure user infrastructure remains safe.
3. **Release:** a security release will be compiled and distributed via GitHub tags. Once resolved, we will publish an advisory and gladly credit your contribution to the project’s security posture (if desired).

---

## Supported versions

Only the latest active [release](https://github.com/ExponentiallyDigital/cfg-pia-wg/releases) version receives security updates and vulnerability patches.

---

## Security update policy

Security-sensitive updates are fast-tracked.

- **Patch generation:** critical security fixes are committed directly into targeted feature branches, reviewed under rigorous isolated criteria, and merged directly into the `main` trunk branch.
- **Automated release compilation:** merges to `main` triggering verified release tags (`v*`) invoke our secure production pipeline (`release.yml`). This compiles highly optimised, production-hardened Android application packages (`.apk`) and auto-generates explicit cryptographic verification checksum profiles (`.sha1`) directly on clean virtualised runner host fabrics.

---

## Secure development practices

This project incorporates strict, automated multi-layered quality and security validations (SSDLC) powered by GitHub Actions. Every single push and pull request targeted to the `main` branch must pass these checks prior to merging:

- **Static application security testing (SAST):** our workflows execute native Flutter static analysis with `—fatal-infos` assertions alongside automated cloud telemetry scans via SonarQube to isolate bugs and design smells.
- **Deep CodeQL semantic scanning:** automated GitHub CodeQL actions parse codebase logic across multiple matrices in parallel, checking both our GitHub Actions pipeline workflows and the underlying native Android Java/Kotlin wrapper scaffolding.
- **Mobile Security Framework (MobSF):** automated `mobsfscan` routines execute structured security analysis across debug binary targets, exporting standardised SARIF diagnostic logs straight into the GitHub Repository Security telemetry dashboard.

---

## Dependency management

To guarantee predictability and avoid supply-chain attacks, we aggressively monitor and enforce strict dependency baselines:

- **Strict lockfile enforcements:** production build actions invoke `flutter pub get —enforce-lockfile` to explicitly mandate that local installation parameters mirror cryptographic signatures locked inside our `pubspec.lock` files exactly.
- **Google OSV scanning:** continuous scanning engines leverage Google’s Open Source Vulnerability (`osv-scanner-action`) framework to inspect codebase modules and dependencies recursively against comprehensive up-to-the-minute public vulnerability catalogs.
- **Automated Dependabot tracking:** upstream pipeline dependencies ("supply chain") are tracked programmatically via a dedicated repository `dependabot.yml` schedule. This automates weekly monitoring routines localised against the `Australia/Melbourne` time-zone to actively track, organise, and patch vulnerabilities detected across our operational infrastructure elements.

---

## Secret management

We enforce a strict **zero-hardcoded-secrets policy** across this entire infrastructure:

- **Runtime application environment:** user credential properties (usernames and passwords) are treated as strictly short-lived volatile variables. They inhabit ephemeral memory maps (`SessionController`) and are passed securely over native Transport Layer Security (HTTPS) connections exclusively to generate transient operational access tokens from Private Internet Access (PIA). Credentials are never logged, and are never written to storage **on the device** - they are wiped from memory on every exit path.
- **Credentials written to the router (watchdog only):** deploying a watchdog necessarily leaves credentials on the router, because the watchdog script re-authenticates with PIA on its own, hours or days later, with the app nowhere in the picture. Your PIA username and password are written to router NVRAM as `cfg_pia_wg_user` / `cfg_pia_wg_password`, and the SMTP username and password for email alerts as `wgcN_wd_smtp_user` / `wgcN_wd_smtp_pass`. **NVRAM is not encrypted**, and anyone with admin or SSH access to the router can read these values. They are removed when the last watchdog is deleted. If that trade is not one you want to make, use the app without the watchdog: generating and pushing a WireGuard configuration never stores a credential on the router.
- **Router SSH credentials** are only ever held in memory for the session and are never written anywhere - not to the device, not to the router.
- **The router SSH connection is held open for the session.** Until v0.8.36 each action opened its own connection and closed it immediately; they now share one, which removes a full handshake and a `dropbear` login line from every button press. The trade is an authenticated session that outlives a single action, so it is closed at the two points where holding it would matter: when the app goes to the **background** (`AppLifecycleState.paused`), because a live session sitting behind a locked screen is a wider exposure than credentials in memory, and whenever credentials are **wiped** - "Exit app", the back key out of the main menu, or a change of router IP, username or password. The next action reconnects on demand. The connection itself is SSH-encrypted throughout and no credential is written to either device as a result.
- **CI/CD pipeline infrastructures:** operational secrets utilised during automated compilation routines (including SonarQube access tokens and base64-encoded Android Release Keystore signing credentials alongside their corresponding decryption passwords) are isolated completely from source repositories. These assets are injected securely at execution runtime via encrypted GitHub Actions Secrets environments.

---

## Build attestation

Build provenance attestations are available for release APK, debug APK, and Google Play Store AAB.
View them at: https://github.com/ExponentiallyDigital/cfg-pia-wg/attestations

---

## Data handling & privacy

**cfg-pia-wg** is architected to operate with a zero-retention, zero-persistence local data footprint to maximise user privacy:

- **Zero permanent footprint:** the application does not maintain long-term local telemetry, profiling metrics, or databases (`shared_preferences`, secure storage, or SQLite).
- **Volatile file lifecycles:** when generating WireGuard configuration artifacts (`.conf`), the underlying code writes the payload payload to a transient workspace directory solely to satisfy the operating system's native file sharing framework requirements. This temporary file is wrapped within an explicit, defensive `try/finally` block that guarantees physical deletion from disk blocks immediately upon completion or cancellation of the share sequence.
- **Automated clipboard overwrite:** to neutralise background memory/clipboard scraping malwares operating on the host device, successful clipboard transfers trigger a 60-second real-time countdown timer. Once expired, the app automatically overwrites the system clipboard with a blank string.
- **Native task-switcher protection** `(FLAG_SECURE)`: enforces native OS-level window flags to block third-party screenshot capturing and automatically obfuscates/blanks the app layout view inside the Android Recent Apps / Task Switcher interface.
- **Native screen capture protection:** the implementation forces native Android system window attributes (`FLAG_SECURE`). This explicitly instructs the host OS kernel to block third-party screenshot captures and automatically obfuscates or blanks the active UI presentation when viewing screens inside the system's Recent Apps / Task Switcher interface.
