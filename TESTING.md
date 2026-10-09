# Testing cfg-pia-wg

The automated tests prove the code does what it says. They cannot prove what a real router, a real PIA account and a real device's traffic actually do, and that is where this app earns its keep or lets someone down. This file is that check: a run sheet to walk through before a release, then the reference behind it.

**Part 1. Run sheet**

- [How to use the run sheet](#how-to-use-the-run-sheet)
- [PRE. Before you start](#pre-before-you-start)
- [CON. Connecting to the router](#con-connecting-to-the-router)
- [HOM. Home screen and drawer](#hom-home-screen-and-drawer)
- [STD. Standalone](#std-standalone)
- [MAN. Manage](#man-manage)
- [WD. Watchdog](#wd-watchdog)
- [BRK. Break a tunnel](#brk-break-a-tunnel)
- [DEV. DEVICES: assignment, names and disabling](#dev-devices-assignment-names-and-disabling)
- [DEF. Default connection](#def-default-connection)
- [GRD. Fail-closed guard](#grd-fail-closed-guard)
- [LOG. App log and router log](#log-app-log-and-router-log)
- [SET. Settings](#set-settings)
- [ABT. About](#abt-about)
- [EXT. Exit, background and session](#ext-exit-background-and-session)
- [LCK. Locked, with no purchase (store build)](#lck-locked-with-no-purchase-store-build)
- [BUY. Buying and restoring (store build)](#buy-buying-and-restoring-store-build)
- [MRL. Merlin smoke test (under an hour)](#mrl-merlin-smoke-test-under-an-hour)
- [END. Last, because it removes things](#end-last-because-it-removes-things)
- [R1. When something looks broken, check these first](#r1-when-something-looks-broken-check-these-first)
- [R2. How the watchdog decides a tunnel is broken](#r2-how-the-watchdog-decides-a-tunnel-is-broken)
- [R3. The backoff ladder](#r3-the-backoff-ladder)
- [R4. What the watchdog leaves on the router](#r4-what-the-watchdog-leaves-on-the-router)
- [R5. Device assignment and default connection notes](#r5-device-assignment-and-default-connection-notes)
- [R6. Sending email by hand](#r6-sending-email-by-hand)
- [R7. Examining NVRAM](#r7-examining-nvram)
- [R8. Store testing notes](#r8-store-testing-notes)
- [R9. What the shape tests stand for, and what proves it](#r9-what-the-shape-tests-stand-for-and-what-proves-it)
- [R10. An AI assistant on the router and in an emulator](#r10-an-ai-assistant-on-the-router-and-in-an-emulator)

**Part 2. Reference**

- [R1. When something looks broken, check these first](#r1)
- [R2. How the watchdog decides a tunnel is broken](#r2)
- [R3. The backoff ladder](#r3)
- [R4. What the watchdog leaves on the router](#r4)
- [R5. Device assignment and default connection notes](#r5)
- [R6. Sending email by hand](#r6)
- [R7. Examining NVRAM](#r7)
- [R8. Store testing notes](#r8)
- [R9. What the shape tests stand for, and what proves it](#r9)
- [R10. An AI assistant on the router and in an emulator](#r10)

---

# Part 1. Run sheet

## <a name='how-to-use'></a>How to use the run sheet

- Each test has a label, such as `MAN-3`. Labels never change. A new test takes the next number in its group; nothing is ever renumbered.

- Each test's title ends with where it runs. `[hand]`: you do it and judge it. `[script]`: you press the buttons, and `e2e.sh` on the router does the checking and answers PASS or FAIL. `[ci]`: an automated test covers it, named in the test, so nobody runs it twice. `[retired]`: kept so its label is never reused, and no longer run.

- For a run, `dart run tool/runsheet.dart --set T=<TABLET> --set D=<DESKTOP> --set P=<PHONE> > .claude/testing/<date>_e2e.md` writes the run sheet: every `[hand]` and `[script]` test in order, with its group's start state, and nothing else. Write PASS, FAIL or SKIP on each Result line, with anything worth keeping.

- **Do:** what you do. **See:** what you get back. **Pass if:** how you know, only where it is not obvious.

- Stock firmware unless a test says otherwise. Merlin has its own short smoke test: see [MRL](#mrl).

- **Which build you need.** Every group here runs on any build - your own debug or release APK included - except [LCK](#lck) and [BUY](#buy). Those two need the app installed **from Play**, on a testing track, with the account on the licence testers list: a build Play did not distribute is always unlocked and never shows a paywall, so there is nothing there to test. [R8](#r8) has the rest of the store setup.

- Guest Wi-Fi is out of scope. The app does not manage its traffic or assignments.

Devices:

- **APP** is the phone running the app. It uses a random MAC.

- **TABLET** and **DESKTOP** are the devices you move between tunnels. Both have fixed MACs.

- **PHONE** is the same phone as APP, used only where a test says so, for the random MAC case.

- A virtual phone on the desktop can run the app, but the router sees it as DESKTOP. It is not a separate device to assign.

Shorthand:

- **Exit IP**: open a what-is-my-IP page on that device. Never check from the router: the router's own traffic does not follow assignments.

- **CHK**: on the router, with the device's own address in place of `<ip>`:

```bash
ip rule show | grep -w <ip>
nvram get vpnc_dev_policy_list | tr '<' '\n' | grep -w <ip>
nvram get vpnc_default_wan
```

- **e2e.sh** does the router-side checking for a step: `sh /jffs/cfg-pia-wg/e2e.sh <label> before`, press the button in the app, then `sh /jffs/cfg-pia-wg/e2e.sh <label> after <checks>`. It writes the STARTED and ENDED lines to the router log, prints what changed, and answers PASS or FAIL. The checks are `exit <ip> wgcN|WAN|BLOCKED`, `rule <ip> <table|main>`, `norule <ip>`, `guard <ip> <table>`, `noguard <ip>`, `default <index>`, `up wgcN` and `down wgcN`. The script's header says more.


- **Router shell variables** the tests use. Set them in every new SSH session to the router:

```bash
T=192.168.1.20   # TABLET's address
TMAC=AA:BB:CC:00:00:20   # TABLET's MAC, upper case, as DEVICES shows it
D=192.168.1.30   # DESKTOP's address
P=192.168.1.40   # PHONE's address
I1=9             # wgc1's routing table: field 7 of its row in vpnc_clientlist
I5=5             # wgc5's
```

---

## <a name='pre'></a>PRE. Before you start

**PRE-5** Baseline router (the very first step of a full end-to-end test) [hand]

- Do: reload the router's baseline settings file: only the settings made straight after a factory reset, before any VPN or app setup. The reload also wipes `/jffs`.
- Do: reformat the USB drive, then reinstall Download Master from the WebUI (USB Application, Download Master).
- Pass if: `ls /jffs/cfg-pia-wg` finds nothing, and `nvram show | grep -E 'cfg_pia_wg|wgc[1-9]_'` prints nothing. A factory-fresh router holds no `wgcN_` keys at all, so any line here is left over.
- Pass if: `nvram get vpnc_clientlist` is empty, `wg show interfaces` is empty, and `cru l` has no watchdog lines.
- Pass if: `ls -l /opt/etc/init.d/` lists `S50downloadmaster` and `S50asuslighttpd`, with no `.old` files, and `grep -l "auto-generated by cfg-pia-wg" /opt/etc/init.d/*` prints nothing.
- Do: `nvram get dhcp_staticlist` and note whether TABLET or DESKTOP has no reservation. DEV-4 needs one that has none.
- Note: the settings file holds passwords in plain text. Keep it out of the repo.
- Then skip PRE-1 and go to PRE-2.

**PRE-1** Clean router, when not reloading the baseline [hand]

- Do: copy `scripts/clearall.sh` and `scripts/showall.sh` to the router, run `./clearall.sh`, then delete every VPN in the WebUI.
- Do: `rm -f /jffs/cfg-pia-wg/jq /jffs/cfg-pia-wg/mailsend-go`, so CON-4 can test the install.
- Do: reboot the router.
- See: `./showall.sh` shows no `wgcN_`, `cfg_pia_wg_` or watchdog entries.

**PRE-2** Router is accepting service calls [hand]

- Do: `grep "rc_service: skip the event" /tmp/syslog.log`
- Pass if: nothing. If anything prints, the router's service queue is stuck and will drop the app's commands without saying so: power cycle it before testing.

**PRE-3** Note your own public address [hand]

- Do: exit IP on DESKTOP.
- See: your ISP's address. Write it down; later tests compare against it.

**PRE-4** Have to hand [hand]

- Do: copy the three check scripts to `/jffs/cfg-pia-wg/` on the router. The router has no `scp`, so `scp` fails in both directions: open each file in `vi` on the router and paste it in, or from Git Bash on DESKTOP, in the repo:

```bash
for F in e2e.sh test-backoff.sh presence-probe.sh; do ssh <user>@<router> "cat > /jffs/cfg-pia-wg/$F && chmod 700 /jffs/cfg-pia-wg/$F" < scripts/$F; done
ssh <user>@<router> 'ls -l /jffs/cfg-pia-wg/*.sh'
```
- PIA username and password.
- An SMTP account with an app password, for example Gmail.
- The router WebUI open on DESKTOP.

---

## <a name='con'></a>CON. Connecting to the router

**CON-1** Wrong SSH password [hand]

- Do: MANAGE, enter the right IP and username and a wrong password, CONNECT TO ROUTER.
- See: "The router refused that username or password." and the form stays, with what you typed.
- Pass if: APP LOG carries the raw SSH error under that sentence.

**CON-2** Unreachable address [hand]

- Do: MANAGE, IP `192.168.50.254`, CONNECT TO ROUTER.
- See: "Could not connect to the router at 192.168.50.254", within a few seconds, not a hang.
- See: no exception text on screen.
- Pass if: APP LOG carries the raw `SocketException`, so the detail is not lost.
- Do: turn Wi-Fi off on the phone and connect again.
- See: the same sentence, naming the address you typed.

**CON-3** Good login [hand]

- Do: MANAGE, right details, CONNECT TO ROUTER.
- See: "Install helper programs?", because PRE removed `jq`. Do: NOT NOW.
- See: the main menu, not the router login again (ID-252).
- See: APP LOG has "Router firmware detected: stock.", and "Router address remembered." if the address is new or has changed since the last login - kept although the install was put off (ID-201). The same address as before writes no line.
- See: your password manager offers to save the login.

**CON-4** Helper programs missing, declined [ci]

- In CI: the install dialog names each binary, its version, checksum and destination, and NOT NOW declines with no second notice. `test/widgets/install_binaries_dialog_test.dart`, `test/screens/router_screens_test.dart`.

**CON-5** Helper programs missing, installed [hand]

- Do: WATCHDOG, connect.
- See: "Install helper programs?", or, if it was declined earlier this session, a warning starting "Unable to locate:" with INSTALL.
- Do: INSTALL.
- See: `jq` and `mailsend-go` install together, and it connects.
- Pass if: `ls -l /jffs/cfg-pia-wg` lists `jq` and `mailsend-go`.
- Pass if: APP LOG ends this sequence with "jq and mailsend-go installed; the router has everything this screen needs." and shows no "Unable to locate" after it.

**CON-6** Address with a port [hand]

- Do: SETTINGS, FORGET ROUTER IP.
- Do: MANAGE, your router's own address with `:22` on the end, for example `192.168.1.1:22`, CONNECT TO ROUTER.
- See: the slot list, as normal.

---

## <a name='hom'></a>HOM. Home screen and drawer

**HOM-1** Every row goes where it says [hand]

- Do: tap each of the nine rows, then HOME.
- See: each opens its screen; HOME and the back key return.

**HOM-2** Rows line up [hand]

- See: each row has its icon at the left, its label, and a chevron at the right.
- See: icons in one straight column, labels starting in line.
- See: EXIT is red with a power icon and no chevron.
- See: every outline is teal, while each row's icon and label carry that screen's own colour - STANDALONE teal, MANAGE blue, WATCHDOG green, DEVICES amber, ROUTER LOG purple, APP LOG indigo, SETTINGS and ABOUT grey.

**HOM-3** Drawer matches [hand]

- Do: open the drawer.
- See: the same destinations in the same order, the same icons, plus a home icon beside HOME.
- See: each row's icon and label in the same colour the menu gives it, with no outline.
- Do: open the drawer from a screen other than HOME.
- See: the row for the screen you are on is marked by a filled background, not by a change of colour.

**HOM-4** Links [hand]

- See: neither line is underlined, and both icons are a muted khaki-gold.
- See: both icons sit in the same column as the nine menu icons above them.
- Do: "how to use this app".
- See: the README section opens.
- Do: "add a Play Store app review".
- See: the Play Store app opens the listing, not a web page inside cfg-pia-wg.

**HOM-5** Tablet [hand]

- Do: open the app on TABLET.
- See: the list is no wider than 520 and centred. On the phone it fills the width.
- See: the block of rows sits optically centred between the header and HOME - spare height above it as well as below, with slightly more below.
- Pass if: on the phone nothing moved: the rows still start at the top and the screen scrolls as before.

**HOM-6** Nothing that should not be there [ci]

- In CI: the menu shows exactly its nine entries, with no footnotes. `test/screens/main_menu_screen_test.dart`.

**HOM-7** Every screen says what it is [hand]

- Do: open each of the nine destinations in turn.
- See: each one is headed with the name of the menu item you tapped, in that item's colour.
- See: the headings are all one size and style, spaced capitals.
- See: the header's "Exponentially Digital" and the version number are not underlined, and both still open their pages.

---

## <a name='std'></a>STD. Standalone

**STD-1** Generate a config [hand]

- Do: choose a region with the browse button, enter PIA details, GENERATE CONFIG.
- See: the heading `GENERATED CONFIG: pia-<region>` and the config text.
- See: the password manager offers to save.

**STD-2** Region filter [hand]

- Do: browse, type part of a region name in the filter.
- See: the list narrows; tapping a row fills the field.

**STD-3** Typed region that does not exist [hand]

- Do: type `pia-nowhere`, GENERATE CONFIG.
- See: an error ending "not found."

**STD-4** Wrong PIA password [hand]

- Do: a real region, wrong password, GENERATE CONFIG.
- See: "PIA rejected this username and password. The PIA username is the one PIA issued for the VPN ...", the same words MANAGE and WATCHDOG use, with the HTTP code in brackets at the end (ID-253).

**STD-5** Bad DNS [hand]

- Do: DNS `9.9.9`, GENERATE CONFIG.
- See: "... is not a valid DNS address ...".
- Do: DNS `1.1.1.1, 8.8.8.8, 9.9.9.9`.
- See: "Enter at most two DNS addresses."

**STD-6** DNS default comes back [ci]

- In CI: a blank DNS is refilled with the Quad9 defaults on entry. `test/screens/standalone_config_screen_test.dart`.

**STD-7** Copy clears itself [hand]

- Do: COPY.
- See: "Config copied" and a 60 second countdown under COPY.
- Do: leave the screen before it ends.
- See: after 60 seconds, APP LOG has "Clipboard auto cleared." and pasting gives nothing.

**STD-8** Share and save [hand]

- Do: SHARE / SAVE, send it to yourself.
- See: a file called `pia-<region>.conf`.
- Do (optional): import it into the router WebUI as a WireGuard client, and connect.
- See: it connects.

**STD-9** Config survives leaving the screen [ci]

- In CI: a config restored from the session keeps its heading and region. `test/screens/standalone_config_screen_test.dart`.

---

## <a name='man'></a>MAN. Manage

**Slots at the start of this group:** all five empty, as PRE-5 or PRE-1 left them. **At the end:** wgc1 and wgc5 configured and running, everything else empty. MAN-9, MAN-11 and MAN-16 each leave a slot broken on purpose and each ends by repairing it - do not skip those steps, because every group after this one assumes wgc1 and wgc5 are up.

Every test starts on MANAGE, connected. MAN-13 and MAN-14 are in the [WD](#wd) group: they need a watchdog to pause, and none exists yet.

**MAN-1** Create wgc1 [hand]

- Do: select wgc1, CREATE, choose a region, enter PIA details, CONTINUE.
- See: "Slot created" and "wgc1 has been created. Remember to ENABLE it via the ENABLE button."

**MAN-2** Create wgc5, in a different region [hand]

- Do: select wgc5, CREATE, choose a region other than wgc1's, enter PIA details, CONTINUE.
- See: both rows read `wgcN:pia-<region>`; empty slots read `wgcN <empty slot>`.

**MAN-3** Enable asks for check targets the first time [hand]

- Do: select wgc1, ENABLE.
- See: "Connectivity check targets", filled in with 8.8.8.8 and 1.1.1.1.
- Do: ENABLE.
- See: APP LOG `wgc1:pia-<region> enabled: up, and its server has answered.` and the ACTIVE badge.
- Pass if, on the router, `ip -o link show up | grep -c wgc1:` prints `1` and `echo $(( $(date +%s) - $(wg show wgc1 latest-handshakes | awk '{print $2}') ))` is under 180: the router's own record of a handshake.

**MAN-4** Two tunnels up [hand]

- Do: ENABLE wgc5.
- See: ACTIVE on both rows, not just one.
- Pass if: `wg show interfaces` lists both.

**MAN-5** Stock VPN limit [ci]

- In CI: a third slot is refused with the limit dialog, and nothing is written. `test/widgets/slot_modal_test.dart`.

**MAN-6** Edit [hand]

- Do: select wgc1, EDIT, clear one field.
- See: SAVE greyed.
- Do: put it back, change DNS to `9.9.9.9`, SAVE.
- Pass if: `nvram get wgc1_dns` reads `9.9.9.9`.

**MAN-7** Stock DNS note [ci]

- In CI: the first-server DNS note shows in CREATE and EDIT on stock, and never in STANDALONE. `test/widgets/slot_modal_test.dart`, `test/screens/slot_params_editor_test.dart`, `test/screens/standalone_config_screen_test.dart`.

**MAN-8** Disable [hand]

- Do: select wgc5, DISABLE, confirm.
- See: the ACTIVE badge goes.
- Pass if: `wg show interfaces` no longer lists wgc5.
- Do: ENABLE it again before moving on. Every group after MAN expects wgc5 up, and MAN-11 - the one test that would otherwise bring it back - is optional.

**MAN-9** Create over a running tunnel, new region [hand]

- Do: with wgc1 up, note `wg show wgc1 latest-handshakes`, then CREATE on wgc1 in a different region.
- See: the overwrite prompt says the tunnel will be stopped first.
- See: afterwards the slot shows disabled and the dialog says the old tunnel was stopped.
- Do: ENABLE.
- Pass if: `wg show wgc1 latest-handshakes` shows a DIFFERENT peer key.

**MAN-10** Overwrite with the same region [hand]

- Do: CREATE on a configured slot, same region.
- See: the overwrite prompt, then "Slot created".
- Do: ENABLE the slot, so the tests after this find it running.

**MAN-11** Enable that fails turns the slot back off (optional, slow) [hand]

- Do: DISABLE wgc5 if it is running. Then EDIT wgc5, change `ep_addr` to `192.0.2.1`, SAVE, ENABLE.
- See: after a minute or two, an error that the tunnel came up but the PIA server never answered.
- See: the error offers RECREATE beside NOT NOW.
- Do: NOT NOW.
- See: the slot shows disabled and nothing else happened.
- Pass if, on the router, `nvram get wgc5_enable` prints `0` and `wg show interfaces` doesn't list wgc5.
- Do: ENABLE again, then RECREATE on the error.
- See: the CREATE flow starts for that same slot - region, then PIA credentials and DNS.
- Pass if: the slot is rebuilt and ENABLE brings it up.

**MAN-12** Delete [ci]

- In CI: DELETE names the VPN, asks first, and leaves the row empty. `test/widgets/slot_modal_test.dart`.

**MAN-15** Slots read wgc5 first, and the buttons are colour-coded [hand]

- See: on MANAGE and on WATCHDOG, the list runs wgc5 at the top down to wgc1.
- See: DEVICES's picker lists them the same way, except that a RUNNING tunnel sorts above a stopped one.
- See: CREATE green, ENABLE teal, EDIT blue, DISABLE amber, DELETE red.
- See, later, once WD-7 has deployed a watchdog: VIEW ROUTER WATCHDOG LOG in ROUTER LOG's plum. There is no watchdog yet at this point in the run, so it is greyed out here.
- See: a greyed-out button is grey whatever its verb colour would be.

**MAN-16** ACTIVE means answered, not merely up [hand]

- Do: with wgc1 up and enabled, open MANAGE.
- See: `● ACTIVE` in teal.
- Do: on the router, `wg set wgc1 peer "$(nvram get wgc1_ppub)" remove`, then wait five minutes and REFRESH the screen by leaving it and coming back.
- See: the badge is now amber and reads `● UP, NO ANSWER` - the interface is still up, and nothing is answering it.
- Pass if: APP LOG says wgc1 is up but its server has not answered for over 5 minutes, and the router agrees: `echo $(( $(date +%s) - $(wg show wgc1 latest-handshakes | awk '{print $2}') ))` is over 300, or the handshake reads `0`.
- Do: MANAGE, wgc1, DISABLE, then ENABLE. There is no watchdog yet at this point in the run, so this is what repairs it.
- See: teal `● ACTIVE` again.
- Note: this is what an expired PIA registration looks like, which is why it is worth knowing by sight.

**MAN-17** SAVE on a running slot restarts it [hand]

- Do: MANAGE, select **wgc1**, running. Note `nvram get wgc1_mtu`.
- Do: EDIT, change MTU to `1400`, SAVE.
- See: "Saving restarts wgc1. Anything using it drops for a few seconds." Do: CANCEL.
- Pass if: the editor is still open with `1400` in it, and `nvram get wgc1_mtu` is unchanged.
- Do: SAVE, then SAVE on the question.
- See: the app log shows "Restarting wgc1 with the new settings", a handshake, then "wgc1 restarted with the new settings."
- Pass if: `ip link show wgc1` says `mtu 1400`.
- Do: EDIT, MTU back to what you noted, SAVE, SAVE.

---

## <a name='wd'></a>WD. Watchdog

**Slots at the start of this group:** wgc1 and wgc5 configured and running, everything else empty, and no watchdog anywhere: `cru l | grep watchdog_` prints nothing. If it prints anything, the router did not start from PRE-5 or PRE-1. **At the end:** watchdogs active on wgc1 and wgc5 with both tunnels up, which is what every group after this one needs.

Which slot each test uses, because they are not interchangeable:

- **wgc1 and wgc5** are the pair the later groups depend on. Nothing here may leave either of them deleted - WD-12 deletes wgc5 and rebuilds it in the same test.
- **wgc2** is the expendable one. WD-9 builds it and deploys a watchdog to it, WD-21 breaks and restores it, and MAN-14 deletes it at the end of the group.
- **wgc3** is empty from MAN-12 onwards, which is what WD-20 and WD-23 need. WD-23 leaves it built; delete it afterwards or leave it, nothing depends on either.

Use a 5 minute check interval throughout. PIA rate-limits token requests: test one slot at a time.

Do first: SETTINGS, Max active VPNs, `4`. At WD-23 wgc1, wgc2, wgc3 and wgc5 all run at once, and stock allows 2 by default.

**WD-1** Form checks what you type [ci]

- In CI: an SMTP server without a port is refused, in the batched error dialog. `test/router_watchdog_unit_test.dart`, `test/watchdog_dialog_test.dart`.

**WD-2** Every problem at once, the region first [ci]

- In CI: a bad region and a bad field below it are reported together, region first (ID-202). `test/watchdog_dialog_test.dart`.

**WD-3** Test email, before any deploy [hand]

- Do: WATCHDOG, select wgc1, CREATE/EDIT. Choose a real region from the list, turn on "Enable email alerts", then fill in email with `smtp.gmail.com:465` and a good app password, TEST EMAIL. Leave email alerts on for every watchdog in this run: WD-13 and the BRK group check the emails.
- See: APP LOG "Test email sent to ...".
- Pass if: the subject ends `TEST email - wgc1:pia-<region on the form>`.

**WD-4** Test email follows the form's region [hand]

- Do: change the region on the form, TEST EMAIL.
- Pass if: the subject and the body's Watchdog row name the new region, and the password manager offers to save the SMTP login.
- Do: set the region back. Left changed, the next SAVE & DEPLOY is a region change and a rebuild.

**WD-5** Test email failure [hand]

- Do: wrong SMTP password, TEST EMAIL.
- See: "The test email could not be sent. ..." and red lines in APP LOG saying what the router reported.
- Do: put the right password back.

**WD-6** Unreachable check target warns, still saves [hand]

- Do: in the form's "Primary ping IP" field, `192.0.2.1`, SAVE & DEPLOY.
- See: "Primary IP 192.0.2.1 is not reachable from the router." and "The settings will still be saved."
- See: ROUTER LOG has the same warning, "Watchdog for wgc1:pia-<region>: Primary IP 192.0.2.1 is not reachable from the router. Saving anyway." (ID-255).
- Do: set it back to `8.8.8.8` and SAVE & DEPLOY.

**WD-7** Deploy on a running slot, same region [hand]

- Do: note `wg show wgc1 peers`.
- Do: with wgc1 up, SAVE & DEPLOY keeping its region.
- See: ROUTER LOG "... is already up; its tunnel was left running".
- Pass if: `wg show wgc1 peers` is the same key: no rebuild.
- See: a SUCCESS email saying "watchdog deployed".

**WD-8** Deploy on a running slot, new region [hand]

- Do: note `wg show wgc1 peers`.
- Do: WATCHDOG, wgc1, CREATE/EDIT, choose a different region, SAVE & DEPLOY.
- See: the prompt says the tunnel is rebuilt on the new region. Do: confirm.
- See: ROUTER LOG "Cleared ... rebuilds it", "Deploying: bringing wgc1 up", then `Deploy SUCCESS: region pia-<new region>`.
- Pass if: `wg show wgc1 peers` is a NEW key, and the WebUI shows wgc1 connected.
- Note: nothing is pinned to wgc1 yet. What a pinned device sees during a rebuild is GRD-2.

**WD-9** Deploy on an empty slot [hand]

- Do: select wgc2, CREATE/EDIT, choose a region, SAVE & DEPLOY.
- See: the slot ends enabled with WATCHDOG ACTIVE.
- See: ROUTER LOG's first check reads "Interface wgc2 is not up yet" or "Not connected yet: ...", in lavender, never the red "No handshake and both pings failed".
- Pass if, on the router a minute later, `wg show wgc2 latest-handshakes` shows a handshake (not `0`) and `cru l | grep watchdog_wgc2` lists its schedule.

**WD-10** Email settings fill in [ci]

- In CI: an empty slot takes the lowest-numbered other slot's email settings; this session's come first; what was on the form is kept. `test/watchdog_dialog_test.dart`.

**WD-11** Pause and resume [ci]

- In CI: DISABLE removes the cron entries and keeps settings, script and tunnel; PAUSED; VIEW LOG still works; ENABLE restores the interval. `test/widgets/slot_modal_test.dart`.

**WD-12** Two watchdogs, delete one [hand]

- Do: WD-7 to WD-9 put watchdogs on wgc1 and wgc2, not wgc5. Give wgc5 one first: WATCHDOG, select wgc5, CREATE/EDIT, keep its region, email alerts on, SAVE & DEPLOY.
- Do: WATCHDOG, select wgc5, DELETE.
- See: "Delete watchdog and VPN wgc5:...?". Afterwards wgc5 is empty, and if wgc5 was the default connection, the default is now Internet.
- See: APP LOG "Another watchdog is still configured; keeping the shared PIA credentials."
- Pass if: `nvram get cfg_pia_wg_user` is still set.
- Do: **rebuild wgc5 before moving on** - MANAGE CREATE it in its old region, ENABLE, then WATCHDOG CREATE/EDIT and SAVE & DEPLOY. WD-22, BRK-6, and the DEV and DEF groups all need it.

**WD-13** Deploy emails [hand]

- Do: open the inbox of the address in the form's "To" field.
- See: one email per deploy so far, each saying "watchdog deployed", subject SUCCESS.
- See: subjects thread by slot: `cfg-pia-wg alert: SUCCESS - wgc1:pia-<region>`.
- See: HISTORY counters in every email, and `nvram get cfg_pia_wg_sdate` is the same date in each.
- Note: the rebuild and failure emails are checked where they are sent, in BRK-1 and BRK-5.

**WD-14** A failed email explains itself [hand]

- Do: wrong SMTP password, SAVE & DEPLOY.
- See: VIEW ROUTER WATCHDOG LOG has "Email FAILED", then `Email diag: resolv.conf [...] via <interface>; <smtp host> resolves to [...]`. An interface name only, no WAN address.
- Pass if: no email arrives from that deploy. The log says it failed; the empty inbox is what shows it.
- Do: right password, SAVE & DEPLOY.

**WD-15** Cannot save without jq [hand]

- Do: on the router `mv /jffs/cfg-pia-wg/jq /jffs/cfg-pia-wg/jq.bak`, then open CREATE/EDIT.
- See: a red banner that jq is not installed; SAVE & DEPLOY refuses.
- Do: `mv /jffs/cfg-pia-wg/jq.bak /jffs/cfg-pia-wg/jq`.

**WD-16** Watchdog log [hand]

- Do: VIEW ROUTER WATCHDOG LOG.
- See: the heading names the slot and region, in green; newest lines at the bottom; on a tablet the text fills the width.
- See: the same colours as ROUTER LOG: watchdog lines lavender, errors and lost connectivity red, and `Deploy SUCCESS`, `Reconfig SUCCESS` and `Alert email sent (SUCCESS)` teal. A first deploy's "Not connected yet" is lavender, not red.
- Do: on the router, `/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground`, then REFRESH without leaving the screen.
- See: the new run's lines at the bottom, scrolled to (ID-211). COPY takes them too.
- Do: CLEAR, confirm.
- See: "Watchdog log cleared for wgc1." and an empty log.

**WD-17** Survives a reboot [hand]

- Do: reboot the router, wait for it.
- Pass if: `cru l` lists `watchdog_wgc1` and `watchdog_log_rotate_wgc1`, and the next check logs `Handshake Ns ago`.

**WD-18** Keyboard [hand]

- Do: WATCHDOG, select wgc1, CREATE/EDIT, and tap into each field in turn, down to the SMTP password.
- See: the keyboard never covers the field you are typing in.

**WD-19** Change the check interval [hand]

- Do: CREATE/EDIT on wgc1, interval `10`, SAVE & DEPLOY.
- Pass if: `nvram get wgc1_wd_check_interval` reads `10`, and `cru l` and the boot persistence file both show `*/10 * * * *` for `watchdog_wgc1`.
- Do: set it back to `5`.

**WD-20** PIA credentials are checked before the router is touched [hand]

- Do: on the router, check wgc3 is empty. All three lines are blank, and `cru l` has no `watchdog_wgc3`:

```bash
logger "**WD-20 START** PIA credentials are checked before the router is touched"
nvram get wgc3_desc; nvram get wgc3_priv; nvram get wgc3_wd_check_interval
cru l
```

- Do: WATCHDOG, CREATE/EDIT on **wgc3**. Enter a wrong PIA password, fill the rest with email alerts on, SAVE & DEPLOY.
- See: "PIA rejected this username and password", and the form stays open.
- Do: run the same commands again:

```bash
nvram get wgc3_desc; nvram get wgc3_priv; nvram get wgc3_wd_check_interval
cru l
logger "**WD-20 END** PIA credentials are checked before the router is touched"
```

- Pass if: nothing was written - the three lines are still blank, `cru l` has no new lines, and no alert email arrives.
- Do: correct the password, SAVE & DEPLOY.
- See: it deploys as usual.

**WD-21** A deploy that fails puts the slot back [hand]

Unplugging the WAN no longer reaches this failure: the phone loses its internet too, so SAVE & DEPLOY stops at its own check with PIA before anything reaches the router (ID-279). So only the router's own web traffic is blocked here, and the phone keeps its internet.

- Do: on **wgc2**, which WD-9 built and which nothing later depends on, note its server and region, and block the router's own HTTPS - its traffic, not your devices':

```bash
logger "**WD-21 START** A deploy that fails puts the slot back"
nvram get wgc2_ppub; nvram get wgc2_desc
iptables -I OUTPUT -p tcp --dport 443 -j DROP
```

- Do: WATCHDOG, CREATE/EDIT on wgc2, choose a DIFFERENT region, SAVE & DEPLOY, and confirm the overwrite.
- See: the spinner while the app checks the region and the login with PIA (ID-279), then the deploy fails, and the message names the cause, says the slot was left as it was, and says the watchdog will try again in N minutes.
- Then:

```bash
nvram get wgc2_ppub; nvram get wgc2_desc
cru l | grep watchdog_wgc2
iptables -D OUTPUT -p tcp --dport 443 -j DROP
```

- Pass if: `wgc2_ppub` and `wgc2_desc` are what they were before, the router's web interface shows the slot as it did, and `cru l` still lists the watchdog - the schedule stays on purpose, because it is the retry.
- Do: wait one check interval, with the block removed.
- See: the watchdog rebuilds the tunnel by itself.

```bash
logger "**WD-21 END** A deploy that fails puts the slot back"
```

- Note: on an EMPTY slot the same failure leaves it empty rather than half-built. Worth doing both if there is time.

**WD-22** A paused watchdog keeps the shared PIA credentials [hand]

- Do: watchdogs on wgc1 and wgc5, both deployed.
- Do: MANAGE, select wgc5, DISABLE - which pauses its watchdog (MAN-13).
- Do: WATCHDOG, select wgc1, DELETE, confirm. That is the last SCHEDULED watchdog on the router.
- Pass if: `nvram get cfg_pia_wg_user` and `nvram get cfg_pia_wg_password` are both still set.
- Do: MANAGE, select wgc5, ENABLE.
- Pass if: the watchdog runs its next check and rebuilds without "PIA username is not set" in its log.

**WD-23** The watchdog form writes the slot's DNS [hand]

- Do: WATCHDOG, CREATE/EDIT on **wgc3**. Note the DNS field - it should be filled in, not grey.
- Do: SAVE & DEPLOY, and wait for it to finish.
- Pass if: `nvram get wgc3_dns` returns what the field showed.
- Pass if: `ip rule show | grep "iif lo"` now lists two rules for that slot's DNS addresses.
- Pass if: `iptables -t nat -S VPN_FUSION | grep <a pinned device's IP>` shows its port-53 lookups redirected to that slot's first DNS server.
- Note: before this build a slot built here had no DNS at all, so a pinned device's lookups left over the WAN instead of through its tunnel. That is what these three checks are about.

**WD-24** The watchdog's own lookups are encrypted [hand]

- Do: WATCHDOG, CREATE/EDIT on **wgc3**, which WD-23 built with Quad9 as its DNS.
- See: "The watchdog's own encrypted DNS" with Cloudflare and `1.1.1.2` filled in.
- Do: choose Quad9 from the list.
- See: the note turns amber and says `9.9.9.9` is also this tunnel's DNS server - the one arrangement to avoid.
- Do: choose "Something else".
- See: both fields empty.
- Do: choose Cloudflare again, SAVE & DEPLOY.
- Do: break wgc3 and run its watchdog:

```bash
logger "**WD-24 START** The watchdog's own lookups are encrypted"
iptables -I OUTPUT -d 1.1.1.2 -p tcp --dport 443 -j RETURN
( while sleep 1; do iptables -vxnL OUTPUT | awk '$3 == "RETURN" && $9 == "1.1.1.2" {print $1}'; done ) > /tmp/doh.count &
wg set wgc3 peer "$(nvram get wgc3_ppub)" remove
/jffs/cfg-pia-wg/watchdog_wgc3.sh foreground
grep -E 'Looked up|Encrypted lookup|NOT encrypted|Reconfig' /tmp/watchdog_wgc3.log | tail -5
kill $!; echo "$(sort -n /tmp/doh.count | tail -1) packets to the DoH server"; rm -f /tmp/doh.count
iptables -D OUTPUT -d 1.1.1.2 -p tcp --dport 443 -j RETURN 2>/dev/null
logger "**WD-24 END** The watchdog's own lookups are encrypted"
```

- Pass if: `Looked up <name> over encrypted DNS via security.cloudflare-dns.com (1.1.1.2)` for each PIA name, then `Reconfig SUCCESS`, and no "Encrypted lookup ... failed" or "NOT encrypted" line.
- Pass if: the packet count is above `0`. That's the router's own count, not the watchdog's word: the lookups really went to the DoH server. It's read once a second while the watchdog runs, because the rebuild's tunnel restart rebuilds the firewall and takes the counting rule with it. `scripts/check-claims.sh full` proves the rest, with the DoH server dead and missing as well.

**WD-25** The mail server's name is resolved privately too [hand]

- Do: with email alerting on for **wgc3**, break it and run its watchdog:

```bash
logger "**WD-25 START** The mail server's name is resolved privately too"
iptables -I OUTPUT -d 1.1.1.2 -p tcp --dport 443 -j RETURN
( while sleep 1; do iptables -vxnL OUTPUT | awk '$3 == "RETURN" && $9 == "1.1.1.2" {print $1}'; done ) > /tmp/doh.count &
wg set wgc3 peer "$(nvram get wgc3_ppub)" remove
/jffs/cfg-pia-wg/watchdog_wgc3.sh foreground
grep -E 'SMTP host resolved|Alert email sent' /tmp/watchdog_wgc3.log | tail -2
grep -c cfg-pia-wg /etc/hosts
kill $!; echo "$(sort -n /tmp/doh.count | tail -1) packets to the DoH server"; rm -f /tmp/doh.count
iptables -D OUTPUT -d 1.1.1.2 -p tcp --dport 443 -j RETURN 2>/dev/null
logger "**WD-25 END** The mail server's name is resolved privately too"
```

- Pass if: `SMTP host resolved privately to <address>` before `Alert email sent (SUCCESS)`, and a count of `0`: the hosts entry is removed after every send.
- Pass if: the email arrives, which proves certificate verification still passed, and the packet count is above `0`: the router counted the lookups going to the DoH server.

**WD-26** The router's own resolver gets a line of its own [hand]

- Do: run wgc1's watchdog by hand, then stop stubby and run it again:

```bash
logger "**WD-26 START** The router's own resolver gets a line of its own"
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
grep 'Router resolver' /tmp/watchdog_wgc1.log | tail -1
kill $(pidof stubby)
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
grep 'Router resolver' /tmp/watchdog_wgc1.log | tail -1
logger "**WD-26 END** The router's own resolver gets a line of its own"
```

- Pass if: `Router resolver OK` the first time (ID-194).
- Pass if: `Router resolver FAILED` the second time, and that run still ends healthy: no rebuild, no alert. If it reads OK, the router restarted stubby first: kill it and run again at once.
- Do: `pidof stubby`; if it prints nothing, `service restart_dnsmasq`, or reboot if that does not bring it back.

**WD-27** A watchdog paused while its run waits stands down [hand]

- Do: pick the highest-numbered slot with an active watchdog; the example uses wgc5. A run started the way cron starts it waits 15 s for each slot below it before it does anything, 60 s for wgc5. Start one, and keep the SSH session open:

```bash
logger "**WD-27 START** A watchdog paused while its run waits stands down"
wg show wgc5 public-key
/jffs/cfg-pia-wg/watchdog_wgc5.sh detached &
```

- Do: within that minute, WATCHDOG, select wgc5, DISABLE.
- Do: when a minute and a half has passed:

```bash
tail -2 /tmp/watchdog_wgc5.log
wg show wgc5 public-key
ps | grep -c "[w]atchdog_wgc5"
logger "**WD-27 END** A watchdog paused while its run waits stands down"
```

- Pass if: the last line is `wgc5's watchdog was paused or removed while this run waited; standing down`, with no check, rebuild or alert after it (ID-240).
- Pass if: the public key is the same both times, so nothing was rebuilt, and the count is `0`: no run is left.
- Do: WATCHDOG, select wgc5, ENABLE.

**WD-28** A deploy that fails on an empty slot leaves nothing behind [hand]

WD-21's opposite. A slot that had a tunnel keeps its watchdog, for the retry; an empty one can't be retried, because the clean-up removes the description the watchdog takes its region from. Until build 490 it kept the schedule anyway, and the watchdog failed every five minutes, emailed, and couldn't be deleted (2026-10-01).

- Do: pick an empty slot; the example uses wgc4. Block the router's own HTTPS, as in WD-21:

```bash
logger "**WD-28 START** A deploy that fails on an empty slot leaves nothing behind"
iptables -I OUTPUT -p tcp --dport 443 -j DROP
```

- Do: WATCHDOG, CREATE/EDIT on wgc4, choose a region, SAVE & DEPLOY.
- See: the deploy fails, and the message says wgc4 was cleared back to empty and no watchdog was set up. It doesn't say it will try again.
- Then:

```bash
iptables -D OUTPUT -p tcp --dport 443 -j DROP
cru l | grep -c wgc4
grep -c wgc4 /opt/etc/init.d/S50downloadmaster
nvram show 2>/dev/null | grep -c '^wgc4_'
ls /jffs/cfg-pia-wg/watchdog_wgc4.sh
logger "**WD-28 END** A deploy that fails on an empty slot leaves nothing behind"
```

- Pass if: three counts of `0`, and `ls` says there is no such file. If another watchdog is running, it still works at its next check: the PIA login it uses was put back.

The last two tests here are MANAGE ones. They live at the end of this group because they act on a watchdog, and there is none until this group has run.

**MAN-13** Disable pauses a watchdog rather than removing it [hand]

- Do: MANAGE, select **wgc2** - WD-9 gave it a watchdog and nothing later needs it - then DISABLE.
- See: the prompt says the watchdog will be paused and that ENABLE brings both back.
- Do: confirm.
- See: the slot shows WATCHDOG PAUSED.
- Pass if: `cru l` has no `watchdog_wgc2` lines, `nvram get wgc2_wd_check_interval` is still set, and `/jffs/cfg-pia-wg/watchdog_wgc2.sh` is still there.
- Do: ENABLE, with check targets already stored.
- See: the tunnel comes up and the slot shows WATCHDOG ACTIVE again.
- Pass if: `cru l` lists both `watchdog_wgc2` lines again, at the interval it had before.

**MAN-14** Delete takes a paused watchdog with it [hand]

- Do: MANAGE, select **wgc2**, which MAN-13 left with a paused watchdog, then DELETE. Do this one on wgc2 and nothing else: wgc1 and wgc5 are needed by every group after this.
- See: the prompt says the watchdog goes too - schedule, script and settings - and that nothing is left to ENABLE.
- Do: confirm.
- Pass if: `ls /jffs/cfg-pia-wg/watchdog_wgc2.sh` finds nothing, `cru l | grep wgc2` prints nothing, and `nvram show | grep wgc2_wd_` prints nothing - the SMTP password included.

---

## <a name='brk'></a>BRK. Break a tunnel

The most common real failure is PIA silently expiring a registration. There is no published schedule: it can be a day or a couple of weeks. The interface stays up, the server stops answering, and the handshake ages out. BRK-1 reproduces exactly that. Why the others are chosen, and why some obvious methods are not used, is in [R2](#r2).

Anything pinned to the slot loses internet during these tests. That is the test working. Use a slot nothing important depends on, with a watchdog, email on, and a 5 minute interval.

**Slots at the start of this group:** watchdogs active on wgc1 and wgc5, both tunnels up, and both slots carrying DNS servers - BRK-8 has nothing to probe otherwise. Each test repairs what it breaks.

`foreground` in the commands runs one check and waits for it, so its log is complete when the next line reads it. Without it the script hands itself to the background and returns at once, which is what cron needs.

**BRK-1** Expired registration (the real one, slow) [hand]

- Do: DEVICES, TABLET to wgc1, APPLY.
- Do: on the router:

```bash
logger "**BRK-1 START** Expired registration (the real one, slow)"
nvram get wgc1_ppub
wg genkey > /tmp/breakit
wg set wgc1 private-key /tmp/breakit
rm -f /tmp/breakit
logger "**BRK-1 END** Expired registration (the real one, slow)"
```

- Do: wait. It takes 5 minutes after the last handshake, plus up to one check interval.
- See: watchdog log "No handshake and both pings failed", "Connectivity lost; reconfiguring (attempt #1)", then `Reconfig SUCCESS: region pia-<region> via ...`.
- See: a SUCCESS email with the outage duration and the new server.
- See: between "Interface wgc1 is up" and the SUCCESS line, "Waiting for a handshake on wgc1" then "Handshake Ns ago after Ns" - the rebuild no longer calls itself a success on the interface alone.
- Pass if: TABLET has no internet from the break until the SUCCESS line, and its exit IP never shows your own address - the fail-closed guard.
- Pass if: `wg show wgc1` lists the NEW key from `nvram get wgc1_ppub`, the next check logs `Handshake Ns ago`, and TABLET's exit IP is back in the region.
- Pass if, on stock: the log shows "Restarting wgc1 through VPN Fusion (vpnc_unit=N)" rather than the stop/start pair, and N matches the row wgc1 occupies in `nvram get vpnc_clientlist`, counting from 0.
- See, in the SUCCESS email: the outage duration, the new server and its latency, and the kill-switch line, which on stock is one of:
  - nothing pinned to the tunnel: it says so;
  - devices pinned and guarded: "the app's guard kept TABLET pinned to this tunnel, and off the internet while this tunnel was down", naming each pinned device as DEVICES does, comma-separated;
  - guard rules missing: how many are covered, and that opening DEVICES and applying puts it back.
- See, when wgc1 is also the default connection: the line adds that devices only following the default are not covered.

**BRK-2** Expired registration (the quick one) [hand]

- Do: on the router:

```bash
logger "**BRK-2 START** Expired registration (the quick one)"
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
tail -12 /tmp/watchdog_wgc1.log
wg show wgc1 peers; nvram get wgc1_ppub
logger "**BRK-2 END** Expired registration (the quick one)"
```

- See: "Connectivity lost; reconfiguring (attempt #1)", then "Waiting for a handshake on wgc1", "Handshake Ns ago", and `Reconfig SUCCESS`, with no 5 minute wait.
- Pass if: the two keys at the end match: the tunnel is on the new server.

**BRK-3** Interface down [hand]

- Do: `ifconfig wgc1 down; /jffs/cfg-pia-wg/watchdog_wgc1.sh foreground; tail -12 /tmp/watchdog_wgc1.log`
- See: watchdog log "Interface wgc1 is down or absent", then "Connectivity lost; reconfiguring (attempt #1)", then the handshake wait, then "Reconfig SUCCESS".
- Pass if: `wg show interfaces` lists wgc1 again and the next check logs `Handshake Ns ago`.
- Pass if: the SUCCESS email arrives only after the handshake - a rebuild that never handshakes must now end "came up but the PIA server never answered it (no handshake in 20s)" and email FAILED instead.

**BRK-4** A tunnel you turned off is left alone [hand]

- Do: in the router's web interface, VPN, VPN Fusion, switch wgc1's own profile OFF. Not the app: its DISABLE pauses the watchdog as well, and then there is nothing left to test. In the release-candidate run the watchdog was paused instead, and the test passed without testing anything (ID-297).
- Do: on the router:

```bash
logger "**BRK-4 START** A tunnel you turned off is left alone"
nvram get wgc1_enable
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground; tail -2 /tmp/watchdog_wgc1.log
logger "**BRK-4 END** A tunnel you turned off is left alone"
```

- Pass if: the first line is `0`. If it is `1`, the tunnel is still on: switch it off in the web interface and run the block again.
- See: watchdog log "wgc1 is disabled in the router; standing down until it is enabled again".
- Pass if: the tunnel stays off and no email arrives.
- Do: switch wgc1 back ON in the web interface.

**BRK-5** A rebuild that fails [hand]

The app now asks PIA about the credentials before it writes them (WD-20), so a wrong password typed into the form never reaches the router. Break the stored ones instead.

- Do: with a working watchdog on wgc1, on the router:

```bash
logger "**BRK-5 START** A rebuild that fails"
cat /tmp/watchdog_backoff_wgc1
nvram set cfg_pia_wg_password=wrong && nvram commit
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
tail -3 /tmp/watchdog_wgc1.log
cat /tmp/watchdog_backoff_wgc1
logger "**BRK-5 END** A rebuild that fails"
```

- See: "PIA rejected the username and password stored on this router (HTTP 403)", naming where to fix it - not `exit 0, HTTP 403, body 66B: {`.
- See: a FAILED email with WHAT TO DO, the attempt count and the last 10 router log lines.
- Pass if: the backoff file went from a count of `0` to `1`, with a new timestamp.
- Pass if: `wg show wgc1 peers` still prints nothing, so the router agrees nothing was rebuilt, and the email arrives.
- Do: WATCHDOG CREATE/EDIT on wgc1, enter the right PIA password, SAVE & DEPLOY.
- See: it recovers and emails SUCCESS.
- Do not repeat this test straight away: PIA refuses repeated token requests for a while.

**BRK-6** Backoff ladder, with no PIA traffic [hand]

Proves that after each failed rebuild the watchdog waits longer before the next - 2 minutes up to 90 - so a tunnel that cannot be fixed does not get the PIA account refused. The script preloads the attempt count and runs the real watchdog, which turns itself away before asking PIA for anything. It runs it once every 15 seconds, as the watchdogs are spaced: run back to back, it crashed the firmware's `asd` (ID-296).

The test breaks the slot for about two minutes, and everything pinned to it has no internet until the last step. Use the slot the fewest devices depend on; the example uses wgc5.

- Do: WATCHDOG DISABLE on wgc5 (it shows PAUSED). A scheduled check during the test would make a real attempt.
- Do: on the router:

```bash
logger "**BRK-6 START** Backoff ladder, with no PIA traffic"
iptables -I OUTPUT -o "$(nvram get wan0_ifname)" -p tcp --dport 443 -j RETURN
wg set wgc5 peer "$(nvram get wgc5_ppub)" remove
sh /jffs/cfg-pia-wg/test-backoff.sh 5
iptables -vxnL OUTPUT | awk '$3 == "RETURN" && /dpt:443/ {print $1 " HTTPS packets left the WAN"}'
iptables -D OUTPUT -o "$(nvram get wan0_ifname)" -p tcp --dport 443 -j RETURN
```

- See: waits of 120, 240, 480, 960, 1800, 3600, 5400, 5400 seconds, and PASS.
- Pass if: the count is `0`, or close to it. The script reads the watchdog's own lines; this is the router counting every HTTPS packet it sent out of the WAN, and a request to PIA would be dozens. Anything else on the router that uses HTTPS in those two minutes counts too, so a handful is not a failure.
- Do: straight away, WATCHDOG ENABLE on wgc5, then rebuild it rather than waiting for the next check:

```bash
/jffs/cfg-pia-wg/watchdog_wgc5.sh foreground
tail -2 /tmp/watchdog_wgc5.log
logger "**BRK-6 END** Backoff ladder, with no PIA traffic"
```

- Pass if: the log ends `Alert email sent (SUCCESS)` after `Reconfig SUCCESS`, and wgc5's devices have internet again.

**BRK-7** A WAN outage does not climb the backoff ladder [hand]

- Do: break wgc1, so the watchdog has something to repair, and note the backoff file:

```bash
logger "**BRK-7 START** A WAN outage does not climb the backoff ladder"
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
cat /tmp/watchdog_backoff_wgc1
wg show wgc1 public-key
logger "**BRK-7 END** A WAN outage does not climb the backoff ladder"
```

- Do: unplug the router's internet, then run `/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground` three times.
- See: each run logs only "no Internet on WAN interface, exiting."
- Pass if: no "Connectivity lost; reconfiguring (attempt #N)" lines, and no alert emails.
- Pass if: `cat /tmp/watchdog_backoff_wgc1` is UNCHANGED - the outage added no rungs - and, before you plug the internet back in, `wg show wgc1 public-key` is the same as at the start: nothing was rebuilt.
- Do: plug the internet back in, then `/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground; tail -3 /tmp/watchdog_wgc1.log`
- See: either a real attempt straight away, ending `Reconfig SUCCESS`, or `Handshake Ns ago` and no rebuild: the firmware restarts the tunnels itself when the WAN comes back, and in the release-candidate run it had already mended wgc1. Both pass. A "Backing off" line fails: that is waiting out a ladder it never earned.

**BRK-8** A tunnel that answers packets but not questions [hand]

This is the fault of CHANGELOG ID-006: devices pinned to a slot lost name resolution for two days while the watchdog logged a healthy handshake every five minutes. It needs a slot WITH DNS servers set, so use one built or edited since build 454.

- Do: note the slot's first DNS server: `nvram get wgc1_dns`.
- Do: on the router, block it through that tunnel only:

```sh
iptables -I OUTPUT -o wgc1 -d 9.9.9.9 -j DROP
```

- Do: `/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground; tail -2 /tmp/watchdog_wgc1.log`
- See: `no answer from 9.9.9.9; one more and it counts as broken` - and NOT a rebuild. One failure is not enough on purpose.
- Do: the same command again.
- See: `wgc1 is up and handshaking, but 9.9.9.9 has answered nothing twice in a row`, then `Name resolution lost on wgc1; reconfiguring`, then a normal rebuild.
- See: the SUCCESS email says it reconfigured "after its DNS server stopped answering".
- Do: remove the block: `iptables -D OUTPUT -o wgc1 -d 9.9.9.9 -j DROP`. It may say "Bad rule": the rebuild restarted wgc1, which took the rule with it. Either way, `iptables -S OUTPUT | grep 9.9.9.9` must print nothing.
- Pass if: `ip rule show | grep 1000:` prints nothing. The probe's temporary rule is removed every time, and a leftover would quietly redirect the router's own lookups.

**BRK-9** The probe skips what it cannot ask [ci]

- In CI: the real script, on a fake router: a disabled slot stands down before any probe, and a slot with no DNS skips the name check and passes. `test/unit/watchdog_behaviour_test.dart` and `test/unit/watchdog_dns_strike_test.dart`.

---

## <a name='dev'></a>DEV. DEVICES: assignment, names and disabling

Stock only. Assigning a device does not restart any tunnel; changing the default connection does, and has its own section, [DEF](#def). Set up: wgc1 and wgc5 up in different regions, default connection Internet.

**Before DEV-1, paste this into your SSH session to the router.** The `e2e.sh` checks need these values, and refuse to run when one is missing (ID-282). The last line must print six values. Paste it again in every new SSH session, including after DEV-17's reboot.

```bash
T=192.168.1.20   # TABLET's address
TMAC=AA:BB:CC:00:00:20   # TABLET's MAC, upper case, as DEVICES shows it
D=192.168.1.30   # DESKTOP's address
P=192.168.1.40   # PHONE's address
I1=9             # wgc1's routing table: field 7 of its row in vpnc_clientlist
I5=5             # wgc5's
echo "$T $TMAC $D $P $I1 $I5"
```

**Slots for this group:** wgc1 and wgc5 configured and running, default connection Internet, and no device pinned: `nvram get vpnc_dev_policy_list` shows no enabled record for TABLET, DESKTOP or PHONE. DEV-15 deletes wgc5 and recreates it; everything else here changes device assignments rather than slots.

**DEV-1** The list [hand]

- See: every LAN device, offline ones dimmed and last.
- See: first line `name - tags`, tags separated by `|`; second line `IP MAC`, or the MAC alone when no address is known.
- See: tags `DHCP` (no reservation), `random MAC`, `offline`.
- See: a device with no known address shows "connect this device once to assign it" and no picker.
- See: the router itself and AiMesh nodes are not listed.

**DEV-2** Stage, then discard [hand]

- See, before touching anything: DISCARD CHANGES and APPLY 0 CHANGES side by side on one row, both greyed, each half the width.
- Do: pick wgc1 for TABLET.
- See: the row marks itself changed; "APPLY 1 CHANGE" and DISCARD CHANGES appear.
- Do: DISCARD CHANGES.
- See: the row is back as it was. Nothing was written: CHK shows no change.

**DEV-3** Staged changes survive leaving the screen [ci]

- In CI: staged changes survive leaving the screen and coming back. `test/widgets/device_assignment_screen_test.dart`.

**DEV-4** Assign TABLET, which has no reservation [script]

- Do: in the WebUI, LAN, DHCP Server, remove TABLET's manual assignment if it has one, and apply.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-4 before`
- Do: DEVICES, TABLET to wgc1, APPLY 1 CHANGE.
- See: the confirmation lists `from -> to` and says TABLET will also be given a fixed address. Do: APPLY.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-4 after "rule $T $I1" "guard $T $I1" "exit $T wgc1"`
- Pass if: PASS, the changes include a new `dhcp_staticlist` line for TABLET, nothing else on the LAN dropped, and TABLET's exit IP is wgc1's region.
- See: `grep reassigned /tmp/syslog.log | tail -1` names TABLET and where it moved.

**DEV-5** Tunnel to tunnel [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-5 before`, then TABLET to wgc5, APPLY.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-5 after "rule $T $I5" "guard $T $I5" "exit $T wgc5"`
- Pass if: PASS, and TABLET's exit IP is wgc5's region.

**DEV-6** To Internet, then straight to a tunnel [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-6a before`, then TABLET to Internet, APPLY.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-6a after "rule $T main" "noguard $T" "exit $T WAN"`
- Pass if: PASS, and TABLET's exit IP is your own.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-6b before`, then TABLET to wgc5, APPLY.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-6b after "rule $T $I5" "guard $T $I5" "exit $T wgc5"`
- Pass if: PASS - the `lookup main` rule is gone - and TABLET's exit IP is wgc5's region.

**DEV-7** Back to the default [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-7 before`, then TABLET to "default - Internet", APPLY.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-7 after "norule $T" "noguard $T" "exit $T WAN"`
- Pass if: PASS, and TABLET's exit IP is your own.

**DEV-8** Several devices in one APPLY [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-8 before`. TABLET follows the default since DEV-7, and DESKTOP has never been assigned.
- Do: TABLET to wgc1 and DESKTOP to wgc5, APPLY 2 CHANGES.
- See: one confirmation listing both.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-8 after "rule $T $I1" "guard $T $I1" "exit $T wgc1" "rule $D $I5" "guard $D $I5" "exit $D wgc5"`
- Pass if: PASS, and each exit IP matches its tunnel.

**DEV-9** Quick router-side check [retired]

- Retired in build 467: every `exit` check e2e.sh makes asks the kernel this question, `ip route get 1.1.1.1 from <ip> iif br0`.

**DEV-10** DNS goes through the tunnel [hand]

- Do: on DESKTOP (pinned to wgc5), run the extended test at dnsleaktest.com.
- Pass if: only the slot's first DNS server, or PIA's, appears. Not your ISP's.

**DEV-11** To a disabled slot [script]

- Do: MANAGE DISABLE wgc5. `sh /jffs/cfg-pia-wg/e2e.sh DEV-11 before`, then DEVICES, TABLET to wgc5.
- See: the confirmation warns wgc5 is not running and TABLET will have no internet until it is enabled.
- Do: APPLY, then `sh /jffs/cfg-pia-wg/e2e.sh DEV-11 after "rule $T $I5" "guard $T $I5" "down wgc5" "exit $T BLOCKED"`
- See: PASS, and TABLET's row reads "wgc5:pia-<region> is not running - no internet until it is enabled". TABLET has no internet.
- Do: MANAGE ENABLE wgc5.
- Pass if: TABLET's exit IP moves to wgc5's region without reassigning, and the note goes.

**DEV-12** To a server that stopped answering [ci]

- In CI: APPLY names a server that has not answered, and for how long. `test/widgets/device_assignment_screen_test.dart`, `test/unit/device_assignment_test.dart`.

**DEV-13** Offline device [hand]

- Do: copy `scripts/presence-probe.sh` to the router again, since it changed in build 470. From Git Bash on DESKTOP, in the repo:

```bash
ssh <user>@<router> "cat > /jffs/cfg-pia-wg/presence-probe.sh && chmod 700 /jffs/cfg-pia-wg/presence-probe.sh" < scripts/presence-probe.sh
```

- Do: on the router, with the shell variables set (DEV's block above), start it on TABLET:

```bash
logger "**DEV-13 START** Offline device"
nohup sh /jffs/cfg-pia-wg/presence-probe.sh "$TMAC" > /tmp/presence.log 2>&1 &
```

  It logs, with the time, each change in every place the router records whether TABLET is online, and when each file was last written (ID-165). Its `cache` line is what DEVICES shows.
- Do: on DESKTOP, in PowerShell in the repo, with the router's web login when it asks. The address is the web interface's, as you open it in a browser; change it if yours differs. It logs each change in what the web interface shows for TABLET.

```powershell
pwsh scripts/webui-presence.ps1 -Router https://192.168.1.1:8443 -Mac AA:BB:CC:00:00:20
```

- Do: switch TABLET off. Leave both running until the web interface and `cache` both say offline (about 30 seconds on Wi-Fi). Switch TABLET on, and leave them another 5 minutes.
- Write down: the router's log and the DESKTOP log (the script prints where it is). Then stop both: Ctrl+C on DESKTOP, and on the router:

```bash
cat /tmp/presence.log
kill $(cat /tmp/presence-probe.pid)
logger "**DEV-13 END** Offline device"
```

  The source that changed with the web interface is the one the app should read.
- Do: run the same measurement again with a WIRED device: unplug its network cable for two minutes, then plug it back in, with its MAC in the router's script. Pulling the cable does the same job as switching it off, so the device can be the one you're working on: your SSH session drops meanwhile, but the probe keeps logging on the router (ID-299). Pass if: its `cache` line changes with the web interface, as TABLET's did. If it stays `"isOnline":"1"` while the web interface says offline, note it: wired devices need a guard (ID-165).
- Do: switch TABLET off again and wait a minute. Leave DEVICES and open it again.
- See: TABLET dimmed with `offline`, still with a picker.
- Do: with TABLET still off, TABLET to wgc1, APPLY.
- Pass if: CHK shows the record, with `90:` and `100:` rules and a `91:` blackhole. Switch TABLET on: exit IP is wgc1's region.

**DEV-14** Someone else changed the router [ci]

- In CI: a router changed under the screen is reported, and nothing is written. `test/widgets/device_assignment_screen_test.dart`, `test/unit/device_assignment_service_test.dart`.

**DEV-15** Delete a VPN with devices on it [hand]

- Note: deleting wgc5 moves EVERY device pinned to it to Internet, not only TABLET; the last step puts them back.
- Do: TABLET to wgc5, APPLY. MANAGE DELETE wgc5.
- See: before you confirm, the prompt names TABLET and every other device pinned to wgc5, in amber, and says they will be moved to the Internet (ID-289).
- See: APP LOG names TABLET, moved to Internet - by the name DEVICES shows, not a bare address.
- Pass if: CHK shows a `lookup main` rule; exit IP is your own.
- Pass if: `ip rule show | grep -E '^9[01]:'` shows nothing for TABLET: the guard is lifted once a device is on the internet by design.
- Do: CREATE wgc5 again, ENABLE. If it had a watchdog, WATCHDOG CREATE/EDIT and SAVE & DEPLOY it again.
- Pass if: TABLET is NOT on wgc5.
- Do: DEVICES, DESKTOP and any other device that was on wgc5 back to wgc5, leaving TABLET on Internet, APPLY. DEV-17 expects DESKTOP on wgc5.

**DEV-16** The random MAC phone [hand]

- Do: PHONE to wgc1, APPLY.
- Pass if: CHK shows ONE rule; PHONE's exit IP is wgc1's region.
- Note: the reservation is tied to today's MAC. Restart the phone and see whether it keeps its address; if it gets a new one, the assignment no longer applies to it. Write down which.

**DEV-17** Survives a reboot [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-17 before`, then SETTINGS, REBOOT ROUTER, and wait for it. Set the shell variables again in the new session.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEV-17 after "rule $T main" "noguard $T" "rule $D $I5" "guard $D $I5" "exit $D wgc5" "rule $P $I1" "guard $P $I1" "exit $P wgc1"`
- Pass if: PASS - one rule per device, the same as before the reboot: TABLET on Internet since DEV-15, DESKTOP on wgc5 since DEV-8, PHONE on wgc1 since DEV-16 - and each exit IP matches. If PHONE came back on a new address in DEV-16, leave its three checks out.

**DEV-18** Rename a device [hand]

- Do: DEVICES, tap TABLET's name, type `DN-Test Name`, press Enter.
- See: the name in amber, and APPLY 1 CHANGE. Nothing has reached the router yet.
- Do: tap PHONE's name, type `a<b`, press Enter.
- See: "A name cannot contain < or >." under the field, and nothing staged for PHONE. Tap anywhere else: PHONE's name is back as it was.
- Do: APPLY. The confirmation shows `name <old> -> name DN-Test Name`. Confirm.
- Then on the router:

```bash
logger "**DEV-18 START** Rename a device"
nvram get custom_clientlist | tr '<' '\n' | grep -i "$TMAC"
grep -E "rc_service|notify_rc" /tmp/syslog.log | tail -2
logger "**DEV-18 END** Rename a device"
```

- Pass if: TABLET's record reads `DN-Test Name>$TMAC>...` with its other fields as they were, and no service call at the time of the APPLY.
- See: the new name in the router's web interface (Network Map, Clients) and in the ASUS Router app.
- Do: tap TABLET's name, clear it, Enter, APPLY.
- Pass if: TABLET shows the name the router detected, and `custom_clientlist` has no record for it. Then give TABLET its usual name back the same way.

**DEV-19** Disable a device, and enable it again [hand]

- Do: in the router's web interface, Parental Controls, Time Scheduling: check it is OFF and its list is empty.
- Do: DEVICES, TABLET's picker. See: **Disabled** last, in red, with "no Internet or VPN access" under it. Pick it.
- See: TABLET's row reads `disabled - no Internet or VPN access`, "disabled" in red. APPLY, confirm.
- Then on the router:

```bash
logger "**DEV-19 START** Disable a device, and enable it again"
nvram show 2>/dev/null | grep -E "^MULTIFILTER_(ALL|BLOCK_ALL|ENABLE|MAC|DEVICENAME)="
iptables -S | grep -i "$TMAC"
```

- Pass if: `MULTIFILTER_ALL=1`, `MULTIFILTER_BLOCK_ALL=0`, `MULTIFILTER_MAC` is TABLET's MAC with `MULTIFILTER_ENABLE=2`, and three DROP rules for it (FORWARD, PControls, WGNPControls).
- See: on TABLET, no web page loads, and the NAS or another device on your network still opens. The web interface's Time Scheduling lists TABLET, set to block.
- Do: DEVICES, TABLET's picker, pick what it was on before. APPLY.

```bash
nvram show 2>/dev/null | grep -E "^MULTIFILTER_(ALL|MAC)="
iptables -S | grep -i "$TMAC"
logger "**DEV-19 END** Disable a device, and enable it again"
```

- Pass if: `MULTIFILTER_ALL=0`, `MULTIFILTER_MAC` empty, no rules for TABLET, and its internet is back on the connection you picked.

**DEV-20** A disabled device pinned to a tunnel [hand]

- Do: TABLET pinned to wgc1, APPLY. Then TABLET, Disabled, APPLY.
- See: TABLET has no internet, through the tunnel or otherwise.

```bash
logger "**DEV-20 START** A disabled device pinned to a tunnel"
ip rule show | grep "$T "
nvram get vpnc_dev_policy_list | tr '<' '\n' | grep "$T>"
```

- Pass if: rules at 90, 91 and 100 for TABLET, and its policy record still pins it to wgc1: disabling keeps the assignment.
- Do: TABLET, pick wgc1 again, APPLY.

```bash
logger "**DEV-20 END** A disabled device pinned to a tunnel"
```

- Pass if: TABLET is back on wgc1: `curl -s ifconfig.me` from it, or a what-is-my-IP page, shows wgc1's region.

**DEV-21** Time Scheduling schedules are named before they switch on [ci]

- In CI: disabling a device while Time Scheduling is off and holds a schedule set up by hand names that schedule in APPLY's confirmation before switching it on (Andrew's decision); names, disabling and enabling write exactly what the web interface writes. `test/unit/device_names_and_blocks_test.dart`, `test/unit/device_assignment_service_test.dart`, `test/widgets/device_assignment_screen_test.dart`.

---

## <a name='def'></a>DEF. Default connection

Changing the default tears the WireGuard clients down and brings the enabled ones back, which can take a minute. Anything using a tunnel can drop, so do not run this on a router someone is relying on - though on run 1 nothing visibly dropped, so write down what actually happens. Set up: wgc1 and wgc5 up in different regions, TABLET on "default", DESKTOP pinned to wgc5. DEV leaves TABLET pinned to Internet, so first: DEVICES, TABLET to default, APPLY.

**Before DEF-1, paste this into your SSH session to the router.** The `e2e.sh` checks need these values, and refuse to run when one is missing (ID-282). The last line must print six values. Paste it again in every new SSH session, including after DEF-10's reboot.

```bash
T=192.168.1.20   # TABLET's address
TMAC=AA:BB:CC:00:00:20   # TABLET's MAC, upper case, as DEVICES shows it
D=192.168.1.30   # DESKTOP's address
P=192.168.1.40   # PHONE's address
I1=9             # wgc1's routing table: field 7 of its row in vpnc_clientlist
I5=5             # wgc5's
echo "$T $TMAC $D $P $I1 $I5"
```

**Slots for this group:** wgc1 and wgc5 configured and running. DEF-9 deletes wgc1 on purpose and ends by rebuilding it, because DEF-10 and the groups after it need it back.

**The watchdog on wgc1** needs no step here: MANAGE DISABLE pauses it, so it cannot undo DEF-6 and DEF-7 leaving wgc1 stopped, and MANAGE ENABLE resumes it.

**DEF-1** Internet to a tunnel [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-1 before`, then DEVICES, default to wgc1, APPLY.
- See: the confirmation warns tunnels stop and restart.
- Do: after "Device assignments applied.", `sh /jffs/cfg-pia-wg/e2e.sh DEF-1 after "default $I1" "up wgc1" "up wgc5" "exit $T wgc1" "exit $D wgc5"`
- Pass if: PASS, and the changes show two new rules at priority 10000, both `lookup $I1`. `$I1` is field 7 of wgc1's clientlist row, which is index 6 counting from 0.
- Pass if: TABLET's exit IP is wgc1's region, and DESKTOP stays on wgc5.

**DEF-2** Every tunnel comes back [retired]

- Retired in build 467: DEF-1's `up` checks are this test.

**DEF-3** Tunnel to a different tunnel, and both keep running [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-3 before`, then default to wgc5, APPLY.
- Do: after "Device assignments applied.", `sh /jffs/cfg-pia-wg/e2e.sh DEF-3 after "default $I5" "up wgc1" "up wgc5" "exit $T wgc5"`
- Pass if: PASS, and TABLET's exit IP is wgc5's region.
- Write down: `grep -c "notify_rc restart_vpnc$" /tmp/syslog.log` before and after. Two more restarts means the router stopped wgc1 as well and the app brought it back; one means it left wgc1 alone. Nobody has measured which yet (ID-220).

**DEF-4** A device pinned to Internet ignores the default [hand]

- Do: DESKTOP to Internet, APPLY.
- Pass if: DESKTOP's exit IP is your own while TABLET's is wgc5's region.
- Do: DESKTOP back to wgc5.

**DEF-5** A default change costs no watchdog rebuild [hand]

- Do: WATCHDOG, wgc1, 5 minute interval, deployed. Default is wgc5, from DEF-3.
- Do: on the router, `wg show wgc1 public-key`, and keep the answer.
- Do: default to wgc1, APPLY.
- Do: for the next 10 minutes, WATCHDOG, wgc1, VIEW ROUTER WATCHDOG LOG, and REFRESH now and then.
- Pass if: the tunnels are back within about a minute, and the log shows one of two things: only healthy checks (`Handshake Ns ago`), which is the usual, or one rebuild ending `Reconfig SUCCESS`.
- Pass if: `wg show wgc1 public-key` afterwards agrees with the log: the same key if it showed only healthy checks, a new one if it rebuilt. A rebuild makes a new key.
- Write down which of the two you saw. A rebuild costs a PIA token and an email, so healthy checks are the better answer.
- Ends with: default wgc1.

**DEF-6** Default tunnel down, unassigned device (fail open or closed) [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-6 before`, then MANAGE, wgc1, DISABLE.
- Do: DEVICES, read the default connection panel.
- See: wgc1 is not running, and unassigned devices use the Internet.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-6 after "down wgc1" "noguard $T" "exit $T WAN"`, and TABLET's exit IP. TABLET is on "default".
- Pass if: PASS, and your own address. The guard covers pinned devices only, and the panel says so: a device that follows the default goes out through the Internet while the default is off.
- Do: MANAGE, wgc1, ENABLE.

**DEF-7** Default tunnel down, device pinned to it: fails closed [script]

- Do: DEVICES, DESKTOP to wgc1, APPLY. Default is still wgc1.
- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-7 before`, then MANAGE, wgc1, DISABLE.
- See: the confirmation names DESKTOP, in amber, and says it will have no internet until wgc1 is enabled or DESKTOP is moved.
- Do: DISABLE. Then `sh /jffs/cfg-pia-wg/e2e.sh DEF-7 after "guard $D $I1" "exit $D BLOCKED"`, and on DESKTOP, exit IP and `ping google.com`.
- Pass if: PASS, and no internet at all - the fail-closed guard. Run 1 on 2026-09-21, before the guard, found DESKTOP out through the Internet here.
- Do: MANAGE, wgc1, ENABLE. DEVICES, DESKTOP back to wgc5, APPLY.

**DEF-8** Back to Internet, and every tunnel keeps running [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh DEF-8 before`, then DEVICES, default to Internet, APPLY.
- Do: after "Device assignments applied.", `sh /jffs/cfg-pia-wg/e2e.sh DEF-8 after "default 0" "up wgc1" "up wgc5" "exit $T WAN"`
- Pass if: PASS, the changes show both priority-10000 rules gone, and TABLET's exit IP is your own.
- Pass if: the "tunnels running" part of the changes is empty: no tunnel stopped (ID-220) and none started - a DISABLED one must not come up (ID-172).
- Pass if: the WebUI's VPN Fusion page agrees with the app about which tunnels are connected.

**DEF-9** Delete the VPN that is the default [hand]

- Do: write down wgc1's region first - MANAGE shows it on the row as `wgc1:pia-<region>`. You are about to delete the slot and you need the same region back.
- Note: deleting wgc1 moves every device pinned to it to Internet, PHONE included (DEV-16).
- Do: DEVICES, default to wgc1, APPLY, and check DESKTOP is still pinned to wgc5.
- Do: MANAGE, select wgc1, DELETE. See: the prompt names PHONE, in amber, before you confirm (ID-289).
- Pass if: `nvram get vpnc_default_wan` reads `0` - deleting the default falls back to the Internet rather than leaving a dangling index - every tunnel restarts, TABLET's exit IP is your own, and DESKTOP is still on wgc5.
- Do: **rebuild wgc1 before moving on**, in this order, because DEF-10 and every group after it expect it. These steps set up what comes next; there is nothing to check in them beyond each one working:
  - MANAGE CREATE wgc1 in the region you wrote down, then ENABLE it.
  - WATCHDOG, wgc1, CREATE/EDIT, 5 minute interval, SAVE & DEPLOY - ABT reads the deployed script, so one has to be there.
  - DEVICES, default connection back to wgc1, APPLY.

**DEF-10** Survives a reboot [hand]

- Do: DEVICES, default to wgc5, APPLY. Write down what every device is assigned to before you go on.
- Do: SETTINGS, REBOOT ROUTER, REBOOT, and wait for "The router answered again after N seconds."
- Pass if: the default connection is still wgc5 and every device is on the tunnel it was on before, both in the app and in `nvram get vpnc_default_wan` and `nvram get vpnc_dev_policy_list`.
- Pass if: each device's exit IP is the region of the tunnel it is assigned to - TABLET follows the default, DESKTOP is pinned to wgc5.

---

## <a name='grd'></a>GRD. Fail-closed guard

A device pinned to a tunnel gets that tunnel or nothing: no internet while the tunnel's server is silent, while the watchdog rebuilds it, or while it is switched off (ID-213, ARCHITECTURE 6.8.10). These tests prove that on a real router, where a unit test cannot.

Since build 491 (ID-364) the guard is two rules per pinned device, `90: from <ip> lookup <200 + slot>` and `91: from <ip> blackhole`, and one table per tunnel with a pin, `200 + slot`, which holds the tunnel's default and the router's local routes. Nothing runs it on a timer: the app runs it after its own actions, and the router's firewall-start asks for one run 10 seconds after the last call of a burst. So after a tunnel starts, its pinned devices get their internet back about 10 seconds after the tunnel is up; until then they're refused. `e2e.sh`'s `guard <ip> <table>` takes the firmware's table, as before, and checks rule 90 against the guard's own.

**Set up:** wgc1 and wgc5 up in different regions, a watchdog on wgc1 at 5 minutes, default connection wgc5, DESKTOP pinned to wgc1. Only DESKTOP loses its internet in this group.

The router commands use the shell variables from [How to use the run sheet](#how-to-use): `D` is DESKTOP's address, `I1` and `I5` are wgc1's and wgc5's routing tables.

How to read DESKTOP's `ping -t 1.1.1.1`: wgc1's usual time is a pass; "Destination host unreachable" or "Request timed out" is a pass while wgc1 is down; any other reply while wgc1 is down is a leak. The TTL tells a leak's path apart when the times are close: a reply through PIA and one through your ISP usually differ by a hop or two.

**Before GRD-1, paste this into your SSH session to the router.** The `e2e.sh` checks need these values, and refuse to run when one is missing (ID-282). The last line must print six values. Paste it again in every new SSH session, including after GRD-4's reboot.

```bash
T=192.168.1.20   # TABLET's address
TMAC=AA:BB:CC:00:00:20   # TABLET's MAC, upper case, as DEVICES shows it
D=192.168.1.30   # DESKTOP's address
P=192.168.1.40   # PHONE's address
I1=9             # wgc1's routing table: field 7 of its row in vpnc_clientlist
I5=5             # wgc5's
echo "$T $TMAC $D $P $I1 $I5"
```

**GRD-1** An APPLY puts the guard in place [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh GRD-1 before`, then DEVICES, DESKTOP to wgc1, APPLY.
- See: APP LOG "Fail-closed guard in place for N pinned device(s)."
- Do: `sh /jffs/cfg-pia-wg/e2e.sh GRD-1 after "rule $D $I1" "guard $D $I1" "exit $D wgc1"`
- Pass if: PASS. The changes show three new lines for DESKTOP - `90: from <D> lookup 201` (wgc1's guard table), `91: from <D> blackhole`, and the firmware's own `100: from <D> lookup <I1>` - one of each, never two.

**GRD-2** A broken tunnel and its rebuild leak nothing [script]

- Do: on DESKTOP, start `ping -t 1.1.1.1` and leave it running.
- Do: on the router, then wait 30 seconds:

```bash
sh /jffs/cfg-pia-wg/e2e.sh GRD-2 before
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
sleep 10
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
```

- See: the ping goes from wgc1's usual time to unreachable or timed out, then back to wgc1's usual time, about 10 seconds after the rebuild's handshake.
- Pass if: not one reply in between.
- Do: on the router, once the ping is back:

```bash
sh /jffs/cfg-pia-wg/e2e.sh GRD-2 after "guard $D $I1" "exit $D wgc1" "up wgc1"
tail -3 /tmp/watchdog_wgc1.log
```

- Pass if: PASS, and the log ends `Reconfig SUCCESS`. A line "The router skipped the restart of wgc1; trying once more" before it is fine: that is ID-214 working. If it ends "the router skipped the restart of wgc1 twice", the router was busy: wait five minutes and run the watchdog line again.

**GRD-3** DISABLE warns, names DESKTOP, and blocks it [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh GRD-3 before`, then MANAGE, wgc1, DISABLE.
- See: the confirmation names DESKTOP, in amber: no internet until wgc1 is enabled again or DESKTOP is moved.
- Do: DISABLE. Watch the ping for 30 seconds, then `sh /jffs/cfg-pia-wg/e2e.sh GRD-3 after "down wgc1" "guard $D $I1" "exit $D BLOCKED"`
- Pass if: PASS, and the ping showed nothing but unreachable or timed out.
- Do: MANAGE, wgc1, ENABLE.
- Pass if: the ping comes back at wgc1's usual time, about 10 seconds after wgc1 is up. Stop it with Ctrl+C.

**GRD-4** The guard comes back after a reboot [script]

- Do: `sh /jffs/cfg-pia-wg/e2e.sh GRD-4 before`, then SETTINGS, REBOOT ROUTER, REBOOT. Reconnect SSH when it is back, and set the shell variables again.
- Do: on the router:

```bash
sh /jffs/cfg-pia-wg/e2e.sh GRD-4 after "guard $D $I1" "exit $D wgc1"
grep "Fail-closed guard on for .*$D (" /tmp/syslog.log | tail -1
```

- Pass if: PASS: the 90 and 91 lines are back, and the grep prints a `Fail-closed guard on` line for DESKTOP from this boot.
- Note: don't compare its time with "WAN was restored". At boot that line can carry the time from before the router set its clock: 5 May, in the release-candidate run.
- Note: this proves the guard is back after the boot, not that nothing leaked before it was. GRD-7 watches that window.

**GRD-5** A change made in the web interface is followed [script]

- Do: on the router, first: `sh /jffs/cfg-pia-wg/e2e.sh GRD-5 before`
- Do: in the router's web interface, VPN Fusion, move DESKTOP from wgc1 to wgc5. It won't move a device while the tunnels run: stop them, move DESKTOP, apply, then start them again. While you do, DESKTOP is not guarded (README 5.4.1).
- Do: once both tunnels are back, wait 15 seconds, then on the router:

```bash
sh /jffs/cfg-pia-wg/e2e.sh GRD-5 after "guard $D $I5" "exit $D wgc5"
grep "Fail-closed guard on for .*$D (wgc5)" /tmp/syslog.log | tail -1
```

- Pass if: PASS: rule 90 looks up wgc5's guard table, 205, with exactly one 91 line, and the grep prints the line from just now. Nothing here ran the guard: starting the tunnels raised the router's firewall-start, which did (ID-364).
- Do: DEVICES, DESKTOP back to wgc1, APPLY. GRD-6 needs it there.

**GRD-6** A firewall restart leaves the guard alone [script]

The firmware restarts its firewall whenever `asd` crashes, which on 2026-09-27 was every few minutes (ID-227). The guard is routing rules, not firewall rules, so it should be untouched; this measures that. Since build 491 the restart also asks for a guard run (ID-364), which should find nothing to change.

- Starts with: DESKTOP pinned to wgc1, from GRD-5's last step. Check first: `ip rule show | grep -w "$D"` shows `lookup 201` at 90 and `lookup 9` at 100 (wgc1's tables). If it shows `lookup 205` and `lookup 5`, do GRD-5's last step. In the release-candidate run it was missed, and GRD-6 failed for that reason alone.
- Do: on the router, with DESKTOP's `ping -t 1.1.1.1` running:

```bash
sh /jffs/cfg-pia-wg/e2e.sh GRD-6 before
service restart_firewall
sleep 20
sh /jffs/cfg-pia-wg/e2e.sh GRD-6 after "guard $D $I1" "exit $D wgc1" "up wgc1"
```

- Pass if: PASS, and the changes list shows no `ip rule` lines added or removed.
- See: the ping carries on at wgc1's usual time, with at most a reply or two lost while the firewall rebuilds.

**GRD-7** Nothing leaks while the router boots [script]

GRD-4 shows the guard is back after a boot. This watches the boot itself, from the pinned device, because nothing on the router can: stock runs no add-on code until `/opt` mounts, after the WAN is up.

- Starts with: DESKTOP pinned to wgc1, with bash (Linux, WSL or Git Bash) and SSH to the router.
- Do: on DESKTOP, from the repo, with your own login in place of `admin@192.168.1.1`:

```bash
ROUTER_SSH='ssh -o ConnectTimeout=3 admin@192.168.1.1' scripts/check-reboot.sh
```

- See: the router reboots, and about two minutes later a PASS or FAIL line. It fetches Cloudflare's trace page by IP address once a second and records which public address answered.
- Pass if: PASS: no answer came from the router's WAN address. Its INFO lines say how many probes were blocked and when the tunnel carried DESKTOP again.
- Note: run it three times. It's a race: before build 488, 4 boots in 6 leaked for 3 to 6 seconds, and the other two passed. Since build 488 the router's Network Services Filter holds from boot (ID-348), and three in a row passed on 2026-10-01.

**GRD-8** The router's filter holds pinned devices, and pings are the user's choice [script]

The guard's second layer (ID-348): the router's own Network Services Filter, which it applies at boot before the internet connection is up.

- Starts with: DESKTOP pinned to wgc1.
- Do: on the router:

```bash
logger "**GRD-8 START** The router's filter holds pinned devices"
/jffs/cfg-pia-wg/guard.sh
iptables -S FORWARD | grep -- "-s $D/32 -i br0 -o"
nvram get filter_lw_icmp_x
```

- Pass if: `filter held N of N`, and two DROP lines for DESKTOP, `-p tcp` and `-p udp`, both `-o` your WAN interface: never a tunnel. The ICMP setting doesn't include `8`.
- Do: SETTINGS, **SECURE STARTUP** (ID-356).
- See: a popup titled Secure startup, with **ALLOW pings (default)** selected and **BLOCK pings** not, the text explaining both (with "anything" in bold red), and SAVE greyed out. Pick BLOCK pings: SAVE lights up. CANCEL closes it, and nothing changes.
- Do: SECURE STARTUP again, BLOCK pings, SAVE.
- See: APP LOG "Secure startup on: devices not on a VPN can't ping the internet. Devices on a VPN still ping through their tunnels."
- Pass if: `nvram get filter_lw_icmp_x` now includes `8`; DESKTOP still pings 1.1.1.1 (through wgc1); a device that isn't pinned, while the default connection is Internet, can't. Start its ping fresh: one already running when you turn it on keeps getting replies until it's stopped for 30 seconds, because the router lets an exchange it's tracking carry on.
- Do: SECURE STARTUP, which now opens on BLOCK pings. Pick ALLOW pings, SAVE.
- See: APP LOG "Secure startup off: every device can ping the internet again."
- Pass if: `8` is gone from `nvram get filter_lw_icmp_x`, anything else that was there is still there, and the unpinned device pings again.
- Pass if: DEVICES has no ping switch.
- Do: `logger "**GRD-8 END** The router's filter holds pinned devices"`

**GRD-9** The guard holds when it's broken on purpose, on two tunnels [script]

The check that lets ID-364 leave WIP, under the CHANGELOG's rule for protection changes: `scripts/check-claims.sh` breaks the guard on purpose, expects each break to be seen, and expects the router's own events to put it right. It stops one tunnel and starts it again, so if that tunnel is the default connection, devices that follow the default lose it for a moment.

- Starts with: DESKTOP pinned to wgc1, both tunnels up, and `check-claims.sh` in `/jffs`.
- Do: DEVICES, PHONE to wgc5, APPLY.
- Do: on the router, `/bin/sh /jffs/check-claims.sh quick`. It takes about five minutes.
- Pass if: it ends `0 failed`, `GUARD-now` counts 2 pinned devices, and these are PASS: `GUARD-cron`, `GUARD-boot`, `GUARD-hook`, `GUARD-wiped`, `GUARD-event`, `GUARD-repaired`, `GUARD-planted` (twice), `FILTER-emptied`, `FILTER-chain`, `FILTER-event`, and for the first pinned device's tunnel, `GUARD-wgcN-empty`, `-refilled`, `-stopped`, `-no91`, `-back` and `-restarted`.
- See: `GUARD-wgcN-no91` says where that device's traffic went with rule 91 gone: `WAN`, or the default connection's tunnel if that's another one. That line is the check seen to fail; `-stopped` just before it is the same check passing with the guard whole.
- See: `GUARD-wgcN-back` gives the seconds from starting the tunnel to the device's traffic going through it: about 10, plus the tunnel's own start.
- Do: DEVICES, PHONE back to where it was, APPLY.

---

## <a name='log'></a>LOG. App log and router log

**LOG-1** App log [hand]

- See: headed APP LOG in capitals, in its own colour from HOME, not teal.
- Do: COPY, then paste into any text field - a notes app, or the SSH terminal's input line.
- See: "App log copied.", no countdown, and the paste keeps its line breaks rather than arriving as one run-on line.
- Do: CLEAR.
- See: "Ready."

**LOG-2** One connection per session [hand]

- Do: note the time, then use the app for a few minutes - open MANAGE, press something, open WATCHDOG, press something.
- Do: on the router, `grep "Password auth succeeded" /tmp/syslog.log | tail -20`.
- Pass if: counting only the lines since the time you noted, there is one per app session, not one per button press.

**LOG-3** Connection drops mid-session [hand]

- Do: with MANAGE open on the app, reboot the router from the SSH session - `reboot`. Use SSH rather than SETTINGS, because MANAGE has to stay open. When the router is back, press ENABLE or DISABLE.
- See: APP LOG "Router SSH connection dropped; reconnecting.", then "Router SSH connection re-established.", and the action completes.
- Pass if: every `Password auth succeeded` in the router's syslog has a line in APP LOG to account for it.

**LOG-4** Router log paging [hand]

- Do: ROUTER LOG.
- See: headed ROUTER LOG, opens at the newest lines.
- Do: scroll to the top.
- See: older lines load and the text you were reading does not jump; no page starts mid-word.
- Do: scroll back quickly, several screens at a time, letting page after page load.
- See: it holds your place each time - it neither jumps back to the newest lines nor throws you several screens down.
- See: at the very start, it continues into the rotated log if there is one, then "- start of the router log -".
- Do: select text across the join between two loaded pages.
- See: it selects in one run.

**LOG-5** Router log colours [ci]

- In CI: the app teal, the watchdog lavender, errors red, the firmware plain even when it says failed. `test/screens/router_log_screen_test.dart`.

**LOG-6** Router log copy and refresh [hand]

- Do: COPY.
- See: "Router log copied.", everything loaded, no countdown.
- Do: REFRESH.
- See: back at the newest lines.

**LOG-7** Router log without a session [hand]

- Do: EXIT the app, reopen, open the drawer and go straight to ROUTER LOG.
- See: it asks for router details. Do: CANCEL.
- See: back where you came from, not an empty log (ID-155).

---

## <a name='set'></a>SET. Settings

**SET-1** Rows [hand]

- See: REBOOT ROUTER, FORGET ROUTER IP, REMOVE CACHED PIA CERT, UNINSTALL FEATURES DEPLOYED TO ROUTER, RESTORE PURCHASE (store build only), MAX ACTIVE VPNS, ROUTER RESOLVER STATUS, ROUTER DNS ROUTING. The last two are teal, with icons used nowhere else in the app.

**SET-2** One login covers the screen [hand]

- Do: with no router session, REMOVE CACHED PIA CERT.
- See: a login prompt with the remembered address filled in, the username blank, and the keyboard not covering it.
- Do: log in.
- Do: open MAX ACTIVE VPNS and CANCEL, go to MANAGE and back to SETTINGS, then open REBOOT ROUTER and CANCEL at its confirmation. Nothing here reboots anything; what is being tested is that the one login covers all of it.
- Pass if: no second login.

**SET-3** A failed login is not kept [hand]

- Do: EXIT, reopen, SETTINGS, REMOVE CACHED PIA CERT with a wrong password, CONTINUE.
- See: the login stays open with "The router refused that username or password." under the fields, and no offer to save the password (ID-155).
- Do: CANCEL, then REMOVE CACHED PIA CERT again.
- See: it asks again, prefilled.

**SET-4** Remove cached PIA cert [hand]

- Do: REMOVE CACHED PIA CERT, DELETE.
- See: "Cached PIA certificate deleted."
- Do: again.
- See: "No cached PIA certificate on the router."
- Pass if, on the router, `ls /jffs/cfg-pia-wg/pia_ca.rsa.4096.crt` says there is no such file.
- See: the next watchdog rebuild - the next one that runs, from BRK or from a check that fails - logs that it is downloading the certificate rather than reusing a cached one. If nothing rebuilds while you are on this screen, mark this line SKIP and look for it the next time one does.

**SET-5** Max active VPNs [hand]

- Do: MAX ACTIVE VPNS, enter `2`, SAVE. WD raised it to 4.
- Do: MAX ACTIVE VPNS, enter `6`.
- See: "Enter a number from 2 to 5."
- Do: you need a third slot to enable. wgc1 and wgc5 are both up; in MANAGE, if wgc3 reads `wgc3 <empty slot>`, CREATE it in any region.
- Do: MANAGE, select wgc3, ENABLE, with the limit still at 2.
- See: "VPN limit reached", saying 2 may run at once and 2 already are. `wg show interfaces` still lists two.
- Do: SETTINGS, MAX ACTIVE VPNS, enter `3`, SAVE.
- See: "Maximum active VPNs set to 3."
- Do: MANAGE, ENABLE wgc3 again, without leaving and re-entering MANAGE first.
- Pass if: it comes up, and `wg show interfaces` lists three. The limit is read at ENABLE, not when the list was loaded (ID-147).
- Pass if: `nvram get cfg_pia_wg_max_conn_prev` reads `2` - what the router had before the app raised it, which END-1 puts back.
- Do: MANAGE DISABLE wgc3 first - the limit counts tunnels that are running - then SETTINGS, MAX ACTIVE VPNS, enter `2`, SAVE.
- Pass if: `nvram get cfg_pia_wg_max_conn_prev` is now empty - there is nothing left to undo.
- Do: if you created wgc3 here, MANAGE DELETE it. Nothing later needs it.

**SET-6** Reboot [hand]

- Do: REBOOT ROUTER, REBOOT. Your SSH session drops with the router; reconnect once it is back.
- See: "Rebooting the router" with a percentage.
- See: it closes with "The router answered again after N seconds."
- Pass if: `wg show interfaces` lists the same tunnels as before, brought back by the router itself.

**SET-7** Forget router IP [ci]

- In CI: FORGET clears the stored address, greys itself out, and the next form falls back to the default. `test/screens/settings_screen_test.dart`.

**SET-8** Every action leaves a trail [hand]

- Pass if: APP LOG has "Deleted cached PIA certificate" (SET-4), "Maximum active VPNs set to 3" (SET-5) and "Router reboot requested" (SET-6), and ROUTER LOG has "Cached PIA certificate deleted from the app", "Maximum active VPNs set to 3" and "reboot requested from the app".
- Pass if: each action really happened, so the trail isn't just words: SET-4's `ls` found no certificate, `nvram get vpnc_max_conn` prints `3`, and `cat /proc/sys/kernel/random/boot_id` changed across SET-6.

**SET-9** Router resolver status [hand]

- Do: ROUTER RESOLVER STATUS.
- See: the heading in teal, then the live check: dnsmasq and stubby each OK, `running`, a time in ms, and every address example.com returned. With DNS-over-TLS off, stubby reads NOT USED.
- See: `/etc/dnsmasq.conf`, `/etc/hosts`, `/tmp/resolv.dnsmasq`, `/etc/stubby/stubby.yml` and `/etc/resolv.conf`, each with when it was written, then Active DNS settings (nvram). dnsmasq.conf carries the amber "review before sharing" line.
- Pass if: the files match `cat` on the router, and a long press selects text anywhere in the window.
- Do: COPY, and paste it somewhere.
- Pass if: the whole window comes out as text, in the same order.
- Do: in SSH, `kill $(pidof stubby)`, then REFRESH straight away, before the router's own watchdog can restart it.
- See: stubby FAILED, `not running`, and the amber advice naming stubby. If it already reads `running`, the router restarted it first: note that, which is worth knowing too.
- Do: `pidof stubby`; if it prints nothing, `service restart_dnsmasq`, or reboot if that does not bring it back. REFRESH shows both OK again.

**SET-10** Router DNS routing [hand]

- Do: ROUTER DNS ROUTING, with TABLET pinned to wgc1.
- See: the top line, "Only pinned devices' lookups go through a tunnel." on the recommended setup.
- See: YOUR DEVICES' LOOKUPS names TABLET under `wgc1:<region>`, tagged `tunnel` and `encrypted to PIA`; "Everything else" goes through stubby, tagged `Internet` and `encrypted (DoT)`.
- See: THE ROUTER'S OWN LOOKUPS lists each `/etc/resolv.conf` server: the DNS Server addresses tagged `not encrypted`, stubby tagged `encrypted (DoT)`, "only if both of the above fail".
- See: THE WATCHDOGS' LOOKUPS, one line per slot with its region, and `encrypted (DoH)` for each watchdog; an empty slot reads `not configured`.
- Pass if: EVIDENCE matches `ip rule show | grep 'iif lo'` and `iptables -t nat -S VPN_FUSION` on the router.
- Pass if: `/bin/sh /jffs/check-claims.sh quick` on the router shows PASS for `DNS-pinned` and `DNS-DoT`. The tags are the app's word; those two measure what they claim.
- Do: unpin TABLET, APPLY, back to SETTINGS, ROUTER DNS ROUTING.
- See: TABLET gone from YOUR DEVICES' LOOKUPS. With no device pinned anywhere, the top line reads "No lookups go through a tunnel." and the redirects section says no device is pinned; with others still pinned, it keeps "Only pinned devices' lookups go through a tunnel."

UNINSTALL is at the very end of the run: [END](#end).

---

## <a name='abt'></a>ABT. About

**ABT-1** Router facts without a session [hand]

- Do: EXIT, reopen, ABOUT.
- See: "login to router to retrieve" on the watchdog rows.
- Do: tap it, log in.
- See: the dialog closes only once the router has accepted the login, and your password manager offers to save it (ID-155).
- See: the watchdog script version, the router firmware, and the history line fill in.
- Do: MANAGE.
- See: it connects without asking: the login from ABOUT is kept for the session.

**ABT-2** Version rows [hand]

- See: Router firmware shows stock and its version.
- See: License status reads homegrown on a self-built copy; licensed or unlicenced on a store build.
- See: `Since <yyyy-mm-dd>: X successful & Y unsuccessful reconfigures`

**ABT-3** Script from another version [hand]

- Do: make the router's copy look as though an older build wrote it. On the router:

```bash
logger "**ABT-3 START** Script from another version"
sed -n '2p' /jffs/cfg-pia-wg/watchdog_wgc1.sh                                  # the real version, write it down
sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v0.0.1 build 1;/' /jffs/cfg-pia-wg/watchdog_wgc*.sh
logger "**ABT-3 END** Script from another version"
```

- Note: installing an APK of a different version over the top is the real-world case and does the same thing; editing the header line is the quick way to provoke it.
- Do: note `wg show wgc1 latest-handshakes` now, so you can tell afterwards whether the tunnel was restarted.
- Do: ABOUT, logging in if it asks.
- See: the script version in amber, reading `v0.0.1 build 1`, and UPDATE WATCHDOG VERSION centred on its own line directly above COPY BUILD INFO, in the same amber.
- Do: UPDATE WATCHDOG VERSION.
- See: APP LOG "Watchdog script updated to <this build> for wgc1:pia-<region>." - the same sentence as ROUTER LOG (ID-190) - and the row goes plain, showing this build's version.
- Pass if: `wg show wgc1 latest-handshakes` has carried on counting from the number you noted rather than resetting - no tunnel was restarted.
- Do: now make the router's copy NEWER than the app, as a Play build installed over a newer sideloaded one does: `sed -i '2s/cfg-pia-wg v[^;]*;/cfg-pia-wg v9.9.99 build 9999;/' /jffs/cfg-pia-wg/watchdog_wgc*.sh`
- Do: leave ABOUT and come back.
- See: this app's own version in red on the first line, the script's `v9.9.99 build 9999` in amber, and UPDATE WATCHDOG VERSION still offered (ID-157).
- Do: UPDATE WATCHDOG VERSION, so the router is back on this build.

**ABT-4** Buttons and links [hand]

- Do: COPY BUILD INFO.
- See: "Build info copied.", no countdown.
- Do: CREATE GITHUB ISSUE.
- See: a prefilled issue carrying the firmware type and version.
- Do: tap the Open source licences link.
- See: it opens on its own screen and does not bleed through the header.
- See: the link row is centred, and none of the five links is underlined; all five still open.

---

## <a name='ext'></a>EXT. Exit, background and session

**EXT-1** Password managers [hand]

- Do: on each of the four forms that ask for credentials - the router login on MANAGE, the router login ABOUT, SETTINGS and ROUTER LOG share, PIA details in MANAGE CREATE, and the SMTP login in WATCHDOG CREATE/EDIT - clear the field, then tap it.
- See: the password manager offers the matching saved login each time: SSH for both router logins, PIA, SMTP.

**EXT-2** Exit wipes [hand]

- Do: EXIT from the menu, and separately the back key on the home screen.
- See: both ask "Exit cfg-pia-wg?" first.
- Do: EXIT.
- Pass if: on reopening, every credential field is blank, staged device changes are gone, and pasting into a text field brings back nothing the app had copied.

**EXT-3** Router address survives exit [ci]

- In CI: EXIT wipes every credential but keeps the remembered address. `test/unit/router_prefs_test.dart`.

**EXT-4** Background under 5 minutes [hand]

- Do: on the router, `grep -c "Password auth succeeded" /tmp/syslog.log`, and write the count down.
- Do: in MANAGE, switch to another app for 1 minute, come back, press an action.
- Pass if: that count has not moved - the app used the session it already had.

**EXT-5** Background over 5 minutes [hand]

- Do: with the count from EXT-4 in hand, switch away for 6 minutes, come back, press an action.
- Pass if: it reconnects by itself, and `grep -c "Password auth succeeded" /tmp/syslog.log` has gone up by exactly one.
- Pass if: APP LOG says "Router SSH connection re-established." - the session the app closed on its own used to reopen in silence.
- Note: the syslog count is what decides this test. It's the router's own record of the login; the APP LOG line is only what you see.

**EXT-6** Release build privacy [hand]

- Do: on a **release** build, try to take a screenshot, then open the task switcher. A debug build allows both on purpose, so mark this SKIP if that is what you are running.
- See: the screenshot is refused, and the task switcher shows a blank or masked thumbnail rather than the screen.

**EXT-7** Rotate mid-action [hand]

- Do: start a watchdog SAVE & DEPLOY, rotate the tablet while it runs.
- Pass if: it completes and the screen is still usable.

**EXT-8** Leave mid-action [hand]

- Do: stage a device change in DEVICES, press APPLY, and while it is still running open the drawer and go to APP LOG.
- Pass if: APP LOG stays open while the apply completes (it shows the lines arriving), and going back to DEVICES shows the result, not "Applying - do not leave this screen". In the release-candidate run APP LOG closed by itself and DEVICES stayed on the spinner (ID-285).

**EXT-9** New icon and splash screen [hand]

- See: the launcher icon is the teal shield on dark navy, `assets/icon/app_icon_legacy.png`, not Flutter's default blue logo, on the home screen and in the app drawer (ID-111).
- Do: cold start the app - swipe it away first.
- See: a dark splash on the app's own background while it starts, not a white flash.
- See: on Android 12 and later, the system's circular splash uses the same artwork on the same background.

---

## <a name='lck'></a>LCK. Locked, with no purchase (store build)

Needs a store build, installed from a testing track, on an account that has not bought it. A self-built copy is always unlocked.

**LCK-1** Free things work [hand]

- Pass if: STANDALONE generates end to end; MANAGE, WATCHDOG and DEVICES open and show the real router.

**LCK-2** No install offer when locked [hand]

- Do: on the router, `mv /jffs/cfg-pia-wg/jq /jffs/cfg-pia-wg/jq.bak`, then connect from the app.
- Pass if: no install dialog and no missing-program warning - a locked app does not offer to put things on the router.
- Do: `mv /jffs/cfg-pia-wg/jq.bak /jffs/cfg-pia-wg/jq`.

**LCK-3** Paid controls open the paywall [hand]

- Do: tap each: MANAGE CREATE, ENABLE, EDIT; WATCHDOG CREATE/EDIT, ENABLE; DEVICES APPLY; ABOUT UPDATE WATCHDOG VERSION; SETTINGS MAX ACTIVE VPNS.
- To reach the two that need something on the router first: MANAGE ENABLE needs a configured slot that is off, so DISABLE one (free, LCK-4) and tap ENABLE. UPDATE WATCHDOG VERSION needs an out-of-date script, so run ABT-3's first `sed` line on the router, then open ABOUT.
- See: the paywall each time, and nothing reaches the router.

**LCK-4** Removing is free [hand]

- Pass if: DISABLE, DELETE and VIEW ROUTER WATCHDOG LOG work on both MANAGE and WATCHDOG.

**LCK-5** Staging is free [hand]

- Do: stage device changes, APPLY, NOT NOW.
- See: the changes still staged.

**LCK-6** Paywall only on a tap [hand]

- Pass if: never on launch, never on entering a screen.
- Pass if: a button that is greyed out for another reason - SAVE with a field empty, APPLY with nothing staged - stays greyed and does nothing, rather than opening the paywall.

**LCK-7** No store [hand]

Aeroplane mode cuts the phone off from the router as well, so nothing can be tested with it. Cut off only the internet: the phone stays on your Wi-Fi, and the router's WAN is unplugged. On a phone, turn mobile data off too, or it goes out that way instead.

- Do: unplug the router's WAN cable. Force-stop the app and start it cold.
- See: locked; the buy button reads "Not available right now" and is disabled.
- Do: tap "Already purchased? Restore".
- See: "Google Play can't be reached; this device looks to be offline." - not "No purchase found" (ID-288).
- Do: plug the WAN back in, and wait for the internet before BUY.

---

## <a name='buy'></a>BUY. Buying and restoring (store build)

Before starting, read [R8](#r8): the tester must be on BOTH Play Console lists, or the purchase charges real money.

**Run these in the order written**, which is not the order of their numbers: the group starts locked, buys, tests what a purchase gives, and ends by refunding, which locks the app again. "Unplug the WAN" means as in LCK-7: the phone stays on Wi-Fi, mobile data off.

**BUY-2** Not now [hand]

- Starts with: locked, from LCK.
- Do: a paid control, NOT NOW.
- See: back exactly where you were, still locked.

**BUY-1** Buy [hand]

- Do: any paid control, then buy.
- See: the price is the store's own, in your currency.
- See: Google's sheet says "test card, always approves".
- See: "Purchase complete. Router features unlocked." and the action you tapped carries on.
- Pass if: every paid control is live straight away, with no restart, and APP LOG has no warning about the store.

**BUY-6** Offline after buying [hand]

- Do: unplug the WAN. Force-stop the app and start it cold.
- See: still unlocked, and a paid control works on the router.
- Do: plug the WAN back in.

**BUY-4** Restore on reinstall [hand]

- Do: uninstall, reinstall from the track, open it.
- Pass if: already unlocked, with nothing pressed, and no sign-in prompt at launch.

**BUY-5** Restore by hand [hand]

- Do: SETTINGS, RESTORE PURCHASE.
- See: "This app is already unlocked on this Google account. Nothing changed." - not "Purchase restored".
- Do: uninstall, and reinstall from the track, but don't open it yet. Unplug the WAN, then open it.
- See: locked. It couldn't ask the store at launch, and a fresh install has nothing kept.
- Do: SETTINGS, RESTORE PURCHASE.
- See: a popup saying Google Play can't be reached, and "Google Play can't be reached; this device looks to be offline." in APP LOG (ID-288).
- Do: plug the WAN back in, wait for the internet, RESTORE PURCHASE.
- See: APP LOG "Restore started.", then "Purchase restored. Everything is unlocked."
- Do: on a second Google account that never bought it, RESTORE PURCHASE.
- See: "No purchase found on this Google account."

**BUY-3** Refund relocks [hand]

- Do: refund and revoke the order in Play Console, then wait for RevenueCat to catch up - a few minutes - and reopen the app.
- Pass if: it relocks without a reinstall, and a paid control shows the paywall again.

---

## <a name='mrl'></a>MRL. Merlin smoke test (under an hour)

Not a repeat of the whole run. The screens, DEVICES, the log windows and the paywall are the same code on both firmwares, and the automated tests build and run the watchdog script for both. This covers only what is different on Merlin: no helper programs, the kill switch, starting and stopping a tunnel, the mail command, boot persistence in `services-start`, and UNINSTALL (ID-301). Merlin is called beta in README and the Play description once it passes.

Set up: a Merlin router with JFFS scripts enabled, SSH on, and no cfg-pia-wg on it. Run in the order written. Bracket the router commands with `logger` lines, as elsewhere.

**MRL-1** Device assignment refuses [ci]

- In CI: Merlin is refused with a reason rather than an empty screen. `test/widgets/device_assignment_screen_test.dart`.

**MRL-2** No VPN limit [ci]

- In CI: on Merlin, which has no limit, MAX ACTIVE VPNS says so and writes nothing. `test/screens/settings_screen_test.dart`.

**MRL-4** Nothing installed [hand]

- Do: MANAGE, connect.
- Pass if: no install offer, APP LOG "Router firmware detected: merlin", and on the router `ls /jffs/cfg-pia-wg` lists no `jq` and no `mailsend-go` - Merlin ships its own.

**MRL-6** Create, enable, disable [hand]

- Do: MANAGE, wgc1, CREATE in any region, then ENABLE.
- See: APP LOG "wgc1:pia-<region> enabled: up, and both check addresses answered through it." and the ACTIVE badge.
- Do: DISABLE, then ENABLE again.
- Pass if: after DISABLE, `wg show interfaces` no longer lists wgc1; after ENABLE, it does, and the badge is back.

**MRL-3** Kill switch [hand]

- See: the KILL SWITCH badge on wgc1's row when its kill switch is on, and the kill switch control in EDIT, which stock does not show.
- Pass if: `nvram get wgc1_enforce` prints `1` while the badge shows, and `0` after you turn the kill switch off in EDIT and the badge goes.

**MRL-7** Watchdog and email [hand]

- Do: WATCHDOG, wgc1, CREATE/EDIT, email alerts on, TEST EMAIL.
- See: "Test email sent to ..." and the email arrives. Merlin sends it with its own tools, not `mailsend-go`.
- Do: SAVE & DEPLOY.
- See: the slot shows WATCHDOG ACTIVE, and a SUCCESS email saying "watchdog deployed".

**MRL-8** Break and rebuild [hand]

- Do: on the router:

```bash
logger "**MRL-8 START** Break and rebuild"
wg set wgc1 peer "$(nvram get wgc1_ppub)" remove
/jffs/cfg-pia-wg/watchdog_wgc1.sh foreground
tail -4 /tmp/watchdog_wgc1.log
logger "**MRL-8 END** Break and rebuild"
```

- Pass if: the log ends `Reconfig SUCCESS` then `Alert email sent (SUCCESS)`, and the SUCCESS email arrives with the kill switch line in Merlin's wording.
- Pass if: that line agrees with `nvram get wgc1_enforce`: ON for `1`, OFF for `0`. The line reports the setting, so the setting is the check.

**MRL-10** The router check on Merlin [script]

- Starts with: a watchdog on wgc1 with its kill switch on, and a VPN Director rule sending one device to WGC1.
- Do: on the router, `/bin/sh /jffs/check-claims.sh quick`, then `full`.
- Pass if: no FAIL. `MAIL-name`: openssl, as Merlin's mail runs it, refuses a certificate for the wrong name and accepts the right one. `KS-wgc1-stopped`: with wgc1 stopped, the VPN Director device's route to the internet is refused, not out of the WAN. Full's `SETUP-as-is`: a real rebuild, with every PIA name looked up over DoH and packets counted by the router at the DoH server; `MAIL-sent`: its SUCCESS email sent (ID-353).

**MRL-11** SECURE STARTUP is stock only [hand]

- Do: after MANAGE has connected, SETTINGS.
- Pass if: there is no SECURE STARTUP. Before the app knows the firmware it shows, and a tap says "Merlin's own kill switch already covers this, so there is nothing to change." with no popup (ID-356).

**MRL-5** Boot persistence [hand]

- Do: on the router: `grep cfg-pia-wg /jffs/scripts/services-start; cru l | grep watchdog_`
- See: two `cru a` lines for wgc1 in `services-start` - the check and the log rotate - and the same two in `cru l`.
- Do: SETTINGS, REBOOT ROUTER, REBOOT. When it's back, wait 2 minutes, then `cru l | grep watchdog_` in a new SSH session.
- Pass if: both entries are back, and the watchdog's next check logs `Handshake Ns ago`.

**MRL-9** Uninstall [hand]

- Do: SETTINGS, UNINSTALL FEATURES DEPLOYED TO ROUTER, both prompts.
- See: "Removed the watchdog lines from /jffs/scripts/services-start" among the results (ID-303).
- Do: on the router:

```bash
grep -c watchdog_ /jffs/scripts/services-start
cru l | grep -c watchdog_
ls /jffs/cfg-pia-wg
wg show interfaces
```

- Pass if: `0`, `0`, no such folder, and wgc1 still listed: the tunnel stays, as on stock.
- Do: reboot, and check `cru l | grep watchdog_` prints nothing: the next boot does not put the schedule back.

---

## <a name='end'></a>END. Last, because it removes things

**END-1** Uninstall [hand]

- Do: SETTINGS, UNINSTALL FEATURES DEPLOYED TO ROUTER.
- See: two prompts; the second says what it will do, with CANCEL first in grey and UNINSTALL second in red.
- See: "Removed from the router", one line per step, and "Please restart your router."
- Pass if, on the router:

```bash
logger "**END-1 START** Uninstall"
ls -l /opt/etc/init.d/S50downloadmaster /opt/etc/init.d/S50asuslighttpd   # restored, or gone
cru l                                    # no watchdog entries
nvram show | grep cfg_pia_wg             # nothing
nvram show | grep -E 'wgc[1-9]_wd_'      # nothing
ls /jffs/cfg-pia-wg                      # gone, guard.sh with it
ip rule show | grep -E '^9[01]:'         # nothing: the guard's rules went first
for N in 201 202 203 204 205; do ip route show table $N; done   # nothing: and its tables
wg show interfaces                       # UNCHANGED: the tunnels are not the app's to remove
nvram get vpnc_max_conn                  # back to 2, if the app raised it (SET-5); untouched if you set it yourself
logger "**END-1 END** Uninstall"
```

- See: the list of what it did includes either "Put the maximum active VPNs back to 2" or "Left the maximum active VPNs alone - the app never changed it", whichever is true of this run.

**END-2** Uninstall twice [hand]

- Do: UNINSTALL again on the same router.
- Pass if: it reports each script is not the app's and deletes nothing. Removing the router's own `S50downloadmaster` here is the bug the header line prevents.

---

# Part 2. Reference

## <a name='r1'></a>R1. When something looks broken, check these first

Each of these presents as a different fault from the one it is, and none of them is guessable.

**`rc_service: skip the event:` in `/tmp/syslog.log`.** The router is silently discarding every service call it is given, and has been since an earlier one hung. Nothing works after that: not the app, not the WebUI, not `reboot`. Only a power cycle clears it. The app detects and clears the stale marker before deploying, but if you see this line while testing by hand, stop: nothing you observe afterwards means anything. Detail in [ARCHITECTURE.md, The router's service queue and how it wedges](ARCHITECTURE.md#the-routers-service-queue-and-how-it-wedges).

**A token fetch that exits 0 with no HTTP status, no body and nothing on stderr.** Stock's `/usr/sbin/curl` refuses to run when `crond` is among its parent processes. It does not fail, it does nothing. Confirm it by looking for `Invalid caller(crond)` in `/jffs/curllst`. Detail in [ARCHITECTURE.md, `curl` refuses to run from cron](ARCHITECTURE.md#curl-refuses-to-run-from-cron).

> [!CAUTION]
> `/jffs/curllst` is world-readable, survives reboots, and records full command lines: the PIA login too, from a watchdog deployed before build 487. Redact it before pasting it anywhere, a bug report included.

**A device assignment that is written correctly and has no effect.** Check `ip rule show` first. Stock never removes a device's previous rule when it is reassigned, so both rules sit at priority 100 and the older one wins. The record in `vpnc_dev_policy_list` looks perfect the whole time. Detail in [ARCHITECTURE.md, Stock leaves the old routing rule behind](ARCHITECTURE.md#stock-leaves-the-old-routing-rule-behind-measure).

**Devices with no internet while every tunnel looks up, or the router's settings gone after a reboot.** Each was seen once and never explained: a phone and the media centre offline with both tunnels up and both watchdogs content, fixed by a reboot but not by `restart_net_and_phy` (ID-195, 2026-09-23); and every WireGuard setting gone after a reboot that followed an NVRAM commit, with the first `jffs2: check_node_data: wrong data CRC` error in that boot's log (ID-219, 2026-09-24). A restart or a reboot destroys most of the evidence, so capture first:

- From a LAN device: `ping 1.1.1.1`, `nslookup google.com`, `nslookup google.com 9.9.9.9`. If the address answers, the first lookup fails and the second works, it's the router's resolver, not the tunnels.
- On the router:

```bash
ip rule show; ip route show table main; ip route show table 5; ip route show table 9
for T in 201 202 203 204 205; do echo "== table $T"; ip route show table $T; done
nvram get vpnc_default_wan; nvram get vpnc_unit; nvram get vpnc_dev_policy_list
cat /tmp/resolv.dnsmasq; ps | grep -E 'stubby|dnsmasq'; nslookup google.com 127.0.0.1; wg show interfaces
```

- If settings are missing after a reboot, also `dmesg | grep -i jffs2` and `nvram get wgc1_desc`, and keep copies of `/tmp/syslog.log` and `/jffs/syslog.log`.

Two candidates were never ruled out for the first: the router's resolver (that night dnsmasq was restarted and stubby wasn't; the reboot restarted both), and, for one device alone, a 5 GHz radio flapping on a DFS channel (52). Moving 5 GHz to a channel outside DFS costs nothing and rules the second out.

## <a name='r2'></a>R2. How the watchdog decides a tunnel is broken

Each check, the watchdog decides in this order:

- If `wgcN_enable` is `0` and this is not a deploy, it stands down: the user turned the tunnel off.
- If the interface is not up (`ip -o link show up`), the tunnel is broken. Detected at once.
- If the newest handshake (`wg show wgcN latest-handshakes`) is under 300 seconds old, the tunnel is healthy.
- Otherwise it pings the two check targets through the interface. On stock that ping always fails, because the router's own traffic is not routed into `wgcN`, so on stock the handshake is the only real test.

So a good test breaks the crypto or the peer, or takes the interface down, and touches neither the WAN nor the check targets.

**The clock runs from the last handshake, not from when you broke the tunnel.** `wg show wgcN latest-handshakes` shows where you are. The watchdog reacts at the first check where that age passes 300 seconds, so the worst case is 300 seconds plus one check interval. A check logging `Handshake 264s ago` after you broke it is the window working. Removing the peer skips the wait, because it removes the handshake record too.

**PIA rate-limits token requests.** The watchdog backs off after failed attempts ([R3](#r3)), but two failing watchdogs climb their ladders independently. If `failed to obtain PIA token` appears with `HTTP 403`, stop and wait 15 to 30 minutes. Test one slot at a time, at a 5 minute interval.

**When PIA expires a registration.** There is nothing published about when PIA rotates or expires a key registration: it has been seen after a day and after a couple of weeks. Observed, not measured: a config seems to age faster when a nearby region is enabled after another nearby region was disabled, plausibly because they are hosted in the same data centre. That is why BRK-1, which lets the handshake age out, is the test that matters most.

Expected watchdog log for a registration that died (BRK-1), once the handshake passes 300 seconds:

```text
2026-09-04 16:40:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 16:40:08 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-04 16:40:08 Connectivity lost; reconfiguring (attempt #1)
2026-09-04 16:40:08 WAN has internet connectivity
2026-09-04 16:40:09 Requesting PIA token for user pNNNNNNN
2026-09-04 16:40:09 PIA token obtained (len=124)
...
2026-09-04 16:40:15 Reconfig SUCCESS: region pia-aus_melbourne via 192.0.2.10:1337
```

Peer removed (BRK-2), verified 2026-09-04 with a 5 minute interval:

```text
18:49:13 Checking wgc1 pia-aus_melbourne connectivity
18:49:13 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
18:49:13 Connectivity lost; reconfiguring (attempt #1)
18:49:14 PIA token obtained (len=124)
18:49:14 Selected server 192.0.2.11 (Server-12444-0a) for region pia-aus_melbourne
18:49:20 Interface wgc1 is up
18:49:20 Reconfig SUCCESS: region pia-aus_melbourne via 192.0.2.11:1337
18:50:00 Handshake 44s ago
```

Interface down (BRK-3):

```text
2026-09-04 16:45:00 Checking wgc1 pia-aus_melbourne connectivity
2026-09-04 16:45:00 Interface wgc1 is down or absent
2026-09-04 16:45:00 Connectivity lost; reconfiguring (attempt #1)
```

A healthy check:

```text
2026-09-04 15:48:00 Checking wgcN pia-region_name connectivity
2026-09-04 15:48:00 Handshake 60s ago
```

The server addresses in these examples are invented.

**"Reconfig SUCCESS" only means the interface came up.** The script does not check for a handshake afterwards (BACKLOG ID-063). The proof of recovery is the next check logging `Handshake Ns ago`, and a new peer key in `wg show wgcN`.

**Methods that look right and are not used:**

- **Moving the peer's endpoint** (`wg set wgcN peer ... endpoint 203.0.113.1:1337`). WireGuard accepts it, then puts the real endpoint back within seconds: endpoint roaming updates a peer's endpoint whenever an authenticated packet arrives from it. No reconfigure ever happens. Anything that leaves the keys intact is undone the same way.
- **Turning the tunnel off in the WebUI.** Tests the stand-down (BRK-4), not recovery.
- **MANAGE DISABLE or DELETE, or WATCHDOG DISABLE.** Each removes or pauses the watchdog itself.
- **Blocking the server with a firewall rule.** If the rebuild picks the same server, registration over TCP still works and the interface comes up, so it can log a false `Reconfig SUCCESS`.
- **Pulling the WAN cable.** The watchdog finds no internet on the WAN and exits without alerting, and the whole LAN goes offline with it.
- **Unreachable check targets.** The same targets are the WAN check, so the run exits quietly.

If a rebuild stops at the token request, check that the deployed script carries a version of v0.8.46 build 416 or later: earlier scripts could not fetch a PIA token from cron at all. Deleting `/tmp/watchdog_backoff_wgcN` makes the next check run in full rather than backing off.

## <a name='r3'></a>R3. The backoff ladder

The wait before the next rebuild attempt grows with each consecutive failed attempt, and resets at the next healthy check:

- 1 failure: 2 minutes
- 2: 4 minutes
- 3: 8 minutes
- 4: 16 minutes
- 5: 30 minutes
- 6: 60 minutes
- 7 or more: 90 minutes, the cap

A check that arrives inside the wait is turned away and says so:

```text
2026-09-04 16:41:00 No handshake and both pings failed (8.8.8.8, 1.1.1.1)
2026-09-04 16:41:00 Backing off after 3 failed attempts: 45s of 480s elapsed
```

`/tmp/watchdog_backoff_wgcN` holds the attempt count and a timestamp. The count rises only when an attempt is actually made. A run the backoff turned away must leave it alone, or the ladder would climb faster on a 1 minute interval than on a 5 minute one.

**Why BRK-6 does not just let it fail for four hours.** Reaching the 90 minute rung honestly means seven consecutive failed rebuilds, each asking PIA for a token. That got the account refused with HTTP 403 on 2026-09-04, and takes most of a day.

**Why it is safe.** The backoff gate sits after the connectivity check and before the first PIA call. A run the gate turns away logs one line and exits, so pre-loading the counter exercises the real arithmetic in the real deployed script without a single token request.

**Why the watchdog is paused first.** Otherwise cron fires its own checks during the test, and one that arrives after a wait has elapsed would perform a genuine rebuild part-way through.

**Why the check must be failing.** A healthy tunnel exits at the handshake check and never reaches the backoff.

`scripts/test-backoff.sh` checks both preconditions and refuses rather than misleading you, walks every rung, checks the two properties below, cleans up, and exits non-zero on any failure. The same loop by hand:

```bash
for n in 1 2 3 4 5 6 7 12; do
    printf '%s\n%s\n' "$n" "$(date +%s)" > /tmp/watchdog_backoff_wgc5
    /jffs/cfg-pia-wg/watchdog_wgc5.sh foreground >/dev/null 2>&1
    echo "CNT=$n -> $(grep 'Backing off' /tmp/watchdog_wgc5.log | tail -1)"
done
```

Verified on stock, build 409, 2026-09-06:

```text
CNT=1  -> Backing off after 1 failed attempts: 1s of 120s elapsed
CNT=2  -> Backing off after 2 failed attempts: 0s of 240s elapsed
CNT=3  -> Backing off after 3 failed attempts: 0s of 480s elapsed
CNT=4  -> Backing off after 4 failed attempts: 0s of 960s elapsed
CNT=5  -> Backing off after 5 failed attempts: 0s of 1800s elapsed
CNT=6  -> Backing off after 6 failed attempts: 0s of 3600s elapsed
CNT=7  -> Backing off after 7 failed attempts: 0s of 5400s elapsed
CNT=12 -> Backing off after 12 failed attempts: 0s of 5400s elapsed
```

The two properties most easily broken by a later change:

- `grep -c 'Requesting PIA token' /tmp/watchdog_wgc5.log` does not change across the loop. If it does, the gate has moved after the first PIA call.
- `head -1 /tmp/watchdog_backoff_wgc5` still reads `12` afterwards. A turned-away run must not increment the counter.

Clean up with `rm -f /tmp/watchdog_backoff_wgc5`, then ENABLE the watchdog in the app.

## <a name='r4'></a>R4. What the watchdog leaves on the router

**Files, on both firmwares:**

```text
/jffs/cfg-pia-wg/                         # everything the app owns lives here
/jffs/cfg-pia-wg/watchdog_wgcN.sh         # one per watched slot
/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt      # cached PIA CA, shared by all slots
/tmp/watchdog_wgcN.log                    # and .log.old after the nightly rotate
/tmp/watchdog_last_ping_success_wgcN
/tmp/watchdog_backoff_wgcN
/tmp/watchdog_unsent_wgcN                 # only after an alert email failed to send
```

**Stock also has**, because it has no `/jffs/scripts` hooks:

```text
/jffs/cfg-pia-wg/jq                       # installed by the app
/jffs/cfg-pia-wg/mailsend-go              # installed by the app, for the watchdog screen
/opt/etc/init.d/S50downloadmaster         # boot persistence, replacement block only
/opt/etc/init.d/S50asuslighttpd           # a stub that returns immediately
```

Merlin uses `/jffs/scripts/services-start` for boot persistence and has nothing installed: it ships `jq` and sends mail with the BusyBox `sendmail` it already has. `jq` or `mailsend-go` under `/jffs/cfg-pia-wg` on a Merlin router was put there by hand.

**Checks on those files:**

- Both init scripts carry `# <name> - auto-generated by cfg-pia-wg; *do* *not* edit.` as their second line.
- Where one replaced a real script, the original is beside it with a `.old` suffix.
- The watchdog script carries a version line, and ABOUT reports it.
- Boot persistence holds two lines per watched slot, between the `REPLACEMENT START` and `REPLACEMENT END` markers on stock:

```bash
cru a watchdog_wgc1 "*/5 * * * *" /jffs/cfg-pia-wg/watchdog_wgc1.sh
cru a watchdog_log_rotate_wgc1 "0 0 * * *" "mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old && touch /tmp/watchdog_wgc1.log"
```

- `cru l` and `crontab -l` show the same two lines, updated immediately when the interval changes.
- Removing a watchdog's lines leaves the boot persistence file at permissions `700`, and anything else in it untouched.

**NVRAM, per watched slot** (`nvram show | grep wgc1_wd_`), ten keys:

```text
wgc1_wd_check_interval=5
wgc1_wd_email_enabled=0
wgc1_wd_email_from=
wgc1_wd_email_subject=cfg-pia-wg alert
wgc1_wd_email_to=
wgc1_wd_primary_ip=8.8.8.8
wgc1_wd_secondary_ip=1.1.1.1
wgc1_wd_smtp_pass=
wgc1_wd_smtp_server=
wgc1_wd_smtp_user=
```

**NVRAM, shared** (`nvram show | grep cfg_pia_wg`):

```text
cfg_pia_wg_password=...
cfg_pia_wg_reconfig_fail=1     # lifetime failed rebuilds, all slots
cfg_pia_wg_reconfig_ok=4       # lifetime successful rebuilds, all slots
cfg_pia_wg_sdate=2026-09-01    # the day the app first configured this router
cfg_pia_wg_user=...
```

The three counter keys are seeded together by whichever of a watchdog deploy or a test email comes first, and committed once per alert rather than once per check, because `nvram commit` writes flash.

**What WATCHDOG DISABLE, WATCHDOG DELETE and UNINSTALL remove:**

- DISABLE removes the slot's two `cru` jobs and its boot persistence lines. The script, the settings and the tunnel stay.
- DELETE removes the jobs, the lines, the script, the `/tmp` files and the ten `wgcN_wd_*` keys, stops the tunnel and deletes the VPN. The shared PIA credentials go only when no other slot still has a scheduled watchdog.
- UNINSTALL removes every file above, every `cfg_pia_wg_*` and `wgcN_wd_*` key, and every `cru` entry the app created. It does not touch the tunnels: `wgcN_*`, the profiles and `vpnc_clientlist` are the user's, and so are device assignments and the default connection.

## <a name='r5'></a>R5. Device assignment and default connection notes

**One profile has three numbers.** Its slot (wgcN), its row in `vpnc_clientlist` (which `vpnc_unit` wants), and its index 6. `vpnc_default_wan` and `vpnc_dev_policy_list` want index 6, so a value of `9` is normal on a five-slot router. Read each profile's index 6 as field 7 of its record in `nvram get vpnc_clientlist | tr '<' '\n'`. On one run wgc1 was 9 and wgc5 was 5. See [ARCHITECTURE.md, The three numbers that name one profile](ARCHITECTURE.md#the-three-numbers-that-name-one-profile).

**Records and rules:**

- Pinned to a tunnel: `1><ip>>><index 6>>`, and one rule at priority 100, `lookup <index 6>`.
- Pinned to Internet: `1><ip>>>0>`, and one rule, `lookup main`.
- Following the default: `0><ip>>>0>`, and no rule for that address.
- The default connection itself: two rules at priority 10000, `from all iif br0` and `from all iif br1`, both `lookup <index 6>`. A per-device rule at priority 100 always wins over them.

**Three behaviours that were each a real fault:**

- **Internet, then straight to a tunnel.** Pinning to Internet writes `lookup main`, and until build 436 the stale-rule sweep matched only digits and could not see it. The device stayed on the WAN through every later move until a reboot. DEV-6 tests it.
- **Deleting a VPN with devices pinned to it.** Those devices go to Internet, matching the WebUI, not to the default connection. A device that was explicitly pinned must never land on a tunnel nobody chose. DEV-15 tests it.
- **Deleting the VPN that is the default.** `vpnc_default_wan` is a key, not a policy record, so nothing that rewrites the policy list touches it. Left behind, every device following the default read as `profile 9 (deleted)`. DEF-9 tests it.

**Reservations.** Assigning a device with no DHCP reservation adds one to `dhcp_staticlist`, applied with `restart_dnsmasq` and `restart_vpnc_dev_policy`. Nothing on the LAN drops. Unassigning removes the policy record and keeps the reservation: that is the firmware's behaviour, and the app does not remove it. The WebUI's own way of adding or removing a reservation restarts the network and the physical layer (every switch port, a new WAN lease), so avoid making reservation changes in the WebUI mid-test.

**A reservation is tied to a MAC.** A phone with a random MAC per network keeps its assignment only while it keeps that MAC. DEV-16 records what happens.

**`nvram get` straight after a `service` call proves nothing.** `notify_rc` queues and returns at once. Poll for the effect instead: the interface appearing in `wg show interfaces`, or the key changing.

## <a name='r6'></a>R6. Sending email by hand

**Use TEST EMAIL first.** It sends a real message through the settings on screen and reports what the server said, using the same path as the watchdog. What follows is for when that fails and you need to see why.

The two firmwares send mail differently:

- **Merlin:** BusyBox `sendmail` wrapped in `openssl s_client` for implicit TLS. Built in.
- **Stock:** `mailsend-go`, with `-ssl -verifyCert`. Installed by the app into `/jffs/cfg-pia-wg`. Stock has no `sendmail` of any kind.

Both use TLS with a verified CA bundle and fail the handshake rather than falling back, so an alert never leaves the router with the credentials exposed.

**Stock:**

```bash
/jffs/cfg-pia-wg/mailsend-go -ssl -verifyCert \
    -smtp smtp.gmail.com -port 465 -sub "test from the router" \
    -f "sender@example.com" -t "recipient@example.com" \
    auth -user "sender@example.com" -pass "APP_PASSWORD" \
    body -file /tmp/test-email.txt
```

`mailsend-go` builds its own headers from those flags, so its body file is the message text alone: no `From:`, `To:` or `Subject:` lines, and no blank separator line. That is the one difference that catches you out if you copy the Merlin body below.

**Merlin.** Replace `sender@example.com`, `recipient@example.com` and `APP_PASSWORD`:

```bash
sendmail -v \
    -H "exec openssl s_client -quiet -tls1_3 -connect smtp.gmail.com:465 -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error" \
    -au"sender@example.com" -ap"APP_PASSWORD" \
    -f"sender@example.com" recipient@example.com \
    < /tmp/test-email.txt
```

> [!CAUTION]
> The command above exposes the app password to shell history and the process list, both cleared at reboot. For anything but a quick test, put the password in a file: `nano /tmp/.smtp-pass`, `chmod 600 /tmp/.smtp-pass`, then use `-ap$(cat /tmp/.smtp-pass)`.

**The test message (Merlin).** Replace the names and addresses:

```bash
cat << EOF > /tmp/test-email.txt
From: Sender Name <sender@example.com>
To: Recipient Name <recipient@example.com>
Subject: Test Email from Command Line - $(date '+%Y-%m-%d %H:%M:%S')
Date: $(date -R)
Message-ID: <$(date +%s).test@$(uname -n)>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: 7bit

Hello,

This is a test email created via command line.

Created at: $(date '+%Y-%m-%d %H:%M:%S')
Host: $(uname -n)

Command Line Tester
EOF
```

- Recreate the file for every send: Google may silently not deliver a repeat of the same `Message-ID:`.
- `EOF` is unquoted on purpose, so `date` and `uname` expand.

**How the Merlin command works.** `sendmail -v` runs verbosely. `-H` hands the connection to `openssl s_client`, which wraps it in TLS 1.3, checks the server's certificate chain against the router's trusted authorities (`-CAfile`), and stops the transmission (`-verify_return_error`) if any certificate is missing or invalid. Once the channel is verified, `sendmail` authenticates (`-au`, `-ap`), sends the envelope, and pipes the message into the session. A good run ends with lines like:

```text
sendmail: recv:'235 2.7.0 Accepted'
sendmail: send:'MAIL FROM:<sender@example.com>'
sendmail: recv:'250 2.1.0 OK ... - gsmtp'
sendmail: send:'RCPT TO:<recipient@example.com>'
sendmail: recv:'250 2.1.5 OK ... - gsmtp'
sendmail: send:'DATA'
sendmail: recv:'354 Go ahead ... - gsmtp'
...
sendmail: recv:'250 2.0.0 OK ... - gsmtp'
sendmail: send:'QUIT'
sendmail: recv:'221 2.0.0 closing connection ... - gsmtp'
```

The username and password are not echoed.

**Certificate detail** (a lot of output):

```bash
openssl s_client -connect smtp.gmail.com:465 -tls1_3 \
    -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error \
    -showcerts < /dev/null
```

## <a name='r7'></a>R7. Examining NVRAM

What the fields mean is in [ARCHITECTURE.md, Router WireGuard NVRAM fields](ARCHITECTURE.md#router-wireguard-nvram-fields). This section is only how to look at them.

The best source of information is `tail -f /tmp/syslog.log`. It shows every `service` call, such as `service restart_vpnc`.

- The two helper scripts, the fastest way to start a clean run. Copy them from `scripts/` with `scp`:

```bash
./showall.sh    # every wgcN_, vpncN_, vpnc_ and cfg_pia_wg_ key, plus wg interfaces and cru
./clearall.sh   # unset all of them, including the counters, and commit
```

- WireGuard:

```bash
wg                  # show everything
wg show interfaces  # interface names only
```

- Watch interfaces come and go, once a second for a minute:

```bash
i=1; while [ $i -le 60 ]; do echo "$(date +%H:%M:%S) - $(wg show interfaces)"; sleep 1; i=$((i+1)); done
```

- Watch `vpnc_unit`, which changes as each slot is acted on:

```bash
i=1; while [ $i -le 9999 ]; do echo "$(date +%H:%M:%S) - $(nvram get vpnc_unit)"; usleep 500000; i=$((i+1)); done
```

- Watch the processes that run when a VPN comes up, goes down, or is created or deleted:

```bash
i=1; while [ $i -le 30000 ]; do echo "$(date +%H:%M:%S) - $(ps | grep -E "vpnc|vpn|openvpn|wg" | grep -v grep | head -5)"; usleep 200000; i=$((i+1)); done
```

> [!WARNING]
> Very small `usleep` values can crash `syslogd` or the router.

- The VPN profile list, one record per line:

```bash
nvram get vpnc_clientlist | tr "<" "\n"
```

- Every WireGuard slot setting:

```bash
nvram show | grep -E "wgc[1-9]_" | sort
```

- Clear one slot by hand (the first slot the WebUI creates is always wgc5):

```bash
for v in wgc5_addr wgc5_aips wgc5_alive wgc5_dns wgc5_enable wgc5_ep_addr wgc5_ep_addr_r wgc5_ep_port wgc5_mtu wgc5_nat wgc5_ppub wgc5_priv wgc5_psk; do nvram unset "$v"; done; nvram commit
```

- VPN runtime state, and the `vpnc_` keys including `vpnc_unit` and `vpnc_max_conn`:

```bash
nvram show | grep -E "vpnc([1-9]|1[0-6])_" | sort
nvram show | grep -E "vpnc_" | sort
```

## <a name='r8'></a>R8. Store testing notes

- **A local build cannot test buying.** Google Play refuses purchases from an app it did not distribute, and a local build has no store key, so it is always unlocked and never shows a paywall. That is the designed behaviour.
- **Two Play Console lists.** The tester account must be on the licence testers list AND opted in to the testing track. Miss the second and the purchase charges real money.
- **RevenueCat hides test purchases by default.** Turn on the Sandbox toggle beside Recent Transactions, or a working purchase looks like no purchase at all.
- **Customer counts never move for a refund.** A customer record is created on first launch and persists; only the entitlement goes. Read the individual customer record, not the dashboard totals.
- **Expect ghost customers after every release.** Play's pre-launch report runs the app on its own devices, and each launch creates an anonymous customer that never buys. Measured 2026-09-12: seven, United States, Android 30, within twenty minutes of the upload.
- **If a refund does not relock the app**, real-time developer notifications are not wired up, and the refund window cannot be used as a trial.
- **`android:allowBackup="false"`** means nothing local survives a reinstall. A restored unlock comes from Play, through `syncPurchases` at launch.
- **No sign-in prompt may appear at launch.** One appearing means something is calling restore programmatically, which RevenueCat's guidance forbids.

---

## <a name='r9'></a>R9. What the shape tests stand for, and what proves it

Some automated tests can only check that a command is written a certain way: that the watchdog passes `-verifyCert`, say. That proves the text, not what the router does with it. Until build 475 one of them stood between the app and a claim that was false for weeks: every test passed `--doh-url` to curl, and ASUS's curl ignores it. So each of these keeps its shape test, and is paired here with the check that watches the behaviour on a real router. `check-claims` is `scripts/check-claims.sh`, run on the router as `/bin/sh check-claims.sh quick` or `full`; each of its checks breaks the thing on purpose, or has a control, so it can fail.

| Shape test | Stands for | Proved on the router by |
| --- | --- | --- |
| `test/unit/doh_resolver_test.dart`, `test/unit/input_checks_test.dart`: the DoH server's address and `--resolve` | the watchdog looks up PIA's names and the SMTP host over encrypted DNS | `test/unit/doh_lookup_test.dart` and its two `doh_lookup_*_test.dart` siblings run a real RFC 8484 lookup against a fake DoH server; check-claims `SETUP-*` (full) rebuilds under six DNS setups, and a dead or missing DoH server must be logged as plain |
| `test/watchdog_harness.dart`: the fake `curl` and `openssl` | ASUS curl's behaviour | the fakes copy what was measured (build 475): `--doh-url` ignored, `--cacert` and `--resolve` honoured. check-claims `DOH-0` says whether curl still ignores `--doh-url` |
| `test/router_watchdog_unit_test.dart`: `-S --cacert` | addKey trusts only PIA's CA | check-claims `TLS-pin`: PIA's own website is refused under PIA's CA. In the app, `test/unit/pia_register_pin_test.dart` does real TLS against a server with the wrong CA |
| `test/router_watchdog_unit_test.dart`: `--tlsv1.2` | the TLS floor | check-claims `TLS-floor`: a TLS 1.1 server is refused |
| `test/router_watchdog_unit_test.dart`: `openssl s_client -verify_hostname` (Merlin) | Merlin's mail checks the server's name | none yet: needs a Merlin router (MRL-7 is the happy path) |
| `test/router_watchdog_unit_test.dart`, `test/router_watchdog_service_test.dart`: `-ssl -verifyCert` | mailsend-go checks the certificate and its name | check-claims `MAIL-name`, with `MAIL-0` as its control, and `MAIL-script` for each deployed watchdog |
| `test/router_watchdog_unit_test.dart`: `echo -n > /jffs/curllst` | the PIA password isn't left on flash | check-claims `SECRET-curllst` |
| `test/router_watchdog_service_test.dart`: `nvram unset cfg_pia_wg_password` | the credentials go when the last watchdog is deleted | by hand, after deleting the last watchdog: `nvram get cfg_pia_wg_password` prints nothing. END-1 covers UNINSTALL |
| `test/unit/router_dns_test.dart`, `test/screens/router_dns_screen_test.dart`: the "encrypted" tags | the router's own lookups really are encrypted | check-claims `DNS-DoT`: with DNS-over-TLS on, fresh lookups send nothing to port 53 on the WAN, and a direct plain query is counted, as the control |
| `test/unit/email_layout_test.dart`: the kill-switch line counts rules | the email's "kept off the internet" line | BRK-1 checks TABLET is offline and its exit IP; nothing checks the line's own words |
| `test/unit/s50_template_test.dart`: the boot hook runs `guard.sh`, and asks for a run on firewall-start | nothing leaks during a boot, and the router's events put the guard back | GRD-7 (`scripts/check-reboot.sh`), from a pinned device, three times; check-claims `GUARD-boot`, `GUARD-hook` and `GUARD-event`, and `GUARD-wgcN-back` after a tunnel restart |
| `test/unit/guard_filter_test.dart` and `guard_filter_more_test.dart`: the Network Services Filter against a fake `nvram`, `service` and `iptables` | the router drops a pinned device's traffic out of the WAN from boot, and only the app's entries are touched | check-claims `FILTER-*`, read from the firewall itself; GRD-7 and GRD-8 |
| `test/unit/fail_closed_guard_test.dart` and `guard_orphan_wan_test.dart`: `guard.sh` against a fake `ip` | the kernel honours the guard's rules | check-claims `GUARD-*`: `ip route get` from every pinned device to the internet and every address main sends out of the WAN, with a rule wiped and repaired by the router's own firewall restart, a WAN route planted in the guard's table, the table emptied with its tunnel up, and the tunnel stopped, rule 91 taken away for a moment to show the leak it stops (ID-364). GRD-2, GRD-3, GRD-9 and DEF-7 by hand |
| `test/unit/device_assignment_service_test.dart`: the stale rule is deleted | a moved device really moves | DEV-5, DEV-6 and DEV-8: `e2e.sh` counts the rules and checks the exit IP |
| `test/router_watchdog_service_test.dart`: `nvram set wgcN_dns` | pinned devices' DNS goes through their tunnel | check-claims `DNS-pinned`; WD-23 and DEV-10 by hand |
| `test/unit/binary_installer_test.dart`: a fake `dgst` | a download is refused if its checksum is wrong | CON-5 is the happy path; the refusal is only tested in CI |
| `test/busybox_tools_test.dart` | the scripts use only what stock's BusyBox has | it reads the scripts as deployed and every string in `lib/`; the check scripts above run them on the router |

## <a name='r10'></a>R10. An AI assistant on the router and in an emulator

Since 30 September 2026 much of this run sheet has been run by Claude Code rather than by hand: on the router itself, and in an Android emulator. What that needs, and what it doesn't.

**The set-up, once.**

- A key pair for the assistant alone, made on the PC with `ssh-keygen -t ed25519 -N ""`. Its public half goes into the router's web interface: Administration, System, Authorized Keys. The assistant logs in with the key, never the router password.
- A settings restore replaces Authorized Keys, which live in NVRAM, so paste the key in again after one. The router's own host key lives in `/jffs/.ssh/` and survives a firmware flash; only a factory reset that formats JFFS replaces it, and then the app refuses the changed key until FORGET ROUTER IP (CON).
- An emulator running the debug build. The person at the keyboard types the router password into it; the assistant never needs it.
- To take the access away, delete the key from Authorized Keys and delete the key files.

**How it runs things.**

- Commands go to the router as `ssh … /bin/sh` with the commands on standard input. Never `sh`: over SSH, stock's PATH finds `/usr/sbin/sh` first, a Broadcom memory tool.
- There is no `scp` on the router, so scripts go across with `ssh … 'cat > /jffs/<file>'`, and the copy is compared by `md5sum`.
- `scripts/check-claims.sh` (`dry`, `quick`, `full`) proves the protection claims on the router, stock and Merlin; `scripts/check-reboot.sh` watches a reboot from a pinned device. Both put back everything they change.
- In the emulator, `adb` installs the build, taps, types and takes screenshots.

**How a run sheet for a person is built.** Every fact is checked against the code or read from the router that day, and anything not checked is marked unverified. The order follows each test's preconditions, with anything destructive last. Every read-only paste block is run on the router first. One copyable block per router step, a `Result:` line under each, and no tables. Anything left to do is a work item, never only a line in a run sheet.
