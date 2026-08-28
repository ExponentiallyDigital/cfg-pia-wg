Purpose of this change: add support for "stock" firmware while retaining "Merlin" firmware support.

Context: read ./claude/CONTEXT.md

As the app currently supports Merlin only, I want you to add support for stock by using if/then/else blocks to surround the existing logic in the `manage_router_screen.dart` and `watchdog_management_screen.dart` files. NB this is an interim step to get this feature enabled, in a future version this will be converted to a FirmwareService/RouterCommandStrategy abstraction - do not implement that now.

Implement firmware detection that triggers exclusively when the user navigates to `manage_router_screen.dart` or `watchdog_management_screen.dart`. Use `nvram get 3rd-party` do a case insensitive check for the word "merlin". If the command fails (non-zero exit code, empty/unexpected output, SSH connection failure, timeout etc), fall back to an error message then return to the previous menu. If successful, set/update an application flag in memory. Once this flag has been set, skip rechecking until the app is exited.

After you have detected the firmware type:

1. if stock
	1.1. Check binaries exist
 		1.1.1. /jffs/cfg-pia-wg/jq
		1.1.2. /jffs/cfg-pia-wg/mailsend-go
	1.2. Display a dismissible warning if either binary is missing explicitly say which file(s) could not be found and display this with a tappable link then return to the previous menu. If only one binary is missing use "Unable to locate: $BINARY1<newline>See [Prerequisites in README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)". If two are missing use this "Unable to locate: $BINARY1, $BINARY2<newline>See [Prerequisites in README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)".
	1.3. Stock uses both nvram entries `wgcN_` and a new entity called `vpnc_clientlist`, you must see ARCHITECTURE.md section "2.3. Router WireGuard NVRAM fields" for details of these.
	1.4. Use `mailsend-go` instead of `sendmail` for sending emails. Here is the command line for sending an email (it is an accepted risk passing the user name and password via the command line):
		/jffs/cfg-pia-wg/mailsend-go -debug -ssl -verifyCert \
		  -smtp "$SMTP_HOST" \
		  -port "$SMTP_PORT" \
		  -sub "Email subject" \
		  -f "$EMAIL_FROM" \
		  -t "$EMAIL_TO" \
		  auth -user "$SMTP_USER" -pass "$SMTP_PASS" \
		  body -file "$TMPMAIL"
	1.5. Instead of `jq` in the path which exists under merlin, as you have determined that we are on Stock, use `/jffs/cfg-pia-wg/jq`.
		1.5.1. `jq` is called in these files, wrap these in a conditional using the firmware detection flag you've added.
			/lib/watchdog_dialog.dart - this runs after the `watchdog_management_screen.dart`.
			/lib/router_watchdog.dart - this runs after the `watchdog_management_screen.dart`.
			/test/router_watchdog_service_test.dart - update this test file to cover both the stock and Merlin branches once the source is wrapped.
		1.5.2. There are calls to `jq` in the watchdog script that is generated from `const String _kWatchdogScriptTemplate` and deployed to the router, as there is a heredoc size limit pushing the script to the router, hardcode the location of `jq` based on what firmware we are running on - do not add conditional logic to `_kWatchdogScriptTemplate`.
2. Else if merlin use existing code logic
3. Catch, anything else display an error "Your firmware type is not supported, see [README.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements)" (make that a tappable link), then return to the previous menu.

You must scan for existing tests in the ./test folder that need to be updated after you have made your changes. For new code, create/extend tests, including but not limited to widget tests for the two new dismissible warnings (missing-binary and unsupported-firmware) and their tappable links. Coverage and test information is contained in ./claude/CONTEXT.md.

Success criteria: I will manually test on real hardware that the code is functioning as required (I won't give you credentials to login to my router).