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

Observed on hardware 2026-09-05: with a tunnel set to **"apply to all devices"**, taking that tunnel down cost the affected devices their internet connectivity. That is **fail-closed** behaviour - **for that mechanism only**.

> [!CAUTION]
> **A per-device assignment falls through to the DEFAULT CONNECTION when its tunnel drops. CONFIRMED 2026-09-08 by running the test twice with different defaults: with the default on "Internet Connection" the device fell back to the WAN (`dev eth0`); with the default on wgc1 the same device fell back to `dev wgc1`, not the WAN.**
>
> So the leak is a property of THAT configuration, not of assignment. Fail-closed is reachable and now recommendable on evidence: pin the devices to a tunnel AND make that tunnel the default, which is the maintainer's long-standing setup and the one where a stale config took the whole network offline rather than leaking - the fault this app was written to fix. One rule covers every case: the `ip rule` dies with the interface and traffic falls through to the default. See `ARCHITECTURE.md` 3.3.6.
>
> So the feature is not a kill switch **by itself**, and whether it protects depends on a separate setting the user may not connect to it. Never describe assignment alone as protection.
>
> What it is: a way to route chosen devices through a chosen tunnel while that tunnel is up. That is worth having - it is what "which of my devices use the VPN" means - but it is a routing feature, not a protection feature.
>
> The watchdog is what makes it safe, by bounding any leak to one check interval. **Assignment without a watchdog on the same slot is the case to warn about.**

> [!CAUTION]
> **That observation covers `vpnc_default_wan`, not per-device assignment.** They are different mechanisms - one is the default route for unassigned traffic, the other is an `ip rule` for one source address - and fail-closed has NOT been shown for the second. It was briefly written up as confirmed on the strength of the 09-05 run; that was a generalisation, not a measurement, and it is withdrawn. See item 10: if per-device assignment fails *open*, the security story for this feature is much weaker and the app has to say so plainly rather than imply a kill switch it does not have.

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

#### 3.3.3a Reserved or not - the distinction the screen needs

The WebUI client list carries an **IP Method** column with exactly two values, and it is the same split this feature turns on:

| IP Method | Means | Source |
| --- | --- | --- |
| `MAC-IP Binding` | has a reservation | the MAC appears in `dhcp_staticlist` |
| `Automatic IP` | plain lease | it does not |

So the app derives it the same way the firmware does - membership of `dhcp_staticlist`, no extra source needed. Useful validation that the model is right, and the label is worth borrowing rather than inventing new wording.

Two behaviours confirmed 2026-09-06:

- **Removing a reservation is as disruptive as adding one.** Deleting one entry in the WebUI dropped a 5 GHz laptop hard enough to kill an RDP session running over it. Any `dhcp_staticlist` write goes through the heavy path, in both directions - which is what makes item 9 worth testing.
- **A device keeps its address after its reservation is removed.** The tablet held the same IP on a plain lease afterwards, reappearing in the client list as `Automatic IP`. So removing a reservation does not immediately break an assignment keyed on that IP - it just stops guaranteeing it, and the breakage arrives silently at some later renewal. That is a worse failure than an immediate one, and it is an argument for the app never removing a reservation on unassign.

> [!NOTE]
> A real example of the fragile combination is sitting in the test data: a device with a **randomised MAC** (`B2:` - locally-administered bit set) that also holds a **reservation**. It looks pinned and is not; the reservation dies at the next MAC rotation and the assignment goes with it, silently. This is the case the 2.1 warning exists for.

---
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

**Records are NOT a fixed nine indexes.** Measured 2026-09-06 on a six-record list, the counts were 9, 9, 9, 8, 6 and 6 - the WebUI writes some trailing empties and drops others, apparently depending on which firmware version created the entry. A parser that requires nine indexes rejects most of a real list.

```text
device1>AA:BB:CC:DD:EE:FF>0>60>>>>><device4>0A:0B:0C:0D:0E:0F>0>4>>>><RT-EFGH>05:04:03:02:01:00>0>24>>
```

Split on `<`, then on `>`, and treat any index past the end as empty. Group type `0` means unknown and gives a generic icon.

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
| 0 | enabled | `1` assigned, `0` not. **Both forms occur** - see below |
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

