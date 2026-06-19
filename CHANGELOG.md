# Changelog

## "to do"

- Release to Play Store - +12 testers for **closed test** over 14 continuous days

## Changes

2026-06-20 version: 0.5.01+328

    - implemented a feature to automatically maintain a persistent WireGuard VPN on the router

2026-06-19 version: 0.5.00+327

    - refined watchdog.md
    - version bump ahead of watchdog implementation

2026-06-19 version: 0.4.35+325

    - updated watchdog.md

2026-06-19 version: 0.4.35+325

    - fix typo in lib\router_push.dart array for the 'psk'
    - formating of license header in dart modules
    - updated context.md
    - added watchdog.md, requirements and spec for setting up the new watchdog feature

2026-06-16 version: 0.4.34+324

    - employed AI MOE to update scripts/build-optimisation.sh
    - finally started using a develop branch (about time!) :)

2026-06-15 version: 0.4.34+324

    - FIX environment error in scripts/build-optimisation.sh, wrong units used, attempted a 2PB RAM allocation (!)

2026-06-15 version: 0.4.33+323

    - updates to setting up an automated script for the build environment

2026-06-15 version: 0.4.32+32

    - updates to setting up an automated script for the build environment

2026-06-14 v0.4.32 build 322

    - split out build info to separate file
    - moved additional scripts to own folder
    - added build environment optimisation script
    - added playstore folder to version track submitted description
    - moved documentation sections from README to ARCHITECTURE.md, BUILDING.md, and CHANGELOG.md

2026-06-13 to 2026-05-31

    - add how to install `fcr` for HTML coverage report
    - feature/router-push merge to main & release
    - add README badge(s) for automated pipeline security & quality tests
    - refactored \_pushToRouter(), FIX WAN IP address determination
    - fix table display on README
    - add push to router steps & screenshots
    - added extensive build environment setup and config notes to README
    - added flow chart to readme
    - updated permission use (clarified)
    - add feature "push cfg to router"
    - increase automated tests to >90% of the codebase
    - added timestamps to LOG
    - update java version to 21(17)in release and code scan yaml
    - update screenshots for phone, 7" and 10" tablets showing clipboard clearing
    - rebuild release output files (drop zip, include 3 versions)
    - include software BOM (bill of materials) in release artifacts
    - add how to privately report a security vulnerability (enabled in GitHub)
    - create SECURITY.md
    - enable dependabot
    - implement local PS1 app to replace tags with SHAs
    - add SBOM as a release artifact (Syft)
    - fixup html intermediary file name (caused resultant doc title issue)
    - renamed `$ADDON` to `$RELEASE` in release.yaml (was carried over from WoW addon packaging)
    - split release.yaml into code scan and actual release
    - automated security/quality analysis: Flutter analyse, SonarCube, Google OSV dependency scan, Mobile security scanning (MobSF), Dependabot dependency management, and CodeQL analysis.
    - clear the clipboard after 60 seconds if conf copied there
    - review Actions CI pipeline - add Flutter analyse, rename pipeline
