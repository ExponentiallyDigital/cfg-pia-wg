# README.md updates - PLAN 3 OF 4

Do this AFTER the ARCHITECTURE rewrite (items 3 and 9 move material into it and point at it) and AFTER the TESTING rewrite (item 6 links to a section that has to exist first).

## Purpose

The README is what someone reads before deciding to let this app near their router. Everything here serves that decision.

## Items

The README must be short, structured, simple and easy to read for a non technical audience. Do not alter **anything** in sections `1. Why use this?`, `2. Features`,  `3. Pre-built release`. Sections 8-15 (App permissions to License) may be altered but judiciously. Rest of the document is open to change.

Scan the code base and make sure that the README covers what the app does.

1. **Section 5, using device assignment.** Add a walkthrough. Leave `<!-- SCREENSHOT: ... -->` placeholders where a picture earns its place; Andrew takes and adds them.

2. **`get-bins.sh` - a decision, not a removal.** It appears twice and the two are different:
   - Line 141, the **Merlin** path. Still the only way to install the binaries there, because the in-app installer is stock-only. This stays, and should say why the two firmwares differ.
   - Line 201, the **stock** path. The app installs these now, so this goes.
   - The script also survives as the fallback the installer itself points at when there is no build for the architecture, so do not delete the file.

AN: AGREED, retain `get-bins.sh`.

3. **Preparing the USB stick** is overly detailed. Make it brief. The finding about which format to use moves to ARCHITECTURE.

4. **The autofill tip is out of date** - the prefilled username is gone.

5. **Section 5.2** should note that the screens differ by firmware: kill switch and inbound firewall are Merlin only.

6. **Section 5.3, SMTP app passwords.** A very brief note linking to the fuller description in TESTING. Only cover Gmail and Outlook.

7. **Bug reports belong in section 11, not 13.** Section 11 is "Bugs and feature requests" and is where a reporter looks; section 13 is a joke about batteries. Two sentences under 11: CREATE GITHUB ISSUE on the About screen opens a prefilled report carrying the build details. Do not spoil the joke.

8. **Renumber nothing by hand.** If sections move, the TOC and every internal anchor move with them.

9. **How to check the script yourself - give this room.** Originally scoped as "a pointer", but this is the most valuable item in the list. The app asks a user to let it write a script that holds their PIA password and runs as root on their router indefinitely. "You can read it" is the whole answer, and it should say:
   - where the script is on the router
   - that it is never obfuscated or minified
   - that the repo copy and the deployed copy are the same thing, and a test enforces that
   - Put it in section 9 (Security) and link to it from section 7.

AN: AGREED.

## Add: four things that changed under this plan

None of these are in the README yet, and all four are things a cautious reader is asking about.

10. **Section 5.6** has no Settings entry and no View router log entry.
11. **Section 5.7** does not mention the deployed watchdog script version or the reconfigure history now shown on the About screen.
12. **Section 7, "What does the app do to my router?"** predates the boot-script replacement. That IS the question a cautious reader is asking, and the honest answer is now longer.
13. **Nothing anywhere says the uninstall exists.** A user deciding whether to install should be told they can take it all off again, and what that leaves behind.