> [!IMPORTANT]
> **A record being present does not mean the device is assigned.** On a freshly rebuilt router that had never had a `wgc` slot configured, the list already read:
>
> ```text
> 0>192.168.1.20>>0<0>192.168.1.21>>0<0>192.168.1.22>>0<0>192.168.1.23>>0
> ```
>
> Four records, all `enabled=0` and `vpnc_idx=0`, one for each device holding a **DHCP reservation** (the router itself and the mesh node excluded). So the firmware seeds a disabled placeholder per reserved device, and separately the probe showed unassigning can remove a record outright. **Both forms mean the same thing.**
>
> Two consequences, and the first is a security bug waiting to happen:
>
> - **Read index 0, never mere presence.** A parser that treats "in the list" as "assigned" reports every reserved device as being on a VPN when none of them are.
> - **Preserve records the app did not create.** Writing only the app's own assignments would drop the placeholders the firmware maintains. Rebuild the list from the existing one with the app's changes applied, rather than from the app's model alone.

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
> **UNVERIFIED: does a device assigned to a down tunnel fail closed or fall back to the WAN?** Fail-closed is the desired property and the one the feature is sold on, but it has only been measured for "apply to all devices" (`vpnc_default_wan`), not for a per-device `ip rule`. Item 10 settles it. Either way the app should warn before assigning to a disabled slot - fail-closed means the device is blackholed, fail-open means the user believes it is protected when it is not, and both deserve a warning.

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
- **Warn when the MAC has the locally-administered bit set** - the second hex digit is `2`, `6`, `A` or `E`. AGREED, and now confirmed against real data 2026-09-06: of six named devices exactly one had it set, and it was one of the two the user knew to be randomising. Cheap, reliable, no guesswork.

  It detects **the address currently in use**, not the device setting - the other known randomiser was connected on its factory MAC at the time and reads as stable. So the warning is "this address looks randomised", never "this device randomises".
- Never silently prune ghosts. The user may have assigned one deliberately.

**Consequences for the UI.**

- Names are **not unique**. Show the IP or the MAC alongside, or two devices look identical.
- Show the `online` state, and let an offline device be assigned anyway - that is the whole point of using the persistent list.
- IP is not in the persistent file. Take it from `/tmp/nmp_cache.js` when the file is there, and simply omit it when it is not, rather than making the screen depend on a `/tmp` file.

**Parsing.** All three are JSON, and stock already requires `jq` at `/jffs/cfg-pia-wg/jq` for the watchdog - so the read is a single `jq` invocation over SSH, not a bespoke parser. Nothing new is needed on the router.

### 2.2 Names are stored raw, not percent-encoded - SETTLED 2026-09-06

The plan assumed `custom_clientlist` percent-encoded awkward characters and that the app would need to decode on read and encode on write. **It does not.** A device deliberately renamed to `Arc's "Tab"` was stored verbatim, apostrophe, double quotes, spaces and all:

```text
device6>AA:BB:CC:DD:EE:FF>0>9>>
```

So there is no codec to write. What replaces it is a smaller job and a sharper hazard.

**Parsing.** Split on `<`, then on `>`, tolerate short records (3.3.4). A name containing `<` or `>` would corrupt the structure and there is no escaping to protect against it; the WebUI most likely rejects those characters on input, but the app should not assume so. Cap the split rather than trusting the field count, and treat a record that does not yield a plausible MAC at index 1 as unparseable rather than guessing.

**Quoting - this is the real risk.** These names arrive over SSH and go back into shell commands. A name holding an apostrophe breaks naive single-quoting, and `Arc's "Tab"` is a live example sitting on the test router right now. Every interpolation of a device name must go through `shellSingleQuote` in `router_slot_service.dart`, the same helper the rest of the app already uses. `test/unit/no_escaped_constants_test.dart` will not catch this one - it looks for the opposite mistake - so it needs its own test with that exact name as the fixture.

**Display.** Nothing to decode, but the name is arbitrary user text going into a Flutter `Text`, so it needs no escaping either - just do not build it into a formatted string that assumes anything about its contents.
### 2.3 Writes must be verified

Section 3.3.5's truncation warning is the same failure `_writeFile` already guards against for the watchdog script, by comparing `wc -c` against the expected byte count and throwing. Any write to `custom_clientlist` or the assignment key should read the value back and compare before reporting success. Silently half-writing a user's device list would be the worst bug this feature could have.

