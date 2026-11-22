# Plan: DNS across stock and Merlin (ID-641)

The one place to see the DNS work items together, and the findings, reasoning and recommendations from 2026-11-20, for Andrew to review and decide on. Status lives in each item's `Now:` line in BACKLOG.md or CHANGELOG.md, never here. Brought up to date on 2026-11-22: the corrected documents went out in build 587 (v0.8.217, both stores) and the SmallNetBuilder, XDA and LinkedIn posts are made; the decisions below are still Andrew's and nothing from "Recommendations" is built.

## In one minute

- On 2026-11-20 Merlin's DNS was measured on a router for the first time, and several statements that the project made for "ASUS routers" turned out to be true of stock only.
- The biggest: on Merlin, when the default connection is a tunnel, devices that aren't pinned send their lookups to the default slot's DNS servers through that tunnel. They don't use the router's own DNS settings. On stock they do.
- The app's mechanisms are already split by firmware. Its explanations, the README, ROUTER-DNS.md and the public posts were written as one stock-shaped story.
- Recommendation: split the model and the how-to guidance by firmware, and leave the UI and the concepts as one. Details in "Recommendations".
- Decisions for Andrew are listed at the end. Nothing needs doing before he has read this.

## How to resume (written 2026-11-20, for Andrew and for a session with none of this context)

Approach: decisions only, in a fixed order, about 30 minutes. Don't design anything in the same sitting.

1. **Read only the top (5 minutes).** This section, "In one minute", and "Decisions for Andrew" at the end. Skip the findings tables, the measurement recipes and "Not yet audited" unless challenging a result: they are the evidence, not the decisions.
2. **Deal with what has a date first (5 minutes).**
   - Build 587 is released (2026-11-20) and the documents on `main` are corrected. The SmallNetBuilder post promised the app's messages "in the next few days", so the clock is running on the DNS commit below.
   - ID-637, the Reddit clarification, and ID-638, the blog note, are still open. Claude drafts them in Andrew's voice, and Andrew posts and gives Claude the exact text and figures for `promotion/posts.md`.
   - Build 588 is built but uncommitted (the Merlin DEVICES fix, ID-644 to ID-651). Claude commits only when Andrew says, with the steps in `CHANGE-PROCESS.md` section 8.
3. **Make the five decisions in ID-641 one at a time (20 minutes).** Yes, no or "later" for each. Claude turns each into an item or declines it. "Later" is fine: nothing else depends on any of them except the first.
4. **Stop there.** ID-639 waits for the router to be on stock, and ID-621 waits for the others.

A message to start the session, since Claude's memory of 2026-11-20 won't be there:

> Read .claude/plans/plan_dns.md and walk me through the five decisions in ID-641 one at a time. First, anything time-sensitive: the Reddit clarification and whether to commit.

That works because this plan holds the evidence, the order and the decisions, and each BACKLOG item has its own `Plan:` link. Before doing router work again, Claude asks Andrew for permission afresh: his 2026-11-20 permission was for that session only. Claude also reads `.claude/CONTEXT.md` section 1 and `CLAUDE.md` first, as they require.

## The map

Every DNS work item, with what it decides or waits for. Relationships only: where an item stands is in BACKLOG.md or CHANGELOG.md, and `test/unit/dns_map_test.dart` fails when an ID in the first column no longer exists in either. Update this table when an item is added, split or closed.

| Item | What it is | Decides, or waits for | Detail |
| --- | --- | --- | --- |
| ID-641 | Decide how documentation and code are split by firmware | Decides the layout for ID-640, ID-594, ID-636 and ID-621 | This plan |
| ID-640 | The app's text about devices that aren't pinned is stock's and wrong on Merlin | Waits for ID-641 (does it build the per-firmware model, or stay a text fix) | This plan |
| ID-639 | Re-measure the stock statements, including with different addresses for the router's settings and the slots | Needs the router on stock; feeds ID-621 and the stock side of ROUTER-DNS.md | This plan |
| ID-636 | On Merlin, a stopped slot's shared DNS address leaks the router's lookups over the WAN | Decided together with ID-594's fallback | `plan_router-dns-slot.md` |
| ID-594 | Choose what carries the router's own DNS | Decided together with ID-636; designed for each firmware after ID-641 | `plan_router-dns-slot.md` |
| ID-621 | DNS modes in SETTINGS | Waits for ID-641, ID-639 and the ID-594 and ID-636 decision | `plan_dns-modes.md` |
| ID-613 | Hand tests for build 581's fixes, including ID-610's ROUTER DNS ROUTING sentence | Read ID-610's sentence on both firmwares in the same pass as ID-640 | `.claude/testing/` run sheets |
| ID-637 | Reddit clarification that the earlier comments were stock only | Independent: public text | None |
| ID-638 | Blog post says its DNS section is stock's and Merlin differs | Independent: public text | None |
| ID-632 | Corrections to ROUTER-DNS.md, README and ARCHITECTURE, with the evidence (closed, build 587) | Done; the record every item above builds on | CHANGELOG, ARCHITECTURE.md 6.10 |

The order, if Andrew accepts the recommendations below: decide ID-641; then ID-640 (with the model if chosen) and ID-639 whenever the router is on stock; then ID-636 and ID-594 together; then ID-621.

## What was found (all Merlin 388.13, one router, 2026-11-20)

Each is recorded with its evidence in ARCHITECTURE.md 6.10 ("DNS") and in ROUTER-DNS.md. This table is the summary.

| Finding | How it was shown | Stock is |
| --- | --- | --- |
| With a tunnel as the default connection, devices that aren't pinned have their lookups rewritten to the default slot's DNS servers and sent through that tunnel | The nat chain rewrite for the whole LAN, its counter rising, the connection table showing the answer from the slot's server, and with the default moved to a slot whose DNS differs from the router's, answers from that slot's server | Lookups go to the router, which uses its own DNS settings, whatever the default is |
| With the internet as the default, unpinned devices' plain DNS is forced to the router | Fresh flows, with the old ones deleted, answered by the router, with DNS Director on and off | Same |
| DNS Director on or off makes no difference to unpinned devices while the default is a tunnel | The same rewrite and answers with it off | Not measured |
| The router's own programs ask the local dnsmasq (`/etc/resolv.conf` is `127.0.0.1`), which uses stubby and the DoT list with DoT on, and the DNS Server setting as ordinary DNS with DoT off | Files and connection table, DoT off needing a WAN restart; Merlin's source agrees | The programs use the DNS Server setting directly |
| A DNS address shared by slots is held by the first slot to start, not the highest-numbered | Run in both directions twice, with throwaway slots; Merlin's source (`ip route add` fails when the route exists) | The highest-numbered slot |
| When the holding slot stops, the route is dropped and nothing takes it over, so the router's lookups for that address leave over the WAN from the home address until a sharing slot starts | Route read, and a real lookup seen leaving from the WAN address and answered | The lookups move to the next-highest slot |
| A held route can point into a tunnel with no handshake | A real lookup sent into one, no answer | Same idea, already known |
| "Helper programs" are installed on stock only | Existing record (Merlin ships `jq`) | Installed |

## What was wrong, and where

Corrected on 2026-11-20 (the files are uncommitted):

- ROUTER-DNS.md, sections 1 to 6 and the section 7 introduction: the callout, the short version, the hotel analogy and its diagram, who looks things up, the shared-address rules, the stopped-slot case, Setup A and B, and a note that the app's overlap note shows on Merlin since build 581.
- README 5.2.2 (the callout and its bullets), the "second reason" paragraph, and 5.5's line on the resolver check.
- ARCHITECTURE.md section 2 row 8, the 2026-09-19 history row, and 6.10's DNS paragraph, which now holds the measurements.

Not corrected, each with its own item:

- The app's text: `resolverAdvice` and its group label in `router_dns.dart`, the watchdog's "Router resolver FAILED" log lines in `router_watchdog.dart`, and the overlap note in `common_fields.dart`. They say that devices that aren't pinned depend on the router's resolver (ID-640).
- Andrew's Reddit comments (ID-637) and the blog post in `promotion/blog` (ID-638).
- The stock statements themselves, which date from September 2026 and weren't re-measured, as the router is on Merlin (ID-639).

## Why it was missed

From the project records, not from memory.

- The original DNS design measurements were stock's. Merlin support came later, from build 575, and its measurements covered mechanics: VPN Director rules, the kill switch, the guard, and the DNS rewrite for devices that are pinned.
- The case "a device that isn't pinned, with a tunnel as the default, on Merlin" was never asked. ARCHITECTURE 6.10 said a device with no rule has plain DNS forced to the router, which is true and easy to read as covering unpinned devices in general.
- It wasn't hidden. ID-632 existed because ROUTER-DNS.md's opening still read as stock only.
- The app's text and README's resolver line were written for stock, and nothing ties a statement to the firmware it was measured on. The Merlin tests cover behaviour, not wording.
- It surfaced because the claim was about to be stated for all routers in public.

## What this means for how the app works

1. On Merlin with a tunnel as the default, unpinned devices' DNS goes through the default slot's tunnel. That's better for privacy than stock, which sends unpinned lookups through the router's own settings. It also makes the default slot's DNS server a single point of failure for every unpinned device, whether or not it shares an address with the router. The default slot's watchdog already asks that server through the tunnel, so it matters more on Merlin than on stock.
2. Protections differ by firmware. ID-636 is Merlin only. The guard could hold the router's route for a stopped slot's shared address, with a check in `scripts/check-claims.sh` seen to fail with the hold removed. ID-594's design was measured on Merlin, where stock's `iif lo` rules don't exist, so it needs a design for each firmware.
3. ID-621's DNS modes (per slot, one path for all, one path with exceptions) overlap with what Merlin already does for a tunnel default. It needs firmware-aware design before anything is built.
4. The explanation layer is wrong in places on Merlin, as above. The hand tests and `check-claims.sh` check mechanics for pinned devices, but nothing checks what happens to unpinned devices or whether wording fits the firmware.

## Recommendations

### Code

- Keep one UI and one flow. Mechanisms are already split through `RouterOps` and the guard.
- Split the explanation layer through a small per-firmware DNS model that answers three questions: who answers unpinned devices (given the default connection), which slot carries the router's own lookups, and what happens when it stops.
- Messages, the overlap note, ROUTER RESOLVER STATUS, ROUTER DNS ROUTING and the watchdog text take their wording from that model, instead of the literals now scattered across `router_dns.dart`, `router_watchdog.dart` and `common_fields.dart`.
- Tests feed the model the measured router outputs as fixtures, one set for each firmware, so a wrong sentence for a firmware fails.
- ID-640 is the first user of this. It could be the item that builds the model, or it could stay a text fix and the model come after. That's a decision for Andrew.

### Documentation

- ROUTER-DNS.md sections 1 to 4 stay one concepts document, with the same layout for each topic: the common statement, then "On stock", then "On Merlin".
- Split section 5 (what to set) and section 6 into a stock how-to and a Merlin how-to, because the advice differs and today's Merlin overrides read badly. Section 7 gets a stock subsection and a Merlin subsection.
- Keep the README short, with a firmware tab that points at the right how-to.
- Keep ARCHITECTURE as it is: it is already split by firmware (6.8 stock, 6.10 Merlin).
- One file per firmware would be easier to read, but it would copy the shared concepts, and copies drifting apart is what produced today's errors. This plan avoids it by splitting only what differs.

