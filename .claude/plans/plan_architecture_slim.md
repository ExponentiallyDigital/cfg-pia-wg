# ARCHITECTURE.md slim-down - brief

Hand this to the session that does the work. It is the second pass on this document: the first, `plan_architecture_rewrite.md`, restructured it in build 430, and its agreed decisions still stand (see "Carried forward").

**When:** after build 447 is hardware-tested and released. The work changes no code and must not compete with a release.

---

## Why

The document has drifted, and it overlaps a second document that drifts with it.

- `ARCHITECTURE.md`: 1,568 lines, 121 KB. Device assignment is about 480 lines and the watchdog about 380. It holds 31 dated measurements, 9 retracted or superseded markers, and an appendix of superseded readings.
- `.claude/CONTEXT.md`: 106 KB, and much of it restates `ARCHITECTURE.md`.
- Drift found on 2026-09-14: "a downed default tunnel takes DNS with it" had spread to README, ARCHITECTURE, CONTEXT and a script comment, and hardware showed it to be wrong. Nothing flagged it, because the claim carried no evidence and no code depended on it.

## Goal

Slim, current, and trustworthy enough that both Andrew and Claude can work from it.

**Success tests** - all four must hold:

1. When ASUS changes VPN Fusion or WireGuard handling in a firmware update, the impact on this app can be worked out from this document alone. (The build 430 test, kept.)
2. Every factual claim says whether it was **measured** (with date) or **inferred**.
3. Every claim the code depends on names the code: a file, and a symbol where there is one.
4. No hardware-won fact is lost. Superseded material is archived, not deleted.

---

## Carried forward from `plan_architecture_rewrite.md` (agreed)

- **Retract in place.** A wrong idea keeps a one-line retraction where a reader would naturally have it, pointing to the full story in the archive. Moving every retraction out of sight invites rediscovering and re-adopting it (CONTEXT working agreement).
- **The firmware dependency register is the core of the document.** It lists every assumption about the firmware, how each was measured, and what breaks if it changes. Everything else in ARCHITECTURE explains an entry in the register.

## Ownership - decide first, write second

Two overlapping documents drift against each other, so each subject gets exactly one home. The other document points to it, never restates it.

| Subject | Home |
|---|---|
| Firmware facts and contracts: NVRAM layouts, service call sequences, `ip rule` and iptables behaviour, file paths on the router, measured quirks | `ARCHITECTURE.md` |
| The firmware dependency register | `ARCHITECTURE.md` |
| How the app's code is organised, file map, navigation, working agreements, house style | `.claude/CONTEXT.md` |
| What changed and when, and why a decision was taken | `CHANGELOG.md` |
| Superseded readings and the long story behind retractions | New `ARCHITECTURE_HISTORY.md` at the repo root |
| Manual test steps | `TESTING.md` (out of scope except links) |

The proposed ownership table is Andrew's call. Confirm it at checkpoint 1 before moving anything.

---

## Non-negotiables

1. **Lose nothing silently.** Every measured fact ends up in the new document, in the archive, or on a drop list with a reason Andrew approves.
2. **Where the document and the code disagree, flag it and don't resolve it.** Either could be the wrong one. List each mismatch as a question.
3. **No real network identifiers, and no router model numbers.** `test/unit/no_lan_identifiers_test.dart` guards this, but write invented values from the start: `192.168.1.x`, `AA:BB:CC:DD:EE:FF`, `my-router.asuscomm.com`. PIA region names are fine. Quad9 and Cloudflare public resolver addresses are fine.
4. **Links stay intact** - see "Incoming references".
5. **Don't line-wrap Markdown.** One paragraph is one line.
6. **Don't change any code.** Only comments that quote an ARCHITECTURE section name may change, and only to follow a rename.

---

## Method

Keep working files under `.claude/plans/`, so a long session survives context summarisation.

### Step 1 - Fact inventory

Create `.claude/plans/architecture_fact_inventory.md`: one row per factual claim in `ARCHITECTURE.md`, plus any CONTEXT claim that duplicates one.

| ID | Claim (one line) | Evidence | Current section | Code that depends on it | Destination |
|---|---|---|---|---|---|
| F001 | `vpnc_unit` is the 0-based row of the slot's `vpnc_clientlist` record, not `5 - slot` | measured 2026-09-0x | 4.2.2 | `lib/router_slot_service.dart` `vpncUnitForSlot` | keep |

- **Evidence** is `measured <date>`, `inferred`, or `unknown`. Don't upgrade inferred to measured.
- **Destination** is `keep`, `archive`, or `drop: <reason>`.

### Step 2 - Code cross-check

For every command string, NVRAM key, service call, file path, rule priority and sequence in the inventory, search `lib/` (and the router script template in `lib/router_watchdog.dart`). Record mismatches in a "Questions" section of the inventory: what the document says, what the code does, and where. Don't fix either side.

