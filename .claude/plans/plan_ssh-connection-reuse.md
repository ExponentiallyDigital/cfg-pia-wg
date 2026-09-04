# Plan: reuse the router SSH connection

**Status:** planned, not started. Agreed after build 402, to be done in a later build once the
watchdog is verified on hardware. Not current state — see `.claude/CONTEXT.md` for that.

## Why

Every user action opens its own connection: `widget.connect()` → `SSHClient` → authenticate → run a
handful of commands → `close()` in a `finally`. That is one dropbear login line in the router log
and one full SSH handshake **per action**, which is most of the delay between tapping a button and
seeing anything happen.

Reported symptoms: a large number of `dropbear[NNNN]: Password auth succeeded` lines in the router
log, and per-action TCP setup/teardown cost.

## What exists today

- `openSshClient(ip, user, pass)` in `router_slot_service.dart` — socket, `SSHClient`, `authenticated`.
- `RouterSlotsScreen._connect()` returns a **fresh** client each call, deliberately: its comment
  says "so a dropped connection self-heals on the next action". That self-healing is real and any
  reuse design has to replace it explicitly.
- The client is passed down as `connect: () async => client` into `SlotModal`, `WatchdogDialog`,
  `AboutScreen` (DEL PIA CERT) and the two router screens.
- Roughly **20 `client?.close()` calls** in `finally` blocks across those files.

## Design

A small `RouterSession` owning a nullable `SSHClient`:

```dart
class RouterSession {
  Future<SSHClient> client();   // live one, or reconnect
  Future<T> run<T>(...);        // optional: retry-once wrapper
  Future<void> close();         // idempotent
}
```

- **Owner:** `SessionController`, which already owns the SSH credentials and the session lifetime.
  Created on CONNECT; closed by `wipeAll()`, so every existing exit path already tears it down.
- **Call sites:** `await session.client()` instead of `await widget.connect()`, and **remove the
  `close()` from every action's `finally`** — a stray close would pull the connection out from
  under the next action.
- **Retry:** on a closed-connection error (`SSHStateError`, socket closed), invalidate, reconnect
  once, retry the command. This belongs in ONE place — `RouterSlotService._run` /
  `RouterWatchdog._run` — not at the call sites. Without it we trade dropbear noise for
  intermittent failures, which is a bad trade.
- **Keepalive:** set `SSHClient.keepAliveInterval`; routers drop idle sessions, and without this
  every action pays a reconnect anyway.
- **Backgrounding:** close on `AppLifecycleState.paused` and reconnect on demand. An authenticated
  session held open while the app is in the background is a slightly wider exposure than
  credentials in memory. `PiaWgApp` already observes lifecycle for `resyncOnResume`.

## Risks

- `service restart_vpnc` / `restart_firewall` can kill the session mid-action. Today the next
  action just reconnects; with reuse, the retry path is what saves us — test it hard.
- A stale-connection bug would present as an intermittent action failure, which looks exactly like
  the enable flakiness under observation after 402. Land this on its own build number so the two
  cannot be confused.

## Tests

- Reuse: two actions in a row open exactly one connection.
- Retry: a command that throws a closed-connection error reconnects once and succeeds; a second
  failure propagates.
- Lifecycle: `wipeAll()` closes it; `paused` closes it; the next action reconnects.
- No call site closes the shared client (a source scan, like the spinner-colour guard).
- The fakes' `close()` is a no-op, so most existing tests are unaffected, but the
  `connect: () async => ssh` plumbing in the harnesses becomes a session.

## Scope

The class and the retry are small. The bulk is the call-site sweep and the test harnesses.
