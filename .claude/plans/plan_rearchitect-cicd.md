# Plan: rearchitect the CI/CD pipeline

The reasoning behind ID-630. This file holds the measurements, the design and the options, never the status: where the work stands is in the work item. Written 2026-11-19, after v0.8.216, when Andrew asked whether the pipeline could be faster without being less safe, and whether the iOS app could be built once.

## End state

What does success look like? A release where the app is always checked first, nothing is published unless it was, and the tag run takes minutes, not most of an hour. Fast and secure, in that order of difficulty, since the checks are what keep it secure.

Three rules, and the design follows from them:

1. **Verify once, build once, publish what was verified and built.** The same source is never checked or compiled twice for the same purpose.
2. **Secrets only where they are needed.** Nothing that runs on a pull request, or on code nobody has reviewed, can see a signing key or a store credential.
3. **A published build is provable.** It carries an attestation tying it to the source it came from, and the publishing job checks it before it uploads.

## What it costs today

Measured on 2026-11-19 from the v0.8.215 release run (44084408655), the v0.8.216 pull request checks (44324417770) and its dry run (44324446667).

| Stage | Jobs, in minutes | Runner |
| --- | --- | --- |
| Pull request checks | OSV 0, then in parallel: quality and tests 5 to 8, CodeQL for Java and Kotlin 9, debug build 5, release bundle 7 (since ID-623), MobSF after the debug build, iOS simulator 14 to 19 | 6 Linux, 1 macOS |
| Dry run on dev | the quality workflow again, a signed Android build, a signed iOS build 13 | the same again |
| Tag run | the quality workflow a third time, then the Android release 6 and the signed iOS build 13 | the same again |

