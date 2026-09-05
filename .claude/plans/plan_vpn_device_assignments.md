# in-app device assignment to VPN slots

Implement a "kill switch" like function in stock firmware (with Merlin this is managed by VPN Director, keeping out of scope - VPN assignments will only be done in our app on stock firmware).

Purpose: this functionality allows the user to see a list of LAN devices and choose which VPN each will use. Where unassigned, a default VPN will be used. The default VPN is goverened by the nvram entry `vpnc_default_wan`.

To support this:

1. CHG: menu changes
   - "Generate PIA WireGuard config" rename to "Standalone PIA WireGuard config".
   - "Manage PIA WireGuard config" no change.
   - "Watchdog Wireguard management" no change.
   - "VPN device assignment+" **<- new entry with a superscript `2` at the end of the line**.
   - "View app log" no change.
   - "Exit app" no change.
   - Add text "superscript`2` stock firmware only" to appear underneath the home screen line "* requires ssh connectivity to an ASUS router"
   - Alter "* requires ssh connectivity to an ASUS router" to be  "superscript`1` requires ssh connectivity to an ASUS router"
2. ADD: additional menu item "VPN device assignment" functionality is
   - get the device names from nvram via "nvram get custom_clientlist" & allow devices to be assigned to VPN slots.
   - select a device the slot applies to
   - "apply to all devices" option - this is managed by nvram setting `vpnc_default_wan=9`
   - sets XX then run "service restart_default_wan"
