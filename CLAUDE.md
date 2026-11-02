# CLAUDE.md

Pointers for an agent working in this repository. The detail lives in the documents named below; this file exists so the working agreements are loaded every session rather than found by luck.

## Read before starting work

- **[.claude/CONTEXT.md](.claude/CONTEXT.md), section 1 "Working agreements"** - how this project expects work to be done: tests required for every change, 80% coverage minimum, what counts as evidence, and why nothing is reported as done unless the real state was read back afterwards.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - how the app and the router scripts fit together, with the measured firmware behaviour behind each decision.
- **[CHANGELOG.md](CHANGELOG.md), the header above section 1** - the rules for work items: prefix codes, unique IDs shared with BACKLOG.md, and the rule that an item making a claim about protection is not done until a check that breaks the protected path has been seen to fail.
- **[TESTING.md](TESTING.md)** - the hardware test sheet, by test id.
- **[BACKLOG.md](BACKLOG.md)** - longer-term work, and where unverified bugs live. They never go in CHANGELOG.md.

## When investigating router behaviour

`.claude/CONTEXT.md` gives this in full, and it is the part most often skipped: watch the router rather than reason about it, sample over time, diff whole namespaces rather than the key you suspect, and treat a single observation as provisional until corroborated. Reach for measurement early, not after the guesses run out - a hypothesis-led probe costs a round trip on hardware at the maintainer's own keyboard, and the project's own history records eleven probes where the first eight were guesses and all eight were wrong.

## Conventions to know before the first edit

- Markdown is never hard-wrapped; unwrap what you touch rather than matching an old wrapped paragraph.
- Markdown prose follows `.claude/testing/voice-guide.md`.
- A protection's check belongs in `scripts/check-claims.sh`, which runs on the router unattended.
- Scripts copied to the router go in `/jffs/cfg-pia-wg`, the app's own directory, never loose in `/jffs` (CONTEXT.md section 1).
- Router instructions are given as one copyable block with real values filled in, not prose steps to type.
- Do not commit or push unless asked. Andrew always says when he wants Claude to commit, and these days usually asks rather than committing himself; when he commits, he does it himself. Every commit is a build and follows the steps at the top of CHANGELOG.md.
- Every CHANGELOG bullet is a work item with an ID, however small, including work found and done in the same pass; the only exceptions are a release result (`REL: vN.N.NN (NNN) passed ...`) and an audit line (`CHG: WIP|1.1|BACKLOG ...`). Give the ID when the bullet is written, not at commit time. `test/unit/changelog_ids_test.dart` enforces it (2026-11-02: nine items in builds 555 to 558 shipped without one).
- Before every commit that changes Dart code, check each new or changed function against SonarCloud's rules and fix it first: cognitive complexity at most 15, at most 7 parameters, no string literal three or more times. SonarCloud only sees what is pushed, so a local commit is the last point it can be caught cheaply (2026-11-01: 7 new issues first seen on PR #63 moved the release to another build). A dev-to-main PR is merged only at zero new Sonar issues, not just a passing quality gate: read them with `curl -s "https://sonarcloud.io/api/issues/search?componentKeys=ExponentiallyDigital_cfg-pia-wg&pullRequest=<n>&resolved=false"`.
- After every commit, and after every release (a dev-to-main merge and its tag), the next CHANGELOG release block, `<date> vN.N.NN build NNN - in progress`, must be open and `pubspec.yaml`'s `version:` must match it, both halves. Check at the start of any work and straight after a merge and tag. If the newest block has been committed, open the next one and bump `pubspec.yaml`. Never commit them on their own: they go in with the next commit.