- **iOS builds for one release:** three simulator builds and two signed ones, about 68 macOS minutes, before any re-run.
- **The serial path of a tag run:** version check, then the whole quality workflow (the macOS simulator build is its longest job, 14 minutes), then the signed iOS build (13). About 27 minutes, plus queueing. Nothing is published until all of it is done, though the two release builds do not need the quality workflow to compile.
- **macOS capacity:** on 2026-11-18 and 2026-11-19, iOS jobs waited for a runner and were cancelled after about 20 minutes ("The job was not acquired by Runner of type hosted", with GitHub's notice that macOS arm64 runners have longer queue times). It happened to a throwaway iOS job and twice to the pull request's simulator job, which passed on its third attempt after 19 minutes 27 seconds. Nothing in the workflow files causes it or can prevent it.

## Can the iOS build be reused?

- **The simulator build cannot.** It is a different target from the signed one, with a different architecture and SDK and no signing, so it can never become the release.
- **The signed build can**, between runs on the same source. Key a stored copy on the tree hash, `git rev-parse HEAD^{tree}`, and the toolchain versions. A clean merge of `dev` into `main` has the same tree as `dev`'s last commit: measured on 2026-11-19, `main` after pull request #84 and the release commit `ff1a257` had the same tree, `3958eb179c8f6243240be631ad453f50bc410caa`. So a dry run's signed build is the tag's, and a tag run needs no iOS compile at all when one exists.
- **Unknown, to be measured first:** whether the .ipa can be taken from one run and uploaded by another without re-signing. The distribution certificate is shared, and the development certificate each run makes is revoked at its end, so it should work. It has not been tried.

## The design from scratch

1. **Verify.** No secrets. Runs on every pull request and push, in parallel: static analysis and tests (split across shards, since CI takes 5 to 8 minutes for what runs locally in about one), OSV, CodeQL, MobSF, and a release-mode Android build with a throwaway key so R8 runs. The iOS simulator build runs when `ios/`, a native plugin or a lockfile changes. It records one result against the source tree.
2. **Build.** Needs secrets, runs only for a release tag. The signed Android bundle and the signed iOS archive compile at the same time, alongside Verify, not after it. If a build for this exact tree exists, it downloads that one.
3. **Publish.** Waits for both builds. Needs a successful Verify for the same tree and a verified attestation for each build, then uploads to Play, TestFlight and the GitHub release with the SBOM. The secrets sit in a GitHub Environment, so only this job sees them, with approval if wanted.
4. **A weekly scheduled run** of the security scans only (OSV, CodeQL, MobSF), with no builds, since its job is to find a new vulnerability in code that has not changed.
5. **Reusable workflows.** One for Android and one for iOS, each with a mode (checks, or signed), so a pull request and a release run the same build steps.
6. **Required checks.** Branch protection requires Verify on `main`, and `main` is reached through a pull request only. A watcher workflow re-runs a job cancelled with "not acquired by Runner" once, so nobody watches for it.

**Why it stays secure:** nothing with a secret runs on a pull request from a fork; a build is tied to one source tree by its hash and proved by its attestation; GitHub isolates caches by branch, so a pull request cannot poison what a release restores; artifacts are taken only from runs on trusted refs.

| | Today | Redesigned (an estimate) |
| --- | --- | --- |
| iOS builds per release | up to 3 simulator and 2 signed, about 68 macOS minutes | 1 simulator on the pull request, when iOS changed, and 1 signed, about 25 |
| Tag run | about 27 minutes plus queueing | about 10 to 12: the signed builds, since Verify is done |
| Gate before release | the quality workflow run three times | Verify required once per tree, checked again at publish |

## Getting there in steps

Each step stands alone and leaves the pipeline working.

1. **A watcher** that re-runs a job cancelled for lack of a macOS runner, once. Skip the simulator build and the debug APK in the release run's copy of the quality workflow: the signed builds are stricter. Small.
2. **Split each release job into build and publish**, so the builds start with the checks and only the publishing steps wait for them. Saves about 14 minutes per tag run, and the gate holds: nothing publishes until every check is green.
3. **Reuse the signed iOS archive by tree hash, with attestation**, and make the tag run check that Verify passed for the tree instead of running it again. The biggest saving, and the biggest change to the gate, so it needs Andrew's decision (see below).
4. **Path filters for the simulator build**, and a scheduled run without builds.

## For Andrew to decide

- **The gate for a commit that reaches `main` other than by a pull request.** Checking "Verify passed for this tree" is as strong as re-running it when the tree is identical, and weaker when `main` has diverged. The fix is to require pull requests for `main`, and to fall back to re-running Verify when the tree has no recorded result.
- **An Environment approval on Publish.** It adds a click to every release, and takes the secrets out of reach of the earlier jobs.
- **Whether the dry run stays.** With R8 on the pull request (ID-623), its remaining job is to prove signing and the release workflow itself. It would run only when those change.

## Not in scope

`promote.yml`, `weekly_updates.yml`, `pia_key_check.yml`, `play_listing.yml`, `app_store_listing.yml` and `target_api_reminder.yml`. None of them builds the app.

## Log

- 2026-11-19: written from the analysis of v0.8.216's pipeline. No workflow has been changed for it.
- 2026-11-23: steps 1, 2 and 4 built, with Andrew's decisions of that day: no Environment approval on Publish, a fall back to the checks as they are and nothing that depends on branch protection (his token could not set it), the dry run kept, and step 3 only if it proves out. Step 3 was not built, since proving it needs a real upload of another run's .ipa to TestFlight.
- 2026-11-23: what was built. `release.yml`'s two release jobs need only the version check, build and sign beside the checks, and stop at "Wait for the quality and security checks" (`scripts/wait-for-checks.sh`, which passes only when every check job of the run has ended well and fails at once on any that has not) before the first step that publishes. A release run leaves out the debug APK, the release bundle, MobSF and the iOS simulator build, since the signed builds replace them. A pull request builds the simulator only when `ios/`, `pubspec.yaml`, `pubspec.lock` or the workflow changed. The weekly scan leaves out the release bundle and the simulator build, and keeps Sonar, OSV, CodeQL and MobSF. `rerun_unacquired.yml` re-runs the failed jobs once when one was not acquired by a runner.

## Time saved (ID-630)

Measured from the runs below, in minutes from the first job starting to the last finishing.

| Run | What | Minutes |
| --- | --- | --- |
| v0.8.219's tag run (45005122359) | before: the checks, then the Android release and the signed iOS build, with the simulator build the longest check (15.9) | 26.6 |
| v0.8.217's tag run (44731517855) | before | 26.8 |
| v0.8.216's tag run (44335215202) | before, with iOS runners queueing | 103.8 |
| A dry run of the new `release.yml` (45155542075) | after: checks and both signed builds side by side, the wait passing at +10.0 (Android) and +10.9 (iOS) | 10.9 |

- **Saved:** 15.7 minutes against v0.8.219, about 59%, and the checks' own longest job went from 15.9 minutes (the simulator build) to 9.2 (CodeQL for Java and Kotlin), which is now what sets the pace beside the signed iOS build's 10.7.
- **What the dry run did not do:** it uploaded nothing to TestFlight, which a tag run does, and the iOS job of v0.8.219's tag run took 10.1 minutes including that. So a real tag run should be a little over 11 minutes, and the figure is confirmed only when the next release runs (ID-685).
- **Two earlier runs** (45151547128 and 45153544197) failed their quality check, by accident, on tests the throwaway branch had not been given, and in each the release jobs ended at "Wait for the quality and security checks" with "a check did not pass", after building and before publishing anything.

## Work item detail, moved from BACKLOG.md (2026-11-22)

Moved verbatim on 2026-11-22: a work item line is at most two sentences (CHANGE-PROCESS.md section 3, `test/unit/work_item_length_test.dart`), and this item's first line was longer. Nothing was cut.

### ID-630

```text
- ID-630 BLD: rearchitect cicd, so a release is fast and the app is still always checked before it: verify once, build once, and publish what was verified and built. Today the same source is checked three times and built for iOS up to five times per release (three simulator builds, two signed, about 68 macOS minutes), and a tag run's serial path is about 27 minutes plus queueing. Raised 2026-11-19, after v0.8.216.
```