### A measurement rule

- Measure DNS behaviour with different addresses for the router's DNS Server setting, the DoT list and each slot. Today's router had them equal (the DNS Server setting, the DoT list and wgc5's DNS were the same two addresses), which made some results ambiguous and needed other tests to settle.

### A rule for CONTEXT.md section 1 (proposed, not written)

- "Any statement about router behaviour, in a document or in the app's text, names the firmware it was measured on and the date. A statement without one is read as stock's." Per CONTEXT.md 1.1 nothing goes into section 1 until Andrew says go.

## What I am still unsure about

- Everything was measured on one router, on 388.13, with DNS Director in one mode and the default on one slot or another. Other Merlin versions and models are unmeasured.
- The router's DNS Server setting and its DoT list were equal on that router, so which of the two feeds which came from Merlin's source and the generated files, not from a test where they differ. Separating them needs one run with different addresses, which changes a setting of Andrew's and needs a WAN restart.
- The stock statements are unchecked until the router is on stock (ID-639).
- The app's own screens, ROUTER DNS ROUTING and ROUTER RESOLVER STATUS, haven't been read on Merlin for other wrong lines (part of ID-640's definition of done).

## The existing DNS items, and what today's findings change for each

None of these has been edited. The list says what each would need, for Andrew to decide. Items and plans were read on 2026-11-20.

| Item | What today changes | Suggested edit |
| --- | --- | --- |
| ID-594 (what carries the router's own DNS), and `plan_router-dns-slot.md` | Its plan says that with the chosen slot down, lookups "fall back to what the firmware does today: through another slot or out the internet connection". On Merlin, measured today, the route is dropped and they leave over the WAN from the home address, never through another slot. The plan's open question 2 ("fall through, or block") is the same question as ID-636. The plan's 1010 rule was measured on Merlin only, and stock's `iif lo` rules mean the design differs on stock. | Link ID-636 from the item and the plan, record today's fallback, and decide the fallback together with ID-636. |
| ID-636 (the Merlin WAN leak when a slot stops) | New today. Overlaps ID-594's fallback. | Decide together with ID-594. |
| ID-621 (DNS modes), and `plan_dns-modes.md` | Its "not yet measured" list includes what the router's own lookups do while their slot is down: answered on Merlin today (WAN). Its "per slot as today" baseline is not one behaviour: on Merlin, unpinned devices already take the default slot's DNS when the default is a tunnel, which is close to its "one path for all" mode. Its stock side is still unmeasured (ID-639). | Update the plan's measured and unmeasured lists, restate "as today" per firmware, and hold the design until ID-641 is decided. |
| ID-613 (hand tests for build 581's fixes, including ID-610's ROUTER DNS ROUTING sentence) | ID-610's sentence is about slot DNS servers the router's own DNS doesn't use. Its wording should be read against today's findings before the stock run. | Read ID-610's sentence on both firmwares in the same pass as ID-640. |
| ID-639 (re-measure stock) | New today. Now also covers: the DNS Server setting and the DoT list set to different addresses, which was not possible to separate on the Merlin router. | Already worded; add the different-address run. |
| ID-640 (the app's wrong text) | New today. It is the first user of the per-firmware DNS model if Andrew chooses to build one. | Decide whether it builds the model or stays a text fix. |
| ID-637 and ID-638 | New today. The Reddit clarification and the blog post. | None. |
| ID-632 | Closed in build 587. It holds the corrections made and the evidence summary. | None. |

Not DNS items, and not affected: ID-578, ID-588 (reruns needing stock), ID-596, ID-597 (VPN Director rules), ID-600, ID-604 (NETWORK status and speed).

## Not yet audited

Anywhere else that may carry a stock-only statement about DNS or unpinned devices. Checked on 2026-11-20 and found clean or corrected: ROUTER-DNS.md, README 5.2.2 and 5.5, ARCHITECTURE 2 and 6.10, the three places in the app's code listed above. Not checked:

The checklist, one line for each place, added at Andrew's request on 2026-11-20 after his SmallNetBuilder post said "the documentation is now correct". Each is read for any statement that unpinned devices use the router's own DNS, that the default connection doesn't decide DNS, that the highest-numbered slot carries a shared address, or that a stopped slot's lookups move to another slot, and is marked or corrected for both firmwares:

- The Google Play listing text and the App Store listing text under `play-store/` and `app-store/`, including the review notes and the screenshots' captions.
- The in-app help and dialog text, the DEVICES, NETWORK, ROUTER DNS ROUTING and ROUTER RESOLVER STATUS screens, the WATCHDOG form, and the DISABLE and DELETE confirmations (read on Merlin with the default on a tunnel and on the internet).
- README: section 4 (the router's DNS settings and the screenshot captions), 5.4 and its sub-sections (the guard and the default connection), the opening and feature lists, and the widget text.
- TESTING.md's DNS and ROUTER RESOLVER hand tests and their pass criteria.
- `scripts/check-claims.sh` comments and the DNS checks (MRL-dns and the like), for what they assume about unpinned devices.
- The blog post under `promotion/blog` (ID-638) and `promotion/posts.md`'s logged comments, which carry the stock-only wording as published.
- Other plan files under `.claude/plans/` that describe DNS behaviour (`plan_network-menu.md`, `plan_vpn_device_assignments.md`, `plan_install-helper-binaries.md` and any other that mentions unpinned devices), read for statements a later session might rely on.
- CONTEXT.md and ARCHITECTURE.md sections outside 6.10 and row 8 that mention the router's DNS or the default connection (6.8 and 12 first).
- ROUTER-DNS.md sections 7.2 to 7.6 themselves, which describe stock's `VPN_FUSION` and the `iif lo` rules and are marked stock only, but whose commands and numbers were not repeated on Merlin.
- The store listings above and the app text are also the places a customer reads first, so they come before the rest.

The earlier, shorter form of the same list follows.

- The store listings under `app-store/` and `play-store/`, and the in-app help and dialog text.
- README sections other than 5.2.2 and 5.5 (4.x and 5.4 mention DNS and the default connection).
- TESTING.md's DNS hand tests, and `scripts/check-claims.sh`'s DNS checks, for what they assume about unpinned devices.
- Other plan files that mention DNS.
- The ROUTER DNS ROUTING and ROUTER RESOLVER STATUS screens, read on Merlin with each kind of default (part of ID-640's definition of done).

## How the measurements were made

So that a later session, with none of today's context, can repeat or extend them. Addresses and the router's name are not recorded here.

- **Access:** SSH to the router with WSL's default key, as `.claude/testing/claude-on-hardware.md` describes, run from Git Bash through `wsl.exe`, with the script on standard input and `/bin/sh` as the remote command. Andrew gave permission each time; his permission on 2026-11-20 covered changing the router so long as it was put back, and is not standing.
- **The router has no** `seq`, `cksum`, `od`, `tcpdump` or `tee`. It does have `conntrack`, `nslookup`, `wg`, `nc` and `iptables`. Use `cmp` and `diff` for comparisons, and `conntrack -L` and `conntrack -D` for the connection table.
- **Pattern for every test:** save a baseline first (`ip rule show`, `iptables -t nat -S`, the VPN Director rule file, the settings to be changed), make the change, wait for it to settle, observe, then restore and compare to the baseline in the same script. Nothing was committed to flash (`nvram commit` was never run), so a reboot would also have undone a test.
- **Settings changed and restored:** `wgcN_enable` (set to 0 before stopping a slot, so its watchdog stands down and doesn't rebuild or email), the default connection (the rule in `/jffs/openvpn/vpndirector_rulelist`, written without a trailing newline and applied with `service restart_vpnrouting0`, then the guard), DNS Director (`dnsfilter_enable_x`, `service restart_dnsfilter`) and DoT (`dnspriv_enable`).
- **Service calls:** `service "stop_wgc N"`, `service "start_wgc N"` and `service "restart_wan_if 0"` each take ONE quoted argument. Unquoted, `service` prints its usage and does nothing, which cost one run.
- **DoT off needs the WAN restarted.** Setting `dnspriv_enable=0` and running `restart_dnspriv` and `restart_dnsmasq` stops stubby but leaves dnsmasq pointing at it. The router rewrites its resolver files only on a WAN event (`update_resolvconf` in Merlin's `rc/wan.c`).
- **Test slots:** throwaway keys from `wg genkey`, an endpoint in the documentation range (`203.0.113.1`) that answers nothing, a private tunnel address of their own, and DNS addresses shared with the real slot (the public Quad9 pair), so nothing real depends on the route. Unset every key afterwards and restore `wgc2_enable` to an empty value.
- **Cleanup trap:** stopping a test slot can leave its `MASQUERADE` rule in the nat table's `POSTROUTING`; delete it with `iptables -t nat -D`. Rule order in that chain follows start order and is harmless.
- **Sampling lookups from LAN devices:** delete the old DNS entries with `conntrack -D -p udp --dport 53` (and tcp), wait 20 to 25 seconds, then list the entries from LAN addresses. An entry's second address pair shows who answered: the router's own address means the router, and a DNS server's address means the lookup was rewritten. Without the delete, a long-lived flow keeps its old rewrite and misleads.
- **Source:** Merlin's code was read with `gh api` at tag `3004.388.13` (`rc/wireguard.c`, `rc/wan.c`). The tag has no `_0`; the firmware reports 388.13 with extension 0.
- **Rendering diagrams:** Node.js 26.13.1 was installed on Andrew's PC on 2026-11-20 with `winget` (he approved the administrator prompt). `@mermaid-js/mermaid-cli` 10.9.1 was installed in the session's scratch folder and run with the PC's Chrome, through a small puppeteer config that sets the browser path with forward slashes.
- **Dead ends, so they aren't repeated:** a Python edit run from Git Bash can't see Git Bash's `/tmp`; the router has no `cksum`, so a checksum compare of the rule file did nothing and `cmp` against a copy was used instead.

## The router when it was measured

Described without addresses or names, so the results can be read. It was one router on Merlin 388.13 with: two tunnels (wgc1 on Quad9's addresses, wgc5 on Cloudflare's security addresses), the default connection on wgc5 through a whole-network rule, two devices pinned (one to each tunnel), DNS-over-TLS on, DNS Director on in its router mode, and the router's DNS Server setting, its DoT list and wgc5's DNS all the same two addresses. Both slots' watchdogs on. Each result in ARCHITECTURE 6.10 says which of these it varied.

## Context outside the repository

- The GUIDES-flair kill-switch reply drafted for Andrew to post on a Sunday morning, and the text of his Reddit "About you", exist only in earlier conversation. Neither is in `promotion/posts.md`. If Andrew posts them and wants them logged, he gives the exact text.
- The Reddit comments that started this (ID-637) claimed the stock behaviour for all routers.
- Andrew's decisions during the work: ID-632's scope was widened from ROUTER-DNS.md sections 3 to 6 to also cover README and ARCHITECTURE; ID-636 was raised as its own item beside ID-594; the default-internet case was to be re-measured (done); stock behaviour is not to be re-measured until the router is on stock.
- The process file, `CHANGE-PROCESS.md` (ID-635), and the moved BACKLOG layout were done in the same build, and are described in ID-635's closing line.

## Build 586 and customers (assessed 2026-11-20)

Build 586 is the release customers have: promoted to Google Play production on 2026-11-19, with the App Store version sent to review the same day. Andrew began marketing the app only days before, so the question was whether today's findings expose anyone. This is the assessment as given then. It rests on one Merlin router's measurements, the code and the documents; build 586 itself was not tested on a customer's router, and stock was not re-measured.

**Conclusion:** nothing found today shows a flaw in build 586 that exposes customers' traffic on stock or on Merlin. It shows wrong explanations, mostly on Merlin, and one narrow privacy gap on Merlin. No reason was found to pause the rollout; the recommendation was to correct what is public.

- **Stock:** nothing from today applies. The known limits stand: no kill switch on stock for devices that aren't pinned, and the guard holds the pinned ones (README 5.4.1). The stock statements date from September 2026 and nothing today contradicted them, but they haven't been re-checked (ID-639).
- **Merlin, misleading messages with no safety effect:** with a tunnel as the default connection, the resolver check, the watchdog's "Router resolver FAILED" line and the DNS overlap note say that devices that aren't pinned lose name lookups. They don't, because those devices use the default slot's DNS servers. The documents said the same and were corrected on 2026-11-20 (uncommitted, so the repository's `main` still carries the old text). The app's text is ID-640.
- **Merlin, a narrow privacy gap (ID-636):** if a user sets the router's DNS to the same servers as one of their slots, then while that slot is stopped the router's own lookups go out over the normal internet connection from the home address. Merlin's firmware does this and the app's guard doesn't cover it. It affects only the router's own lookups, not devices' traffic, and only people who share the addresses (the documents' Setup B).
- **Merlin, devices that aren't pinned rely on Merlin's own kill switch:** that holds while the default slot is enabled. If the default slot is disabled, or the default is changed to the internet, those devices go straight out the WAN. This is by design and recorded in ARCHITECTURE 6.10. Not checked: whether the app's DISABLE warns about devices that follow the default, as it does for pinned ones.
- **Claims at risk in the marketing:** "every device protected" holds for devices on the tunnel while it works, but the guest Wi-Fi is outside any tunnel; and the DNS comments were stock only (ID-637, ID-638). The store listings and the in-app help were not audited.

Andrew's text for the SmallNetBuilder forums (his wording, final version, given on 2026-11-20; he posts it, and as soon as it is posted build 587 is released):

> A note on DNS and Asuswrt-Merlin for cfg-pia-wg v0.8.216 (build 586, released 2026-11-19):
>
> Extended scripted edge case testing has confirmed that stock ASUS firmware and Asuswrt-Merlin handle DNS lookups differently for devices you haven’t pinned to a slot: on stock they use the router’s own DNS settings, while on Merlin, when your default connection is a tunnel, they go through that tunnel’s DNS servers. The former was known and correctly described, but the latter isn't documented correctly in the app's GitHub documentation and in the app, in ROUTER RESOLVER STATUS, the watchdog's "Router resolver FAILED" log lines and the DNS note under the slot form's DNS field.
>
> Your devices’ traffic protection isn’t affected, but some of the app’s messages and our documentation described the stock behaviour for both, and I'm correcting that.
>
> One thing to know if you run Merlin: if you’ve set your router’s DNS to the same servers as one of your VPN slots, then if that slot is manually stopped, disabled or a watchdog rebuilds the slot, then the router’s own lookups can go out through your normal internet connection. If that matters to you, use different DNS servers for the router and for your slots. Devices pinned to a slot are not affected either way.
>
> The documentation is now correct (build 587 released today) and the app's messages will follow in the next few days in a subsequent release (I'm looking at enhancing some other DNS functions at the same time). I'll post here when the updated code has completed testing and is available on GitHub and in the stores.

Settled by that version: "scripted" testing, the deadline softened to "the next few days", the docs claim tied to build 587 released today, the right screens named, and the watchdog rebuild included.

Left as Andrew wrote it, with Claude's notes:

- **"The documentation is now correct" is wider than what was checked.** README (5.2.2 and 5.5), ROUTER-DNS.md and ARCHITECTURE.md were corrected. The store listings, the in-app help, TESTING.md's DNS tests, other README sections and the blog post were not audited (see "Not yet audited" and ID-638). It is true of the GitHub documentation named in the same post.
- **"Enhancing some other DNS functions at the same time"** can stretch the follow-up release. The text fix (ID-640) could go out alone first, with the rest after the decisions in this plan.
- **Timing.** The post says the documentation is corrected "today", so the release of build 587 has to follow the post the same day. The release steps are in the next point.
- **Release of 587, as soon as the post is up** (Andrew's instruction, 2026-11-20): the commit follows CHANGE-PROCESS.md section 8: the block's summary replaces `in progress`, a ```` ```play ```` note is written (the block has none; "Behind the scenes" fits, as nothing user-visible changes), the full suite is run and the new test code screened against SonarCloud's rules, then the push, the PR, a zero-issue Sonar check, merge and tag under Andrew's standing permission, with promotion only when Andrew says.
- **Ready before the commit (checked 2026-11-20):** `dev` is level with `origin/dev`, all tests pass (2374), and the new test code has no string literal used three times. Three files in the working tree were not written for this work and need Andrew's say on whether they go in: `.claude/plans/plan_rearchitect-cicd.md`, the README line he changed himself, and `promotion/posts.md`.

## Andrew's own router, 2026-11-20

Recorded because it shows what "devices that aren't pinned" meant in practice, and because the router was changed on purpose. No addresses or device names here.

- Before: two devices were pinned (the tablet to wgc1, the phone to wgc5), and seven other devices on the main network plus any on the guest Wi-Fi were not. The seven followed the default connection (wgc5) and were held only by Merlin's whole-network kill switch.
- What could have failed open for them: wgc5 switched off or disabled (not tested, because it would cut them to the WAN), and the default connection changed to the internet (measured: unpinned traffic went straight out the WAN). The guest Wi-Fi has no rule at all and goes straight out the WAN; no guest device was active. IPv6 is off, so there is no second path.
- What was done, at Andrew's request: every device on the main network was pinned to wgc5 except the tablet, which stays on wgc1. That was 11 rules added to the VPN Director rule file, applied the way the app does (restart VPN routing, then the guard), and verified on the router: each has its wgc5 rule and two holds ahead of the default (the guard's and Merlin's kill switch), the tablet is still on wgc1, and both tunnels handshake. The file is in flash, so it persists.
- Two of the pinned devices were on dynamic addresses, not reservations, and were pinned by their current address; they should be given DHCP reservations. Devices known to the router but offline, with no reservation, still follow the default.
- A copy of the original rule list (three rules) was saved in the session's scratch folder, which can be cleared; the pins can also be removed in DEVICES.

## Public communication, and the order that matters

- The corrections to ROUTER-DNS.md, README and ARCHITECTURE reached `main` in build 587, so posts that link to them now point at corrected text.
- Posted and logged in `promotion/posts.md`: the SmallNetBuilder clarification, the XDA post, the LinkedIn comment, and the catalog listing row. Still open: ID-637 (Reddit) and ID-638 (blog).
- Asking Merlin users to report what other versions and models do is still the main thing not measured. No item exists for it; ID-637's pattern would fit. The stock boot hook is never mentioned in outward text, and nothing from the router's addresses or device names goes in a post.
- The SmallNetBuilder text promised a follow-up post when the app's messages are corrected and released.

## Measured 2026-11-22: what a hold on a stopped slot's DNS address can and can't be (Merlin 388.13, one router)

Two scripted runs with throwaway slots wgc3 and wgc4 on an unroutable documentation address, standing in for the router's DNS address, plus one run on the real address with a WAN bounce. Andrew gave permission for the session. Everything was put back and compared with a baseline; the one difference, from running the app's own `merlin-guard.sh` at the end, is below. Source read at tag `3004.388.13`: `rc/wireguard.c` (`_wg_client_dns_setup`, `stop_wgc`) and `rc/wan.c` (the WAN DNS route).

- **The leak path is a route Merlin adds at WAN-up.** For each of the router's DNS addresses it adds `<addr> via <gateway> dev <wan> metric 1` in the main table (`wan.c`, "add wan dns route via wan interface"). A slot that shares the address adds `<addr> dev wgcN` at metric 0 beside it. Stopping the holder removes the metric 0 route and the WAN route stays, so lookups leave over the WAN. Seen with a real slot stop.
- **A hold at metric 1 works.** Replace the WAN route with `blackhole <addr> metric 1`: with no slot running the kernel refuses the address; a slot that starts adds its metric 0 route beside it and wins; when it stops, the address is refused again. It survived a WAN bounce, and a slot restarted by the bounce added its route beside it.
- **A hold at metric 0 breaks the slot.** Merlin's `ip route add <addr> dev wgcN` fails when a metric 0 route to the address exists; the slot came up and the router's lookups stayed refused. Never hold at 0.
- **A second sharing slot does not take over.** Today the second slot's add fails because the first holds the route, so when the holder stops the router's lookups leave by the WAN though the second slot is up. With a hold they are refused until a slot restarts. The design needs a backup route per running sharing slot. Two backups at the same metric collide (`File exists`), so each needs its own metric, for example 10 plus the slot. Measured in a third run, in both start orders: with no WAN route, a backup route per running sharing slot at metric 10 plus the slot, and the blackhole at metric 100, the router's lookups moved to the other running slot when the holder stopped, then were refused when none was left; a backup goes with its interface, and the slot's own route came back on restart. The WAN route must be gone for this, as at metric 1 it beats the backups.
- **The hold is defeated for a few seconds at WAN-up.** Merlin re-adds the WAN route with `route_add` at the same metric as the hold, the two coexist, and the WAN route wins: after the bounce the real address went out the WAN for about two seconds, until the tunnel's route returned (t=6s to t=8s on this router). The guard's boot watch checks rules only, so it would need to check routes too. The hold closes the leak while a slot is stopped or disabled, not the seconds around a WAN event or a boot. That is how the guard's other protections are described (ID-582).
- **`wgclient-stop` runs before the interface is deleted** (the interface was still present, with its route, when the hook ran). A hook can place the hold early, but can't add a backup route at metric 0 for the next slot at that moment.
- **Side finding:** a WAN bounce restarts every slot with `wgcN_enable=1`. A throwaway slot left enabled came back by itself.
- **The mailer.** With a watchdog DoH server set, the SMTP host's address is looked up that way and put in `/etc/hosts`, so the alert needs no resolver. Without one the mailer asks the router's resolver, and a refused upstream means the alert fails; the script already remembers a missed email and the next one says so (`UNSENTFILE`).
- **Rebuild.** With a DoH server set, the rebuild resolves PIA's names that way; without one (or if the lookup fails) curl asks the router's resolver. So the hold stops a rebuild only for a slot that shares an address with the router, has no working DoH server, and is the one stopped.
- **The WAN-up window, measured again** with the hold on the real address and polling once a second (this BusyBox's `sleep` takes whole seconds only): the address went out the WAN for one poll, between the WAN coming up and the tunnel's route returning, about one to two seconds on this router.
- **Not measured:** the hold across a real reboot (it would take every device offline and wasn't asked for); other Merlin versions; whether the app's guard can place all of this from its hooks without a race.
- **Side effect of the cleanup:** running `merlin-guard.sh` removed two stale `prohibit` rules (old device addresses) and added two for the addresses set in VPN Director on 2026-11-21. The guard now matches the rules file. Until it ran, those two devices weren't held, since a change made in VPN Director's own page isn't guarded until the next tunnel start or boot.

### Two real reboots, 2026-11-22 (Andrew asked for them)

A sampler on `services-start` logged once a second: the route for each of the router's two DNS addresses, the source address of real connections to them (a WAN source means the lookup left by the WAN, a 10.x one by a tunnel), whether the clock was set, which tunnels were up. Reboot 1 was a control with no hold. Reboot 2 held one address with the route design (the WAN route deleted, a blackhole at metric 100, polled each second) and the other with a firewall rule placed by `firewall-start` (`-d <addr> ! -o wgc+ -j DROP`), both from boot and both released by themselves after 200 s so the router couldn't be stranded. The router's DNS Server setting, DoT list and wgc5's DNS were the same two addresses, which is the case the hold is for.

- **Control: the router's lookups leave by the WAN for about two minutes after every boot.** The WAN comes up about 29 s in and the WAN routes for both addresses appear with it; connections to them carry the WAN source until the tunnels start, about 150 s. The clock is set at about 105 s, using that WAN path. The guard's rules are flushed at WAN-up and back within 2 s.
- **Hold from boot: it blocks the lookups, and it stops the router starting its tunnels.** While the hold was in place no new connection to either address was created (a dropped packet leaves no connection entry), and the clock stayed unset for the whole 197 s, against 76 s after WAN-up in the control. After the release the clock was set at 337 s and the tunnels at 366 s and 397 s, about 215 s later than in the control. Time sync resolves its server through the router's resolver (`rc/ntp.c`, `nslookup`), and `start_wgcall` waits for the clock (`rc/wireguard.c`, `_wait_time_sync`), so with every upstream held and no tunnel yet, nothing can start. **A hold must therefore never be armed before the clock is set and a sharing slot has run, and the boot-time leak of about two minutes stays**, as it is today.
- **A side effect:** wgc5's own watchdog rebuilt wgc5 at about 6 minutes after that boot and sent one SUCCESS email, because the tunnel came up late. The router's tunnel address for it changed.
- **The route hold leaked once at WAN-up.** The WAN route for the address appeared for one sample before the poll removed it, and a probe in that second left by the WAN (one connection entry with a WAN source). The firewall rule was already in place at the first sample after the firewall started, in the same second as the WAN route, and `firewall-start` ran again 15 s later when the firewall was rebuilt. Neither is proven to be zero seconds: a packet counter on the rule, read at a finer grain, would show it.
- **Firewall-rule hold, as a design:** it doesn't depend on the guard's timing, because Merlin rebuilds the firewall and runs `firewall-start` each time. It only blocks the WAN path, so tunnel traffic to the address is untouched, and it needs no backup routes to work; the backup routes are still wanted so that a second running slot carries the lookups.

### The WAN-up window with packet counters, 2026-11-22 (Andrew asked for it before the design was fixed)

Two WAN bounces on the real addresses, sampled every 50 ms: a control with no hold, then the firewall-rule hold placed by `firewall-start`. Probes to both addresses were sent continuously; a leak is a connection entry whose source is not a tunnel or LAN address, and the rule's packet counter says how many packets it refused.

- **Control:** the WAN routes returned 5.22 s after the bounce was requested and the tunnel's routes 0.9 s later. In that time 16 connections to each address left with the WAN source.
- **With the rule:** no leaked connection while the WAN route existed (0 entries), and the rule refused 26 packets per address. The firewall was rebuilt about 4.1 s in, the rule was absent for about 0.4 s while the route was still the tunnel's, and `firewall-start` put it back about 1 s before the WAN route returned (hook log: 4.16 s). Once the route went back to the tunnel the counter stopped at 26, so nothing left by a non-tunnel interface after that. Fifteen connection entries with a non-tunnel source address appeared in the first second after the tunnel's route returned and the rule's counter did not rise; the reading that fits is probes bound to the WAN source before the route changed and then sent out the tunnel, which is not proven.
- **One event only.** A boot, a DHCP renewal and a firewall restart on its own weren't measured with counters, and the order of the firewall's rebuild and the WAN route at boot is not known (the earlier boot run had both in the same second). At boot the hold isn't armed in the design, for the reason in the reboot results, so only mid-session WAN events count.
- **Superseded by the next section:** the filter-table rule has a gap each time the firewall is rebuilt, and the order of the firewall rebuild and the WAN route is not fixed. The mechanism is a raw-table rule.
- **Not shared means no hold.** The hold exists only for an address that both the router uses and a configured slot lists. With different addresses there is nothing to hold, no deadlock at boot, and the router's lookups use the WAN by the user's own choice. Partial sharing was measured: see the next section.

### The rest of the measurements, 2026-11-22 (Andrew: nothing is to be left "not measured" that can be measured)

All on the real router, wgc5 stopped the way the app's DISABLE does (`wgcN_enable=0`, then `stop_wgc`), sampled every 50 ms, probes to both addresses sent continuously. A leak is a connection with a non-tunnel, non-LAN source; a refused packet is the rule's counter.

- **Slot stopped, no hold (ID-636 measured a second time):** 465 connections to each address left by the WAN in 30 s. **With the filter-table rule placed by `firewall-start`:** none, and 2,533 and 2,509 packets refused. A DROP in OUTPUT makes the sender's `sendto` fail at once (EPERM), so a lookup is refused immediately, not after a timeout.
- **Events that rebuild the firewall leave the filter rule absent for part of a second** (0.35 to 0.6 s). While the slot was stopped, that leaked 8 connections to each address for a firewall rebuild, and about 31 for a WAN bounce, which rebuilds the firewall twice (at about 4 s and 19 s). The WAN route can return before the firewall is rebuilt, so the earlier "rule first, WAN route a second later" order was one observation, not a guarantee. A blackhole route as well doesn't cover a WAN bounce: Merlin re-adds the WAN route at the same metric and it wins.
- **A rule in the `raw` table survives all of that.** The same events, with the slot stopped: a firewall rebuild, a WAN bounce, both with 0 leaked connections and the rule present at every sample, and 0 leaks. So the hold is a **raw-table rule**, `iptables -t raw -I OUTPUT -d <addr> ! -o wgc+ -j DROP`. The tunnel's own traffic is untouched (the router's lookups worked again as soon as the slot's tunnel was up).
- **A DHCP lease renewal** (`udhcpc` signalled) changed nothing observable in 20 s: no route or rule change. Not a gap on this router.
- **Lookups.** Asked of an upstream address directly for a name that exists: refused with the hold, answered with the rule lifted and answered again after it was put back. The router's own resolver (dnsmasq with DNS-over-TLS) with the slot stopped and no hold: answered after 14 s (stubby reconnecting by the WAN); with both addresses held: no answer in 30 s; with only one held: answered at once; after the lift: answered at once. (My first resolver check used names that resolve to private addresses, which dnsmasq's rebind protection drops: with the tunnel up it also "failed". Corrected, and the tunnel-up control then answered at once.)
- **Partial sharing at boot costs time.** With one address held from boot and the other open, the clock was set at 274 s against 105 s in the control, and the tunnels were up at 343 s against 152 s. Time sync survived, so partial sharing isn't a deadlock, but it adds about 170 s. Holding both from boot (the earlier run) blocked the clock until the hold released. **So nothing is held from boot.**
- **Armed after the clock is set, it costs nothing.** In the same boot the second address was armed the moment the clock was set (at 274 s), with the first already held, so both were held from then on. The tunnels came up 69 s later (47 s in the control: the retry job runs on a one-minute cycle), and the counters stopped rising once the tunnels were up (1,226 and 292 packets refused, none after 343 s). The router's own lookups were refused from arming until the tunnels were up, 69 s.
- **Doubled DNAT rules for wgc1:** gone by themselves after later restarts; the chains read as single rules again on 2026-11-22. Merlin's `wgc_set_exclusive_dns` appends and doesn't clear first, so only a second start of a running slot doubles them (`rc/wireguard.c` and `libovpn/amvpn_routing.c` at 3004.388.13). Cause on that boot not established.

### Which setting feeds the router's own lookups, and the events the guard can react to (2026-11-22)

With the settings set to different addresses, as the new CONTEXT.md rule requires, and wgc1 (Quad9) as the holder, then everything put back: with **DNS-over-TLS on, the DoT list alone** carried the router's lookups (stubby's connections to the DoT addresses, over wgc1 while it ran and over the WAN when it was stopped; the DNS Server setting's addresses saw nothing). With **DNS-over-TLS off, the DNS Server setting** carried them as plain DNS (82 connections to one address over the WAN while wgc1 was stopped; the DoT list saw nothing). A raw rule on the shared addresses stopped both, and the router's resolver then answered none of its lookups, as intended. So the addresses the hold covers are the DoT list when DoT is on and the DNS Server setting when it is off, which is what `ownServers` in `router_dns.dart` already computes.

Merlin's web page applies a DNS change with `restart_wan_if`, `restart_stubby` and `restart_dnsmasq` (`www/Advanced_WAN_Content.asp` at 3004.388.13). With a logging `service-event` and `service-event-end` in place, both fired for `restart dnsmasq`, `stubby`, `dnsfilter`, `vpnrouting0`, `wan_dns` and `wan_if` (the end hook 2.1 s after the WAN one began), and the raw rule was present after each. The router already had a one-line `service-event` stub, which was put back byte for byte. IPv6: `ipv6_service` is disabled on this router and it has no IPv6 raw table; the slot DNS field takes IPv4 only, so a shared address is always IPv4.

### Built, and seen on the router (2026-11-22)

The design above was built as ID-636 (the hold), ID-652 (the takeover), ID-653 (the rebuild's lift) and ID-657 to ID-659 (the check, the warnings, the reboot). What changed on the way, and what was seen with the built guard:

- **The takeover is rules, not backup routes.** Backup routes need the WAN route for the address deleted and put back, and Merlin re-adds it at WAN-up at a metric that beats them. The guard puts one `ip rule to <addr> iif lo lookup wgcN` at 1050 minus N for each running slot that lists a held address instead. A stopped slot's table is flushed, so its rule finds nothing and the kernel falls through to the next slot's, and last to the main table, where the raw rule refuses it. With throwaway slots wgc3 and wgc4: both running, the route was wgc4; wgc4 stopped, before the guard ran again, wgc3; both stopped, the WAN route, and a probe left no connection by the WAN. The highest-numbered running slot wins, as on stock; Merlin gave the lookups to the first slot to start. The `check-claims.sh` full-mode checks TAKEOVER-first, -second and -none pass on the router and TAKEOVER-first fails against a guard whose takeover does nothing.
- **The hold's check** (HOLD-control, HOLD-refuses, HOLD-firewall, HOLD-release in quick mode) passes with the new guard and HOLD-refuses and HOLD-firewall fail with a hold that does nothing.
- **A real reboot with the guard's own code** (not the prototype): nothing was held until the clock was set, which came at about 105 s, as in the control; the hold was armed in the same second by the boot watch; the tunnels were up at about 177 s (152 s in the control; the retry job's one-minute cycle); 298 and 293 packets to the router's two DNS addresses were refused between the clock and the tunnels, where the control let them out by the WAN; the takeover rules for wgc5 went in as it started, and the refused counters did not move after that. So the boot leak is the time to the clock, about 75 s after the WAN, not the whole time to the tunnels. This router does share an address: wgc5's DNS is its DoT list.
- **This router, once the new guard is deployed:** the router's lookups are held to wgc5's tunnel by the rule, and refused while wgc5 is stopped.

What this means for the design, as Andrew decided on 2026-11-22 (black hole, with a warning in the slot form's amber text, not a block):

- (Superseded by "Built, and seen on the router": the takeover is rules, not backup routes.) The hold is a **raw-table** rule, `iptables -t raw -I OUTPUT -d <addr> ! -o wgc+ -j DROP`, for each address the router uses that a configured slot also lists. The guard places it, `firewall-start` puts it back if it is ever missing, and it comes out when no slot lists the address and on UNINSTALL. It needs no route work. Optional, for availability only: with the rule alone, a second running slot that shares the address does not carry the router's lookups when the holder stops (they are refused until the holder is back), so the backup-route scheme (WAN route removed, a route per running sharing slot at metric 10 plus the slot) is a later addition, not part of the first build.
- Armed only once the clock is set, never from boot, and not even for one of two addresses: held from boot the clock took 274 s instead of 105 s, and with both held it never came until the hold released. The boot leak of about two minutes stays and is said so in the README and in the slot form's amber note, so each user decides.
- A slot with no DoH server of its own that shares the router's DNS has the hold lifted by its watchdog for the few seconds of a rebuild and put back, even on failure; with a DoH server it stays on. The note recommends a DoH server.
- The app's text says it plainly: while the slot is stopped, lookups to that address are refused, devices that depend on the router's resolver may lose name lookups, and a watchdog with no DoH server may not be able to look up PIA's host to rebuild or the mail server to send.

### Real rebuilds of a throwaway slot, 2026-11-22 (ID-660, ID-629; Andrew's yes for the PIA logins and emails)

A throwaway `wgc3` (region `pia-aus_melbourne`, the alert settings of `wgc1`, DNS equal to the router's DoT list, no DoH server first and the same DoH resolver as `wgc1` second) was made with `nvram` and a watchdog script generated by `buildWatchdogScript`, a placeholder endpoint in the documentation range so the guard counted it, and run with `foreground`. A sampler beside it read the raw table every 0.3 s. Everything was removed afterwards and the router read back to its baseline.

- **No DoH server (the lift).** The rule held both addresses until the check began, was open from the lift to the end of the run, and was back in the same second the script ended. The PIA token, the server list and the key registration all worked through the router's resolver during the lift. The log says the lift and the restore. Three runs.
- **With a DoH server.** Both addresses stayed held at every sample, there was no lift line, PIA's names were looked up over DoH, the rebuild succeeded and the email was sent.
- **A gap in the lift, found and fixed (ID-663).** The email failed on name resolution 8 s after the tunnel came up in 2 runs of 2, where a control with the hold off from the start sent it. Resolver probes (one new name a second, a probe over 3 s counted as stalled) showed why: after a hold that had refused lookups, the first lookups after the slot started stalled for about 15 s (two slow probes of 5 to 7 s each, 3 of 3 runs); with no hold before, none (3 of 3). Restarting stubby at the lift did not help (2 of 2 still stalled); restarting it once the slot had its handshake did (0 slow probes, 2 of 2). The watchdog now restarts it then, and only when the hold held one of its slot's addresses. With that, the sharing slot's rebuild sent its email in 2 runs of 2.
- **A slot that shares the router's DNS and goes dead cannot send its FAILED email.** With the tunnel up and answering nothing, the router's lookups to the shared address go into it, so the mail server's name does not resolve; the lift cannot help, because the hold is not what refuses them. That is the old, documented failure (ROUTER-DNS 4), not a regression. WD-29 therefore has to be run on a slot whose DNS differs from the router's.
- **WD-29 (ID-629), on a slot that doesn't share.** Cut the server and PIA's login; after the handshake was 300 s old the check found no handshake and no pings, the rebuild failed and one FAILED email went out. With the cut removed, the next check's ping woke the tunnel and sent exactly one RECOVERED; the two checks after sent nothing. Stopping the tunnel made the next check rebuild it, one SUCCESS went out, and the two checks after sent no RECOVERED. The first run with the slot still sharing is the previous bullet.

### What Merlin does to each kind of DNS traffic, 2026-11-22 (ID-667)

Probed from a PC the default slot's whole-network rule covers, with DNS-over-TLS and DNS Director on: UDP and TCP port 53 to the router, and UDP and TCP port 53 to `8.8.4.4`, were each rewritten to wgc5's DNS server and answered from wgc5's tunnel address (the whole-network rule's counter rose from 554 to 579 packets, no per-device rule moved); a connection to port 443 of another address was not rewritten and left from the tunnel's address; three connections to port 853 never started and DNS Director's `DNSFILTER_DOT` counter rose from 927 to 936. The `PREROUTING` jumps to every `DNSVPN` chain are `-p tcp --dport 53` and `-p udp --dport 53` with no destination, so this is wider than stock's redirect. Not measured: a device pinned to a slot other than the default, DoT with DNS Director off, and any probe with the internet as the default.

## Work item detail, moved from CHANGELOG (2026-11-22)

Moved verbatim from CHANGELOG.md on 2026-11-22: CHANGE-PROCESS.md section 3 keeps a work item to its first line and one `Closed` line, and these had grown into paragraphs. Nothing was cut. Read the CHANGELOG line for what was done and this for how and why.

### ID-641

```text
- ID-641 ARC: the documentation and the app's code are split by firmware, after the 2026-11-20 Merlin DNS findings. Andrew reviewed [plan_dns.md](.claude/plans/plan_dns.md) and decided on 2026-11-22: the how-to guidance is split by firmware and the concepts stay together (ID-654); a small per-firmware DNS model is built by ID-640, with each firmware's measured output as its test fixtures; the router's own DNS protection is designed for Merlin first (ID-636, ID-652, ID-653) and stock follows ID-639's measurements; and the measurement rule is added to `.claude/CONTEXT.md` section 1. ID-594 moved to Next Release. The statement rule is added as well, in the same section, at Andrew's later yes: a statement about router behaviour, in a document or in the app's text, names the firmware and the date, and is read as stock's when it names none.
  - DoD: the plan's decisions answered by Andrew, and each one turned into an item or declined.
  - Closed 2026-11-22: all five decisions are answered and each is an item (ID-640, ID-654, ID-636, ID-652, ID-653, ID-639) or the rules in CONTEXT.md section 1: the measurement rule, a new bullet under "When the router disagrees with you", and the statement rule, added to the claim rule.
```

### ID-640

```text
- ID-640 FIX: the app's text about devices that aren't pinned was stock's, and was wrong on Merlin when the default connection is a tunnel, where those devices use the default slot's DNS servers and not the router's resolver (measured 2026-11-20, ROUTER-DNS.md section 2). The places: `resolverAdvice` in `router_dns.dart` (every message says "devices that aren't pinned to a VPN can't look names up"), its group label "YOUR DEVICES' LOOKUPS" for dnsmasq and stubby, the watchdog's "Router resolver FAILED" log lines in `router_watchdog.dart` (a redeploy carries a change), and the overlap note `kDnsMatchesRouterNote` in `common_fields.dart` ("every device you have not pinned"). ROUTER DNS ROUTING and ROUTER RESOLVER STATUS are to be read on Merlin for any other line that says it. Decided 2026-11-22: this item builds a small per-firmware DNS model that answers three questions (who answers a device that isn't pinned, given the default connection; which slot carries the router's own lookups; what happens when that slot stops), and the messages take their wording from it, in a table of sentences, not in branching code, so that SonarCloud's limits hold. The measured outputs for each firmware are its test fixtures; stock's come from the September 2026 records and say so. README 5.5's line on the resolver check was corrected on 2026-11-20. Raised 2026-11-20.
  - DoD: on Merlin each message says what is true for the default connection the router has (a tunnel, or the internet), with a test for each wording, and Andrew has read ROUTER DNS ROUTING and ROUTER RESOLVER STATUS on Merlin with each default; stock's text is unchanged, byte for byte in the golden tests, and a case never measured on stock says so; releasable on its own.
  - Partly done 2026-11-22: built in `lib/dns_wording.dart`, a small model of the firmware and the default connection (a tunnel, the internet, or not known) that holds each sentence in a table and says what each rests on. `resolverAdvice`, the heading and the file descriptions on ROUTER RESOLVER STATUS (which now reads the firmware and VPN Director's whole-network rule, `parseDnsWording`), the slot form's overlap note (`dnsMatchesRouterNote`) and the watchdog's two "Router resolver FAILED" log lines take their wording from it; a redeploy carries the watchdog's. On Merlin with a tunnel as the default the messages say the router's own lookups fail and that devices that aren't pinned use the default tunnel's DNS servers and still look names up; with the internet as the default they name those devices; with the default not known they say both. Stock's text is unchanged byte for byte: the existing goldens and widget tests pass untouched, and `test/unit/dns_wording_test.dart` pins each stock sentence beside each Merlin case, with the reader tested against the router's replies and the generated script for both firmwares. Stock's cases not measured since September 2026 are labelled as such in the file (ID-639). Remainder: ID-656, Andrew reading both screens on Merlin with each default.
```

### ID-636

```text
- ID-636 BUG: on Merlin, when the slot that holds a DNS address shared with the router is stopped, disabled or being rebuilt, the router's own lookups for that address left over the internet connection from the home address, by the WAN route Merlin adds for the router's own DNS (`rc/wan.c`), until a sharing slot starts. Measured on 388.13_0 on 2026-11-20 and again on 2026-11-22: 465 connections to each address left by the WAN in 30 s. It breaks setup B's promise that the provider doesn't see the home address. Raised 2026-11-20.
  - Decided 2026-11-22 (Andrew): a hold that refuses them, with a warning in the slot form's amber note and the README, not a block on saving. The router's lookups, and the devices that depend on its resolver, fail while the slot is down. On by default once the guard runs, with no setting to turn it off, and the release note and the amber note say so (Andrew, 2026-11-22). Other Merlin versions and dual WAN will not be measured (Andrew, 2026-11-22), so the README says it was measured on 388.13 with one WAN.
  - Design, measured 2026-11-22 (plan_dns.md): a rule in the raw table, `iptables -t raw -I OUTPUT -d <addr> ! -o wgc+ -j DROP`, for each address the router uses that a configured slot also lists. The guard places it, `firewall-start` puts it back if it is missing, and it comes out when no slot lists the address and at UNINSTALL. A rule in the filter table leaves a gap at every firewall rebuild, and a route hold is beaten by the WAN route Merlin re-adds at WAN-up; the raw rule survived both with no leaked connection. It is armed only once the clock is set, never from boot: held from boot the clock took 274 s instead of 105 s, and with both addresses held it never came. The boot leak of about two minutes stays, and the README and the note say so.
  - Which addresses, and when, measured 2026-11-22 with the DNS Server setting and the DoT list set to different addresses: the router's own lookups use the DoT list when DNS-over-TLS is on and the DNS Server setting when it is off, and the other is unused (a slot sharing the unused one leaks nothing and needs no hold), as `ownServers` in `router_dns.dart` already works out. The web page's DNS Apply runs `restart_wan_if`, `restart_stubby` and `restart_dnsmasq`; `service-event-end` fires for each (and for `restart_wan_dns`, `restart_dnsfilter` and `restart_vpnrouting0`) and the raw rule survived every one, so the guard re-reads the settings from that hook. IPv4 only: the slot DNS field takes IPv4 addresses and this router has no IPv6 raw table.
  - DoD: with the rule placed, a stopped, disabled or rebuilding slot leaks no connection to the address over the WAN, through a firewall rebuild and a WAN bounce, in `check-claims.sh` with a check seen to fail with the rule removed; after a reboot the rule is placed once the clock is set and the tunnels still start; README, ROUTER-DNS.md and the slot form's note say what the hold does, who loses name lookups while the slot is down, and the boot leak; DISABLE's and DELETE's confirmations say that the router's own lookups stop while a slot that shares the router's DNS is down; unit tests for the guard's script and the note's wording.
  - Plan: [plan_router-dns-slot.md](.claude/plans/plan_router-dns-slot.md), and the measurements in [plan_dns.md](.claude/plans/plan_dns.md)
  - Partly done 2026-11-22: built in `lib/merlin_guard.dart`: `merlin-guard.sh` has a `hold` mode (`router_dns`, `slot_dns`, `holds`, `held_addrs`, `hold`) that puts `-d <addr> ! -o wgc+ -j DROP` in the raw table for each address the router uses (the DoT list while DNS-over-TLS is on, the DNS Server setting while it is off) that a slot with a server also lists, whatever the slot's state, only once the clock is set, takes it out when no slot lists the address, says each change in the router's log, and reports an address the router refused as an error for the next watchdog run. The guard's ordinary run, `table N` and the boot watch run it, so it arms as the clock is set after a boot, and a new `service-event-end` hook line, kept and removed with the other two, re-reads the settings after `restart wan_if`, `wan_dns`, `stubby`, `dnsmasq` and `dnspriv`; `clear` removes it for UNINSTALL. `GUARD_HOLD_ADDRS` names addresses outright, for `check-claims.sh`. 13 new tests in `test/unit/merlin_guard_test.dart` on a fake `iptables` that keeps the raw table in a file: which addresses, with DNS-over-TLS on and off, never from boot, a slot with no server, a stopped slot, the hold let go, the watch arming it when the clock is set mid-watch, a refusal kept as an error, the override, `clear`, and only the raw table touched. The fake `nvram` now ends its answers with a newline as the router's does: without one the first run ran two slots' DNS lists together and held one address of two. Remainder: ID-657.
```

### ID-657

```text
- ID-657 ADD: continuing ID-636, which built the guard's hold: the rest of it. A check in `check-claims.sh`, seen to fail with the rule removed, on the router's own kernel (the rule placed, a stopped slot's probe to the address leaving no connection by the WAN, the rule surviving a firewall rebuild, and the same probe leaking with the rule taken off); the confirmations for DISABLE and DELETE saying that the router's own lookups stop while a slot that shares the router's DNS is down; the slot form's note saying what the hold does and the boot leak; README and ROUTER-DNS.md for each firmware (ID-654 carries the rest of the split); and the hold seen on the router with throwaway slots, and through a reboot. Raised 2026-11-22.
  - DoD: `check-claims.sh` has the check and it has been seen to fail with the rule removed; DISABLE's and DELETE's confirmations name the router's own lookups when the slot shares its DNS, on Merlin only, with a test for each; the slot form's amber note, README and ROUTER-DNS.md say what the hold does, who loses name lookups while the slot is down, and the boot leak of about two minutes; on the router the rule is placed once the clock is set and the tunnels still start through a reboot, and a stopped sharing slot leaks nothing by the WAN, written in the plan's measurements.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
  - Partly done 2026-11-22: built in `scripts/check-claims.sh`, in quick mode on Merlin: a stand-in address in the documentation range is held through the guard (`GUARD_HOLD_ADDRS`), with a control first (with no rule a probe leaves by the WAN, so a leak can be seen), then the rule placed in the raw table and the probe leaving no connection by the WAN, the rule surviving `restart_firewall`, and the guard letting go of an address no slot lists, with `hold_verdict` and `hold_seen_verdict` in the verdicts block, which name the safe answer exactly (a count that is not a number is not zero), and the restore taking the stand-in's rule out. Seen on the router, 388.13, on 2026-11-22: all four checks pass with the new guard, and with a guard whose hold does nothing HOLD-refuses and HOLD-firewall fail. The first run said "not checked" because this BusyBox has no `command`; it uses `which`. The run also showed that this router does share an address: wgc5's DNS is the router's DoT list, so the guard held the router's own two DNS addresses (removed again by hand; the old guard on the router doesn't manage them). Remainder: ID-658.
```

### ID-658

```text
- ID-658 ADD: continuing ID-657, which built the hold's check: the rest. The confirmations for DISABLE and DELETE saying that the router's own lookups stop while a slot that shares the router's DNS is down; the slot form's amber note saying what the hold does and that it does not cover boot; README and ROUTER-DNS.md for each firmware (ID-654 carries the rest of the split); and the hold seen through a reboot on the router. Raised 2026-11-22.
  - DoD: DISABLE's and DELETE's confirmations name the router's own lookups when the slot shares its DNS, on Merlin only, with a test for each; the slot form's note, README and ROUTER-DNS.md say what the hold does, who loses name lookups while the slot is down, and the boot leak of about two minutes; on the router the hold is placed once the clock is set after a reboot and the tunnels still start, written in the plan's measurements.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
  - Partly done 2026-11-22: built in `lib/widgets/slot_modal.dart`, `lib/dns_wording.dart`, `lib/router_slot_service.dart` and `lib/router_ops.dart`. DISABLE's and DELETE's confirmations, on Merlin, name the router's own lookups when the slot lists an address the router uses (`routerDnsWarning`, joined with the pinned-devices warning by `joinWarnings`): while the VPN is down the router refuses its lookups to the address and the router and any device that relies on its resolver can't look names up until it is enabled again; deleting it ends the sharing and those lookups then leave by the internet connection from the home address. The slot form's note on Merlin says what the hold does, that it refuses rather than sends over the internet connection while the slot is stopped, disabled or being rebuilt, that the first two minutes after a reboot are not covered, and that different DNS servers avoid all of it. The slot form and both confirmations now know the router's own addresses on Merlin with DNS-over-TLS off too: `kDotServerListCommand` reads the DNS Server setting (`wan0_dns`) as well and `parseDotServerList(dnsServerWhenOff: true)` returns it then (stock's answer is unchanged), since measured 2026-11-22 that setting carries the router's lookups while DoT is off. `deleteSlot` and `writeSlotParams` have the guard re-read the addresses on Merlin so the hold follows a deleted slot or an edited DNS, and stock does not. Tests: the confirmations on Merlin for DISABLE and DELETE through the real dialog and as text, nothing shared and stock saying nothing, the parser with DoT on and off, the guard run after a delete and after a DNS write, and the note's Merlin text. The documents' text and the reboot remain: Remainder: ID-654 (ROUTER-DNS.md and README, with the rest of the firmware split) and ID-659 (the hold through a reboot).
```

### ID-653

```text
- ID-653 ADD: a slot with no DoH server of its own that shares the router's DNS can still be rebuilt while ID-636's hold is on. The rebuild asks the router's resolver for PIA's names, which the hold refuses; with a DoH server set, the rebuild and the alert email's mail server address don't use the resolver (`lookup()` and `resolve_smtp` in `router_watchdog.dart`). Decided 2026-11-22 (Andrew, option 3): the watchdog lifts the hold for the length of the rebuild and puts it back, even when the rebuild fails, and says so in its log and email; a slot with a DoH server keeps the hold on, and the WATCHDOG form recommends one for a slot that shares the router's DNS.
  - DoD: on the router, a rebuild of a sharing slot with no DoH server resolves PIA's names and the hold is back afterwards, after a failed rebuild too; with a DoH server the hold stays on throughout; tests on the script's lift and restore. A redeploy of the watchdog carries it, and the release note says so.
  - Partly done 2026-11-22: built. The guard (`lib/merlin_guard.dart`) has `lift N` and `restore`: a lift is `<epoch> <slot>` in `/tmp/cfg-pia-wg-hold-lift`, lets go of the addresses that slot lists and no others, stops the ordinary run, `table N`, the watch and the event hook putting the hold back while it stands, and expires after ten minutes, so a watchdog that dies leaves the hold back on by itself; `restore` removes it and puts the hold back; both say so in the router's log. The watchdog script (`lib/router_watchdog.dart`) calls `hold_lift` at the start of a rebuild when it has no DoH server of its own, and `hold_back` from its EXIT trap, so the hold is back however the script ends, after the alert email has gone; with a DoH server it does nothing, and on stock the guard isn't there and both are no-ops. A redeploy of the watchdog carries it. The watchdog form shows an amber note, as the DNS or the DoH URL is typed, when the slot's DNS is also the router's and no DoH server is chosen (`dohHoldHint`), saying the hold is lifted for each rebuild and that a DoH server keeps it on. 7 guard tests (lift for one slot only, not re-armed while lifted, restore, ten-minute expiry, a malformed lift ignored, `lift` with no slot, `clear`), 8 on the script's functions run in a shell against a fake guard (lift, DoH, the exit trap after an abort, nothing lifted, no guard, a refused lift, and where in the script the lift and the trap are), and 2 on the form's note. Remainder: ID-660, the rebuild on the router with Andrew's yes (it logs in to PIA and sends the alert email).
```

### ID-652

```text
- ID-652 ADD: on Merlin, a second running slot that lists the same DNS address as the router's DNS carries the router's lookups when the slot holding it stops. Merlin adds a slot's route to its DNS address only as the slot starts, so a second slot never has one and, with ID-636's hold, the lookups would be refused until the holder is back. Measured 2026-11-22 (plan_dns.md): with the WAN route for the address deleted, a route per running sharing slot at metric 10 plus the slot, and a blackhole at metric 100, the lookups moved to the other slot when the holder stopped, in both start orders, and were refused when none was left; two backups at the same metric collide. The WAN route returns at WAN-up and beats the backups, so the raw rule of ID-636 stays the safety net until the guard acts. Added to this commit at Andrew's request, 2026-11-22.
  - DoD: with two running slots sharing the address, `ip route get` for it shows the other slot after the holder stops and refusal after both stop; a check in `check-claims.sh` seen to fail with the takeover removed, on two sharing slots (throwaway slots if the router has no two real ones, as in the plan); unit tests for the guard's logic.
  - Closed 2026-11-22: built in `lib/merlin_guard.dart` as rules, not as backup routes: the design changed after the first measurement, because backup routes need Merlin's WAN route for the address deleted and put back, and Merlin re-adds it at WAN-up at a metric that beats them. The guard's `takeover` puts one `ip rule to <addr> iif lo lookup wgcN` at 1050 minus N for each running slot that lists a held address (the highest-numbered slot wins, as on stock), removes the rule of a slot that has stopped, puts none in before the clock is set or while a rebuild has the hold lifted, and `clear` removes them; the watchdog's own probe at 1000 is ahead of them. A stopped slot's table is flushed, so its rule finds nothing and the kernel falls through to the next slot's, and last to the main table, where the raw rule refuses it, with no event needed. Measured on the router, 388.13, 2026-11-22, with throwaway slots wgc3 and wgc4 and the new guard: both running, `ip route get` showed wgc4; with wgc4 stopped and the guard not yet run again, wgc3; with both stopped, the WAN route, and a probe to the address left no connection by the WAN; wgc3 back, then both, as before; the ordinary run and `table N` kept the rules. 8 tests in `test/unit/merlin_guard_test.dart` (which slots get a rule, the priority order, a slot that stops, a second run, never before the clock, the lift, another slot's rules, `clear`), `takeover_verdict` tested on its own, and the full-mode check TAKEOVER-first, -second and -none in `scripts/check-claims.sh`, seen to pass on the router and to fail (TAKEOVER-first) against a guard whose takeover does nothing; the throwaway slots are removed by the run and by the restore trap. The router's lookups to a shared address now follow the highest-numbered running sharing slot, where Merlin gave them to the first slot to start: ROUTER-DNS.md says so (ID-654).
```

### ID-659

```text
- ID-659 TST: continuing ID-658: the hold through a real reboot of the router with the guard's own code, not the prototype of 2026-11-22: the rule is placed by the boot watch once the clock is set and not before, the tunnels still start, and nothing leaves by the WAN to the held addresses after the tunnels are up. Run by Claude over SSH with the new guard on the router and the old one put back after, with Andrew's permission for the session. Raised 2026-11-22.
  - DoD: the boot's timeline written in the plan: the clock, the arming, the tunnels, and the refused-packet counters, compared with the control of 2026-11-22.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
  - Closed 2026-11-22: run on the router, 388.13, with the new guard in place of the installed one and the sampler on `services-start`, then everything put back (the guard byte for byte, `services-start` identical, rules, routes and firewall as before). Nothing was held until the clock was set, at about 105 s, as in the control with no hold; the boot watch armed both of the router's DNS addresses in the same second (wgc5's DNS is its DoT list); the tunnels were up at about 177 s against 152 s in the control, the retry job's one-minute cycle; between the clock and the tunnels 298 and 293 packets to the two addresses were refused, where the control let them out by the WAN; the takeover rules for wgc5 were added as it started, and the counters did not move after that. The boot leak is therefore the time to the clock, about 75 s after the WAN comes up, and not the whole time to the tunnels. Written in `.claude/plans/plan_dns.md`.
```

### ID-654

```text
- ID-654 DOC: split the DNS how-to by firmware, as decided in ID-641: ROUTER-DNS.md sections 5 and 6 into a stock how-to and a Merlin how-to, section 7 into a stock and a Merlin subsection, sections 1 to 4 kept as one concept in the order common statement, On stock, On Merlin; the README kept short with a pointer for each firmware. Then the places in plan_dns.md's "Not yet audited" list, the store listings and the in-app help first, each read for a statement that holds for stock only. A statement about router behaviour names the firmware and the date measured; stock's say "measured September 2026" or "not measured on stock" until ID-639.
  - DoD: each place read and corrected or confirmed, listed in the item's closing line in CHANGELOG, and the link and testing-figure tests pass.
  - Closed 2026-11-22: ROUTER-DNS.md says what the hold does on Merlin from build 588 and why it is in the raw table, what it does not cover (the first part of a boot, until the clock is set), that the highest-numbered running slot that lists the address carries the router's lookups, and that a rebuild lifts it; the short version, the section 4 stopped-slot case, the two table rows and the Merlin paragraph of setup B are corrected, each with its date and router. README 5.2.1 and 5.2.2 say the same in a sentence each. ARCHITECTURE 6.10 records the design and the measurements, and the router resolver line's paragraph is worded for the firmware. The audit: the Google Play and App Store listings under `play-store/` and `app-store/` hold no DNS statement; the in-app text was read and the four places are ID-640's; TESTING.md's mentions of devices that aren't pinned are about the kill switch and the pings, not DNS; the other plan files that mention them are plans, which a later session doesn't read as current state. The restructure of sections 5 to 7 by firmware, which this item left, was done in ID-661.
```

### ID-660

```text
- ID-660 TST: continuing ID-653, which built the watchdog's lift of the hold: a real rebuild on the router of a slot that shares the router's DNS and has no DoH server, on Merlin, with Andrew's yes because it logs in to PIA and sends the alert email: the watchdog lifts the hold at the start of the rebuild, resolves PIA's names and the mail server, sends the email, and the hold is back as the script ends, in the router's log and in `ip rule`/`iptables -t raw`; then the same with a DoH server, where the hold stays on throughout. Raised 2026-11-22.
  - DoD: both runs written in the plan's measurements, with the router's log lines and the raw table before, during and after, and any failure a bug under its own ID.
  - Closed 2026-11-22: run on the router with Andrew's yes, on a throwaway wgc3 (removed afterwards; the router read back to its baseline). No DoH server: the raw rule held both addresses until the check began, was open from the lift to the end, and was back in the same second the script ended; PIA's login, server list and key registration worked through the router's resolver during the lift; the log says both. With a DoH server: held at every sample, no lift, the rebuild and the email worked over DoH. The measurements and the router's log lines are in plan_dns.md. It found a real gap, ID-663.
```

### ID-663

```text
- ID-663 BUG: the watchdog's alert email after a rebuild failed on name resolution, 8 s after the tunnel came up, for a slot that shares the router's DNS and has no DoH server, in 2 runs of 2 (found in ID-660). The lift (ID-653) opened the hold, but the router's resolver (stubby) had been refused while it was on and then stalled for about 15 s after the slot started.
  - DoD: the email goes out after such a rebuild, a test fails on the script without the fix, and the router shows it.
  - Closed 2026-11-22: `resolver_fresh` in the Merlin script restarts stubby once the tunnel has its handshake, only when the hold held one of the slot's own addresses, so a rebuild of a slot that doesn't share the router's DNS doesn't interrupt anyone's lookups. Measured on the router, resolver probes a second for 40 s after the slot started, hold history first: no fix 2 slow probes (5 to 7 s each) in 3 of 3 runs; stubby restarted at the lift 2 of 2 still stalled; restarted after the handshake 0 slow probes in 2 of 2; a control with no hold history 0 of 3. With the final script the sharing slot's rebuild sent its email. Four tests in `watchdog_hold_lift_test.dart` (one fails on the old script, one for each of the two conditions where nothing is restarted, and the script's order). The app carries it to a router by itself: at its first connection it replaces a watchdog script older than the app, and on Merlin refreshes the guard with it.
```

### ID-664

```text
- ID-664 BUG: on Merlin, ROUTER DNS ROUTING tagged a watchdog with no DoH server "Internet, not encrypted: the router's DNS Server setting", when its lookups go to dnsmasq and so, with DNS-over-TLS on, to stubby and the DoT list, through the same tunnel as the router's own. The evidence box with no rules said Merlin has no such rules and the first slot to start carries the lookups, which stopped being true with the guard's rules (ID-652). Seen on the emulator on 2026-11-22 (ID-666).
  - DoD: the watchdog's line follows the router's own, a golden fixture pins it, and the no-rules sentence says what the guard adds.
  - Closed 2026-11-22: `_watchdogViaLocalCache` in `router_dns.dart`; the new golden `routing_merlin_local_cache_no_doh.txt` reads "[Internet, encrypted (DoT)] - no encrypted DNS set: the router's own resolver, dnsmasq to stubby", and the two Merlin goldens change by the evidence sentence only.
```

### ID-666

```text
- ID-666 TST: continuing ID-656: ROUTER DNS ROUTING and ROUTER RESOLVER STATUS read on Merlin with a tunnel as the default connection, by Claude on the emulator against Andrew's router, with the throwaway wgc3 sharing the router's DNS and, for the second screen, its tunnel cut.
  - DoD: both screens read, each message checked against the router, and any wrong line a bug under its own ID.
  - Closed 2026-11-22: the devices, the router's own line, the slots' DNS and the evidence were all true for the router's state, including the guard's rules (priority 1047, to wgc3). Two wrong things: the watchdog line and the no-rules sentence (ID-664), and the resolver advice that names the DoT Server List and a reboot when the cause is a slot (ID-665). The reading with the internet as the default is left as ID-656.
```

### ID-667

```text
- ID-667 DOC: ROUTER-DNS.md 7.2.3 is completed from measurements, 7.2.1 has the diagram of the Merlin roads Andrew asked for, and section 6 is corrected: on Merlin plain DNS to any server is rewritten, not only DNS to the router.
  - DoD: the table says what was measured and what wasn't, ARCHITECTURE 6.10 and the plan carry the runs, and section 6 no longer says a device sending DNS to another server goes past the filter on Merlin.
  - Closed 2026-11-22: probed from a PC under the default slot's whole-network rule: UDP and TCP port 53 to the router and to another server were rewritten to wgc5's DNS server and answered from its tunnel address, port 443 was not rewritten, and port 853 was refused by DNS Director; the `PREROUTING` jumps are on TCP and UDP port 53 with no destination, so Merlin's rewrite is wider than stock's. Not measured, and said so: a device pinned to another slot, DoT with DNS Director off, the internet as the default.
```

### ID-656

```text
- ID-656 TST: continuing ID-666, which read both screens on Merlin with a tunnel as the default connection: Andrew reads ROUTER DNS ROUTING and ROUTER RESOLVER STATUS on Merlin with the internet as the default connection, since the wording follows the default VPN Director has and Claude can't change the household's default to read it. Raised 2026-11-22.
  - DoD: both screens read with the internet as the default, each message true for it, and any line that still says something that is stock's a bug under its own ID.
  - Closed 2026-11-22: with Andrew's authority to change the default for testing, set to the internet through DEVICES (APPLY 1 CHANGE) on the emulator, read, and set back to wgc5 the same way; the router's rules file, `vpnc_default_wan`, `vpnc_dev_policy_list`, `ip rule` and the nat table hash identically before and after. ROUTER DNS ROUTING read true: the verdict "Only pinned devices' lookups go through a tunnel", "Everything else -> dnsmasq -> stubby -> the DoT servers [Internet, encrypted (DoT)]" (what the 2026-11-20 measurements found for this default), the router's own line, the watchdogs and the slots' DNS. ROUTER RESOLVER STATUS read true: both resolvers OK, and the files headed "YOUR DEVICES' LOOKUPS", which is right while the internet is the default. The emulator ran the build installed that morning, so the evidence box still said "Merlin has no such rules", which is ID-664's wording, fixed in the tests and not yet on that screen.
```

### ID-665

```text
- ID-665 BUG: ROUTER RESOLVER STATUS's advice when the router's resolver fails because a slot that shares its DNS addresses has stopped, or is up and answering nothing, says "Check the DoT Server List in the web interface, or reboot the router." The cause is that slot, and neither helps. Seen on the emulator on 2026-11-22 with a cut tunnel sharing the DoT addresses (ID-666). Raised 2026-11-22.
  - DoD: when a slot lists an address the router uses, the advice names that slot and says it is stopped or not answering, with a test for each; the other advice is unchanged.
  - Closed 2026-11-22: the resolver check reads each slot that has a server (its region, whether its interface is up, its DNS; read on the router and its output checked), and when one lists an address the router uses, the advice names it in place of "check the DoT Server List or reboot": a running one "lists those servers and is running, so the router's lookups to them go through its tunnel, which may be answering nothing", a stopped one, on Merlin, "isn't running, so the app's guard refuses the router's lookups to them until it is. Start it in MANAGE (ENABLE)". On stock a stopped slot is not named, since its lookups move to another. The addresses are the DoT list while DNS-over-TLS is on and the DNS Server setting while it is off. `resolver_shared_slot_test.dart`, 10 tests; not read on the emulator, whose build predates it and whose reinstall would ask for the router login again.
```

### ID-637

```text
- ID-637 DOC: within the next few days, Andrew posts a clarification reply in his r/PrivateInternetAccess thread "Run PIA on your router: every device protected, at full WireGuard speed". It says his earlier comments about DNS applied to stock firmware only, that Asuswrt-Merlin behaves differently, and that the differences are documented in ROUTER-DNS.md, README.md and ARCHITECTURE.md in the project's GitHub repository.
  - DoD: the reply is posted, and its text, date and the thread's figures are logged in promotion/posts.md.
  - Closed 2026-11-22: Andrew posted the reply in his thread; the text and date are in `promotion/posts.md`. The thread's figures were not read that day, so the DoD's "figures" are not logged.
```

### ID-662

```text
- ID-662 DOC: continuing ID-638, which corrected the article and regenerated its WordPress HTML: Andrew adds a reply under the published post on his blog saying that its DNS section describes stock firmware and that Asuswrt-Merlin differs, instead of editing the post (Andrew, 2026-11-22). The corrected article stays in `promotion/blog` as the source. Raised 2026-11-22.
  - DoD: the reply is posted, and its text and date are logged in `promotion/posts.md`.
  - Closed 2026-11-22: Andrew posted the reply under the published post, and left the post as it was; the text and date are in `promotion/posts.md`.
```

### ID-661

```text
- ID-661 DOC: continuing ID-654, which wrote the hold into the documents and audited the store listings: restructure ROUTER-DNS.md for the firmware split decided in ID-641: sections 5 and 6 into a stock how-to and a Merlin how-to, section 7 into a stock and a Merlin subsection, sections 1 to 4 kept as one concept in the order common statement, On stock, On Merlin, and the README kept short with a pointer for each firmware. Raised 2026-11-22.
  - DoD: the sections split as above, every statement about router behaviour naming its firmware and date (stock's "measured September 2026" or "not measured on stock" until ID-639), and the link and testing-figure tests pass.
  - Closed 2026-11-22: ROUTER-DNS.md is split as above, by moving the text and not rewriting it. Sections 2 to 4 give the common statement, then On stock, then On Merlin (4 has a subsection for each, 3 labels each bullet); section 5 has the settings and the DNS Server advice once, then 5.1 for stock (its table, setup A and setup B) and 5.2 for Merlin (what the default connection decides, and a table of what each setup costs); section 6 is the same on both and stays one; section 7 has 7.1 for stock (the pieces, the router rules, the broken tunnel, pinned devices) and 7.2 for Merlin (the pieces, what the guard adds, pinned and not pinned), then the common DNS services and a read-only command list for each firmware. The `the-router-rules` anchor ARCHITECTURE links to is kept. Two statements were out of date and are corrected: the Merlin cell of setup B's DoT row still said no other slot may use the addresses because the first to start holds them, which stopped being true with the takeover (ID-652), and section 4's Merlin bullet read as if the first-to-start rule still applied. The Merlin pinned-device table in 7.2.3 has only what was measured on 2026-11-20; it makes no claim about TCP, DoT or DoH from a pinned device, which wasn't measured on Merlin. Stock's statements carry the September 2026 date from the opening of section 7, and stay unmeasured on this firmware release until ID-639. README says so with a link for each firmware. `numbered_docs_test.dart` (headings, numbers and contents list) and `dns_map_test.dart` pass.
  - Plan: [plan_dns.md](.claude/plans/plan_dns.md)
```

### ID-643

```text
- ID-643 DOC: the network traffic diagrams list RevenueCat and the Google Play Store but not the Apple App Store, which the iOS app connects to for purchases. Checked 2026-11-21: none of the four SVGs in `images/` or the two generators, `scripts/network-traffic-logical.py` and `scripts/network-traffic-representative.py`, mentions it. Andrew's XDA post (2026-11-21) uses the logical diagram under "What does it connect to?", which says it shows every connection.
  - DoD: both generators draw the App Store connection with its path, the four SVGs are regenerated from them, and ARCHITECTURE.md section 8's numbering and alt text match; the XDA and SNB posts' copies are Andrew's to replace.
  - Closed 2026-11-22: both generators draw it: the box and the pill that said RevenueCat and Google Play now say RevenueCat, Google Play and the App Store (`api.revenuecat.com`, Play Billing and StoreKit), the phone is "Android or iOS", the store listing is no longer "the Play Store listing", and flow 13's row in the table names the Apple App Store; the numbering is unchanged, and ARCHITECTURE 8's alt text doesn't name a store, so it needed nothing. The four SVGs are regenerated, the dark ones with `svg-dark-variant.py`, and the logical one was rendered and read: the new text fits its box and its row. The copies Andrew posted on XDA and SNB are his to replace.
```

### ID-638

```text
- ID-638 DOC: the blog post in `promotion/blog` says that its DNS section describes stock firmware, and that Asuswrt-Merlin behaves differently: with a tunnel as the default connection, devices that aren't pinned send their lookups to the default slot's DNS servers through that tunnel. It points to ROUTER-DNS.md, README.md and ARCHITECTURE.md for the detail. The section already opens "On stock firmware", so the sentence that follows needs a Merlin counterpart, and its diagram (`images/04-dns.png`) shows stock only. Raised 2026-11-20, after Merlin was measured.
  - DoD: `article.md` corrected and `wordpress/article.html` regenerated from it with `make_wordpress.py`, the diagram either marked "stock" or redrawn with Merlin's path, and the published copy updated by Andrew if the post is already live.
  - Partly done 2026-11-22: `promotion/blog/article.md` says after the stock paragraph that Asuswrt-Merlin differs (with a tunnel as the default connection a device that isn't pinned has its lookups sent to that tunnel's DNS servers through the tunnel, and with the internet as the default it behaves as stock does; measured on 388.13 in November 2026, on one router) and points to ROUTER-DNS.md, README.md and ARCHITECTURE.md; the diagram's alt text starts "Stock firmware" and a caption under it says it is stock's and what Merlin does; `wordpress/article.html` is regenerated with `make_wordpress.py` (19,562 characters). The diagram is marked, not redrawn. Remainder: ID-662, Andrew updating the published post.
```

## Stock, and the days before the router can be swapped

Andrew can't run stock for several days, and a swap costs many hours each way, so everything that needs stock goes in one session, ready to paste, and nothing that can be done on Merlin waits for it.

- **Done or doable now, on Merlin and from the records:** the per-firmware model and ID-640's wording; ID-636's hold and its check; the amber note for the slot form; ID-650; the documentation audit. Stock statements ship labelled with the date they were measured (September 2026) or "not measured on stock", and the stock text and its golden tests stay byte for byte as they are.
- **One stock session (ID-639 and the stock halves):** run once, in this order, with each step's expected result written before it is run (CONTEXT.md section 1): (1) devices that aren't pinned, with a tunnel as the default, with the router's DNS Server setting, the DoT list and the slots' DNS all different; (2) the router's own lookups when the slot holding a shared address stops (does it move to the next slot, as September's record says); (3) ID-594's rule at 1010 through a reboot and with the slot stopped; (4) WD-29 on stock (ID-629's stock half); (5) the ROUTER DNS ROUTING and ROUTER RESOLVER STATUS screens read on stock with each default.
- **Claude runs it, not Andrew** (his instruction, 2026-11-22): the sheet is written now in `.claude/testing/` (untracked) with each step's expected result first, and once the router is on stock and Andrew has given permission for that session, Claude runs it over SSH, restores the router and records the results.
- **What changes after it:** if the results match the records, only labels change, in a documentation commit. If not, the model's stock sentences change in a small build.

## One DNS commit (proposed 2026-11-22)

Andrew wants many items in one commit, probably all the DNS changes. Proposed contents, in build order inside the commit:

- ID-641 (the decisions, which fix the layout), then ID-640 (the app's wording, from the per-firmware model if chosen), then ID-636 and ID-594 together (the Merlin leak and what carries the router's own DNS), and the tests that feed the model each firmware's measured outputs.
- Documentation changes that follow from the decisions: ROUTER-DNS.md sections 5 to 7 split by firmware, the README firmware pointer, and the audit in "Not yet audited" (store listings and in-app text first).
- Left out, with reasons: ID-621 (DNS modes) needs ID-639's stock measurements and a design, so it follows in its own commit; ID-639 needs the router on stock; ID-637 and ID-638 are public text, not part of a build, and can go out as soon as Andrew posts them.
- Cost of one large commit: a failure anywhere holds back the Merlin wording fix that the SmallNetBuilder post promised. Mitigation: build ID-640 first and keep it releasable, so the commit can be split at that point if the ID-636/594 design runs long.
- Build 588 (already built) either goes first as its own commit, or is folded in. Andrew decides.

What Claude needs from Andrew before building it is the next section's decisions, plus these:

- Is build 588 its own commit first, or folded in?
- Is ID-621 out of this commit?
- ID-636 and ID-594: the choice of what carries the router's own DNS and what happens when it stops (the guard holds the route, blocks, or lets it fall to the WAN and warns).
- Permission, for that session only, to test on the Merlin router, so the ID-636 hold is seen to fail with the hold removed.
- Whether the stock side may ship on September's measurements, marked as such, until ID-639 is run.

## Decided

- 2026-11-22, Andrew: ID-636 and ID-594's fallback is to black hole. While a slot that holds a shared DNS address is stopped, the router's own lookups to that address are refused, not sent over the WAN. Costs: on Merlin, devices that follow dnsmasq lose name lookups while that slot is down, if the router's DNS shares an address with it; the app's text says so. Read from the code the same day: the guard (`merlin_guard.dart`) already restores rules at boot and at each tunnel start, and `check-claims.sh` has the pattern for a check seen to fail (stop a tunnel, read `ip route get`, expect refused).

- 2026-11-22, Andrew, the rest of ID-641 (closed in build 588's block): how-to guidance split by firmware, concepts together (ID-654); the per-firmware DNS model built in ID-640; Merlin designed first and stock after ID-639; one commit for the DNS work with the second-slot takeover included (ID-652) and option 3 for rebuilds (ID-653); the measurement rule added to CONTEXT.md section 1. The statement rule was added as well, later the same day: a statement about router behaviour names the firmware and the date, and is read as stock's when it names none. Hold on by default once the guard runs, with no setting to turn it off. Other Merlin versions and dual WAN will not be measured. ID-594 moved to Next Release.

## Decisions for Andrew (answered 2026-11-22, kept for the record)

1. Split the how-to guidance by firmware as above, keep the concepts together, or choose another layout?
2. Build the per-firmware DNS model, and should ID-640 be the item that builds it?
3. Adopt the measurement rule and the CONTEXT.md rule?
4. Should ID-636's hold, ID-594 and ID-621 be designed for each firmware before any of them is built?
5. What order, and when? A suggestion: decide 1 to 4, then ID-640 with the model, then ID-636 and ID-594 together, then ID-639 on stock.

## Changed on 2026-11-20 (released in build 587)

ROUTER-DNS.md, README.md, ARCHITECTURE.md, CHANGELOG.md (ID-632, ID-635 and ID-642 closed in build 587), BACKLOG.md (ID-636 to ID-641 added), CHANGE-PROCESS.md and its tests, `test/unit/dns_map_test.dart`, this plan (renamed from `plan_firmware-split.md`) and the two older DNS plans' links up to it, CLAUDE.md, .claude/CONTEXT.md and a few pointers. No router setting was left changed; the router was restored after each test.