3. nvram format
   1. nvram setting `vpnc_default_wan` stores a integer which represents `vpnc_clientlist``'s field 6 (0 based) aka `vpnc_idx` per `ARCHITECTURE.md` "3.2. Stock `vpnc_clientlist`". For example, with the following we can determine that the pia-aus_melbourne

      ```text
      vpnc_default_wan=9
      vpnc_clientlist=pia-aus_melbourne>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg
      ```

   2. sample `custom_clientlist` contents
      hostname1>00:01:02:03:04:05>0>4>>>>><hostname2>05:04:03:02:01:00>0>60>>>>><hostname3>AA:BB:CC:DD:EE:FF>0>60>>>>><hostname4>FF:F0:E0:D0:C0:B0>0>9>>>>>

   3. sample `dhcp_staticlist` contents
      <00:01:02:03:04:05>192.168.1.2>><05:04:03:02:01:00>192.168.1.30>>hostname2<FF:F0:E0:D0:C0:B0>192.168.1.40>>hostname5<A0:AD:7F:23:A1:57>192.168.1.60>>hostname6

4. update ARCHITECTURE.md, add a section called "3.3" per the below:

`dhcp_staticlist` and `custom_clientlist` are both single nvram strings using `<` as the record separator and `>` as the field separator. Values are stored percent-encoded (the web UI runs `decodeURIComponent()` on read), so names containing `<`, `>` or spaces come back escaped.

## dhcp_staticlist

Four fields per record, always with a leading `<`:

```
<MAC>IP>DNS>Hostname
```

| Idx | Field | Notes |
| ---: | --- | --- |
| 0 | MAC      | Uppercase, colon separated                      |
| 1 | IP       | The reserved lease                              |
| 2 | DNS      | Per client DNS server, empty for most entries   |
| 3 | Hostname | Optional, pushed into dnsmasq as the lease name |

Trailing fields are treated as empty if absent, so `<MAC>IP` alone is still valid and the UI will fill in `""` for DNS and hostname. Worth knowing if you script this: on 384.13 through the 386 branch, ASUS and Merlin briefly split hostnames out into a separate `dhcp_hostnames` variable (`<MAC>hostname`). Your firmware is clearly on the reunified four field layout, but any older script you find on the forums may assume the split.

## custom_clientlist

Up to nine fields per record. The first record has no leading `<`, so split on `<` and discard empty chunks rather than assuming index 0 is junk:

```
Name>MAC>Group>Type>Callback>Keeparp>AppGroup>AppAge>AppGroupID
```

| Idx | Field | Notes |
| ---: | --- | --- |
| 0 | Name       | User assigned display name                                   |
| 1 | MAC        | Uppercase                                                    |
| 2 | Group      | Always written as `0` by the UI                              |
| 3 | Type       | Icon index into the device type list in `client_function.js` |
| 4 | Callback   | ROG device property, preserved on edit, otherwise empty      |
| 5 | Keeparp    | ROG device property, preserved on edit, otherwise empty      |
| 6 | AppGroup   | Parental controls / app tags, empty unless used              |
| 7 | AppAge     | Parental controls / app tags, empty unless used              |
| 8 | AppGroupID | Parental controls / app tags, empty unless used              |

The five trailing `>` on every record are the empty fields 4 through 8. The UI writes them unconditionally. Group type `0` means unknown and gives a generic icon.

Two practical notes. The two lists are independent, so a MAC can appear in one and not the other, and a rename in `custom_clientlist` does not change the DHCP hostname. Both live in nvram with a hard size ceiling, so after `nvram set` you need `nvram commit`, and a silently truncated write is the usual failure mode when the list gets long.

Sources:
- [Advanced_DHCP_Content.asp, asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/www/Advanced_DHCP_Content.asp)
- [client_function.js, asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/www/client_function.js)
- [rc: Split static lease hostnames into their own nvram](https://github.com/RMerl/asuswrt-merlin.ng/commit/5e862e3aed685260b4fd66e744cf823b52f485da)
- [Script to update the Client List from the arp table, SNBForums](https://www.snbforums.com/threads/script-to-update-the-client-list-from-the-arp-table.95676/)

---

## Review notes 2026-09-05 (Claude) — read before writing code

The `dhcp_staticlist` / `custom_clientlist` research above is the hard part and it is done. What
follows is what a review turned up: one correctness trap, one hole where the core data model should
be, and a handful of smaller things.

### 1. BLOCKER: the plan never says where a device-to-VPN assignment is stored

Section 3.1 covers `vpnc_default_wan` — the **default** for unassigned devices — and section 3.2
covers `custom_clientlist`, which is the device *name and icon* list. Neither holds "device X uses
VPN Y". That mapping is the feature, and no key in this plan carries it.

`custom_clientlist` almost certainly does not: its nine fields are name, MAC, group, icon type and
five parental-control slots, all accounted for in the table above. So VPN Fusion is keeping the
binding somewhere else, and section 2's `sets XX then run "service restart_default_wan"` is an
`XX`-shaped hole in exactly that place.

**Find it before designing anything else**, with the same before/after diff that settled
`vpnc_unit`:

```sh
nvram show 2>/dev/null | sort > /tmp/nv.before
# In the WebUI: VPN Fusion -> assign ONE named device to ONE VPN profile -> Apply
nvram show 2>/dev/null | sort > /tmp/nv.after
diff /tmp/nv.before /tmp/nv.after
```

Then repeat for: a second device on the same profile, a device moved to a different profile, a
device unassigned again, and "apply to all devices" on and off. Five diffs will give the whole
schema, including whether assignments are per-profile lists or one global list, and what
`vpnc_default_wan=0` means (presumably plain WAN, but confirm rather than assume — `clearall.sh`
sets it to `0` on that assumption today).

Everything downstream — the UI, the data model, the write path — depends on the answer, so this is
the one task that has to come first.

### 2. Field numbering: this plan and ARCHITECTURE.md disagree, on the same word

Section 3.1 says `vpnc_default_wan` holds **"field 6 (0 based)"**, and for the worked example that
is correct: index 6 of that record is `9`.

But `ARCHITECTURE.md` numbers the same record **1-based**, so it calls that same field **"field 7"**
(section 3.2), and it uses **"field 6"** to mean the *active* flag (sections 4.2.2 and 4.2.3) — which
is index **5** in this plan's counting. Two documents, the same phrase, two different fields.

The code is 0-based (`_activeIdx = 5`, `_iptablesIdx = 6` in `router_slot_service.dart`), but its own
doc comment on `vpncStateIndex` says "Field 7", so the confusion is already inside the codebase.

**Proposal:** say `index N (0-based)` everywhere and never the bare word "field", in this plan,
in ARCHITECTURE.md and in the code comments. The existing `VpncRecord` constants are the reference:

| Constant | Index | Holds | ARCHITECTURE.md calls it |
| --- | ---: | --- | --- |
| `_descIdx` | 0 | description / region | field 1 |
| `_slotIdx` | 2 | slot number | field 3 |
| `_activeIdx` | 5 | active flag | field 6 |
| `_iptablesIdx` | 6 | the `vpncN_*` state index | field 7 |

Getting this wrong writes the active flag where the state index belongs, which would disable a
tunnel while appearing to assign a device to it.

### 3. `custom_clientlist` is not the full device list

The sample data in section 3 shows the problem: `hostname4` appears in `custom_clientlist` but not
in `dhcp_staticlist`, and `hostname5` / `hostname6` are the other way round. `custom_clientlist`
holds devices the user has *named or customised* in the WebUI; a device that has simply joined the
network may be in neither list.

A user who cannot see their laptop in the list will call the feature broken, so decide the source
of truth before building the UI. Options, roughly in order of completeness:

- `custom_clientlist` alone — simplest, and matches what the WebUI's own VPN Fusion picker shows
- merged with `dhcp_staticlist` on MAC — adds reserved-lease devices, still misses transient ones
- plus the ARP table (`ip neigh` / `arp -a`) — catches everything currently connected, at the cost
  of showing devices with no friendly name

Whichever is chosen, the MAC is the join key and the only stable identifier; hostnames are not
unique and are user-editable in one list without changing the other.

### 4. Values are percent-encoded and nothing in the app decodes them yet

Section 4's note that the WebUI runs `decodeURIComponent()` on read matters for us: a device named
`Andrew's iPad` or `Study TV` comes back escaped. `parseVpncClientlist` does no decoding today
because our own descriptions never needed it. A device-name parser will, both ways — decode for
display, re-encode on write, and round-trip a name the app did not create without corrupting it.

