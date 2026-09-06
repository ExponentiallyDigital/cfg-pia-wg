# Plan: in-app device assignment to VPN slots

**Status:** DRAFT. **Phase 0 is complete** - the schema and the service calls were confirmed on hardware 2026-09-06 and are written up in 3.3.6. Phase 2 is designable. Backlog item: `BACKLOG.md` 1.1 "ADD: in-app device assignment to VPN". Not current state - see `.claude/CONTEXT.md` for that.

> [!NOTE]
> Every IP address, hostname and MAC address in this document is invented, including in the sample NVRAM records. Real values from the maintainer's LAN are never recorded in this repository - see the working agreement in `.claude/CONTEXT.md`. Do not replace them with observed values when confirming the schema.

Sequenced so that phase 1 is written as the finished text for `ARCHITECTURE.md` section 3.3 and can be copied there verbatim once the schema is confirmed.

---

## Purpose

Let the user see their LAN devices and choose which VPN each one uses. Unassigned devices fall back to a default VPN, governed by `vpnc_default_wan`.

**Stock firmware only.** Merlin does this through VPN Director, which is out of scope - the app will not touch device assignment there.

### Why it matters more than it looks

Stock has no `wgcN_enforce`, so there is no kill switch: when a tunnel drops, traffic silently continues over the plain WAN. Device assignment is the nearest thing stock has to one.

Observed on hardware 2026-09-05: with a tunnel set to "apply to all devices", taking that tunnel down cost the assigned devices their internet connectivity. That is **fail-closed** behaviour, and it is the justification for the whole feature.

Two consequences to carry through:

- `ARCHITECTURE.md` section 5.1.2 already carries a note to revisit the stock kill-switch wording in alert emails once this lands. A stock failure email currently says *"not supported on this firmware - traffic is reaching the internet without the VPN"*. Once devices are assigned, the truer and better sentence is that those devices lost connectivity.
- The wording lives in `_kKillSwitchStock` in `router_watchdog.dart`.

---

## Phase 0 - BLOCKER: find where an assignment is stored

Nothing else can be designed until this is answered.

`vpnc_default_wan` holds the **default** for unassigned devices. `custom_clientlist` is the device *name and icon* list - all nine of its fields are accounted for below, and none of them is a VPN. So VPN Fusion keeps the device-to-VPN binding somewhere this plan has not yet identified, and that binding is the feature.

Find it the way `vpnc_unit` was found - change one thing in the WebUI and diff NVRAM:

```sh
nvram show 2>/dev/null | sort > /tmp/nv.before
# WebUI: VPN Fusion -> assign ONE named device to ONE VPN profile -> Apply
nvram show 2>/dev/null | sort > /tmp/nv.after
diff /tmp/nv.before /tmp/nv.after
```

Repeat for each of these, keeping the diffs:

| # | Change in the WebUI | What it should reveal |
| --- | --- | --- |
| 1 | Assign one device to one profile | The key, and its record format |
| 2 | Assign a second device to the **same** profile | Whether it is one list or one key per profile |
| 3 | Move a device to a **different** profile | How a binding is rewritten rather than appended |
| 4 | Unassign the device | How a binding is removed - empty field, or record dropped |
| 5 | "Apply to all devices" on, then off | What `vpnc_default_wan` becomes, and whether per-device bindings survive |

Also confirm, in the same session:

- What `vpnc_default_wan=0` means. `clearall.sh` sets it to `0` today on the assumption that it means "plain WAN, no VPN" - assumed, never verified.
- Which `service` call applies a change. The 2026-09-06 router log shows the WebUI issuing `restart_vpnc_dev_policy` and `restart_default_wan` together, four times over, which suggests `restart_vpnc_dev_policy` is the one that matters for per-device policy:

  ```text
  Sep  6 09:18:03 rc_service: httpds 1319:notify_rc restart_default_wan
  Sep  6 09:18:03 rc_service: httpds 1319:notify_rc restart_vpnc_dev_policy
  ```

