# Plan: "Promote release" on both stores (ID-468, ID-469)

Where each item stands is its `Now:` line in CHANGELOG.md, not here. This file holds the detail. ARCHITECTURE.md's appendix "Process - GitHub Actions workflows" describes what each workflow does.

## Log

Moved from the CHANGELOG items, word for word, 2026-10-21, when work items were made short:

- ID-468 REL: **"Promote release" promotes on Google Play and the App Store together, and a tag doesn't fail on a build Apple already has.**
  - **Why:** a tag already uploads to both stores, but only Play's half could be promoted. Andrew asked, 2026-10-21, for both stores to get each release from one dev-to-main merge and tag.
  - **The App Store's side of Play's tracks:** internal is TestFlight's Internal group, which already gets every build on the tag (ID-465). alpha and beta are the external TestFlight group Family: the build is added to it and sent to Beta App Review. `** PRODUCTION **` is App Review: the App Store version for the build's version number is found, or made from the last one, with the build's TestFlight notes as its "What's New"; the build is attached and the version submitted. A version already with App Review is left alone; one approved for a manual release is released; one on sale is reported. So production is run once to submit and, with a manual release, once more after approval.
  - **Built:** `scripts/app_store_connect.py promote`, whose next step for each state is a table of its own (`production_step`, `testflight_step`) with Python tests in `scripts/test_app_store_connect.py`, now run by the quality workflow. `promote.yml` gains an App Store job beside Play's, and a `stores` choice: both, Google Play only, or App Store only. Its dry run shows both stores' next steps and changes nothing. Play's job now checks the source track carries the build named, so one run can't promote two different builds.
  - **The tag:** `scripts/app_store_connect.py has-build` asks Apple whether it has the build number, and release.yml's iOS job skips the TestFlight upload when it has, since Apple refuses one twice. Build 534 went up from a manual run, for the submission, before v0.8.164 was tagged. The notes and testers step still runs, so the build takes the release's notes. release.yml's header names both stores.
  - **Done when:** v0.8.164's tag run passes with the iOS upload skipped and the release carrying the iOS SBOM (from ID-433), and a dry run of "Promote release" shows both stores' next steps.
- ID-469 REL: **the next tagged release's iOS build reaches TestFlight from the tag, and signing leaves no pile of certificates.** Split from ID-431 when it closed, 2026-10-21. v0.8.164's tag skips the upload, since Apple has build 534 from the submission run (ID-468), so a tag's own upload is first seen on the next release.
  - **Done when:** a tag's run uploads its build and it shows in TestFlight, and Andrew has checked Certificates, IDs & Profiles, Certificates, after it: if each run leaves a new certificate, the job keeps one in a secret instead (ID-418).

### 2026-10-21: v0.8.164 released, and the dry runs

- Tag run 39542215493 passed. Android went to Play's internal track with the corrected note. On iOS, "Is the build in App Store Connect already" found 534, the upload was skipped, and the notes and testers step ran. The release carries `cfg-pia-wg-v0.8.164_sbom.spdx.json`, `cfg-pia-wg-v0.8.164_ios-sbom.spdx.json` and the Dart licences.
- Dry run 39544201487, build 534, internal to alpha, both stores: Play would move 534 (v0.8.164) to alpha; TestFlight: build 534 not yet in Family, not yet sent to Beta App Review. Nothing changed.
- Dry run 39544205094, build 534, internal to production, both stores: Play would move 534 to production; App Store version 0.8.164 is WAITING_FOR_REVIEW, so nothing to do until Apple approves. Nothing changed.
