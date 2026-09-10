# CONTEXT.md update - PLAN 4 OF 4

Do this LAST. Item 5 replaces detail with pointers into ARCHITECTURE, and those sections are about to be renumbered - writing the pointers first means rewriting them.

## Purpose

This file is read at the start of every session, so it is the only document guaranteed to be seen. That makes it the most valuable page in the repo and the one that suffers most from being long.

**The test for what stays:** not "is it true" but "would I get this wrong without being told". A working agreement, a convention, a trap. Anything merely *describable from the code* can be a pointer, because the code is readable.

## Items

1. **Rebuild the device assignment material by scanning the code.** It is mentioned four times in 478 lines, and the feature is absent from the call graph entirely. Someone reading this file would not know the screen exists.

2. **DONE (build 429).** Section 3 claimed 28 files; `lib/` holds 44. All sixteen missing entries added, and a test-style check confirmed the list and the directory now agree exactly.

3. **4.1 and 4.2 are out of date.** 4.1 predates the `routerLog` and `settings` destinations; 4.2 predates the staged-assignment state and `canReuseRouterSession`.

4. **Remove "the app used to do X" - but not all of it.** There are fourteen historical passages. Most describe what changed and should go. A few carry the *reason a rule exists*, and that reason is the only thing stopping the rule being undone:
   - spinners cleared before awaiting a modal
   - never `AlertDialog` for a form
   - the SSH connection lifetime
   - Strip the history from those and what is left is an arbitrary-looking prohibition that the next person reverses.
   - **Rule:** remove history that says what changed; keep history that says why a rule exists, in one sentence.

5. **Replace duplicated detail with pointers.** 4.9 (NVRAM variables) is 46 lines duplicating ARCHITECTURE section 3, which is now the authority for every key. The same treatment suits 4.8, 4.8.1 and 4.10a.

## Add: kill the line-number references

Not in the original draft. Seven references point at specific lines:

```
slot_modal.dart:99-104        slot_modal.dart:520-551
app_drawer.dart:51-57         watchdog_dialog.dart:219-262
router_watchdog.dart:373-392
router_slot_service.dart:28-46    router_slot_service.dart:177-193
```

Every one of them is wrong now, because all of those files moved this week. Line numbers in prose rot silently and there is no way to notice. Name the SYMBOL instead - a symbol either exists or a grep for it fails loudly.

## Do not touch

Section 1, the working agreements. None of the five original items reach them, which is right. They are the highest-value content in the repo. Whatever else is cut, they stay in full and stay at the top.

AN: AGREED.