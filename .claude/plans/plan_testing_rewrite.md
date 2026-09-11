# TESTING.md rewrite - PLAN 2 OF 4

Do this AFTER the ARCHITECTURE rewrite. Item 7 pulls material out of ARCHITECTURE and links into it, so its sections have to be settled first.

Do it BEFORE the README rewrite. That plan wants a brief SMTP note here linking to a fuller description, which has to exist first.

## Purpose

Structured by what a USER does, not by what we happened to investigate first. Someone testing a feature should find its tests in one place.

## Do it in two commits, not one

Items 1 and 2 move almost the whole file and re-level every heading. Items 4 to 8 then edit sections that have just moved. Done in one pass, the later edits are aimed at a document that no longer matches the plan, and the diff is unreadable.

### Commit 1 - structure only

1. Move the block from "## 4. Full end-to-end manual test" to the end of the file up to the top, under the TOC. Convert to H1-Hx using the existing indentation as the heading level. Remove the indents.
2. Break into sections with `---`, one per app function, in the order a user meets them: home screen, then Standalone, Manage, Watchdog, VPN device assignment, View app log, then the hamburger items not already covered (View router log, Settings, About). Relocate existing text into the right section.

Change nothing but position and heading level, so the diff can be read for what was lost.

### Commit 2 - content

3. **New section: device assignment.** Not covered at all today.
   - It changes routing, and the default-connection test drops every tunnel for about a minute. That section needs the same warning treatment section 2 already has, or someone runs it on a router they care about.
4. Review everything that currently precedes "## 4. Full end-to-end manual test" and place it in the new hierarchy. Note what is missing - for example section 1 is Merlin-shaped and needs the `mailsend-go` equivalent for stock.
   - Worth reframing rather than duplicating: the app has a TEST EMAIL button that does this. The section is better as "when the button fails, here is how to test the same thing by hand" than as the primary route.
5. DONE - 2.1 Checks bullet 5 removed.
6. DONE - 2.1.7 removed up to but not including "14. Apply a new config to a blank slot".
7. Move "3. Examining nvram settings" to a new L2 heading after the above, and expand it with material from ARCHITECTURE **only as it relates to testing**. More than a short paragraph means a link to the ARCHITECTURE section instead.
8. Update "files deployed to router", currently step 18. It is out of date: the boot stub, the header line on both scripts, and what the uninstall removes are all new.

## Add: the diagnostics from this week

Not in the original draft, and the most useful thing a tester could be told.

A tester following this document today would not know to look for any of these, and each one is a symptom that looks like something else:

- `rc_service: skip the event:` in the syslog means the router is discarding every service call and only a power cycle recovers it. This is now the single most useful diagnostic in the project.
- `exit 0` with no HTTP status, no body and no stderr from the token fetch means curl refused the caller.
- An assignment that is written correctly and has no effect means a stale `ip rule` - check `ip rule show` before anything else.

## Add: a link check, rather than a working agreement

Item 7's original wording asked for a CONTEXT.md agreement that links between TESTING and ARCHITECTURE must be kept resolving. The cause is anchors generated from heading text, which change whenever a section is reworded - so the rule will be forgotten exactly when it matters, during a rewrite.

A test that every intra-repo Markdown link resolves is better. There is precedent: `no_lan_identifiers_test.dart` guards a rule the same way, and a rule nobody can forget beats one written down.
