# Plan: back off when PIA refuses

**Status:** IMPLEMENTED in v0.8.35 build 405. Agreed after build 402. Not current state — see `.claude/CONTEXT.md` section 4.8 for that.

## Why

PIA temporarily refuses token requests with **HTTP 403** after sustained re-registration. Observed twice on 2026-09-04: once mid-morning and once around 18:05, each clearing on its own after some tens of minutes. Confirmed by hand from the router:

```text
rc=22 http=[403]
curl: (22) The requested URL returned error: 403
```

and confirmed released later the same evening, when the script obtained a token normally with no change to the request.

The script retried every `COOLDOWN=120` seconds indefinitely. When PIA is refusing, that is precisely the behaviour that provokes and prolongs the block — and with two watchdogs it is a request a minute between them.

## What exists

- `COOLDOWN=120` in the script: a fixed floor between reconfigure attempts.
- `/tmp/watchdog_backoff_wgcN`: already holds an attempt count and a timestamp (`0\n0` on success), so the state needed for a growing backoff is there.
- The abort message now carries the status and body (`exit $RC, HTTP 403, body NNNB: ...`), so a refusal is distinguishable from a network fault in the log.

## Design

Grow the cooldown on **consecutive** failures, reset it on success. The agreed ladder, in minutes: **2, 4, 8, 16, 30, 60, capped at 90**.

| Consecutive failures | Wait before the next attempt |
| ---: | --- |
| 1 | 120 s (2 min, unchanged) |
| 2 | 240 s (4 min) |
| 3 | 480 s (8 min) |
| 4 | 960 s (16 min) |
| 5 | 1800 s (30 min) |
| 6 | 3600 s (60 min) |
| 7 and beyond | 5400 s (90 min) — the cap |

Any successful reconfigure resets the count to 0, so the common single-failure case is exactly as responsive as it was.

The ladder is **not** a clean doubling past 16 minutes, which rules out arithmetic: it is a lookup table, emitted into the script as a POSIX `case` by `buildBackoffCase()` from the same `kBackoffLadder` list that `backoffSeconds()` reads. One definition, two languages, and a test asserting they agree — the anti-drift arrangement the email layout already uses.

**Counting attempts, not checks.** `CNT` used to increment on every check that found a fault, including the ones the cooldown turned away. That made the growth rate depend on the check interval: at a 1-minute interval with a 120 s cooldown it rose by two per actual attempt, so a 1-minute watchdog escalated twice as fast as a 2-minute one. It is now incremented only past the gate, so a rung means the same thing on every schedule. This also makes the alert email's `Attempt: N` row honest — it had been reporting failed checks under an "attempt" label.

A run inside the wait logs why nothing is happening (`Backing off after 3 failed attempts: 45s of 480s elapsed`); a long quiet gap otherwise looks like the watchdog has stopped.

The failure email's `Attempt:` row names whichever of the backoff and the next cron tick comes later, so it never promises a retry sooner than one can actually happen.

## Risks

- A genuinely broken tunnel now takes longer to recover after repeated failures. That is the point, but the cap matters: 90 minutes is a deliberate ceiling, not a starting point for tuning upward.
- The script pays for this in bytes. It measured 16,183 bytes after this change, against the 24576-byte tripwire in `router_watchdog_unit_test.dart` — prune comments in the script before raising that again.

## Tests

`test/unit/backoff_test.dart`, 12 tests:

- `backoffSeconds` directly: the six rungs, the cap holding at 5400 s for 7, 8 and 500 failures, the first failure still waiting the original 120 s, and every rung longer than the one before.
- `buildBackoffCase()` emits exactly the expected POSIX `case`, and every rung in the shell matches the Dart function.
- The generated script no longer contains `COOLDOWN=120` or `$COOLDOWN`, and does contain the ladder.
- The increment sits **after** the early exit — the property that keeps the growth rate independent of the check interval.
- A success resets the count (the existing `0
0` write; asserted).
- A non-numeric backoff file reads as zero rather than crashing the arithmetic.
- The alert names `max(backoff, next tick)`, and a junk interval defaults to 300 s.

Verified against the real script by running it under stubbed `nvram`/`wg`/`ping`/`uptime`: the ladder reported 120, 240, 480, 960, 1800, 3600, 5400 and 5400 s for 1..7 and 12 consecutive failures, a second run inside the wait logged the backoff and made no attempt, and a success rewrote the file to `0 0`.
