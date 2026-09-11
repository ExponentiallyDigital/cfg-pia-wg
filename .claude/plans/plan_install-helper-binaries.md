# Plan: install `jq` and `mailsend-go` for the user

**Status:** DRAFT, not started. Backlog item: `BACKLOG.md` 1.1 "ADD: install `jq` and `mailsend-go` for the user". Starting point is `scripts/get-bins.sh`. Not current state — see `.claude/CONTEXT.md` for that.

## Why

Stock firmware needs two binaries the app cannot do without: `jq` to parse PIA's JSON, and `mailsend-go` to send watchdog alerts. Today the user installs them by hand with `scripts/get-bins.sh` over SSH, which means a terminal, a script from GitHub, and a step that has nothing to do with the app they just installed. The app already detects both are missing (`missingStockBinaries`) — it just cannot do anything about it.

That friction is not hypothetical: it is what drove the maintainer to Merlin in the first place, and being able to stay on stock is the point of the stock support added in 0.9. A user who hits this wall has no reason to believe the app works at all.

## Shape

When MANAGE or WATCHDOG opens on stock and a needed binary is missing, offer to install it. Five things decide whether this is a good feature or a liability.

### 1. Ask, do not do it silently

This downloads an executable and runs it on the user's router. That is not a detail to bury in a spinner. The prompt names what is being installed, the version, the source URL, the destination and the size, and the user says yes.

**Offered as a convenience, not imposed.** The app is doing the user a favour here, not asserting a right to put files on their hardware. Someone who would rather install the binaries themselves must be able to decline and still get on with it — so the decline path shows what `scripts/get-bins.sh` does and where the files go, rather than a dead end.

**And it has to be honest about the consequence.** MANAGE and WATCHDOG genuinely cannot run without these on stock, so declining means the screen stays unavailable. Say that in the prompt, before the user chooses, rather than letting them decline and then discover it. A refusal is remembered for the session so the prompt does not nag on every screen entry; the existing blocking message remains for anyone who declined.

### 2. Only what the screen needs

`missingStockBinaries(needMailsend:)` already gets this right — MANAGE never sends email, so it must not demand `mailsend-go`. The prompt inherits that: offer exactly the binaries the current screen requires, and do not mention the other one.

### 3. Supply chain — the part that needs the most care

`get-bins.sh` resolves "latest" from the GitHub API and `wget`s whatever comes back. That is fine for a maintainer at a terminal and not fine as an app feature:

- **Unpinned.** Whatever is latest at that moment lands on the router, including a breaking release or a compromised one.
- **Unverified.** No checksum. BusyBox `wget` on stock has weak or absent TLS validation, so the download is exposed in a way the rest of the app is not — PIA's `addKey` is CA-pinned with a CN check, and SMTP uses `openssl s_client -verify_return_error`. This would be the softest thing the app does.

**Pin the versions and ship SHA-256 checksums in the app.** After download, hash on the router and refuse to install on mismatch. `openssl dgst -sha256` is the safer bet for computing it — `openssl` is already known present, since the watchdog uses `openssl s_client` for SMTP; `sha256sum` may or may not exist in the BusyBox build and must be probed before being relied on.

**Hash what was downloaded, not what was unpacked.** The two binaries arrive differently and this decides whether a checksum can be corroborated at all:

- `jq` is a **raw binary**. The file that lands is byte-for-byte the released asset, so its hash is directly comparable to the checksum upstream publishes. Independently verifiable.
- `mailsend-go` is a **`.tar.gz`** that `get-bins.sh` extracts, then moves the binary out of. Hashing the extracted binary produces a value nothing upstream publishes, so it can only ever be trust-on-first-use - it says "this is the same as the copy we happened to download once", not "this is the release the author signed".

So **verify the archive before extracting it**, and pin the archive checksum. The extracted binary is then trusted by derivation from something that can be checked against upstream. `get-bins.sh` should be changed to match, since it is the reference the app is built from.

While there: `find ... -name "mailsend-go*" | head -1` picks whichever entry the archive happens to list first. Extract the exact expected path instead - a glob plus `head` is not a specification.

> [!NOTE]
> **Considered and rejected: download on the phone, push over SSH.** The phone has real TLS and a real trust store, so this would remove the router's weak `wget` from the path entirely. But dropbear on stock has no SFTP or SCP, so the bytes would have to go through the command channel — `MAX_CMD_LEN` is 9000, and `mailsend-go` is around 6 MB, which is roughly 900 round trips. Too slow to be acceptable. Pinned checksums get most of the safety without it.

#### The pins - VERIFIED 2026-09-07

