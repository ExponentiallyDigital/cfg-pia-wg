# 1. CHANGELOG.md

- [1. Changes](#1-changes)
  - [1.1. Pending to do](#11-pending-to-do)
  - [1.2. WIP](#12-wip)
  - [1.3. Implemented - chronological change history](#13-implemented---chronological-change-history)

---

## 1. Changes

### 1.1. Pending to do

See [BACKLOG.md](https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/BACKLOG.md) for "deep" backlog.

- DOC: Sequenced documentation updates: ARCHITECTURE, TESTING, README, COINTEXT.
- BUG: when deploying a watchdog (even with build 429) while saving, the spinner is below the fold and the last edited field is showing as editable. This has been a repeating issue across multiple builds.
- commit.
- ADD: implement RevenueCat.
- commit.
- REL: release **v8.x.y** to GPS alpha track, review [Play Console technical quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799), specifically:
  - [r8-analyzer/SKILL.md](https://github.com/android/skills/tree/main/performance/r8-analyzer)
  - [Perfetto Skills](https://github.com/google/perfetto/tree/main/ai/skills)
  - [profilers/android-profiler](https://github.com/android/skills/tree/main/profilers/android-profiler)
- commit.

### 1.2. WIP

**longer term:**
- DELETE: `.claude\testing\2026-09-07_pristine-lan-reference.md` once device assignment is complete and tested.
- commit.
- ADD: Automate updating `THIRD-PARTY-NOTICES.md`, and add as part of `scripts\build.ps1/sh all`. Add to GitHub actions script `.github\workflows\release.yml`.
- commit.
- CHG: **cap the in-memory app log.** `SessionController.log` grows without limit - `logEntry` only ever appends - and the log screen renders every entry. Each is small and the whole thing is wiped on exit, so it is not a problem today; a long session with a chatty watchdog is where it would start to show. A few hundred entries, dropping the oldest, is cheap insurance. Noticed 2026-09-07 while checking app size after Google tightened their performance requirements.
- commit.

---

### 1.3. Implemented - chronological change history

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
- automated security/quality analysis: Flutter analyse, SonarCube, Google OSV dependency scan, Mobile security scanning (MobSF), Dependabot dependency management, and CodeQL analysis.
- clear the clipboard after 60 seconds if conf copied there
- review Actions CI pipeline - add Flutter analyse, rename pipeline
