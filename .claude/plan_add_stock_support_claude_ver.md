# Stock ASUS firmware support alongside Merlin

## Context

Today the app assumes Asus-Merlin everywhere it touches the router. `router_slots_screen.dart:132`
hard-gates the watchdog screen on `nvram get 3rd-party == 'merlin'`, and every NVRAM read/write
assumes Merlin's 17-field `wgcN_*` layout, Merlin's `jq` on `$PATH`, BusyBox `sendmail`, and
`/jffs/scripts/services-start` for cron persistence.

Stock ASUS firmware differs in five ways that matter: it exposes only 12 of the 17 `wgcN_*` fields
and keeps region + active-state in a single delimited `vpnc_clientlist` string; it has no `jq` or
mail binary on `$PATH` (the user installs them under `/jffs/cfg-pia-wg/`); it has no `sendmail`
worth using (hence `mailsend-go`); and it has no `services-start` equivalent, so `cru` entries do
not survive a reboot unless an already-executed init script is hijacked.

Outcome: both firmwares work from the same screens, chosen by a once-per-session detection on entry
to either router screen. This is deliberately an **interim step** — `if (isStock) … else …` inside
the existing classes. No `FirmwareService` / `RouterCommandStrategy` abstraction; that is a later
release.

## Decisions taken (from clarification)

| Question | Decision |
| --- | --- |
| `nvram get 3rd-party` empty | **Stock.** Only non-zero exit / SSH error / timeout is a failure. Contains `merlin` (case-insensitive) → Merlin. Any other non-empty value → unsupported dialog. |
| New `vpnc_clientlist` record | Populate fields 1 (desc), 2 (`WireGuard`), 3 (slot), 6 (active), 7 (iptables ID = **10 − slot**), 12 (`Web`). Fields 4, 5, 8, 9, 10, 11 empty. |
| Watchdog script region source on stock | Mirror desc into an **app-owned `wgcN_desc` NVRAM key** (same practice as the already-invented `wgcN_wd_*` keys). Template needs no desc surgery. |
| Watchdog script path on stock | `/jffs/scripts/watchdog_wgcN.sh`, unchanged. |
| Binary gate | `jq` on the manage screen; `jq` **and** `mailsend-go` on the watchdog screen. |
| Service calls | Identical on both firmwares (`service "start_wgc N"`, `stop_wgc N`, `restart_vpnrouting0`, `start_vpnrouting0`). |
| JFFS setup on stock | `mkdir -p /jffs/scripts`; do **not** write `jffs2_scripts` / `jffs2_on`. |

## Conflicts to flag (do not silently resolve)

1. **`scripts/get-bins.sh` installs to `/jffs/bin`**, but the brief and this plan probe
   `/jffs/cfg-pia-wg/jq` and `/jffs/cfg-pia-wg/mailsend-go`. One of the two must change.
   `get-bins.sh` is out of scope here — raise it, don't edit it.
2. **`README.md` §4.1 step 3 is `<************** PLACEHOLDER **************>`.** The new dialogs
   link to `#4-prerequisites--requirements`, which exists, but the section does not yet tell the
   user where to install the binaries.
3. **The two files named in the brief are 47-line wrappers.** `manage_router_screen.dart` and
   `watchdog_management_screen.dart` both just render `RouterSlotsScreen(mode: …)`. The branching
   lands in the shared [router_slots_screen.dart](lib/widgets/router_slots_screen.dart); the two
   wrappers are untouched.
4. **Pre-existing doc bug:** `ARCHITECTURE.md` §3.3 lists the global keys as `cfg-pia-wg_user` /
   `cfg-pia-wg_password`; the code uses `cfg_pia_wg_user` / `cfg_pia_wg_password`. Flag only.

---

## Implementation

### 1. New: `lib/firmware.dart`

The session-scoped flag plus every stock path constant. A library-level cache (not a
`SessionController` field) so services with no controller — `RouterSlotService`, `RouterWatchdog` —
reach it without threading a parameter through four factories. Trivially deleted when the real
abstraction lands.