### 2.4 Menu and home screen

- Rename "Generate PIA WireGuard config" to **"Standalone PIA WireGuard config"** - touches `AppDestination.standalone.title`, the README walkthrough and the screenshots.
- New entry **"VPN device assignment"**, carrying **both** footnote markers: it needs SSH connectivity *and* stock firmware.
- Renumber the footnotes: `*` becomes `¹ requires SSH connectivity to an ASUS router`, and add `² stock firmware only`.
- No change to "Manage PIA WireGuard config", "Watchdog Wireguard management", "View app log" or "Exit app".

> [!NOTE]
> **Checked on hardware 2026-09-06: it fits, and comfortably.** A screenshot of the current five-button menu, taken on a phone with an enlarged system font and display zoom - the worst realistic case - showed roughly a third of the screen empty below the help link. A sixth button plus the extra footnote line has room without shrinking anything.
>
> **No submenu.** That decision is now made rather than deferred, which was the point of checking first.
>
> `test/screens/main_menu_screen_test.dart` asserts "main menu shows five entries", and the drawer (`AppDestination`) gains a destination too.

### 2.5 The screen itself - AGREED 2026-09-08

```text
  VPN DEVICE ASSIGNMENT

  Default connection
  [ wgc1 - pia-aus_melbourne           v ]
  Devices set to "default" use this. Assigned
  devices fall back to it if their tunnel drops.
  --------------------------------------------
  Laptop - 192.168.1.29
  [ default                            v ]
  --------------------------------------------
  Console - 192.168.1.31 - DHCP
  [ wgc5 - pia-aus_perth             * v ]
  --------------------------------------------
  NAS - 192.168.1.40
  [ OpenVPN, not app managed           v ]
  --------------------------------------------
  00:01:02:03:04:05 - 192.168.1.55 - DHCP
  [ default                            v ]
  --------------------------------------------

  Names come from your router's client list.

              [     APPLY 2     ]
```

**Two lines per device.** Name and IP on one line separated by ` - `, the picker on the next. The MAC replaces the name only when there is no name; it is never a third line.

**Tag only the exception.** A device that is online, on a stable MAC and holding a DHCP reservation shows nothing but its name and address. Everything else earns a tag: `DHCP` for no reservation, `offline`, and a warning for a locally-administered MAC. This keeps the common row short enough for a narrow screen and puts every mark where it means something.

**The `offline` tag reads `online` from `nmp_cl_json.js`, not `isOnline` from `nmp_cache.js`.** Measured 2026-09-08: after ten minutes powered off, the first had updated and the second had not. Taking liveness from `nmp_cache.js`, where every other field comes from, would show every device online forever.

**There is no "last seen" tag.** It was in the design until `conn_ts` was measured on 2026-09-08. It reads `0` for every WIRED device, and the five wireless devices that do carry a value share it to within three seconds - a single moment, the last reboot. It is a wireless association time, not a last-seen time, and showing it would mark every wired device as never-seen. `online` / `isOnline` are reliable, so the `offline` tag stays.

**The default connection sits at the top, with its sentence.** Not in a sub-page. 3.3.6 makes it the switch that decides whether an assignment fails open or fails closed, and no user would guess that. It stages like any other change and adds `restart_default_wan` to the apply.

**Staged changes, one APPLY, centred.** Matches the WebUI, matches the cost model - one service call for N changes - and lets a single confirmation cover every warning. The confirmation lists each change as `name` over `from -> to`, then adds only the paragraphs that apply: the whole-network restart when any staged device needs a reservation created, and the replacement notice when a staged device currently belongs to a VPN this app does not manage.

**The picker gives each entry two lines** - `wgcN - pia-<region>` over the watchdog state in words (`watchdog active` / `watchdog paused` / `no watchdog`), from the `watchdogActive` and `watchdogConfigured` fields `SlotInfo` already carries. Two lines because `pia-us_north_carolina-pf` is 24 characters and the state will not fit beside it. The `pia-` prefix is kept: the rest of the app shows `info.desc` raw, and it is what the WebUI shows too.

