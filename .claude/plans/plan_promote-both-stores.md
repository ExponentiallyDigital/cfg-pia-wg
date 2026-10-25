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

### 2026-10-25: the certificates the CI runs left (ID-469)

- Andrew read Certificates, IDs & Profiles, Certificates: Andrew's own Development certificate (Xcode, expires 2027-10-14); one Distribution Managed certificate created by the App Store Connect API key (expires 2027-10-20); and 7 Development certificates "Created via API" by the same key, 4 expiring 2027-10-20 and 3 2027-10-21.
- release.yml ran 9 times on 2026-10-20 and 21 UTC (4 on the 20th and 5 on the 21st in Australian time), 3 of them failing, some before the archive. So about one Development certificate per run that reached the archive: the archive signs with a development identity, each runner starts with an empty keychain, and `-allowProvisioningUpdates` makes a new one each time. The distribution side is fine: the one cloud-managed certificate is reused.
- Apple caps how many Development certificates a team can have, so this would end in a failed release. Building the .ipa on the MacBook (ID-475) added none: it used Andrew's own.
- Fix to try first, needing no secret: archive with the distribution identity (`CODE_SIGN_IDENTITY="Apple Distribution"` on the archive), checked with a dry run from dev and a count afterwards. If Xcode refuses that with automatic signing, keep one Development certificate as a .p12 in GitHub secrets and import it into a temporary keychain, as the plan said. Then revoke the 7, which signed nothing that was distributed.

### 2026-10-25: the fix, in build 538 (ID-469)

- Not the first idea, signing the archive with the Distribution identity: the cloud-managed certificate's private key stays with Apple, so a local archive can't sign with it, and asking would most likely make a second, local Distribution certificate, of which a team gets even fewer.
- Instead the run cleans up after itself. "Note the team's certificates", before the archive, writes their ids to the runner (`app_store_connect.py note-certificates`); "Revoke the certificates this run made", after the last export and whatever failed (`always()`, once the note succeeded), revokes the new ones whose type is Development (`revoke-new-certificates`). Any other new certificate, such as a Distribution one, is left alone with a warning. The venv for the App Store Connect client moved into the note step, so a dry run has it too.
- Tests in `scripts/test_app_store_connect.py`: only new Development certificates are revoked, Andrew's own and the shared Distribution one never; the note comes before the archive and the revoke after the upload, under `always()`. Each was seen to fail with its code broken. Two runs at once could revoke each other's certificate mid-archive; release runs aren't run in parallel here.
- Left: a dry run from dev, after which the certificate count should be what it was before; then Andrew revokes the 8 "Created via API" Development certificates, by hand, leaving Andrew's own (expires 2027-10-14) and the Distribution Managed one.

### 2026-10-25: the dry run (ID-469)

- Dry run 40151279067 from dev, build 538, passed. "Note the team's certificates": 9 before the archive. The archive and export passed. "Revoke the certificates this run made": revoked `DEVELOPMENT "Apple Development: Created via API", expires 2027-10-25`, the one this run made; nothing else new.
- 9, not the 10 expected if v0.8.167's tag run had added an 8th: Andrew's own, the Distribution Managed one and the 7 Andrew counted. Which of the 7 are which isn't needed: all 7 "Created via API" Development ones go.
- Left: Andrew's count in Certificates, IDs & Profiles (9 expected), then revoking the 7 by hand.