```dart
enum RouterFirmware { merlin, stock }

RouterFirmware? _cached;
RouterFirmware get routerFirmware => _cached ?? RouterFirmware.merlin; // default keeps existing tests green
bool get firmwareDetected => _cached != null;
bool get isStockFirmware => routerFirmware == RouterFirmware.stock;
void setRouterFirmware(RouterFirmware f) => _cached = f;
@visibleForTesting void resetRouterFirmware() => _cached = null;

const kStockBinDir = '/jffs/cfg-pia-wg';
const kStockJqPath = '$kStockBinDir/jq';
const kStockMailsendPath = '$kStockBinDir/mailsend-go';
const kS50Path = '/opt/etc/init.d/S50downloadmaster';
const kServicesStartPath = '/jffs/scripts/services-start';
const kReadmePrereqUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements';

String jqCommand([RouterFirmware? f]) => (f ?? routerFirmware) == RouterFirmware.stock ? kStockJqPath : 'jq';
```

Plus a pure classifier so detection is unit-testable without SSH:

```dart
/// null => unsupported firmware. Empty output is stock (the key is unset on stock).
RouterFirmware? classifyFirmwareTag(String raw);
```

Licence header on the new file, per the standing convention.

### 2. New: `lib/s50_template.dart`

`const String kS50DownloadmasterTemplate = r'''…'''` — a **verbatim** copy of
[scripts/S50downloadmaster-TEMPLATE.sh](scripts/S50downloadmaster-TEMPLATE.sh), same pattern as
`license_text.dart` mirroring `LICENSE`. A test asserts the two match byte-for-byte so drift fails
CI rather than a router.

Two pure helpers live here (or in `router_watchdog.dart` beside the other builders — prefer here to
keep the template and its parser together):

```dart
/// Pulls the cru lines currently sitting between the REPLACEMENT markers. '' => [].
List<String> extractS50CruLines(String existingScript);

/// Rebuilds the full script with [cruLines] between the markers, 4-space indented to match the
/// surrounding `case` arm. Everything outside the markers is copied unchanged.
String buildS50Script(List<String> cruLines);
```

Marker literals: `# ********** REPLACEMENT START **********` /
`# ********** REPLACEMENT END **********`.

### 3. New: `lib/widgets/firmware_notice.dart`