**Deliverable of phase 0:** the key name, its record and index layout, and the service call. The device-list half of phase 0 is already answered (see 2.1); this is the remaining blocker, and the write path depends on it.

`scripts/probe-device-assignment.sh` runs the whole sequence: it snapshots NVRAM **and** `/jffs/nmp_cl_json.js` either side of each action, uses two control steps to work out which keys are just clock and enable/disable churn, suppresses those from the summary, and captures the `rc_service` lines so the service call names itself.

---

## Phase 1 - NVRAM reference (destined for `ARCHITECTURE.md` section 3.3)

Written as finished documentation. When phase 0 lands, add the assignment key here and copy the whole section across.

> [!IMPORTANT]
> **Numbering.** Records are counted **0-based** and the word is `index`, never `field` - settled in 409 and now a working agreement in `.claude/CONTEXT.md`. Slot numbers are unaffected and stay `wgc1`..`wgc5`.
>
> | Constant | Index | Holds |
> | --- | ---: | --- |
> | `_descIdx` | 0 | description / region |
> | `_slotIdx` | 2 | slot number |
> | `_activeIdx` | 5 | active flag |
> | `_iptablesIdx` | 6 | the `vpncN_*` state index |
>
> Getting this wrong writes the active flag where the state index belongs, which disables a tunnel while appearing to assign a device to it.

### 3.3.1 `vpnc_default_wan`

An integer naming the VPN that unassigned devices use. It is **index 6 (0-based)** of that profile's `vpnc_clientlist` record - the same number the `vpncN_*` runtime keys are indexed by, not the slot number and not `vpnc_unit`.

```text
vpnc_default_wan=9
vpnc_clientlist=pia-aus_melbourne>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg
                                                            ^ index 6 = 9
```

So `vpnc_default_wan=9` means slot 1, `pia-aus_melbourne`. Confirm what `0` means (phase 0).

### 3.3.2 Shared format

`dhcp_staticlist` and `custom_clientlist` are both single NVRAM strings using `<` as the record separator and `>` as the field separator. Values are stored **percent-encoded** - the WebUI runs `decodeURIComponent()` on read - so names containing `<`, `>` or spaces come back escaped.

### 3.3.3 `dhcp_staticlist`

Four fields per record, always with a leading `<`:

```text
<MAC>IP>DNS>Hostname
```

| Idx | Field | Notes |
| ---: | --- | --- |
| 0 | MAC | Uppercase, colon separated |
| 1 | IP | The reserved lease |
| 2 | DNS | Per client DNS server, empty for most entries |
| 3 | Hostname | Optional, pushed into dnsmasq as the lease name |

Sample:

```text
<00:01:02:03:04:05>192.168.1.2>><05:04:03:02:01:00>192.168.1.30>>hostname2<FF:F0:E0:D0:C0:B0>192.168.1.40>>hostname5<0A:0B:0C:0D:0E:0F>192.168.1.60>>hostname6
```

Trailing fields are treated as empty if absent, so `<MAC>IP` alone is valid and the UI fills in `""` for DNS and hostname.

> [!NOTE]
> On 384.13 through the 386 branch, ASUS and Merlin briefly split hostnames into a separate `dhcp_hostnames` variable (`<MAC>hostname`). Current firmware is back on the reunified four-field layout, but any older script found on the forums may assume the split.

### 3.3.4 `custom_clientlist`

Up to nine fields per record. The **first record has no leading `<`**, so split on `<` and discard empty chunks rather than assuming index 0 is junk:

```text
Name>MAC>Group>Type>Callback>Keeparp>AppGroup>AppAge>AppGroupID
```

