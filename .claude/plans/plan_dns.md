# Plan: DNS across stock and Merlin (ID-641)

The one place to see the DNS work items together, and the findings, reasoning and recommendations from 2026-11-20, for Andrew to review and decide on. Status lives in each item's `Now:` line in BACKLOG.md or CHANGELOG.md, never here. Nothing in this plan has been built or decided.

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
   - The corrected documents are uncommitted, so any post that links to them points at the old text until they are committed (see "Public communication"). Andrew was also considering a SmallNetBuilder forum post on 2026-11-20.
   - ID-637, the Reddit clarification, is due within days of 2026-11-20. Claude drafts it in Andrew's voice, and Andrew posts it and gives Claude the exact text and the thread's figures, which go in `promotion/posts.md`.
   - Whether to commit build 587. The tests passed on 2026-11-20 (2374 tests, 95.88% coverage) and nothing is committed. Claude commits only when Andrew says, with the steps in `CHANGE-PROCESS.md` section 8: the block's summary replaces `in progress`, a ```` ```play ```` note is written (the block has none), the subject is `v0.8.217 build 587 - <summary>` with no trailer, then build 588's block is opened and `pubspec.yaml` bumped. Which of the uncommitted files belong is Andrew's call: `.claude/plans/plan_rearchitect-cicd.md`, the README line he changed himself, and `promotion/posts.md` were not written for this work.
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

- The corrections to ROUTER-DNS.md, README and ARCHITECTURE are uncommitted. A post that links to them (ID-637's Reddit reply, the blog, or a forum post) points readers at the old text on `main` until they are committed and released, or at the `dev` branch once it is pushed. Commit first, or word the post so it doesn't depend on the links.
- Andrew was considering a post on the SmallNetBuilder forums (where Merlin users are) on 2026-11-20. That audience is the one affected. A post there could also ask Merlin users to report what their routers do on other Merlin versions and models, which is the main thing not measured. No item exists for it yet; ID-637's pattern (what it says, DoD: posted and logged in `promotion/posts.md`) would fit. The stock boot hook is never mentioned in outward text, and nothing from the router's addresses or device names goes in a post.

## Decisions for Andrew

1. Split the how-to guidance by firmware as above, keep the concepts together, or choose another layout?
2. Build the per-firmware DNS model, and should ID-640 be the item that builds it?
3. Adopt the measurement rule and the CONTEXT.md rule?
4. Should ID-636's hold, ID-594 and ID-621 be designed for each firmware before any of them is built?
5. What order, and when? A suggestion: decide 1 to 4, then ID-640 with the model, then ID-636 and ID-594 together, then ID-639 on stock.

## Changed on 2026-11-20 (uncommitted)

ROUTER-DNS.md, README.md, ARCHITECTURE.md, CHANGELOG.md (ID-632, ID-635 and ID-642 closed in build 587), BACKLOG.md (ID-636 to ID-641 added), CHANGE-PROCESS.md and its tests, `test/unit/dns_map_test.dart`, this plan (renamed from `plan_firmware-split.md`) and the two older DNS plans' links up to it, CLAUDE.md, .claude/CONTEXT.md and a few pointers. No router setting was left changed; the router was restored after each test.