One dismissible dialog with a tappable link, serving both new warnings. Reuses the existing
guard-then-launch pattern at [about_screen.dart:95-100](lib/screens/about_screen.dart#L95-L100)
(`canLaunchUrl` → `launchUrl(mode: platformDefault)`, silent no-op on failure) and the
`Text.rich` + `TapGestureRecognizer` link styling from
[about_screen.dart:117-132](lib/screens/about_screen.dart#L117-L132).

```dart
Future<void> showFirmwareNotice(BuildContext, SessionController, {
  required String message,      // leading prose, may contain \n
  required String linkText,     // the tappable span
  String url = kReadmePrereqUrl,
});
```

Keys (`snake_case`, per convention): `firmware_notice`, `firmware_notice_link`,
`firmware_notice_ok`. Logs the message with `isError: true` and brackets with
`enterModal`/`exitModal`, matching `AppErrors._present`.

Two call sites:

- Missing binaries — `'Unable to locate: /jffs/cfg-pia-wg/jq, /jffs/cfg-pia-wg/mailsend-go\nSee '`
  + link `'Prerequisites in README.md'`. One path when only one is missing; comma-joined when both.
- Unsupported firmware — `'Your firmware type is not supported, see '` + link `'README.md'`.

### 4. `lib/widgets/router_slots_screen.dart` — the branch point

Rework `_onConnect` (currently lines 112-151). Detection must run **before** `fetchSlots()`, because
`fetchSlots` now reads different NVRAM depending on firmware.

```
client = await _connect()
if (!firmwareDetected) {
  raw = await svc.readFirmwareTag()          // throws on non-zero exit / SSH error / 5s timeout
      -> catch: AppErrors.system('Unable to determine router firmware type: …'); return  // flag NOT set
  fw = classifyFirmwareTag(raw)
  if (fw == null) { await showFirmwareNotice(unsupported…); return }  // flag NOT set
  setRouterFirmware(fw)
}
if (isStockFirmware) {
  missing = await svc.missingStockBinaries(needMailsend: widget.mode == SlotModalMode.watchdog)
  if (missing.isNotEmpty) { await showFirmwareNotice(missing…); return }
}
slots = await svc.fetchSlots()
… existing SlotModal open, unchanged
```

Delete the `// DISABLED MERLIN` block at lines 131-135 — the unsupported-firmware branch supersedes
it. Every early return leaves the user on the router-credentials screen, which *is* the previous
menu.

### 5. `lib/router_slot_service.dart`

**New SSH methods**

- `Future<String> readFirmwareTag()` — `nvram get 3rd-party`, `.timeout(Duration(seconds: 5))`.
- `Future<List<String>> missingStockBinaries({required bool needMailsend})` — `[ -x '<path>' ] && echo 1 || echo 0` per binary; returns the absent paths in `jq, mailsend-go` order.

**New pure helpers** (top-level in this file, no SSH — the unit-testable core of the stock work):

```dart
class VpncRecord { final List<String> fields; }        // always 12 entries
List<VpncRecord> parseVpncClientlist(String raw);       // records split on '<', fields on '>'
String serialiseVpncClientlist(List<VpncRecord> recs);  // no leading '<'
VpncRecord buildVpncRecord({required int slot, required String desc, required bool active});
List<VpncRecord> upsertVpncRecord(List<VpncRecord>, {required int slot, String? desc, bool? active});
List<VpncRecord> removeVpncRecord(List<VpncRecord>, int slot);
```

`upsert` matches on field 3 (slot number) and **preserves every field it does not own** on an
existing record — only fields 1 and 6 are ever rewritten. `buildVpncRecord` is used only when no
record exists, and applies the layout in the decisions table (field 7 = `10 - slot`).

**Branched methods** — Merlin path byte-identical to today in every case:

| Method | Stock behaviour |
| --- | --- |
| `fetchSlots` | One `nvram get vpnc_clientlist`; `desc` ← field 1, `enabled` ← field 6 == '1'. `killSwitch` always false (no `enforce` on stock). The `cru l` watchdog probe now runs on **both** firmwares — drop the `isMerlin &&` guard at line 118. |
| `createConfigToSlot` | Write the 12 stock keys **plus** the `wgcN_desc` mirror; skip `enforce`, `fw`, `ep_addr_r`, `rip`. Then `upsertVpncRecord(active: false)` and write it back. Backup/restore snapshot must include `vpnc_clientlist`. |
| `enableSlot` / `_revertEnable` / `disableSlot` | Flip field 6 in `vpnc_clientlist` alongside `wgcN_enable`, before the `service` call. Service commands unchanged. |
| `deleteSlot` | Unset the 12 keys + the `wgcN_desc` mirror + both `wd_*_ip` keys; `removeVpncRecord` and write back. |
| `readSlotParams` | Read the 12 + the `desc` mirror; the four Merlin-only keys resolve to `''`. |
| `writeSlotParams` | Skip `enforce`, `fw`, `ep_addr_r`, `rip`. When `desc` is present, write **both** `wgcN_desc` and `vpnc_clientlist` field 1. |

`RouterSlots.isMerlin` and the `nvram get 3rd-party` read inside `fetchSlots` stay as-is — one extra
round trip, zero churn in the existing suite. Note it as cleanup for the later refactor.

### 6. `lib/screens/slot_params_editor.dart`

On stock, hide the controls for fields that do not exist: the `enforce` and `fw` switches
(lines 123-124) and the `ep_addr_r` / `rip` read-only rows (lines 128, 130). All ten editable text
fields are valid on stock, so `_canSave` is unchanged.

### 7. `lib/router_watchdog.dart`

| Member | Change |
| --- | --- |
| `isJqInstalled()` | Stock: `[ -x /jffs/cfg-pia-wg/jq ]`. Merlin: `which jq`, unchanged. |
| `enableJffsScripts()` | Stock: `mkdir -p /jffs/scripts` only. Merlin: unchanged. |
| `buildWatchdogScript(cfg, {RouterFirmware? firmware})` | New optional param (defaults to the global) so both branches are unit-testable as pure functions. |
| `buildMailsendGoCommand(host, port, cfg)` | New sibling of `buildSendmailCommand`, exactly the invocation in the brief. Credentials on the command line are an accepted risk. |
| `buildMailPlainBody(cfg, {success, testMode})` | New. `mailsend-go` takes `-sub` + a headerless `body -file`, so it cannot reuse the RFC-822 `buildMailBody`. |
| `testEmail()` | Picks command + body builder by firmware. The three diagnostic layers (stderr → `nc` → `openssl s_client`) are firmware-independent and stay. |
| `_ensureServicesStart(slot, intervalMin)` | Branches — see below. |
| `stopWatchdog(slot)` | Stock: strip this slot's two cru lines from `/opt/etc/init.d/S50downloadmaster` via the same extract/rebuild helpers (not the Merlin `grep -v` one-liner, which would shred the template scaffolding), rewrite, `chmod 700`. If no cru lines remain, leave the file in place with an empty replacement block — it is a hijacked stock file, deleting it is worse. Everything else unchanged. |
| `deployWatchdog` | Order at lines 364-383 unchanged; only step 1 and step 7 branch internally. |

**Template substitution.** `_kWatchdogScriptTemplate` gains three placeholders alongside `__SLOT__`,
all resolved at build time so no conditional logic enters the script (heredoc ceiling ≈ 7 KB):

- `__JQ__` — the five `jq` call sites and the `which jq` preflight (line 767) become
  `[ -x __JQ__ ]` on stock.
- `__MAILBODY__` — the `{ echo … } > "$TMPMAIL"` block (lines 661-673). Merlin keeps the RFC-822
  headers; stock emits body lines only.
- `__MAILCMD__` — the `/usr/sbin/sendmail … < "$TMPMAIL"` invocation (lines 676-682). Stock
  substitutes the `mailsend-go` form.

The `nvset "enforce="` / `"fw="` / `"rip="` / `"ep_addr_r="` lines are left in place on stock: they
write app-owned keys the firmware ignores, exactly as `wgcN_wd_*` already does, and removing them
would cost template surgery for no behavioural gain. `nvset "desc="` is now correct on both
firmwares thanks to the mirror.

**Stock `_ensureServicesStart`:**

```
existing = await _run("cat '/opt/etc/init.d/S50downloadmaster' 2>/dev/null")
lines = extractS50CruLines(existing)
    ..removeWhere(mentions 'watchdog_wgc$slot ' or 'watchdog_log_rotate_wgc$slot ')
    ..addAll([buildCronCheckLine(slot, intervalMin), buildCronRotateLine(slot)])
heredocWrite(kS50Path, buildS50Script(lines))   // via _runHeredoc, 30s bound
chmod +x kS50Path
'/opt/etc/init.d/S50downloadmaster start'       // installs the cru entries immediately
```

The accumulate-then-rebuild shape is what makes multiple concurrent watchdogs work later; only one
is supported now. Reuses the existing `buildCronCheckLine` / `buildCronRotateLine` unchanged.

### 8. `lib/watchdog_dialog.dart`

`_load()`'s jq gate and the two user-facing strings (lines 151, 221, 332) become firmware-aware so
the message names `/jffs/cfg-pia-wg/jq` on stock. Flow, `_jqMissing` state, and SAVE gating are
unchanged.

---

## Tests

**Global-state hygiene is the main risk.** The firmware flag is a library global, so every suite
that touches router code must `resetRouterFirmware()` in `setUp`. Add a shared helper to
[test/watchdog_test_utils.dart](test/watchdog_test_utils.dart) and use it everywhere; a leaked
`stock` flag will produce confusing cross-file failures under parallel workers.

**Existing files to update**

| File | Why |
| --- | --- |
| `test/screens/router_screens_test.dart` | Several responders return `''` for `3rd-party`, which now means **stock**. Add `'merlin'` where Merlin is intended. Replace `watchdog CONNECT on non-Merlin firmware is rejected` with unsupported-firmware and stock-happy-path cases. |
| `test/router_slot_service_test.dart` | `watchdog flag is false on non-Merlin firmware` (line 75), the 17-key count (line 96) and the `deleteSlot` count (line 176) all move. Add a stock group covering `vpnc_clientlist` reads/writes. |
| `test/router_watchdog_service_test.dart` | Brief requires both jq branches. Add stock groups for `isJqInstalled`, `enableJffsScripts`, S50 deploy + `start`, `stopWatchdog` stripping, and `testEmail` via `mailsend-go`. |
| `test/router_watchdog_unit_test.dart` | `buildWatchdogScript` jq/mail assertions per firmware; `which jq` assertion at line 334 becomes branch-aware. |
| `test/watchdog_dialog_test.dart` | Responders key off `which jq`; add stock equivalents keyed off the `-x` probe. |
| `test/screens/slot_params_editor_test.dart` | New case: the four Merlin-only controls are absent on stock. |
| `test/widgets/slot_modal_test.dart` | Audit for firmware sensitivity; pin to Merlin where behaviour is unchanged. |

**New files**

- `test/unit/firmware_test.dart` — `classifyFirmwareTag` (empty → stock, `merlin`/`Merlin-386` → merlin, other → null), flag caching and reset, path getters.
- `test/unit/vpnc_clientlist_test.dart` — parse/serialise round-trip against the ARCHITECTURE §2.3.2 worked example; upsert preserves unknown fields; new-record layout (field 7 = 10 − slot, fields 4/5/8/9/10/11 empty); remove.
- `test/unit/s50_template_test.dart` — embedded constant matches `scripts/S50downloadmaster-TEMPLATE.sh` byte-for-byte; markers present; `extractS50CruLines`/`buildS50Script` round-trip; rebuild leaves all non-marker content untouched.
- `test/widgets/firmware_notice_test.dart` — **required by the brief.** Both dialogs render their exact copy, dismiss on OK, and the link is tappable. Mock `url_launcher` via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` on `plugins.flutter.io/url_launcher` and assert `canLaunchUrl` + `launchUrl` fire with `kReadmePrereqUrl`.

Coverage bar stays 80% (`coverage/lcov.info`).

## Docs

Update [.claude/CONTEXT.md](.claude/CONTEXT.md) — note the brief says `./claude/CONTEXT.md`; the
file is at `.claude/CONTEXT.md`. Brief and high-level, per the ask:

- §2 Snapshot — drop "(Merlin firmware only)" from the watchdog description.
- §3 — three new `lib/` files in the tables.
- New §4.x "Firmware detection & the stock branch" — the once-per-session flag, the three outcomes, the binary gate, and a stock-vs-Merlin table of paths (`jq`, mail binary, cron persistence file).
- §4.7 Preconditions — rewrite; the Merlin gate is gone.
- §4.9 NVRAM — add `vpnc_clientlist` with its field schema and the `wgcN_desc` mirror.

## Verification

```bash
flutter analyze          # must be clean; flutter_lints, no custom rules
flutter test             # all suites green — the hard gate before hardware
flutter test --coverage  # confirm >= 80%
```

Targeted while iterating:

```bash
flutter test test/unit/vpnc_clientlist_test.dart test/unit/firmware_test.dart \
             test/unit/s50_template_test.dart test/widgets/firmware_notice_test.dart
```

Then, on real hardware (your pass — no credentials here). Highest-risk items first:

1. **Stock, manage screen** — connect; confirm detection logs stock and the slot list shows regions read from `vpnc_clientlist`, not `wgcN_desc`.
2. **CREATE into an empty slot on stock** — verify with `nvram get vpnc_clientlist | ./scripts/read-vpnc_clientlist.sh` that the new record has field 7 = 10 − slot and fields 4/5/8/9/10/11 empty. *This is the inference most likely to be wrong.*
3. **ENABLE / DISABLE on stock** — the tunnel comes up **and** the router web UI reflects the active state (proves field 6 is being written where the firmware reads it). Confirms the shared `service "start_wgc N"` assumption.
4. **Watchdog deploy on stock** — `/jffs/scripts/watchdog_wgcN.sh` exists, `cru l` shows both entries, `/opt/etc/init.d/S50downloadmaster` contains exactly two cru lines between the markers with the rest of the template intact.
5. **Reboot the router** — `cru l` still shows both entries (the whole point of the S50 hijack).
6. **TEST EMAIL on stock** — arrives via `mailsend-go`; on failure check the router syslog for the three diagnostic layers.
7. **Missing-binary and unsupported-firmware dialogs** — rename `/jffs/cfg-pia-wg/jq` to force the warning; confirm the README link opens.
8. **Merlin regression** — one full watchdog deploy/stop cycle to prove nothing moved.