| Idx | Field | Notes |
| ---: | --- | --- |
| 0 | Name | User assigned display name |
| 1 | MAC | Uppercase |
| 2 | Group | Always written as `0` by the UI |
| 3 | Type | Icon index into the device type list in `client_function.js` |
| 4 | Callback | ROG device property, preserved on edit, otherwise empty |
| 5 | Keeparp | ROG device property, preserved on edit, otherwise empty |
| 6 | AppGroup | Parental controls / app tags, empty unless used |
| 7 | AppAge | Parental controls / app tags, empty unless used |
| 8 | AppGroupID | Parental controls / app tags, empty unless used |

Sample:

```text
hostname1>00:01:02:03:04:05>0>4>>>>><hostname2>05:04:03:02:01:00>0>60>>>>><hostname3>AA:BB:CC:DD:EE:FF>0>60>>>>><hostname4>FF:F0:E0:D0:C0:B0>0>9>>>>>
```

The five trailing `>` on every record are the empty indexes 4 through 8; the UI writes them unconditionally. Group type `0` means unknown and gives a generic icon.

### 3.3.5 Practical notes

- **The two lists are independent.** A MAC can appear in one and not the other, and renaming in `custom_clientlist` does not change the DHCP hostname. The sample data above shows it both ways: `hostname4` is only in `custom_clientlist`, `hostname5` and `hostname6` only in `dhcp_staticlist`.
- **MAC is the only stable identifier.** Hostnames are not unique and are editable in one list without changing the other.
- **NVRAM has a hard size ceiling.** After `nvram set` you need `nvram commit`, and a silently truncated write is the usual failure mode once a list gets long.

### 3.3.6 `vpnc_dev_policy_list` - the assignment

**SETTLED 2026-09-06** by `scripts/probe-device-assignment.sh`: eight WebUI actions, each diffed against a snapshot either side, with two control steps supplying the noise set. Records separated by `<`, indexes by `>`.

```text
enabled>IP>?>vpnc_idx>
```

| Idx | Field | Notes |
| ---: | --- | --- |
| 0 | enabled | `1` on every record observed. An unassigned device is **absent from the list**, not present with `0`. |
| 1 | **IP address** | the device LAN IP - **not its MAC** |
| 2 | ? | empty on every record observed, purpose still unknown |
| 3 | vpnc_idx | **index 6 of the target profile `vpnc_clientlist` record** - not the slot number, and not the row index |
| 4 | - | trailing empty, written unconditionally |

Worked example. Two profiles, wgc1 at clientlist index 6 = `9` and wgc5 at index 6 = `5`:

```text
vpnc_clientlist=pia-aus_melbourne>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg<pia-aus_perth>WireGuard>5>>password>0>5>>>0>0>cfg-pia-wg
vpnc_dev_policy_list=1>192.168.1.20>>9><1>192.168.1.22>>5>
```

`192.168.1.20` is on wgc1 and `192.168.1.22` is on wgc5. **Index 3 is the third of the three indexes a profile carries** - alongside the slot number and the clientlist row (`vpnc_unit`) - so resolving it needs the clientlist read first. Getting it wrong assigns the device to a different tunnel, or to one that does not exist.

#### How a change is written

| Action | Before | After |
| --- | --- | --- |
| Assign one device | *(empty)* | `1>192.168.1.20>>5>` |
| Assign a second to the same tunnel | `1>192.168.1.20>>5>` | `1>192.168.1.20>>5><1>192.168.1.21>>5>` |
| **Move** `.20` from wgc5 to wgc1 | `1>192.168.1.20>>5><1>192.168.1.21>>5>` | `1>192.168.1.21>>5><1>192.168.1.20>>9>` |
| Unassign `.21` | `1>192.168.1.21>>5><1>192.168.1.20>>9>` | `1>192.168.1.20>>9>` |

> [!IMPORTANT]
> **A move is a delete plus an append, not an edit in place.** Record order is not stable across a change, so the app must rebuild the whole list from its own model and write it in one go, keyed on IP. Any code that patches the string positionally, or assumes a device keeps its index, will corrupt the list the first time a user moves a device.

#### `vpnc_dev_policy_list_tmp`

