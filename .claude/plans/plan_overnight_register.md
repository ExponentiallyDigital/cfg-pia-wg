# Overnight documentation run - register

Started 2026-09-11, build 430. Two sections: decisions I could not make on my own, and tests I had to touch.

Andrew reviews both when back at the keyboard.

## Decisions needed

**Two README section numbers are still quoted inside ARCHITECTURE** - `README.md section 5.3.1` for the
email examples and `README.md section 4.1` for the Download Master warning. Both are left as they are
until the README rewrite settles its own numbering, then pointed at titles like everything else. Flagged
rather than decided because the README plan forbids touching sections 1-3 and I do not yet know whether
the numbering below that moves.

## Tests I had to change

Nothing yet.

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
