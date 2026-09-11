# Plan: reuse the router SSH connection

**Status:** IMPLEMENTED in v0.8.36 build 406. Agreed after build 402. Not current state — see `.claude/CONTEXT.md` section 4.8.2 for that.

## Why

Every user action opens its own connection: `widget.connect()` → `SSHClient` → authenticate → run a handful of commands → `close()` in a `finally`. That is one dropbear login line in the router log and one full SSH handshake **per action**, which is most of the delay between tapping a button and seeing anything happen.

Reported symptoms: a large number of `dropbear[NNNN]: Password auth succeeded` lines in the router log, and per-action TCP setup/teardown cost.

## What exists today

- `openSshClient(ip, user, pass)` in `router_slot_service.dart` — socket, `SSHClient`, `authenticated`.
- `RouterSlotsScreen._connect()` returns a **fresh** client each call, deliberately: its comment says "so a dropped connection self-heals on the next action". That self-healing is real and any reuse design has to replace it explicitly.
- The client is passed down as `connect: () async => client` into `SlotModal`, `WatchdogDialog`, `AboutScreen` (DEL PIA CERT) and the two router screens.
- Roughly **20 `client?.close()` calls** in `finally` blocks across those files.

## Design — as built

`RouterSession` **implements `SSHClient`** rather than wrapping one behind a `client()` getter. That was the decision that kept the change small: the services still take an `SSHClient`, every `connect: () async => client` site still type-checks, and the test fakes still substitute for one. Only three members of the interface are ever touched (`run`, `close`, `authenticated`); the rest goes to `noSuchMethod`, exactly as the test fakes already do.

```dart
class RouterSession implements SSHClient {
  Future<SSHClient> client();   // live one, or open one; concurrent callers share the open
  Future<Uint8List> run(...);   // reconnect-once-and-retry on a transport failure
  Future<void> close();         // idempotent session teardown
}
```

- **Owner:** `SessionController.routerSession(connect)`, keyed on router IP + SSH username + password. A change to any of them builds a new session, because reusing a connection to a different box, or authenticated as a different user, would silently ignore what the user just typed.
- **Call sites:** unchanged in shape — `await widget.connect()` still returns something that behaves like a client. The **twenty `client?.close()` calls in `finally` blocks are gone**, and a source scan fails the build if one comes back.
- **Retry:** in `RouterSession.run`, not at the call sites. Only on `isConnectionLost(e)`: `SSHStateError`, `SSHAuthAbortError`, or a message containing closed / connection reset / broken pipe / socketexception. `client.run` returns a failing command's output rather than throwing, so a throw is nearly always transport-level — but re-running `nvram set` or a heredoc append because of an error we did not understand is worse than the original failure.
- **Liveness:** deliberately **not** `SSHClient.isClosed`. It only goes true after a clean close, so a connection the router silently dropped still reports itself open; and the test fakes route it through `noSuchMethod`, where it throws. A failed command is the honest test.
- **Keepalive:** dartssh2 already defaults `keepAliveInterval` to 10 s, so nothing to set.
- **Backgrounding:** `AppLifecycleState.paused` closes it. An authenticated session held open behind a locked screen is a wider exposure than credentials in memory, and the next action reconnects.

## Risks

- `service restart_vpnc` / `restart_firewall` can kill the session mid-action. Today the next action just reconnects; with reuse, the retry path is what saves us — test it hard.
- A stale-connection bug would present as an intermittent action failure, which looks exactly like the enable flakiness under observation after 402. Land this on its own build number so the two cannot be confused.

## Tests

`test/unit/router_session_test.dart` (19) and a `connection reuse` group in `test/screens/router_screens_test.dart` (2):

- Reuse: five actions open one connection; three concurrent first actions open one, not three; nothing opens until something is run.
- Retry: a lost connection reconnects and the command still runs on the new client, and says so in the app log; a second failure propagates rather than looping; the action after a drop reuses the replacement.
- No retry for an error the router itself raised, and `isConnectionLost` accepts the four transport shapes and rejects command errors.
- Teardown: `close` is idempotent, closes the live client, survives a client that throws on close, and the next action reconnects.
- Ownership: the same session comes back while credentials are unchanged, a changed password builds a new one, `wipeAll()` closes it.
- Source scan: no file under `lib/` calls `close()` on a client — the twenty removed `finally` closes cannot come back.
- Through the real screens: a second CONNECT opens no second connection, and closing the session (what pause does) means the next one reconnects.

## Scope — as built

The class and the retry were small, as expected. The call-site sweep was mechanical and the test harnesses needed **no changes at all**, which is the dividend of implementing `SSHClient` instead of introducing a new type.

One thing the plan did not anticipate: `test/unit/no_escaped_constants_test.dart`, the guard written after the `\$kRouterAppDir` bug, was **inert**. Its pattern `r'\\$[a-z]'` is a literal backslash followed by the end-of-string *anchor*, which nothing can follow, so it had matched nothing since the day it was written. A real `\$routerIp` introduced in this change went straight past it and was caught by a unit test instead. Pattern corrected to `r'\\\$[a-z]'`.
