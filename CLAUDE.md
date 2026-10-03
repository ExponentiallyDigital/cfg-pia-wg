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
- Router instructions are given as one copyable block with real values filled in, not prose steps to type.
- Do not commit or push unless asked.
