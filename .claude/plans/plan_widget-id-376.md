# Plan: a home-screen widget (ID-376)

**Agreed 2026-10-12** (Andrew, slice by slice). Tracked as ID-376, with ID-378 for the check the "status only" claim rests on. **Where this item stands is in CHANGELOG.md, not here** - see "Build order" below for why that matters.

## The end state

A 4×2 and a 2×1 Android home-screen widget, showing each WireGuard tunnel's state, where it exits, and what the guard is holding offline, refreshed in the background without the app being open, using one restricted SSH key as the first credential the app keeps.

## Where this stands, from BACKLOG ID-376

- Andrew's decisions, 2026-10-12: yes to the key; yes to keeping the last status on the phone through EXIT.
- Measured on stock (Dropbear v2022.82): the key's own restrictions block another command, and block reaching another host through the router.
- The third restriction, blocking the key from making the router listen on a forwarded port, was measured by Andrew himself, outside this session, with a tool other than Claude: pass, port opened for an unrestricted key, no port opened for the restricted one.
- Andrew has since added a check for this to `scripts/check-claims.sh` by hand (see review below).
- Not yet measured: how stock copies NVRAM's `sshd_authkeys` into the key file Dropbear reads, which decides how the app installs its own key so it survives a reboot.

## Review of the check added to `scripts/check-claims.sh`

This is a review of code already in the working tree, not a live action against a router - it's in scope for me to do.

```sh
if ps w | grep '[d]ropbear' | grep -qE -- '-[jk]( |$)'; then
  pass SSH-forwarding "Dropbear daemon has port forwarding disabled (-j/-k)"
elif [ "$(nvram get sshd_forwarding)" = "0" ]; then
  pass SSH-forwarding "NVRAM sshd_forwarding is disabled (0)"
else
  SSH_PORT="$(nvram get sshd_port)"; [ -z "$SSH_PORT" ] && SSH_PORT=22
  LISTEN_LEAKS="$(netstat -tlpn 2>/dev/null | awk -v p=":$SSH_PORT" '$0 ~ /dropbear/ && $4 !~ p {print $4}')"
  if [ -z "$LISTEN_LEAKS" ]; then
    pass SSH-forwarding "No active SSH forwarded listening ports found in netstat"
  else
    fail SSH-forwarding "Dropbear is listening on unauthorized forwarded port(s)" "$LISTEN_LEAKS"
  fi
fi
```

Two problems, one of them the kind CHANGELOG's header rules out:

1. **It never exercises the protected path.** Every branch inspects state as it happens to be when `check-claims.sh` runs; none of them opens an SSH connection with the widget's restricted key and asks it to forward a port. On this router, from the 2026-10-12 measurement, neither the `-j`/`-k` flags nor `sshd_forwarding=0` are set, so it always falls to the `netstat` branch - and if nothing happens to be forwarding at that instant, which is true almost always, it passes without having tested anything. CHANGELOG's rule is that a protection claim isn't done until a check that breaks the protected path has been seen to fail; this check has no path to seeing that, because it never tries the break. It would need its own restricted key, an `ssh -R` attempt made during the check, and a read of whether a socket opened - the same three steps Andrew's own test already did by hand once.
2. **`netstat -p` is unverified on this firmware.** Nothing else in this project uses `netstat`, and BusyBox builds often compile it without `-p` (`CONFIG_FEATURE_NETSTAT_PRG`). If `-p` isn't compiled in here, no line will contain the word `dropbear`, `$LISTEN_LEAKS` is always empty, and the check passes regardless of what's actually listening - a silent false pass. Worth confirming with `netstat -tlpn 2>&1 | head -3` on the router before relying on this.

**Rewritten 2026-10-12** (Andrew: go). The new version installs a throwaway key, has the router dial itself with `dbclient` (confirmed present at `/usr/bin/dbclient`) and try to forward a port, and reads `/proc/net/tcp` directly for whether a listener appeared - no `netstat`, no flag that might not be compiled in. A control run with an unrestricted key must show a listener before the restricted run's result is trusted either way, the same check Andrew's own hand test applied. File-based backup of `authorized_keys`, matching what was actually measured working, not the NVRAM path, which stays unmeasured. Gated out of `dry`. **Not yet run on the router** - checked with `sh -n` only. First run should be `dry` then `quick`, read in full, before it's trusted in the regular suite.