Confirmed: it holds the **previous committed value** of `vpnc_dev_policy_list`. After every one of the eight steps, `_tmp` equalled the list as it stood before that step. It is the WebUI rollback copy.

The app should write it the same way - set `_tmp` to the outgoing value, then set the list - so a WebUI visit afterwards does not find a stale rollback point pointing at a configuration that never existed.

#### Service calls

Exactly three, in this order, for an assignment change to a device that **already has a DHCP reservation**:

```sh
service stop_vpnc                    # the tunnel must be down first - see below
service restart_vpnc_dev_policy      # applies the new list
service restart_vpnc                 # brings the tunnel back
```

But when the device has **no reservation** and the firmware has to create one, the middle call becomes a chained pair and the cost changes completely:

```text
notify_rc restart_net_and_phy;restart_vpnc_dev_policy;
```

`restart_net_and_phy` restarts the network **and the physical layer**. Every switch port bounces, which takes down anything wired downstream - a second router, an AP, a switch, and everything behind it - and it renews the WAN lease, which on a residential connection usually means a new public address. Confirmed 2026-09-06: the LAN dropped at `20:11:41`, `udhcpc_wan` re-leased at `20:11:58`, and DDNS registered a new address at `20:12:08`. The `restart_vpnc_dev_policy`-only steps earlier in the same run caused none of that.

And for "apply to all devices", the same shape with the middle call swapped:

```sh
service stop_vpnc
service restart_default_wan          # applies vpnc_default_wan
service restart_vpnc
```

All of these go through `notify_rc`, which queues and returns immediately, so none of them is finished when the call returns - the same trap that produced the watchdog deploy race in 409. Verify by polling, do not sleep and hope.

#### `vpnc_default_wan` uses the same identifier

Turning on "apply to all devices" for wgc1 set `vpnc_default_wan=9` - the clientlist index 6 again, not the slot. Turning it off set it back to `0`. So `0` means plain WAN and any other value is an index-6 identifier, which settles the open question in 3.3.1.

#### Assigning a device with no DHCP reservation creates one

The device used for the final step had no reservation. Assigning it added one to `dhcp_staticlist`:

```text
<AA:BB:CC:DD:EE:FF>192.168.1.22>>
```

MAC, IP, empty DNS, **empty hostname**. That follows from the binding being by IP: the firmware has to pin the address before a policy on it means anything. Two consequences for the app:

- Assigning a device is not a read-only act on `dhcp_staticlist`. If the app writes `vpnc_dev_policy_list` itself, it must add the reservation too, or the assignment decays the moment the lease moves.
- For a device using **MAC randomisation** the reservation is pinned to the address it happens to be using now, so it breaks silently at the next rotation. Warn, or refuse.

> [!IMPORTANT]
> **The tunnel must be disabled before its assignments can be changed.** Confirmed on hardware: the WebUI will not apply an assignment to a running profile, and every observed sequence starts with `stop_vpnc`.
>
> **A device assigned to a tunnel that is down loses internet access entirely** - it fails closed rather than falling back to the WAN. That is the desired security property, and it is also a footgun: assigning a device to a disabled slot silently blackholes it. The app must refuse, or warn unmistakably.

> [!WARNING]
> **Applying an assignment costs one of two very different amounts, and the app should not treat them alike.**
>
> - **Device already has a DHCP reservation:** `stop_vpnc` / `restart_vpnc_dev_policy` / `restart_vpnc`. VPN routing bounces for assigned devices. Everything else is untouched. Cheap.
> - **Device has no reservation:** the firmware creates one, which drags in `restart_net_and_phy` - every switch port bounces, downstream routers and APs drop with everything behind them, and the WAN re-leases. Expensive, and it hits devices that have nothing to do with the assignment.
>
> So the app should offer devices that already hold a reservation as the ordinary case, and treat "create a reservation for this device" as a distinct, explicitly confirmed action that warns the whole network will drop for a minute. `restart_default_wan`, used by "apply to all devices", was measured as harmless by comparison - it did not drop anything during the run.

