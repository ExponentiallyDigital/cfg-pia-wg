Read all 24 Dart source files in the ./lib folder and its sub folders. Do not read any files in the ./test directory. Do not read any markdown files except .claude/context.md, but treat it as historical intent, not fact - it may be outdated or describes things that were never implemented or were later changed.

Task: produce a single, complete, up-to-date context.md that will be read at the start of every future session before code changes are made. It must describe what the code actually does today.

Before merging, briefly summarise:
1. What each Dart source code file covers (1-2 sentences each)
2. What you found in the actual codebase for each major area (UI, slot 
   management, watchdog, about screen, NVRAM variables, etc.)

Structure the output as:
1. Working agreements (tests required for every change, update this file 
   in the same change as any architecture/behaviour change, flag 
   conflicts rather than silently resolving them)
2. Snapshot (what the app does, one paragraph)
3. Architecture (actual file/module map, from the repo)
4. Feature reference sections — reference-style, tables/bullets not prose
5. Doc-vs-code discrepancies — anywhere the existing context.md file describes 
   behaviour that the code doesn't actually have (or has differently), 
   state what the doc says, what the code does, and which file/line 
   the code lives in. Do not assume the existing context.md is correct.

Constraints:
- No invented code standards: derive it from what the codebase  actually does (existing lint config, actual state-management pattern  in use, actual error-handling pattern), not generic Flutter advice.
- Keep it dense and reference-style — this file loads into every session, so token efficiency matters.
