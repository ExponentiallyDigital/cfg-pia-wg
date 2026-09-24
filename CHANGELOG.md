# 1. CHANGELOG.md

** DO NOT ALTER THE STRUCTURE OF THIS FILE** it is used by GitHub actions workflows.

- [Prefix codes](#prefix-codes)
- [1. Changes](#1-changes)
  - [1.1. Pending to do](#11-pending-to-do)
  - [1.2. WIP](#12-wip)
  - [1.3. Implemented - chronological change history](#13-implemented---chronological-change-history)

---

## Prefix codes

Work items below use these three-letter prefixes.

| Prefix | Meaning |
|---|---|
| ADD | New feature or capability added |
| ARC | Architecture, design or structure notes |
| BLD | Build process or build scripts |
| BUG | Known bug or defect |
| CFG | Configuration change |
| CHG | General change to existing behaviour |
| DEC | Design decision recorded |
| DELETE | Removal of a file, feature, or item |
| DOC | Documentation |
| FIX | Bug fix |
| GUI | User interface change, may altapoear under code UI |
| INF | Informational note, points elsewhere for detail |
| MOD | Code modification or optimisation |
| NOTE | General note |
| REL | Release process or release readiness item |
| SEC | Security related change |
| TST | Test added or updated |
| UI | User interface, element or copy level, may also appear under code GUI|

Bold the first sentence only on multi-sentence items, as a scannable headline. Single-sentence items stay plain.

**Unique IDs**

Every new work item gets an ID. This is the standard from the v0.8.78 build 448 release (and the current Pending/WIP items) onward. It was not applied retrospectively: v0.8.77 build 447 and every earlier release keep their original, ID-free form.

IDs are shared with BACKLOG.md: one number line across both files, so an ID always points to exactly one item no matter which file it lives in.

Format: `ID-NNN XXX:`, where `XXX` is the item's prefix code, placed at the start of the bullet before the prefix.

Example:

- ID-014 FIX: the watchdog passes a tunnel that handshakes but cannot resolve names...

To assign a new ID, search **both** CHANGELOG.md and BACKLOG.md for the highest existing `ID-NNN` and use the next number. No separate counter or log to maintain, and nothing already in either file needs to be touched or renumbered.

When adding several items in one sitting, look up the highest existing ID once, then increment by one for each new item in that batch.

---

 [BACKLOG.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/BACKLOG.md) contains work items that are longer term and yet to be release prioritised. Unverified bugs live in BACKLOG.md, never in this file.

---

## 1. Changes

This file contains lists of work items in a specific and purposeful relative sequence. All work items are sequenced in descending relative importance, this portrays the intended implementation sequence. The exception is "1.3. Implemented": each release block lists its completed work items in chronological implementation sequence, oldest first, so the most recently completed item is at the bottom of its block.

1. work items listed under "1.1. Pending to do" are planned for the **next** release.
2. "1.2. WIP" lists work items that are being actively worked on for the **current** release; and
3. "1.3. Implemented - the chronological change history" which lists, in sequence, every release and its work items.

---

### 1.1. Pending to do

Work items for the **next** release:

**Work items in section 1.1 may not have been sequenced, review and agree sequencing before moving any items from here to section 1.2**

`<none>`

---

### 1.2. WIP

Work items for the **current** release:

`<none>`

---

### 1.3. Implemented - chronological change history

This section contains, in chronological order, all **completed** work items that are ready for the **current** release, or have been **committed** to a release. Each block commences with a header that contains the date that work commenced, the version and build number, followed by a very brief summary in one sentence or less describing what that release contains. Following the header are **completed** work items.

Every release committed to GitHub **must** contain the version formatted as "vN.N.NN" and build number formatted as "build NNN", a dash and the brief summary, then a new line and all completed work items in chronological implementation sequence.

When a work item in "1.2. WIP" is completed, move it to the bottom of the current release block below, keeping its ID.

Every commit is a build. Whoever commits follows these steps, in this order:

1. **Before the commit**, replace `in progress` in the current release block's header with a short summary of what the block contains, one sentence or less. The commit subject is `vN.N.NN build NNN - <that summary>`, word for word. Never commit a header that still reads `in progress`.
2. **Straight after the commit**, open the next release block in "1.3. Implemented - chronological change history": a new header line above the current one, reading `<today's date> vN.N.NN build NNN - in progress` with the build number one higher, and bump `version:` in `pubspec.yaml` to match, both halves. Do not commit the new block and the bump on their own: they wait for the next commit.

2026-09-24 v0.8.91 build 461 - the guard proven on a real router, and tests that pass from any shell

- ID-216 TST: **the guard's shell tests pass from PowerShell too, so `scripts/build.ps1` builds again.** They ran the real guard script under Git's `sh`, but a run started from PowerShell or cmd found `C:\Windows\System32\sort.exe` ahead of Git's `sort` on the PATH. Windows' `sort` rejects `-u` and `-k` and prints nothing, so every rule the script had added read back as missing and five tests failed. The test now puts the shell's own `/usr/bin` ahead of everything but its stand-ins. The router and GitHub's Linux runners were never affected: `sort` there is always the Unix one.
- REL: updaded pinned GitHub Actions
- ID-213 FIX: **a device pinned to a tunnel now gets that tunnel or nothing.** Measured 2026-09-24: a tunnel whose server stops answering already blocked its devices, but a watchdog rebuild let one reply out through the default connection, and DISABLE let a pinned device out for as long as the tunnel was off - in the clear when the default is Internet. Neither a blackhole route (the firmware rebuilds the slot's table on every restart, and the copied WAN default beats it) nor a firewall rule (`restart_vpnc` rebuilds the FORWARD chain) survives; rules do. So each pinned device gets two, `90: lookup <table> suppress_prefixlength 0` and `91: blackhole`, kept by one script, `/jffs/cfg-pia-wg/guard.sh` (`lib/fail_closed_guard.dart`), that reconciles them from `vpnc_dev_policy_list` under a lock. It runs after APPLY, before DISABLE, after DELETE moves devices to Internet, on every watchdog check, at boot from `S50downloadmaster`, and on UPDATE WATCHDOG VERSION; UNINSTALL clears it first. The stale-rule sweep is confined to priority 100 and names it in every delete, or it would have taken the guard's rule at 90 for a duplicate. DISABLE's confirmation names the pinned devices in amber (Andrew's decision: blocked until the slot is enabled or they are moved), and DEVICE ASSIGNMENT's notes and APPLY warnings say "no internet until it is enabled" where they said the device would use the default connection. Twelve behavioural tests run the real guard script under a shell against stand-ins for `nvram` and `ip` - the first router-side shell in the repo tested by running it. ARCHITECTURE 6.8.10 rewritten from the measurements; TESTING.md gains group GRD and five tests that described the old fall-through are corrected. README 5.4.2 and the email section rewritten, text approved by Andrew. **Hardware check passed 2026-09-24** (`runsheet_2026-09-24_guard-check.md`, run 3, on a freshly reset router, wgc1 NZ and wgc5 UK so every path had its own ping time): the guard came back one second after the WAN on a reboot; a rebuild, a DISABLE and both tunnels stopped in the web interface all blocked DESKTOP; an APPLY and a web-interface move each re-aimed the guard; a pin to Internet carried no guard; DISABLE named the pinned device in amber. 537 ping replies, every one from a tunnel, none from the ISP. Two things fixed on the way: the check for an existing guard file no longer logs a failed command on a router that has never had one, and TESTING.md's four `logread` commands read `/tmp/syslog.log` instead - stock has no `logread`. ARCHITECTURE 6.8.10 now records the boot window, and corrects an earlier claim that a ping's TTL separates PIA from the ISP: a UK server answered with the same TTL as the ISP did.

2026-09-23 v0.8.90 build 460 - a pinned device gets its tunnel or nothing

- DOC: fixed typo in ARCHITECTURE.md.
- DOC: removed extra section break from ARCHITECTURE.md.
- ID-152 CHG: CLOSED - won't implement. Original ask: quote 12 router-log lines in a failed-alert email instead of 10, so it includes "SMTP host resolved privately to..." and "Alert email sent (FAILED)", and include the `logger` test marker that was missing from one. A line count cannot do either. The email quotes the watchdog's own log file, `/tmp/watchdog_wgcN.log`, not the syslog, so lines written by anything else - `logger` markers included - never appear in it. And both lines are written after the email has been composed and sent: a FAILED line cannot be inside the email that failed.
- ID-166 GUI: CLOSED - won't implement. Original ask: show `assets\Icon\app_icon_legacy.png` as the splash screen. On Android 12 and later the system splash shows only the launcher icon, masked to a circle, whatever the app asks for; the full image would need a second, in-app splash after the system one.
- ID-160 CHG: CLOSED - replaced by ID-193. Original ask: offset the watchdogs' start times (wgc5 at 0 seconds down to wgc1 at 40) with a sleep, so their router-log lines do not interleave. The harm the interleaving caused was the DNS-probe race, and ID-193 removes it with a `mkdir /tmp/watchdog_dns.lock` mutex and a bounded wait, which delays no check. Watchdogs that run in the same minute will still interleave their log lines.
- ID-161 FIX: CLOSED - answered by ID-193. Original ask: show "Could not aim a lookup at 9.9.9.9 through wgc1; skipping the name check" in red, after discussing why it happens on a tunnel that looks healthy. It is a race between two watchdogs probing the same address in the same second, not a fault in either tunnel, so it stays lavender; ID-193 removes the race.
- ID-159 FIX: CLOSED - covered by ID-192, ID-193 and ID-169. Original ask: with the router on Cloudflare and Quad9 on several slots, 2026-09-21 logged "no answer from 9.9.9.9; one more and it counts as broken" and "Could not aim a lookup" on tunnels that were working, and doubled the prefix as "wgc1: wgc1:". The misses are ID-169 and ID-192, "Could not aim" is the race in ID-193, and the doubled prefix is fixed with ID-193.
- ID-164 FIX: CLOSED - duplicate of ID-144, which now carries it. Original ask: the "also used for DNS on this router" warning appears for Quad9 on wgc1 when the router uses Cloudflare and only wgc5 uses Quad9.
- ID-180 FIX: CLOSED - merged into ID-155, which now carries it. Original ask: credentials are not auto-filled or saved when logging in to the router from the links in ABOUT, and are not cached there either.
- ID-154 FIX: **every log line and warning now names a device the way DEVICE ASSIGNMENT does.** DELETE's "Moving N devices to Internet" read names from `custom_clientlist` alone, so any device the user had not renamed in the web interface came out as a bare address while the screen named it (DEV-15, 2026-09-21). The five device sources the screen joins are now one shared command and parser, `kDeviceSourcesCommand` and `parseDeviceSources` in `lib/device_assignment.dart`, and the DELETE log and the new DISABLE warning both read through them.
- ID-198 FIX: **the alert email no longer says pinned devices fell through to the default connection.** They did not: BRK-1 on 2026-09-20 had TABLET with no internet during the outage while the SUCCESS email said its traffic had gone to wgc5. The stock kill-switch line now reports the guard as the router actually holds it - counting the pinned devices and the guard's rules for this tunnel - in one of three forms: nothing pinned; the guard kept the N pinned devices off the internet; or the guard covers only some of them, and how to put it back. When the tunnel is also the default connection it adds that devices only following the default are not covered.
- ID-191 GUI: **DEVICE ASSIGNMENT no longer says a watchdog will report a default-connection change as an outage.** The restart takes seconds, so a watchdog reports it only if its check happens to land inside them. The warning now says the tunnels stop and restart and anything using them loses its connection for about a minute; ARCHITECTURE 6.8.8 says the same.
- ID-150 FIX: **a watchdog DELETE removes `wgcN_wd_doh_ip` and `wgcN_wd_doh_url` too.** DELETE kept its own list of the slot's watchdog keys, and when 454 added the two DoH ones only UNINSTALL's list was updated (MAN-14, 2026-09-19). Both now use one list, `kWatchdogSlotNvramFields`, so the next key added cannot be missed by one of them.
- ID-175 FIX: **`scripts/clearall.sh` resets what a factory-fresh router has.** It now sets `vpnc_max_conn=2`, unsets `cfg_pia_wg_max_conn_prev` and both DoH keys on every slot, removes the fail-closed guard's rules and script before anything else, and clears the DNS probe's strike files. A stray `\n` that had split one of its `rm` lines is gone.
- ID-215 DOC: **the app now says which routing rules it touches, and why.** README 5.4 gains a short answer to "what does it change on my router?", text approved by Andrew, and ARCHITECTURE 6.8.12 lists every rule on the router by priority - who makes it, what the app does to it and why - with the six hardware tests behind the table, from the 2026-09-08 probes to the 2026-09-24 fail-closed runsheets. It also records, for the first time outside CHANGELOG, that the firmware re-adds a rule for every policy record each time it applies them (ID-183).

2026-09-22 v0.8.89 build 459 - narrative that's as beautiful as the code

- ID-181 DOC: pre-emptive updates to README in expectant anticipation of a release of this fully reworked app, resplendent in its new menu and UI scheme. Yes, I've been writing too much lately. Fine tuned image sizes.
- ID-019 DOC: Updated `README.md` screenshots.
- ID-020 DOC: Updated `README.md` [5. Using the app](https://github.com/ExponentiallyDigital/cfg-pia-wg#5-using-the-app).
- ID-022 DOC: Update Play Store screenshots
- ID-183 FIX: **device routing rules piled up, one more copy per device per APPLY.** Found on hardware 2026-09-22: `ip rule show` carried four copies of one device's rule and three of every other device's, and a reboot - which rebuilds the list from scratch - left exactly one each. The cause is that `restart_vpnc_dev_policy` reinstalls a rule for EVERY record in `vpnc_dev_policy_list` each time it runs, while the sweep that clears stale rules only ever looked at the devices the current apply had changed. Everything it did not look at gained a duplicate. Duplicates that agree are harmless; the moment one does not, the first match wins and the device leaves by a tunnel nobody chose, which is the 2026-09-10 fault the sweep was written to prevent. The sweep now works from the policy list rather than the change set: new `expectedRuleTargets` says what single rule each device should have - its profile index when pinned to a tunnel, `main` when pinned to the internet, and NONE when it follows the default - and everything else at priority 100 for those addresses is deleted. An address the policy list does not mention is still left alone, because a rule the app cannot explain is not one it should remove. Eight new tests, two of them over the shape of the hardware dump; putting the old scoping back fails both service tests.
- ID-184 DOC: ARCHITECTURE's link into README's prerequisites section followed the heading rename, so `markdown_links_test.dart` passes on that one again.
- updated popup wording when a router reboot has been requested - lib\screens\settings_screen.dart.
- ID-185 CFG: **`.gitignore` was hiding every renamed screenshot.** A shorthand `0*` line - added for scratch files like `0.txt` - matched any path starting with a zero, so the whole `00.0-` to `04.02-` screenshot scheme was invisible to git while the old names showed as deleted. Committing that would have broken every image in README at once. The line is gone; the images are tracked.
- ID-186 DOC: **README spelling and grammar pass**, 37 fixes and a re-scan: wrong or missing words, `Absolutly`, `straight forward`, US spellings the rest of the page does not use (`behaviors`, `traveler`, `CloudFlare`), `set up` and `setup` the wrong way round, a semicolon that changes what a sentence claims, and one garbled sentence removed outright at Andrew's request. Two `> [!IMPORTANT]` callouts had their text on the marker's own line, so GitHub rendered them as plain quotes rather than boxes. The stock-firmware line said "from version 0.9"; it now says build 403, 5 September 2026, which is what CHANGELOG shows.
- ID-187 DOC: **five README screenshots, with nothing of the maintainer's network in them.** Three DEVICE ASSIGNMENT screens patched in place - measured box, measured colour, measured font size, so the substitutions sit where the originals did - and the APP LOG and ROUTER LOG screens re-rendered whole, using Flutter's own Material icon font for the app log's four states. Every line is wording the app or the watchdog really emits, taken from a hardware run and re-timed so the two log screens are the same session; the devices are a TV, a tablet, a laptop, a console and a robot vacuum on the default connection, which is what people actually assign. Invented throughout: addresses, MACs, PIA username, PIA servers, mail address, router login.
- ID-188 DOC: CONTEXT gains a working agreement that `README.md` is Andrew's - not edited without an explicit ask, and the proposed text shown before anything is written.

2026-09-20 v0.8.88 build 458 - quality manual testing: full end-to-end regression, all app features tested together as a whole

- ID-139 DOC: fix bullet number in work instruction, BACKLOG.md.
- ID-141 REL: fixed incorrect dates in CHANGELOG on last four builds.
- GUI: updated error message displayed to user when can't connect to router at IP address provided.
- GUI: updated help text in "Install helper programs".
- GUI: altered prompt wording for overwrite warning when creating a slot over an existing slot (`lib\widgets\slot_modal.dart`).
- GUI: in WATCHDOG, altered the wording of DoH prompt explanation text.
- GUI: altered text displayed in the failed email popup error message.
- ID-171 TST: **the run sheet now says what to do, from DEF-5 to the end.** DEF-5 read "change the default, APPLY" and never said what to change it to, which stopped the hardware run. The remaining 53 tests were read the same way - as somebody who knows only what is on the page - and 27 of them were missing the other half. DEF-5 names wgc1 and says why: DEF-6 and DEF-7 both start from it. DEF-6 and DEF-7 now switch the watchdog on wgc1 off first, which is load-bearing, because it would rebuild the tunnel both tests need stopped; DEF-9's rebuild step puts a fresh one back, since ABOUT reads a deployed script. SET-5 said "a third tunnel now enables" at a point in the run where there may be no third slot: it now creates wgc3, watches the cap of 2 refuse it, raises the cap, and deletes what it created. ABT-3 asked for a second build installed over the top and now provokes the amber version row with one `sed` on the script's header line. Every check that reads the router's syslog carries the `logread` command to run, every "exit IP" names the device it belongs to, and the screenshot, aeroplane-mode and password-manager tests say which build and which forms. Same 152 tests, same labels.
- SEC: **router logs pasted into BACKLOG carried the maintainer's own LAN.** Four `dropbear` lines and one reassignment line, added with ID-161 and ID-169, named the router login, two LAN addresses and a device by its real name. Redacted in place to invented values; `test/unit/no_lan_identifiers_test.dart` is what found them, and it passes again.
- SEC: **a PIA username was in BACKLOG too, twice**, in the same pasted logs - spotted by Andrew, not by a test, which is the gap. Replaced with the invented `p123456789`, and `no_lan_identifiers_test.dart` gains a sixth check: `for user ` followed by a letter and a run of digits, anything but the invented one. It matches on shape rather than on the real value, like the MAC and model checks, so nothing real is written into the test. Two sample logs that used `p1234567` - README and a plan - now use the one placeholder, so there is a single invented username across the repo.
- TST: the wording test for the helper-program dialog follows the new copy - "remain unavailable" for "stays unavailable".
- ID-172 FIX: **setting the default connection back to Internet started a VPN the user had switched off.** Found on hardware 2026-09-21, at DEF-8: MANAGE showed wgc1 ACTIVE while the router's own WebUI showed it Disconnected, and DESKTOP, pinned to wgc1, was exiting through NZ on a tunnel that was supposed to be stopped. `vpnc_unit` is a pointer the firmware keeps between calls, and `stop_vpnc` and `restart_vpnc` both act on whatever it names. A switch to Internet has no target row, so `_setDefaultConnection` wrote nothing to it and ran both services anyway; the disable ten minutes earlier had left it on wgc1's row, so the sequence ended by starting wgc1. `restart_vpnc` does not touch the clientlist active flag, which is why the interface, the routes and the DNS rules all came up while VPN Fusion went on reporting the profile as off. Two changes: the teardown now names the OUTGOING default - the tunnel actually being replaced - and `restart_vpnc` runs only when there is a target to start, which is what ARCHITECTURE 6.8.8 already said the Internet case should do. A new test fails against the old code, and the tunnel-to-tunnel sequence is pinned unchanged beside it.

2026-09-19 v0.8.87 build 457 - fix watchdog deployment

- ID-134 DOC: added spacing in README between document title and app asset image.
- ID-136 FIX: **every watchdog deploy failed its own size check, and blamed free space for it.** Found on hardware 2026-09-20, during the end-to-end run: `the router has 37185 bytes of a 37031 byte file ... check free space on the router filesystem`, on a router with 55.5 MB free. The router had MORE than it was sent, not less, and the difference was exactly 154 bytes. The cause was mine, from builds 454 and 455: section-divider comments in the shell script template used the box-drawing dash `─` (U+2500), 77 of them - three bytes each in UTF-8, one each in Dart's `String.length`. The size check has always counted characters while `wc -c` counts bytes; they agree only for plain ASCII, which the script was until then. Four fixes. The expected size is now counted in UTF-8 bytes (`writtenByteCount`), and so is the heredoc chunker's limit, which had the same flaw with more margin. The script template is plain ASCII again. The message now tells a SHORT file (cut off, most likely a dropped connection, space the second thing to check) from a LONG one (part of it arrived twice, which happens when a dropped connection resends a piece) - "check free space" was right for neither case the app has actually met. And the test double's `wc -c` now counts bytes too: it counted characters, the same mistake as the code under test, so it agreed with the bug and 1178 tests passed. New tests pin the script as ASCII on both firmwares, the byte count, the chunk limit in bytes, and the long-file wording; putting the old count back makes the byte test fail with `Expected: 4, Actual: 2`. The rollback from ID-121 worked exactly as designed on its first hardware run: wgc1 was put back as it was and its watchdog stayed scheduled.
- ID-137 BLD: **CI's pinned actions move up a patch release**, still pinned by commit hash: the SonarQube scan 8.2.1 to 8.2.2, and CodeQL's `init` and `upload-sarif` 4.38.0 to 4.38.1. `THIRD-PARTY-NOTICES.md` gains the one licence line the notices tool now finds for `flutter_native_splash`, added as a dev dependency in build 454.

2026-09-19 v0.8.86 build 456 - a run sheet that survives its own tests, and the app's house style written down

- ID-131 TST: **the run sheet survives being run.** Reviewed end to end after eleven tests were added across builds 453 to 455, and five problems came out of it. Three were sequencing: WD and BRK read 23, 24, 25, 20, 22, 21 and 8, 9, 7, 6 because each new test was inserted against an anchor rather than in sequence, and a sheet is worked down the page; MAN-13 and MAN-14 act on a watchdog and sat in a group that runs before any watchdog exists, so they move to the end of WD keeping their labels; and MAN-14 would have deleted a slot that BRK, DEV and DEF all need, so it now names wgc2, which WD-9 builds and nothing later wants. Two were state: WD-12 deletes wgc5 and DEF-9 deletes wgc1, and neither rebuilt what it removed, so every group after them was running against a router that had quietly changed. MAN-8 had the same fault and is older than any of tonight's work - it disabled wgc5 and left it down, with only the optional MAN-11 to bring it back. MAN, WD, BRK, DEV and DEF now each open with the slots they expect going in and coming out, and WD says what each slot is for, because they are not interchangeable. 152 tests, no duplicate labels, nothing renumbered.
- ID-132 DOC: **the app's house style is written down, as ARCHITECTURE section 12.** Every colour with its hex and where it is seen, the per-destination and verb maps, the type scale from 28 down to 9 with what each size is for, buttons and their three roles, inputs, dialogs, badges, the menu and drawer, the three different log colourings, the layout constants, and a cross-reference table naming the file that defines each element and the screens that use it. Every value was read out of `lib/` and the hexes were checked against `app_colors.dart` rather than transcribed. It closes with a section for editing screenshots, which is what prompted it: the app is monospace throughout because the theme sets it, so a same-length replacement occupies the same width, and DroidSansMono is a close enough match to patch an image with. Put in ARCHITECTURE rather than a new root file or `assets/`, which is what ships inside the APK.
- ID-133 DOC: **the Markdown written this session is unwrapped.** CONTEXT line 44 asks for one logical unit per line and no hard wrap at any column, because a reworded sentence in a wrapped paragraph re-flows every line after it. Hard wrapping crept into README's four new sections, ARCHITECTURE's new curl section, two BRK tests, ROUTER-DNS's added intro and `plan_dns-probe.md`, which was wrapped end to end - 155 lines to 108, same words. Found by Andrew in README. The wrapping that predates the rule is untouched and recorded as BACKLOG ID-130: it wants its own commit, touching nothing but line endings.

2026-09-19 v0.8.85 build 455 - a watchdog that asks whether names resolve, not just whether packets move

- ID-078 FIX: **a tunnel that handshakes but resolves nothing is rebuilt, not passed.** The watchdog's checks all asked whether packets moved; none asked whether anything answered a question, which is how devices pinned to `wgc4` went two days without name resolution while the log showed a healthy handshake every five minutes (ID-006). After the cheap checks pass, the script now asks the SLOT's own first DNS server - the one the firmware redirects a pinned device to - for `example.com`, and two consecutive failures count the tunnel as broken. Built to `.claude/plans/plan_dns-probe.md`, from the hardware measurements of 2026-09-19, and three of them shaped it. **The aim is verified before any answer is believed:** a lookup aimed at a STOPPED slot falls through to the WAN and succeeds, so the probe checks `ip route get` names this interface, and skips rather than guesses when it does not. **The wait is built by hand:** `which timeout` finds nothing on the router and BusyBox's `nslookup` takes 20 seconds to give up, so the lookup runs in the background and is killed after six - against a measured 0.5s for a healthy answer and 2.1s for a cold one. **A slot with no DNS is skipped, not failed:** that was the normal state for anything built by the watchdog shortcut until ID-126. The temporary routing rule is removed after the probe, on abort, and swept at the start of the next run by its priority marker. Two consecutive failures, so one lost packet cannot bounce a working tunnel, and the count is cleared by any success.
- ID-006 FIX: **closed by ID-078.** The fault it recorded - a tunnel with a recent handshake whose devices could not resolve names - is what the probe above detects and rebuilds. The half of the original design note that proposed probing the router's own resolver is deliberately NOT built: it would test whichever slot owns the address today rather than this one, which the shared-address case makes unpredictable. The temporary rule is what makes a per-slot question possible instead.
- ID-001 FTR: CLOSED - recorded where it is now depended upon. The firmware routes the router's own lookups to a slot's DNS addresses through that slot's tunnel, lowest routing table first, which is the highest-numbered slot sharing the address. Everything this item asked for is built: ID-075 corrected its rule, ID-005 says when a slot's DNS overlaps the router's own, ID-079 published the whole mechanism as `ROUTER-DNS.md`, and ID-011 removed the overlap on the test router. The behaviour itself is now ARCHITECTURE section 2 row 8, because the app DEPENDS on it rather than merely knowing it - ID-078's probe adds a rule of the same shape and relies on the lowest priority winning. The one loose end it carried, the 2026-09-06 undelivered alert reported as `server misbehaving`, moves to BACKLOG as ID-129 rather than being closed with it (closed 2026-09-20).
- NOTE: **the DNS analysis of 2026-09-17 is finished, across three builds.** It began with Andrew reading that the watchdog resolved names in the clear, having assumed the router encrypted everything when DoT is set and every device is assigned to a slot. Seven items were drafted and sequenced that day, and the order was the point: ID-075 fixed the sentence the rest quoted; ID-076 made the watchdog's own lookups private and everything after it easier; ID-077 finished what ID-076 could not reach; ID-078 was the missing half of ID-006; ID-079 and ID-080 were what the user reads; ID-081 was a decision rather than code. All of it shipped, in that order: ID-075 and ID-080 in build 453, ID-005 with ID-076, ID-077, ID-079, ID-081 and ID-104 in 454, and ID-078 closing ID-006 and ID-001 here in 455. ID-011, Andrew's router test, ran on 2026-09-19 and removed the overlap that started it. Section 1.1 is empty as a result, for the first time since it was created.

2026-09-19 v0.8.84 build 454 - the watchdog stops talking in the clear, and the app stops guessing about DNS

- ID-125 TST: **the run sheet matches build 453.** Twenty-one tests carried expectations the build had just changed. The ones that would have read as failures in the morning: CON-1 and CON-2 still quoted the raw SSH error, BRK-5 typed a wrong PIA password into a form that now refuses it before the router is touched, MAN-11 said to rebuild a stale slot by hand when the failure now offers RECREATE, and ABT-3 named a button that has been relabelled. The rest - CON-5, HOM-2 to HOM-5, WD-16, BRK-1, BRK-3, DEV-2, LOG-3, LOG-4, SET-5, END-1, ABT-4, EXT-5 and BUY-5 - gained the checks the change is worth. Seven new tests cover what had none: HOM-7 (every screen names itself in its menu colour), MAN-13 (DISABLE pauses a watchdog, ENABLE resumes it), MAN-14 (DELETE takes a paused watchdog with it, settling BACKLOG ID-066 in the run sheet too), MAN-15 (slots read wgc5 first, buttons colour-coded), WD-20 (PIA credentials checked before the router is touched), WD-21 (a failed deploy puts the slot back) and EXT-9 (the icon and the splash screen). Labels are unchanged and nothing was renumbered: 136 tests to 144.
- ID-065 FIX: **a paused watchdog keeps the PIA credentials it will need.** `_otherWatchdogsRemain` asked `cru l` whether another slot still had a schedule, and a paused watchdog has none - so deleting the last SCHEDULED watchdog unset the shared `cfg_pia_wg_user` and `cfg_pia_wg_password` under a paused one, whose ENABLE then restored the schedule but not the credentials and whose next reconfigure aborted with "PIA username is not set". It now counts a slot with watchdog SETTINGS as a watchdog, in one extra NVRAM probe. Build 453 made this more likely rather than less: ID-095 turned MANAGE DISABLE into a pause, so paused watchdogs are now a normal state. Found by reading the code 2026-09-15, built 2026-09-19.
- ID-064 FIX: **a WAN outage no longer climbs the watchdog's backoff ladder.** The script incremented the attempt counter, wrote the backoff file and logged `Connectivity lost; reconfiguring (attempt #N)` BEFORE it tested the WAN, which then exited with `no Internet on WAN interface, exiting.` and no alert - so a long outage added a rung every check for attempts that never happened, and a tunnel that could not recover by itself could wait up to 90 minutes for its first real try once the internet came back. The WAN test moves above the backoff block: an outage now exits before the ladder is touched and claims no attempt in the log. Found by reading the code 2026-09-15, built 2026-09-19. Reaches a router on its next deploy or ABOUT's UPDATE WATCHDOG VERSION, as ID-063 and ID-070 do.
- ID-123 FIX: **ACTIVE now means the server answered, not that the device exists.** The badge came from `ip -o link show up`, which is set as soon as an interface exists - and an expired PIA registration leaves one that sends and is never answered, the state that strands the router's own web interface on "connecting". `fetchSlots` reads `wg show all latest-handshakes` alongside the interface list, against the ROUTER's clock, and a slot answered within 300 seconds keeps the teal `● ACTIVE`. One that is up without an answer gets an amber `● UP, NO ANSWER` rather than silently losing its badge (agreed 2026-09-19): a missing badge reads as "not enabled", which would be a new wrong answer in place of the old one. 300 seconds is the watchdog's own window, and every slot this app creates carries `alive=25`, so a healthy tunnel handshakes without any traffic on it. Best-effort: a router that cannot answer the command leaves every up slot reading as answering, which is what the badge did before the distinction existed. From the ID-092 analysis.
- ID-124 FIX: **a stop that leaves the interface up says so on screen.** The original write-up of this was wrong and is corrected here: `disableSlot` and `_revertEnable` have always polled for the interface to go, and always wrote a red line when it did not. What was missing is that the line went only to the app log, while the screen behind it carried on badging the slot as running with nothing to explain why. `disableSlot` now returns whether the interface went, and MANAGE DISABLE turns a false into a plain dialog naming the slot, saying the router accepted the change, and suggesting a reboot if it stays that way. From the ID-092 analysis; the rest of that finding is BACKLOG ID-122, deferred.
- ID-066 BUG: CLOSED - settled by ID-095 in build 453. MANAGE DELETE called `stopWatchdog` only when the watchdog was ACTIVE, so deleting a slot whose watchdog was paused left the script, the schedule settings and the SMTP password on the router; it now runs for a watchdog that is merely configured as well. Covered by TESTING MAN-14 and by `slot_modal_test.dart`. Original ask: MANAGE DELETE on a slot whose watchdog is paused leaves that watchdog on the router, SMTP password included (closed 2026-09-19).
- ID-005 ADD: **the DNS field says when an address is one the router uses for itself.** `fetchSlots` reads `dnspriv_enable` and `dnspriv_rulelist` on stock and carries the result with the slots, and both forms that write a slot's DNS - the CREATE credentials dialog and MANAGE EDIT - compare what is typed against it as it is typed, naming the addresses that actually overlap rather than the whole field. Amber, and information only: sharing an address is Setup B and a reasonable thing to choose deliberately, so the app says what it costs and changes nothing. Silent when DNS Privacy is off, because the list then routes nothing. Measured on hardware 2026-09-19: with both slots on Quad9 the router's own lookups left through wgc5, `ip route get 9.9.9.9` naming the tunnel, which is the state this note describes.
- ID-126 FIX: **a slot built from the WATCHDOG form now gets DNS servers.** Measured on hardware 2026-09-19: neither of Andrew's slots had a `wgcN_dns` key at all, so the firmware added no `iif lo` rules and no `VPN_FUSION` redirect - and a device pinned to such a slot sent its traffic through the tunnel while its NAME LOOKUPS went out over the WAN from the home address. `git log -S` shows the watchdog has never written that key: the form has no DNS field and the script writes twelve keys without it, so only MANAGE CREATE ever set it. The form now carries a DNS field, prefilled with the slot's own value when it has one and the session default when it does not, and the deploy writes `wgcN_dns` when the field has something in it - empty leaves an existing choice alone. Without this, TESTING DEV-10 fails for any slot built by the shortcut.
- ID-128 GUI: **the home screen's chevrons stay teal.** With ID-112 giving each row its own colour, the `>` took that colour too and started reading as part of the label. It means "this opens a screen", which is the same statement on every row, so it keeps the house teal while the icon and label carry the destination's colour. EXIT still has none, and still holds the width so every label starts in the same place. Reported by Andrew 2026-09-19 from the running build.
- ID-076 SEC: **the watchdog looks names up over encrypted DNS.** Its three PIA lookups - the server list, the token, and the CA when it is not cached - went out in the clear, so anyone between the router and its DNS server could see a router asking for PIA. The script now resolves over DoH, and the shape is not the obvious one: measured on hardware 2026-09-19, ASUS's `curl` refuses any URL whose host is an IP literal, silently, with only `Invalid DL URL(1.1.1.2)` in `/jffs/curllst` - so `--doh-url https://1.1.1.2/dns-query` does nothing at all, while a HOSTNAME url works, and a hostname url with `--resolve` supplying the address works while looking nothing up in the clear. That last pair is what shipped, and it is the same shape `addKey` has always used. The watchdog form picks the resolver - Cloudflare's malware filter at `1.1.1.2` by default, Google, Quad9, or your own - and says so when the address chosen is one this slot or the router already uses for DNS, because the firmware would route those lookups into the very tunnel the watchdog exists to repair (ID-001). One retry drops back to plain resolution and logs that it did: a watchdog that cannot rebuild a tunnel is worse than one whose lookups are visible. New keys `wgcN_wd_doh_url` and `wgcN_wd_doh_ip`, removed by the uninstall with the rest.
- ID-077 SEC: **the alert email's hostname is resolved privately too.** The lookup ID-076 could not cover, and the one that actually reveals something: the PIA names say a router talks to PIA, which its WireGuard traffic already says, while the SMTP hostname names the user's email provider and nothing else on the wire does. Neither mailer takes an address and a name separately, so the script learns the address over DoH first - by asking curl to connect and report `%{remote_ip}`, which resolves the encrypted way and works on both firmwares - and then gives it to each mailer the only way it accepts: a temporary `/etc/hosts` entry on stock, so the name is still what the certificate is checked against, and `-connect <ip> -servername <host> -verify_hostname <host>` on Merlin. The entry carries a per-interface marker, is removed after the send, on `abort()`, and at the start of the next run, so a script killed mid-send cannot leave one behind. Certificate verification is unchanged on both firmwares; a failure to resolve privately falls back and says so in the log.
- ID-079 DOC: **the DNS explainer is published, with its three corrections.** Andrew's full write-up is now `ROUTER-DNS.md`, tracked, with the router model removed (CONTEXT), the "first tunnel" rule corrected to the highest-numbered slot (ID-075), and the claim that the app warns about an overlap left standing because ID-005 made it true in this build. README gains a short section, 5.2.2, with the three rules, the pinning recommendation and links through. The source copy in `.claude/testing/` is deleted, so there is one version rather than two that drift.
- ID-104 DOC: **README recommends pinning the devices you care about**, in the new 5.2.2, with the reason rather than the instruction: a pinned device's traffic and its lookups leave from the same place, and nothing else on the router can move them. The placeholder link in the original item is now that section.
- ID-081 INF: **decided, and documented rather than built.** The app resolves PIA's three names through Android's own resolver, so STANDALONE and CREATE are in the clear unless the user has Private DNS on. README 5.2.2 says so and names Private DNS as the answer. Resolving them in Dart over DoH is more code, and more to go wrong, than the exposure justifies - a phone that has already told its network it is talking to PIA by opening the tunnel.
- ID-011 CFG: **the router's own DNS no longer shares an address with any slot.** Andrew's test, run 2026-09-19: the router's DNS Server and its DoT Server List both moved to Cloudflare's malware-filtering pair, with the slots left on Quad9. Confirmed on hardware afterwards - `/etc/resolv.conf` lists the Cloudflare addresses then stubby, `ip route get` for the Cloudflare address names the WAN rather than a tunnel, `9.9.9.9` still names wgc5 because the slots still use it, and the four `iif lo` rules are unchanged. That is Setup A from ROUTER-DNS.md: the router's own lookups, and every unpinned device's, now leave over the internet connection instead of through wgc5, so a tunnel that looks connected and answers nothing can no longer take name resolution away from the house. Settles the wording ID-005 and ID-079 were waiting on.

2026-09-19 v0.8.83 build 453 - one colour scheme, screens that say what went wrong, and a watchdog deploy that cleans up after itself

```play
A new app icon, and a splash screen while the app starts.

Every screen now has a colour of its own, on the menu, in the drawer and at the top of the screen, so you can tell where you are at a glance.

Problems read as sentences, with the detail kept in the app log: "Could not connect to the router at 192.168.1.1".

A watchdog that fails to deploy now puts your VPN slot back as it found it, and checks your PIA login before it changes anything.
```

- ID-112 GUI: **one colour map drives the menu, the drawer, every screen heading and the slot-action buttons.** Main menu rows keep their teal outlines; only the icon and label text change: STANDALONE #00C2B6, MANAGE #29B6F6, WATCHDOG #8BC34A, DEVICE ASSIGNMENT #FFB300, ROUTER LOG #8E5499, APP LOG #6052FF, SETTINGS and ABOUT #8A97A0, EXIT unchanged red. The drawer takes the same colours on its icons and labels, with no outline added, from the same map rather than its own copy. Screen headings follow: ROUTER LOG and APP LOG in the style WATCHDOG CONFIGURATION already uses, and STANDALONE, DEVICE ASSIGNMENT, SETTINGS and ABOUT gain a heading named after the menu item tapped. **Merged 2026-09-18:** ID-114 (WATCHDOG EDIT heading `EDIT wgcN:pia-region` #8BC34A), ID-115 (MANAGE EDIT heading #29B6F6), ID-116 (WATCHDOG LOG heading #8BC34A) and ID-118 (slot-action verbs from the same map: CREATE and CREATE/EDIT #8BC34A, ENABLE #00C2B6, EDIT #29B6F6, DISABLE #FFB300, DELETE unchanged red, VIEW ROUTER WATCHDOG LOG #8A97A0, in both MANAGE and WATCHDOG). Put the map where the app keeps its colours rather than in a new file. **Implemented 2026-09-19:** `kDestinationColours` and `kSlotActionColours` in `app_colors.dart`, read by the menu, the drawer, every heading and the slot buttons. Two decisions worth knowing: STANDALONE and ENABLE use the app's own teal `kHighlight` (#00D4AA) rather than the #00C2B6 in the specification, because the note beside it said "unchanged, still teal" and #00D4AA is what teal has always been here; and the drawer now marks the current screen with a tile fill, since its colour is spoken for. One `ScreenHeading` widget gives every screen the same 12pt spaced capitals, so the two log headings changed from plain 13pt to match the configuration headings.
- ID-117 GUI: **the watchdog log is coloured by outcome.** Error lines red; `Deploy SUCCESS`, `Reconfig SUCCESS` and `Alert email sent (SUCCESS)` teal; other deployment lines amber; everything else, the routine handshake checks included, unchanged. Supersedes ID-083. **Implemented 2026-09-19:** `watchdogLogLineColour` in `slot_modal.dart`, matched on the wording the script itself writes, with the log rendered as one `SelectableText.rich` so COPY and selection are unchanged. "Backing off after N failed attempts" comes out red rather than amber: it carries the word failed, and the tunnel is still down.
- ID-085 CHG: **ABOUT's redeploy button moves up, centres, and reads UPDATE WATCHDOG VERSION.** Mock-up: `.claude/testing/about-screen-mock-up.png`. **Implemented 2026-09-19:** it sits centred on its own line directly above COPY BUILD INFO, in the amber of the `Watchdog script` row it fixes, per the mock-up.
- ID-089 GUI: **centre ABOUT's link row** - ReadMe, Change log, Security policy, Privacy policy, Open source licenses - per the same mock-up.
- ID-110 GUI: **links lose their underline but stay tappable:** the header's "Exponentially Digital" and version number, and ABOUT's link row. **Implemented 2026-09-19:** the prompts INSIDE a sentence keep their underline - "login to router to retrieve" is a link in running text, where the underline is what separates it from the words around it.
- ID-109 GUI: **HOME's two footer lines line up with the menu.** Indent "how to use this app" and "add a Play Store app review" so their icons sit in the same column as the nine menu icons, remove the underline, and colour both icons #BFB27C (muted khaki-gold). They stay tappable. **Implemented 2026-09-19:** `kMenuIconIndent`, 20px: the rows pad by 18 and their icons are 20px against the links' 16px, so the icon CENTRES line up.
- ID-107 GUI: **the home screen sits optically centred on a tall screen.** Today the nine rows, EXIT and the two text lines are top-aligned with every bit of spare height below them. Add a second `Spacer()` above the block so the leftover height is shared, weighted rather than even - flex 1 above and about 1.2 below - because an evenly split block reads slightly low to the eye (agreed 2026-09-19). No device check is needed: `AppScaffold(fillViewport: true)` already forces the body to at least the viewport height, so the spacers take only height that is genuinely spare and collapse to nothing on a phone, where the screen scrolls exactly as it does now. The block centres between the header and the pinned bottom button, which sit outside the scrolling area. Update the comment in `main_menu_screen.dart`, which records the opposite intent - spare height below, so a tall screen does not push the links down. Tests: at tablet height the space above the first row matches the weighting below the last line; at phone height nothing changes.
- ID-090 GUI: **DEVICE ASSIGNMENT's two buttons sit side by side before anything is staged.** With nothing selected they stack vertically and only line up once a change is staged: the label reads APPLY 0 CHANGES, wide enough to wrap the row. **Implemented 2026-09-19:** a Row of two equal halves at the smaller label size, rather than a Wrap that reflows. The pair now holds its row at every width instead of only when a change is staged.
- ID-113 GUI: **the overwrite prompt names the slot in its title.** Title becomes `Overwrite wgcN:pia-region_name?`; the body drops the sentence repeating the slot and region, keeping "Creating a new configuration will overwrite it." and the note that assigned devices stay and follow the new region.
- ID-108 GUI: **connection failures read plainly on screen.** With Wi-Fi off, DEVICE ASSIGNMENT showed a raw `SocketException ... errno = 110`; show "Could not connect to the router at <address>" instead and keep the full text in the app log. Same treatment for the other screens' connect errors. **Implemented 2026-09-19:** `routerConnectMessage` in `router_session.dart` names the failures that mean "could not reach the router" or "refused that login"; everything else keeps its caller's own wording. `AppErrors.system` gained `logDetail`, so the dialog says the plain thing while the app log keeps the raw exception.
- ID-101 GUI: **slots list wgc5 first, down to wgc1**, in MANAGE, WATCHDOG and the DEVICE ASSIGNMENT picker. Display order only, and it matches ID-080: the highest-numbered slot is the one that carries the router's own DNS when addresses are shared. **Implemented 2026-09-19:** the device picker still sorts a RUNNING tunnel above a stopped one, then highest slot first - someone choosing a connection needs to see what is up before anything else.
- ID-102 DOC: **CONTEXT's "three drawer-only screens" sentence is out of date.** Section 2, line 61, still says three screens are drawer-only; every destination is on the main menu as well.
- ID-119 DOC: **CONTEXT tells Claude to write Markdown prose to the voice guide** at `.claude/testing/voice-guide.md`, CONTEXT itself excepted, and a test fails with a clear explanation if that file is ever tracked by git. **Implemented 2026-09-19:** the rule is in CONTEXT section 1, and `test/unit/no_lan_identifiers_test.dart` names the guide on its own - tracking it would do something worse than leak an address.
- ID-075 DOC: **correct ID-001's "first tunnel" to the rule the firmware actually follows.** BACKLOG ID-001 is titled "the router's own DNS follows the first tunnel" while its own body says the `from all to <slot DNS> iif lo lookup <table>` rules match the LOWEST table first. Measured September 2026: the tables run `wgc1` 9, `wgc2` 8, `wgc3` 7, `wgc4` 6, `wgc5` 5, so the lowest table is the HIGHEST-numbered slot, and "first tunnel" reads as the opposite. ID-001 was reproduced with only `wgc1` up, which could not tell the two apart. Fix the wording in ID-001 and everywhere it was repeated - CHANGELOG ID-005 and ID-006 both say "first tunnel". Cheap, and ID-079, ID-080 and ID-104 all quote this rule. In ID-061's scope. **Implemented 2026-09-19:** ID-001's title, its body, ID-005 and ID-006. The one place left is a closed release note from build 4xx, which is history and stays as written.
- ID-080 DOC: **recommend the highest-numbered slot as the "home" slot, and say why.** Among slots sharing a DNS address the lowest table wins, which is the highest slot number (ID-075), so the router's own DNS-over-TLS lookups leave through `wgc5` when it shares those addresses. It also matches what a new user sees, since the router's own web interface creates `wgc5` first. Two cautions to carry into the wording: whichever slot carries the router's lookups carries the whole LAN's, so an ID-006 failure there takes names away from everything unpinned; and moving a region between slots means creating the new slot and moving pinned devices BEFORE deleting the old one, because deleting a slot sends its devices to Internet rather than to the default connection (TESTING DEV-15). Pairs with ID-101, which lists slots wgc5 first. **Implemented 2026-09-19:** README 5.2.1, "Which slot should carry your main VPN?", with both cautions and the create-move-delete order.
- ID-086 DOC: **README section 2 Features lists device assignment**, with the list resequenced: watchdog first, device assignment second, then the rest. **Implemented 2026-09-19:** watchdog first, its email alerts with it, then device assignment, then the rest.
- ID-087 DOC: **README's text under the table of contents follows the same order:** watchdog, then device assignment, then the rest.
- ID-088 DOC: **README section 1 says what device assignment is for**, in a sentence or two about the benefit.
- ID-103 DOC: **README notes that the router expires SSH sessions aggressively**, so extra logins appear in the router log; the app reconnects transparently.
- ID-105 DOC: **README, DEVICE ASSIGNMENT: a section on phones and per-network MAC randomisation.** Why it matters: a rotating MAC makes an assignment stop applying, so that device leaves by the default connection. iOS 27: Settings > Wi-Fi > the network > Private Wi-Fi Address, off, which is per network. Android on Pixel: Settings > Network & internet > Internet > gear > Privacy > "Use device MAC", also per network. Android can also rotate on its own when Developer options has "Wi-Fi non-persistent MAC randomisation" on (at reboot or lease expiry), and without Developer options when an app asks through the network suggestion API or on an open network with no captive portal. **Implemented 2026-09-19:** README 5.4.1, with the per-network settings for iOS and Pixel and the two ways an Android phone rotates on its own.
- ID-106 DOC: **README, DEVICE ASSIGNMENT: a note that the device list comes from the router's firmware** and can lag - a device may read offline until it sends traffic, and a "ghost" entry can linger, particularly with a random MAC. Links to ID-105's section. **Implemented 2026-09-19:** README 5.4.2.
- ID-082 TST: **TESTING says up front which licence state a run needs.** The locked and buying sections need a store build on a testing track; everything else does not.
- ID-091 CHG: **RESTORE PURCHASE says what actually happened.** It reports "Purchase restored. Everything is unlocked." even when the app was already licensed. Wanted: an already-licensed message; a restored message only when the state changes; and on failure a plain-English popup with the detail in the app log. **Implemented 2026-09-19:** the state before the store is asked decides the wording, so "restored" is said only when something changed. A store that cannot be reached is a popup rather than a snack bar, with its own words kept in the app log.
- ID-097 GUI: **no missing-binaries error after a successful install.** On a fresh install following UNINSTALL, licensed, entering WATCHDOG offered `jq` and `mailsend-go`, both installed, and the app log still carried the red "Unable to locate" notice naming `/jffs/cfg-pia-wg/jq`. **Implemented 2026-09-19:** a failed install no longer shows the manual-install notice on top of its own error - one failure, one message - and a successful install now logs a line saying the router has what the screen needs, so the log does not end on the red notice from before it.
- ID-098 FIX: **uninstall puts the maximum active VPNs back to 2** if the app raised it. **Implemented 2026-09-19:** `setMaxActiveVpns` records what the router had in `cfg_pia_wg_max_conn_prev` before it first raises the cap, and the uninstall puts that value back. A cap the user raised themselves is left alone: this undoes the app's change, it does not impose a default.
- ID-084 FIX: **an SSH reconnect is not always written to the app log.** Seen 2026-09-16 after activity on ABOUT: the router log recorded a fresh password auth with no matching "Router SSH connection dropped; reconnecting." line in the app log, while a later reconnect that day did log one. **Implemented 2026-09-19:** `RouterSession` logs "Router SSH connection re-established." for every connection after the first. The drop-and-retry path already announced itself; a session the app closed on its own - the background grace expiring - did not, which is the case that produced a dropbear login the app log could not account for.
- ID-095 FIX: **DISABLE pauses a watchdog, DELETE removes it, and both say so.** MANAGE DISABLE currently tears the whole watchdog down - schedule, script and settings - while its dialog says only "stops its watchdog". Agreed 2026-09-18: DISABLE takes the slot down and pauses its watchdog, keeping the settings and script so ENABLE restores it; DELETE removes the watchdog and the slot together, after a popup that says so and is accepted. Settles the other half of ID-066. **Implemented 2026-09-19:** MANAGE DISABLE calls `disableWatchdog` (schedule off, settings and script kept), MANAGE ENABLE puts a paused schedule back with the tunnel, and DELETE names both and removes both - including for a watchdog that was only paused, which settles the MANAGE half of BACKLOG ID-066. It also keeps the MANAGE path clear of BACKLOG ID-065, since pausing no longer touches the PIA credentials.
- ID-094 GUI: **offer RECREATE when an enable fails because the server never answered.** Add a house-colour button to that popup which runs the CREATE flow for the slot - PIA credentials dialog, DNS choice, then the usual build - for a configuration whose PIA registration has gone stale. **Implemented 2026-09-19:** offered for all three enable failures - the interface never came up, it came up with no handshake, or nothing answered through it. A write that failed or a refused service call keeps the plain dialog.
- ID-099 GUI: **the router log loses your place when older pages load quickly.** Scrolling back many screens in quick succession, fetching the next segment jumped the view down by several screens: it neither returned to the newest lines nor held position. **Implemented 2026-09-19:** two fixes. The scroll position is anchored to the BOTTOM of the content, so whatever appears above the reader - the page, the spinner that was showing while it loaded - the distance from the newest line is kept; and the re-entrancy guard is now set before the first await, so a fast flick cannot start two loads that each correct the offset for their own insertion.
- ID-111 GUI: **new launcher icon and a native splash screen.** `flutter_launcher_icons` takes `image_path: assets/icon/app_icon_legacy.png`, `adaptive_icon_background: "#001620"` and `adaptive_icon_foreground: assets/icon/app_icon_foreground.png`, keeping its other settings. Add `flutter_native_splash` as a dev dependency with `color: "#001620"`, `image: assets/icon/splash_detail.png`, android and ios true, and an android_12 block using the foreground image with `icon_background_color: "#001620"`. Declare `assets/icon` under flutter assets if it is not already, regenerate with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`, and update `build.ps1` and `build.sh` to run both. The three new assets are tracked as of 2026-09-18 and the old icon files are removed; nothing but pubspec and the generated platform files changes. **Implemented 2026-09-19:** regenerated with both tools, `assets/icon/` declared, and README's heading image repointed at `app_icon_legacy.png` - it still named the icon that was deleted with the old set.
- ID-063 FIX: **a rebuild counts as a success only when the server answers.** After restarting the slot the script's only test is `ip -o link show up`, so it logs `Reconfig SUCCESS`, counts `cfg_pia_wg_reconfig_ok` and emails SUCCESS even when no handshake ever completes - the log, the lifetime counters and the alert all say recovered at once. Poll `wg show <iface> latest-handshakes` every 2 seconds for up to 20 seconds after the restart, and only then call it success. Measured 2026-09-19 from four days of router syslog: of nine rebuilds, four already had a completed handshake about 4 seconds after the restart, before the script logged success; the larger figures in that log come from the next scheduled check and reflect WireGuard rekeying, not the first handshake. 20 seconds is double what the app's own ENABLE allows, which polls every 2 seconds five times; otherwise abort with its own message and let the existing backoff, alert and counters treat it as the failure it is. Found by reading the code 2026-09-15; scheduled 2026-09-19 with ID-070, which it also settles. Expect this to surface failures that were previously silent, which is the point: TESTING BRK-1 and BRK-3 currently have to be confirmed by hand from the NEXT check. **Implemented 2026-09-19:** the gate polls `wg show <iface> latest-handshakes` every 2 seconds for up to 20, between the interface check and the success lines, and aborts with its own message otherwise - so the existing backoff, alert and counters treat it as the failure it is. The script size guard moves 28160 -> 29696 to carry this and ID-070.
- ID-070 FIX: **the watchdog script restarts a stock tunnel the way the app does.** Its reconfigure calls `stop_wgc`, `start_wgc` and `restart_vpnrouting0` on both firmwares, while the app's own enable and disable use VPN Fusion on stock - `nvram set vpnc_unit=<row>` then `restart_vpnc` or `stop_vpnc`. CONTEXT claimed the Merlin commands are inert on stock, which is now flagged unproven: the one stock log of a rebuild was taken while the router's service queue was stuck, and "interface up" proved little on its own (ID-063). Use the app's stock path in the script, so a rebuild on stock restarts the tunnel it rewrote. Scheduled 2026-09-19 alongside ID-063: with the handshake gate in place, a stock rebuild that does not truly restart will now say so instead of reporting success. Settles the CONTEXT flag either way. **Implemented 2026-09-19:** the script resolves `vpnc_unit` from `vpnc_clientlist` the same way the app does - the row index, in awk - then `restart_vpnc`. A slot with no row falls back to the interface commands rather than poking a unit that does not exist. Merlin is untouched. The CONTEXT "inert on stock" flag goes: with ID-063 in place, a stock rebuild that does not truly restart now says so.
- ID-120 ADD: **check PIA credentials with PIA before writing them to the router.** A deploy on 2026-09-17 carried the router's SSH username as the PIA account and only failed minutes later, in a FAILED alert email (ID-096). The app already fetches a PIA token for STANDALONE, so SAVE & DEPLOY can do the same with the credentials entered and stop with "PIA rejected these credentials" before touching the router. Turn 401 and 403 from the token endpoint into that plain-English message wherever it surfaces - the app, the app log and the alert email - instead of `exit 0, HTTP 403, body 66B: {`. Deliberately NOT a format check on the username: PIA's account naming is theirs to change. Checked 2026-09-19: the PIA, SMTP and router fields already sit in separate `AutofillGroup`s, which is correct, but every field uses the generic `AutofillHints.username` / `.password` and Android has no per-service hint, so a password manager can still offer the router login in the PIA field. A group decides what is saved together, not what is offered, so asking PIA is the guard that actually works. **Implemented 2026-09-19:** SAVE & DEPLOY asks PIA for a token with the credentials on the form before a single NVRAM key is written. Only a REFUSAL stops the save: PIA being unreachable from the phone says nothing about the credentials, so that logs a warning and carries on, and the router does its own asking. The script says the same thing about a 401 or 403 instead of `exit 0, HTTP 403, body 66B: {`.
- ID-121 FIX: **a watchdog deploy that fails puts the slot back as it found it, and says what it did.** MANAGE CREATE is already transactional: a failed write restores the previous configuration, or clears the slot back to empty when it started empty. The watchdog deploy is not. It writes the slot keys, upserts the profile row, sets the slot enabled and adds the cron entries BEFORE running the script, and a region change blanks `priv`, `ppub` and `ep_addr` first, so an abort leaves a slot that the app reads as configured while the router's own web interface shows nothing (ID-096). Make the deploy roll back on failure the way CREATE does, restoring a previous configuration or clearing an empty slot, so both views agree. Two considerations. **Keep the schedule:** the cron entries are what finished the build after a reboot on 2026-09-17, so removing them as well would take away the retry that rescued it; roll the slot back and leave the watchdog scheduled. **Say what happened:** the failure message should name the cause and state what was undone, for example "PIA rejected these credentials; wgcN was left as it was and its watchdog will retry in N minutes", in the app, the app log and the alert email. Related: ID-063, because a rebuild currently reports success on an interface that merely came up. **Implemented 2026-09-19:** `_snapshotSlot` before anything is written, `_restoreSlot` on any failure, and a message that names the cause and what was undone. The schedule and the watchdog settings are deliberately kept, because the scheduled check is what finished the build after a reboot on 2026-09-17.
- ID-096 BUG: **a watchdog deploy that fails part way leaves the slot looking configured while the router shows nothing.** Reported 2026-09-17 from an empty router: creating a slot through WATCHDOG failed, the WebUI showed no slot, the app showed it configured but not active, and after a reboot the scheduled check finished the build. Diagnosed 2026-09-18 from the syslog: the deploy asked PIA for a token using the router's SSH username rather than the PIA account, and PIA answered HTTP 403. Nothing in the app copies one to the other, but the PIA username field carries the same autofill hint as the router login, so a password manager can fill it - ID-120. The deploy aborted after the rebuild had already blanked the slot's keys and set it enabled, which is the state the app reported. **Andrew, 2026-09-18:** when a watchdog-created slot fails part way, the app's status for that slot should match what the router's own web interface shows - not configured. **Settled 2026-09-19 by ID-120 and ID-121:** the credentials are checked before the router is touched, and a deploy that fails anyway puts the slot back - so there is no half-built slot left for the app and the router's web interface to disagree about.
- ID-092 FIX: **MANAGE can show ACTIVE for a slot that is not up.** Analyse every path that can produce it - the badge comes from `wg show interfaces` when the list is read, so a stale read, a tunnel dropping after the read, and an enable that failed with the flag left set are all candidates - and write the findings into BACKLOG section 2 as new items. No code changes unless they overlap work already scheduled for this build. Two earlier fixes are behind it: `activeSlots` replacing a single-slot badge, and a badge that stayed after DISABLE. **Analysed 2026-09-19, no code changes:** three paths can badge a slot that is not carrying traffic, and they are BACKLOG ID-122 (nothing refreshes the badge after the one read), ID-123 ("up" is the link flag, not a handshake) and ID-124 (nothing verifies that a disable or a revert actually took the interface down). Two non-faults are recorded there as well, so they are not re-investigated: a WireGuard server interface is `wgs1` and cannot badge a client slot, and a tunnel enabled in the router's own web interface badges here by design.

2026-09-15 v0.8.82 build 452 - a clean-router test baseline, cached Gradle, and a backlog triaged into one build

- ID-073 DOC: **a full end-to-end test starts from a router with nothing left over.** Testing documentation updated to enable repeatable and high quality e2e testing to occur. New first step in TESTING.md, PRE-5: reload the baseline settings file taken straight after a factory reset (which also wipes `/jffs`), reformat the USB drive and reinstall Download Master, then confirm there is no app state in `/jffs`, NVRAM, `cru` or `/opt/etc/init.d`. A settings reload alone restores NVRAM only, and the USB drive keeps the app's `S50downloadmaster` block and backups from earlier runs. Download Master has to be reinstalled after the format, because on stock the watchdog's boot persistence lives in its init scripts and SAVE & DEPLOY refuses without them. PRE-1 remains for runs that do not reload the baseline.
- ID-074 BLD: **CI keeps Gradle between runs, so a release no longer depends on downloading it again.** Build 451's release run failed on 2026-09-15 when GitHub returned HTTP 500 for `gradle-9.1.0-all.zip`: the wrapper's `services.gradle.org` address hands the download to GitHub's release storage, and no job cached Gradle, so every job fetched the distribution and every dependency afresh. The three jobs that run Gradle now set `cache: gradle` on their `actions/setup-java` step: `release` in `release.yml`, and `build-debug` and `codeql` in `quality_and_security.yml`. The `quality` job, which runs `flutter analyze` and `flutter test` but never Gradle, is left alone. setup-java caches the wrapper distribution separately, keyed on `gradle-wrapper.properties` only, so it survives dependency changes. The dependency cache's key is set with `cache-dependency-path` to the Gradle build files, `gradle.properties`, the wrapper properties and the three `gradle.lockfile`s: setup-java's default key misses the lockfiles, so a lockfile-only change would otherwise have reused a stale cache. A restored cache changes nothing about what resolves: STRICT dependency locking still fails any build whose dependencies differ from the lockfiles. The job order is unchanged: every check still waits for the OSV scan, and the release still waits for every check. Not yet seen in CI: the first run after this writes the caches, and the one after that should log a cache hit for Gradle, the wrapper and the JDK.
- ID-083 GUI: CLOSED - duplicate of ID-117, which specifies the same WATCHDOG LOG colouring in more detail. Original ask: WATCHDOG LOG - colorise watchdog log errors in red, reconfigured in amber, normal operations in green.... (closed 2026-09-18).
- ID-093 FIX: CLOSED - firmware noise, not the app. The `pktrunner` kernel line accompanies `stop_vpnc` on this platform and appears whoever issues it; nothing in the app can prevent or suppress it. Original ask: this may not need a code fix - when an enabled slot was disabled, a kernel error was reported by pktrunner:... (closed 2026-09-18).
- ID-100 DOC: CLOSED - the TESTING rewrite (ID-071) removed the old section 7, and the one remaining `scp` mention is in the reference section, about copying the helper scripts to the router. Original ask: TESTING section 7, correction required: there is no scp, instead suggest that they use SSH with vi and clipboard copy and paste.... (closed 2026-09-18).
- ID-114 GUI: CLOSED - merged into ID-112, which now carries it. Original ask: when a user edits a WATCHDOG slot, alter the colour of the heading text "EDIT wgcN:pia-region_name" from teal to #8BC34A (green).... (closed 2026-09-18).
- ID-115 GUI: CLOSED - merged into ID-112, which now carries it. Original ask: when a user edits a MANAGE CONFIGURATION slot, alter the colour of the heading text "EDIT wgcN:pia-region_name" from teal to #29B6F6 (sky blue).... (closed 2026-09-18).
- ID-116 GUI: CLOSED - merged into ID-112, which now carries it. Original ask: when a user views a WATCHDOG log, alter the colour of the heading which says "WATCHDOG LOG - wgcN:pia-region_name" from teal to #8BC34A (green).... (closed 2026-09-18).
- ID-118 GUI: CLOSED - merged into ID-112, which now carries it. Original ask:  I want to establish a consistent "action verb colour" scheme for the button text used across two slot-action menus: MANAGE and... (closed 2026-09-18).

2026-09-15 v0.8.81 build 451 - a release that checks its own tag, and a test run sheet you can follow

- ID-060 DOC: **CONTEXT and ARCHITECTURE describe what the watchdog code does today.** The watchdog works correctly and several statements about it did not match the code, which a later change could have "fixed" the code to fit. The script lives in `/jffs/cfg-pia-wg`, not `/jffs/scripts`: CONTEXT's deploy order and its stock table said otherwise, and stock's deploy makes that directory. The deploy order and `stopWatchdog` described only Merlin's `services-start`; stock rewrites `S50downloadmaster`. "Watchdog ACTIVE means" and "Watchdog script path" sat in the table of stock differences, one of them missing a cell, though both are the same on both firmwares; they are now a paragraph under it. ARCHITECTURE and CONTEXT said `restart_vpnc` clears `wgcN_enable`, but the watchdog script's stand-down, `getWatchdogStatus` and the watchdog screen's SAVE all need it to stay `1` after an enable. Measured on stock 2026-09-15: `1` on all five slots, all enabled, with watchdogs on wgc1 and wgc5. CONTEXT now names those three readers and says not to change them without a hardware test. The rule against sending an escaped `\$kConstant` to the router moved to the working agreements, and two CONTEXT table cells with a `|` inside code now show in full; three Markdown style warnings in CONTEXT are fixed. No code changed.
- ID-062 FIX: **a release stops within seconds when its tag does not match `pubspec.yaml`.** PR #20's merge commit was build 450 (`0.8.80+450`) and was tagged `v0.8.78`. The release workflow took the release name and the Play version code from `pubspec.yaml` and everything else from the tag, and nothing compared the two: build 450 reached the internal track correctly, but the GitHub release "v0.8.80 (build 450)" sat on tag `v0.8.78`, carried only build 448's notes, and had its SBOM and licence files named for v0.8.78. `release.yml` now starts with a `version-check` job that reads `pubspec.yaml` at the commit being released and fails unless the tag is `v` followed by that version, before the Quality & security checks, the build or the Play upload start. A manual run is held to the same rule through its `tag_name`. The error names the tag to use and how to delete the wrong one. `BUILDING.md` gains how to tag a release.
- ID-069 DOC: **CONTEXT describes the app as it is today in eight more places.** Found 2026-09-15 while reviewing TESTING.md against the code, each checked against the code before it was changed: watchdog mode has ENABLE and DISABLE buttons, which act on the schedule and keep the script, settings and tunnel, and VIEW ROUTER WATCHDOG LOG stays available while a watchdog is paused (it said there were no such buttons and the log needed an active watchdog); the router session closes after five minutes in the background, not the moment the app is paused (two places); FORGET ROUTER IP is on SETTINGS, not ABOUT; the router address is remembered from every screen that asks for router credentials, not two; the watchdog SAVE no longer enables the slot a second time after deploying, and is also blocked on stock when the Download Master boot directory is missing; a stock user with a helper binary missing is offered an install before any notice, and a locked user is never checked; and a store build is locked until the store confirms a purchase, with REDEPLOY and MAX ACTIVE VPNS gated as well (it said entitlement returns true today). The stock table's "The Merlin commands are inert on stock" is now flagged as unproven: the watchdog script's own reconfigure still calls `start_wgc` on stock, and the only hardware evidence was logged while the router's service queue was stuck. Tracked as BACKLOG ID-070.
- ID-071 DOC: **TESTING.md is a run sheet you can follow without losing your place, with the reference moved to the end.** It had grown to a thousand lines mixing tests with SSH recipes, background and fault history, in several visual styles, and the watchdog section in particular was hard to follow. Part 1 is now a run sheet in the order a full test walks through the app: short Do / See / Pass if bullets under labels that never change, such as `MAN-3`, a blank line between tests, and no tables. Part 2 keeps the reference: what to check first when something looks broken, how the watchdog decides a tunnel is broken, the backoff ladder, what the watchdog leaves on the router, device assignment notes, sending email by hand, examining NVRAM, and store testing notes. Reviewed on 2026-09-15 against every use case in the code, it gains tests for: the stock helper-program install; Standalone validation and a wrong PIA password; ENABLE's check-target prompt and an ENABLE that fails; watchdog form validation, a failed test email, pause and resume, two watchdogs, and SAVE refused without jq; a tunnel turned off in the WebUI being left alone; several devices in one APPLY, a conflicting WebUI change, staged changes surviving, offline and random MAC devices, and DNS through the tunnel; the default connection moving tunnel to tunnel, every tunnel coming back, an Internet pin ignoring the default, a watchdog during the change, and both ways a down default can fail, open or closed, which settles whether ARCHITECTURE and the README or the app's own notes are wrong; MAX ACTIVE VPNS and REBOOT ROUTER's progress; the five-minute background session grace; and REDEPLOY and MAX ACTIVE VPNS behind the paywall. Breaking a tunnel is down to five methods plus the backoff script: the private-key swap, which lets the handshake age out exactly as an expired PIA registration does and on stock also settles ID-070; peer removal, its quick form; interface down; a WebUI turn-off that must be left alone; and one failed rebuild. Moving the endpoint, firewall blocks, pulling the WAN and the DISABLE buttons are explained in the reference as methods that look right and are not. Also corrected: the `cfg_pia_wg_*` key names, the boot persistence file's permissions (700, not 777), and a note that the script tests `ifconfig`. Guest Wi-Fi is recorded as out of scope.
- ID-072 DELETE: `scripts/new-test-record.py` is retired. It built a blank test record, as a Markdown table, from a TESTING.md section 4 that no longer existed, so it failed before writing anything. With test labels that never change, nothing renumbers, so a run is now recorded by copying TESTING.md into `.claude/testing/` and writing PASS, FAIL or SKIP under each label. `scripts/test-backoff.sh` now points at the reference section "The backoff ladder" instead of a section number that had moved.

2026-09-15 v0.8.80 build 450 - the dependency scan runs again, on what the app ships and builds with

- ID-056 FIX: **the OSV dependency scan runs again, and a failed scan stops the Quality & security run.** The pull request from `dev` to `main` failed it with "Incorrect Usage: flag provided but not defined: -exclude". `quality_and_security.yml` passed `--exclude=/usr/local/go` and `--exclude=/opt/hostedtoolcache/go`, added 2026-07-20 when osv-scanner still had `--exclude`; it is now `--experimental-exclude`, and the v2.6.0 scanner that ID-036 pinned rejects the old name. Both paths were the runner's own Go toolchain, outside the scanned `./` and not visible inside the scanner's container, so they never excluded anything and are gone rather than renamed. The failure had been possible to miss: the reusable workflow runs the scanner with `continue-on-error`, and before v2.6.0 it reported a scan that wrote no results as clean; v2.6.0 fails the job instead, which is how this surfaced. Quality, the debug build and CodeQL now `need` the OSV scan (MobSF needs the debug build), so a vulnerability or a scanner failure skips the rest of the run instead of spending fifteen minutes on it; `release.yml` already refuses to release unless the whole workflow succeeds.
- ID-058 FIX: **the OSV scan covers what the app ships and builds with, and passes.** With the scan running again (ID-056), the pull request failed it on 86 known vulnerabilities (3 critical, 35 high) in 18 packages - Netty, protobuf, Bouncy Castle, Apache httpclient and commons-lang3. Every one was locked only for the Android Gradle plugin's Unified Test Platform, the tooling that runs instrumented tests on a device or emulator, through 13 internal `_internal-unified-test-platform-*` configurations. This app has no instrumented tests and no workflow runs any, and none of it ships; it was in `android/app/gradle.lockfile` only because every configuration is locked, and had been since at least v0.3.38 - the broken scan had hidden it. Dependency locking is switched off for those 13 configurations, so their 150 entries leave the lockfile (5 shared entries just lose their names) and a full `--write-locks` regeneration leaves it byte-identical; the 108 entries that remain, the release build's 76 libraries among them, have no known vulnerabilities. The unlock is in `android/build.gradle.kts`, after the last `lockAllConfigurations()`, because `evaluationDependsOn(":app")` evaluates the app script before that call and it switched an unlock made there back on. Revisit if instrumented tests are ever added: those tools would then run, unpinned. Checked: local OSV query of every locked package finds none, clean debug build, analyze and the full suite.

2026-09-15 v0.8.79 build 449 - a build pipeline that checks itself, and screens that remember what you told them

- ID-036 FIX: **the action pin scripts no longer write a new tag's comment beside the previous tag's SHA.** `scripts/pin-actions-latest.ps1` and `.sh` cached one SHA per action and reused it whenever the cached tag matched, but the tag was refreshed before the SHA was looked up, so a new release was written as `@<old sha> # <new tag>`. Five actions (10 workflow lines) were affected, the oldest since build 391: `actions/setup-java` v6.0.1 was running v6.0.0, `anchore/sbom-action` v0.24.2 was v0.24.0, `github/codeql-action` v4.38.0 was v4.37.9, `google/osv-scanner-action` v2.6.0 was v2.5.1 and `softprops/action-gh-release` v3.0.3 was v3.0.2; all are now pinned to the right commits. The cache now records which tag its SHA belongs to (`shaTag`). Every pin is then checked against its tag with `git ls-remote`, which needs no token and uses no API quota, and a mismatch exits 1 and stops `build.ps1` and `build.sh`. When the API cannot answer, the tag and SHA come from `git ls-remote`; if GitHub cannot be reached at all the build carries on with a warning, so offline builds still work. The scripts now report what they do: a header (token and API quota, cache, mode), one status line per action (`ok`, `UPDATED`, `FIXED`, `PINNED`, `SKIPPED`, `UNRESOLVED`) saying where the tag and SHA came from, the files written, the check result and a summary; `-v` / `-Verbose` adds each API request and git lookup. The git lookups run in parallel, so a run takes seconds. The .sh help (`-h`) prints only the header instead of every comment in the file.
- ID-037 BLD: **the local build scripts stop when a check fails, and report only what they built.** `build.ps1` carried on after a failing `flutter analyze` or `flutter test`, because PowerShell's `$ErrorActionPreference` does not cover external programs, then built and reported success; it now stops, and the failure message names the command and its error. In both scripts: analyze runs with `--fatal-infos`, as CI does; the action pins are checked straight after the environment check instead of after a minute of cleaning and fetching, and `--skip-pin` leaves them out; the scripts work from the repo root wherever they are started; the artefact summary lists only what the chosen mode builds and fails on a file that is missing or left over from an earlier build; the release APK is named `cfg-pia-wg-v<version>_build<n>_release.apk`, in CI's style, and an unreadable `pubspec.yaml` version stops the build instead of producing `cfg_pia_wg-v_release.apk`. Also: `flutter doctor` runs only when `ANDROID_HOME` is unset, the unused Java lookup and the `gradle --refresh-dependencies` call are gone, the step messages say what actually runs, `build.sh` uses `set -E` so its failure trap also fires inside functions, and it runs the pin script through `bash` because the file is not marked executable in git.
- ID-038 REL: CLOSED - not applicable: the Wear OS requirements in Play's technical quality list (64-bit and 16 KB page size by 15 Sep 2026; crash 4%, ANR 5% and battery 1% per watch model). The app is for phones and tablets and its manifest declares no watch feature. Split from ID-010.
- ID-039 REL: CLOSED - not applicable: the Android TV requirement for 64-bit and 16 KB page size by 1 Aug 2026. The manifest declares no leanback feature. Split from ID-010.
- ID-040 REL: CLOSED - not applicable: zero-tap sign-in restoration with the Restore Credentials API, from April 2027, which covers apps with user sign-in. The app has no account of its own: router and PIA credentials are entered for a session and wiped from memory, so there is nothing to restore. Split from ID-010.
- ID-023 REL: CLOSED - not doing: moving the version to 0.9 with the first stock-support release. The version stays on 0.8 until the iOS version.
- ID-042 CHG: **removed the `in_app_review` plugin; the review link opens the Play Store listing with `url_launcher`.** The plugin applied the Kotlin Gradle plugin unconditionally, which Flutter warned about on every build and which fails the build once built-in Kotlin is on (ID-043); its latest release, 2.0.12, is four months old, and the AGP 9 fix (PR #188) has had no maintainer response. The app only ever called `openStoreListing()`, an ACTION_VIEW on the https listing URL, so `openPlayStoreReview()` now opens `kPlayStoreListingUrl` with `launchUrl(..., mode: LaunchMode.externalApplication)`: the Play Store app takes the link, where `platformDefault` would show Play's web page in an in-app browser tab. It still returns false when nothing opened, and both callers log it. The Play review libraries (`review`, `review-ktx`, `core-common`) left the Android build; `play-services-base` stays, required by Play Billing through RevenueCat, and with the plugin no longer forcing newer versions it resolves to Billing's own 18.5.0 (was 18.7.2), with `play-services-tasks` at 18.2.0 (was 18.3.2). Both lockfiles regenerated. Tests mock url_launcher's channel instead of faking the plugin, check the listing opens outside the app, and hold the listing id to `applicationId` in `build.gradle.kts`.
- ID-028 FIX: CLOSED - fixed by ID-042: `openPlayStoreReview()` no longer goes through `in_app_review`'s `openStoreListing()`, which needed an `appStoreId` on iOS and threw without one.
- ID-043 CFG: **turned on AGP 9's built-in Kotlin (`android.builtInKotlin=true`).** Android's docs say the opt-out is removed in AGP 10, and Flutter will drop support for plugins that apply the Kotlin Gradle plugin, so it is done now rather than forced later; ID-042 removed the one plugin that applied it unconditionally. `package_info_plus` and `share_plus` apply it only below AGP 9, and `app/build.gradle.kts` already used `kotlin { compilerOptions }`, so nothing else changed. Checked: the Gradle lockfiles regenerate with no further change; a clean debug build and a release AAB both build with no Kotlin Gradle plugin warning; the About screen's Kotlin version still reads 2.3.20. `android.newDsl` stays `false`, as Flutter's Gradle plugin still depends on the old DSL types. CI still to confirm on the next push.
- ID-044 REL: **a release's notes cover every CHANGELOG block since the previous tag, not only the tagged one.** The GitHub release for v0.8.77 left out everything from v0.8.75 and v0.8.76, which were never tagged: commit `58fb480` replaced the old "every unreleased block" logic, which asked the GitHub API which releases existed, with only the tagged block. The parser moved out of an inline Python step into `tool/release_notes.dart`, which `release.yml` runs with `dart run`. It takes the previous tag from git (the highest version tag below the one being released; the checkout already fetches every tag) and collects each block down to it, newest first and in the order written, each under its own heading. Play's what's new is the tagged block's own ```play fence when it has one, otherwise the fences of the other blocks the release covers; the 500-character limit, the loud no-block body and the changelog-link fallback are unchanged. 16 tests, including the real CHANGELOG, where v0.8.77 now carries 447, 446 and 445. The stale `test/release/release-notes.sh`, still looking for the old 1.2 heading, is deleted.
- ID-045 REL: **a manually run workflow, Update Play listing (`.github/workflows/play_listing.yml`), publishes the `en-AU` store listing text from `play-store/description.md` and `play-store/description_short.md`.** `tool/play_listing.dart` checks both before anything is sent: the full description stops at 4,000 characters or more, deliberately one under Google Play's limit, and the short description above Play's 80, where every character counts. A failure names the file, says why the run stopped, and gives its character count and how far over the most it accepts it is; characters are counted as Play counts them (code points), after dropping the file's trailing newline. The check writes the exact request body, so what was counted is what gets sent. The workflow then gets an access token with `google-github-actions/auth` (v3.0.0, pinned; no credentials file written to the workspace) from the `PLAY_CONSOLE_JSON_KEY` secret the release and promote workflows already use, and makes one edit through the Android Publisher API: open, patch the listing, commit, deleting the edit if any step fails. A check-only option runs the check and sends nothing. Neither existing Play action edits store listings, which is why this calls the API directly. The service account may need the Play Console permission to edit the store listing; releases do not grant it. 11 tests, including the real files at 3,408 and 78 characters. `play-store/README.md` lists both files and the workflow.
- ID-007 ADD: **`THIRD-PARTY-NOTICES.md` is generated instead of kept by hand, and now covers the Android libraries too.** The hand-kept file had drifted: it listed 18 dev-only packages as shipped, missed `in_app_review`, gave `dartssh2` as 2.22.5 with 4.1.0 locked and `x25519` as 0.1.1, and had four licences wrong (`fake_async` and `x25519` are Apache-2.0, `posix` MIT, `vector_math` BSD-3-Clause). `tool/third_party_notices.dart` lists the Dart packages the app ships - everything reachable from `pubspec.yaml`'s direct dependencies in `flutter pub deps --json` - with each licence recognised from the package's LICENSE file (dart_pubspec_licenses), preferring a licence the file names outright (`asn1lib`). It lists the 76 Android libraries in the release build's `releaseRuntimeClasspath` from `android/app/gradle.lockfile`, each with the licence its Maven POM declares, read from the Gradle cache or fetched from Google Maven and Maven Central and following parent POMs; the cache alone lacks the POMs for 48 of them. It regenerates the file in `scripts/build.ps1` and `build.sh` `all` mode; offline it leaves the file unchanged and the build carries on with a warning. `release.yml` runs it with `--check`, which warns when the committed file is stale and never fails the run. Output is deterministic, so a stale file is a real change. 11 tests, including one that holds the committed file to `pubspec.yaml`'s direct dependencies. Result: 66 Dart packages, 76 Android libraries, 5 dev dependencies, no licence unrecognised. Worth knowing: RevenueCat brings Amazon's Appstore SDK (`com.amazon.device:amazon-appstore-sdk`, Program Materials License) into the Play build.
- ID-010 REL: **reviewed the release build against Play Console's technical quality requirements; it meets every one that can be checked before release.** Measured 2026-09-15 on the release APK and on the `Pixel_7_Pro` emulator (Android 17, x86_64, 4 GB, 16 KB page size). Requirements that do not apply were closed as ID-038, ID-039 and ID-040.
  - 16 KB page size: all nine native libraries are stored uncompressed and 16 KB zip-aligned (`zipalign -c -P 16`), and their ELF LOAD segments align at 16 KB (`libdartjni`) or 64 KB (`libflutter`, `libapp`). The app installs, starts and survives a 400-event monkey run on the 16 KB image with no crash or ANR. The debug-only Vulkan validation layer is not in the release.
  - DEX optimisation, from February 2027, does not apply: the R8-shrunk release DEX is 2.93 MB, under the 10 MB threshold.
  - memory, from February 2027: anonymous RSS plus swap is about 98 MB in the foreground and 90 MB in the background, against 2 GB and 1 GB for a 4 GB device; bitmap memory is under 1 MB, against 200 MB and 400 MB.
  - R8 keep rules, reviewed by hand, since r8-analyzer's automated paths need AGP 9.3 or a development build of R8: the two broad rules in `proguard-rules.pro` keep all of `io.flutter.**` and the app's own package. A trial build without them cut the DEX from 3.07 MB to 2.66 MB (13.5%) and left 92 rather than 502 Flutter classes unrenamed; it also started and survived the monkey run, but the router, clipboard and billing paths were not exercised. RevenueCat's consumer rules keep all 402 classes of the Amazon Appstore SDK, which `purchases-store-amazon` brings into the Play build. Both are candidates for items of their own.
  - crash rate, ANR rate and excessive partial wake locks are measured from real users in Play Console, so they are checked after release. The app requests no `WAKE_LOCK` permission.
  - emulator start-up times (690-860 ms cold) are a smoke test, not a device measurement.
- ID-046 FIX: **a login on SETTINGS is kept for the session, and every SETTINGS action says what happened in the logs.** Reported: after logging in on a SETTINGS prompt, MAX ACTIVE VPNS asked for the login again, every time. SETTINGS stored the credentials but never marked the session connected, and a session that has not connected is deliberately not reused (the 423 fix, so a filled-in form that never reached a router still asks); the router log screen marks it, SETTINGS did not. Each router action on SETTINGS now marks the session connected once it has reached the router, so one login covers the rest of the screen and every other screen, and a login that fails is not kept as connected - the next action asks again, prefilled. Logging, checked action by action: REBOOT ROUTER and UNINSTALL already wrote to both logs, FORGET ROUTER IP to the app log, and a failure reaches the app log as an error. REMOVE CACHED PIA CERT now also writes the router log; MAX ACTIVE VPNS now logs when there is nothing to change (Merlin, or firmware it does not support) and when the same number is saved again, as well as a new limit. Tests: one login covers MAX ACTIVE VPNS, a failed login is not kept, and each action's log lines. TESTING section 10 carries the manual checks.
- ID-047 FIX: RESTORE PURCHASE on SETTINGS logs "Restore started." and then what it found - restored, no purchase, or the store error - in the same words the paywall's restore already logged, where it wrote nothing before. Tested for all three outcomes through a test seam that stands in for the store.
- ID-048 FIX: **deploying a watchdog on an empty slot no longer logs a failure.** Reported: the router log showed `wgc1: No handshake and both pings failed (8.8.8.8, 1.1.1.1)` after a deploy that worked. The deploy's first run checks the slot before its tunnel exists, so for that run "not up" is the starting state, not an outage - the same reasoning that already gave it `Deploying: bringing wgcN up for the first time` rather than `Connectivity lost`. A deploy run now logs `Interface wgcN is not up yet` or `Not connected yet: no handshake, and no answer from <primary> or <secondary>`, neither of which the router log colours red; a scheduled run still logs the failure as it did. Tests: the script's wording and order on both firmwares, and that the router log does not treat the new lines as errors. TESTING section 6 carries the manual check.
- ID-049 ADD: the watchdog's test email names the region on the form, in its subject (`TEST email - wgcN:pia-<region>`) and in the body's Watchdog row, as the deployed, delay and failure emails do. It used to take the region from the router's `wgcN_desc`, which is empty before the first deploy and still the old region after it is changed on the form, so the subject said only `wgcN` and the body "region not yet set". Tests: the region passed in reaches both, and the form passes its own.
- ID-050 ADD: **the watchdog form pre-fills every email field.** Retyping them for each watchdog was tedious even with copy and paste, and some autofill providers, Google's included, do not fill several fields at once. From, to, subject prefix, SMTP server:port, SMTP username and SMTP password all come from one source, taken whole, in this order: the slot's own settings in NVRAM (as before), the settings entered this session, the lowest-numbered other slot that has some, then the remaining slots in turn; with none anywhere the fields are blank and the subject keeps its default. A set with no SMTP server and no recipient counts as none. The other slots are read only when the slot and the session have nothing, in one command for all five (`kEmailSettingsCommand`) rather than `loadConfig`'s key-at-a-time reads, which would have cost two dozen SSH round trips. The session keeps whatever is on the form when it closes, as it already did for the PIA credentials, in `SessionController.watchdogEmail`, which `wipeAll` clears on exit; nothing is stored on the phone, and the NVRAM is only read after a router login. The email switch is left as the slot has it. Also removed two stale comments describing an idle wipe that was reverted long ago (`session_controller.dart`, `standalone_config_screen.dart`). New `lib/watchdog_email.dart`; tests for the order, the one-command read and its parsing, each source on the form, the form's values kept on close, and `wipeAll` clearing them. TESTING section 6 carries the manual check.
- ID-051 CHG: on ABOUT, COPY BUILD INFO and CREATE GITHUB ISSUE sit 20 px below the watchdog history line rather than 8, and are centred across the column; they still fall to two lines on a narrow phone. The row is full width, since a Wrap otherwise shrinks to its buttons and has nothing to centre them in. Tested for the gap and the centring.
- ID-052 CHG: **FORGET ROUTER IP asks before deleting the remembered address**, naming it, with CANCEL first in grey and FORGET in red, like the other rows on SETTINGS that remove something; CANCEL keeps the address and logs nothing. The app log sent people to the wrong screen - "Clear it with FORGET ROUTER IP on the About screen" - and two comments (`session_controller.dart`, `router_prefs.dart`) said the same; all three now say SETTINGS, where the button has been since 422. Tested for the prompt, CANCEL, and the log wording.
- ID-053 FIX: the GitHub issue CREATE GITHUB ISSUE prefills gives the router firmware version once. It was in the Environment block (`Router firmware: stock <version>`) and again as a `Router firmware version` bullet under it; the bullet is gone. Test updated to hold it to one.
- ID-054 ADD: **REBOOT ROUTER shows a count once confirmed**: 0% to 100%, one per cent a second, as the ASUS WebUI does, with a progress bar and no buttons; the back key leaves it and the reboot carries on. It closes early as soon as the router answers on its SSH port again, checked every 3 seconds - but only after a check has found it down, since the router takes a few seconds to go down and an early answer would close the count at once. Either way the outcome goes to the app log and a snackbar: "The router answered again after N seconds." or, at 100, that it has not answered yet. The shared SSH session is closed after the reboot request, so the next action opens a fresh one rather than finding a dead one. Replaces the one-line "Reboot requested" snackbar. Tests with a stand-in for the router check: the count, closing only after down-then-up, stopping at 100, the back key, and no buttons.
- ID-055 TST: TESTING section 14 checks that a Play Store build shows RESTORE PURCHASE on SETTINGS, in its place between UNINSTALL FEATURES DEPLOYED TO ROUTER and MAX ACTIVE VPNS, and that a local build does not; and that APP LOG shows `Restore started.` and the outcome (ID-047).
- ID-004 CHG: **the app log keeps up to 100,000 characters, and a long log no longer slows the LOG screen.** The log only ever grew, and the LOG screen laid the whole of it out as one paragraph on every new line - and once a second during a clipboard countdown, since it listened to the whole controller. The principle agreed on 2026-09-15: keep the log, always; it is never written to storage, so keep the most a user can both see and copy, and copy nothing that is not on screen. Measured with the new `tool/log_cap_probe.dart` on the Android 17 emulator: one paragraph missed a 16 ms frame at about 20,000 characters (roughly 250 lines), and text symbols in place of the icons gained only a quarter; drawn in blocks of 100 lines, adding a line stayed inside a frame to about 200,000 characters; the clipboard took 1,000,000 characters and failed at 2,000,000 (`TransactionTooLargeException`). So: `LogPanel` draws the log in blocks of 100 lines and reuses every block that has not changed, looking exactly as before; a selection across blocks keeps its line breaks, through a `SelectionContainer` delegate that joins them, since `SelectionArea` joins separate widgets with nothing; the LOG screen redraws only when the log changes (`SessionController.logChanges`); and the log is capped at half the screen's limit, 100,000 characters - about 1,300 lines, ten times a heavy session. Past the cap the oldest lines go in one chunk, down to 90%, under a first line, shown and copied: "Log truncated by N lines: the oldest were removed so the whole log can still be shown and copied without slowing the app down. The app never saves the log to the phone, so they cannot be recovered." Tests: the cap, the chunked trim and its running count, the newest line always kept, CLEAR starting afresh, the marker on screen and in COPY, redrawing only for log changes, blocks of 100, copy across blocks keeping every line break, and a new line rebuilding only the last block.

2026-09-14 v0.8.78 build 448 - fixes and user facing changes

- ID-012 DOC: updated `./play-store/description.md`, now only contains the Google Play Store description. Needs automation, yet to be created, to alter release.yml to update the GPS description automatically. A BACKLOG work items has been created to automate this through a GitHub actions workflow.
- ID-013 DOC: added `./play-store/description_short.md` and `./play-store/copy_reqs.md`, the latter stores the maximum character count for description and short description.
- ID-014 DOC: added `./.github/description.md`, this is the GitHub repo description.
- ID-015 DELETE: `.claude\testing\2026-09-07_pristine-lan-reference.md` once device assignment is complete and tested.
- ID-016 INF: The RevenueCat implementation, product decisions and price is in [`.claude/plans/plan_revenuecat-implementation.md`](.claude/plans/plan_revenuecat-implementation.md)
- ID-030 INF: adopted the `ID-NNN` unique identifier convention, shared as one number line across CHANGELOG.md and BACKLOG.md. Applied to Pending, WIP and this release in CHANGELOG, and backfilled across all existing prefixed items in BACKLOG. Earlier CHANGELOG releases (v0.8.77 build 447 and before) were not retrofitted. Extensive edits to BACKLOG and CHANGELOG implementing a prompted backlog management workflow.
- ID-009 DOC: Trademark protection: add to README that app name, logos, and branding are reserved trademarks.
- ID-031 CHG: **the main menu is a left-aligned list with an icon for every destination.** It had eight teal-filled buttons with centred labels, and with an icon centred beside each label every row's icon started in a different place, so the screen read as nine disjointed bundles. Each destination is now a row - icon, label, chevron - with a `#12141A` fill (the screen colour) and a teal border and label. EXIT keeps its red outline, gains the power icon, has no chevron and sits a little apart. On a tablet the list stops at 520 wide and centres, and the help and review links line up with it. The drawer shows the same icons, plus HOME, and both take them from one function, `destinationIcon`, so they cannot drift. Icons: STANDALONE `note_add_outlined`, MANAGE `app_registration_outlined`, WATCHDOG `monitor_heart_outlined`, DEVICE ASSIGNMENT `hub_outlined`, ROUTER LOG `router_outlined`, APP LOG `list_alt_outlined`, SETTINGS `settings_outlined`, ABOUT `info_outline`, EXIT `power_settings_new`, HOME `home_outlined`. CONTEXT's house style no longer exempts the main menu, and TESTING's home screen checks and the main menu tests cover the rows, the icons, the tablet cap and the drawer.
- ID-032 CHG: **device assignment rows show each device's MAC address.** A row's first line is the device name and its exceptions - `offline`, `random MAC`, `DHCP` - separated by ` | `; the second line is the IP address and MAC in grey, or the MAC alone when no address is known. The MAC tells apart two devices with the same name and matches the router's own client list.
- ID-033 CHG: APP LOG and ROUTER LOG are headed with their menu names, in teal capitals, placed and styled like the VIEW WATCHDOG LOG heading.
- ID-034 CHG: **the watchdog's lines in the router log are lavender, not amber.** Amber means a warning everywhere else in the app, so healthy watchdog lines looked like problems. The app's lines stay teal, errors red and the firmware's own lines plain; lavender (`#B69CFF`) is distinct from all of them.
- ID-035 CHG: MANAGE and WATCHDOG list each slot on one line, `wgc1:pia-region_name`, the way every log line and dialog already names a slot, with the slot in teal and the region in white; an empty slot reads `wgc2 <empty slot>`.

2026-09-14 v0.8.77 build 447 - device assignment you can check, and DNS you can see

- ADD: **a failed alert email records how name resolution looked at that moment.** After `Email FAILED`, the watchdog log gains `Email diag: resolv.conf [...] via <interface>; <SMTP host> resolves to [...]` - the nameservers in `/etc/resolv.conf`, the interface the first one is reached through, and what the SMTP host resolved to, or the lookup's error. The one undelivered alert so far, on 2026-09-06, failed on `server misbehaving` and left nothing to say why; the next one explains itself. The route is cut down to its interface name, because the full route names the WAN address and the log is quoted in failure emails.
- DOC: CHANGELOG Pending records where the router keeps its DNS-over-TLS list (`dnspriv_rulelist`), the measurement the slot-DNS overlap note was waiting on. ARCHITECTURE, CONTEXT and TESTING describe the new log line.
- TST: the diagnostic line sits in the failure branch after the mailer error and never on a send that worked, reads `/etc/resolv.conf`, looks the SMTP host up, and takes only the interface from the route. The script size guard rises from 26,624 to 28,160 bytes to make room, as agreed.
- ADD: **the DNS field says that devices assigned to a VPN use only its first server.** On stock, under the field in MANAGE's CREATE credentials dialog and in EDIT: "Devices assigned to this VPN use only the first server. If they reach IP addresses but not names, try a different first server." Measured on hardware: the firmware redirects an assigned device's DNS to the slot's first server and never tries the second. STANDALONE, whose `.conf` goes to another client, and Merlin do not show it. Nothing on the router changes.
- FIX: **README, ARCHITECTURE and CONTEXT no longer say that a downed default connection stops alert emails.** Measured 2026-09-14: traffic the router creates never follows the default connection, the watchdog resolves through `/etc/resolv.conf` with the WAN's DNS first, and a test email went out while a tunnel's encrypted DNS was blocked. README's advice to leave a tunnel unassigned as the default for that reason is gone. The one undelivered alert, on 2026-09-06, is unexplained again. The script template's comment is corrected too, with no change to what the script does.
- DOC: BACKLOG records the router's own DNS following the first tunnel rather than the default connection as firmware behaviour, moved out of Unconfirmed BUGs with its reproduction. CHANGELOG Pending swaps the DNS-fallback decision, now built, for a note when a slot's DNS matches the router's own encrypted-DNS servers. README 5.2 and 5.4 and TESTING cover the new line.
- TST: the first-server note on stock in CREATE and EDIT, and its absence on Merlin and on STANDALONE.
- ADD: **APPLY checks the tunnels it moves devices onto.** Read fresh when APPLY is pressed - up or down, and how long since the server last answered, against the router's clock - and the confirmation says what it found: a tunnel that is not running names where the devices go meanwhile, and one whose server has been silent for more than three minutes says they may have no internet. A warning, never a block, because assigning to a disabled slot is legitimate. The default connection's tunnel is checked when the default changes or a device is sent to it. A handshake is not proof of a working path, so this catches "not running" and "not answering", not every failure.
- ADD: **a device whose tunnel is not running says where its traffic actually goes.** A note under its picker names the default connection it falls through to, or the plain internet when that is not running either, and the default connection panel gets the same note when the default tunnel is down. The picker still names the assignment: the pin is intact, and enabling the tunnel restores it. Tunnel state is re-read after APPLY, so the notes follow a default-connection change.
- TST: the handshake parse, the three-minute threshold, ages against the router clock and no alarm without one, each warning's wording, the exit resolution two hops deep with an unknown state answering nothing, and the one-round-trip health read; on the screen, a stopped tunnel warned about and still applied, a silent server, a healthy tunnel adding nothing, the default tunnel's own warning, and the exit notes on a device and on the default panel.
- DOC: TESTING 7.2 is the end-to-end device assignment run for a release: between tunnels, to and from the default, a disabled slot, a silent server, delete and recreate, the default connection, and a reboot. CONTEXT and README describe the tunnel check and the exit note.

2026-09-13 v0.8.76 build 446 - one house style, every screen on the menu, and tunnels that match their labels

- FIX: **changing a slot's region on the watchdog form rebuilds the tunnel on the new region.** Found while fixing CREATE: SAVE & DEPLOY wrote only the new region name, and the deploy run left the old server's tunnel alone because its handshake was recent, so the old server kept running under the new name. A region change now stops a running tunnel, blanks the old server's keys and endpoint, and lets the deploy run build the tunnel on the new region - the path the empty-slot watchdog shortcut already takes. The overwrite prompt says the tunnel is down while that happens and that assigned devices use the default connection meanwhile. No change to the router script.
- TST: a region change stopping a running tunnel and blanking the old server before the new name is written and the deploy runs, on Merlin and on stock (`stop_vpnc`, then the restart); a slot that is not running cleared without a stop; an unchanged region clearing nothing; and the form's prompt warning of the rebuild only when the region changes.
- DOC: TESTING lists the manual scenarios for a region on the watchdog form - same and new region on a running slot, a disabled slot, an empty slot, the stock WebUI, an assigned device during the rebuild, and a failed rebuild. CONTEXT and README describe the rebuild.
- FIX: **CREATE over a running slot no longer leaves the old tunnel running under the new region's name.** Measured on hardware: overwriting a running wgc4 on `us_alabama` with `aus_perth` wrote Perth's settings and label while traffic kept leaving through Alabama, and the dialog then said to ENABLE a slot that was already up. CREATE now stops a running tunnel first, the way DISABLE does, and leaves the slot disabled. The overwrite prompt says so beforehand and the dialog says so afterwards. Both firmwares.
- FIX: **adding a watchdog to a tunnel that is already running no longer restarts every tunnel.** The deploy enabled the slot unconditionally, which on stock is `restart_vpnc`. When the slot is up and keeps its region, the enable flags are still written but the service call is skipped. A changed region still takes the full enable.
- TST: CREATE stopping a running slot before any write, on Merlin and on stock (`stop_vpnc`, never a restart), returning whether it did, and the modal warning and reporting it; a deploy onto a running slot with its region unchanged making no service call on either firmware, and a region change still enabling.
- DOC: CONTEXT, ARCHITECTURE, TESTING and README describe both fixes. CHANGELOG pending loses the two completed items and gains the watchdog region-change fault found while fixing them.
- DOC: README brought up to date with build 446: menu names throughout, DISABLE asking first, the watchdog form's region and SAVE & DEPLOY, the watchdog log including the previous file, the failure email's five-point checklist and the stock kill-switch cases, SETTINGS in its new order with REBOOT ROUTER and RESTORE PURCHASE, the uninstall's new name, and the About screen's firmware, licence and redeploy.
- CHG: **the watchdog form chooses its region on the form**, with the same region row STANDALONE has, pre-filled with the slot's own region. The button reads SAVE & DEPLOY. The picker used to arrive after SAVE, as a surprise at the end of a long form. A configured slot still warns before it is overwritten, and a region typed into the field is checked against PIA's list before anything reaches the router.
- FIX: **the watchdog email no longer talks about "its devices" when nothing is assigned to the tunnel.** On stock it counts the devices assigned to the tunnel, and one with none that is not the default connection says so.
- FIX: **the watchdog email checks the default connection before saying devices stayed on a VPN.** "Still on a VPN" is now said only when the default is a WireGuard tunnel whose interface is up. A default that is down, or is not WireGuard and so cannot be checked, is reported as not confirmed up, and devices may have had no VPN. These reach a router on its next deploy, or through REDEPLOY TO UPDATE VERSION on the About screen.
- CHG: the email's checklist asks "Is your PIA user account active?" rather than "billing account".
- DOC: CONTEXT and TESTING cover the region on the watchdog form and the new kill-switch wording.
- TST: the region pre-filled on the form, an unknown region refused, an empty one asked for, and SAVE & DEPLOY going straight on with no picker; and the new kill-switch cases on stock, with every case still carrying all three tenses.
- CHG: **settings in the agreed order**: REBOOT ROUTER, FORGET ROUTER IP, REMOVE CACHED PIA CERT, UNINSTALL FEATURES DEPLOYED TO ROUTER, then RESTORE PURCHASE on a store build.
- CHG: UNINSTALL FEATURES INSTALLED TO ROUTER is renamed UNINSTALL FEATURES DEPLOYED TO ROUTER.
- FIX: **the uninstall's "are you sure" buttons follow the house style.** Both were teal-bordered, the destructive UNINSTALL included, and they sat in the opposite order to every other confirmation. CANCEL now comes first in grey and UNINSTALL second in red. The button change earlier in this build missed them because they were styled by hand.
- TST: the settings rows in the agreed order under their new names.
- FIX: **the GitHub issue carries the router's firmware version.** A local variable holding the firmware type was named `firmware` and shadowed the version passed in, so both firmware lines in a report said only "stock" and the version never arrived. It now reads, for example, "Router firmware: stock 3.0.0.4.388_25127", and the type comes from the router itself rather than only from an earlier visit to a router screen.
- ADD: **Router firmware on the About screen**, type and version, once the router has been read.
- ADD: **License status in the build info**: licensed, unlicenced, or homegrown for a copy built without a store key. It travels with the rest of the block into COPY BUILD INFO and CREATE GITHUB ISSUE.
- ADD: **an out-of-date watchdog script shows amber on the About screen, with REDEPLOY TO UPDATE VERSION under it.** It rewrites only the script files already on the router, for the firmware it finds there, then reads the version straight back. No tunnel is restarted and no schedule or setting changes, because the script reads its settings from the router on every run. It sits behind the paywall, as a change to the router.
- CHG: more space around the About screen's grey section rules.
- DOC: CONTEXT and TESTING cover the new rows and the redeploy offer.
- TST: the three licence states; the firmware status with and without a version; the issue carrying firmware type, version and licence; amber and the redeploy offer only for an out-of-date script; and redeploy writing only existing scripts, refusing unsupported firmware and finding nothing to do.
- ADD: **errors in the router log are red.** A line the app or its watchdog wrote that reports a fault - ERROR, failed, connectivity lost, down or absent, never answered, no Internet - shows in red rather than teal or amber. The firmware's own lines stay plain even when they say failed, so red always means this app.
- ADD: **the watchdog log shows yesterday as well as today.** The log rotates into a `.old` copy at midnight and the viewer only ever read today's file, so an alert emailed overnight usually pointed at lines the screen could not show. It now reads the rotated copy first and then today's, and a file not existing yet is not reported as a failure.
- CHG: CLEAR on the watchdog log also deletes the rotated copy, since the viewer now shows it. Clearing only today's file would have refilled the screen with yesterday's lines the moment it reopened.
- CHG: **the watchdog log's heading names the region as well as the slot**, for example WATCHDOG LOG · wgc1:aus_melbourne, and so does the question before CLEAR.
- DOC: CONTEXT no longer says the drawer offers three screens the main menu lacks, which stopped being true in the navigation change. TESTING checks the router log's colours and the watchdog log's rotated copy.
- TST: our error lines are red and the firmware's are not; the watchdog log reads the rotated copy first and tolerates either file being absent; CLEAR truncates the live log and removes the rotated copy; and the heading names the region.
- CHG: **the main menu offers every destination**, in the drawer's order: STANDALONE, MANAGE, WATCHDOG, DEVICE ASSIGNMENT, ROUTER LOG, APP LOG, SETTINGS, ABOUT, then EXIT. ROUTER LOG, SETTINGS and ABOUT were drawer-only. The menu now builds its buttons from the drawer's own list, so the two cannot offer different screens or put them in a different order.
- CHG: **shorter names, identical on the menu and in the drawer.** "Standalone PIA WireGuard config" is STANDALONE, "Manage PIA WireGuard config" is MANAGE, "Watchdog WireGuard management" is WATCHDOG, "VPN device assignment" is DEVICE ASSIGNMENT, "View router log" is ROUTER LOG, "View app log" is APP LOG, and "Exit app" is EXIT.
- CHG: the superscript markers on the menu buttons, and the two footnotes under them, "requires SSH connectivity to an ASUS router" and "stock firmware only", are gone.
- CHG: "how to use this app" and "add a Play Store app review" sit together directly under the buttons with no gap between them. The review link used to be pushed down to the foot of the screen.
- CHG: the MANAGE screen's heading reads MANAGE CONFIGURATION rather than WIREGUARD CONFIGURATION.
- DOC: CONTEXT's navigation table and notes, TESTING's home screen checks and ARCHITECTURE's menu diagram follow the new names.
- TST: all nine menu entries by label and order with no footnotes; the two links adjacent and under the buttons; and taps on buttons now below the fold on the test surface scroll to them first.
- CHG: **paywall wording, as agreed.** The manage pitches now end "No desktop, no laptop, no unfathomable scripts." and speak of a tunnel and a slot rather than the tunnel and the slot. The watchdog pitch checks "at your chosen check interval" and ends "or worse, not knowing you were unprotected". The first claim reads "One lifetime payment", and the button reads UNLOCK FOR LIFE with the store's price. What stays free drops "with or without a router", and spells out that removing includes every watchdog, their helper apps and all configuration the app deployed, while configured VPNs are kept.
- ADD: **every paywall event reaches the app log**: shown, and for which control; purchase started, completed, cancelled, pending or failed; restore started, restored, nothing found or failed; and closed still locked. A declined card or a slow approval used to flash a message at the foot of the screen and vanish, leaving nothing to read back.
- FIX: **store errors read as sentences** rather than the plugin's raw exception, with the store's error code in brackets for bug reports. A slow card is reported as a pending payment that unlocks once Google Play confirms it, as a warning rather than a failure.
- FIX: **Restore on the paywall says when the account holds no purchase**, in the same words as RESTORE PURCHASE in settings: "No purchase found on this Google account." It said nothing at all. The two now share their wording so it cannot drift.
- TST: the agreed paywall wording; logging on open, close, purchase and restore; nothing found; a declined payment as an error; a pending payment as a warning; and a completed purchase unlocking and leaving the page.
- FIX: **manage DISABLE asks first.** It took a tunnel down, and any watchdog running on it, in a single tap, while DELETE and the watchdog screen's DISABLE both asked. The question names the slot and says when a watchdog stops too. Reported as appearing only with the entitlement; in fact no path asked.
- FIX: **the watchdog log fills the width**, laid out like the app log and the router log. Its text sat in a centred column with no side padding, so on a tablet the lines were a narrow strip with a wide empty seam either side.
- FIX: **opening a slot with a VPN running but no watchdog no longer logs two "router command failed" lines.** Both were reads of files only a watchdog creates, the last successful ping and the deployed script, and a missing file is an ordinary answer rather than a failure. They are now read only when present, so absence is silent while a file that exists but cannot be read still reports.
- CHG: DEL PIA CERT on the settings screen is renamed REMOVE CACHED PIA CERT.
- TST: manage DISABLE's question, its watchdog wording and its CANCEL; the watchdog log's width and padding on a tablet-sized screen; and the guarded reads.
- CHG: **one house style for every button** outside the main menu and the paywall: bordered, unfilled, with the border and label in one colour that says what the button does. Teal does something, red destroys, removes, discards, reboots or exits, and grey is a way out that changes nothing. Disabled is darker again, so a greyed-out action never reads as a live CANCEL. The app had drifted into four looks chosen screen by screen - filled teal, bare text links, bordered teal and bordered grey - and a colour cannot mean anything while the same action wears a different one on the next screen.
- CHG: the slot buttons on MANAGE and WATCHDOG, both CONNECT TO ROUTER buttons, GENERATE CONFIG, the slot editor's SAVE, the watchdog form's SAVE and TEST EMAIL, and every dialog's buttons move onto it. DELETE is red on both slot screens.
- CHG: device assignment's DISCARD CHANGES and APPLY are always shown and follow the pending state: red and teal with changes staged, grey and disabled with none. APPLY loses its fill, and the two wrap onto separate lines on a phone too narrow for both labels.
- FIX: the device assignment picker's outline was drawn in the panel border colour and all but vanished, so it read as plain text. It is grey now, and amber while it holds a staged change.
- CHG: COPY BUILD INFO and CREATE GITHUB ISSUE on the About screen are bordered buttons rather than text links.
- DOC: CONTEXT records the house button style and its two exemptions, so a later change cannot quietly reintroduce a fill or a bare link.
- TST: the colour for each role and the disabled colour are pinned, and so is device assignment's DISCARD and APPLY pair in both states.
- FIX: rebooting the router now writes to the app log as well as the router log. The router's log is on the device that is about to go dark, so the app log is the one the user can still read while it comes back.
- CHG: REBOOT ROUTER now sends `sync; reboot`. Stock already runs an emergency sync on its way down, but the app should not rely on each firmware's shutdown path to get the watchdog scripts and boot hook in /jffs onto flash. No `nvram commit`: app writes already commit, and committing here would persist changes the app did not make.
- CHG: updated privacy policy formatting, replaced GitHub issue link with email address.
- NOTE: RevenueCat fully implemented, some UI facing code changes to follow. 

2026-09-13 v0.8.75 build 445 - the store says why, when it has nothing to sell

- ADD: **the app log now names WHY the paywall has nothing to offer.** Three faults, fixed in three different places, all presented as one greyed button reading "Not available right now": the store unreachable, no offering marked current in the RevenueCat dashboard, and an offering whose product Google Play will not price. It now says which. Written after the first hardware purchase test spent an hour on the third of those.
- FIX: **CI - the Sonar scan is skipped on Dependabot runs.** A Dependabot-triggered workflow does not read the normal Actions secrets, it reads a separate Dependabot store, so the token arrived empty and the scanner died on startup with exit code 3 - which reads like a code problem and is not one. Copying the token into that store would be the wrong fix: these pull requests bump GitHub Actions, so they edit the very workflow files that would then run holding it.
- CHG: nothing is lost by skipping. An action version bump changes no Dart code, and the Monday scheduled run scans the default branch every week regardless.
- DOC: TESTING gains what a purchase test actually looks like from the dashboard side. Sandbox activity is hidden from RevenueCat's transaction views by default, so a working purchase looks like no purchase; customer counts never move for a refund; and Play's pre-launch report adds ghost customers after every release, measured at seven from the United States within twenty minutes of an upload.
- DOC: the plan records the Test Store trap that cost an hour. RevenueCat's setup wizard builds the default offering around its own Test Store product, which Google Play cannot price, and the control for fixing it is only in the offering's EDIT view - not on the offering page, not on the product page, and not in the three-dot menu.
- DOC: BACKLOG gains showing where a pinned device is really exiting when its slot is down. Measured on hardware: the policy record survives a disable, the router drops the routing rule, and the device falls through to the default connection and keeps working. Correct behaviour, but the screen still names the pinned slot, which is true of the configuration and false of the traffic.
2026-09-12 v0.8.74 build 444 - the seam has something behind it

```play
cfg-pia-wg now has a one-off unlock for the router features. One payment, no subscription, no trial to forget to cancel.

Generating standalone PIA WireGuard configurations stays free for everyone, forever.

You can always look at your router, and you can always remove anything this app set up, including taking it off the router entirely. Those never cost anything.

Nothing is tracked. No analytics, no advertising id.
```
- REL: **this is the release that introduces the price**, and it spans three build numbers. Builds 442 and 443 were spent getting Play to accept an artifact that could actually transact, so they exist as version codes rather than as releases; their entries are below. What a user meets is one thing: gated controls open a paywall, everything else carries on as it did.
- ADD: **`entitlement.dart` is a real implementation over RevenueCat.** It is still the only place the app asks about payment and the only file that imports the SDK; every gated screen reads the same `isUnlocked` it read yesterday. The seam existed for exactly this: landing purchasing replaced one implementation instead of editing every caller.
- ADD: **the key is not compiled in.** It arrives as `--dart-define=REVENUECAT_ANDROID_KEY`, from a repository secret. Not for secrecy - RevenueCat's public key is meant to be embedded and can be read out of any APK in a minute. It is so that a build WITHOUT it behaves correctly.
- CHG: **a keyless build sells nothing and withholds nothing.** Google Play refuses purchases from an artifact it did not distribute, so a self-built copy carrying a compiled-in key would show a paywall its owner could never complete. That is the opposite of what the paywall says. Building it yourself is the free path, and now the code says so rather than just the copy.
- ADD: **the release build FAILS when that secret is empty**, before it compiles anything. The failure it prevents is silent: an app that cannot ask who has paid withholds nothing, ships the paid features to everyone, and looks entirely normal doing it.
- CHG: with a key present the default is LOCKED. A first run that cannot reach the store has no evidence of a purchase, and inventing one would hand the app to anyone who turns off their wifi. A returning customer is covered by the SDK's own cache, so being offline never locks out someone who paid.
- ADD: **the store starts off the first frame**, and the price is fetched once at launch rather than when the paywall opens. A spinner where the price should be is the worst possible moment to make someone wait. An unreachable store logs a warning and leaves the paywall reading correctly with its button disabled.
- CHG: one place applies a customer record, whether it came from launch, the SDK's own listener, a purchase or a restore, and it holds the notify callback itself. No path can update the entitlement without telling the UI.
- CHG: a cancelled purchase is a normal outcome and returns false. It is not an error and must not be reported as one.
- CHG: **`android:allowBackup="false"` stays.** RevenueCat advises turning backups on so their anonymous user id survives a reinstall; that advice is for CONSUMED products, which Billing Client 8 can no longer query. A non-consumable comes back from the signed-in Google account with no local state, so restore already works, and this app holds router and PIA credentials.
- ADD: **RESTORE PURCHASE on the settings screen**, hidden in a build that cannot sell, where it could only ever report "no purchase found". It is the only row on that screen that gives something back rather than removing it, and it is there because someone with a new phone looks in settings before they look at a paywall.
- CHG: **restore is never automatic.** RevenueCat's guidance is that calling it programmatically can raise an operating-system sign-in prompt, and one of those on a cold start that nobody asked for is alarming and inexplicable. The plan had specified a silent auto-restore; that was wrong.
- ADD: the launch path calls `syncPurchases` instead, which is the sanctioned programmatic call and raises no prompt. A reinstall or a new phone arrives as a fresh anonymous id holding nothing, and this hands it whatever Google Play already knows the account owns. Nobody has to press anything, and nothing is stored on the device.
- TST: two more on the seam - a keyless build is unlocked and sells nothing, and the entitlement id still reads `router_features`. Spelled wrong, purchases succeed and unlock nothing, and only a customer ever finds out.
- DOC: **`SECURITY.md` says what a purchase costs in privacy terms**, in both the places that matter. Purchase state is not a credential and is not held on the device; the app never sees a card number or a billing address; RevenueCat is told a pseudonymous installation identifier it generated itself and nothing about who you are, because the app makes no account and never calls its `logIn`. There is still no analytics, no advertising identifier and no usage tracking.
- DOC: **TESTING.md gains "Buying and restoring"**, including the two things a local build cannot test and the reason, the refund that has to relock the app without a reinstall, and the sign-in prompt that must never appear at launch. Also the licence-tester trap: the tester list and the track opt-in are separate, and missing the second charges real money.
- DOC: the plan carries drafted Data safety answers, written to agree with `SECURITY.md` line for line. Three documents disagreeing about what leaves the device is a reason for a reviewer to reject.
- DOC: the plan records where the key lives and why. It briefly also carried an open question about the GitHub release APK undercutting the Play sale; that question does not exist, because releases publish no binaries at all. The SBOM and the licence manifest are the only attachments and the bundle goes straight to Play.
2026-09-12 v0.8.73 build 443 - the billing library Play actually looks for

- ADD: **`purchases_flutter` 10.12.0, bringing Google Play Billing Library 8.3.0.** The SDK arrives before the RevenueCat key that configures it, because Play forced the order. Play will not let you create a one-time product until it has an uploaded artifact that can actually transact, and it judges that by what the artifact links. An upload carrying only the permission was reported back as "Play Billing Library version AIDL", the legacy interface, against a floor of 8.0.0.
- CHG: **nothing calls the SDK.** It is linked, not configured, and no purchase code runs, so no data leaves the device. Verified in the release bundle rather than assumed: `billing.properties` reports `billing_client=8.3.0` and the classes survive R8, which is what Play reads. A dependency that R8 strips would have satisfied the compiler and failed the console.
- CHG: the three `gradle.lockfile`s regenerated. Dependency locking is strict here and refused the build until they were, which is the system working.
- DOC: `THIRD-PARTY-NOTICES.md` gains `purchases_flutter` and its one transitive, `equatable`, both MIT.
- REL: version bump. Play refused the upload with "version code 442 has already been used", so the one-time product setup carries on against 443.

2026-09-12 v0.8.72 build 442 - the paywall, and what stays free

- ADD: **the entitlement seam is now reactive.** `Entitlement.isUnlocked` is mirrored on `SessionController` as `isUnlocked`, and `setUnlocked` notifies. A gated control has to rebuild the instant a purchase completes, or someone who has just paid is left looking at the button they paid for, still greyed. It still answers true for everyone: nothing can be withheld until the app has a way to take money.
- ADD: **`widgets/paywall.dart`, the one place the app asks to be paid.** A page, not a dialog. The content grows and a long form in an unbounded card is the bug this project shipped four times, with SAVE below a fold that would not scroll; a page has a bounded viewport by construction.
- CHG: it opens CONTEXTUALLY, on tapping a control that would create or change something, and at no other time. Not on launch and not on entering a screen. An on-entry prompt fires at exactly the people the read-only view exists to welcome.
- ADD: one sentence per gated action saying what THAT action would have done, rather than a feature grid. The watchdog sentence carries the most weight, because a locked user opening WATCHDOG sees a screen with nothing on it and is the only case that cannot demonstrate itself.
- ADD: **a 'what stays free' section below the fold**, in the same words used everywhere else: generating standalone configurations is free forever, you can always look at your router, you can always remove things including taking the app back off the router, and the source is on GitHub if you would rather build it.
- CHG: the price shown is the store's OWN localised string, never a hardcoded number. The wrong currency destroys trust instantly and silently. With no store reachable the button reads "Not available right now" and is disabled, which is a real runtime state rather than a placeholder.
- ADD: **gating on the rule that created or changed is paid, removed is free.** CREATE, ENABLE, EDIT and the watchdog's own enable open the paywall; DISABLE, DELETE and VIEW LOG do not. Someone who stops paying attention can always undo what the app did, including uninstalling it from the router, without being asked for money to do it.
- CHG: **the entitlement check runs BEFORE the firmware and dependency checks** on the slots screen. Reversed, a locked user on stock without `jq` is told to go and install packages on their router to reach a screen they cannot use anyway, which is a worse first impression than the price.
- CHG: a control greyed for its own reasons stays greyed and does not become a sales pitch. Selling something that would not have worked anyway is the fastest way to earn a refund.
- TST: ten - four on the seam itself, including that `wipeAll` does not take the entitlement away, and six on the screens. Two of those are a new `router_slots_screen_test.dart` that exists for one property, and it is a property about ORDER rather than output: the same router with the same missing binaries, differing only in who is asking. Swapping those two checks compiles and passes everything else.
- CHG: **the PayPal and PATREON buttons come off the home screen.** Asking for money twice, in two different ways, on the same screen reads as pleading. The Play Store review link stays and is now the last line, with a fixed gap above it so it cannot ride up under the help line on a phone that has to scroll.
- ADD: **`com.android.vending.BILLING` in the manifest.** Necessary, and it turned out not to be sufficient on its own, which is what 443 is about. It is a normal permission: no runtime prompt, no dialog, and it grants nothing on the device.
- DOC: README gains permission 8.4, saying what billing does and does not give the app: Google Play handles the payment, no card number reaches this app or its developer, and the only question the app asks is whether this installation holds the purchase.
- DOC: **TESTING.md gains a "Locked, with no entitlement" section**, and CONTEXT records the gating rule in one place. A rule this easy to state - created or changed is paid, removed is free - is worth writing down once rather than inferring from six call sites.

2026-09-12 v0.8.71 build 441 - the watchdog checks it can survive a reboot

```play
Watchdog reliability, and two device assignment fixes.

The app now checks your router can keep a watchdog schedule across a reboot, and tells you
before you save one rather than failing quietly weeks later.

Fixed: a device sent to the plain internet stayed there, ignoring later changes, until a restart.

Fixed: deleting a VPN returns its devices to the internet, and resets the default connection if
it pointed at the VPN you deleted.
```
- ADD: **stock is checked for the init directory Download Master provides, before a watchdog can be saved.** Nothing checked it, and without `/opt/etc/init.d` a watchdog is not durable. Which way that failed depended on the router and neither was any use: with the directory absent the script write failed and reported a byte-count mismatch that reads like a full filesystem, and with the directory present but no working Download Master the write succeeded, cron installed, and nothing ran it at the next boot. The second is silent, which is the worse of the two.
- CHG: it BLOCKS rather than warns, alongside the existing `jq` check, because a watchdog that stops at the next power cut and says nothing is worse than one never deployed.
- CHG: the message names the cause in the user's terms - "Download Master is not installed on this router" - rather than the missing path. Nobody installs Download Master for its own sake, and naming a directory sends them looking in the wrong place.
- TST: three - the directory is probed and SAVE is disabled with the reason shown, Merlin is never asked because it uses `services-start`, and a stock router with both preconditions met is unaffected.
- CHG: **CI - every workflow run now says WHY it ran.** GitHub titles a run after the head commit rather than the trigger, so tagging a commit that had just been merged produced two runs with the same title. A `run-name` on each workflow puts the event and the ref in the list instead.
- CHG: **CI - the same commit was being scanned three times.** Once for the pull request, once for the merge commit landing on main, and once by the release build before it publishes. The middle one is gone: a commit reaching main came through a checked pull request, and anything released is checked again at the tag. Three runs of fifteen minutes each is what drove development off main in the first place.
- FIX: **the GitHub release note was silently empty.** The parser looked for a CHANGELOG heading by NUMBER - "1.2. Implemented - chronological change history" - and that section became 1.3 when the WIP list was added above it. No match, no blocks, and the release body fell back to the bare string "Release v0.8.70". It now matches the TITLE, anchored to a heading line so the table of contents entry above it cannot match first, and it says so loudly with a `::warning::` when a tag has no block rather than publishing something that looks deliberate.
- CHG: the note carries ONLY the block for the tag being released. It used to collect every block down to the newest published tag, which was right when releases were frequent and would have produced sixty builds of notes after a long gap.
- CHG: the note is no longer sorted alphabetically. That suited three bullets and destroyed a block with commit sub-headings, because the bullets separated from the heading they belonged to. The order a block is written in carries meaning: the most important change goes first on purpose.
- ADD: **the Google Play "what's new" is generated too, from a ```` ```play ```` fence in the release block.** One CHANGELOG block now feeds both audiences: everything outside the fence goes to GitHub, the fence itself goes to Play. They cannot be the same words - Play allows 500 Unicode characters, renders no markdown, and will not make a URL tappable - so a developer preamble sent there arrives as literal asterisks and a dead link, cut off mid-word. Play used to get a bare link to the hosted changelog and the real notes were typed into Play Console by hand.
- ADD: the build FAILS if that note exceeds 500 characters, and warns if a release block has no fence. Both are caught in CI rather than by Play, or worse by nobody. The first draft of this release's own note came in at 512 characters and was refused.
- CHG: **CI - one Quality & security run per ref at a time**, newest wins. Three pushes in a minute used to start three fifteen-minute runs all scanning code that was already superseded, which is how the CPU-minute limit was reached.
2026-09-12 v0.8.70 build 440 - the UI review list

- ADD: **REBOOT ROUTER on the settings screen**, last in the list, behind a confirmation that says what it costs: "Are you sure? This will disconnect all devices including WiFi connections." It clears a ghost service marker BEFORE asking, because a wedged queue discards a reboot request like any other event - measured 2026-09-10, where the web interface reported a reboot that never happened. A recovery control that can silently do nothing is worse than no control.
- CHG: the settings screen loses its "ROUTER" and "THIS DEVICE" headings. Four rows that each say what they touch do not need sorting into categories.
- CHG: **the About version line joins the block it belongs to.** Same size and weight as the rows under it, no blank line between them, and it reads `cfg-pia-wg: v0.8.70 build 440`. It was a larger, heavier line standing over the table, which made it look like a title rather than the first row.
- CHG: `Open source licenses` moves to the END of the links line, so all five destinations read as one set rather than four and an afterthought. The row still wraps on a narrow screen, which is why the test asserts reading order rather than a shared line.
- ADD: a section break above and below that links line - a thin centred grey rule, a quarter of the screen wide. The screen is three unrelated things stacked, and without a break they read as one wall.
- ADD: **README - the device view is the headline feature, and now says so in the introduction.** A router thinks in slots, and finding out which device is using one generally means stopping it to see what breaks. This app lists devices and moves any of them in one tap.
- ADD: README - turn OFF Android battery optimisation for the app, with the setting path. Backgrounding it otherwise freezes the process mid-action: measured 2026-09-11, an SSH session dropped during a watchdog deploy and an alert email abandoned halfway through.
- TST: four - the reboot asks first and CANCEL sends nothing, the ghost marker is cleared before the reboot is sent, the four settings rows are in order with no headings, and the About links read in order with a rule above and below them.
2026-09-12 v0.8.69 build 439 - the service queue stops calling our own commands ghosts

- FIX: **the app was clearing the `rc_service` marker its own call had just set, about a second after making it.** `rc_service_pid` holds the pid of `notify_rc`, which queues the work and exits immediately, so "that process has gone" is true the instant ANY call returns - including one whose service is still running. Every service call in an eighteen-step hardware run on 2026-09-12 logged `cleared stale rc_service marker`, which meant the wait-for-the-queue step was declaring the call a ghost on its first poll and returning without waiting for anything.
- CHG: a marker now has to sit UNCHANGED, with its process gone, for ten seconds before it is called a ghost, and a marker that CHANGES restarts that clock - a queue that is moving is a queue doing its job. A service that is genuinely working clears its own marker when it finishes, so time is the only honest test. The wedge this guards against lasted ninety minutes; the wait costs nothing.
- INF: two consequences of the old behaviour. The wedge guard was not doing its job, because it cleared any marker on sight rather than telling a hung service from a call in flight. And the warning fired on every action, which is the surest way to train someone to ignore the one line that matters.
- TST: four - a service that finishes normally is waited for and nothing is cleared, a marker that never moves is cleared once it has sat long enough, a queue moving through three different services is never called a ghost, and the pre-call guard waits before deciding too.
- DOC: **the service-queue section is rewritten as one story rather than a claim with a correction bolted on.** It said `rc_service_pid` was what made a wedge recoverable, and then contradicted itself two paragraphs later. A reader met the wrong idea first. It now runs: how the queue works, what a wedge is and what ninety minutes of one looked like, why the obvious test fails, and a table of what the app actually does in each of the five situations. The table describes the current code rather than the code from two builds ago.
- DOC: the section opens with an OVERVIEW before any mechanism - what the queue is for, what a jam looks like from the outside, and why it earns a section. It went straight into NVRAM keys, which tells a reader how before telling them why they should care.
- DOC: CONTEXT carried the same wrong shortcut in two places - "clears a ghost marker (key set, pid gone)". Both now say what the ten seconds are for.
2026-09-11 v0.8.68 build 438 - deleting a VPN takes the default connection with it

- FIX: **deleting the VPN that WAS the default connection left the default naming it.** `vpnc_default_wan` is a key of its own, not a policy record, so releasing the per-device pins never touched it. Every device following the default then read as "profile 9", and the firmware was being told to send unassigned traffic to a profile that no longer existed. Reported on hardware 2026-09-11. DELETE now puts the default back to Internet when it is deleting the profile the default names, and leaves a default naming any OTHER profile alone.
- CHG: **released devices go to Internet, not to the default connection**, which is what the web interface does. Sending a device that was explicitly pinned onto whatever tunnel the default happens to name is a destination nobody chose. The record is `1>IP>>0>`, a pin to the WAN, and the `lookup main` rule that goes with it is kept rather than swept.
- CHG: a profile index no record carries reads `profile 9 (deleted)` rather than a bare `profile 9`. Short deliberately: it renders inside a device row on a phone.
- INF: `restart_default_wan` resets the key to 0 as it runs, so returning the default to Internet needs no write at all - the teardown half of the sequence is the whole of it.
- TST: three on the service - the default is reset when it names the profile being deleted, left alone when it names another, and not touched when it already reads 0. The pure tests now assert the Internet pin rather than a fall-through to the default.
- DOC: ARCHITECTURE and README both record it.
- DOC: TESTING gains "The full assignment run" - one sequence covering moves, deletes and the default connection, in the order that reaches all three faults measured on 2026-09-11. Written to be worked from on a phone.
2026-09-11 v0.8.67 build 437 - the save spinner, fixed in a way that cannot come back

- FIX: **the watchdog save spinner sat below the fold.** Fixed in 409, back in 412, fixed again in 425, back again in 435. Every one of those fixes dismissed the keyboard, waited for something, then scrolled the SAVE button into view, and every one was a race against two animations that a single early frame could lose. The spinner is now a full-screen overlay in a `Stack` above the page, so it is not in the scroll view and has no fold to be below. Nothing is left to race.
- CHG: the SAVE button keeps its label during a save instead of turning into a spinner. That is what put the one thing the user needed to see inside the scroll view in the first place, and it also leaves a grey blob where the label was, which reads as the button breaking.
- CHG: focus is still dropped on save, so the keyboard retracts and the last-edited field loses its green border - the other half of what made a save look like nothing had happened. Nothing waits on it any more.
- TST: the STRUCTURAL property, which is the only form of this a later change cannot quietly undo: the progress overlay must have no `Scrollable` ancestor, must cover the whole screen, and the SAVE button must still be showing its label. Put the spinner back in the button and it gains a scrollable ancestor and the test fails.
- DOC: CONTEXT carries the rule beside the "a long form belongs on a page" one it belongs with.
2026-09-11 v0.8.66 build 436 - a device that had been on Internet was stuck there

- FIX: **once a device had been assigned to Internet, every later assignment had no effect until the router was rebooted.** Pinning a device to the plain internet makes the firmware write `from <ip> lookup main` at priority 100, and the stale-rule sweep matched `lookup <digits>` only - so that rule was invisible to it. Every later move added its own numeric rule underneath, `main` was still listed first, and at equal priority the kernel takes them in order. NVRAM, the web interface and the app all agreed the device was on wgc5 while its traffic went out of the WAN. Reported on hardware 2026-09-11.
- CHG: the sweep matches the routing table by NAME rather than by number, and knows that index 0 is supposed to have `lookup main` - so moving TO Internet keeps that rule and moving off it removes it.
- INF: the `from` address is what keeps this safe. The global `32766: from all lookup main` and the priority-10000 `from all iif br0` default-connection rules name `all` and never a device, so a per-device sweep cannot reach them however the table is written.
- TST: four - moving off Internet sweeps `lookup main`, index 0 keeps it, returning to the default sweeps both, and no rule belonging to `all` is ever returned for a device.
- DOC: ARCHITECTURE records the measurement beside the stale-rule section it corrects.
2026-09-11 v0.8.65 build 435 - the last of the test-pass list

- ADD: **CREATE GITHUB ISSUE fills in the router model and firmware.** They were placeholders a reporter had to look up, so nobody did. Both come from two extra reads on a round trip the About screen already makes. A reporter on an unsupported router or an ancient firmware is the case this answers, and the issue is editable before it is submitted.
- ADD: **a malformed DNS address is refused on GENERATE**, naming the entry that is wrong and leaving it on screen to correct. A config generated with "149.137" in it resolves nothing and the tunnel still comes up looking healthy. The range is not checked - an unusual resolver is the user's business - only that the address is four numbers.
- CHG: **one DNS server is now a legitimate choice.** A single entry used to be topped up to two from the defaults, which quietly overrode a user who had typed exactly what they wanted. The defaults fill an EMPTY field and nothing else.
- CHG: the watchdog SAVE button reads **SAVE & SELECT REGION**, because a region picker follows it, and the overwrite prompt no longer describes that next dialog.
- CHG: "Boot persistence script written to ..." is now "updated". Pausing a watchdog rewrites that file too, and "written to" read as though a pause had redeployed something.
- CHG: the watchdog alert for a region PIA has stopped listing says so. It blamed the slot description, which is only one of the two causes - a region can drop off PIA's list and come back, which is what took a CREATE down on 2026-09-11. Needs a redeploy per slot to take effect.
- TST: two - a malformed DNS entry is refused and not corrected behind the user, and the SAVE button says what it is about to do.
2026-09-11 v0.8.64 build 434 - colour in the router log

- ADD: **the router log picks out the app's own lines in colour.** This app's lines are teal, the watchdog's are amber, the router's own stay grey. A page of syslog is otherwise a wall of identical text and the lines anyone opened the screen for are a handful among hundreds.
- INF: both the app and the deployed watchdog write under the tag `cfg-pia-wg`, and the only thing separating them is the interface prefix the script adds to every line. Giving the script its own tag would be unambiguous, but a tag change reaches a router only on its next watchdog deploy, so every router in the field would go on emitting the old one. The prefix costs nothing and works today.
- CHG: the whole page is still ONE text run, so selection and COPY are unchanged - a widget per line would have broken both.
- CHG: the watchdog log opens scrolled to its newest entry, matching the app log and the router log.
- TST: four on the classifier - the app, the watchdog, a two-digit interface, and that naming an interface in a kernel line is not the same as being tagged by us.
2026-09-11 v0.8.63 build 433 - the app log reads like the other two log screens

- CHG: **the app log is built like the router and watchdog logs.** The log fills the screen, and COPY / CLEAR / HOME sit in one pinned row of equal-width bordered buttons at the bottom. CLEAR used to be a small button in the top right corner and there was no COPY at all.
- CHG: it opens scrolled to the NEWEST entry. The reason anyone opens a log is to see what just happened; opening at the top meant scrolling past a session to reach it.
- CHG: the "LOG" field label above the panel is gone. The screen is the log.
- ADD: **a third log severity - warning, in amber.** Red was being spent on things that need no action, and a log where most of the red is routine is a log nobody reads.
- CHG: "Router SSH connection dropped; reconnecting" is a warning, not an error. The app reconnects by itself, and a genuine failure to connect is still reported in red by whatever was trying to run.
- CHG: **the stuck-router-command message says what it means.** It read "The router was still marked as running stop_vpnc, but that process (pid 11025) has gone" - the router's own bookkeeping, with the consequence buried at the end. It now reads "The router was stuck on an earlier command and would have ignored this one. Cleared it and carried on - nothing for you to do", in amber, with the pid and the service name written to the ROUTER syslog where the detail belongs.
- TST: five on the new screen - it opens at the newest entry, carries the three buttons and no field label, COPY takes the log verbatim and arms no clipboard countdown, COPY and CLEAR grey out on an empty log, and a warning renders amber where an error renders red.
2026-09-11 v0.8.62 build 432 - deleting a VPN releases the devices pinned to it

- FIX: **a device pinned to a deleted VPN kept its pin, and silently moved to whatever region was created in that slot next.** Stock names a pin by the profile's index 6 and never releases one, so after a DELETE the record went on naming an index that no longer existed: the web interface could not show it, this app could only call it "profile 5", and the device's traffic followed that index wherever it led. Reported on hardware 2026-09-11. DELETE now sends those devices back to the default connection before the profile goes, and NAMES each one it moves - in the app log and in the router syslog.
- FIX: the routing rules went with them. Stock leaves a device's old `ip rule` in place on a reassignment and does the same on a delete, so a released device would have kept using the deleted profile's routing table until something else cleared it.
- CHG: the overwrite confirmation says what overwriting actually does to assignments. The profile survives a CREATE over an existing slot, so every device pinned to it stays pinned and starts using the new region without being asked. Stock only.
- DOC: README - a device assigned to a tunnel that is merely turned OFF keeps its assignment and falls through to the default connection until it comes back. That is different from deleting, and the two were not distinguished.
- TST: seven - which devices a profile index holds, that index 0 is not a pin, that releasing rewrites only those records, that a record naming an OpenVPN profile survives byte for byte, and on the service side that a delete releases and names the pinned device, removes its stale rule, and writes no policy list at all when nothing was pinned.
2026-09-11 v0.8.61 build 431 - CREATE tells the truth, and so does the uninstall button

- FIX: **CREATE announced success after a failure.** The slot runner reported the error and returned nothing, so CREATE went on to say "wgcN has been created. Remember to ENABLE it" over the top of the error saying it had not been. It now reports whether the work completed, and the confirmation only fires when it did.
- FIX: **a CREATE could fail on a region the picker had just offered.** The region list was fetched twice - once for the picker, once inside `generateConfig` - and a region with no WireGuard servers in the second snapshot is dropped from it. Reported on hardware: `ca_ontario` was picked at 12:09:17 and was not in the list fetched at 12:09:23. The record the user chose is now carried into the generate instead of being resolved again. A typed region id still resolves by fetching, because that field is free text.
- CHG: a failed ENABLE now explains itself in the dialog - PIA configurations expire on PIA's own rotation interval, so one created and left unused can go stale. Deliberately NOT written to the app log, where it would be noise on every scroll and the error itself is already recorded.
- TST: four - a handed-in region is used without a second fetch, a handed-in region for a different id is ignored and resolved normally, a failed CREATE announces nothing, and the stale-config hint reaches the dialog but not the log.

- CHG: the working agreement on NVRAM keys now says what each document is for. Every key is NAMED in CONTEXT §4.9 and EXPLAINED in ARCHITECTURE, and the explanation is deliberately not copied into both. CONTEXT is the only file guaranteed to be read at the start of a session, so a key missing from it can be written past; ARCHITECTURE is what a user audits.
- FIX: **CONTEXT said the main menu had four screens and that VPN device assignment was drawer-only.** It has been the fourth button on the menu since build 414. The README was wrong the same way and listed five choices where there are six.
- FIX: the destination table described the main-menu suffix as a star. It is a superscript numeral, and there are two of them - ¹ for "needs SSH" and ² for "stock firmware only".
- FIX: CONTEXT claimed 29 test files. There are 54, plus five shared harnesses.
- FIX: the destination table had the standalone screen's title wrong.
- FIX: the UNINSTALL note on SETTINGS read "Tunnels, watchdog settings and cron entries are left alone". Only the tunnels are: since build 425 the uninstall also removes every watchdog schedule it created and every NVRAM key the app wrote, history included. The confirmation dialog behind the button had it right all along, so the button was the one screen element contradicting both the dialog and the documentation.

2026-09-11 v0.8.60 build 430 - documentation rebuild

One build, sixteen commits. Newest on top. Four documents rebuilt in the order they depend on
each other: ARCHITECTURE, then TESTING, then README, then CONTEXT.

b8f2356 CONTEXT - name the symbol, not the line, and point rather than repeat

- FIX: **seven references to a specific line range, every one of them wrong.** All of those files moved this week and nothing reported it. They now name the SYMBOL - `SlotModal._runSlot`, `navigateToDestination`, `WatchdogDialog._save`, `RouterWatchdog.deployWatchdog`, `createConfigToSlot`. A symbol either exists or a grep for it fails loudly; a line number rots in silence.
- CHG: the 17-key table and the `vpnc_clientlist` field table point at ARCHITECTURE for what a key MEANS and keep only what the APP does with it. Two documents describing the same firmware is two documents to keep right.
- CHG: nine passages that only recorded what changed are gone - which build made the slot list a page, which one moved a button, which gate used to exist. The ones that give the REASON a rule exists are kept in full: spinners cleared before awaiting a modal, never a dialog for a long form, one SSH connection per session, and why the backoff counter counts attempts rather than checks.
- FIX: FORGET ROUTER IP was documented as living on ABOUT. It is on SETTINGS.

003866b CONTEXT - the device assignment screen exists

- ADD: **4.14 Device assignment.** The feature was mentioned four times in 492 lines and was absent from the call graph, so a session reading this file would not have known the screen was there. It now covers the eight-source read, why staged changes live on the session, the conflict check before any write, the light service pair, and the stale `ip rule` sweep.
- CHG: the snapshot said the drawer added one destination. It adds four.
- ADD: the destination table gains the device screen, and the session-state table gains `canReuseRouterSession` and the two staged-assignment fields.
- ADD: the call graph gains the three drawer-only screens.
- FIX: a "see 4.14" that pointed at a section which did not exist.

0d80d6a README - the last gaps, and the last section numbers

- ADD: the watchdog's ENABLE and DISABLE actions, and the PAUSED badge. The README listed CREATE/EDIT, DELETE and VIEW LOG and stopped there.
- ADD: what is actually on the Settings screen - the uninstall, DEL PIA CERT, and FORGET ROUTER IP, which is the only thing the app keeps on the phone.
- CHG: the last three references to a README section NUMBER - two in ARCHITECTURE, one in a `lib/` comment - now name the section.

3778bcb README - what the app does to your router, and how to check it

- CHG: **section 7 answers the question it asks.** It was a paragraph of reassurance and a link. It is now the whole list: what a slot change writes, what a watchdog deploy writes - including that your PIA and SMTP passwords sit in NVRAM in plain text - what makes the schedules survive a reboot, and what the app never does.
- ADD: **the uninstall exists**, said plainly in the section where someone is deciding whether to install. It takes the app off and leaves your tunnels alone.
- ADD: **9.1 How to check the watchdog script yourself.** The app asks a user to let it run a script holding their PIA password as root on their router forever. "You can read it" is the whole answer, so it now says where the script is, that it is never obfuscated, that a test fails the build if the deployed text and the repo template drift apart, and that every file the app writes says so on its second line.
- ADD: bug reports under section 11, where a reporter actually looks - CREATE GITHUB ISSUE on the About screen opens a report with the build details filled in. Section 13 keeps the joke.

b889bfd README - the screens as they are now

- ADD: **5.4 VPN device assignment**, which the README had never mentioned. What it is for, how to use it, and the four things that surprise people - a device with no known address cannot be assigned, assigning one pins its address for good, a randomised MAC breaks the assignment silently, and **this is not a kill switch**.
- ADD: the two hamburger entries that were missing - View router log and Settings.
- ADD: the About screen reports the watchdog script version deployed on the router, and the running count of successful and unsuccessful reconfigures since the app first configured it.
- CHG: on stock the app installs `jq` and `mailsend-go` itself, showing the source, the destination and the checksum it verifies. `get-bins.sh` stays, and now says why Merlin still needs it: the in-app installer writes to an `/opt` area only stock has.
- FIX: the autofill tip described a prefilled `admin` username that no longer exists.
- ADD: SMTP alerts need an app password, not the account password, with the shortest possible route to one for Gmail and Outlook.
- ADD: a note that the slot EDIT screen is shorter on stock - the kill switch and inbound firewall are Merlin features.

dc46331 TESTING - a test that every Markdown link resolves

- ADD: `test/unit/markdown_links_test.dart`. Every link between the repo's own Markdown files must resolve, both the file and the anchor. Anchors are generated from heading text, so any reword silently breaks every link into that heading - and a rewrite is exactly when a written-down rule gets forgotten. Same approach as the LAN-identifier guard: a rule nobody can forget beats one written down.
- INF: it reproduces GitHub's slug rule, including the two details that would otherwise produce false failures - each space becomes its own hyphen, so `A & B` yields a double hyphen, and a heading indented up to three spaces is still a heading.
- INF: `.claude/plans/` is out of scope. Those record what was believed at the time and are not kept current.

b8257a6 TESTING - pass 2, the things a tester could not guess

- ADD: **"When something looks broken, check these first"**, second section in the file. The wedged service queue, curl refusing a caller with `crond` in its ancestry, and a stale `ip rule` after a reassignment. Each presents as a completely different fault, and a tester following this document last week would have had no way to find any of them.
- ADD: a device assignment section. It was not covered at all, and the default-connection test drops every tunnel on the router for about a minute - so it carries the same warning treatment the watchdog tests already had.
- ADD: sections for the router log and for SETTINGS, including the check that matters most - run UNINSTALL twice and confirm the second run deletes nothing.
- CHG: the email section leads with the TEST EMAIL button and is now "how to test this by hand when that fails". It also says, for the first time, that stock sends through `mailsend-go` and Merlin through BusyBox `sendmail`, and gives the stock command.
- CHG: "files deployed to the router" was out of date on every point - the second init script, the header line both now carry, the installed binaries, and what an uninstall does and does not remove.
- FIX: two cross-references pointing at a numbering no document has used for weeks.

a5727f1 TESTING - pass 1, one section per thing a user does

- CHG: the end-to-end manual test moves from the bottom of the file to the top and becomes the spine. Its nine checklist items are now sections, in the order a user meets them, and the material that used to sit above it - email, watchdog checks, NVRAM - is filed underneath the function it belongs to.
- CHG: stable `<a name>` anchors on all 25 headings, keyed on the title rather than the number, and a regenerated TOC. Same convention as ARCHITECTURE, so a link into either survives a renumber.
- INF: position and heading level only. A word-level comparison of the file before and after accounts for every line: nothing is lost except the old TOC, three section labels absorbed into the sections that replaced them, and the `<br>` separators the old checklist used.

aa19ac4 ARCHITECTURE - pass 3, narrative

- ADD: an opening. What the app does, the one idea needed before any of the detail makes sense - the two firmwares drive WireGuard in completely different ways - and where to start reading when a firmware update breaks something.
- CHG: the six provisioning steps say what they do rather than describe themselves. The certificate step now records what actually happens: the PIA root is fetched at runtime, the platform trust store is turned off for the call, and the server certificate is accepted only when its Common Name matches.
- ADD: "What happens when the tunnel drops" is its own section. The rule that decides whether an assignment fails closed or leaks was buried inside a section about DHCP reservations, in a blockquote, three screens from the heading.
- FIX: the plain-language walkthrough of a push never said it was the Merlin path. It uses `stop_wgc` and `start_vpnrouting0`, neither of which exists on stock.

8ad63ce ARCHITECTURE - pass 3, stale claims and internal references

- FIX: fourteen references to ARCHITECTURE's own section NUMBERS, every one of them pointing at a numbering the document stopped using. The earlier pass caught the references FROM other files and missed the ones inside this one. All now name the section, and a link check confirms all 99 resolve.
- FIX: "the app does not write any of this yet", at the head of the device assignment section. It has written it since build 421.
- CHG: the last of the two-cost model removed from the sections that leaned on it - the reserved/unreserved table, the reservation-is-permanent finding, and the removal warning. The distinction the screen needs is still reserved versus not; the reason is now that an unpinned address moves and takes the assignment with it, not that writing one bounces the LAN.

c2efe95 ARCHITECTURE - prior designs appendix

- ADD: an appendix holding two readings that were believed, acted on, and then measured to be wrong: the two-cost model for applying a device assignment, and placeholder records in the policy list. The working that produced each one is kept, because an idea that fitted the evidence once will fit it again.
- CHG: a one-line retraction stays where the wrong idea would occur to a reader, with a link to the long story. Moving a retraction to the back of a document invites exactly the rediscovery it was written to prevent.
- CHG: "the tunnel must be disabled before its assignments can be changed" corrected. That is what the web interface does, not what the firmware requires - the app changes assignments on a running profile and they take effect.
- CHG: the starting-state section now leads with the fact rather than the correction. An untouched router has an EMPTY policy list, so the screen renders "everything on the default connection" from an empty string.
ae1e78f ARCHITECTURE - diagrams: watchdog run and reconfigure flows

- ADD: two flowcharts for the router-side script. "When it runs" covers the detach, the enable check, the handshake and ping tests, the backoff and the WAN gate - most runs do nothing, and everything before the expensive path exists to avoid taking it. "What a reconfigure does" covers the twelve steps that follow, each of which can abort.
- ADD: the reason each gate exists, beside the gate. Why the detach is there, why a tunnel switched off by hand is not an outage, why ping alone is not a liveness test on stock, and why a missing WAN exits silently without alerting.
- CHG: the email flow is documented as a BRANCH of the reconfigure rather than a diagram of its own. `send_alert` is called from exactly two places, and a failure and its recovery are two halves of one story.

bff134a ARCHITECTURE - diagram: the three numbers that name one profile

- ADD: a diagram of the profile identity problem, with a worked example from a real two-profile list. One WireGuard profile is named by its slot, its clientlist ROW and its index 6, and every one of those is used somewhere - keys and interface by slot, `vpnc_unit` by row, default connection and device pinning and routing table by index 6.
- INF: this caused more wrong guesses during development than anything else, and prose never fixed it. It also records why `5 - slot` looked right for so long: the web interface can only create profiles in descending slot order, so on any list IT built the row and `5 - slot` agree.

bed9375 ARCHITECTURE - firmware dependency register

- ADD: **"What this app depends on ASUS not changing"**, immediately after the overview. Ten assumptions, each with where the detail lives and what breaks if that assumption fails - because when a firmware update breaks something, the failure almost never looks like its cause. This is the section the document exists for.
- ADD: USB storage for Download Master, moved out of the README, beside the boot hook it is a prerequisite of. The README keeps three sentences and a link.
- INF: the register carries the "how it fails" column deliberately. A wedged service queue looks like a failed command; a rejected curl looks like a network problem; a stale routing rule looks like an assignment that was never written.

4827ba0 ARCHITECTURE - reference sections by title, not number

- CHG: 26 references to ARCHITECTURE section NUMBERS, across ten files and six `lib/` comments, now name the section instead. A number changes whenever the document is reordered; a title does not, and a wrong title is visible where a wrong number is not.
- INF: five of them were already wrong before this run. `ARCHITECTURE.md 2.3.1` and `2.3.2` pointed at a numbering the document stopped using some time ago, and nothing could have told us.
- CHG: comments only in `lib/` and `test/`; no behaviour changed anywhere.

e79ea61 ARCHITECTURE - pass 1, restructure

- CHG: high level first, then deeper. SSH commands now precede the NVRAM reference, because how the app drives the router is the shape of the thing and the field list is detail.
- CHG: section 3 split in two. At 566 lines it was half the document; device assignment is now its own top-level section.
- CHG: every heading renumbered in document order. Subsections had drifted out of sequence - 3.3.5b sat above 3.3.5a, and the uninstall was described before the service queue and init scripts it depends on.
- ADD: a stable `<a name>` anchor on all 58 headings, keyed on the TITLE rather than the number, so a future renumber cannot break a link into this document. The TOC is regenerated against them.
- INF: movement only. Every prose line in the file is byte-identical to the previous version; the diff is relocation, nothing else.

2026-09-11 v0.8.59 build 429 - CONTEXT.md knows about the whole app again

- FIX: **CONTEXT.md section 3 listed 28 files when `lib/` holds 44.** The sixteen missing ones were everything added since device assignment landed - both halves of device assignment, the router service queue, log paging, the binary installer, router prefs and command, the entitlement seam, the settings and router log screens, and four widgets. A reader of the file the app is documented in would not have known the assignment screen existed.
- CHG: two stale counts corrected in place, and a line count dropped from the `router_watchdog.dart` entry that had been wrong for several builds. Counts in prose rot silently.
- ADD: the ARCHITECTURE.md and CONTEXT.md rewrite plans, alongside the README and TESTING ones, so all four are in the repo rather than in drafts.

2026-09-11 v0.8.58 build 428 - an uninstall that finishes the job

- FIX: **a second uninstall deleted the router's own boot scripts.** The first run restored them, and the second found files it did not recognise and removed them. Both replacement scripts now carry `auto-generated by cfg-pia-wg` as their second line, and the uninstall will not delete a file without it - `S50downloadmaster` had only its REPLACEMENT markers, which a restored original does not carry either. Reported from hardware.
- ADD: **the uninstall removes the watchdog cron entries and every NVRAM key the app writes.** A `cru` entry pointing at a script that has just been deleted fires every few minutes forever and does nothing but log a failure, and fifteen settings left in NVRAM are fifteen things the next person has to wonder about. The `wgcN_*` TUNNEL keys are deliberately untouched: this removes the app, not the user's VPNs, which stay manageable from the web interface.
- ADD: a second confirmation before an uninstall, carrying a Play Store review link - the one moment in the app where asking is fair, because the user is leaving and why they are leaving is the most useful thing they could tell us. Bold red UNINSTALL beside teal CANCEL, both in house style.
- CHG: the result now ends with an amber "Please restart your router." The cron entries are gone but a running watchdog process is not, and the firmware keeps its own idea of what is configured until it restarts. Its lines lost their full stops - it is a list of outcomes, not prose.
- CHG: **the "unable to locate" notice lists one path per line and offers to INSTALL.** As a comma-separated sentence the paths ran together with the words around them, and telling a user what is missing then leaving them to find the install elsewhere is a dead end when the app can do it from here. The unsupported-firmware notice offers nothing, because there is nothing it can fix.
- DOC: ARCHITECTURE.md 5.2.2 records what an uninstall leaves behind, and a NOTE that a DISABLED default connection does not block traffic - observed with everything uninstalled and every device pointed at a disabled wgc5, LAN traffic left via the WAN. The default connection is not a kill switch.
- TST: nine - a script without our header being left alone, the header grep itself, cron and NVRAM removal including all five slots and the tunnel keys being spared, the second confirmation and cancelling it touching nothing, the restart line, the notice listing paths per line, and INSTALL appearing only where it can help.

2026-09-11 v0.8.57 build 427 - naming things the same way everywhere

- CHG: **a tunnel is `wgc1:pia-aus_melbourne` everywhere now.** The device assignment screen wrote `wgc1 - pia-aus_melbourne` while every log line, email and slot heading in the app used the colon form, so the same tunnel looked like two different things depending on which screen you were on. Rows, the picker, the apply confirmation and the router log line for a default-connection change all go through `slotLabel` now.
- CHG: the picker lists tunnels in wgcN order within the active and disabled groups. It came back in `vpnc_clientlist` order, which is creation order, so a router built out of sequence showed wgc4 above wgc3.
- CHG: an active watchdog is teal in the picker. It is the one fact there worth spotting while choosing, so it is the one that is not grey.
- ADD: **every device reassignment is written to the ROUTER log**, not just the app log. The app log dies with the app, and a reassignment that explains where a device's traffic went weeks later has to survive that.
- CHG: APPLY and DISCARD CHANGES share one centred row at HOME's height, and DISCARD CHANGES is capitalised like every other button label.
- ADD: **the watchdog reconfigure history on the ABOUT screen**, set apart from the build info because it describes the router rather than the app: "Since 2026-09-01: 4 successful & 1 unsuccessful reconfigures". The same three NVRAM counters the alert emails carry, shortened for the width.
- INF: absent entirely when the router has never recorded any, so an untouched router shows no empty gap. Both ABOUT rows come from ONE round trip, which is also why tapping either row's login link fills in the other.
- TST: seven - the wgcN ordering, the teal watchdog note, the button row and its capitals, the history line rendering, no history row when there are no counters, one round trip for both rows, and the reassignment reaching the router log.

2026-09-11 v0.8.56 build 426 - two log screens that behave the same

- FIX: **the router log showed only its last 41,644 characters.** It tailed 500 lines, and `/tmp/syslog.log` reached 512 KB in a day on the test router. It now opens on the newest 32 KB and pages BACKWARDS on demand: scroll near the top and the next page is fetched, with the scroll position corrected so what you are reading does not move under you.
- ADD: paging continues into the ROTATED log. The firmware rotates to `syslog.log-1` rather than truncating, so the history a user wants can span two files and three quarters of a megabyte. It stops at the start of the older file and says so.
- INF: each page is one command - `tail -c <total> file | head -c 32768` - so the router does the seeking and only 32 KB crosses SSH however far back you scroll. Every page but the oldest starts mid-line and has that fragment trimmed, or half a timestamp appears at the top of the screen.
- ADD: **a COPY button on the router log**, taking everything loaded. Android places its own Copy/Share toolbar relative to the SELECTION, so on a full-height selection it lands on the app's own buttons - which is how a tap meant for Copy cleared the watchdog log on 2026-09-10. An in-app copy removes the need for the system toolbar in the one case where it gets in the way. It cannot be fixed by layout: nothing the app does moves where Android puts that toolbar.
- CHG: both log screens now carry the same row of three bordered, equal-width buttons - COPY REFRESH HOME and COPY CLEAR CLOSE. They were bare TextButtons and read as three unrelated links.
- CHG: the watchdog log lost its left and right margins. It is a wide monospace block and every column lost to padding is a wrapped line.
- TST: fifteen - the paging arithmetic including the second page ending where the first began, a short last page, continuing into the rotated file, exhaustion, a missing rotated log, and the partial-line trim; plus the screen reading on entry, REFRESH starting again, COPY taking everything without arming the clipboard countdown, and both button rows being bordered and in order.

2026-09-11 v0.8.55 build 425 - one control, one size

- FIX: **HOME was a different width on different screens.** Full width on ABOUT and DEVICE ASSIGNMENT, 480-wide on SETTINGS, MANAGE and WATCHDOG - because those screens cap their body width on a tablet and the cap was being applied to the button as well. The cap is for content, not for chrome. Reported from a tablet.
- DOC: CONTEXT.md carries it as house style now: one control, one size, on every screen. The two log screens are the deliberate exception, since a row of three buttons cannot also be one full-width button.
- TST: HOME is wider than the content cap on a 1200-wide screen while the slot rows are still capped.

2026-09-10 v0.8.54 build 424 - surviving a wedged rc_service

- FIX: **the app now survives a router that has stopped accepting service commands.** Every `service` call goes through `notify_rc`, which records what it is doing in `rc_service` and clears it when done; a call finding that key set waits 15 seconds and then DISCARDS itself. A service that never finishes never clears the key, and from then on the router silently throws away everything sent to it. The app clears a ghost marker - key set, pid gone - before every service call, and waits for the key to clear afterwards.
- INF: measured on hardware 2026-09-10. `restart_vpnc` hung at 17:40 and the router spent ninety minutes discarding events: four watchdog reconfigures fetched a PIA token, registered a key and wrote a complete config that nothing acted on. It discarded a `reboot` request too - the web interface said it was rebooting and it was not - so a power cycle was the only way out.
- ADD: `RouterServiceWedgedException` for the one case the app cannot fix, a marker whose process is still alive. It names the service and says to power cycle, rather than reporting a fifth opaque "router command failed (exit 1)".
- FIX: **an interface seen up once is no longer called up.** The app reported "wgc1 enabled" a second after `restart_vpnc` because it caught the interface mid-restart, then ran the deploy script against a tunnel on its way back down. Two consecutive sightings are required now.
- INF: the thirteen zombie watchdog processes seen during the wedge were a symptom of it, not of the detach guard added in 416. Each wedged run sat through three 15-second waits before failing; five healthy runs since have left none.
- TST: twenty - the marker parser including a probe that does not parse reading as idle, clearing a ghost but never a live marker, the clear happening BEFORE the service call, an idle router not being written to, a service dying mid-wait, the wedged exception and what its message must say, and an interface sighting that does not persist not counting as up.
- DOC: ARCHITECTURE.md 5.2.0 records the queue, the ninety minutes, and the power cycle.

2026-09-10 v0.8.53 build 423 - ask before connecting, and a log you can select from

- FIX: **three screens tried to connect to 192.168.50.1 instead of asking for credentials.** Reported from a tablet that had never logged in. Opening MANAGE writes the FACTORY DEFAULT address into the session before the user types anything, so the test "are these three fields filled in" said yes for a session that had never reached a router. DEL PIA CERT, the ABOUT script-version link and the router log now all ask `canReuseRouterSession`, which requires a connect to have actually succeeded.
- FIX: **the watchdog log viewer is a full screen, not a card.** Selecting the whole log put Android's own Copy/Share toolbar directly over the action row, and a tap meant for Copy landed on CLEAR. There is now 72px of empty space below the last line for that toolbar to sit on.
- CHG: the ABOUT links are one pipe-separated line - ReadMe | Change log | Security policy | Privacy policy - wrapping with a 14px gap so the second row is still comfortably tappable.
- ADD: the GitHub issue body carries the deployed script version, or UNKNOWN. It used to carry whatever the screen was showing, and "login to router to retrieve" is an instruction to the user standing in front of the app rather than anything the reader of an issue can use.
- CHG: SETTINGS says "No router SSH credentials are stored on this device" rather than "Credentials are never stored at all", which claimed more than the app can promise about the router end.
- CHG: `Router command failed` is lowercase at source, so it reads correctly where it appears after a colon.
- TST: four - a filled-in but never-connected session still gets the prompt, a connected one does not, the issue body says UNKNOWN rather than the login prompt, and the log viewer is a page with CLEAR between COPY and CLOSE.

2026-09-10 v0.8.52 build 422 - uninstall and new menu

- ADD: **SETTINGS, a drawer screen for everything that removes something.** It carries a new uninstall that puts back the two boot scripts the app replaced and deletes `/jffs/cfg-pia-wg`, in that order - so a failure at the last step still leaves a router that boots the way it originally did. Where no `.old` backup exists the app's own copy is removed rather than left behind, and the result says which of the two happened for each script.
- INF: the uninstall deliberately leaves cron entries, NVRAM and the tunnels alone, and the prompt says so. They belong to the watchdog and the slots, which have their own DELETE; an uninstall that silently tore down a working VPN would be a much bigger action than the button says.
- CHG: DEL PIA CERT and FORGET ROUTER IP moved from ABOUT to SETTINGS. ABOUT is a page people open to read, and those two sat among the build metadata and the licence text. Each now carries a line saying what it removes.
- ADD: **View router log**, a drawer screen showing the last 500 lines of `/tmp/syslog.log` with REFRESH and HOME. Every alert email and half the failure messages in this app end with "check your router log", which until now meant leaving the app for an SSH client. It opens scrolled to the newest lines and the text is selectable without arming the clipboard countdown.
- ADD: **the deployed watchdog script's version in the ABOUT build info**, above `Built by`. The app updates from the store while the script only changes on a deploy, so a user can be running a build whose fixes never reached their router. Filled in for free when the session already has a connection; otherwise the row offers "login to router to retrieve", and says "not deployed" when the router has no script at all.
- INF: a refused login leaves that link in place rather than reporting "not deployed" - that would be a different answer to a question we never got to ask.
- ADD: a CLEAR button on the watchdog log viewer, between COPY and CLOSE. It truncates rather than deleting: the script appends and never creates, so removing the file would lose every line until the next reboot.
- CHG: the ABOUT links are the labels themselves now, not label plus URL. A raw GitHub blob URL is 70-odd characters that wrap across two lines on a phone and tell the reader nothing. "Open source: licenses" became "Open source licenses", tappable end to end.
- ADD: `SshCredsDialog`, shared by ABOUT, SETTINGS and the router log. All three are reachable without ever visiting a router screen, so each needs a way to ask for credentials rather than sending the user away.
- TST: eighteen - the uninstall's order and its two outcomes per script and what it must not touch, the prompt naming what survives, the router log tailing rather than reading whole and refreshing and offering selectable text, the script version read without a prompt when there is a session and offered as a login when there is not and "not deployed" when there is no script, CLEAR sitting between COPY and CLOSE and truncating rather than deleting, and the SETTINGS actions stacked with their explanations.
- DOC: ARCHITECTURE.md 5.2.1 and CONTEXT.md 4.1 record the uninstall and the two new destinations.

2026-09-10 v0.8.51 build 421 - device assignment: say what is on, what changed, and what default means

- FIX: **a device pinned to the plain internet was shown, and rewritten, as though it followed the default connection.** The router models both - `1>IP>>0>` pins and ignores the default, `0>IP>>0>` follows it - and `isAssigned` collapsed the two. The picker now offers *default* and *Internet* as separate choices, which also ends the complaint that with one tunnel configured it listed the same profile twice.
- CHG: **a row that follows the default now says what the default is** - "default - wgc1 - pia-aus_melbourne" rather than "default". Reading the old label meant holding the default connection in your head while going down a dozen rows. It follows the STAGED default when one is pending, so the list says where those devices will be after APPLY.
- ADD: the picker tags each tunnel teal **Active** or amber **Disabled**, the colours the slot modal uses for the same facts. A tunnel that is down accepts an assignment happily and then carries no traffic, which is a slow thing to work out from the outside.
- FIX: **staged changes survived leaving the screen and coming back.** They live on the session now rather than on the screen's State, which is rebuilt on every entry - so a glance at the log discarded everything staged. Cleared on APPLY, on Discard, and by the credential wipe.
- ADD: **both logs now name what changed.** The app log lists each device change as "<name>: <from> -> <to>", one per line, instead of "Applying...", and a default-connection change is named from and to in the app log AND the router syslog, which said nothing about it at all before.
- CHG: the device list sorts offline devices below online ones, then by name. Scrolling past greyed rows to reach a device that is actually there was the common case.
- FIX: the apply confirmation no longer indents the "from" line by two spaces.
- TST: fourteen - the pin-versus-follow distinction in the model and what each writes, the resolved default label on rows and in the confirmation, the Internet choice writing the enabled form, the Active and Disabled colours, staged changes surviving a rebuild and being cleared by Discard, both log paths, and the new sort order.
- DOC: ARCHITECTURE.md 3.3.6 records that the app now models both index-0 meanings.

2026-09-10 v0.8.50 build 420 - alert emails: what to do, and how to turn them off

- CHG: **stock alert emails no longer claim a leak that usually is not one.** The kill-switch row said "traffic is reaching the internet without the VPN" whatever the state of the router. A device pinned to a dropped tunnel actually falls through to the DEFAULT CONNECTION, which is one of three things, and only one of them is a leak - so the script reads `vpnc_default_wan` and says which happened.
- INF: the three cases. This tunnel IS the default, so its devices have no internet rather than an unprotected one - fail-closed, and worth saying so. Another tunnel is the default, so its devices are still on a VPN, and the email names it. The plain internet is the default, which is the only case the old sentence described. A warning that cries wolf twice for every time it is right is one people learn to ignore.
- CHG: the deploy payload guard is now an absolute 26 KB for both firmwares rather than tying stock to Merlin's size. Stock carries three branches of this wording that Merlin has no need of, because Merlin has a real kill switch to report on and stock has to work out where the traffic went instead.
- TST: six - the two NVRAM reads, one per case for the fail-closed, other-tunnel and plain-internet branches, all three tenses present in each, and the old blanket claim gone from the script entirely.
- ADD: **every alert email now says how to turn alert emails off** - via WATCHDOG, CREATE/EDIT, then deselecting "Enable email alerts", naming the controls exactly as the app labels them. An alert arrives hours later at an address that may not even be the phone the app is on, and one that does not say how to stop it gets silenced at the mail client instead, which loses the next one too.
- CHG: the TEST email deliberately does NOT carry that footer. It is sent from the very screen the sentence points at, with the checkbox on it.
- ADD: WHAT TO DO gains "Review your router log." as step 4, and the remaining step is renumbered.
- TST: five - the new step and the renumbering, the numbering having no gaps or repeats, the footer present on an alert and absent from a test email, its position above the review line with the sign-off still last, and the deployed script carrying the same footer and the same steps as the app builds.

2026-09-10 v0.8.49 build 419 - router install: helper binary ownership and boot script backups

- ADD: **the two init scripts the app takes over are backed up before it writes over them.** `S50downloadmaster` and `S50asuslighttpd` are copied to `<path>.old` on a stock deploy, so a router can be put back the way it was found - and so the uninstall feature has something to rename back. Guarded three ways: the file must exist, `.old` must not already exist, and the file must not already be the app's own copy, because a false backup is worse than none.
- ADD: **`S50asuslighttpd` is replaced by a stub that returns immediately.** It runs at boot and again on every VPN up or down, and its `sleep` calls stall the boot outright when the router starts with a VPN enabled. Nothing in it is wanted here. Rewritten on every deploy, so a firmware update that restores the original is undone next time.
- FIX: the installed helper binaries and `/jffs/cfg-pia-wg` are now owned by root. Ownership came out of the archive otherwise - mailsend-go's tarball carries 501:201, the uid and gid of whoever built it, and tar preserves them. Numeric `0:0` rather than `root:root`, which BusyBox needs `/etc/passwd` and `/etc/group` entries for. Best-effort: the binary runs as root either way.
- TST: nine - the chown covering both the binary and the app directory and never failing an install, both backups preceding their writes with all three guards present, the stub written at mode 700 and proved by byte count, Merlin untouched, and the embedded stub matching the repo copy, shipping LF only, carrying the backup marker and containing no logic at all.
- DOC: ARCHITECTURE.md 5.2.1 - the second init script, and why each backup guard is load-bearing.

2026-09-10 v0.8.48 build 418 - device management regression fixes

- FIX: **the login form flashed on entry to MANAGE, WATCHDOG and DEVICE ASSIGNMENT.** All three reconnect on their own when the session already has a working connection, but they rendered the form for the whole of that reconnect - asking for credentials the app already held, on a screen the user was about to be taken off, with fields they might start typing into. A reconnect now shows a placeholder from the first frame, and the form appears only when the reconnect fails and it is actually needed.
- ADD: `ReconnectingBody`, shared by all three screens so the reconnect looks the same wherever it happens.
- FIX: **back from MANAGE and WATCHDOG dropped the user on the login form they had finished with.** Reported against 418, which pushed the slot list as a second route. It is not a route at all now: the screen IS the connect form until it connects and the slot list afterwards, exactly as the device assignment screen works - so back leaves for the menu, and there is no extra route to name, observe or return to.
- FIX: on a tablet the slot rows sat alone at the far left of a very wide line. Content on the slot list and the watchdog form is capped at 480 and centred, the width those screens had as cards. A phone is narrower than the cap, so nothing changes there.
- ADD: `AppScaffold.maxContentWidth`, which caps and centres the body and the HOME button together - HOME running the full width of a tablet under a narrower column would have swapped one oddity for another.
- FIX: **the SSH username field is prefilled with 'admin' again.** Fixed on the device assignment screen in 413 and regressed on MANAGE and WATCHDOG in 414 - the two screens carried the same line and only one was changed. A password manager will not overwrite a field that already has content, so the default cost a manual clear before every autofill. The ABOUT screen's router login follows, since its comment says it starts from the same place the router screens do.
- CHG: **MANAGE and WATCHDOG are full screens now, not modals.** They are destinations, and they were sitting on top of a connect form that had done its job. Both are pushed with the destination name of the screen underneath, so the drawer keeps highlighting the right entry.
- FIX: the watchdog CREATE/EDIT form is a page too, which is what fixes SAVE and its spinner sitting below a fold that would not scroll. That shipped in 409, was fixed, and came back in 412: a shrink-wrapping scroll view inside an unbounded card has no overflow to scroll, and no height arithmetic makes one. On a page the scroll view is bounded by construction.
- FIX: the HOME button is the shared one everywhere. The slot list had its own small right-aligned button while every other screen pins a full-width one below the scroll view - which is the inconsistency reported against the device assignment screen. It also means the processing overlay now covers HOME rather than stopping at the edge of a card.
- FIX: `AppScaffold` is a `Material` rather than a `ColoredBox`. An opaque box between a `ListTile` and the chrome's `Material` makes Flutter assert that the ink splash will be invisible, which is what the email-alerts row hit once the form became a page.
- TST: eleven - the reconnect placeholder showing on the first frame of a re-entry on all three screens and the form coming back when a reconnect fails, the username left blank on both router screens and in ABOUT, the slot list and the watchdog form being pages with the shared chrome and no modal depth, HOME being the pinned `AppScaffold` button outside the scroll view, the watchdog form scrolling on a 360x560 screen with SAVE reachable and no overflow, the slot rows capped and centred on a 1200-wide screen, and connecting pushing no route.
- DOC: CONTEXT.md 4.1 and 4.10b - pages versus dialogs, and why a long form is never a dialog.
- FIX: **a device assignment was written correctly and had no effect.** Stock never removes a device's old policy routing rule when its assignment changes, and both rules sit at priority 100 - so the kernel takes them in insertion order and the older one always wins. `vpnc_dev_policy_list`, the web interface and the app all read wgc5 while the traffic kept leaving through wgc1. The app now deletes the stale rules itself after `restart_vpnc_dev_policy`.
- INF: no service call clears it. `restart_dnsmasq`, `restart_vpnc_dev_policy`, `restart_vpnrouting0`, `restart wgcN` and a full `stop_vpnc`/`restart_vpnc` cycle with `vpnc_unit` set to the target row were each measured and each left the rule in place. Only `restart_net_and_phy` clears it, and that bounces every switch port and re-leases the WAN - far too much for moving one device.
- FIX: unassigning had the same defect, so a device sent back to the default connection carried on using the tunnel it had left. Every per-device rule for that address is now removed. The priority-10000 `from all iif br0` rules that ARE the default connection are matched on the address and never touched.
- DOC: ARCHITECTURE.md 3.3.6b records the measurement, the commands to see it, and the three cases the sweep has to get right.
- TST: eleven - six on the rule parser including a prefix-match trap and the default-connection rules, and five over a fake router that actually applies the deletes.

2026-09-09 v0.8.47 build 417 - sync commit

- updated work sequence and items (one disappeared today).

2026-09-09 v0.8.46 build 416 - the reason the watchdog could never recover a tunnel

- FIX: **the watchdog could never recover a tunnel on its own.** ASUS's `/usr/sbin/curl` walks its live process ancestry and refuses to run when `crond` is anywhere in the chain: it exits 0 having produced no HTTP status, no body and no stderr, and writes `Invalid caller(crond)` to `/jffs/curllst`. Every cron-driven PIA token request had been silently rejected. A cron run now re-execs itself detached and waits to be reparented to init before doing any work; a `deploy` run over SSH is untouched, because dropbear was never the problem.
- INF: measured three times over on hardware, same command one minute apart: from cron the write-out was empty, detached to init it was `200 exit=0`, and `/jffs/curllst` carried the rejection line only for the cron caller. This is what an overnight outage of four and a half hours, eight failed attempts and five disproved hypotheses came down to.
- INF: the five hypotheses measured and disproved on the way there, recorded so they are not re-run. DNS routed through the dead tunnel - the alert emails were delivered throughout, and there is no `wgc1_dns` at all. Tmpfs exhaustion - 9.7 MB used, no OOM in the log. A device-assignment apply killing the tunnel - an apply was run with the handshake sampled either side and it advanced. The router's own traffic routed into the down tunnel - `ip route get` shows the PIA endpoint going out `eth0`. The fetch failing because the tunnel is down - the identical curl returns HTTP 200 with wgc1 down.
- SEC: `abort()` now empties `/jffs/curllst` too. The token request passes `-u user:password` on the command line, curl records every command line in that world-readable file, and only the success paths flushed it - so a failed fetch left the PIA password on flash until the next successful reconfigure.
- DOC: ARCHITECTURE.md section 5.5 records the caller check, the measurements and the `/jffs/curllst` exposure; SECURITY.md and TESTING.md section 2.1.4 carry the parts that matter to users.
- ADD: **both version numbers, in both logs.** Every watchdog run logs `Watchdog started for wgcN [script v0.8.46 build 416]` to the router syslog and the watchdog log, and opening the watchdog screen logs the deployed script's version next to the app's - saying "redeploy the watchdog to update it" when they differ. The app updates from the store but the script only changes on a deploy, so the two drift silently: the 415 interface fix was tested on hardware against a script two builds old before that was noticed.
- INF: closes the open question of whether the watchdog could not recover because the router's own DNS was routed through a stopped tunnel. Both 2026-09-08 failures reported the same `exit 0, HTTP none, body 0B: empty`, both ran from cron, and DNS was separately ruled out when the alert emails were delivered throughout. It was the caller check; there is nothing further to confirm.
- INF: an unknown version is deliberately not reported as a mismatch. Scripts deployed before the marker existed have none, and a warning nobody can act on teaches people to ignore the ones they can.
- TST: five script assertions - the detach guard, the reparent wait, deploy runs staying attached, the guard preceding every curl, and the abort-path flush - plus the version marker in the start line, the header parser, the mismatch rule, and the status read reporting to both logs.

2026-09-09 v0.8.45 build 415 - what "active" means, and why a watchdog could not recover

- FIX: **a configured-but-DOWN interface reported as ACTIVE.** Reported from hardware: `ifconfig wgc1 down` left the app badging the slot active while the router's own web interface showed "connecting" and nothing passed. `wg show interfaces` lists WireGuard DEVICES and says nothing about link state, so every liveness question in the app was asking the wrong one - the ENABLE verification loop that decides the badge, the watchdog's interface polls, the delete-time wait, and the device-assignment waits. All six now use `ip -o link show up`.
- INF: the obvious fix would also have been wrong. A WireGuard device reads `state UNKNOWN` while it is up, because it is POINTOPOINT/NOARP - matching on `state UP` would have failed always. The UP flag in the angle brackets is the signal, and `ip -o link show up` filters on it: up is `<POINTOPOINT,NOARP,UP,LOWER_UP>`, down is `<POINTOPOINT,NOARP>`.
- FIX: the router-side script had the same flaw. `ifconfig "$IFACE"` succeeds for a device that exists, up or down, so "Interface $IFACE is down or absent" never fired for a downed interface - only the handshake and ping fallback caught it, which is slower and less clear about what is wrong.
- ADD: **the PIA token fetch now records what curl says rather than what the script infers.** Five failures between 2026-09-07 and 2026-09-09 reported `exit 0, HTTP none, body 0B: empty` - curl reporting success while producing no status, no body and no stderr, which curl should not be able to do. curl 7.84 on this firmware supports `%{exitcode}`, `%{errormsg}` and `%{num_connects}` (all 7.75+), so it is now asked directly.
- ADD: one retry, three seconds apart, when the token fetch comes back with no status or `000`. The existing message already guessed "the network was still coming back up"; a retry tests that guess for the cost of three seconds against a tunnel that otherwise stays down for hours.
- ADD: the token request's temp files are kept when the fetch fails instead of being deleted. That failure has only ever happened under cron, has never been reproduced by hand, and left nothing behind to examine - an overnight outage on 2026-09-09 ran eight attempts over four and a half hours and the only surviving evidence was a zero-byte stderr file.
- TST: a regression test that a configured-but-down interface is not active, and script assertions for the new `-w` format, the retry and the kept files.
- DOC: updated TESTING.md - what a healthy tunnel looks like.
- ADD: resequenced WIP list.

2026-09-09 v0.8.44 build 414 - in-app device assignment, implementation phase 2: decode mechanism behind how default connection is done on stock the screen, phase 3 - screen UI

- ADD: in-app device assignment to VPN. Design in`.claude\plans\plan_vpn_device_assignments.md`. Reference now in `ARCHITECTURE.md` 3.3.
- INF: **`enabled` separates "pinned to the internet" from "follows the default".** Both carry index `0`, and the router's own interface renders an enabled index-0 record as SELECTED under Internet Connection and a disabled one as a GREYED selection. Unassigning in this app writes the disabled form, so a user checking the web interface afterwards sees their device greyed there - which is not the same as being pinned to the internet, and is the difference between leaking and failing closed when a tunnel drops.
- CHG: the apply progress is a centred, non-dismissible dialog rather than a spinner inside the APPLY button. In the button it left a grey blob at the bottom of the screen where the label had been, which read as the button breaking rather than as work in progress. Blocking input is also correct here: the sequence stops the tunnels and must not be interrupted.
- ADD: **changing the default connection works, and the sequence took eleven probes on hardware to find.** Writing `vpnc_default_wan` does nothing on its own. The order is `vpnc_unit` to the target's clientlist ROW, `stop_vpnc`, `restart_default_wan`, THEN the key and `wgc_unit`, commit, `restart_vpnc`. Three different numbers name the same profile - row, index 6 and slot - and getting `vpnc_unit` wrong stops the wrong tunnel and silently applies nothing. Written up in `ARCHITECTURE.md` 3.3.
- INF: **`restart_default_wan` is a teardown, not a routing refresh.** It stops every WireGuard client and resets `vpnc_default_wan` to `0`. That reset is why every attempt that wrote the key first failed - the value went in ahead of the thing that clears it.
- INF: the default connection IS a pair of `ip rule`s at priority 10000, `from all iif br0 lookup <index 6>` and the same for `br1`, and they are installed when `restart_vpnc` starts the TARGET profile. Not by writing the key, and not by `restart_vpnc_dev_policy`, which handles device assignments and does nothing for the default.
- FIX: **`notify_rc` only queues, so the first implementation raced itself.** Issued back to back the whole sequence finished in two seconds and failed. It now polls for each step to land - the target leaving `wg show interfaces`, the key reading `0`, the target returning - which takes about six seconds against fifty-five for fixed sleeps.
- ADD: the confirmation warns that changing the default connection stops and restarts the tunnels for about a minute and that a watchdog on an affected slot will report the outage. Assigning a device does none of that, and the two must not feel like the same kind of action.
- FIX: **the screen did not match the other two router screens.** It had its own `FilledButton` reading `CONNECT` rather than `CONNECT TO ROUTER`, no spinner, and no auto-connect - so it asked for a password every time it was opened while MANAGE and WATCHDOG walked straight in on the shared session.
- FIX: an early `return` inside a `try`/`finally` skipped the code that presented the error, so a firmware refusal showed nothing at all. Both `_connect` and `_apply` now collect the failure, clear the spinner and present afterwards - which also stops the spinner animating behind a dialog, something no widget test can settle around.
- CHG: a default-only apply no longer rewrites `vpnc_dev_policy_list`. There is no reason to put our copy of the device assignments over whatever arrived between the read and the write.
- INF: **BusyBox on this firmware has no `comm`, `diff` or `seq`** either, all found in one evening alongside the earlier `find -type f`. Recorded in `.claude/CONTEXT.md`: assume nothing beyond the shell builtins, `grep`, `sed`, `awk`, `tr`, `cut`, `sort` and `head`/`tail`.
- TST: B1 to B10 run on an RT-ABCD. The list, staging, the light path, reservation creation, the foreign-VPN record surviving, stale-write refusal, offline assignment and the watchdog notes in the picker all passed. The default connection took eleven probes and now passes through the app, confirmed by `ip rule` and by the router's own web interface agreeing.
- INF: **the wgcN-only correctness rule is confirmed on hardware.** With a throwaway PPTP profile created in the web interface and a device pinned to it, the app showed that device as `PPTP, not app managed` rather than as unassigned, offered no non-WireGuard profile in its picker, and carried the foreign record through a write byte-for-byte - a record-wise comparison of the policy list either side showed the only change was the device actually being moved. Getting this wrong would silently destroy an assignment made elsewhere, which is why it was worth creating a profile to test.
- FIX: **the assignment screen held the SSH client it opened, so an APPLY minutes later died.** Reported on hardware: six minutes between connecting and applying, then `SSHSocketError ... errno 103, software caused connection abort`. Every other router screen uses the shared `RouterSession`, which reopens and retries a dropped connection; this one did not. It does now, which also means one dropbear login per app session rather than one per screen. Guarded by a test asserting the services are handed a `RouterSession` rather than a raw `SSHClient`.
- FIX: **the screen reported a stock router as Merlin** when opened before the MANAGE screen. `routerFirmware` defaults to Merlin until something probes it, and the probe lived in the other screen's connect path - so whether device assignment worked depended on where the user had been first. It detects the firmware itself now.
- FIX: SSH autofill. The username field defaulted to `admin`, and a password manager will not overwrite a field that already holds text, so every autofill needed a manual clear first; and the two fields were not in one `AutofillGroup`, so the manager filled the username and never offered the password. Both corrected to match the other router screens.
- CHG: the picker is a centred dialog titled with the device, not a bottom sheet. Anchored to the bottom of a tall phone it opened nowhere near the row that was tapped and covered that row. Its entries are bordered, filled tiles: three lines of plain text read as a paragraph rather than as three things you could choose.
- CHG: a staged change is **amber**, not teal. Device names are teal, so a teal picker made the whole row one colour and the pending state vanished into it. Amber also carries the right meaning - not yet written.
- CHG: the default-connection block and the device list are two bordered panels on a common ground. Read as one continuous column they were indistinguishable, and the first attempt used `kSurface`, which is the header colour, so the panel disappeared into the header instead.
- CHG: `APPLY 1` became `APPLY 1 CHANGE`. Beside a numbered runsheet the bare digit read as a step number.
- INF: **the light path is confirmed from the app, not just from a shell script.** Assigning a reserved device produced `restart_dnsmasq` and `restart_vpnc_dev_policy` and nothing else, the policy record read exactly `1>IP>>5>`, `ip route get` showed the device on `dev wgc5`, and no session dropped.
- INF: **creating a reservation does NOT need the heavy path.** Assigning the one unreserved device took the reservation count from 9 to 10 and still produced only the light pair - no `restart_net_and_phy`, no mcast burst, no connectivity lost. So the whole-network restart is the web interface's choice for this job and not a requirement, and the confirmation dialogue says a fixed address will be created rather than warning about a restart.
- INF: unassigning leaves the record disabled rather than deleting it (`0>IP>>0>`) and leaves the reservation in place, both as designed and both confirmed on hardware.
- INF: **`isOnline` in `/tmp/nmp_cache.js` is stale and must not be used.** Measured on a device powered off for ten minutes: `nmp_cl_json.js` had updated to `"online": 0` while `nmp_cache.js` still read `"isOnline": "1"`. Liveness comes from `nmp_cl_json.js`; everything else can come from `nmp_cache.js`. Reading it from the file that supplies every other field - the obvious choice - would have shown every device as permanently online and the `offline` tag would never have appeared.
- INF: **an offline device keeps its `ip` in `nmp_cache.js`**, so it stays assignable and the `dhcp_staticlist` fallback is a second source rather than the main one. The genuinely unassignable case is narrow: unreserved, powered off, and not seen since the last reboot, because `/tmp` is rebuilt at boot. The disabled row stays in the design for it.
- INF: **`/tmp/nmp_cache.js` mixes non-device keys in among the MAC-keyed ones** - `maclist`, an array of every tracked MAC, and `ClientAPILevel`, the string `"5"`. A parser assuming every value is a device object throws, which is exactly how this was found. Skip any entry whose value is not an object and require the key to look like a MAC. Documented as `ARCHITECTURE.md` 3.3.5b along with the rest of the reading traps.
- CHG: **the "last seen" tag is dropped from the assignment screen design.** `conn_ts` measured across eleven devices reads `0` for every WIRED one, and the five wireless devices that carry a value share it to within three seconds - one moment, the last reboot. It is a wireless association timestamp, not a last-seen time, and showing it would mark every wired device as never-seen. The `offline` tag stays, since `online` and `isOnline` are reliable.
- INF: the two device files agree on the device set - every MAC in one is in the other - and the router itself appears in neither `nmp_cache.js` nor `maclist`. So `cfg_device_list` is strictly needed only to exclude the mesh node.
- INF: **`cfg_device_list` identifies the router and every mesh node in one key**, as `name>IP>MAC>flag` records with the flag `1` for the router and `0` for a node. Any MAC in it is never offered as assignable - by identity, rather than by matching a model string. This was a real gap: a mesh node is otherwise indistinguishable from a laptop, carrying `isGateway: "0"` in `nmp_cache.js` like any other client, and `lan_hwaddr` names only the router. Documented as `ARCHITECTURE.md` 3.3.5a.
- INF: `nmp_cache.js` also carries `amesh_isReClient` and `amesh_papMac` on devices connected THROUGH a node, the latter being the node MAC. That marks a device behind the mesh - assignable like any other - not the node itself.
- INF: **BusyBox on stock has no `comm`.** Added to the absent-command list in `.claude/CONTEXT.md` beside `command -v` and `find -type f`. Two sorted lists are diffed with `grep -vxF -f` instead.
- INF: **both device files are plain JSON despite the `.js` extension** - `/jffs/nmp_cl_json.js` and `/tmp/nmp_cache.js` are objects keyed by uppercase MAC with no `var` wrapper and no trailing semicolon, so `jq` reads them directly and no de-wrapping step is needed. 2258 and 7692 bytes, small enough to read whole in one round trip.
- INF: the two files disagree about types - `type` is an integer in `nmp_cl_json.js` and a STRING in `nmp_cache.js` - and `nmp_cache.js` already carries `nickName` merged from `custom_clientlist`. So when the `/tmp` file is present it alone supplies name, nickname, address and type; `custom_clientlist` is the fallback for when it is not.
- FIX: **a router with nine DHCP reservations and a completely EMPTY `vpnc_dev_policy_list`** disproves the documented claim that the firmware seeds a disabled placeholder record per reserved device. The records seen on 2026-09-06 were residue from assignments made and undone, not firmware-created. Nothing downstream changes - the rule was always to read index 0 rather than presence - but the expectation does: an untouched router has an empty list, so the screen renders "everything on the default connection" from no records at all.
- TST: `LanDevice.hasRandomisedMac` matched the router exactly - of ten devices, the one flagged for a locally-administered address is the Android phone, and nothing else is. A useful accident found while writing it: `AA:BB:CC:DD:EE:FF`, the invented MAC the privacy guard recommends, is itself locally-administered, so it cannot be used as the negative case.
- ADD: `lib/device_assignment.dart` - the pure layer. Parses and serialises `vpnc_dev_policy_list` keeping unknown trailing fields, distinguishes a real assignment from a disabled placeholder or a WAN-pointing index 0, resolves a display name through custom-then-detected-then-MAC, and refuses to call a device assignable when no source knows its address. 22 tests, no SSH.
- TST: `.claude\testing\2026-09-08_device-assignment-runsheet.md` written before any code, per the usual pattern. Part A runs first and settles one open question - whether `/tmp/nmp_cache.js` keeps an offline device with its IP - plus captures the real shape of both JSON files. Part B is the functional pass once the screen exists, including the stale-write refusal and the byte-for-byte survival of a non-WireGuard policy record. Gitignored: it holds real LAN data.
- DEC: **the assignment screen design is agreed and written up in the plan section 2.5.** Two lines per device (`name - IP`, then the picker), MAC standing in only when there is no name, tag only the exception (`DHCP`, `offline`, `last seen`, randomised-MAC warning), the default connection at the top with its explanation, staged changes behind one centred APPLY, and a two-line picker carrying the watchdog state in words.
- DEC: **scope is `wgcN` and nothing else.** The web interface allows 16 VPN profiles of any kind sharing `vpnc_clientlist`, so a policy record can name an OpenVPN or PPTP profile. The picker offers only app-managed WireGuard slots; a device pinned elsewhere is shown as its type plus `not app managed` and its record written back byte-for-byte. Rendering it as unassigned would silently destroy the user's assignment on the next write, which makes this a correctness rule rather than a scope note.
- DEC: **the policy record is keyed by IP, so a device with no known address cannot be assigned.** `nmp_cl_json.js` - the only source listing offline devices - carries no `ip`. The address now comes from `/tmp/nmp_cache.js` first and `dhcp_staticlist` second, the latter covering every reserved device online or not. A device that is both unreserved and uncached is listed but not assignable, and says why.
- DEC: **APPLY re-reads before it writes.** README section 6 records that a stale web-interface page rewrites the whole list from the copy it loaded; the hazard runs both ways. Apply now re-reads and compares every record it is not touching, refusing rather than clobbering.
- DEC: guest-network devices are never offered for assignment - they are on `br1` and cannot reach the LAN.
- DOC: `ARCHITECTURE.md` 3.3 carried a stale "open question - decide before the screen is built" note about guest devices that the CHANGELOG had already decided. Conflict resolved in favour of the decision.
- DOC: `ARCHITECTURE.md` 3.3.6 gains the 16-profile ceiling, the two rules that follow from it, and the IP-keying consequence.
2026-09-08 v0.8.43 build 413 - in-app device assignment, implementation phase 2 - finalise design decisions
- FIX: **a failed CREATE into an EMPTY slot left the wreckage behind.** `createConfigToSlot` backs the slot up only when it is already occupied, and the recovery path was `if (backup != null)` - so a create into an empty slot that failed part-way through the 17 `nvram set` calls restored nothing, cleaned up nothing, and never reached `nvram commit`. That is exactly the state seen on 2026-09-08: every `wgc5_*` key readable, no `vpnc_clientlist` row, keys unflushed in RAM, and both this app and the router web UI reading the slot as unconfigured. The two WIP items were one defect, not two. An empty slot is now unset key by key, its clientlist row dropped, and the clear committed.
- FIX: **a restore that failed still reported success.** The recovery path called `client.run` directly, which discards the exit code, so a restore whose own `nvram set` failed logged `config restored` and told the user their overwritten slot was safe. It goes through the strict `_run` now, so a failed restore reaches the existing `CRITICAL: could not restore` line instead.
- FIX: restored values are single-quoted through `shellSingleQuote` rather than interpolated into double quotes. The values are round-tripped out of NVRAM, so a quote or a `$` in an old description could previously corrupt the restore command it was part of.
- INF: **build 413's strict `_run` does turn this class of failure into a thrown one.** `_editVpncClientlist` already called `_run`; what changed in 413 is that `_run` stopped tolerating a non-zero exit. So the silent `nvram set vpnc_clientlist` failure that produced the half-written slot would now throw - and, with the fix above, be cleaned up rather than left. The underlying failure is older than 413.
- TST: five tests on the recovery paths, which is where this went wrong: a failed create into an empty slot unsets what it wrote and commits, the stock case also drops the clientlist row, a restore that itself fails says CRITICAL and not `restored`, and a value containing a quote survives the restore intact.
- INF: **Q9 ANSWERED - the heavy `restart_net_and_phy` is not needed.** Writing the reservation and the policy record and then calling only `restart_dnsmasq` and `restart_vpnc_dev_policy` applied the assignment with nothing bouncing: WAN address unchanged, no `net_and_phy` in the syslog, and a wired SSH session that did not drop. The WebUI is simply heavier than the job requires, so **the app can be gentler than the WebUI** and the assignment screen needs no whole-network disruption warning.
- INF: **Q10 ANSWERED AND CONFIRMED - a pinned device falls through to the DEFAULT CONNECTION when its tunnel drops.** The test was run twice with different defaults. Default on "Internet Connection": the device returned to the plain internet, silently, which read as a leak. Default on wgc1 with the target still wgc5: the same device fell to `dev wgc1`, **not** `dev eth0` - which is the measurement that discriminates. One rule, and the outcome is chosen by a setting: the `ip rule` is torn down with the interface and traffic falls through to whatever the default is.
- INF: so assignment is not a kill switch **by itself**, but fail-closed behaviour is reachable and now recommendable on evidence: pin the devices to a tunnel AND make that tunnel the default, which is the maintainer's own setup and the one where a stale config took the network offline rather than leaking. The app can tell the user how to get the property instead of only warning them they lack it.
- INF: **the watchdog bounds every outcome to one check interval** by bringing the tunnel back - a leak in one configuration, an outage in the other. Assignment, default connection and watchdog are one story rather than three features, and assignment WITHOUT a watchdog on the same slot is the combination to warn about. It also retires the "two mechanisms behave differently" reading: `vpnc_default_wan` appeared to fail closed on 2026-09-05 only because the default WAS the tunnel.
- INF: **a DHCP reservation is created by assigning a device to ANY profile, including "Internet Connection", and is never removed when the device is unassigned.** Measured 2026-09-08: assigning all ten devices and then unassigning them all left an empty policy list and ten reservations, six of them new and with empty hostnames. This settles the open sub-question about whether unassigning cleans up - it does not.
- INF: the whole-LAN bounce is therefore a **first-touch cost per device, not a recurring one**. A router that has ever used VPN Fusion already has a reservation for every device, so later assignments are all cheap. A freshly reset router is where it bites - which is exactly where a new user starts, so this does not argue the warning away.
- FIX: **an unreachable router reported "Unable to determine router firmware type".** `RouterSession` connects lazily, so the connect call does no I/O and the socket timeout surfaced inside the firmware probe - whose catch relabels anything it sees. The connection is now forced before the gate, so a wrong address or a refused login is reported as what it is. It also only misreported on the FIRST connect of a session, since the firmware is cached afterwards and the probe skipped, which is why the same mistake produced two different messages on consecutive days.
- DOC: `README.md` section 6 warns to change things in one place at a time. The web interface writes the whole of `vpnc_clientlist` back on **Apply all settings** from the copy it loaded when the page opened, so a change made in the app can be overwritten by a page that was already open. (An earlier draft of this entry blamed browser caching for a missing wgc5 row; that was disproved - a cache clear and browser restart did not reveal it, and `showall.sh` confirmed the row was absent from NVRAM. See the WIP item.)
- INF: **the AiMesh oddity is explained and does not block device assignment.** A device on a mesh node's ethernet port is bridged transparently and never registers as a mesh client, so the AiMesh client table has no IP binding for it - which is why the kernel logs `<MAC> not mesh client, can't update it's ip` and why the WebUI labelled exactly those devices `Static IP`. One cause, two symptoms. The app's own sources are unaffected: `nmp_cache.js` has the address and `/proc/net/arp` has the MAC.
- INF: `nmp_cl_json.js` carries **no `ip` field at all**, confirming the two-source device list is necessary rather than tidy - the address has to come from `nmp_cache.js` for every device.
- INF: kernel messages appear only in `dmesg`, never in `/tmp/syslog.log`: `/proc/sys/kernel/printk` reads `5 4 1 7`, so only priorities below 5 are forwarded and these are informational. Worth knowing before grepping the wrong place for a router-side symptom.
- FIX: **a failed router command could be returned as a value.** Every command went through `utf8.decode(await client.run(cmd)).trim()`, and `SSHClient.run` MERGES stderr into stdout - so a failing `nvram get wgcN_desc` handed back "nvram: can't open /dev/nvram" where the region name should have been, and the app carried on with it. That is a data-integrity bug, not a logging gap. Commands now go through `runWithResult`, which keeps the two apart.
- FIX: **115 of 125 router commands could fail in silence.** `run` discards the exit code, and only ten commands encoded success in their own output (`&& echo OK || echo FAIL`). The new `lib/router_command.dart` captures it, and the default is now to **throw**.
- CHG: reads and writes are treated differently, because they fail differently. A failing write (`nvram set`, `cru a`, `service`, `mv`, `chmod`) throws - a silent failure there leaves the router in a state the app reports as success. A failing read (`nvram get`, `cat`, `wg show`, probes) does not, because non-zero is routine for them and an alarm that cries wolf gets dismissed along with the one that mattered. 42 call sites became `_read`; `cru d` and `nvram unset` are explicitly tolerant, both being remove-if-present.
- CHG: every failure is logged with its exit code and stderr whether or not it is fatal, to the app log and the router syslog, so a tolerated failure is still diagnosable without interrupting anyone.
- ADD: **logged commands are redacted.** The app log is shown on screen and pasted into bug reports, so a failed `nvram set wgc1_wd_smtp_pass=...` must not report the password. Redaction is by KEY - anything containing `pass`, `priv`, `psk`, `token`, `key` or `user` - which cannot miss one the way looking for secret-shaped values would. The PIA username is redacted too, since it identifies an account.
- TST: `test/unit/router_command_test.dart` - 18 tests, all about failure: stderr never reaching a caller as a value, a failing write throwing, a failing read not throwing, both being logged, the tolerated one not being flagged as an error, and nothing logged carrying a credential. Two of them drive `RouterSlotService` end to end, so the policy is proven wired and not merely implemented.
- FIX: **the watchdog no longer fights a user who disables a tunnel.** A tunnel switched off in the WebUI looked exactly like one that had dropped, so the watchdog reconfigured it, brought it back up and emailed an alert - undoing the user and reporting a fault that had not happened. It now reads `wgcN_enable` and stands down. Observed 2026-09-07 22:45, and it blocked device assignment, which requires disabling the tunnel to change an assignment. Only an explicit `0` stands down; an empty value means the firmware does not keep the key, which is not the user saying no.
- FIX: **"no servers found for region X" blamed the region for a network failure.** The server-list fetch was one pipeline, so `$?` was jq's and curl's failure was invisible. Fetch and parse are now separate steps with three distinct messages: the download failed (with curl's exit code and stderr), the list downloaded but would not parse, or the list is fine and the region is not in it.
- FIX: `failed to download CA cert` now carries curl's exit code and its first line of stderr. It could equally have meant DNS, TLS, a 404 or a full disk, and said none of them.
- CHG: `could not select a server for region X` says how many candidates were tried and that the list downloaded, so it points at the router reaching PIA rather than at the region name. `Interface wgcN did not come up` now reports what `wg show interfaces` actually listed.
- CHG: the PIA token request runs curl as the condition of an `if` rather than capturing `$?` after an assignment. The assignment form was suspected of the 2026-09-07 `exit 0` report, but was **tested and captures the status correctly** in POSIX sh - so that was not the cause and the real one is still unknown. The `if` form cannot be misread by any shell, which is worth having in a script that runs on BusyBox builds we cannot inspect.
- ADD: a token request that reports success while returning no status code, no body and no stderr is now named as its own failure rather than described as an HTTP error - that is what made the observed failure unreadable.
- ADD: CLOSED - will not be done: device icons on the assignment screen. NOT by fetching ASUS's artwork off the router - `custom_clientlist` index 3 is an integer indexing a device-type list, and the images live in the firmware's web assets, so displaying them would mean copying their files into the app. The viable path is their integer plus our own icon, which copies nothing; it needs the code-to-meaning table out of `/www/client_function.js`. Deferred because a Material icon set beside ASUS's own would look wrong next to the WebUI and the ASUS app, not because of the effort.
- INF: a device behind the AiMesh node assigns like any other. Its sources check out (`nmp_cache.js` has the IP, ARP has the MAC); only the end-to-end assignment is still unproven.
- INF: index 2 of `vpnc_dev_policy_list` is empty on every record seen; purpose unknown. Write it empty and match the WebUI.
- DOC: CLOSED - instead of calling them "slots", I should consider calling them "units" - that's a lot of risky search and replace though :/

2026-09-07 v0.8.42 build 412 - in-app device assignment, implementation phase 1 - deploy binaries

- ADD: implement a function to get and deploy needed binaries (using `scripts\get-bins.sh` as template starting point), add test for DownloadMaster installed, on first run rename `router:/opt/etc/init.d/S50downloadmaster` and `router:/opt/etc/init.d/S50asuslighttpd` to `*.old`.
- INF: `ARCHITECTURE.md` 3.3.6a records the WebUI starting state before any VPN exists - "Internet Connection" is itself a server-list entry, marked Default Connection with "Apply to all devices" on, holding exactly the four devices that have a DHCP reservation. Those are the same four that appear as `0>IP>>0>` placeholder records, which suggests index 0 means bound to the WAN rather than seeded-and-disabled. Unverified, and the parsing rule is the same either way.
- INF: **app size is not a concern, measured 2026-09-07.** The 88 MB of app data on a test device was `app_flutter/flutter_assets`, which is `kernel_blob.bin` (72.6 MB - the whole Dart program as unoptimised kernel) plus `isolate_snapshot_data` (11.1 MB). Both are **debug-only**: release AOT-compiles to `libapp.so` inside the APK and extracts nothing to app data. The 154 MB debug APK is likewise three copies of `libflutter.so` (one per ABI, 107 MB) plus a 14.5 MB Vulkan validation layer, none of which ships. Worth re-measuring with `flutter build appbundle --release --analyze-size` before acting on any size warning from Play.
- INF: `jq` is pinned at 1.8.2 and `mailsend-go` at v1.0.12, with SHA-256 checksums for both architectures taken from the checksum files each project publishes and independently recomputed on hardware. Settles the "which versions, and where do the checksums come from" question.
- FIX: **the save spinner went below the fold again.** `unfocus()` only STARTS the keyboard retracting, so scrolling on the next frame positioned against a viewport about to grow by the keyboard's height. The 409 fix was still in place - it was racing an animation rather than waiting for it. `_showSpinner` now waits for `viewInsets.bottom` to reach zero before scrolling.
- FIX: the router screen drops keyboard focus before connecting and after the install dialog closes. Closing a dialog restores focus to whatever held it last, so the keyboard reopened over the connect spinner on a field the user had finished with.
- FIX: **a deploy no longer reports itself as an outage in the router log.** The first run after SAVE logged "Connectivity lost; reconfiguring" and "Reconfig SUCCESS" - both literally true, both reading as a fault, when the tunnel not being up yet is the expected starting state. It now says "Deploying: bringing wgcN up for the first time" and "Deploy SUCCESS". Build 409 fixed the same confusion in the alert emails and missed the log.
- CHG: the install offer reads "I can download it for you" rather than "The app can download it for you".
- CHG: dropped the full stop from `Interval: not set, watchdog has yet to be saved and deployed` - it is a status line, not a sentence.
- FIX: **`find -type f` silently returns nothing on this BusyBox.** It was how the extracted archive was located, and `ls -la` on the same directory listed all five files - so the install failed on both architectures with the checksum already verified and the payload sitting right there. With stderr discarded, a `find` that ERRORS on an unsupported option is indistinguishable from one that matched nothing. Now uses `ls -1`, which is always present and needs no options.
- CHG: the archive is extracted by `cd`-ing into the directory first rather than `tar -C DIR`, removing the question of which BusyBox builds honour `-C` after `-f`. Not the cause of the failure above, but one less assumption about a shell that has now broken three of them.
- FIX: the README reference in the install dialog is a working link. Users tapped it because the same words are a link on the notice that follows, so plain text there read as a broken link rather than a deliberate difference.
- CHG: the install dialog shows the **expected SHA-256** under the source and destination lines. Saying a download is checksum-verified without showing which checksum asks the user to take on trust the very thing being verified; shown in full, it can be compared against the checksums the projects publish.
- FIX: install failures name the binary and use a colon, so they read as sentences. Build 412 produced "Could not install the archive extracted to nothing", which parses as nonsense on first reading.
- CHG: "the archive extracted to nothing" now names the directory it looked in and lists what was actually there.
- FIX: **the mailsend-go archive member is named after the release, not the program.** It holds `LICENSE.txt`, `README.md`, `mailsend-go-v1.0.12-linux-arm64` and `platforms.txt` - flat, no directory - so looking for a file called `mailsend-go` found nothing and the install failed on both architectures. The exact member name is now pinned per asset. `scripts/get-bins.sh` only worked because its `mailsend-go*` glob happened to match.
- CHG: the Router IP field defaults to `192.168.50.1:22` rather than the bare address. The hint showing the `host:port` form only renders while the field is empty and it is always prefilled, so the syntax was undiscoverable; the value itself is the one place a user looks. `splitHostPort` parses it back, so nothing downstream sees the port.
- FIX: **FORGET ROUTER IP did not forget.** It deleted the stored address but not the one held for the session, which shadows it - and merely opening a router screen copies the prefill into that session value. The address stayed on screen and the button looked broken while doing exactly what it said. Forgetting now clears both, and also clears the connected flag so the auto-reconnect cannot fire at an address the user just asked the app to drop.
- FIX: declining the helper-binary install no longer follows the dialog with the same information again. The dialog already says what happens and where to read more, so repeating it immediately was nagging; the README notice now appears on the next visit, where it is a reminder rather than a repeat.
- FIX: install failures read correctly after "Could not install " - lower case, no trailing full stop - with a test pinning it, because they were wrong on the first hardware run.
- FIX: **the archive handler could not say what went wrong.** The first hardware run failed on both architectures with "did not contain exactly one", which equally covered tar failing, an empty archive, or the binary being named something else. It now captures tar's own error, lists what was actually extracted, names it in the failure, and accepts a version-decorated binary name while still refusing to guess between two candidates.
- CHG: the install prompt names the repository (`github.com/jqlang/jq`) and the download size rather than just "from github.com", which was about as informative as "from the internet" for something the user is being asked to run on their router.
- CHG: the installer writes progress and failures to the **router syslog** as well as the app log - architecture and candidate order, each download with size and source, checksum verified or the actual mismatch, and every failure. A support request arrives with a router log far more often than an app screenshot.
- ADD: **the app can install `jq` and `mailsend-go` itself.** On stock, opening MANAGE or WATCHDOG with a helper binary missing now offers to download it rather than only explaining how to do it by hand. Offered, never imposed: the prompt names the version, the source and the destination before anything happens, says that declining leaves the screen unusable, and a dismissed dialog counts as declining. A refusal is remembered for the session so it does not nag, and still falls through to the existing README notice.
- ADD: `lib/binary_installer.dart` pins `jq` 1.8.2 and `mailsend-go` v1.0.12 with SHA-256 checksums for both architectures. Every download is verified before installation and discarded on mismatch - BusyBox `wget` on stock has weak-to-absent TLS validation, so the checksum is what makes the result trustworthy rather than the transport. The four pinned hashes were each checked against the checksum files the two projects publish, and the arm64 pair was independently recomputed on an RT-ABCD.
- ADD: the **archive** is hashed for `mailsend-go`, not the binary inside it. Hashing the extracted file would produce a number nothing upstream publishes, which is trust-on-first-use dressed as verification.
- ADD: architecture is confirmed by **running** the installed binary, not by trusting `uname -m` - a 64-bit kernel over a 32-bit userspace is common on these routers. If the reported architecture will not execute, the other is tried before giving up, and a binary that will not run is deleted rather than left where the missing-binary check would find it and pass.
- ADD: free space on `/tmp` and `/jffs` is checked before downloading, and nothing is ever deleted to make room - the app did not put whatever is there. `/tmp` is cleaned up on both success and failure, since it is RAM on these routers.
- CHG: `SessionController` remembers declined install offers for the session, cleared by `wipeAll` with everything else. A refusal is not a setting and is not persisted.
- FIX: **the router SSH port is no longer assumed to be 22.** `sshd_port_x` is settable in the router's WebUI, which actively suggests moving it, and the app simply could not reach a router that had taken that advice. The Router IP field now accepts `host:port` (`192.168.50.1:2222`); a bare address still means 22, and a malformed port falls back to 22 so the user gets a connection error rather than a parse error. The port cannot be probed for - reading `sshd_port_x` needs a working SSH session - so it has to come from the user.
- FIX: `RouterPrefs` rejected any address containing a colon, so a remembered address with a non-default port would have been silently dropped - the users who most need it remembered were the ones it refused.
- FIX: **the README claim that a factory reset does not clear custom NVRAM values was wrong.** Measured on stock (RT-ABCD) 2026-09-07: three committed marker values - one arbitrary, one shaped like `cfg_pia_wg_password`, one shaped like `wgcN_wd_smtp_pass` - were all gone after a WebUI factory-default restore, and gone again after a WPS hard reset, with an identical key count either way. Section 6 now says a reset does clear them, records how that was measured, and still recommends the scripts for anyone on Merlin, which has not been tested.
- FIX: `ARCHITECTURE.md` 5.2 and the `s50_template.dart` header both claimed only the region between the REPLACEMENT markers of `S50downloadmaster` is rewritten and everything else is copied through untouched. Not so: `buildS50Script` builds from the template bundled in the app, carries across only the `cru` lines, and discards the rest of the file.
- INF: **deploying a watchdog on stock destroys a working DownloadMaster installation.** A real `S50downloadmaster` is 52,525 bytes and the app's replacement is around 700, measured either side of an install. Harmless for the documented setup, where DownloadMaster exists only to provide `/opt`, and not harmless for anyone actually using it. The two overwrite each other in both directions, so re-running the DownloadMaster installer also removes the watchdog's boot persistence.
- INF: DownloadMaster's footprint, for `BACKLOG.md` 1.1: 24 NVRAM keys added (`dm_http_port`, `dm_https_port`, `ed2k_*`, `gen_*`, `trs_*`), six `apps_state_*` changed, and `/opt/etc/init.d/S50downloadmaster` (52,525 bytes) plus `S50asuslighttpd` (8,448 bytes) written.
- TST: `no_lan_identifiers_test.dart` skips `.claude/testing/`, which is gitignored precisely so it can hold verbatim session output. It uses `Uri.path` so the exclusion works on Windows separators too.
- DOC: `README.md` section 4.1 now covers the stock-firmware prerequisites properly - Download Master, with the five install screenshots, and the helper binaries. Closes two backlog items. Includes the USB format requirements, since **exFAT will not mount** and is what Windows picks by default for any stick over 32 GB; ext4 on a single primary MBR partition is recommended, per the ASUS Plug-n-Share compatibility list.
- DOC: the SSH step in `README.md` section 4.1 mentions the `address:port` form for a router whose SSH daemon is not on 22.
- DOC: user-facing text describes the boot-persistence *requirement* and its *consequence*, never the mechanism, and `.claude/CONTEXT.md` records that as a working agreement. `ARCHITECTURE.md` keeps the engineering rationale and now marks the design settled, so it is not mistaken for something to tidy up.
- ADD: `.claude/plans/plan_install-helper-binaries.md` - plan for installing `jq` and `mailsend-go` from the app, with five decisions agreed: **offer it, never impose it** (and say up front that MANAGE and WATCHDOG cannot run without them, so declining is an informed choice rather than a discovery); offer only what the current screen needs; **pin versions and verify SHA-256** rather than trusting GitHub-latest over the router's weak TLS; confirm the architecture by **executing** the binary rather than trusting `uname -m`; and **check free space on both `/tmp` and `/jffs` first**, reporting which is short and by how much.
- DOC: `BACKLOG.md` 1.2.3a records the ordering rule for freemium - entitlement check, then dependency check, then any offer to install. A user without the unlock sees the paywall, never a dependency error, and the app never offers to put binaries on the router of someone who cannot use them.
- ADD: `scripts/capture-baseline.sh` snapshots the router and reports only what changed since the previous snapshot. Written for a from-scratch rebuild: a snapshot taken between a factory reset and the first configuration change is the only way to learn the true factory values, and `clearall.sh` currently restores values that were inferred rather than measured. Also isolates what a DownloadMaster install actually puts where, which `BACKLOG.md` 1.1 needs. No dependency on `diff` - a factory reset wipes `/jffs` and takes the installed `diff` with it, so the comparison is done in awk.
- TST: verified the app is unaffected by a WireGuard **server** interface. `wg show interfaces` returns `wgs1` alongside the client interfaces on a router running one; the active-slot parse uses `RegExp(r'wgc(\d)')` and every other read is `contains('wgc$slot')`, so neither can match `wgs1`, and `clearall.sh` deletes only `wgc1`-`wgc5` by name. Never previously checked.
- ADD: (untracked) `.claude\testing\2026-09-07_factory-reset-runsheet.md`
- ADD: DM installation images added to `.\images` & repo

2026-09-06 v0.8.41 build 411 - in-app device assignment, implementation phase

- INF: **device names in `custom_clientlist` are stored raw, not percent-encoded.** A device renamed to `Arc's "Tab"` came back verbatim - apostrophe, double quotes and spaces intact - so the decode/encode pass the plan assumed is not needed. What replaces it is a shell-quoting requirement: every device name interpolated into an SSH command must go through `shellSingleQuote`, because an apostrophe in a name breaks naive single-quoting.
- INF: **`custom_clientlist` records are not a fixed nine indexes.** A six-record list measured 9, 9, 9, 8, 6 and 6 - the WebUI writes some trailing empties and drops others. A parser that requires nine indexes rejects most of a real list; split and treat any index past the end as empty.
- INF: a MAC with the locally-administered bit set (second hex digit `2`, `6`, `A` or `E`) is a reliable tell for a randomised address, confirmed against real data. It detects the address currently in use, not the device setting, so the warning is "this address looks randomised", never "this device randomises".
- INF: `/tmp/nmp_cache.js` parses as JSON despite the `.js` extension - a top-level object keyed by uppercase MAC with `.ip` populated, so it is usable as the current-IP source and needs no key normalisation to join against `nmp_cl_json.js` or `custom_clientlist`. Volatile, so a missing file means "no IP known", not an error.
- INF: **offering only devices with a DHCP reservation is not viable.** A reservation is a deliberate manual mapping, not something a device gets by connecting - most routers have none at all, so that list would be empty for most users. The app therefore has to write `dhcp_staticlist` itself, which is what the stock WebUI already does, because binding a policy to a lease that can move would silently transfer the assignment to whatever device next takes that IP.
- INF: **removing a DHCP reservation is as disruptive as adding one** - deleting one entry in the WebUI dropped a 5 GHz laptop hard enough to kill an RDP session over it. Every `dhcp_staticlist` write takes the heavy path, in both directions.
- INF: a device keeps its address on a plain lease after its reservation is removed, so removing one does not break an IP-keyed assignment immediately - it stops guaranteeing it, and the breakage arrives silently at some later renewal. An argument for the app never removing a reservation on unassign.
- INF: the WebUI client list already makes the distinction the assignment screen needs - an IP Method column reading `MAC-IP Binding` or `Automatic IP`, derived from `dhcp_staticlist` membership. The app can derive it the same way and should borrow the wording rather than invent its own.
- ADD: `scripts/verify-device-assignment.sh` settles both remaining unknowns in one run and restores the router afterwards: whether `restart_net_and_phy` is really needed to apply a new reservation (the device already holds the address on a lease, so `restart_dnsmasq` may be enough), and whether a per-device assignment fails closed when its tunnel drops. Uses `ip route get ... from ... iif br0` so nothing has to run on the device being tested, and prints a short ANSWERS block rather than a log dump.
- DOC: `.claude/plans/plan_vpn_device_assignments.md` finalised. Every blocking question is answered: schema, write semantics, both service sequences, the device-list source, freemium (paid), and the six-button home screen (fits, no submenu). Two items remain - one optional probe and one design decision - both written up at the bottom of the plan.

2026-09-06 v0.8.40 build 410 - in-app device assignment

- INF: **phase 0 of the device-assignment plan is answered.** `vpnc_dev_policy_list` holds `enabled>IP>>vpnc_idx>` records joined by `<`, where `vpnc_idx` is **index 6 of the profile `vpnc_clientlist` record** - not the slot number and not the row index. Unassigning removes the record rather than zeroing it, and a move is a delete plus an append, so the list has to be rebuilt whole and keyed on IP rather than patched in place.
- INF: the assignment service sequence is `stop_vpnc` then `restart_vpnc_dev_policy` then `restart_vpnc`; "apply to all devices" is the same with `restart_default_wan` in the middle and writes `vpnc_default_wan` using the same index-6 identifier (`0` = plain WAN), which settles that open question. `vpnc_dev_policy_list_tmp` is the WebUI rollback copy - the previous committed value.
- INF: assigning a device that has no DHCP reservation makes one, with an empty hostname, because the policy is keyed by IP. Two consequences: the app must write the reservation too or the assignment decays with the lease, and a device using MAC randomisation gets a reservation that breaks silently at the next rotation.
- INF: a tunnel must be disabled before its assignments can change. Whether a device assigned to a **down** tunnel fails closed or falls back to the WAN is **not yet known** - that was briefly recorded as confirmed, but the only measurement covers "apply to all devices" (`vpnc_default_wan`), which is a different mechanism from a per-device `ip rule`. It decides whether this feature can be described as a kill switch, so it is now item 10 in the plan.
- INF: **assigning a device costs one of two very different amounts.** With a DHCP reservation already in place it is `stop_vpnc` / `restart_vpnc_dev_policy` / `restart_vpnc` and only VPN routing bounces. Without one, creating the reservation drags in `restart_net_and_phy` - every switch port bounces, downstream routers and APs drop with everything behind them, and the WAN re-leases onto a new public address. Measured on hardware 2026-09-06: LAN down at 20:11:41, WAN re-lease at 20:11:58, new address registered at 20:12:08. The app must treat creating a reservation as a separate, explicitly confirmed action.
- ADD: **the router address is remembered between sessions.** A successful SSH connect writes the address you connected to into a single-line file in the app private storage, and the SSH form prefills from it. Precedence is session value, then remembered, then the shipped default. It is written only after the connect has SUCCEEDED, so a typo or a wrong guess is never stored.
- ADD: `FORGET ROUTER IP` on the ABOUT screen deletes the remembered address. Greyed out when there is nothing stored, which is also the only way a user can see that anything is stored at all.
- CHG: `kDefaultRouterIp` is now `192.168.50.1`, the ASUS factory address, on every branch. It was a real router address on dev, which was a privacy problem and only tolerable because it saved retyping - and now nothing needs retyping. Closes the BACKLOG item asking for a main/dev split, which is no longer needed.
- CHG: `wipeAll` deliberately does NOT clear the remembered address. It is not a credential, and wiping it on every exit would make storing it pointless. Everything else it wiped before, it still wipes.
- INF: the remembered address is the ONLY thing this app writes to device storage - no username, no password, no generated config. It is validated on read as well as on write (the file is hand-editable on a rooted device and its contents reach an SSH connect), and `android:allowBackup="false"` keeps it off Google Drive.
- TST: `test/unit/router_prefs_test.dart` - 23 cases covering the round trip, the rejected shapes (shell metacharacters, spaces, over-long values), an unreachable directory, the prefill precedence, and that `wipeAll` leaves the address alone. Plus a source scan asserting `router_prefs.dart` writes the address and nothing else, so a future author cannot quietly add a password to it.
- TST: `RouterPrefs` is inert under `flutter test`. The path_provider channel has no handler in a test binding and its reply never arrives, so an await on it hangs - which appeared as a connect spinner that never cleared and a bare `pumpAndSettle timed out` with no exception to explain it. A test that wants storage passes a directory; widget tests use an in-memory subclass, because a `testWidgets` body runs under fake async and never completes real file I/O.
- DOC: SECURITY.md, README.md and `.claude/CONTEXT.md` (new section 4.2.1) rewritten where they claimed nothing at all is persisted. The claim is now "one non-secret value, by explicit choice, user-clearable" rather than quietly going stale.
- FIX: replaced a MAC address in `.claude/plans/plan_vpn_device_assignments.md` that did not match the invented pattern of the samples around it, and moved the "every value here is invented" note from the middle of the document to the top, where a reader meets it before the sample records.
- TST: `test/unit/no_lan_identifiers_test.dart` fails the build if anything under `.claude/testing/` becomes tracked, if `.claude/testing/` leaves `.gitignore`, or if any repo file carries a MAC address that is not a visibly invented one.
- DOC: working agreement added to `.claude/CONTEXT.md` - no real IPs, hostnames, DDNS names, MAC addresses, router logins or PIA usernames in any tracked file, with the invented values to substitute and the one deliberate exception (`kDefaultRouterIp`).
- FIX: NVRAM record fields are now numbered **0-based everywhere, and called `index`, not `field`**. `ARCHITECTURE.md` was contradicting itself - its `vpnc_clientlist` schema table counted from 0 while the prose in the same document counted from 1, so "field 6" meant the *active flag* in one place and the *state index* in another. `.claude/CONTEXT.md` disagreed with itself too, calling the description both "field 0" and "field 1". 37 references corrected across ARCHITECTURE.md, CONTEXT.md, `router_slot_service.dart`, `slot_params_editor.dart`, `router_slot_service_test.dart`, both helper scripts and two plans, matching the `VpncRecord` constants the code has always used. Slot numbers are unaffected and stay `wgc1`..`wgc5`.
- DOC: recorded the convention as a working agreement in `.claude/CONTEXT.md`, so it does not drift back. Getting it wrong writes the active flag where the state index belongs, which disables a tunnel while appearing to succeed.

2026-09-06 v0.8.39 build 409 - e2e testing updates

- ADD: `scripts/new-test-record.py` generates a blank manual-test record from `TESTING.md` section 4 - a flat table with Ref, Area, Check, Result and Notes columns. The 2026-09-06 run was recorded by hand-editing a copy of the checklist, which VS Code renumbered as it was edited, and the copy then drifted from the original. Now the checklist lives in one place and the record is generated from it; the script refuses to overwrite a run already in progress.
- FIX: `TESTING.md` section 4 had eight results ("- stock OK") pasted into the checklist itself, which is exactly the drift above. Stripped - results belong in a generated record.
- CHG: `scripts/clearall.sh` removes `/tmp/watchdog_unsent_wgcN` too, and `stopWatchdog` does the same for the slot it is tearing down.
- TST: full end-to-end manual app test, used `TESTING.md` section `4. Full end-end-to-end manual test` as a template, results saved to `.claude\testing\2026-06-09_10-40_e2e_manual_test.md`
- FIX: **the watchdog deploy races the interface coming up.** `enableVpnSlot` issues `restart_vpnc` and returns without waiting - `notify_rc` queues the call - so the script runs about a second later, finds "Interface wgcN is down or absent" and performs a full reconfigure that was never needed. Seen on every deploy where the slot was not already up: wgc5 08:31:07 -> 08:31:08, wgc4 08:48:24 -> 08:48:25, wgc1 10:00:37 -> 10:00:38, wgc5 10:06:13 -> 10:06:14. Costs a needless PIA token + `addKey` per deploy. MANAGE's `enableSlot` already waits and verifies; the watchdog path should do the same before exec'ing the script.
- FIX: a deploy run **increments `cfg_pia_wg_reconfig_ok`**, so the lifetime counter counts deployments as reconfigures. Consequence of the race above, and wrong even without it.
- FIX: the deploy email reads `Event: reconfigured successfully on attempt 1` under the heading "Watchdog deployed and the tunnel is up", and carries `Tunnel was down for: unknown (no successful check since the router last rebooted)`. A `deploy` run should say it deployed, whatever path it took, and should omit the outage line - there was no outage.
- FIX: **cron-triggered alert emails report the wrong timezone** - `Time: 2026-09-06 09:20:00 UTC` when the router is AEST. The clock and the offset are right; only the zone *name* is wrong. Root cause found 2026-09-06: cron inherits `TZ` from init, which holds `/etc/TZ` = `UTC-10DST,M10.1.0/2,M4.1.0/3` - a POSIX string that literally names the zone "UTC" with a +10 offset. A dropbear login shell sets no `TZ` at all (`echo $TZ` is empty), so `date` falls back to `/etc/localtime` and correctly says AEST - which is why manual and app-run alerts looked fine. So exporting `TZ` from nvram would not have helped; it is the same string. Emit the numeric offset instead - `%z` gives `+1000`, which cannot be wrong whatever the zone is called, and reads the same from cron and from a shell.
- FIX: a hard token failure prints two shell errors: `watchdog_wgcN.sh: line NNN: can't open /tmp/wgcN_token.json: no such file`. When curl cannot resolve the host the file is never created, and `< "$TMPTOK"` fails in the shell *before* the command runs - so the `2>/dev/null` on `jq` / `wc` / `head` does not suppress it. Guard with `[ -f "$TMPTOK" ]`.
- FIX: in GENERATE, the Quad9 defaults are only restored when the DNS field is emptied **completely**. Deleting one of the two entries and leaving the screen keeps the single remaining entry. The blank-check should also fill in a missing second server.
- GUI: after SAVE on the watchdog configure dialog the spinner is **below the fold** and the last-edited field keeps focus with a green border and the keyboard up, so it looks like nothing happened and the field looks editable. Centre the spinner in the viewport (or scroll to it) and drop focus before the deploy starts.
- GUI: the watchdog overwrite prompt says `Overwrite wgc4...`; it should name the region, `Overwrite wgc4:pia-au_brisbane-pf...`, like the delete prompts do.
- CHG: a better format for recording a manual test run - the current nested list renumbers itself when edited and is hard to read. Suggest a flat table with a status column per check, generated from `TESTING.md` section 4 so the checklist and the record cannot drift.
- ADD: **report alerts that could not be sent.** The missing 7th email was not a defect - wgc4's 09:12 failure alert could not be sent because DNS was down at that moment (`lookup smtp.gmail.com ... server misbehaving`), wgc1 being the default connection and itself down. An alert about lost connectivity can be unsendable for the same reason it fired. Decided 2026-09-06: rather than resend it late, count the failures and say so in the next email that *does* get through - `1 earlier alert could not be sent (09:12)`. The recovery email is the one people read, and a stale alert arriving hours later is worse than a line of context. Also document the limitation in `README.md`.
- CHG: **backgrounding no longer closes the router connection immediately** - it now waits 5 minutes (`kBackgroundSessionGrace`), and coming back cancels the timer. The e2e test recorded ten dropbear logins in one session, every one following an `HTTPD [LOGIN]` from the same device: hopping to the router WebUI and back was charging a fresh handshake each time, which is most of what sharing the connection in 406 was meant to remove. A wipe still closes it immediately. Three tests cover brief background, long background and wipe-during-grace.
- ADD: `scripts/test-backoff.sh` - walks the whole backoff ladder on the router in about two minutes with no PIA traffic, from the loop used to verify it by hand. It refuses to run unless the watchdog is paused and the tunnel is actually down (the two ways this test silently misleads you), confirms no PIA token was requested and that turned-away runs left the counter alone, cleans up its own state file, and exits non-zero on failure. A unit test asserts its hard-coded rungs still match `kBackoffLadder`.
- TST: backoff **verified on stock** 2026-09-06 - all eight rungs exact (120, 240, 480, 960, 1800, 3600, 5400, 5400 s), the counter untouched by turned-away runs, and no PIA token requests during the test. `TESTING.md` section 2.1.6 now records why the test is built the way it is, not just the commands.

2026-09-06 v0.8.38 build 408 - sync commit ahead of e2e app test

- REL: sync commit

2026-09-05 v0.8.37 build 407 - fixed the reset/inspection scripts and the broken review link, and brought the docs up to date.

- CHG: updated `scripts\clearall.sh` with additiooanl values to reset/delete all configs.
- FIX: `scripts/clearall.sh` never removed a single cron entry. It called `cru d "{field}_wgc${slot}"` - a missing `$` - so it asked the router to delete a job literally named `{field}_wgc1`. A watchdog kept running after what looked like a clean wipe, which is exactly the state that makes a fresh test start dirty.
- FIX: `scripts/clearall.sh` cleared `enforce`/`fw`/`rip` for slots 1 and 5 only, and hand-listed a partial set of `vpncN_` runtime keys. Both are now swept for every slot, and `vpncN_` across the whole 1-16 range those keys can occupy.
- ADD: `scripts/clearall.sh` now also removes what it had only ever half-removed - the deployed watchdog scripts, the cached PIA CA, the `/tmp` log, last-good and backoff files, and our lines in `services-start` / `S50downloadmaster`. It deliberately leaves `jffs2_scripts` / `jffs2_on` and the user-installed `jq` / `mailsend-go` alone, and says so.
- ADD: `scripts/showall.sh` shows what the NVRAM dump cannot - the contents of `/jffs/cfg-pia-wg`, the boot-persistence lines in both hook files, the `/tmp` watchdog state including the backoff counter, and the Merlin JFFS flags.
- DOC: closed the `BACKLOG.md` 1.2.7 item "add link to reconfigure email seeking an app review, with an NVRAM timestamp when the watchdog is first deployed and a counter incremented on each reconfigure" - all three shipped in 404 as `cfg_pia_wg_sdate`, `cfg_pia_wg_reconfig_ok` and `cfg_pia_wg_reconfig_fail`, reported in the HISTORY section of every alert email alongside the review link.
- DOC: `BACKLOG.md` sections 1.2, 1.3 and 1.4 record what the review turned up - the pre-flight check that is mostly already written and the one that is missing, the measured firmware-branch count and file sizes behind the cleanup, and what actually blocks iOS. Early thinking in three plans: `plan_revenuecat-implementation.md` (renamed from `pan_revenucat-...`, two typos), `plan_firmware-abstraction.md` and `plan_ios-port.md`, each cross-referenced from its backlog item.
- DOC: `ARCHITECTURE.md` section 4.1 - the Merlin SSH commands were a placeholder. Now documents enable, disable and delete, the `restart_vpnrouting0` / `start_vpnrouting0` asymmetry, why `nvram commit` precedes every service call, and what only Merlin has (the kill switch, `wgcN_desc` as a real field, the JFFS partition).
- DOC: `ARCHITECTURE.md` section 5 - the watchdog was described as ping-only, deploying to a path it stopped using in 402. Rewritten: the handshake is the primary liveness check with ping as the Merlin fallback, the script lives in `/jffs/cfg-pia-wg`, and reboot persistence is `services-start` on Merlin against a hijacked `S50downloadmaster` on stock (which is why DownloadMaster is a stock prerequisite).
- DOC: `ARCHITECTURE.md` sections 5.1.1 and 5.1.2 are new - the backoff ladder with its table and why the counter tracks attempts rather than checks, and email alerting: the three sending events, the deploy email that fires even when nothing is wrong, and the note that a failure email's log excerpt carries the PIA username.
- DOC: `ARCHITECTURE.md` flow diagram said the watchdog screen required Merlin and that ENABLE stops the other watchdogs. Neither has been true since 395.
- DOC: `README.md` no longer frames router management and the watchdog as Merlin-only in the intro, section 1 and the feature list, which contradicted the stock support announced further down the same page. `CONTRIBUTING.md` said the same thing.
- DOC: `README.md` section 5.7 documented the About screen with a screenshot and one sentence. Now covers COPY BUILD INFO, CREATE GITHUB ISSUE, DEL PIA CERT and the licences page.
- DOC: the example emails in `README.md` named a specific build, which would go stale every release. Genericised.
- DOC: `TESTING.md` quoted `Cooldown Ns < 120s; skipping`, a log line 405 removed, and described the fixed 120 s cooldown in three places. Replaced with the ladder, plus how to jump to a rung without waiting for it.
- DOC: `TESTING.md` section 3 gains the global `cfg_pia_wg_*` keys - the lifetime counters an alert email reports - and `scripts/showall.sh` / `clearall.sh`.
- DOC: `BUILDING.md` listed 4 of the 8 direct dependencies, missing `dartssh2`, which every router operation runs over. Also records that adding a Flutter plugin with native Android code needs the Gradle lockfiles regenerated - the trap `in_app_review` fell into in 406.
- DOC: `SECURITY.md` records the SSH session introduced in 406: it is now held open for the app session rather than per action, and closed when the app is backgrounded and whenever credentials are wiped.
- FIX: the home screen's "add a Play Store app review" link did nothing when tapped, on debug and release alike. It asked Play to draw its in-app rating card, and Play draws one only when it chooses to - quota-limited per user, and never at all on a build Play did not install - while reporting success either way, so the app could not tell a shown card from nothing happening. Google's own guidance is not to put that flow behind a button. The link now opens the Play Store listing, which always does something.
- CHG: the whole review line is the tap target rather than just the underlined text. A 12px line of glyphs is a small thing to hit, and a `TextSpan` recogniser fires on nothing else.
- TST: the review-link tests now TAP the widget instead of calling its recogniser directly, which bypassed hit-testing entirely - they would have passed against a link nobody could hit. One asserts a tap well off to the side of the centred text still counts.

2026-09-05 v0.8.36 build 406 - stock support implemented alongside Merlin

- CHG: the app now holds ONE SSH connection to the router and every action shares it, instead of opening and closing its own. That removes a full handshake from the front of every button press and a `dropbear[NNNN]: Password auth succeeded` line from the router log per action. Design in `.claude/plans/plan_ssh-connection-reuse.md`.
- CHG: a dropped connection used to heal by accident, because the next action simply connected again. `RouterSession.run` now does it deliberately: on a transport failure it reconnects once and re-runs the command, and says so in the app log. Without that this change would have traded log noise for intermittent action failures, which is the worse bug.
- CHG: only transport failures are retried - a closed connection, a reset, a broken pipe. An error the router itself raised is reported as-is, because re-running `nvram set` or a heredoc append over an error we did not understand is worse than the original failure.
- CHG: the connection is keyed on router IP, SSH username and password, so editing any of them builds a new one rather than silently reusing a session pointed at a different box.
- CHG: the connection closes when the app goes to the background and when credentials are wiped. An authenticated session held open behind a locked screen is a wider exposure than credentials sitting in memory; the next action reconnects.
- FIX: `test/unit/no_escaped_constants_test.dart` - the guard added after the `\$kRouterAppDir` bug never actually ran. Its pattern was a literal backslash followed by the end-of-string anchor, which nothing can follow, so it had matched nothing since it was written. A real escaped-interpolation bug introduced in this change walked straight past it.
- TST: 21 new tests - reuse, the reconnect-and-retry path, what must NOT be retried, teardown and ownership, plus a source scan that fails the build if any screen closes the shared connection again. The twenty per-action `client?.close()` calls are gone, and a stray one would break the next action rather than announce itself.
- INF: `RouterSession` implements `SSHClient` rather than wrapping one, so the services, the call sites and every test fake were unchanged. Nothing downstream needed to know.

2026-09-05 v0.8.35 build 405 - stock support implemented alongside Merlin

- CHG: the watchdog now backs off when PIA refuses a token request. PIA answers HTTP 403 after sustained re-registration and clears on its own after tens of minutes, so retrying every 120s indefinitely is what prolonged it - with two watchdogs that was a request a minute between them. The wait now climbs 2, 4, 8, 16, 30 and 60 minutes on consecutive failures and caps at 90, resetting the moment a reconfigure succeeds. A single failure, the common case, is exactly as responsive as before.
- FIX: the failure counter counted checks, not attempts. It incremented on runs the cooldown had already turned away, so how fast the wait grew depended on the check interval - a 1-minute watchdog would have escalated twice as fast as a 2-minute one. It now rises only when an attempt is actually made, which also makes the alert email's "Attempt: N" row mean what it says.
- CHG: an alert now names the real wait before the next try - whichever of the backoff and the next cron tick comes later - rather than promising the bare check interval, which stopped being true the moment the backoff exceeded it.
- CHG: a run inside the backoff window logs "Backing off after 3 failed attempts: 45s of 480s elapsed". A long silent gap in the watchdog log otherwise reads as a watchdog that has stopped.
- TST: `test/unit/backoff_test.dart` - 12 tests over the ladder, the cap, the generated shell matching the Dart function, and the increment sitting after the early exit. The ladder is a lookup table generated from one list, because it stops being a clean doubling at 16 minutes.
- DOC: `.claude/CONTEXT.md` records that Markdown is never line-wrapped - one logical unit per line, no hard wrap at any column. The 130-character limit is a Dart rule for `lib/` and `test/` only. Wrapped prose written earlier in 404 has been unwrapped to match.

2026-09-05 v0.8.34 build 404 - stock support implemented alongside Merlin

- FIX: the router syslog truncated long entries - the SMTP probe stopped mid-word at "SSL handshake has read 4104 byt". BusyBox syslogd caps a single message, and the diagnostics worth having are the long ones. `_logRouter` now splits at 200 characters into `(1/3)`-numbered parts, breaking on a `|` line boundary or a space where there is one near the limit, and sends them as one command so a split still costs one SSH call. Both services use it.
- FIX: a failed test email reported almost nothing usable. The one app-log line was styled as a success and said "see router log for details"; the mailer's stderr, the TCP probe and the TLS probe all went to the router syslog only, and the screen said nothing at all. Every diagnostic now goes to the app log as an error, `testEmail` returns whether it sent, and the watchdog dialog raises a dismissible warning pointing at View app log.
- FIX: the `nc -w 5 <host> <port>` reachability probe reported UNREACHABLE for every host on stock. BusyBox builds nc as `nc IPADDR PORT` with no options at all, so the `-w` made it exit on a usage error - and a host that delivered mail seconds later was reported as unreachable, in both the app and the deployed watchdog script. The probe is gone; `openssl s_client` answers the same question and says far more when it fails.
- CHG: dropped `-debug` from the mailsend-go command and now capture the LAST 20 lines of stderr rather than the first. With debug on, the parser's chatter filled the capture and pushed the actual error off the end - which is why the first report of this bug carried nothing usable.
- INF: the send failure itself turned out not to be the command line at all - the SMTP app password was a character short, which the router answered with `535 5.7.8` and the app had been swallowing. Found within a minute of the new diagnostics landing, which is the whole point of them.
- ADD: an "add a Play Store app review" link on the home screen, above the donation block and clear of it, invoking Google Play's in-app rating card via `InAppReview.instance.requestReview()` - no trip to the Play Store. Where that flow does not exist, on a sideloaded or debug build, it opens the store listing instead so the tap is never dead.
- INF: Play limits how often the rating card may be shown per user and never reports whether it drew one, so the app claims nothing about the outcome. Only a request that could not be made at all is logged.
- GUI: "How to use this app" on the home screen is now "how to use this app".
- INF: `android/app/gradle.lockfile` gains seven entries - the Play review library and its Play Services dependencies. Gradle dependency locking rejected the build until they were declared, which is the point of it; regenerated with `gradlew :app:dependencies --write-locks` rather than relaxing the lock.
- CHG: rebuilt the watchdog alert and test emails. Three lines became a sectioned plain-text message answering the questions the alert actually raises: how long the tunnel was down, whether the kill switch held while it was, which server it reconnected to and how fast, how many attempts it took, when the next check runs, and - on a failure - what to do about it plus the last ten lines of the router log. Design in `.claude/plans/plan_rebuild_test_configure_emails.md`.
- CHG: alert bodies are written in shell by the router script and the test email in Dart by the app, so every heading, step, review ask and sign-off now comes from shared constants in `router_watchdog.dart` and a test asserts the two agree. Wording changed in one language only is what this prevents.
- ADD: three global NVRAM fields - `cfg_pia_wg_sdate`, `cfg_pia_wg_reconfig_ok`, `cfg_pia_wg_reconfig_fail` - giving every email a "Since <date>, N successful and M failed reconfigurations" line. Seeded by whichever of a watchdog deploy or a test email comes first, committed once per alert rather than once per check, because `nvram commit` writes flash.
- FIX: the first run after a deploy reported a SUCCESSFUL RECONFIGURATION, having configured rather than re-configured anything. The app now runs the script as `<path> deploy` and it says "watchdog deployed"; cron runs are unaffected. It also emails on that run even when the tunnel is already healthy - that email is the proof that alerting works.
- CHG: the email subject is now `<your subject>: SUCCESS - wgc1:pia-aus_melbourne`. The configurable subject stays the prefix, so an existing mail rule keeps working, and the slot and region are appended so a client can thread by VPN.
- FIX: the kill-switch line claimed "OFF" on stock, which has no kill switch to be off. Three states now: on, available-but-disabled (Merlin), and not supported (stock).
- ADD: the outage duration in an alert, measured from a `$STATUSFILE` that now leads with an epoch. It is read before the file is re-stamped, or every outage would read zero; after a reboot the file is gone and the email says so rather than inventing a number.
- CHG: the deploy payload ceiling rises to 24576 bytes - the richer email took the script from about 9 KB to 15 KB. This was never an SSH limit once the write was chunked in 402; it is a notice-when-it-grows tripwire.
- ADD: `test/unit/email_layout_test.dart` - 27 tests over the section order, the dropped-empty-row rule, the router-fact parsing and its fallbacks, and the script/app agreement.
- CHG: `scripts/showall.sh` and `scripts/clearall.sh` cover the three new fields, and `ARCHITECTURE.md` section 3 now documents every global `cfg_pia_wg_*` field rather than mentioning the credentials in passing. It also had the credential keys written with hyphens; they are underscores.
- GUI: the MANAGE delete prompt is now one line naming what goes - "Delete VPN wgc1:pia-aus_melbourne?" - instead of a title plus a body repeating the slot number.
- GUI: the WATCHDOG delete prompt reads "Delete watchdog and VPN wgc1:pia-aus_melbourne?". The old wording buried the important half ("will also delete and disable the underlying region") in a second line.
- CHG: `SlotModal._confirm` takes an optional `message`, so a question that already names the slot and its region shows no body at all.
- ADD: credentials can be filled from the device's password manager (KeePass, Bitwarden, Google, anything registered as the autofill service). Every credential field now declares `autofillHints`; without them Android disables autofill for the field, so the app was invisible to every provider. Verified that `FLAG_SECURE` does not block the autofill overlay.
- CHG: each login is its own `AutofillGroup` - PIA, router SSH, and SMTP - so a provider cannot offer the router password for the PIA field or save one mixed-up vault entry. The router IP, DNS servers, ping targets and mail addresses are deliberately left unhinted: they are not secrets and have no business in a password vault.
- CHG: a "save this password?" prompt is offered only where the credentials have just been proven - after a successful config generation and a successful router connect. Every group is created with `onDisposeAction: cancel`, so leaving a screen or dismissing a dialog asks nothing.
- DOC: `README.md` gains a Password manager support feature bullet, and a tip in section 5.2: Android only offers a suggestion for an EMPTY field, so the SSH username - prefilled with `admin` - has to be cleared before the manager will prompt. Left as is; the default is worth more than the prompt.
- INF: this takes the clipboard out of the credential path, which is what the 60-second auto-clear exists to mitigate. Nothing about the app's zero-persistence model changes: it still stores no credential anywhere.

2026-09-05 v0.8.33 build 403 - stock support implemented alongside Merlin

- CHG: Restructured `CHANGELOG.md` format - clearer pending and WIP.
- CHG: Added draft freemium plan, code cleanup, and iOS to `BACKLOG.md`.
- CHG: Extensively updated `BACKLOG.md`, sequenced and grouped changes.
- CHG: Updated app icons to fix shield icon clipping, confirmed fixed.
- ADD: Scripts to display and reset nvram settings: `scripts\showall.sh` & `scripts\clearall.sh`.
- DOC: Added to `README.md` as a warning in section `## 6. Notes`, factory restore does **not** remove custom NVRAM values. Potential exposure of credentials (PIA & smtp) if router is sold/given away and the watchdog function is used; use `scripts\showall.sh` & `scripts\clearall.sh` scripts to display and unset nvram settings.
- REL: CLOSED - not an issue `./scripts/pin-actions-latest.*` chokes if comment missing.
- REL: CLOSED - not an issue `.github/workflows/release.yml` "Warning: WARNING!! 'track' is deprecated and will be removed in a future release. Please migrate to 'tracks'".
- REL: CLOSED - check `build-config/gradle.properties` default values are still suitable. They were set up for my laptop, not desktop. Updated `build-config\gradle.properties` to match desktop hardware. Saved old version to OneNote.
- DOC: CLOSED - not added, not needed: add README note that SBOM (build provenance) is for the aab pushed to the PS.
- DOC: CLOSED - no action required. Add to TESTING.md: `wgcX_rip` is updated by the Web GUI via an unknown method (review Asus_WRT src), router log shows no `service` script(s) were run to display this in the web GUI. It is not the public IP address (which is served from a pool to external sites), it is the router's IP address on PIA's infrastructure (?) and always differs from `wgc1_ep_addr` and `wgcX_ep_addr_r` (except PIA's webiste shows the public IP address as `wgc1_ep_addr*` vs other sites which showed `wgcX_rip` as the public ip address).
- TST: CLOSED - `lib\app_shell.dart` is the lowest at 86%. Overall Line Coverage 96.1% 2331 / 2426 lines, Function Coverage
100.0%, Files 26 high 0 med 0 low coverage. Was "review opportunities to increase code base testing, examine `ftr` report for functions with low coverage".

2026-09-04 v0.8.32 build 402 - beta test stock support for Watchdog function

- FIX: ENABLE reported a slot ACTIVE when the tunnel was dead. `wg show interfaces` only says the device exists, and an expired PIA registration still produces one that sends and never receives - the router WebUI sits on "connecting" for ever. ENABLE now waits for a WireGuard handshake and reverts with "the PIA server never answered it" when none arrives.
- FIX: on stock the watchdog reported "Primary and Secondary pings FAILED" on tunnels it had just negotiated, re-registering with PIA every cooldown until PIA refused to issue tokens. The router's own traffic is not routed into wgcN there, so `ping -I` can never succeed; the script now treats a handshake in the last 300s as proof of life and keeps the pings as a fallback for Merlin.
- INF: the app's stock ping is the same trap in reverse - it pings from the tunnel's source address but routes over the WAN, so it answered OK for a tunnel the peer had never answered. On stock it is now logged, not enforced; on Merlin, where it is a real end-to-end test, a failure still blocks the enable.
- FIX: DELETE left `wgcN_enforce` / `_fw` / `_rip` behind on stock. The app never writes them there (`kMerlinOnlySlotKeys`) so DELETE never unset them - but the watchdog script did. The stock script no longer writes them, nor `ep_addr_r`.
- FIX: `WATCHDOG_EOF` was the last line of the deployed `S50downloadmaster`, and turned up in the test email. BusyBox ash reaches EOF before it recognises a here-document delimiter that has no newline after it, and writes the delimiter into the file; `heredocWrite` now terminates it properly.
- FIX: the drawer stopped navigating to a screen after the back button was used over an open modal. Popping a page that sat above a dialog reported the DIALOG as the previous route, which the observer ignored, so `currentDestination` kept naming the page just left and the drawer no-opped. It now tracks the page stack itself.
- CHG: the "VPN limit reached" refusal comes before the ping-target prompt, not after it. The gate needs no router round trip, so there is no reason to make the user fill in a form for an enable that will be refused.
- DOC: `SECURITY.md` incorrectly stated that credentials are never written to disk. They are: deploying a watchdog writes the PIA username and password to router NVRAM, and the SMTP ones with email alerts, because the script re-authenticates on its own long after the app has gone. The section now says so, says NVRAM is not encrypted, and says how to avoid it.
- FIX: every watchdog deploy failed with "SSH connection closed" the moment the script grew past 9000 bytes. That is dropbear's `MAX_CMD_LEN`: an exec request over it is refused outright and the connection dropped, after the slot had already been enabled - which is why the app showed ACTIVE + PAUSED and the WebUI sat on "connecting". The script is now written in ~4 KB chunks (`cat >` then `cat >>`), so its size no longer touches the SSH limit.
- CHG: the S50 boot-persistence script goes through the same chunked, verified writer as the watchdog script (`_writeFile`) - one way to put a file on the router, so neither can outgrow dropbear's limit unnoticed or be left half-written. It still deploys to `/opt/etc/init.d/`, which is Entware's init directory and the only place it would run from.
- FIX: a failed script write went unnoticed - the deploy carried on and added cru entries pointing at a file that was never created. The write is now verified against the expected byte count and the deploy stops with both sizes named.
- CHG: the PIA token request no longer uses `--fail`. That flag suppresses the response body, which is the only thing that explains a refusal - a router saw HTTP 403 with nothing to say why. The status still comes from `-w '%{http_code}'`; every other call keeps `--fail`.
- CHG: a failed PIA token request now reports curl's exit code and the HTTP status - "failed to obtain PIA token (exit 0, HTTP 429: ...)". Piping curl into jq discarded its exit status, so throttling, wrong credentials and a TLS failure all logged the same bare line. The body goes to a temp file that is removed as soon as it is parsed, since it holds a token, and its size and first line are reported too - a router answered `exit 0, HTTP none`, where curl succeeded and `-w '%{http_code}'` printed nothing, so the status alone could not distinguish throttling from a cut-down curl.
- DOC: `TESTING.md` section 13 rewritten - the old "set the ping targets to unroutable addresses" method cannot force a reconfigure, because those targets are also the WAN reachability check, so the script concludes there is no internet and exits. Replaced with ways to break a tunnel that WireGuard cannot undo - replacing the interface's private key, removing the peer, taking the interface down - each with the log it should produce, plus why moving the peer's endpoint does NOT work (endpoint roaming puts it straight back), which method skips the 300s wait and which does not, plus what a healthy check looks like, the 300s handshake window to wait out, and a warning about PIA rate-limiting repeated re-registrations. Stale `/tmp/scripts` paths corrected throughout.
- FIX: a running watchdog showed as PAUSED, so it could not be disabled. The new active probe asked the ROUTER to expand `$kRouterAppDir` - a Dart constant, escaped by mistake, that the shell knows nothing about - so the file test ran against `/watchdog_wgcN.sh` and always failed. `watchdogScriptPath` moved to `firmware.dart` so both services share one definition, and a test now fails on any escaped `\$` in front of a lower-case identifier anywhere in `lib/`: shell variables here are upper-case, so that pattern is always this mistake.
- CHG: a watchdog counts as ACTIVE only if its cron entry AND its script are both present. The cron entry alone said ACTIVE for a watchdog that could never run.
- CHG: the deployed watchdog script moved from `/jffs/scripts/` to `/jffs/cfg-pia-wg/` (`watchdogScriptPath`), alongside the CA cache and the stock binaries. `/jffs/scripts` is Merlin's hook directory and still holds `services-start`.
- FIX: the working spinner was near-black in the watchdog dialog and on CONNECT. Those spinners appear while their button is DISABLED, so they sit on Material's disabled grey rather than the teal fill, and `kOnPrimary` is invisible there - they are all `kHighlight` now. One also hardcoded `Color(0xFF12141A)`.
- TST: +22 tests (436 -> 458), coverage 96.1%. The script-size tripwire moved 9500 -> 10000 for the token diagnostics; it is a review prompt now, not an SSH limit, since the write is chunked. The payload ceiling moved 9000 -> 9500 for the handshake check.

2026-09-04 v0.8.31 build 401 - WIP stock support for Watchdog function

- FIX: the watchdog's PIA re-negotiation always failed at addKey with curl exit 35. `--tlsv1.3` sets a MINIMUM version and PIA's addKey endpoint on :1337 does not offer 1.3, so the connection was refused before the request went out; the floor is now 1.2, which still negotiates 1.3 where the server supports it (the token and server-list hosts always did). This is the "ongoing since v0.8.17" addKey error.
- FIX: the curl error reached the log mangled - "u (35) eo1409442Eib...". BusyBox `tr` has no character classes, so `tr -d "[:cntrl:]"` deleted every literal c, n, t, r and l from the message. It now takes the first line and cuts it.
- FIX: deploying a watchdog on an empty slot enabled it twice - `deployWatchdog` brings the slot up, and the dialog then did it again, bouncing the tunnel the deploy's immediate script run had just established (two `service restart_vpnc` calls on stock). The dialog's second enable is gone; the immediate script run stays, so a failure still lands in the router log at deploy time rather than at the next cron tick.
- GUI: the watchdog CREATE/EDIT heading names the region - "WATCHDOG - wgc5:pia-aus_perth" - matching the EDIT modal and the log lines.
- CHG: `FLAG_SECURE` is now skipped for DEBUG builds so the app can be screenshotted on a device while testing. Release builds always set it; a test fails if that changes or if the release escape hatch (`allowScreenCaptureInRelease`) is left switched on.
- FIX: opening the keyboard on a form dialog left only its buttons on screen, over "BOTTOM OVERFLOWED BY 38 PIXELS". An `AlertDialog` puts its content in a `Flexible`, and inside the app chrome - where the Scaffold has already taken the keyboard's height off the body - that Flexible collapses to zero height and the fields spill out of the card. The SSH credentials, PIA credentials and ping-target dialogs are now built on the scrolling `Dialog` structure `SlotParamsEditor` uses (new `_FormDialog`).
- FIX: every dialog subtracted the keyboard's height TWICE, collapsing to a sliver. `AppChrome`'s `MediaQuery.removePadding` (added in 399 for the header) was handed the AppChrome context, which re-injected the outer MediaQuery below the Scaffold and undid the Scaffold's own `removeViewInsets`. It now takes the context from inside the body via a `Builder`.
- INF: the same dialog pumped on its own lays out correctly, which is why the first test written for this passed against the broken code. The regression tests now drive the whole app.
- FIX: the DEL PIA CERT credentials form opened empty. It now starts from the same defaults as the router screens (`kDefaultRouterIp` / `kDefaultSshUsername`, hoisted out of `router_slots_screen.dart` so the two cannot drift), with any session value taking precedence.
- FIX: on stock, a slot with a watchdog read back as unconfigured, greying out every button in both slot modals except CREATE / CREATE-EDIT - VIEW ROUTER WATCHDOG LOG included. `fetchSlots` takes the region name from `vpnc_clientlist` there, and the watchdog deploy path only ever wrote `wgcN_desc`. It now writes the profile row too, and marks it active when it enables the slot.
- FIX: `fetchSlots` on stock falls back to `wgcN_desc` when a slot has no `vpnc_clientlist` row, so a watchdog deployed by an earlier build stops showing as "<empty slot>" with every button greyed out. Enabling such a slot also repairs the row, description included.
- FIX: on stock the watchdog started and stopped tunnels the Merlin way (`service start_wgc` / `stop_wgc`), which does nothing there. `enableVpnSlot` / `disableVpnSlot` now use VPN Fusion - `nvram set vpnc_unit=<row>` then `service restart_vpnc` / `stop_vpnc` - the same calls MANAGE makes, via a now-public `RouterSlotService.runVpncService`.
- CHG: form dialogs take their height from the incoming constraints instead of capping it at the screen size, so the card fits the space the keyboard leaves and scrolls inside it.
- TST: +12 tests (424 -> 436), coverage 96.3%. One asserts the slot is enabled exactly once per deploy. The keyboard regression tests drive the whole app; a test fails if `FLAG_SECURE` stops covering release builds, and the stock fakes now read `vpnc_clientlist` back so a missing row cannot pass unnoticed.

2026-09-03 v0.8.30 build 400 - WIP stock support for Watchdog function

- CHG: watchdogs are no longer mutually exclusive. Deploying one used to tear down every other slot (`deactivateOtherSlots`, now gone); two can run side by side, capped by the same `vpnc_max_conn` gate MANAGE's ENABLE uses - CREATE/EDIT checks it before opening the dialog rather than after it is filled in.
- FIX: VIEW ROUTER WATCHDOG LOG was greyed out for a disabled watchdog. `/tmp/watchdog_wgcN.log` outlives the schedule, and the run that prompted the DISABLE is exactly the one worth reading, so it now needs the watchdog to be configured, not scheduled.
- CHG: an addKey failure in the router script logged only "curl addKey request failed". It now reports curl's exit code and message (35 TLS, 60 CA, 22 HTTP, 7 connect), which is what a stock router failing here needs to say.
- FIX: the router script rewrote `wgcN_enforce=1` on every successful re-negotiation, so a slot created with the kill switch OFF came back ON once the watchdog fired. It now reads the current value before the config write and puts it back; empty - which is always the case on stock, where there is no kill switch - means off.
- ADD: `⏸ WATCHDOG PAUSED` badge in the slot modal for a watchdog whose settings are on the router but whose schedule has been removed - muted grey, since nothing is running. Without it a paused watchdog looked like one that was never configured.
- ADD: watchdog ENABLE / DISABLE buttons, acting on the cron schedule rather than the tunnel. DISABLE drops the two `cru` entries and their boot persistence, keeping the settings, the script and the running VPN; ENABLE puts the schedule back at the interval stored in `wgcN_wd_check_interval`. ENABLE lights up only for a slot with settings and no schedule.
- FIX: DELETE unset the GLOBAL `cfg_pia_wg_user` / `cfg_pia_wg_password` unconditionally, which with two watchdogs would leave the survivor unable to authenticate with PIA. They are now cleared only by the last watchdog standing.
- CHG: the router's cached PIA CA moved from `/jffs/pia_ca.rsa.4096.crt` to `/jffs/cfg-pia-wg/pia_ca.rsa.4096.crt` (`kPiaCaCertPath`, built from the renamed `kRouterAppDir`). The watchdog script now `mkdir -p`s that directory before downloading - it exists on stock, where the user installs jq into it, but not necessarily on Merlin. An old copy at the previous path is simply ignored.
- ADD: `DEL PIA CERT` button on the ABOUT screen, after CREATE GITHUB ISSUE. Confirms, then deletes the cached certificate over SSH, reporting whether one was there. With no router credentials in the session it asks for them inline (prefilled from whatever is there, and kept for later screens) rather than sending the user to a router screen.
- CHG: the clipboard is now emptied through `ClipboardManager.clearPrimaryClip()` on the host instead of by copying an empty string, so exiting the app and the 60s countdown no longer flash Android's "copied" popup at a user who copied nothing. New `clipboard_service.dart` + channel; API 24..27 has no `clearPrimaryClip()`, so MainActivity reports an error and Dart falls back to the old write.
- DOC: dropped the two README notes explaining the "copied" popup on exit and at timer expiry.
- FIX: clearing the DNS field left it blank on re-entry while a generate still quietly used the Quad9 defaults. The field is refilled with `kDefaultDns` on entry and again just before generating, so what it shows is what the config gets. It can still be cleared to retype.
- GUI: the generated config heading now names its region - "GENERATED CONFIG: pia-aus_melbourne" - matching the `pia-<region>.conf` that SHARE / SAVE writes. No region known, no suffix.
- TST: +36 tests (388 -> 424), coverage 96.2%. The deploy-payload ceiling moved 8700 -> 9000 bytes: the CA `mkdir` and the kill-switch read-back cost a line each. `pia_service_test` pins the service's own blank-DNS fallback to `kDefaultDns`, and a new test reads `MainActivity.kt` so the clipboard channel name and method cannot drift from Dart's.

2026-09-03 v0.8.29 build 399 - WIP stock support for Watchdog function

- ADD: an app-wide `AnnotatedRegion<SystemUiOverlayStyle>` (`kSystemOverlayStyle`) making both system bars transparent with light icons, re-applied every frame. `MaterialApp` already pushes light icons for a dark theme, but leaves an opaque black navigation bar that shows against `kBg` on Android 14 and below.
- ADD: main menu carries a "(?) How to use this app" link opening README section 5, "Using the app".
- CHG: dropped the main menu's "Select from the above and/or use the top left (menu icon) menu." hint; the SSH footnote and the help link below it are now centred.
- CHG: the header bar's `kSurface` now runs behind the status bar instead of leaving a `kBg` strip above it. The single `SafeArea` around the whole chrome became two: the header insets its own content, the navigator takes the bottom and the landscape cutouts.
- FIX: "Open source: licenses" screen, bleeding through the About screen between the app header and the "<-" back button at the top of the "Open source: licenses" screen.
- FIX: COPY BUILD INFO had the same gap from the other side - it bypassed the controller, so a countdown left running by a config copy still wiped the build info. It now goes through `copyToClipboard(armAutoClear: false)`, which needs `AboutScreen` to sit under a `SessionScope` (it always does in the app).
- FIX: copying a watchdog log armed the 60s clipboard auto-clear, so the conf screen counted down over it and then wiped it. `copyToClipboard` takes `armAutoClear`; a non-secret copy arms nothing and stands down any countdown left by an earlier config copy.
- FIX: the licences screen opened with a band of the About screen showing between the app header and its back arrow. `showDialog` wraps its child in a `SafeArea`, so the status bar inset still sitting in the navigator's `MediaQuery` was applied a second time below a header that had already cleared it; the navigator subtree now gets `MediaQuery.removePadding(removeTop: true)`.
- INF: Google Play's edge-to-edge notice needs no `enableEdgeToEdge()` call. `flutter.targetSdkVersion` is already 36, where Android forces edge-to-edge with no opt-out, and Flutter enables it on every Android version regardless. Nothing in the manifest or either `styles.xml` sets `statusBarColor`, `navigationBarColor` or the opt-out flag.
- TST: edge-to-edge tested on  on Android 15: gesture and 3-button navigation, landscape with a cutout, the keyboard over the SSH and PIA password fields, the drawer, and each dialog.
- TST: +12 tests (376 -> 388), coverage 96.1%. Simulated status/navigation bar insets pin the header background at y=0, its content and the drawer below the status bar, the HOME button above the navigation bar, and the licences dialog flush under the header.

2026-09-03 v0.8.28 build 398 - WIP stock support for Manage function only

- FIX: text copied from the app LOG screen pasted as one run-on line. The log is now one `Text.rich` with the line breaks inside it, not a widget per entry - `SelectionArea` joins separate widgets with no separator. Entry icons became `WidgetSpan`s and add nothing to the copy.
- GUI: ABOUT screen - removed the "Architecture" and "GitHub source code repository" links. Remaining order: ReadMe, Change log, Security policy, Privacy policy.
- GUI: enable selecting and copying to the system clipboard, text in the build info section of the ABOUT screen. The whole screen is now one `SelectionArea`, so a drag or long-press "Select all" spans the build info, the links and the licence text.
- CHG: ABOUT screen body widgets are plain `Text` rather than `SelectableText` - a `SelectableText` nested in a `SelectionArea` keeps its own private selection and the region skips it. The licences dialog gets its own `SelectionArea` - a region does not reach into a dialog's route.
- FIX: pasting a selection ran the build info rows together ("...releaseCommit hash: ..."). SelectionArea joins the text of separate widgets with no separator, so the rows are now one `Text.rich` with the line breaks inside it.
- ADD: CREATE GITHUB ISSUE button on the ABOUT screen, beside COPY BUILD INFO. Opens `/issues/new` with the title and every section of `bug_report.md` prefilled, the Environment block carrying the same text COPY BUILD INFO produces plus the detected router firmware. The two buttons share a `Wrap` so they fall to a second line on a narrow phone rather than overflowing.
- INF: GitHub applies an issue template OR a `body` parameter, never both, so `bugReportUrl` reproduces the template's headings. A test fails if `.github/ISSUE_TEMPLATE/bug_report.md` gains or renames one.
- DOC: `.github/ISSUE_TEMPLATE/feature_request.md` now names the app.
- DOC: rewrote `.github/ISSUE_TEMPLATE/bug_report.md`. Environment now asks for COPY BUILD INFO output plus router model and firmware version, matching what the app prefills; section headings unchanged, so the drift test still passes.
- ADD: COPY BUILD INFO button on the ABOUT screen, writing the same newline-separated text straight to the clipboard. Not via `SessionController.copyToClipboard`, which arms the 60s auto-clear meant for credentials.
- FIX: the "Open source: licenses" screen repeated packages - `accessibility` appeared 16 times. `LicenseRegistry` yields one entry per licence TEXT, each naming every package it covers, so rendering entries directly repeats a package once per distinct notice. New `groupLicensesByPackage` inverts that: one heading per package, sorted, with its notices underneath, matching Flutter's own licence page. Byte-identical texts collapse; ones differing only by year do not.
- FIX: licence notices are rendered paragraph by paragraph, keeping Flutter's indent and centred-header layout, instead of being flattened into one block.
- INF: expat's ASCII art still reads as run-on text. `LicenseEntryWithLineBreaks` joins hard line breaks with a space before any of our code sees it; Flutter's own licence page shows it identically.
- TST: +24 tests (352 -> 376), coverage 95.8%; `about_screen.dart` reaches 100%. The old licences-dialog test reimplemented the dialog inline and asserted only that an AppBar existed, so it could never have caught this; replaced with one that opens the real dialog against a seeded LicenseRegistry. Cover the link order, ARCHITECTURE.md being gone, the selection region, no nested `SelectableText`, the line breaks surviving a copy, and the COPY button.

2026-09-03 v0.8.27 build 397 - WIP stock support for Manage function only

- FIX: update "HOME" button grey -> teal in slot modal, and the screen HOME button in `app_scaffold.dart` (text and border) to match.
- FIX: DELETE left `wgcN_enable` behind. It was already being unset, but `stop_vpnc` returns as soon as `notify_rc` queues it, so the firmware rewrote the key afterwards. DELETE now waits for the slot to leave `wg show interfaces` first, bounded by `verifyPollInterval` / `verifyMaxAttempts`.
- FIX: DELETE now also unsets `vpncN_dut_disc` / `vpncN_sbstate_t` / `vpncN_state_t` (`kVpncRuntimeKeys`), stock only - Merlin does not use VPN Fusion.
- FIX: runtime keys are indexed by `vpnc_clientlist` field 7, not the slot number - wgc1 leaves `vpnc9_*`. New `vpncStateIndexForSlot`, read from the record before it is removed, falling back to `10 - slot`. The earlier slot-number reading came from wgc5, where both are 5.
- INF: one profile carries three indexes - slot number, clientlist row (`vpnc_unit`), and field 7. See ARCHITECTURE.md 4.2.
- INF: `vpncN_dns` also survives a stop; deliberately left out of the sweep.
- FIX: ACTIVE badge stayed on a slot after DISABLE until the modal was reopened. The modal did refresh; `disableSlot` just returned before the tunnel was down, so the refresh read a stale `wg show interfaces`. It now settles first, as DELETE does. `_revertEnable` too.
- CHG: DISABLE is greyed once a MANAGE slot is down; it stays live if the interface is up even when the enable flag reads 0, so a running tunnel is never stranded behind a greyed button.
- TST: +25 tests (327 -> 352), coverage 93.8%. Includes regressions for the reported cases: deleting wgc1 clears `vpnc9_*` not `vpnc1_*`, and the ACTIVE badge clears after DISABLE without reopening the modal.

2026-09-02 v0.8.26 build 396 - WIP stock support for Manage function only

- GUI: append all router and app log messages to include the description (region name), eg "Enabling wgc1..." -> "Enabling wgc1:pia-aus_melbourne...". New `slotLabel` / `fetchSlotLabel` in `router_slot_service.dart`; the description is read from `vpnc_clientlist` field 0 on stock and `wgcN_desc` on Merlin, cached per service instance so it costs one extra nvram read per action however many lines mention it. Best-effort: a failed lookup degrades to the bare `wgcN` rather than breaking the action or masking its error. Raw router output echoed into the log (`wg show interfaces: wgc1`) is left verbatim.
- GUI: alter EDIT dialogue box heading to show the slot:description eg wgc1:pia-aus_melbourne. The description is passed in from `fetchSlots` rather than read from the nvram map, because on stock a WebUI-created slot has no `wgcN_desc` mirror to read.
- GUI: preface slot descriptions with "pia-" to avoid confusion with other VPNs on the router. Applied by one helper (`slotDescFor`) at both write sites - MANAGE create and the watchdog dialog's region pick - so the two cannot disagree on naming. Idempotent, so re-saving an existing slot never yields "pia-pia-".
- FIX: that prefix would have broken the watchdog. `wgcN_desc` doubles as the PIA region id for the router script's `select(.id==$id)` lookup, so the script now derives `REGION="${DESC#pia-}"` and looks up on that, while its logs and its NVRAM write-back keep the full stored name. Tolerates descriptions written before the prefix existed. Payload grew 8376 -> 8496 bytes (Merlin), 8206 (stock).
- TST: +16 tests (311 -> 327), coverage 93.8%. Covers prefix add/strip round-tripping, label formatting and both firmware lookups, the best-effort fallback, the enable/disable/delete log lines, the EDIT heading, and the script's region strip.

2026-09-02 v0.8.25 build 395 - WIP stock support for Manage function only

- CHG: MANAGE slots now run concurrently. `_enableManage` no longer disables every other slot first - the "one active at a time" sweep is gone from both firmwares. Hardware step 7 (enable wgc5 while wgc1 is up) failed because that sweep was doing exactly what it was written to do; the sweep, not the badge, was the thing to change.
- ADD: concurrency gate. Stock caps simultaneous tunnels, so ENABLE counts the other interfaces that are up and refuses beyond the cap with a "VPN limit reached" dialog naming the ASUS limit and asking the user to disable a slot. No router writes happen when it refuses. Merlin has no cap key, so it is never gated.
- ADD: `RouterSlots.maxActiveSlots` (`int?`, null = unlimited) read from `nvram get vpnc_max_conn`, falling back to `kDefaultStockMaxActiveSlots` (2) when missing or unparseable - follows the router's own setting rather than hardcoding 2.
- TST: +8 tests (303 -> 311). Two tests that encoded the old one-active rule were inverted; new cases cover the cap at 2, refusal of the third, a non-default cap, the target slot not counting against itself, and Merlin being uncapped.
- DOC: `.claude/CONTEXT.md` 4.4 / 4.5 / 4.13 updated for concurrent slots and the cap.

2026-09-02 v0.8.24 build 394 - WIP stock support for Manage function only

- FIX: stock disable never stopped the tunnel. `disableSlot`, `_revertEnable` and `deleteSlot` issued `service restart_vpnc`, which clears `wgcN_enable` and `vpnc_clientlist` field 6 - so the WebUI reads "disconnected" - while leaving the interface up in `wg show interfaces`. Now `service stop_vpnc` per `ARCHITECTURE.md` 4.2.3. This is the root cause of "wgc5 shows ACTIVE with no tunnel running": the badge was telling the truth.
- FIX: `vpnc_unit` is the 0-based **row index** of the slot's record in `vpnc_clientlist`, not `5 - slot`. The WebUI can only create profiles in slot order 5,4,3,2,1, so on any list it built the two agree - which is how the wrong rule went unnoticed. The app lets the user pick any slot: with rows `[slot 5, slot 1]` the old rule asked for unit 4, a row that does not exist, and wgc1 never came up. Measured against the WebUI (rows `[slot5, slot1]` -> it writes `vpnc_unit=1`). New pure helper `vpncUnitForSlot`; all four stock service calls now route through `RouterSlotService._runVpncService`.
- FIX: `RouterSlots.activeSlot` (`int?`) is now `activeSlots` (`Set<int>`), built from `allMatches` rather than `firstMatch` of `wgc(\d)` in `wg show interfaces`. `firstMatch` badged whichever interface `wg` happened to print first - the "ACTIVE flag is incorrect (slot 3 not 1)" symptom. NB manage ENABLE still enforces one active slot at a time, so this is groundwork for the planned two-concurrent-slot support rather than a visible change today.
- FIX: manage ENABLE now sweeps other slots on `enabled || activeSlots.contains(n)`. The flag alone missed a tunnel that was still up while its flag already read 0.
- CHG: `enableSlot` commits NVRAM **before** the service call, matching the other three paths, so the service can never read a half-written slot.
- CHG: replaced the temporary `DEBUG:` log lines with permanent, readable ones naming the resolved unit and its row.
- ADD: enabling a slot with no `vpnc_clientlist` profile now fails with an actionable message instead of silently poking a non-existent unit; stopping such a slot is a no-op.
- TST: +17 tests (286 -> 303), all passing; coverage 93.7%. Covers both `stop_vpnc` vs `restart_vpnc`, the row-index derivation including the out-of-order case that reproduces this bug, multi-interface `activeSlots`, and the ENABLE sweep.
- DOC: `ARCHITECTURE.md` 4.2 / 4.2.2 / 4.2.3 corrected - `vpnc_unit` diagram, ordering constraints, and a warning that `restart_vpnc` does not stop a tunnel. `.claude/CONTEXT.md` 4.4 / 4.5 / 4.13 updated.

2026-09-02 v0.8.23 build 393 - WIP stock support for Manage function only

- FIX: updated enable and disable with correct stock calls, set `vpnc_unit` then calling `service restart_vpnc`.
- FIX: reverted 391 "enabling a slot in manage fails with attempt to start incorrect device number", restored `upsertVpncRecord` & `removeVpncRecord` (Claude).
- FIX: reverted 392 `router_slot_service_test.dart`: `upsert appends a new record when the slot has none` and `disableSlot clears the vpnc active flag`.
- CHG: set source in `vpnc_clientlist` to cfg-pia-wg, and password (field 5) to password
- FIX: sets `vpnc_clientlist` fields 10 (tunnel) and 11 (wan_idx) to 0 to match creating via WebUI.
- FIX: now removes `ep_addr_r` on slot delete.
- CHG: updated `scripts\read-vpnc_clientlist.sh` displayed field names.
- FIX: updated `test\router_slot_service_test.dart` to account for vpnc_client list fields being set (4 - password, 9 - tunnel, and 10 - wan_idx).
- CHG: updated ARCHITECTURE.md field schema & worked example to be zero based (to match code) and updated field contents to match code.
- ADD: slot enable DEBUG print showing `vpnc_unit` and `wg show interfaces`. Also added logrouter to match applog "Enabling wgc$slot...".
- REL: all tests passing.

2026-09-01 v0.8.22 build 392 - WIP stock support for Manage function only

- FIX: `router_slot_service_test.dart` - 2x vpnc_clientlist parsing, 1x stock slot mutations disableSlot; caused by buiuld 391 change to serialisation of vpnc_clientlist.
- DOC: extensive updates to `ARCHITECTURE.md` describing stock flows, commands, parameters, and settings.
- REL: all tests passing.

2026-08-31 v0.8.21 build 391 - WIP stock support for Manage function only

- TST: accepted 70% coverage on about_screen: 27 lines are in private implementation details `_LicensesDialog`, `_LicensesDialogState` build methods and `_launch()` method with URL launcher calls. Hard to test because GestureRecognizers inside TextSpans cannot be tapped in widget tests and URL launcher requires platform channel mocking that conflicts with tap simulation.
- CHG: altered verifyMaxAttempts to 5 (10s), was 30 (60s) then 15 (30)s; how many times to try to connect on this interface before pronouncing it dead.
- FIX: Updated `lib\router_slot_service.dart` as stock requires a different stop command to Merlin; updated in `disableSlot` and `_revertEnable` (now using `service stop_vpnc` instead of `service "stop_wgc $slot"; service restart_vpnrouting0` - retained Merlin behaviour).
- FIX: enabling a slot in manage fails with attempt to start incorrect device number.
- FIX: reverted `enableSlot` check `isStockFirmware` - to be retested.

2026-08-31 v0.8.20 build 390 - WIP stock support for Manage function only

- REL: updated shell scripts to LF from CRLF.
- REL: moved plans to own folder.
- CHG: added a conditional `sleep 10` to `S50downloadmaster.sh` - only runs once at boot. This fixes a blocking issue: something inside the boot process which I can't see expects a delay before the DM script completes, if there's no delay the boot process goes into a blocking state (but ONLY if a VPN is set to activate on boot). The original `S50` scripts had several `sleep` statements, so this is a matching hack, unclean and unwelcome, but this fixes it :/
- TST: update unit tests to match new template file and the changes to tunnel verification (from v0.8.18 build 388); all tests now passing.
- TST: updated tests to increase coverage of lib\screens\about_screen.dart.

2026-08-31 v0.8.19 build 389 - WIP stock support for Manage function only

- DOC: reorganised files, moved `.\scripts\S50*` to `.\.watchdog-implementation`
- REL: set LF as default with `.gitattributes`

2026-08-30 v0.8.18 build 388 - WIP stock support for Manage function only

- CHG: updated `scripts\read-vpnc_clientlist.sh` to read from nvram, field names shown too.
- CHG: updated comment in `scripts\S50downloadmaster.sh` header - this is only a test script, used to mimic Download Master running, setting its env variables, posting a log message every 5 minutes, and exiting with a 0. Router fails to load at boot (blocking behaviour) unless this script execs and exits with a 0.
- CHG: updated `enableSlot` in `router_slot_service.dart` - Merlin uses per vpn start commands `start_wgc 5; restart_vpnrouting`, WebUI uses whole of vpn restart with `service restart_vpnc`.
- CHG: `pingViaSlot` in `router_slot_service.dart` - stock ping does not honour pinging by interface name, must use IP address instead.
- INF: deleting a slot when on stock leaves behind **all** nvram keys, cfg-pia-wg removes them (as it should!).
- INF: `wgcN_desc` is set on stock as the watchdog needs somewhere easily accessible to get the slot name from, otherwise we'd need to implement parsing nvram's `vpnc_clientlist` in the router deployed script (which is getting close to the heredoc size limit).
- CHG: v0.1.1 `S50downloadmaster-TEMPLATE` & , removed `sleep 10` was nice to have correct router log timestamps but this script gets called often by the router and was unnecessarily slowing exec down.
- INF: if S50downloadmaster-TEMPLATE has 0 sleep, router blocked if a VPN is set active, try sleep 3, try 5, try 9 OK!. Polling `nvram get success_start_service=1` with a 1s interval fails as it is likely set after kernel init completes. The issue is that the script execs in the boot process and stalls other services if there is no delay after it runs.
- FIX: `scripts\S50downloadmaster.stock.sh` had mangled lines, re-extracted. Created `scripts\S50downloadmaster.stock-logging.sh` to log sleep functions in original script.
- ADD: added `scripts\S50asuslighttpd*` for testing: use that instead of DM?

2026-08-28 v0.8.17 build 387

- CHG: implemement stock support.
- CHG: updated get-pins.sh to point to new install location `/jffs/cfg-pia-wg`.
- CHG: on stock implement stock firmware slot naming with NVRAM variable `vpnc_clientlist`
- CHG: on stock add watchdog (wd) script and tie to `cru` entry, convert wd script to use `/jffs/bin/mailsend-go` and `/jffs/bin/jq` (store binaries on `opt`?).
- CHG: Convert to use `sendmail-go` (**no** mta on stock firmware)
- CHG: install replacement `S50downloadmaster.sh`.

2026-08-29 v0.8.16 build 386

- CHG: pre-implemement stock support.
- FIX: version and build number.

2026-08-29 v0.8.15 build 385

- CHG: updated `.claude\plan_add_stock_support.md` - added services-start workaround to prompt.
- CHG: removed DISABLED MERLIN placeholders from code.

2026-08-29 v0.8.14 build 384

- ADD: added `S50downloadmaster.stock.sh` to the repo, this is the original stock firmware script + added a "properly" formatted version, my eyes were bleeding re-reading the stock script!
- CHG: set `sleep 10` (seconds) in `S50downloadmaster.sh`, 60 caused issues with blocking as this script runs whenever the firewall is restarted, 0 also caused issues, and 10 is a compromise. Try 5, but might not work well on lower powered processors.
- DOC: added `.claude\plan_add_stock_support.md`.
- DOC: extensive updates to `ARCHITECTURE.md` to account for the nvram differences between Merlin and stock.
- DOC: updated `.claude\context.md`, a complete rewrite.
- DOC: updated `BUILDING.md` with name of new `scripts\pin-actions-latest.sh`.
- DOC: updates to README.md on enabling support for Stock firmware.
- GUI: changed wording of exit app confirmation screen to "Exit cfg-pia-wg?"
- NOTE: having more than two concurrent WireGuard slots is not supported on stock firmware but can be overridden by `nvram set vpnc_max_conn=X; nvram commit` - enabling 5 causes issues at boot (no VPNs connect).
- REL: added .gitignore exclusion for `./gradle` folder
- REL: ported `build.ps1` to `build.sh` (bash version wasn't in sync with the PowerShell version).

2026-08-28 v0.8.13 build 383

- DOC: generated new `CONTEXT.md`
- DOC: add .claude plans for context creation.
- ADD: `./scripts/get-latest-tag.sh` - gets the latest tag from GitHub, used to confirm latest tags for specific GitHub actions, e.g. kevin-david/promote-play-release

2026-08-19 v0.8.12 build 382

- CHG: optimised scripts/S50downloadmaster.sh, fixed DEBUG bug.
- REL: set workflow permissions, add 5m timeout, limit concurrency, and validate inputs in `promote.yml`

2026-08-19 v0.8.11 build 381

- Solved: (but not implemented) we now have a way to run the watchdog script on stock firmware.
- Solved: (but not implemented) we now have tools to replace `jq` and `sendmail` on stock firmware.
- Solved: (but not implemented) can now support all app functionality on stock firmware, including watchdogs, and email alerts.
- CHG: added `scripts\S50downloadmaster.sh` - example of how to add a cron job to run the watchdog script every 5 minutes, triggered by installing Download Master. This is a workaround for stock firmware which has no boot hook. Curently just prints a msg to the router log every 5 minutes.
- CHG: added `scripts\extract-with-context.ps1` to extract a section of a router log file with 1 lines before and after the match "cfg-pia-wg_cru", used for checking `S50downloadmaster` is running correctly.
- REL: material_color_utilities maintainers have fixed the issue with their package resolving to different versions on Windows/Linux.

2026-08-17 v0.8.10 build 380

- REL: updated pubspec.lock

2026-08-17 v0.8.09 build 379

- REL: updated pubspec.lock to reflect latest dependency versions

2026-08-17 v0.8.08 build 378

- REL: merged dev to main

2026-08-17 v0.8.07 build 377 (dev)

- REL: upgraded W11 from Flutter 3.44.8 to 3.47.0 (Dart 3.13.0 DevTools 2.60.0) with `flutter upgrade --force`
- REL: updated Flutter dependencies with `flutter pub upgrade --major-versions`
- REL: fix `pubspec.lock`
- REL: added `analysis_options.yaml` exclusions

2026-08-17 v0.8.06 build 376 (dev)

- REL: updated dependency dartssh2 3.0.2 (was 2.22.5).
- TST: fix 'RecordingSSHClient.close' ('void Function()') isn't a valid override of 'SSHClient.close'.
- CHG: fix double declaration of '_licencesRecognizer'.
- GUI: fix About open source license font size, format now consistent with other text in the screen.
- GUI: reformatted License screen to match the About screen, added scrollable text, and added a back button to return to the About screen.
- GUI: enable About screen text selection and copy to the clipboard (only one line at a time :/).

2026-08-16 v0.8.05 build 375 (dev)

- REL: codeql-action updated

2026-08-13 v0.8.04 build 374 (dev)

- CHG: refactor About screen.

2026-08-13 v0.8.03 build 373 (not released, exploring conversion to stock firmware target)

- CHG: Added "// DISABLED MERLIN" with comments to remove gating check for watchdog function on stock & use downloaded jq, not implemented, just a placeholder for now, still requires Merlin to function.
- CHG: Watchdog script now using `uname -n` instead of `hostname`, as `hostname` not in stock firmware.
- CHG: Added "Open source licences" display to ABOUT screen (was supposed to be in 372 but got missed, reimplemented in 373).

2026-08-10 v0.7.12 build 372

- CHG: CLOSED - not relicensing under GPLv2/MIT/Apache.
- DOC: CLOSED - no longer converting to html - Fix display of TIP, WARNING, and IMPORTANT in README.md after pandoc converts the file to HTML.
- DOC: minor edits to README, fixed URLs.
- GUI: Changed colour of region name from GREY to WHITE in WG Config and Watchdog modals.
- GUI: Hamburger menu item spacing normalised by reducing text (configuration -> config).
- REL: Activated Payment Account in **Google Play Console**.
- REL: Add sbom metadata and license info.
- REL: Added `scripts\get-bins.sh` script - downloads latest `jq` and `sendmail-go` binaries and installs to `/jffs/bin` (for testing with stock firmware).
- REL: Added `scripts\mailsend-go_test.sh` script - sends a test email alert using `sendmail-go` (for testing with stock firmware).
- REL: Added `THIRD-PARTY-NOTICES.md`.
- REL: Added dart_pubspec_licenses for SBOM attestation.
- REL: Converted `update-shas.ps1` to `./scripts/pin-actions-latest.ps1`, updated reference in `build.ps1`.
- TST: Reinstall stock ASUS router firmware - found replacements for `jq` and `sendmail` (`mailsend-go`), see see github.com/jqlang/jq/releases and github.com/muquit/mailsend-go.

2026-08-06 v0.7.11 build 371

- DOC: Add README note on tools to check your exit node
- DOC: Add README note that PIA sometimes takes regions offline for maintenance
- DOC: Added README note on "Watchdog shortcut"
- DOC: Fix broken centering of images and headings
- DOC: README format change to bullets
- DOC: Rewrote README.md section 1-3, added data from an indicative test comparing OpenVN throughput with WireGuard, added "why use wireguard" heading.
- REL: Built and tested OpenWRT under Hyper-V as a potential future port to support TP-Link routers (which have no user accessible SSH or dropbear), deferred.

2026-08-05 v0.7.10 build 370

- REL: sequenced backlog
- REL: renamed promote.yml job name from "Promote Release to Production" to "Promote release"

2026-08-05 v0.7.09 build 369

- REL: `promote.yml` now uses kevin-david/promote-play-release
- REL: Renamed update-shas.sh to ./scripts/pin-actions-latest.sh, updated reference in build.sh

2026-08-05 v0.7.08 build 368

- REL: `release.yml` now uses `pubspec.yaml` to parse current build and release.
- REL: `release.yaml`, discards AAB after sucessful upload to PS
- REL: Updated `./scripts/update-shas.sh` to stop using API returned "latest" SHA version (setup java's tag was touched today returning v1.4.5 instead of v5.7.0!), now pulls all versions, sorts, and picks highest release.
- REL: automated update of PS "what's new" with release notes -> "See github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md for changes since last release".

2026-08-05 v0.7.07 build 367

- REL: Updated `release.yal` push aab to PS via API.
- REL: Parse changelog entries by matching against the pushed tag, sort by type and insert as GH release text.
- REL: Added `promote.yml`, promotes PS aab from `internal` track to `production` (configurable under manual workflow run condition).
- TST: Added `test/release/release-notes.sh` to test new automated GH release notes, run from repo root.
- DOC: Split out backlog from `CHANGELOG.md` to `BACKLOG.md`.
- REL: Updated scripts/update-shas.sh
- REL: Added URL redirect from exponentiallydigital.com/cfg-pia-wg/changelog to github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md
- DOC: Added "GB" to "...8, 16, 32, 64 RAM configuations..." in BUILDING.md

2026-08-03 v0.7.06 build 366

- REL: Upgraded Flutter to 3.44.8 from 3.44.5 with `flutter upgrade --force`
- REL: Buildchain updated with `flutter pub upgrade --major-versions` & `.\android\gradlew -p android :dependencies :app:dependencies --write-locks`

2026-08-03 v0.7.05 build 365

- CHG: updated SHAs.
- CHG: updated `android\app\build.gradle.kts` to `base.archivesName.set("cfg_pia_wg") // this sets the name of the .AAB output file`.
- CHG: removed postscript from in app LICENSE display.
- DOC: updated CHANGELOG format.
- DOC: added how to upgrade dependency versions in BUILDING.md "4.1.2. When to regenerate lockfiles"
- REL: updated dependencies: `dartssh2` 2.22.5 & `jni` 1.0.3
- REL: tagged for release.

2026-08-03 v0.7.04 build 364

- REL: renamed app from *cfg_pia_wireguard* -> *cfg_pia_wg* (must use underscores, *cannot* use hyphens)
  1. update `pubspec.yaml` -> name: cfg_pia_wg
  2. search and replace in .dart files -> "import 'package:cfg_pia_wg/"
  3. update `android/settings.gradle.kts` -> rootProject.name = "cfg_pia_wg"
  4. check tests run and app compiles
  5. update `.github\workflows\release.yml` -> mv build/app/outputs/bundle/release/cfg_pia_wg-release.aab
  6. update `scripts\build.ps1`
     1. $TARGET_APK = "build/cfg_pia_wg-v${VERSION}_release.apk"
     2. $APK_RELEASE = "build/cfg_pia_wg-v${VERSION}_release.apk"
     3. $AAB_RELEASE = "build/app/outputs/bundle/release/cfg_pia_wg-release.aab"
  7. update `scripts\build.sh`
     1. TARGET_APK="build/cfg_pia_wg-v${VERSION}_release.apk"
     2. APK_RELEASE="build/cfg_pia_wg-v${VERSION}_release.apk"
     3. AAB_RELEASE="build/app/outputs/bundle/release/cfg_pia_wg-release.aab"
  8. save and exit VS Code, check tests run and app compiles with .\scripts\build all
  9. check app builds on GitHub dev branch
- FIX: can't paste into password fields, and can't "q"uit debug running in any screen showing password fields, also causing screen `D/EGL_emulation(24795): app_time_stats: avg=499.58ms min=498.77ms max=500.27ms count=3` count to increment; **revert build 363 changes** to `lib\widgets\common_fields.dart` and `lib\watchdog_dialog.dart`. Tested and now operating corectly: can "q"uit debugger, no incrementing count and can paste.

2026-08-03 v0.7.03 build 363

- FIX: Disabled ability to copy a password when the field is revealed. (didn't check could paste which is now broken when testing build 364, **reverted changes** in build 364)

2026-08-03 v0.7.02 build 362

- DOC: Update readme with the new name of command line tool - `cfg-pia-wg`.
- FIX: Updated `pubspec.yaml` - app name was showing incorrectly in launchers, updated from "Configure PIA WireGuard" to "cfg-pia-wg".
- DOC: Spellcheck ARCHITECTURE, CHANGELOG, and README.md.
- DOC: Replace ipv4.icanhazip.com in architecture.md, now using ping targets.
- DOC: Add to README.md that screenshots are disabled.
- DOC: Update security.md hotlink for reporting an issue, fix US spellings, remove Inactivity session self-destruct.
- CHG: Router IP address, 192.168.1.1 by default (matches SVG examples) and retained when entered.
- DOC: Add copies of all Claude plans to repo.
- GUI: Display the quad 9 default DNS addresses next to the Cloudflare ones in generate.
- GUI: suggested DNS address help text is truncated.
- BLD: Added warning to understand what the build optimisation script does **before** use.
- DOC: clarified README.md reason for `JFFS` partition enablement for storage of the watchdog script and settings between reboots.
- REL: Drop debug and release builds from Actions workflows, update README.md to account for this
- DOC: added TOC and section numbering to TESTING.md
- ARC: per TESTING.md, the architecture only deploys `/jffs/scripts/services-start` and `/jffs/scripts/watchdog_wgcN.sh` to NVRAM. Other files are written to volatile storage: `/tmp/watchdog_wgcN.log`, `/tmp/watchdog_last_ping_success_wgcN`, and `/tmp/watchdog_backoff_wgcN`. This reduces NVRAM write wear. The watchdog log is not persistent and is rotated at midnight to reduce volatile storage.
- DOC: added note to test that VPN is active after a firmware update (JFFS may be recreated by flashing process).
- GUI: enlarge WireGuard Configuration prompt for PIA credentials so that you can see the example DNS addresses, display is truncated.
- DOC: Update privacy.html to note that URLs in About screen go to locations on the Internet.
- INF: log message "kernel: jffs2: warning: (27325) jffs2_sum_write_data: Summary too big (-32 data, -877 pad) in eraseblock at 00280000", only seen once. No activity from app or script around that time. Checked deployed artifact sizes: 8,346 bytes (watchdog script), 205 bytes (services-start), 2,719 bytes (pia_ca.rsa.4096.crt), 181 bytes (cron entries) -> 11,451 bytes total used by app (typical). Web searches show that this can be ignored: created during NVRAM housekeeping. Likely occured as a result of extensive app testing.
- ARC: check all non critical data written to tmp not JFFS

2026-07-30 v0.7.01 build 361

- REL: Deploy to 'production' on Google Play Store
- CHG: add updated watchdog modal screenshot to Play Store
- REL: Create a GitHub actions release and verify build data in the new "About" screen.
- CHG: removed Watchdog DISABLE and ENABLE menu options + services, rolled capability to CREATE/EDIT.
- CHG: renamed watchdog "EDIT" button to "CREATE/EDIT".
- CHG: PIA username/password now cached while the app is running, no need to keep entering it (this matches the router username/pwd caching).
- CHG: updated text displayed when editing a watchdog slot.
- GUI: app name had reverted from yesterday's backed out changes -> cfg-pia-wg.
- DOC: updated app name in README.
- GUI: updated text when deleting a watchdog.
- CHG: updated watchdog modal screenshot in docs.
- DOC: updated Watchdog functionality changes.
- CHG: no message is written to the router log if you edit and save the watchdog's `cronIntervalMinutes` - the cron job is updated, cosmetic.
- DOC: updated `(FLAG_SECURE)` entry in README.
- DOC: updated Privacy Policy noting in-app links to the app's source code & documentation.

2026-07-29 v0.6.28 build 358

- REL: release.yaml already calls quality_and_security.yml directly via workflow_call whenever a tag is pushed, quality_and_security.yml should not listen for tag pushes directly.

2026-07-29 v0.6.27 build 357, sync build

- REL: current GitHub pipeline runs on commit and tag. Reorganise to run quality_and_security.yml on every commit, and on release, run quality_and_security.yml then release.yaml using shared build artifacts so we don't rebuild the app multiple times in the same workflow run.

2026-07-29 v0.6.26 build 356, sync build

- FIX: build artifact naming in release.yml

2026-07-29 v0.6.25 build 355

- FIX: updated quality_and_security.yml to grant permissions required by the reusable workflow
- FIX: prevented release.yml from skipping checks on manual runs.

2026-07-28 v0.6.24 build 354 (pre–Google Play Store release)

- FIX: every url_launcher link in the app was dead (About screen links, and the header bar's "Exponentially Digital" and version/GitHub links, which last worked in v0.6.21) with `PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.canLaunchUrl")`. Not a url_launcher fault: `android/app/gradle.lockfile` pinned `kotlinx-coroutines-android` to 1.8.1 on the runtime classpaths, but share_plus 13.3.0 declares 1.11.0 and compiles `Dispatchers.IO.limitedParallelism(1)` against it, emitting a call to the `limitedParallelism$default(..., int, String, ...)` bridge whose `name` parameter only exists in coroutines 1.10+. STRICT dependency locking silently downgraded the runtime dependency, so `SharePlusPlugin.onAttachedToEngine` threw `NoSuchMethodError` on startup. Because that is an `Error` and not an `Exception`, `GeneratedPluginRegistrant.registerWith`'s per-plugin `catch (Exception e)` did not catch it: registration aborted at plugin 4 of 5 and `url_launcher_android` was never registered. `package_info_plus` is plugin 3 and registered before the throw, which is why the header still showed a version string and made this look link-specific rather than global. SHARE was broken by the same fault. Fixed by regenerating the lockfiles (`gradlew -p android :dependencies :app:dependencies --write-locks`), which moves the four coroutines artifacts to 1.11.0 on the runtime/lint classpaths - a 4-line lockfile change, nothing else altered. Verified on-device: plugin registration is clean and all eight links open in the browser.
- CHG: rebranded to "cfg-pia-wg": updated all text, icons, and diagrams.
- ADD: added to repo a local copy of the .\play-store\privacy.html file.
- ADD: "About" menu option to the hamburger menu, directly below "View app log". New `AppDestination.about` + `lib/screens/about_screen.dart`, so the drawer tile, route name, selected-state highlight and no-op-on-current behaviour all come from the existing generated-tile machinery. Shows build provenance, tappable links to the repo/README/changelog/architecture/security/privacy documents, and the full GPL v3 text. The security policy link uses `/blob/main/SECURITY.md` - the bare `/SECURITY.md` form 404s.
- ADD: `android/app/build.gradle.kts` now enables `buildFeatures { buildConfig = true }` (AGP 8+ defaults it off and AGP 9 dropped the `android.defaults.buildfeatures.buildconfig` escape hatch, so `BuildConfig` was not being generated at all) and injects `BUILD_TIMESTAMP`, `GIT_COMMIT_HASH`, `GIT_COMMIT_DATE`, `GIT_BRANCH`, `CI_RUNNER_ID`, `COMPILE_SDK` and `KOTLIN_VERSION`. git runs via `providers.exec` (a raw `ProcessBuilder` is a configuration-cache violation) as `git -C <android/>`, and every failure path - git off `PATH`, no `.git` in a source tarball - degrades to "unknown" rather than failing the build. `gitBranch` prefers `GITHUB_REF_NAME` and rejects a literal "HEAD" from the git fallback, because a tag push leaves actions/checkout in detached HEAD where `rev-parse --abbrev-ref` returns "HEAD" and never the tag. `javaStringLiteral()` escapes each value: `buildConfigField` emits its third argument verbatim into `BuildConfig.java`, so a branch named `foo"bar` would otherwise produce uncompilable generated Java. `kotlinVersion` comes from `getKotlinPluginVersion()`; the Kotlin plugin is deliberately *not* added to the app's `plugins {}` block, as Flutter's Gradle plugin already applies it and declaring it again makes Flutter log an AGP-9 migration warning at error level on every build. No new dependencies, so the STRICT lockfiles are untouched.
- ADD: `MainActivity.kt` gained the app's first `MethodChannel` (`...:/build_info` -> `getBuildInfo`), returning a flat `Map<String, String>` of the `BuildConfig` values plus the device-side facts: install source (`getInstallSourceInfo` on API 30+, legacy `getInstallerPackageName` below, mapped to friendly labels), `Build.SUPPORTED_ABIS[0]`, OS version + API level, and versionName/versionCode from `PackageManager`. Deprecation suppressions are scoped to one-line helpers rather than blanketing callers. `super.configureFlutterEngine` is called first - that is where the generated plugin registrant runs, and skipping it silently breaks path_provider, share_plus, url_launcher and package_info_plus.
- ADD: `lib/build_info_service.dart`. `loadBuildInfo` catches `MissingPluginException` and `PlatformException` and returns `BuildInfo.unknown()`; this is load-bearing rather than defensive, since `flutter test` registers no native side and every full-app widget test takes that path. `BuildInfo.fromMap` defaults each missing key individually so a partial reply degrades one row at a time.
- ADD: `lib/license_text.dart` - `./LICENSE` verbatim as a raw-string constant, generated at development time rather than loaded at runtime or registered as a pubspec asset, so the About screen has no I/O path and cannot display a licence differing from the repo's. Regenerate it if `./LICENSE` ever changes.
- CHG: accepted build-speed trade-off for exact provenance: `BUILD_TIMESTAMP` is wall-clock at Gradle configuration time, so `GenerateBuildConfig` is never up to date and every build recompiles and repackages the app module (with `org.gradle.caching=true` this also leaves single-use cache entries). `GIT_COMMIT_DATE` is delivered alongside it as a reproducible cross-check. Note that if `org.gradle.configuration-cache` is ever enabled the timestamp would be frozen into the cache entry and silently go stale.
- TST: `test/screens/about_screen_test.dart` covers the populated screen, all six links, the embedded licence, and three degradation paths (`MissingPluginException`, `PlatformException`, partial host reply). `main_menu_screen_test.dart` gained a case asserting the About tile sits below the log tile and that the screen renders with no channel mocked at all.
- FIX: Restructured logic in calls to `startWatchdog` from `saveWatchdogConfig` & `deployWatchdogScripts` - cosmetic, causes double log entry.
- CHG: Updated Play Store screenshots & short/long description
- FIX: PIA username and password are not cached in device RAM if entered via lib\watchdog_dialog.dart.
- UI: In generate `PIA WireGuard config` modal, add text to say which region the currently displayed config is for, add this next to the GENERATED CONFIG header
- ADD: When editing a watchdog, display what the current region is in the modal, and allow changing this via the region selection screen, can then drop call to region selection which fires on save.
- BUG: from a blank slate when creating a watchdog from scratch, with no underlying VPN created on the slot, causes NVRAM to not be correctly updated and slot status to display incorrectly.
- BUG: unable to reproduce (setting to done): if router stops accepting commands (hung web UI, ASUS Android app, and SSH) but is still routing, and an SSH socket times out creating a watchdog, you are incorrectly told that the slot had been created. Occurred once when router web GUI, ASUS app, and SSH access failed, a router process had died but there was no way to access and check. Probably a router firmware bug, power cycling fixed it, nothing useful in router log though. Retained for completeness.
- ADD: TOCs to ARCHITECTURE, BUILDING, CHANGELOG, CONTRIBUTING, README, SECURITY, and TESTING.
- DOC: Added **About** menu screen to README.
- REL: safety commit save ahead of testing GitHub build with new pipelines

2026-07-28 v0.6.23 build 353

- FIX: update-shas.sh/ps1 were writing two spaces after the SHA e.g. "...890  # v1.01"
- CHG: updated SHAs
- FIX: update all minor version dependencies & release publock on jini 1.0.0; test if 1.0.2 fixes the Gradle bug exposed by 1.0.1 - OK
- FIX: when saving a new watchdog, scan for other watchdogs and delete them before the new watchdog is activated: e.g. deploying a watchdog to slot 5 does not disable an active VPN on slot 1, so you end up with two VPNs running at the same time - apply same logic from 'Manage Router PIA WG Cfg' to disable any other active VPN slots. `RouterWatchdog.deactivateOtherSlots` now sweeps wgc1-5 on both `saveWatchdogConfig` and `startWatchdog`, stopping any other watchdog and disabling its interface. The sweep runs *before* the new config's NVRAM write because `stopWatchdog` unsets the global `cfg-pia-wg_*` credentials.
- ADD: `RouterWatchdog.disableVpnSlot`, mirroring `RouterSlotService.disableSlot` - clears `wgcN_enable`, commits, then stops the interface.
- FIX: `stopWatchdog` issued `service "stop_wgc wgcN"` where the service expects the bare slot index (`stop_wgc N`, per ARCHITECTURE.md), so watchdog DISABLE never actually brought the tunnel down and left an unsupervised VPN running. It now delegates to `disableVpnSlot`, which also clears `wgcN_enable` so the slot cannot return on the next `start_vpnrouting0` or reboot.
- FIX: `probeLatency reports failed probe with progress callback` failed intermittently in the full suite (errno 10048). `probeLatency` dialled a hard-coded port 1337, so faking a responding server meant binding that one global port; three test files need it and `flutter test` runs test files in parallel workers, so they collided.
- ADD: `PiaService.probePort` (default `PiaService.defaultProbePort` = 1337), injectable via `PiaService({probePort})`. Tests now bind an ephemeral port (0) and pass it back in, removing the contention at source rather than serialising the binds behind retry loops. pia_service_test.dart and standalone_config_screen_test.dart were converted and their retry loops deleted; unit/main_unit_test.dart still binds the default port because it drives the real `PiaWgApp` shell, which constructs `StandaloneConfigScreen` itself (app_drawer.dart) and so offers no injection seam - harmless, as it is now the only file binding it.

2026-07-28 v0.6.22 build 352

- FIX: sequenced release.yaml to only run after quality_and_security.yaml successfully completes
- CHG: re-enabled FLAG_SECURE to disable in-app screenshots, hides screen display from task switcher (was disabled during closed testing to allow screenshots), set in `android\app\src\main\kotlin\com\exponentiallydigital\pia_wireguard_cfga\MainActivity.kt`.
- DOC: updated Play Store descriptions
- TST: end-to-end manual retest of the entire app

2026-07-27 v0.6.21 build 351

- Google Play Store release candidate (not deployed)
- ADD: update-shas.ps1 now uses a 24-hour cache
- ADD: update-shas.ps1 added `-ForceRefresh` switch
- FIX: update-shas.ps1 trailing comments

2026-07-20 v0.6.20 build 350

- ADD: added updating of dependencies to build.ps1/.sh (NB major versions are **not** upgraded automatically)
- ADD: allow copy/paste from router log
- ADD: COPY button to the router log display screen
- MOD: optimised, and reduced size of kWatchdogScriptTemplate by 123 chars
- ADD: watchdog shell script now checks for Internet access before attempting repair
- CHG: router watchdog shell script does not ping secondary target if primary is successful
- FIX: updating the watchdog timeout in the UI did not update a pre-existing cron schedule
- FIX: if you created a VPN via the watchdog interface, it was showing as enabled when it was not. Removed reminder to set it to active; when saving, the watchdog script is deployed and runs immediately.

2026-07-20 v0.6.19 build 349

- updated GitHub action SHAs to latest versions
- updated tests test\screens\standalone_config_screen_test.dart and test\screens\standalone_config_screen_test.dart to run in parallel
- added update-shas.sh, a direct conversion of the update-shas.ps1 script
- build.ps1/.sh scripts now run update-shas.ps1/.sh ahead of building to ensure these are always up-to-date

2026-07-06 v0.6.18 build 348

- set minSdk = 24 (Android 24, Android 7.0 Nougat) in android\app\build.gradle.kts
- source code grammar and spelling (non-functional changes)
- reverted internal name space to "com.exponentiallydigital.pia_wireguard_cfga" in MainActivity.kt, proguard-rules.pro, build.gradle.kts, and settings.gradle.kts. This was part of the rename several commits ago but I found that this would have forced a complete restart of the Google Play closed test.
- updated actions/setup-java SHA to latest version
- updated dependency locks with "cd android; ./gradlew dependencies --write-locks"
- updated BUILDING.md to note how to upgrade flutter packages to their latest compatible build

2026-07-06 v0.6.17 build 347

- temporary change to allow screenshots to be taken (to allow Android testers to prove that they have the app installed and are testing it - "SwapTest - 12 Testers")

2026-06-29 version 0.6.16+346

- updated GitHub actions dependency versions

2026-06-29 version 0.6.15+345

- modified readme formatting, added build chain details, normalised brand name convention

2026-06-25 version: 0.6.14 build 344

- after auditing the router's file system, it was found that `/usr/sbin/curl` writes a command line history to `/jffs/curllst` with file permissions 666 (!), this log file is also rotated and my exist as `/jffs/curllst.1`. There appears to be no way to stop this file being generated/used, so the bash script empties the file after every `curl` execution ;)

2026-06-25 version: 0.6.13 build 343

- added indicator to slot display if email alerting is enabled
- line-by-line port of `build.sh` to `build.ps1`

2026-06-25 version: 0.6.12 build 342

- added patreon/paypal donation buttons

2026-06-25 version: 0.6.11 build 340

- no functional changes
- modified modals to use 100% of vertical screen (was pixel based)
- updated human visible play store app name from `pia_wireguard_cfga` to `cfg_pia_wireguard`, internal name retained (v painful if change in G Store)
- confirmed private app datastore contains 0 sensitive data, examined output from

```bash
`C:\Users\andrew\AppData\Local\Android\sdk\platform-tools\adb.exe exec-out "run-as com.exponentiallydigital.pia_wireguard_cfga tar c ." > C:\Users\andrew\Desktop\app_dump.tar`
```

2026-06-25 version: 0.6.10 build 340

- no functional changes
- changed internal build name back to "com.exponentiallydigital.pia_wireguard_cfga" from "com.exponentiallydigital.cfg-pia-wg". Google does not allow a project name change, doing so would require an entirely new app store listing :/
- added 512x512 icon for Play Store

2026-06-26 version: 0.6.09 build 339

- released: complete UI overhaul + self-healing watchdog function
- fix deployment yamls

2026-06-26 version: 0.6.08 build 338

- merge development to main

2026-06-26 version: 0.6.07 build 336

- FIX disposed-controller crash when the app prompts for PIA username/password and DNS during router slot creation (only occurs if PIA username/pwd not cached in RAM).

2026-06-25 version: 0.6.06 build 334

- updated build SHAs
- added field descriptions to kSlotNvramKeys
- extensive updates to README, SECURITY, and TESTING documentation, added new app screenshots
- renamed nvram variable from `pia_wg_cfga` to `cfg-pia-wg`
- FIX deleting a managed slot does not unset: `wgcN_wd_primary_ip` and `wgcN_wd_secondary_ip`

2026-06-25 version: 0.6.05 build 334

- Manage router
  - Only one interface active at a time — ENABLE first disables any other active interface (and its watchdog); ENABLE is greyed when the selected slot is already enabled.
  - DISABLE and DELETE also stop the slot's watchdog; DELETE's confirmation shows the slot description.
  - CREATE now writes wgcN_enforce=0 (kill switch off).
  - CREATE / ENABLE / DISABLE / DELETE and the ENABLE ping-check are logged to the router syslog (cfg-pia-wg), not just the app log.
- Watchdog management
  - ENABLE and DELETE are greyed for an empty slot; only one watchdog active at a time (ENABLE stops any other active watchdog first).
  - DELETE confirmation reads exactly "This will also delete and disable the underlying region."
  - Configuring a watchdog on an empty slot pops a "remember to ENABLE" reminder (matching CREATE).
  - deployWatchdogScripts logs the region too (e.g. "Deployed watchdog script for wgc5, aus_melbourne"). EDIT prefills PIA credentials (already wired; verified).
- Slot editor / modal
  - The read-only row now shows "Enabled YES/NO". The modal's HOME button returns to the main menu (not the router login).
- UI / shell
  - The 10-minute inactivity timer, countdown, and global activity listener are removed entirely (clipboard 60-second auto-clear kept).
  - Router screens default to the shipped router address / admin; once connected, re-entering a router screen auto-reconnects and opens its modal.
  - Every exit path (back key, menu "Exit app", drawer "Exit app") now confirms before wiping + exiting.
  - Main menu shows a green hint with an inline hamburger icon; the drawer "HOME" entry is grey and navigates to the menu; the active destination shows green (fixed: the tiles' explicit text colour had been overriding selectedColor, and the route observer now ignores dialog routes so the active item stays green while a modal is open).

2026-06-25 version: 0.6.04

- change from `pia-wg-cfga` to `cfg-pia-wg` as router log prefix
- renamed `pia_wireguard_cfga` to `cfg-pia-wg` in all build scripts, tests, and settings files
- add `flutter analyse` to build scripts, actions, and docs
- updated quality_and_security.yml to use java 21 (was 17 in some places), this matches the local build envs. V25 breaks local dev tool chain.
- added version number to release assets created by `build.ps1` and `build.sh` (matches GitHub Actions release script)
- updated slot edit text
- renamed menu entry from "VPN watchdog management" -> "Watchdog WireGuard management"
- watchdog shell script, changed log message from "Checking wgc1 connectivity" to "Checking wgc1 aus_melbourne connectivity"
- updated text for overwriting watchdog config with a different region
- dropped "standalone" from menu item name
- renamed modal screens from WireGuard/watchdog "slots" to "configuration"
- hamburger menu "Close app" -> "Exit app"
- slot modal "(Empty Slot)" -> "<\empty slot>"
- change "CLOSE" button on each of the 4 option screens -> "HOME"

2026-06-24 version: 0.6.03

- no code changes, updated extensive to do list

2026-06-23 version: 0.6.02

- no code changes, extensive to do list generated
- added actual prompt used to ui_reorganisation.md
- rebuilt icons
- changed build.sh to use bash shell (doesn't execute under WSL, check why!)

2026-06-23 version: 0.6.01

- FIX local env issues (commit not sent correctly, VSC issue)

2026-06-22 version: 0.6.00

- implemented `.claude\ui_reorganisation.md` to fundamentally rebuild the user interface.

2026-06-23 version: 0.5.14

- further updated `.claude\ui_reorganisation.md`, this fundamentally rebuilds the user interface.

2026-06-22 version: 0.5.13

- significantly updated `.claude\ui_reorganisation.md`

2026-06-22 version: 0.5.12

- removed unused variable in test\router_push_sheet_test.dart
- updated assets to match rebranding

2026-06-22 version: 0.5.11

- Rebranded and renamed from `pia-wireguard-cfga` "PIA WireGuard Config" to `cfg-pia-wg` "Configure PIA WireGuard"

2026-06-22 version: 0.5.10

- moved `watchdog_wgc$slot.log`, `watchdog_last_ping_success_wgc$slot` and `watchdog_backoff_wgc$slot` files from `/jffs` to `/tmp` to reduce NVRAM writes
- renamed email alerts from "PIA Watchdog Alert" to "cfg-pia-wg"
- fix script deployment (heredoc limit reached) by optimising and reducing package size
- updated alert email subject
- updated watchdog connectivity testing logging text
- updated tests to match new `watchdog_wgc__SLOT__.sh`
- fixed test not returning `Successfully retrieved router config.`
- added WIP `ui_reorganisation.md`

2026-06-21 version: 0.5.09

- fix removed unused `commitCount` test variable
- fix test `Step 1: pushToRouter Error Recovery experiences a CRITICAL Failure`, `FakeSSHClient` wasn't reaching the catch block
- fix test `Step 1: pushToRouter triggers Error Recovery and restores backups successfully` self-resetting flag that crashes the first command of the write phase to trigger the recovery loop, then immediately disables itself so the subsequent rollback actions can succeed

2026-06-21 version: 0.5.08

- ??? pushing to wgc5 (perth) did not disable wgc1 (Melb), due to a change I made...where was that!
- found it, `stopWatchdog`, in `lib\router_watchdog.dart`: had commented out `await _run('service "stop_wgc wgc$slot"; service start_vpnrouting0');` now re-enabled that line (and it works again, no more multiple VPNs running concurrently!)

> [!NOTE]
> If slot 1 was active and a watchdog was deployed to it, it remained active even if slot 5 was made active and a watchdog deployed to that slot, so we end up with multiple watchdogs, added to the `to do` list to note in the docs that the watchdog is only for one slot at a time. Who runs multiple VPNs on different slots? Maybe someone does, just like having more than one WG VPN active concurrently. Ping me if this is an issue!

- fix new sendmail commands causing errors: moved `-CAfile` and `-verify_return_error` back inside the OpenSSL quoted string, replaced `timeout 10 openssl` with `openssl -timeout 10`

2026-06-20 version: 0.5.07

- fix CA cert check (wrong variable tested)
- fixed unit tests (testing on prior version's value)
- removed unnecessary `nvram commit` x2
- restart interface to flush routing on watchdog removal
- on failed write of current slot restart only that slot, not a full WG restart
- added warning to `scripts\build-optimisation.sh` header (caveat emptor)
- fix services-start permission is 777 on uninstall
- normalised router send email command: re-sequenced, added -verify_return_error, added space after "H", removed -amLOGIN, removed test from messageID
- added 3-layer mail send failure: sendmail exit code, sendmail's stderr, and any detail from the underlying openssl handshake
- added same error checking to test email send function invoked by the UI through `buildSendmailCommand` and `testEmail`
- updated test email header and body generation per RFC-822, now matches shell script
- renamed "DEPLOY WATCHDOG" to "WATCHDOG CONFIG" because you can set/unset from there not just deploy
- fixed tests to match current code

> [!NOTE]
>
> - **ADD** removal of `wgcN_ep_addr_r` & `wgcN_rrip` (explicit delete in `_pushToRouter` at service stop)
> - Potential Merlin bug discovered: these are left set to prior values if the slot is set to `default` in the GUI

2026-06-20 version: 0.5.06

- extra router logging added to `` script
- cache PIA CACERT
- added `--fail` to curl
- added check that CA cert is valid
- optimised `/jffs/scripts/watchdog_wgcN.sh` `sed` and `jq` calls
- replace multiple `curl` commands with `$CURL` to assist with code maintenance

2026-06-20 version: 0.5.05

- fix, added encoding of PUB and PVT keys with `/jffs/scripts/watchdog_wgcN.sh` script curl
- fix transient error, added sleep to final interface up commands in `/jffs/scripts/watchdog_wgcN.sh` script
- fix transient error, removed unnecessary `wg setconf "$IFACE" "$TMPCONF"` from `/jffs/scripts/watchdog_wgcN.sh`

2026-06-20 version: 0.5.04

- change "WATCHDOG.." to "DEPLOY WATCHDOG"
- NVRAM now cleared when watchdog disabled (wgcN + PIA creds)
- `command` doesn't exist on busybox, replaced with `which`

2026-06-20 version: 0.5.03

- added message ID to email template
- rename "clear creds & cfg" rendering off screen -> "CLEAR ALL", updated tests & projects docs to match
- fix local IP address (added `--interface $wgc$slot`)

2026-06-20 version: 0.5.02

- added TESTING.md, covers manual email testing

2026-06-20 version: 0.5.01

- implemented a feature to automatically maintain a persistent WireGuard VPN on the router

2026-06-19 version: 0.5.00

- refined watchdog.md
- version bump ahead of watchdog implementation

2026-06-19 version: 0.4.35

- updated watchdog.md

2026-06-19 version: 0.4.35+325

- fix typo in lib\router_push.dart array for the 'psk'
- formatting of license header in dart modules
- updated context.md
- added watchdog.md, requirements and spec for setting up the new watchdog feature

2026-06-16 version: 0.4.34+324

- employed AI MOE to update scripts/build-optimisation.sh (which was a terrible outcome, build performance dropped!)
- finally started using a develop branch (about time!) :)

2026-06-15 version: 0.4.34+324

- FIX environment error in scripts/build-optimisation.sh, wrong units used, attempted a 2PB RAM allocation (!)

2026-06-15 version: 0.4.33+323

- updates to setting up an automated script for the build environment

2026-06-15 version: 0.4.32+32

- updates to setting up an automated script for the build environment

2026-06-14 v0.4.32 build 322

- split out build info to separate file
- moved additional scripts to own folder
- added build environment optimisation script
- added play store folder to version track submitted description
- moved documentation sections from README to ARCHITECTURE.md, BUILDING.md, and CHANGELOG.md

2026-06-13 to 2026-05-31

- add how to install `fcr` for HTML coverage report
- feature/router-push merge to main & release
- add README badge(s) for automated pipeline security & quality tests
- refactored \_pushToRouter(), FIX WAN IP address determination
- fix table display on README
- add push to router steps & screenshots
- added extensive build environment setup and config notes to README
- added flow chart to readme
- updated permission use (clarified)
- add feature "push cfg to router"
- increase automated tests to >90% of the codebase
- added timestamps to LOG
- update java version to 21(17)in release and code scan yaml
- update screenshots for phone, 7" and 10" tablets showing clipboard clearing
- rebuild release output files (drop zip, include 3 versions)
- include software BOM (bill of materials) in release artifacts
- add how to privately report a security vulnerability (enabled in GitHub)
- create SECURITY.md
- enable dependabot
- implement local PS1 app to replace tags with SHAs
- add SBOM as a release artifact (Syft)
- fixup html intermediary file name (caused resultant doc title issue)
- renamed `$ADDON` to `$RELEASE` in release.yaml (was carried over from WoW addon packaging)
- split release.yaml into code scan and actual release
- automated security/quality analysis: Flutter analyse, SonarCube, Google OSV dependency scan, Mobile security scanning (MobSF), Dependabot depende