**Scope is `wgcN` and nothing else.** The WebUI allows up to 16 VPN profiles of any kind, and `vpnc_dev_policy_list` refers to them by clientlist index 6 - which can point at OpenVPN, PPTP, L2TP or a third-party provider just as easily as WireGuard. Two rules follow:

- The picker offers **only** app-managed `wgcN` slots. A non-WireGuard profile is never an option, only a state a device can already be in.
- A device already pinned to one is shown with its type and `not app managed`, and its record is written back **byte-for-byte**. Rendering it as "default" would silently destroy the user's assignment on the next apply. Choosing a `wgcN` for it is allowed, behind a confirmation that says it replaces the existing assignment.

**The policy record is keyed by IP, so a device with no known IP cannot be assigned at all.** `nmp_cl_json.js` - the persistent inventory - carries no address. So the IP is sourced in order: `/tmp/nmp_cache.js` when present, then `dhcp_staticlist`, which holds MAC-to-IP for every reserved device whether it is online or not. A device that is unreserved AND has no cached address is listed with its picker disabled and the line "connect this device once to assign it", because there is no address to write and none we could safely invent.

**APPLY re-reads before it writes.** README section 6 records that a WebUI page open since before your change writes the whole list back from its stale copy; the same hazard runs in reverse. So apply re-reads `vpnc_dev_policy_list` and `vpnc_clientlist`, compares every record it is not touching against what was loaded, and refuses with "the router changed while you were editing" rather than clobbering.

**Service calls: the light pair only** - `restart_dnsmasq` then `restart_vpnc_dev_policy`, per Q9. `restart_net_and_phy` is reached only when the firmware itself drags it in by creating a reservation, which is the case the confirmation warns about.

### 2.6 Freemium

**DECIDED 2026-09-06: paid.** `BACKLOG.md` 1.2 puts everything except config generation behind the lifetime unlock, and device assignment is router management, so it follows the rule with no special case. Build the gate in from the start rather than retrofitting it changes where the paywall check goes, and it is a far easier decision now than later.

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

**Everything blocking is answered. The plan is finalised and phase 2 can be built.** What remains is one optional check and one design decision that only Andrew can make.

### Answered

1. ~~Run `scripts/probe-device-assignment.sh`.~~ **Done 2026-09-06.** Schema, write semantics and both service sequences are in 3.3.6. The run stopped at step 8 when `restart_net_and_phy` bounced the LAN; the state it stopped in supplied the answer anyway.
2. ~~Confirm `vpnc_default_wan=0` means plain WAN.~~ **Confirmed 2026-09-06.** Turning on "apply to all devices" for wgc1 wrote `9` - the clientlist index 6, the same identifier the assignment records use - and turning it off wrote `0`.
3. ~~Decide the device-list source.~~ **Settled** - see 2.1. `/jffs/nmp_cl_json.js` for the device set and online state, `custom_clientlist` for the display name.
4. ~~Free or paid?~~ **Paid**, decided 2026-09-06. Follows the `BACKLOG.md` 1.2 rule with no special case; build the gate in from the start.
5. ~~Check the six-button home screen.~~ **Fits comfortably**, checked 2026-09-06 on an enlarged-font phone - about a third of the screen was still empty. **No submenu.**
6. ~~Capture a name with an apostrophe.~~ **Done, and it overturned the plan** - see 2.2. Names are stored **raw**, not percent-encoded, so there is no codec to write; the real risk is shell quoting, and there is now a live example on the router to test against.

### Still open

**One decision left: item 8.** Item 7 is answered and item 9 is a cheap test that could change the answer to 8.

7. ~~Does `/tmp/nmp_cache.js` parse as JSON?~~ **Yes**, confirmed 2026-09-06 with `jq -e`. Top-level object keyed by **uppercase MAC**, with `.ip` present and populated:

    ```text
    AA:BB:CC:DD:EE:FF  ip=192.168.1.20
    0A:0B:0C:0D:0E:0F  ip=192.168.1.21
    ```

    Same key format as `nmp_cl_json.js` and `custom_clientlist`, so the join needs no normalisation. It is volatile (`/tmp`), so treat a missing file as "no IP known" rather than an error.

