# Contributing to cfg-pia-wg

- [1. Project expectations](#1-project-expectations)
- [2. How to contribute](#2-how-to-contribute)
  - [2.1. Fork the repository](#21-fork-the-repository)
  - [2.2. Create a feature branch](#22-create-a-feature-branch)
  - [2.3. Set up your development environment](#23-set-up-your-development-environment)
  - [2.4. Follow code style \& quality rules](#24-follow-code-style--quality-rules)
  - [2.5. Respect dependency pinning](#25-respect-dependency-pinning)
  - [2.6. GitHub Actions security requirements](#26-github-actions-security-requirements)
  - [2.7. Commit your changes](#27-commit-your-changes)
  - [2.8. Push and open a pull request](#28-push-and-open-a-pull-request)
- [3. Security‑sensitive contributions](#3-securitysensitive-contributions)
- [4. Testing guidelines](#4-testing-guidelines)
- [5. Build determinism requirements](#5-build-determinism-requirements)
- [6. Documentation contributions](#6-documentation-contributions)
- [7. Bugs \& feature requests](#7-bugs--feature-requests)
- [8. Code of conduct](#8-code-of-conduct)
- [9. Licensing](#9-licensing)
- [10. Thank you](#10-thank-you)

Thank you for your interest in contributing to **cfg-pia-wg**. A security‑sensitive, reproducible‑build Android application that generates Private Internet Access (PIA) WireGuard configurations and optionally deploys them to ASUS routers running stock or Asuswrt‑Merlin firmware.

This document explains how to contribute safely, consistently, and in a way that aligns with the project’s security and build‑determinism goals.

---

## 1. Project expectations

This project places strong emphasis on:

- **Security** (credential handling, memory safety, no persistence, certificate pinning)
- **Reproducible builds** (strict dependency pinning, deterministic CI)
- **Code quality** (Flutter analysis, high test coverage, SonarCloud, OSV scanning)
- **Supply‑chain hardening** (pinned GitHub Actions SHAs, SBOM generation)
- **Clear, auditable changes** (lockfile enforcement, structured PRs)

Contributions must respect these principles.

---

## 2. How to contribute

### 2.1. Fork the repository

Create your own fork on GitHub and clone it locally.

### 2.2. Create a feature branch

Use a descriptive branch name:

```bash
git checkout -b feature/<short-description>
```

Examples:

- `feature/router-slot-validation`
- `fix/latency-probe-timeout`
- `docs/update-build-instructions`

### 2.3. Set up your development environment

Follow the build instructions from the README:

- Flutter SDK ≥ 3.10
- Android Studio + JDK 17
- Android SDK Command-line Tools
- Physical device or AVD
- Run:

```bash
flutter clean
flutter pub get --enforce-lockfile
dart run flutter_launcher_icons
```

### 2.4. Follow code style & quality rules

Before committing:

- Run static analysis

```bash
flutter analyze
```

```bash
- Format all Dart code
flutter format .
```

- Run tests

```bash
flutter analyze
flutter test --coverage
```

> [!NOTE]
> This project targets **>80% test coverage**.  
> New features must include tests; PRs without tests will not be accepted.

### 2.5. Respect dependency pinning

This project uses **Gradle dependency locking in strict mode** and pinned Dart dependencies.

If you add or update dependencies:

1. Update the relevant Gradle or Dart manifest.
2. Regenerate lockfiles:

```bash
./android/gradlew -p android :dependencies :app:dependencies --write-locks
```

3. Commit the updated lockfiles.

PRs that modify dependencies **without updated lockfiles will fail CI**.

### 2.6. GitHub Actions security requirements

All GitHub Actions must be pinned to **full commit SHAs**, not tags.

If you modify workflows:

- Run the repository’s `update-shgas.ps1` script to regenerate pinned SHAs.
- Commit the updated workflow files.

### 2.7. Commit your changes

Use clear, conventional commit messages:

```bash
git commit -m "feat: add router slot description parsing"
git commit -m "fix: correct CA pinning fallback logic"
git commit -m "docs: update screenshots for tablet layout"
```

### 2.8. Push and open a pull request

```bash
git push origin feature/<short-description>
```

Then open a PR against `main`.

Your PR **must include**:

- A clear description of the change
- Test coverage for new logic
- Confirmation that `flutter analyze` passes
- Confirmation that lockfiles are updated (if applicable)
- Screenshots for UI changes (phone + tablet if relevant)

---

## 3. Security‑sensitive contributions

Because this app handles:

- WireGuard private keys
- PIA credentials
- Router SSH credentials
- Certificate pinning
- Memory‑resident secrets

…any contribution that touches authentication, cryptography, memory handling, or router‑push logic will undergo **enhanced review**.

If you believe you have found a security issue:

Please **do not open a public issue.** Follow the private reporting process in **SECURITY.md**.

---

## 4. Testing guidelines

All new features must include:

- Unit tests for logic in `lib/`
- Integration tests where applicable
- Router‑push logic tests using mocks (never real SSH)
- Tests for error paths, not just success paths

Coverage reports can be generated with:

```bash
flutter test --coverage
fcr coverage/lcov.info --open
```

---

## 5. Build determinism requirements

To maintain reproducible builds:

- Never commit keystore files
- Never commit generated artifacts
- Never modify CI signing logic
- Never introduce dynamic or floating dependency versions
- Never bypass lockfile enforcement

If a PR breaks reproducibility, it will be rejected.

---

## 6. Documentation contributions

Documentation updates are welcome.  
When updating screenshots:

- Provide phone + 7" + 10" tablet screenshots (as in README)
- Use consistent dark‑mode theme (`#12141A`)
- Place images under `/images/` with descriptive filenames

---

## 7. Bugs & feature requests

Use the GitHub Issues page:

- Provide reproduction steps
- Include device model + Android version
- Include relevant log output (sanitised)
- For router issues, include router model + Merlin version

---

## 8. Code of conduct

Be respectful, constructive, and security‑minded.  
This project values:

- Clear communication
- Evidence‑based reasoning
- High‑quality engineering
- Respect for user privacy and safety

---

## 9. Licensing

By contributing, you agree that your contributions will be licensed under the **GNU GPLv3**, the same license as the project.

---

## 10. Thank you

We deeply appreciate security researchers and contributors who help keep this project safe.
Your efforts directly protect users’ privacy, routers, and VPN credentials. If you have questions about this policy, please [open an issue](https://github.com/ExponentiallyDigital/cfg-pia-wg/issues) and/or see **SECURITY.md**.