---
## Phase 2 - app changes

### 2.1 Device list - SETTLED 2026-09-06

Measured on hardware. Three sources were candidates; the answer is a **layered read of two persistent ones**, with a third as an optional extra.

| Source | Persistent | Holds | Verdict |
| --- | :-: | --- | --- |
| `/jffs/nmp_cl_json.js` | yes | every device ever seen, keyed by uppercase MAC, with `online` 0/1, `conn_ts`, auto-detected `name`, `vendor`, `type` | **the device set** |
| `custom_clientlist` | yes | the user's own name for a device, uppercase MAC | **the display name** |
| `/tmp/nmp_cache.js` | no | the same devices plus `ip` and a `nickName` already merged from `custom_clientlist` | IP only, if wanted |
| `/proc/net/arp` | n/a | currently-reachable devices, **lowercase** MACs, no names | rejected |
| `/tmp/clientlist.json` | no | wireless associations by AP MAC and band, with RSSI - not an inventory | rejected |
| `client_info_tmp` | - | empty on this firmware | rejected |

**Why not ARP.** It is a presence table: it only knows what is answering right now. Assigning "the media centre" must not require the media centre to be switched on, and the router itself clearly manages this - the WebUI and the ASUS app both list devices that are currently off. `/jffs/nmp_cl_json.js` is how: it is in `/jffs` so it survives a reboot, and it carries an explicit `online` flag. Confirmed on hardware - one entry read `online: 0` while every other read `1`.

**Why two sources and not one.** `nmp_cl_json.js`'s `name` is the *auto-detected* name - a vendor string or a DHCP hostname - not the name the user gave the device. On the test router one device came back as its vendor string where the user calls it something else entirely, and **two different devices shared an identical auto-generated hostname**. So:

```text
display name = custom_clientlist name   (the user's own, if they set one)
             | nmp_cl_json.js name      (auto-detected)
             | the MAC                  (last resort)
```

Both are keyed by **uppercase** MAC, so the join needs no case normalisation - that problem only existed because ARP reports lowercase.

**MAC randomisation breaks assignment silently.** Modern phones and tablets rotate their MAC per network. An assignment keyed on MAC - which is the only key the firmware offers - simply stops applying when the address changes, with no error and nothing in any log; the device reappears in the list as a new entry and the old one lingers as a ghost. Observed on the test router: one device was using a locally-administered address - second hex digit `2`, `6`, `A` or `E` - the tell-tale of a randomised MAC.

Nothing can be done about the binding itself, but the app should not pretend the problem does not exist:

- An entry that has been offline for a long time is more likely a rotated MAC than a device that left. Show `conn_ts` as "last seen", so a stale entry looks stale.
- Consider warning when assigning a device whose MAC has the locally-administered bit set (`second hex digit is 2, 6, A or E`) - "this device randomises its address and may lose its assignment".
- Never silently prune ghosts. The user may have assigned one deliberately.

**Consequences for the UI.**

- Names are **not unique**. Show the IP or the MAC alongside, or two devices look identical.
- Show the `online` state, and let an offline device be assigned anyway - that is the whole point of using the persistent list.
- IP is not in the persistent file. Take it from `/tmp/nmp_cache.js` when the file is there, and simply omit it when it is not, rather than making the screen depend on a `/tmp` file.

**Parsing.** All three are JSON, and stock already requires `jq` at `/jffs/cfg-pia-wg/jq` for the watchdog - so the read is a single `jq` invocation over SSH, not a bespoke parser. Nothing new is needed on the router.

### 2.2 Percent-decoding

Nothing in the app decodes today, because our own descriptions never needed it. A device named `Andrew's iPad` or `Study TV` comes back escaped. Needed **both ways**: decode for display, re-encode on write, and round-trip a name the app did not create without corrupting it.

### 2.3 Writes must be verified