8. ~~Which devices does the screen offer?~~ **DECIDED 2026-09-06: all of them.**

    Reserved-only was considered and rejected. A DHCP *reservation* is a deliberate manual mapping, not something a device acquires by connecting - every device has a *lease*, almost none has a reservation. The test router is atypical with most devices reserved; a normal user has none, so a reserved-only list would be **empty on most routers**. That is not a narrower feature, it is no feature.

    **Corroborated by the reference implementation 2026-09-07**: with the router in a clean state and only four reservations left, VPN Fusion offered **eight** devices as assignable - every device it currently knows about, reserved or not. Stock makes no distinction in the picker, so neither should the app.

    **So the app writes `dhcp_staticlist` itself.** Not by choice - VPN Fusion binds by IP, and the stock WebUI creates the reservation for you (observed at probe step 8). Matching stock is also the least surprising option: requiring a WebUI trip first would be a two-app workflow for the headline feature, and this app exists so that everything needed for VPN management is in one place.

    The alternative - writing the policy record against a lease that can move - fails in the worst direction for a VPN tool, and silently both ways:

    - the lease moves, the assignment stops applying, and the user believes a device is protected when it is not;
    - **whatever device next takes that IP inherits the assignment** - a guest phone routed through the tunnel without anyone asking for it.

    What the app owes the user is disclosure, not avoidance: assigning a device with no reservation must state that it will reserve the address the device holds now, that this is what the router own VPN Fusion page does, and what the disruption is. Cost is **per device, not per operation** - the expensive path runs once, and every later move or unassign of that device is cheap.

    Open sub-question, low stakes: does unassigning remove a reservation the app created? Not observed - probe step 5 unassigned a device that was already reserved, so it proves nothing. A leftover reservation is harmless. **Do not track "reservations we created" in order to undo them** - that is app-side state describing router-side config, and it goes stale the moment anyone edits it elsewhere.

9. ~~Is `restart_net_and_phy` really required?~~ **ANSWERED 2026-09-08: no.** The light pair - `restart_dnsmasq` then `restart_vpnc_dev_policy` - applied a brand-new reservation and policy with nothing bouncing. The app should always use it, and needs no whole-network disruption warning.

10. ~~Does a per-device assignment fail closed?~~ **ANSWERED 2026-09-08, then CONFIRMED by a second run: it falls through to whatever the default connection is.** Run 1 (default = Internet) sent the device to the WAN, which read as failing open. Run 2 (default = wgc1, target still wgc5) sent the same device to `dev wgc1` - if the blunter "always falls to the WAN" reading were right it would have gone to `eth0`. So there is one rule, and the outcome is chosen by a setting the user controls. This is the most consequential result of the whole investigation, and the second run is what made it actionable rather than merely alarming.

### Both questions are answered; phase 2 can be built

`scripts/verify-device-assignment.sh` was run on an RT-ABCD 2026-09-08 and settled both. What it changes in the design:

| | Result | Consequence |
| --- | --- | --- |
| Q9 | the light pair is enough | no disruption warning; the app is gentler than the WebUI |
| Q10 | **falls through to the default connection** | assignment alone is routing, not protection - but pairing it with the default connection IS protection, and the app can say how |

What still needs deciding is not a measurement but a presentation question: **how the screen states what happens when the tunnel drops** without either burying it or making the feature sound useless. The confirming run gives a better answer than a warning does - the app can tell the user how to get fail-closed behaviour instead of only telling them they do not have it: assign the devices to a slot, make that slot the default connection, and deploy a watchdog on it. Three settings, one outcome.

## Test environment note

The secondary router was converted to an **AiMesh node** on 2026-09-07. Side effect worth knowing: **the conversion removed that router own DHCP reservation** - it dropped out of `dhcp_staticlist` without being asked, so a mesh node is not a device the app should expect to find there.

Two things to re-check now that the mesh is up, before trusting any device-list behaviour measured before that date:

- **Do devices behind a mesh node appear the same way?** They share the one DHCP server, so `dhcp_staticlist` and `nmp_cl_json.js` should be unchanged in shape, but the client list attributes a device to the node it is associated with and the probe has only ever seen a standalone secondary router.
- **Does an assignment work for a device behind the node?** The policy is an `ip rule` on the main router, and traffic from the node passes through it, so it should - but "should" is what item 10 is about.

Neither blocks phase 2. Both belong in the `TESTING.md` checklist for the feature.
