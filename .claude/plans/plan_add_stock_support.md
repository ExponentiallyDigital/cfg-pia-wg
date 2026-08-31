Purpose: add stock ASUS firmware support alongside the existing Merlin support.

Context: read ./claude/CONTEXT.md and ./ARCHITECTURE.md section 2.3 (Router WireGuard NVRAM fields) before starting.

Approach: this is an interim step. Wrap the existing Merlin logic in manage_router_screen.dart and watchdog_management_screen.dart in if/else blocks branching on firmware type. Do not build a FirmwareService/RouterCommandStrategy abstraction yet, that will come in a later release.

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

5. services-start file location and content (stock only):
   - Stock has no service-start script and cru entries do not persist past a reboot/power cycle, so the only way to get cru entries loaded at boot or after a power cycle is to hijack an unused script called /opt/etc/init.d/S50downloadmaster which is automatically executed by the router at boot time, and/or if a firewall restart event occurs.
   - Read the file ./scripts/S50downloadmaster-TEMPLATE.sh so you understand what this section is required to do.
   - To ensure that the app has a copy of this file, embed it as a string constant in the app.
   - To populate the ./scripts/S50downloadmaster script on stock, instead of _ensureServicesStart writing to /jffs/scripts/services-start (Merlin behaviour), _ensureServicesStart will use the contents of the repo file ./scripts/S50downloadmaster-TEMPLATE.sh which will be edited then deployed to the router as /opt/etc/init.d/S50downloadmaster.
   - All existing content in the template must remain unchanged, other than between the delimiters REPLACEMENT START and REPLACEMENT END below.
   - Search for the block below and add what you would have written to /jffs/scripts/services-start instead to /opt/etc/init.d/S50downloadmaster:

     ``` text
     # ********** REPLACEMENT START **********
     # 1 to N cruCheckLine entries
     # 1 to N cruRotateLine entries
     # ********** REPLACEMENT END **********
     ```

   - The placeholder cruCheckLine is to be populated by the existing call to buildCronCheckLine.
   - The placeholder cruRotateLine is to be populated by the existing call to buildCronRotateLine.
   - As with /jffs/scripts/services-start, there may be multiple cruCheckLine and cruRotateLine line items in /opt/etc/init.d/S50downloadmaster, one per watchdog. For now we only support one watchdog, but a future release will allow for multiple concurrent watchdogs (but only one per region).
   - After deploying the new /opt/etc/init.d/S50downloadmaster script, run it with the start argument so cru entries are installed immediately.
   - If the watchdog is disabled by function stopWatchdog, the logic to search for and remove appropriate cru entries already exists in this function , only the filename and path have changed from /jffs/scripts/services-start to /opt/etc/init.d/S50downloadmaster.

## Branch: merlin

Use the existing logic unchanged.

## Branch: anything else

Show: "Your firmware type is not supported, see [README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)" (tappable link), then return to the previous menu.

## Tests

Scan ./test for anything these changes affect and update it. For new code, add tests, including widget tests for both new dismissible warnings (missing-binary and unsupported-firmware) and their tappable links. Test/coverage conventions are in ./claude/CONTEXT.md.

## Docs

Add a brief and high level update to CONTEXT.md to reflect the new stock firmware support once the change is complete.

## Success criteria

I'll manually verify on real hardware, no router credentials will be provided. All automated tests must pass before that.
