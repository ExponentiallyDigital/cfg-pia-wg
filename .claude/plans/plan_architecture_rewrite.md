# ARCHITECTURE.md rewrite - PLAN 1 OF 4

Do this one FIRST. The TESTING and README plans both pull material out of this document and link into it, and the CONTEXT plan replaces its own detail with pointers to it. Doing any of them first means writing links into a structure that is about to move.

## Purpose

A reference for why and how the app does what it does.

**The test of success:** when ASUS change VPN Fusion in a future firmware, it must be easy to work out the impact on this app. Everything else in this plan serves that.

## The problem

It reads like design notes because it was written as design notes, incrementally, while we were still finding things out. 1,199 lines, of which section 3 alone is 566 - because every device-assignment discovery landed there.

Concretely: a mix of features, observations and discussion; islands of information rather than a narrative; concepts introduced without introduction ("takes the cheap path"); and no path from a high-level view down to detail.

## Do it in three passes, one commit each

A single rewrite of a 1,199-line document is not reviewable, and this document holds measurements that cost days to obtain. Losing one silently is the real risk.

### Pass 1 - restructure only, no content changes

Move and re-level. Do not reword. The diff should be pure movement, so it can be read for what was dropped.

1. High level first, then deeper. Someone arriving should meet the shape of the system before any NVRAM key.
2. Split section 3. At 566 lines it is not a section, it is half the document.
3. Prior designs we did not take forward move to an appendix, **with one caveat** - see "Conflict to resolve" below.

### Pass 2 - the diagrams

4. **How the fields and settings interact.** The hardest and the most valuable: three different numbers name one profile (slot, `vpnc_unit` row, index 6) and prose has never made that clear. May need more than one diagram.
5. **The watchdog script on the router:** when it runs, and what it does. Likely two diagrams rather than one - "when it runs" (cron, deploy, backoff) and "what a reconfigure does" - because one will be unreadable.
6. **The email flow** folds into 5 rather than standing alone. It is a branch of the same script.

Mermaid renders on GitHub and in VS Code. Diagrams drift from code silently, worse than prose does, so where a diagram names NVRAM keys those names must appear in the code - the same rule section 3 already carries.

### Pass 3 - narrative and prose

7. Introduce concepts before using them. Give the document a flow rather than a set of islands.
8. Remove "the app used to do X" where it is only history. Keep it where it is the reason a rule exists.

## Add: the firmware dependency register

Not in the original draft, and the thing the stated purpose actually asks for.

One section listing every assumption this app makes about the firmware, each with how it was measured and what breaks if ASUS change it. Today these are scattered across four sections:

- `vpnc_clientlist` schema, and the three numbers that name one profile
- `vpnc_dev_policy_list` format, and enabled-index-0 versus disabled-index-0
- the default-connection sequence (eleven probes to find)
- `ip rule` priorities 100 and 10000, and that stock never removes a stale one
- `rc_service` semantics, and that a hung service wedges the whole queue
- `/usr/sbin/curl` refusing to run with `crond` in its ancestry
- `stop_wgc` / `start_wgc` versus `restart_vpnc` per firmware
- `S50downloadmaster` and `S50asuslighttpd` as the boot hook

That list IS the impact assessment. Everything else in the document is explanation of it.

## Conflict to resolve before starting

Item 3 (move prior designs to an appendix) conflicts with a working agreement in CONTEXT.md:

> Retract in place rather than quietly editing: leave enough that a reader knows the earlier claim existed and why it was wrong, so it is not rediscovered and re-adopted.

Moving every retraction to the back invites exactly the rediscovery it was written to prevent. Suggested resolution: a one-line retraction stays where the wrong idea would naturally occur to a reader, and the long story moves to the appendix. Confirm before pass 1.

AN: AGREED.

## Also missing from the draft

The last three days. All three are in the document now, all three are the newest and most scattered material, and two of them are firmware dependencies:

- the wedged `rc_service` (5.2.0)
- the curl caller check (5.5)
- the stale `ip rule` after a reassignment (3.3.6b)

AN: AGREED.