## What I will build

### 1. The status read

One SSH round trip, over the app's existing authenticated session (the user's real login, the only one the app has ever used), gathering what DEVICES and MANAGE already read: which tunnels are up, each one's last handshake age, which devices are pinned to which slot, the guard's rule state, and the watchdog's state. Stock and Merlin both. This is the same shape of command as the rest of the app and needs no new access.

### 2. The widget's own key - setup, in the app, when the user opts in

- Generated on-device (`package:cryptography` or similar; confirm against THIRD-PARTY-NOTICES before adding).
- Installed over the user's own authenticated SSH session, the same way the app already writes other settings: appended to `sshd_authkeys` in NVRAM with the `command="…",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty` restrictions, so it survives a reboot. This is the measurement still outstanding - reading how stock's `>`-joined `sshd_authkeys` format is written, so the app appends rather than overwrites.
- The private half stored with `flutter_secure_storage` (Android Keystore-backed).
- A "remove widget key" action in SETTINGS that deletes it from both the router and the phone, and is also run automatically if the user turns the widget feature off.
- `no_secret_prefs_test`'s rule (nothing but the router IP survives in `router_prefs.dart`) doesn't cover this: the key lives in Keystore-backed secure storage, not that file, and needs its own test asserting that.

### 3. The widget

- Android native (Kotlin), since Android widgets can't be built in Flutter; the `home_widget` package passes data from the Flutter side to it.
- Two layouts, both already mocked up: 4×2 (header badge, one row per tunnel, footer with last-checked time and a refresh button) and 2×1 (badge and one line).
- Tap opens the app; the refresh button in the 4×2 layout triggers an immediate background read.

### 4. Background refresh

- `workmanager`, 15 minutes at the shortest, matching Android's own floor.
- Runs only when the connection is to the home network - the router's SSH only ever accepted LAN connections, so a refresh elsewhere fails harmlessly and the widget shows its age.
- On EXIT, the last successful read (tunnel regions, slot names, device names - no credentials) is kept so the widget isn't blank; this is Andrew's decision 2 above, and needs README, SECURITY.md and the privacy policy updated to say what's kept.

### 5. New dependencies, each checked before adding

- `home_widget`
- `workmanager`
- `flutter_secure_storage`
- a key-generation package (TBD against existing THIRD-PARTY-NOTICES entries)

### 6. Tests

- Key install/remove logic; the secure-storage test asserting nothing else is ever written there.
- Widget data formatting, both layouts, from a fixed status read.
- The status read itself, mirrored from existing DEVICES/MANAGE tests.
- A rebuilt `check-claims.sh` forwarding check, once it exercises the path itself (see review above), run on hardware.

## Build order, one slice per build

**Status is not recorded here. It lives in CHANGELOG.md, and only there** - ID-376 in WIP while this
is in flight, moved into the release block when it is done. This file is the design and the
reasoning behind it: why the shape is this shape, what was measured, what was rejected. On
2026-10-12 this section carried a "Done." marker per slice as well, and that was the whole cause of
CHANGELOG going five slices without an entry - ticking a slice off here felt like recording the
work, so the real record was never missed. One record, not two.

1. The status read, as a pure function over the data the app already fetches: no UI, no key, so the
   shape the widget shows can be tested before any of it exists.
2. The widget's two layouts, fed by a fixture, so the Android side can be built and looked at on a
   real phone before the key exists.
3. The key: generated on device, kept in Android's Keystore, with the SETTINGS action that makes or
   removes it - before it is wired to the router or to any background job, so each half can be
   judged on its own.
4. How stock holds more than one key, measured before anything writes to `sshd_authkeys`, then the
   install path: NVRAM so it survives a reboot, the live file so it works immediately.
5. The background refresh, on WorkManager's schedule and the widget's own button.
6. The documents: what is kept on the phone now has to be said in README, SECURITY.md and the
   privacy policy, and the forwarding check (ID-378) has to be run on hardware before the "status
   only" claim stands.

## Open, for Andrew

- Whether the existing `check-claims.sh` addition stays as-is, is rebuilt, or is dropped until it can be rebuilt.
- Confirming `netstat -tlpn` on the router actually prints `dropbear` against its listening line (the `-p` concern above).
- The NVRAM append measurement in step 4 - a short paste block, when this point is reached.
