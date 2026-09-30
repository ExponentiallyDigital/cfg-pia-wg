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

- **Runtime application environment:** user credential properties (usernames and passwords) are treated as strictly short-lived volatile variables. They inhabit ephemeral memory maps (`SessionController`) and are passed securely over native Transport Layer Security (HTTPS) connections exclusively to generate transient operational access tokens from Private Internet Access (PIA). Credentials are never written to storage **on the device** - they are wiped from memory on every exit path. They are kept out of the app log by one filter every log line passes through, which removes the session's actual passwords and usernames, a PIA token in a URL and a WireGuard private key, whatever carried them in: a command, its error output, or an exception. Until build 482 only commands were filtered, by the names of their settings, so an error that echoed a secret could reach the log.
- **Credentials written to the router (watchdog only):** deploying a watchdog necessarily leaves credentials on the router, because the watchdog script re-authenticates with PIA on its own, hours or days later, with the app nowhere in the picture. Your PIA username and password are written to router NVRAM as `cfg_pia_wg_user` / `cfg_pia_wg_password`, and the SMTP username and password for email alerts as `wgcN_wd_smtp_user` / `wgcN_wd_smtp_pass`. **NVRAM is not encrypted**, and anyone with admin or SSH access to the router can read these values. They are removed when the last watchdog is deleted. If that trade is not one you want to make, use the app without the watchdog: generating and pushing a WireGuard configuration never stores a credential on the router.
- **`/jffs/curllst` (a stock ASUS firmware behaviour, not ours):** the router's own `/usr/sbin/curl` appends the full command line of every invocation to `/jffs/curllst`, which is world-readable (mode 666), survives reboots, and is rotated to `/jffs/curllst.1`. It cannot be disabled. The watchdog's PIA token request passes credentials on the command line, so the deployed script empties the file after every `curl` and on every failure path. Its encrypted name lookups put no hostname on the command line at all, so your email provider's name no longer reaches the file either; until build 477 it did. Anything else on the router that uses `curl` is not covered by that, so treat the file as sensitive and redact it before sharing.
- **Router SSH credentials** are only ever held in memory for the session and are never written anywhere - not to the device, not to the router. The router's *address* and its SSH *host key fingerprint* are kept, and nothing else - see "Data handling & privacy" below.
- **The router's SSH host key is checked.** The first successful login records the key's SHA256 fingerprint, as `ssh` does in `known_hosts`; every connection after that is refused, before any password is sent, if the router presents a different key, and the app says why. Until build 478 any key was accepted, so anything that answered on the router's address could have collected its login. A reset or reflashed router has a new key: FORGET ROUTER IP clears the record, and the next login records the new one.
- **The router SSH connection is held open for the session.** Until v0.8.36 each action opened its own connection and closed it immediately; they now share one, which removes a full handshake and a `dropbear` login line from every button press. The trade is an authenticated session that outlives a single action, so it is closed at the two points where holding it would matter: five minutes after the app goes to the **background** (`AppLifecycleState.paused`; coming back sooner keeps it), because a live session sitting behind a locked screen is a wider exposure than credentials in memory, and whenever credentials are **wiped** - "Exit app", the back key out of the main menu, or a change of router IP, username or password. The next action reconnects on demand, and checks the router's host key again. The connection itself is SSH-encrypted throughout and no credential is written to either device as a result.
- **Purchase state is not a credential, and is not held here.** The app never sees a card number, a billing address or any payment detail: Google Play takes the payment and RevenueCat records only whether this installation holds the unlock. The app asks that question and receives a yes or no. Nothing about a purchase is written to device storage by this app, and the answer is not derived from anything the app keeps - it belongs to the Google account, which is why recovering it on a new phone needs no local state and why `android:allowBackup="false"` costs nothing.
- **The RevenueCat public key is injected at build time**, not committed. It reaches the release build as a `--dart-define` from a GitHub Actions secret, alongside the keystore credentials described above. The key is public by design and readable from any published artifact, so this is not concealment: a build without it cannot sell anything, and the release workflow fails rather than producing one. No RevenueCat secret key exists in this project - the app only ever uses the public one.
- **CI/CD pipeline infrastructures:** operational secrets utilised during automated compilation routines (including SonarQube access tokens and base64-encoded Android Release Keystore signing credentials alongside their corresponding decryption passwords) are isolated completely from source repositories. These assets are injected securely at execution runtime via encrypted GitHub Actions Secrets environments.