Section 3.3.5's truncation warning is the same failure `_writeFile` already guards against for the watchdog script, by comparing `wc -c` against the expected byte count and throwing. Any write to `custom_clientlist` or the assignment key should read the value back and compare before reporting success. Silently half-writing a user's device list would be the worst bug this feature could have.

### 2.4 Menu and home screen

- Rename "Generate PIA WireGuard config" to **"Standalone PIA WireGuard config"** - touches `AppDestination.standalone.title`, the README walkthrough and the screenshots.
- New entry **"VPN device assignment"**, carrying **both** footnote markers: it needs SSH connectivity *and* stock firmware.
- Renumber the footnotes: `*` becomes `¹ requires SSH connectivity to an ASUS router`, and add `² stock firmware only`.
- No change to "Manage PIA WireGuard config", "Watchdog Wireguard management", "View app log" or "Exit app".

> [!NOTE]
> That makes six primary buttons plus two footnote lines and two footer links, on a screen that already needs a `Spacer` to fit. Check the smallest supported screen before committing to a sixth button - a submenu under MANAGE is the fallback.
>
> `test/screens/main_menu_screen_test.dart` asserts "main menu shows five entries", and the drawer (`AppDestination`) gains a destination too.

### 2.5 The screen itself

- List devices with their current assignment.
- Assign a device to a slot, or clear it.
- An "apply to all devices" control, writing `vpnc_default_wan`.
- Apply with the service call confirmed in phase 0.

### 2.6 Freemium

`BACKLOG.md` 1.2 puts everything except config generation behind the lifetime unlock. Device assignment is router management, so on that rule it is paid. Decide explicitly **before** the UI exists - it changes where the paywall check goes, and it is a far easier decision now than later.

---

## Phase 3 - documentation

1. Copy phase 1 into `ARCHITECTURE.md` as section **3.3**. The numbering conflict it used to warn about was resolved in 409 - the whole document is 0-based now.
2. `ARCHITECTURE.md` section 5.1.2 and `_kKillSwitchStock`: reword the stock kill-switch line now that assigned devices fail closed.
3. `.claude/CONTEXT.md`: new screen in the section 3 file table, the NVRAM keys in section 4.9, and the assignment behaviour alongside the other stock quirks.
4. `README.md`: the new menu entry in section 5, a subsection for the screen, and the renamed Generate entry.
5. `scripts/showall.sh` and `scripts/clearall.sh`: show and clear the assignment key and `vpnc_default_wan`.
6. `TESTING.md` section 4: checks for assigning, unassigning, apply-to-all, and the fail-closed behaviour when an assigned tunnel drops. Then regenerate a record with `scripts/new-test-record.py`.

---

## What Andrew needs to do

In order. **Step 1 is done** - phase 2 is unblocked.

1. ~~Run `scripts/probe-device-assignment.sh`.~~ **Done 2026-09-06.** Schema, write semantics and service calls are in 3.3.6. The run stopped at step 8 when the WAN renegotiated; the state it stopped in supplied the answer anyway.
2. ~~Confirm `vpnc_default_wan=0` means plain WAN.~~ **Evidence gathered 2026-09-06**: with all ten devices unassigned and `vpnc_default_wan=0`, every one still had internet. Step 5 of the probe confirms the other direction - that an unassigned device follows a VPN when one IS the default.
3. ~~Decide the device-list source.~~ **Settled 2026-09-06** - see 2.1. `/jffs/nmp_cl_json.js` for the device set and online state, `custom_clientlist` overlaid for the user's own name.
4. **Decide whether device assignment is free or paid** (2.6).
5. **Check the six-button home screen on your smallest device** (2.4) before I build it, so a submenu decision is not made after the fact.
6. Optional, whenever convenient: **capture a `custom_clientlist` with a device whose name has an apostrophe or a space**, so the percent-decoding in 2.2 is written against a real value rather than an assumed one.
7. Optional: confirm `/tmp/nmp_cache.js` parses as JSON with `jq` despite the `.js` extension - it is the only source of a device IP, and if it does not parse we simply leave IPs off the screen.