**Checkpoint 1 - Andrew:** confirm the ownership table and answer the mismatch questions.

### Step 3 - Outline

Propose the new heading structure, with the dependency register first after a short overview. For each heading: what it holds, which inventory IDs land there, and its approximate length. As a guide, not a rule, aim to roughly halve the document by moving history out and CONTEXT duplication to a single home.

**Checkpoint 2 - Andrew:** approve the outline.

### Step 4 - Write

- `ARCHITECTURE.md`: current behaviour only. Each claim carries its evidence tag inline, for example `(measured 2026-09-14)` or `(inferred)`, and names its code where one exists.
- `ARCHITECTURE_HISTORY.md`: superseded readings and retraction stories, each linked back from its one-line retraction.
- `.claude/CONTEXT.md`: replace duplicated firmware detail with pointers to the owning section. Leave everything else as it is.

### Step 5 - Audit

- Every inventory row has a destination, and every `keep` row appears in the new text. List any that don't.
- Every mismatch from Step 2 is either answered and applied, or recorded as still open.
- Run `flutter test`. The two guards that matter here are `markdown_links_test.dart` (every link between the repo's Markdown files resolves; `.claude/plans` and `.claude/testing` are skipped) and `no_lan_identifiers_test.dart`.

**Checkpoint 3 - Andrew:** review the audit, then the diff.

### Step 6 - Commit

One commit on `dev`, pushed with `git push origin dev` (it pushes to GitHub and the NAS). Add a `DOC:` bullet at the top of the open CHANGELOG block.

---

## Incoming references (measured 2026-09-14)

`markdown_links_test.dart` catches Markdown link breaks. **Nothing checks section names quoted in code and test comments.** Any heading that one of these names points to must keep its wording, or every citing comment must be updated in the same commit.

**Quoted section names** (count of citations):

| Name | Count |
|---|---|
| `vpnc_dev_policy_list - the assignment` | 7 |
| `Stop/Disable` | 4 |
| `curl refuses to run from cron` | 3 |
| `Field reference` | 3 |
| `The router's service queue, and how it wedges` | 2 |
| `Stock vpnc_clientlist` | 2 |
| `Stock` | 2 |
| `The second init script` | 1 |
| `Stock leaves the old routing rule behind` | 1 |
| `Enable existing slot` | 1 |
| `Device assignment (stock)` | 1 |

Re-run the search before Step 6, since this list will have moved:

```sh
git grep -hoE 'ARCHITECTURE\.md[ ,]*"[^"]+"' -- . ':!CHANGELOG.md' | sort | uniq -c | sort -nr
```

**Anchors** linked from other documents: `#usb-storage-for-download-master`, `#the-three-numbers-that-name-one-profile`, `#the-routers-service-queue-and-how-it-wedges`, `#stock-vpnc-clientlist`, `#stock-leaves-the-old-routing-rule-behind-measure`, `#router-wireguard-nvram-fields`, `#field-reference`, `#device-assignment-stock`, `#curl-refuses-to-run-from-cron`. The link test covers these, but renaming them means editing the linking documents too.

**Files citing ARCHITECTURE** (outside CHANGELOG and plans): `.claude/CONTEXT.md` (17), `lib/router_slot_service.dart` (6), `TESTING.md` (6), `lib/router_watchdog.dart` (4), `lib/device_assignment_service.dart` (3), `README.md` (3), `lib/device_assignment.dart` (2), four test files (2 each), and one each in `lib/widgets/device_assignment_screen.dart`, `lib/screens/slot_params_editor.dart`, `lib/s50_template.dart`, `lib/binary_installer.dart`, `play-store/description.md`, `BACKLOG.md` and two more tests.

---

## Material the new document must absorb

These are measured after the last restructure and sit in BACKLOG or the artifact, not in ARCHITECTURE:

- **The router's own DNS path** (BACKLOG 1.1.2, "the router's own DNS follows the first tunnel, not the default connection"):
  - dnsmasq sends everything to stubby, and stubby does DNS-over-TLS to the servers in `dnspriv_rulelist`.
  - The firmware adds a per-tunnel `from all to <slot DNS> iif lo` rule, and the lowest table wins.
  - Assigned devices are DNAT'd to the first slot DNS server over UDP 53.
  - Router-originated lookups use `/etc/resolv.conf`, with the WAN's DNS first.
  - These are firmware dependencies, so they belong in the register.
- **Stock `CREATE` over an enabled slot** leaves the old tunnel running unless it is stopped first (2026-09-14).
- **A watchdog deploy run does not rebuild a tunnel with a recent handshake,** so a region change needs the slot cleared (2026-09-14).

## Out of scope

- Rewriting README or TESTING (their links are in scope).
- Any code change beyond comment renames.
- Resolving mismatches between document and code without Andrew's answer.