---

## Build attestation

Build provenance attestations are available for release APK, debug APK, and Google Play Store AAB. View them at: https://github.com/ExponentiallyDigital/cfg-pia-wg/attestations

---

## Data handling & privacy

**cfg-pia-wg** is architected to operate with a zero-retention, zero-persistence local data footprint to maximise user privacy:

- **Zero permanent footprint:** the application does not maintain long-term local telemetry, profiling metrics, or databases (`shared_preferences`, secure storage, or SQLite).
- **Two things are remembered on the device: the router's LAN address, and its SSH host key fingerprint.** Since build 410 a successful SSH connect writes the address you connected to into a single-line file in the app private storage, so it prefills next time instead of being retyped every session. Since build 478 a second file holds the router's host key fingerprint, the public line `ssh` prints, so the next connection can be checked against it. Neither is a credential: the address is a private-range address that identifies nothing outside your own network, and the fingerprint is public by design. No username, no password, no generated configuration. Both are written only after a login has succeeded, so a wrong address or an impostor at first connect never replaces a good record; `android:allowBackup="false"` keeps them off Google Drive; and SETTINGS -> FORGET ROUTER IP deletes both, and reads the store back to say whether it worked. A source-scanning test fails the build if the address file ever learns to write anything else.
- **What the store sees.** Once purchasing is enabled the app talks to Google Play and to RevenueCat, and that is the one place data leaves the device that is not the user's own router or Private Internet Access. RevenueCat receives the purchase history for a **pseudonymous installation identifier it generates itself**, and those purchase records are what tell the developer how many copies have sold. It collects no crash logs or diagnostics, and this app has no crash reporting of its own. It is never told who you are: the app makes no account, asks for no email, and never calls RevenueCat's `logIn`, so the identifier is anonymous and is not linked to any identity the app holds. There is still no analytics, no advertising identifier and no usage tracking of any kind.
- **Shared configuration files:** SHARE writes the `.conf` to a temporary file and deletes it when the share sheet returns. The sharing library, share_plus, first copies that file into its own cache folder and hands the other app the copy, because the other app may read it after the sheet has closed. That copy, private key included, is deleted when you leave the config screen, when the app exits, and when it next starts. Until build 478 it stayed until the next share, while this page said the file was wiped immediately. Deleting a file does not overwrite it on the storage chip, and the app does not claim to.
- **Clipboard:** a copied configuration is marked sensitive, so Android 13 and later show dots instead of its text in the clipboard preview. The app clears the clipboard 60 seconds after a copy, and when it exits. If Android kills the app inside those 60 seconds, the countdown dies with it, so the app also clears its own copy the next time it starts - its own only, recognised by its label, never something you copied from elsewhere. A keyboard's own clipboard history is the keyboard's, and the app cannot reach it.
- **Keyboard learning:** every text field asks the keyboard not to learn from what is typed (`IME_FLAG_NO_PERSONALIZED_LEARNING`), as well as turning off suggestions and autocorrect. Until build 478 only the last two were set. Whether a keyboard honours the request is up to the keyboard.
- **Native task-switcher protection** `(FLAG_SECURE)`: enforces native OS-level window flags to block third-party screenshot capturing and automatically obfuscates/blanks the app layout view inside the Android Recent Apps / Task Switcher interface.
- **Native screen capture protection:** the implementation forces native Android system window attributes (`FLAG_SECURE`). This explicitly instructs the host OS kernel to block third-party screenshot captures and automatically obfuscates or blanks the active UI presentation when viewing screens inside the system's Recent Apps / Task Switcher interface.

---
