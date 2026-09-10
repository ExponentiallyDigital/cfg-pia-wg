TESTING.md - fundamental rewrite

1. With the existing block from "## 4. Full end-end-to-end manual test" to the end of the current file, move that to the top of the file underneath the TOC, and convert that to H1-Hx headings using the indentation as a guide for the heading number, remove any indents.
2. Section break with "---" each app function from a user perspective eg sequence as home screen functions/buttons, then per function: Standalone, Manage, Watchdog, VPN device assignment, view app log, then the items in the hamburger menu that have not already been covered. Relocate existing text to the appropriate section(s).
3. Add a new section to test device assignment under the new structure.
4. Review all text that currently precedes "## 4. Full end-end-to-end manual test", and decide where in the new hierarchy it should be moved to and what is missing eg. the existing content under "## 1. Testing email send from SSH" requires a matching block on how to do that with stock when using mailsend-go.
5. I have removed 2.1 Checks, bullet 5.
6. I have removed 2.1.7 up to, but not including, the bullet "14. Apply a new config to a blank slot".
7. Move "3. Examining nvram settings" to a new L2 heading after all of the above, and expand that section with relevant material from ARCHITECTURE.md but only as it relates to testing - if there is more than a very short paragraph required, give a link to the appropriate section of ARCHITECTURE.md that should be referenced. Add to CONTEXT.md that when updating either TESTING or ARCHITECTURE, that links must be updated so that they resolve correctly.
8. Update "files deployed to router, currently step 18.
