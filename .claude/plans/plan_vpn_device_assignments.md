# Plan: in-app device assignment to VPN slots

**Status:** DRAFT. Blocked on one unknown - see phase 0, which has to be answered before anything else is designed. Backlog item: `BACKLOG.md` 1.1 "ADD: in-app device assignment to VPN". Not current state - see `.claude/CONTEXT.md` for that.

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

**Deliverable of phase 0:** the key name, its record and field layout, and the service call. Everything downstream - the data model, the UI, the write path - depends on it.

---

## Phase 1 - NVRAM reference (destined for `ARCHITECTURE.md` section 3.3)

Written as finished documentation. When phase 0 lands, add the assignment key here and copy the whole section across.

> [!IMPORTANT]
> **Field numbering.** This section counts fields **0-based**, matching `VpncRecord`'s constants in `router_slot_service.dart`. `ARCHITECTURE.md` elsewhere counts **1-based**, so the same field has two names in two documents - and "field 6" currently means the *active flag* there and the *state index* here. Fix on merge: say `index N (0-based)` everywhere and never the bare word "field".
>
> | Constant | Index (0-based) | Holds | ARCHITECTURE.md calls it |
> | --- | ---: | --- | --- |
> | `_descIdx` | 0 | description / region | field 1 |
> | `_slotIdx` | 2 | slot number | field 3 |
> | `_activeIdx` | 5 | active flag | field 6 |
> | `_iptablesIdx` | 6 | the `vpncN_*` state index | field 7 |
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
<00:01:02:03:04:05>192.168.1.2>><05:04:03:02:01:00>192.168.1.30>>hostname2<FF:F0:E0:D0:C0:B0>192.168.1.40>>hostname5<A0:AD:7F:23:A1:57>192.168.1.60>>hostname6
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

The five trailing `>` on every record are the empty fields 4 through 8; the UI writes them unconditionally. Group type `0` means unknown and gives a generic icon.

### 3.3.5 Practical notes

- **The two lists are independent.** A MAC can appear in one and not the other, and renaming in `custom_clientlist` does not change the DHCP hostname. The sample data above shows it both ways: `hostname4` is only in `custom_clientlist`, `hostname5` and `hostname6` only in `dhcp_staticlist`.
- **MAC is the only stable identifier.** Hostnames are not unique and are editable in one list without changing the other.
- **NVRAM has a hard size ceiling.** After `nvram set` you need `nvram commit`, and a silently truncated write is the usual failure mode once a list gets long.

### 3.3.6 Assignment key

To be written once phase 0 identifies it.

---

## Phase 2 - app changes

### 2.1 Device list: decide the source of truth first

`custom_clientlist` holds only devices the user has **named or customised** in the WebUI. A device that simply joined the network may be in neither list, and a user who cannot find their laptop will call the feature broken. Options, in increasing completeness:

| Source | Gets you | Costs |
| --- | --- | --- |
| `custom_clientlist` alone | What the WebUI's own VPN Fusion picker shows | Misses unnamed devices |
| + `dhcp_staticlist`, joined on MAC | Reserved-lease devices too | Still misses transient ones |
| + ARP table (`ip neigh`) | Everything currently connected | Shows devices with no friendly name |

Whichever is chosen, join on **MAC**.

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

1. Copy phase 1 into `ARCHITECTURE.md` as section **3.3**, resolving the field-numbering conflict flagged at the top of phase 1 across the whole document.
2. `ARCHITECTURE.md` section 5.1.2 and `_kKillSwitchStock`: reword the stock kill-switch line now that assigned devices fail closed.
3. `.claude/CONTEXT.md`: new screen in the section 3 file table, the NVRAM keys in section 4.9, and the assignment behaviour alongside the other stock quirks.
4. `README.md`: the new menu entry in section 5, a subsection for the screen, and the renamed Generate entry.
5. `scripts/showall.sh` and `scripts/clearall.sh`: show and clear the assignment key and `vpnc_default_wan`.
6. `TESTING.md` section 4: checks for assigning, unassigning, apply-to-all, and the fail-closed behaviour when an assigned tunnel drops. Then regenerate a record with `scripts/new-test-record.py`.

---

## What Andrew needs to do

In order. Nothing in phase 2 can start until step 1 is answered.

1. **Run the five NVRAM diffs in phase 0** and paste the output back. This is the blocker: the plan has no data model for the actual feature until it is done. Roughly ten minutes at the WebUI.
2. **Confirm `vpnc_default_wan=0`** means plain WAN with no VPN - `clearall.sh` assumes it today without ever having checked.
3. **Decide the device-list source** from the table in 2.1. Recommendation: `custom_clientlist` merged with `dhcp_staticlist` on MAC, which matches what the WebUI shows plus reserved leases, without the noise of unnamed transient devices.
4. **Decide whether device assignment is free or paid** (2.6).
5. **Check the six-button home screen on your smallest device** (2.4) before I build it, so a submenu decision is not made after the fact.
6. Optional, whenever convenient: **capture a `custom_clientlist` with a device whose name has an apostrophe or a space**, so the percent-decoding in 2.2 is written against a real value rather than an assumed one.
