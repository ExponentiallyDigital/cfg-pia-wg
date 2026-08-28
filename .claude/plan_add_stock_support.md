Purpose: add stock ASUS firmware support alongside the existing Merlin support.

Context: read ./claude/CONTEXT.md and ./ARCHITECTURE.md section 2.3 (Router WireGuard NVRAM fields) before starting.

Approach: this is an interim step. Wrap the existing Merlin logic in manage_router_screen.dart and watchdog_management_screen.dart in if/else blocks branching on firmware type. Do not build a FirmwareService/RouterCommandStrategy abstraction yet, that comes in a later change.

## Firmware detection

- Runs only on navigation to manage_router_screen.dart or watchdog_management_screen.dart, once per app session (cache the result in an in-memory flag, don't recheck until the app exits).
- Command: `nvram get 3rd-party`. Case-insensitive match for "merlin" in the output.
- Command failure (non-zero exit, empty/unexpected output, SSH failure, timeout) → show an error, return to the previous menu, do not set the flag.
- Success → set the flag to stock or merlin accordingly.

## Branch: stock

1. Check these binaries exist on the router:
   - /jffs/cfg-pia-wg/jq
   - /jffs/cfg-pia-wg/mailsend-go

   If either is missing, show a dismissible warning and return to the previous menu:
   - One missing: "Unable to locate: $BINARY\nSee [Prerequisites in README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)"
   - Both missing: "Unable to locate: $BINARY1, $BINARY2\nSee [Prerequisites in README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)"
   - The README link must be tappable.

2. Stock reads/writes both wgcN_ nvram entries and vpnc_clientlist. See ARCHITECTURE.md 2.3 for the field layout of both.

3. Send email via mailsend-go instead of sendmail:

   /jffs/cfg-pia-wg/mailsend-go -debug -ssl -verifyCert \
     -smtp "$SMTP_HOST" -port "$SMTP_PORT" -sub "Email subject" \
     -f "$EMAIL_FROM" -t "$EMAIL_TO" \
     auth -user "$SMTP_USER" -pass "$SMTP_PASS" \
     body -file "$TMPMAIL"

   Passing credentials on the command line is an accepted risk here, no change needed.

4. jq path is /jffs/cfg-pia-wg/jq on stock (vs the Merlin path already in use).
   - Dart-level jq calls live in lib/watchdog_dialog.dart and lib/router_watchdog.dart (both only run after watchdog_management_screen.dart, so the flag is guaranteed to be set). Wrap these in a conditional on the firmware flag. Update test/router_watchdog_service_test.dart to cover both branches.
   - Separately, the watchdog script generated from const String _kWatchdogScriptTemplate and deployed to the router also calls jq. Because of the heredoc size limit, do not add conditional logic inside the template itself, instead hardcode the correct jq path into the generated string at build time, based on the detected firmware.

## Branch: merlin

Use the existing logic unchanged.

## Branch: anything else

Show: "Your firmware type is not supported, see [README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)" (tappable link), then return to the previous menu.

## Tests

Scan ./test for anything these changes affect and update it. For new code, add tests, including widget tests for both new dismissible warnings (missing-binary and unsupported-firmware) and their tappable links. Test/coverage conventions are in ./claude/CONTEXT.md.

## Docs

Update ARCHITECTURE.md and CONTEXT.md to reflect the new stock firmware support once the change is complete.

## Success criteria

I'll manually verify on real hardware, no router credentials will be provided. All automated tests must pass before that.