### 5. The truncation risk deserves the same treatment the script writes got

Section 4's closing note — "a silently truncated write is the usual failure mode when the list gets
long" — is exactly the failure `_writeFile` already guards against for the watchdog script, by
comparing `wc -c` against the expected byte count and throwing. Any write to `custom_clientlist`
or the assignment key should read the value back and compare before reporting success. Silently
half-writing a user's device list would be the worst bug this feature could have.

### 6. Say why this is worth doing, in the plan

The opening line calls it "a kill switch like function", which undersells it and is worth stating
precisely, because it is the justification for the whole feature: **on stock there is no
`wgcN_enforce`**, so a dropped tunnel means traffic silently reaching the internet unprotected.
Observed on hardware (2026-09-05): with a tunnel set to "apply to all devices", taking the tunnel
down cost the assigned devices their connectivity — that is fail-closed behaviour, and it is the
nearest thing stock has to Merlin's kill switch.

Two things follow:

- `ARCHITECTURE.md` section 5.1.2 already carries a note to revisit the stock kill-switch wording in
  alert emails once this lands. Today a stock failure email says *"not supported on this firmware -
  traffic is reaching the internet without the VPN"*. Once devices are assigned, the truer sentence
  is that those devices lost connectivity, which is better news and should be said.
- `_kKillSwitchStock` in `router_watchdog.dart` is where that wording lives.

### 7. Menu and home-screen details

- The new entry needs **both** markers, not just `²`: it requires SSH connectivity *and* stock
  firmware. So `VPN device assignment¹ ²` with the existing `* -> ¹` renumbering.
- This makes six primary buttons plus two footnote lines and two footer links, on a screen that
  already needs a `Spacer` to fit. Worth checking on the smallest supported screen before
  committing to a sixth button — a submenu under Manage is the fallback.
- `test/screens/main_menu_screen_test.dart` asserts "main menu shows five entries"; it will need
  updating, and the drawer (`AppDestination`) gains a destination too.
- Renaming "Generate PIA WireGuard config" to "Standalone PIA WireGuard config" touches
  `AppDestination.standalone.title`, the README walkthrough, and the screenshots.

### 8. Freemium interaction

`BACKLOG.md` 1.2 puts everything except config generation behind the lifetime unlock. Device
assignment is a router-management feature, so on that rule it is paid — worth deciding explicitly
now, because it changes where the paywall check goes and it is a much easier decision before the
UI exists than after.
