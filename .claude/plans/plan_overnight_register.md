# Overnight documentation run - register

Started 2026-09-11, build 430. Two sections: decisions I could not make on my own, and tests I had to touch.

Andrew reviews both when back at the keyboard.

## Decisions needed

**RESOLVED - the two README section numbers quoted inside ARCHITECTURE** now name their sections, as
does the one in a `lib/` comment. Both targets survived the README rewrite unmoved.

**The UNINSTALL button on the Settings screen describes itself wrongly.** Its on-screen note reads
"Tunnels, watchdog settings and cron entries are left alone", but `uninstallFromRouter()` removes
every `cru` entry it created and every one of the app's NVRAM keys, including the watchdog
settings - which is what you asked for in the build 425 feedback. Only the TUNNELS are left alone.
The note predates that change. I have NOT touched it: my permission this run covers comments only,
and this is a user-visible string in `lib/screens/settings_screen.dart`. The README and TESTING now
describe what the code actually does, so the app is the only thing saying the wrong thing.

**A section-1 working agreement now pulls against plan 4 item 5.** The agreement says every NVRAM
variable the app writes must be described in ARCHITECTURE **and** "Describe it in §4.9 here as
well". Item 5 asks §4.9 to stop duplicating ARCHITECTURE. I have split the difference rather than
touch section 1, which you told me not to: §4.9 still NAMES every key, so a key that exists only in
code is still visible there, but what a key MEANS now lives in one place. If you want the agreement
to match, the wording to change is "Describe it in §4.9 here as well" -> "List it in §4.9 here as
well, with whatever the app does with it".

**I left §4.8, §4.8.1 and §4.10a alone**, though plan 4 item 5 names them alongside §4.9. §4.9 was
genuinely two documents describing the same firmware. Those three are not: they are the reasons the
CODE looks the way it does - the dropbear 9000-byte exec limit, BusyBox `tr` having no character
classes, the TLS floor that is a minimum and not a pin, Android forcing edge-to-edge at SDK 36.
ARCHITECTURE does not carry any of that, so pointing at it would point at nothing. Say the word and
I will trim them, but every line I checked passed your own test - "would I get this wrong without
being told".

## Tests I had to change

**Added `test/unit/markdown_links_test.dart`** - the link check from plan 2, pre-approved. It passes
on the tree as it stands. Two details of GitHub anchor generation had to be reproduced exactly or it
reported false failures: each space becomes its own hyphen (so `Security & QA` yields a double
hyphen), and a heading indented by up to three spaces is still a heading - BACKLOG.md has eight of
those inside a list.

No existing test has needed a change so far.

## Deviations from the plans

**ARCHITECTURE pass 1 did not move the prior-design material.** The plan lists that under pass 1, but writing the one-line retractions that stay behind is a CONTENT change, and pass 1 was meant to be pure movement so its diff could be read for what was dropped. The appendix gets its own commit later in the run.


**The `IP Method` column warning stayed where it is.** It was on the candidate list for the prior-designs
appendix. It is not a design we took forward and then dropped - it is a warning against one, and the
observation IS the argument. Moving the evidence to the back would leave a bare prohibition that the next
reader has every reason to overturn. Two entries went to the appendix instead: the two-cost model and the
placeholder records.

**Retiring the two-cost model cost more than the appendix commit.** Four sections elsewhere still argued
from it - the reserved/unreserved table, the "cost is per device, once, ever" finding, the reservation-
removal warning, and a NOTE about freshly reset routers. They are corrected in the "stale claims" commit.
The distinction the screen needs is unchanged; only the REASON for it is, and the reason is now that an
unpinned address moves and takes the assignment with it.

**Pass 3 is two commits, not one.** The mechanical half (fourteen dead internal section numbers, two
out-of-date claims) would have been unreadable mixed into the prose half.
