# Plan: back off when PIA refuses

**Status:** planned, not started. Agreed after build 402, for the same session as
`plan_ssh-connection-reuse.md`. Not current state — see `.claude/CONTEXT.md` for that.

## Why

PIA temporarily refuses token requests with **HTTP 403** after sustained re-registration. Observed
twice on 2026-09-04: once mid-morning and once around 18:05, each clearing on its own after some
tens of minutes. Confirmed by hand from the router:

```text
rc=22 http=[403]
curl: (22) The requested URL returned error: 403
```

and confirmed released later the same evening, when the script obtained a token normally with no
change to the request.

The script currently retries every `COOLDOWN=120` seconds indefinitely. When PIA is refusing, that
is precisely the behaviour that provokes and prolongs the block — and with two watchdogs it is a
request a minute between them.

## What exists

- `COOLDOWN=120` in the script: a fixed floor between reconfigure attempts.
- `/tmp/watchdog_backoff_wgcN`: already holds an attempt count and a timestamp (`0\n0` on success),
  so the state needed for a growing backoff is there.
- The abort message now carries the status and body (`exit $RC, HTTP 403, body NNNB: ...`), so a
  refusal is distinguishable from a network fault in the log.

## Design

Grow the cooldown on **consecutive** failures, reset it on success:

- attempt 1 → 120 s (unchanged)
- then 240, 480, 960, capped at **1800 s** (30 min)
- any successful reconfigure resets the count to 0, so the common single-failure case is exactly
  as responsive as it is today.

Read the count from the backoff file, which is already written and reset. Keep it arithmetic in
POSIX sh — no `bc`, no arrays.

Consider logging the wait explicitly (`Backing off 480s after 3 failures`) so the log says why
nothing is happening; today a long quiet gap looks like the watchdog has stopped.

## Risks

- A genuinely broken tunnel now takes longer to recover after repeated failures. That is the point,
  but the cap matters: 30 minutes is a deliberate ceiling, not a starting point for tuning upward.
- The script pays for this in bytes; it is close to the 10000-byte tripwire in
  `router_watchdog_unit_test.dart`. Prune comments in the script before raising it again.

## Tests

- The backoff sequence is a pure function of the attempt count — test the emitted script contains
  the arithmetic, and unit-test the sequence if it can be factored into Dart.
- A success resets the count (the existing `0\n0` write already does this; assert it).
- The cap holds at 1800 s.