Downloaded on hardware, hashed on the router, and each hash checked against the checksum the project publishes. Both matched exactly, so these are the release artefacts and not something a middlebox substituted.

`jq` 1.8.2 - raw binary, so the hash is of the installed file:

```text
8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309  jq-linux-arm64
78458244fb546469b4042e9e07cf78714ef6848895eb9515df76b4eb0b1dc992  jq-linux-armhf
```

`mailsend-go` v1.0.12 - archives, so the hash is of the **`.tar.gz`**, checked before extraction:

```text
408bedba0cfbcb5cdc94d4b4575d43c3d40d9fbb0b62c766da3f057987acd731  mailsend-go-v1.0.12-linux-arm64.d.tar.gz
5a35d15b1fa54b5e0da769327c635d9ea6db124df34c5656f61c71af5bc942af  mailsend-go-v1.0.12-linux-arm.d.tar.gz
```

Sources, both fetched from the release:

- `https://github.com/jqlang/jq/releases/download/jq-1.8.2/sha256sum.txt`
- `https://github.com/muquit/mailsend-go/releases/download/v1.0.12/mailsend-go-v1.0.12-checksums.txt`

The arm64 pair was verified end to end on an RT-ABCD (`uname -m` = `aarch64`). The armhf/arm pair comes from the same published checksum files but has **not** been run on hardware - it is the fallback the execute-test exists to catch.

Only the arm64 side is confirmed working, so treat a 32-bit install as unproven until someone runs it.

### 4. Architecture, decided empirically - AGREED

`uname -m` reports `aarch64` or `armv7l`, and `get-bins.sh` maps those to `linux-arm64` / `linux-arm` and `linux-arm64` / `linux-armhf`. A 64-bit kernel with a 32-bit userspace is common on these devices, so the reported architecture is a hint, not an answer.

So: pick by `uname -m`, install, then **run the binary** (`jq --version`, `mailsend-go -h`). If it will not execute, try the other architecture before giving up. Only if both fail is it a real failure — and then say so plainly, name the reported architecture, and point at `scripts/get-bins.sh` for a manual attempt rather than leaving a broken file in place.

The execute-test is worth running even on a binary that was already there: it catches a half-finished earlier download and a stick that was pulled mid-write.

### 5. Check free space first, in two places - AGREED

Filling `/jffs` on a router is not a small mistake: it is where the app keeps the watchdog scripts and the cached PIA CA, and the firmware keeps its own state there. Running out mid-write leaves a truncated binary that the execute-test will reject but that still occupies the space.

**Two partitions matter, not one.** `get-bins.sh` downloads to `/tmp` and extracts there before moving the result, and `/tmp` on these routers is tmpfs - RAM, not flash. So:

| Partition | Needs | Why |
| --- | --- | --- |
| `/tmp` | ~2x the archive | the tarball plus its extracted contents exist at the same time |
| `/jffs` | ~7 MB | roughly 1 MB for `jq`, 6 MB for `mailsend-go`, plus headroom |

`df` is BusyBox and reports 1K blocks; parse the available column for each mount rather than assuming a total. Check **before** downloading, not after.

If either is short, say which one and by how much - "`/jffs` has 3 MB free, this needs 7 MB" is actionable and "installation failed" is not. Do not attempt a partial install, and do not delete anything to make room: the app did not put whatever is there and must not decide it is expendable.

Clean up `/tmp` afterwards whether the install succeeded or failed, since a 6 MB leak in RAM persists until the next reboot.

## Sequencing against freemium

`BACKLOG.md` 1.2 gates router management behind the lifetime unlock. **The entitlement check must come first.** A user without the unlock should see the entitlement message, not "jq is missing" — being told to install a dependency for something they cannot use either way is worse than being told the truth. So: entitlement gate, then binary check, then prompt.

## Other things it has to handle

- **Destination.** `/jffs/cfg-pia-wg`, as now. Not `/opt`: that lives on the USB stick, which the user can pull.
- **Upgrades.** With versions pinned, the app can notice an installed binary that is not the pinned version and offer to replace it. Worth having, not worth blocking on.
- **`clearall.sh` already leaves both alone** deliberately — "you installed those by hand; re-downloading them is a chore". Once the app installs them, revisit whether that still holds.

## Tests

- Pure: architecture mapping, checksum comparison, the "try the other architecture" fallback, and the free-space check.
- Seams: the existing `RouterSlotService` constructor-injected factories pattern. No network in tests — the download step takes an injected fetcher.
- A test that the entitlement gate precedes the binary check, so the ordering above cannot regress silently.
- A test asserting every pinned checksum is a well-formed SHA-256, so a placeholder cannot ship.
