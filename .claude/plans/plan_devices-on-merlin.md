# DEVICES on Merlin (ID-555 to ID-559)

The measurements below, from 2026-11-12, are provisional: Andrew suspects that router's settings restore, and ID-555 measures again on a router reset and configured by hand. "Merlin's source" stands.

Reasoning and findings only; status lives in CHANGELOG. Device names, MACs and LAN addresses are in the git-ignored `.claude/testing/2026-11-12_merlin-devices.md`; here devices are named by role, and LAN addresses are invented (`192.168.1.x`, `192.168.1.0/24`), as CONTEXT.md section 1 requires.

## What has to be learnt first (ID-555)

On stock, DEVICES writes `vpnc_dev_policy_list` (VPN Fusion) and the app's own guard holds a pinned device offline when its tunnel is down. Merlin ignores that list: it routes devices through VPN Director and has its own kill switch per WireGuard client. Before designing anything, watch what Merlin's own web interface writes for each thing DEVICES does.

## Method

- Merlin 3004.388.13_0 on the maintainer router, flashed 2026-11-12, settings from a September Merlin backup, every WireGuard slot deleted, the app not installed.
- `snap.sh LABEL` captures whole namespaces into `/tmp/mm/LABEL` on the router (RAM, gone at reboot): all of NVRAM with each `<` list record on its own line, `ip rule`, every routing table, `ip addr`, iptables `-S` for filter, nat, mangle and raw, `wg show all` without the handshake and transfer lines, `cru l`, the process list without PIDs, `ls -lR /jffs`, and the contents of `/jffs/openvpn`, `/jffs/configs`, `/jffs/scripts`, `/jffs/addons` and `/etc/dnsmasq.conf`.
- `cmp.sh A B` prints each line that went (`-`) or arrived (`+`) between two snapshots, per file, with any value whose key looks like a secret masked. BusyBox has no `diff` or `comm`, so it uses `grep -vxF -f` both ways.
- Two baselines 60 seconds apart, with nothing changed, give the noise: whatever changes on its own.
- After each change, a snapshot at once and another two minutes later, since the firmware applies some changes after the page returns.
- A single observation is provisional until repeated.

## The changes, in order

1. `slots`: the app creates and enables wgc1 and wgc5, kill switch off. The new baseline.
2. `vd1`: VPN Director, one rule sending a wireless test device to WGC1.
3. `ks1`: wgc1's kill switch on; then `ks1down`, wgc1 switched off with the rule in place, and `ks1up`, switched back on. Then `ksapp`, the same switch-off through the app's DISABLE, to corroborate.
4. `vd2`: a second rule sending the wired test device to WGC5.
5. `vd1off`: the first rule disabled, not deleted.
6. `block` and `unblock`: a device's internet access switched off and on from the network map.
7. `rename`: a device renamed from the network map.
8. `ks5`: wgc5:pia-aus_melbourne's kill switch on, to test the rule numbering.
9. `default`: every LAN device through wgc5:pia-aus_melbourne, the Merlin counterpart of stock's default connection.
10. `wanpin`: one device sent to WAN under the network rule, the counterpart of stock's pin to Internet.
11. `reboot`: whether VPN Director and the kill switch hold from the first second after a restart, sampled once a second from a routed device, as stock's reboot leak was found (ID-345). A session of its own.

## Findings

(each change's NVRAM keys, rules and firewall entries, as measured)

### Baseline, 2026-11-12

- 4,612 lines per snapshot. In 60 seconds with nothing touched, only four things changed: `syslog.log` and `syslog.log-1` in `/jffs` (size and time), `sys_uptime_now` and `tstamp_bwdpi_alive`. Those are the noise, and are ignored below.
- With every slot deleted, `wgc1_enable` reads empty while `wgc2_enable` to `wgc5_enable` read `0`: deleting slot 1 seems to clear the key rather than reset it. One observation.
- `/jffs/openvpn` holds only five empty `vpn_clientN_custom3` files; no VPN Director rule file yet.

### 1. `slots`: the app creates and enables wgc1 and wgc5, kill switch off

- NVRAM: the slot keys the app writes (`wgcN_addr`, `_aips`, `_alive`, `_desc`, `_dns`, `_enable=1`, `_enforce=0`, `_ep_*`, `_fw=1`, `_mtu`, `_nat=1`, `_ppub`, `_priv`, `_psk`, plus the app's `_wd_primary_ip` and `_wd_secondary_ip`). Merlin keeps `wgcN_aips` in `/jffs/nvram/` as files. wgc5 had keys left from the September settings file; the app overwrote them.
- No `ip rule` changed. Enabling a slot routes nobody through it: on Merlin a WireGuard client carries LAN traffic only once VPN Director sends some there.
- Each slot gets its own routing table, `wgc1` and `wgc5`, holding `0.0.0.0/1` and `128.0.0.0/1` through the tunnel, a copy of the LAN, WAN and guest routes, and the endpoint via the WAN.
- The main table gains `9.9.9.9 dev wgc1` and `149.112.112.112 dev wgc1`, and table `wgc5` the same: the slots' DNS servers are routed through the first slot to start, for the router itself as well, and table `wgc5` copied that route from the main table when wgc5 started. Merlin's source confirms both (see "Merlin's source" below). Matches what ROUTER DNS ROUTING reads from the kernel on Merlin (ID-337).
- Firewall: `WGCF` and `WGCI` accept out, drop in, and clamp MSS per interface; `MASQUERADE` out of each tunnel; mangle marks `0x1/0x1` both ways; and two new, empty NAT chains, `DNSVPN6` and `DNSVPN10`, jumped to from PREROUTING for port 53. If those numbers are the slot's VPN Director unit, wgc1 is 6 and wgc5 is 10, so WireGuard units would run 6 to 10 after OpenVPN's 1 to 5. One observation.

### 2. `vd1`: one VPN Director rule, a wireless test device to WGC1

- The rule is kept in a file, not NVRAM: `/jffs/openvpn/vpndirector_rulelist`, mode `rw-rw----`, holding `<1>vd1>192.168.1.x>>WGC1`. Each record is `<enable>description>local IP>remote IP>interface`, records joined by `<`, the interface written `WGC1`.
- One `ip rule`: `11210: from 192.168.1.x lookup wgc1`. Before it, the only rules were `local`, three `90: to 10.6.0.N lookup main` for the WireGuard server's peers, `main` and `default`.
- The device's DNS follows the slot: `DNSVPN6` gains `-s 192.168.1.x/32 -j DNAT --to-destination` for each of wgc1's two DNS servers. So `DNSVPN6` belongs to wgc1, and `DNSVPN10` presumably to wgc5.
- `ip route get 8.8.4.4 from 192.168.1.x iif br0` changed from `via <gateway> dev eth0` to `dev wgc1` at once; the wired control device stayed on `eth0`.
- Applied in full by the time the page returned; nothing changed in the next two minutes but housekeeping. The tunnels were not restarted (`wg show` unchanged).
- `wgc1_rip` and `wgc5_rip` filled in at the same time, with an address near each endpoint, wgc5's too, though no rule names wgc5. Probably each tunnel's exit address, checked on a timer rather than by the rule. One observation.
- More housekeeping to ignore: `login_timestamp`, `wan0_expires`, and in `/jffs` `HTTPD_FB_DEBUG.log`, `security_recored.log`, `curllst`, `wl1_chansps`, `wlcnt.json`; plus a multicast route. `nmp_cl_json.js`, `asus_device_list` and `cfg_device_list` change on their own too, but are watched in case renaming a device touches them.

### 3. `ks1` and `ks1down`: the kill switch, then the slot switched off

- Kill switch on (web interface, Apply): `wgc1_enforce=1`, and one rule, `12215: from 192.168.1.x prohibit`, behind the device's `11210 ... lookup wgc1`. While wgc1's table has routes the device uses them; without them it falls to the prohibit. Apply restarted both tunnels (new interface numbers and listening ports), and Merlin wrote a full copy of the edited slot's keys into `wgc_*` (the web page's working copy) and rewrote `wgc1_dns` without the space after the comma.
- **Slot switched off with the kill switch on (web interface, Enable WireGuard No): the device leaked.** `wgc1_enable=0`; Merlin removed the `prohibit` rule, every route in table `wgc1`, the `DNSVPN6` chain with the device's DNS redirect, and wgc1's firewall and NAT entries. The rule `11210 ... lookup wgc1` stayed, but with its table empty the lookup fell through to `main`: `ip route get` gave `via <gateway> dev eth0`, and the device loaded websites. The main table's routes to the DNS servers moved from wgc1 to wgc5.
- So Merlin's kill switch holds while a slot is enabled and its tunnel is down or restarting, which is what `check-claims.sh` KS-stopped measured in October with `service stop_wgc` and what the watchdog's rebuild does. It does not hold once the slot is switched off. The app's DISABLE on Merlin sets `wgcN_enable=0` and stops the tunnel, as the web interface does, and warns about no devices there, since it reads only stock's pin list. First seen through the web interface; `ksapp` repeated it through the app.

### 3a. `ks1up`, `ksapp` and `ksappup`: back on, then the app's DISABLE and ENABLE

- Back on through the web interface: the `prohibit` rule, table `wgc1`, `DNSVPN6` with the device's redirect and the firewall entries all return, and the device goes `dev wgc1` again.
- **The app's DISABLE on wgc1:pia-nz leaked the same way (corroborated, ID-567).** Its confirmation named no device. `wgc1_enable=0`; the `prohibit` rule, the table's routes, `DNSVPN6` and the firewall entries went; `11210 ... lookup wgc1` stayed; `ip route get` gave `dev eth0`, and the device loaded websites.
- The app's ENABLE put everything back, `prohibit` included, but not the copies of the DNS server routes in table `wgc5` that the web interface's Apply restores (`9.9.9.9` and `149.112.112.112 dev wgc1 table wgc5`). The web page's Apply restarts every slot; the app restarts one. Harmless here, since nothing routes to wgc5:pia-aus_melbourne yet.

### 4. `vd2`: a second rule, the wired test device to wgc5:pia-aus_melbourne, kill switch off

- The file gains a second record: `<1>vd1>192.168.1.x>>WGC1<1>vd2>192.168.1.y>>WGC5`, in the order added; it is rewritten whole (25 bytes to 51).
- One rule, `12010: from 192.168.1.y lookup wgc5`, and the device's DNS redirect in `DNSVPN10`, so `DNSVPN10` is wgc5's: the chain is `DNSVPN<unit>`, with WireGuard slots on units 6 to 10.
- No `prohibit` for it, the kill switch being off. The device went `dev wgc5` at once; nothing else changed.
- Rule numbers so far: wgc1's routing rule 11210, wgc5's 12010, wgc1's kill switch 12215. A guess that fits: routing rules from 11200 + 200 x (slot - 1) + 10 per rule, so wgc2 to wgc4 would start at 11400, 11600 and 11800; kill switch rules from 12200 up. Not confirmed: the next rules and wgc5's kill switch will test it, and the app should read the rules rather than compute their numbers.
- The two DNS server routes in table `wgc5` that the app's ENABLE did not restore (3a) are still missing; applying a VPN Director rule does not put them back.

### 5. `vd1off`: the first rule switched off, not deleted

- The record's first field goes `1` to `0`: `<0>vd1>192.168.1.x>>WGC1`. Merlin removes the routing rule, the kill switch's `prohibit` and the device's DNS redirect together; the device goes out the WAN, as chosen.

### 6. `block` and `unblock`: a device's internet from the network map

- Identical to stock (ARCHITECTURE 6.9). Block appends the device to `MULTIFILTER_MAC`, `MULTIFILTER_DEVICENAME`, `MULTIFILTER_ENABLE` (as `2`) and `MULTIFILTER_MACFILTER_DAYTIME_V2`, and sets `MULTIFILTER_ALL=1`. The firewall gains the same MAC rules: `FORWARD` to `PControls`, `DROP` in `PControls`, `DROP` in `WGNPControls` for the guest bridge, and `PCREDIRECT` sending port 80 to the router's block page. A `pc_block` process runs while a block is in force. The device could not load websites.
- Merlin keeps the long `MULTIFILTER_*` values and `custom_clientlist` as files in `/jffs/nvram/`, but `nvram get` and `nvram show` read them as usual.
- The web page also added a `custom_clientlist` record for the device, with an icon number, when it saved the block.
- Unblock sets that device's `MULTIFILTER_ENABLE` back to `0` and keeps its entry; `MULTIFILTER_ALL` stays `1`; the firewall rules go.
- So DEVICES' switch-off needs no Merlin branch, beyond confirming `restart_firewall` does on Merlin what the page's Apply did.

### 7. `rename` and `renameback`: a device renamed from the network map

- Only the device's record in `custom_clientlist` changed: `<name>MAC>0>9>>`, the name field rewritten in place, and back again. Nothing else, no service restart. The device has no address reservation, so whether a rename also rewrites a `dhcp_staticlist` name, as the app does on stock, is untested.

### 8. `ks5`: wgc5:pia-aus_melbourne's kill switch on

- `wgc5_enforce=1`, and `12219: from 192.168.1.y prohibit` behind `12010 ... lookup wgc5`. With wgc1:pia-nz's at 12215, the kill switch rules sit at 12214 + slot, or 12209 + unit; which, and how a second device on one slot is numbered, is still open. The app reads them.
- Apply restarted both tunnels again and restored the two DNS server routes in table `wgc5` that the app's ENABLE had left out (3a), and loaded slot 5 into the page's working copy (`wgc_unit=5`, `wgc_*`).

### 9. `default`: the whole LAN through wgc5:pia-aus_melbourne

- A third record, `<1>default>192.168.1.0/24>>WGC5`; one rule, `12011: from 192.168.1.0/24 lookup wgc5`; a kill switch rule, `12219: from 192.168.1.0/24 prohibit`; and `DNSVPN10` redirects the whole subnet's DNS to the slot's servers. Every test device went `dev wgc5`; the router's own traffic stayed on `eth0`.
- **Numbering, now from two rules on one slot:** routing rules are 11010 + 200 x slot + the rule's place among that slot's rules (wgc1 11210; wgc5 12010 and 12011), so each slot has a block of 200, which matches the page's limit of 199 rules. Kill switch rules are one number per slot, 12214 + slot, shared by every rule on it (12215, 12219).
- **Consequence for DEVICES: a lower slot wins, whatever the rule.** The kernel takes the lowest number first, so every rule for wgc1 beats every rule for wgc5, a whole-subnet rule included. Stock's per-device pin overrides the default connection; on Merlin a device pinned to a higher slot than the network rule would follow the network rule instead. Within one slot, rules apply in the order they were added. The DNS chains do not follow the same order: each slot inserts its chain's jump at the top of PREROUTING when it starts, so the slot started last is checked first (see "Merlin's source"). Here `DNSVPN6` was first because wgc1:pia-nz had been started last. (Corrected 2026-11-13: after a full restart the firewall puts the lowest slot's chain first; see the correction under "Merlin's source".)
- Not yet seen: how a rule to WAN ranks, which is how a device would be kept out of a VPN default.

### 10. `wanpin`: one device to WAN under the network rule

- The record goes to the front of the file, not the end: `<1>wanpin>192.168.1.z>>WAN<0>vd1>...`. Merlin keeps WAN rules first.
- One rule, `10010: from 192.168.1.z lookup main`: WAN rules have their own block from 10010, below every VPN rule, so a pin to WAN wins over any VPN rule, the network rule included. The device went `via <gateway> dev eth0`; the others stayed on `dev wgc5`.
- DNS: `-s 192.168.1.z/32 -j RETURN` added to both `DNSVPN6` and `DNSVPN10`, every WireGuard slot's chain, the disabled slot's too. Read in full afterwards: the `RETURN` is first in both chains, ahead of the subnet's `DNAT`, so the device's lookups go to the router's own DNS like the rest of its traffic. Merlin inserts WAN exclusions at the top.

## Remeasurement on the rebuilt router (ID-555, 2026-11-13)

The router reset to Merlin's defaults and configured by hand, no settings file restored; DNS Director off (it was on for every 2026-11-12 measurement). Each step below says what 2026-11-12 showed, so the run confirms or contradicts it.

### Post-reset check

- Clean: no `/jffs/openvpn` (so no VPN Director file), every `MULTIFILTER_*` empty, the app absent, `dnsfilter_enable_x=0` with no `DNSFILTER` jump, and `ip rule` holding only `local`, the WireGuard server's three peer rules at 90, `main` and `default`.
- Every `wgcN_enable` reads empty on a fresh router. On 2026-11-12 wgc2 to wgc5 read `0`: left by slots created and deleted, not a default.

### Baseline

- 4,277 lines per snapshot (4,612 on 2026-11-12, with the restored settings).
- In 60 seconds untouched, the same noise as 2026-11-12: `syslog.log`, `syslog.log-1` and `wlcnt.json` in `/jffs`, and `sys_uptime_now`, `tstamp_bwdpi_alive` and `login_timestamp`. The noise list is corroborated.

### 1. `slots`, created and enabled in the app, wgc5 first on purpose

wgc5:pia-aus_melbourne was created and enabled first, then wgc1:pia-nz, both with the app's default DNS, Quad9 (`9.9.9.9, 149.112.112.112`), kill switch off. Done in that order so the two readings of 2026-11-12 predict different results. Interface numbers confirm the order: wgc5 82, wgc1 83.

- **The DNS server route goes to the first slot to start, not the lowest-numbered.** The main table routes 9.9.9.9 and 149.112.112.112 through wgc5, and `ip route get 9.9.9.9` from the router says `dev wgc5`. The 2026-11-12 reading, "lowest-numbered", is disproved; the source's reading (`ip route add`, first to start) holds.
- **A later slot's table copies the route.** Table `wgc1` holds `9.9.9.9 dev wgc5` and `149.112.112.112 dev wgc5`; table `wgc5` holds neither, as it copied the main table before adding its own. So a device routed through wgc1 should have its DNS to Quad9 leave through wgc5: step 2 tests it.
- **Merlin's table numbers** (`/etc/iproute2/rt_tables`): wgc1 116 to wgc5 120, as the source's `115 + unit`. Tables 5 and 9, which the watchdog's `10 - slot` looks in, are empty (ID-572). With this start order the watchdog warning should move to wgc1's watchdog, the slot started second. Not yet seen.
- Same as 2026-11-12: no `ip rule` added; a table per slot holding `0.0.0.0/1` and `128.0.0.0/1` through the tunnel, copies of the LAN, guest, WAN and server-peer routes, and the endpoint via the WAN; `WGCF`/`WGCI` firewall entries, `MASQUERADE` per tunnel, mangle marks, and empty `DNSVPN6` and `DNSVPN10` chains jumped to from PREROUTING (`DNSVPN6` listed first); `wgcN_aips` as files in `/jffs/nvram`; the test devices still on the WAN.

### 2. `vd1`: VPN Director, the tablet to WGC1 (pia-nz)

- Same as 2026-11-12: `/jffs/openvpn/` created, the file holding `<1>vd1>192.168.1.x>>WGC1`; one rule, `11210: from 192.168.1.x lookup wgc1`; DNAT for the tablet to both Quad9 servers in `DNSVPN6`; the tablet `dev wgc1`, the desktop on the WAN; `wgc1_rip` and `wgc5_rip` filled in. Nothing but noise in the next two minutes: applied at once, now seen twice.
- **Cross-slot DNS, from the routes.** `ip route get 9.9.9.9 from <tablet> iif br0` gives `dev wgc5`, as does 149.112.112.112: the tablet's traffic goes through wgc1, its DNS through wgc5, by the route table `wgc1` copied in step 1. On the tablet, dnsleaktest.com's standard test showed its address in New Zealand and its DNS servers in Melbourne. (Corrected after step 11a: first written as "confirmed two ways". In 11a the routes sent the tablet's DNS through wgc1, and dnsleaktest still showed Melbourne servers, so Quad9 answers PIA's New Zealand exit from Melbourne and the servers' location can't tell the tunnels apart. The route reading stands; a check that can tell them apart is still to run.) Run after step 11, from the connection table: the desktop, routed through wgc5, had three DNS lookups in `/proc/net/nf_conntrack`, each `src=<desktop> dst=<router> dport=53` with the reply `src=9.9.9.9 dst=<wgc1's tunnel address>`. The reply's destination is the tunnel the lookup left by, so **cross-slot DNS is confirmed by a second, independent reading**: the desktop's traffic left through Melbourne, its lookups through New Zealand.

### 3. `ks1` and `ks1down`: wgc1's kill switch on, then wgc1 switched off (web page)

- `ks1`: `wgc1_enforce=1`, rule `12215: from <tablet> prohibit`, `wgc_*` (the page's working copy) filled with slot 1, `wgc1_dns` rewritten without the space; as 2026-11-12. Apply restarted both tunnels in slot order (wgc1 interface 84, wgc5 85), so the start order flipped: the main table's Quad9 routes moved to wgc1, table `wgc5` copied them, table `wgc1` lost them, and the tablet's DNS went `dev wgc1`. A web-page Apply resets the start order to slot order, as `start_wgcall()` predicts. `DNSVPN6` stayed first in PREROUTING though wgc5 started last, which corrects the chain-order reading (see "Merlin's source").
- **`ks1down`: the leak (ID-567) is confirmed on the rebuilt router.** `wgc1_enable=0`; the `prohibit` rule, table `wgc1`, `DNSVPN6` and wgc1's firewall and NAT entries went; `11210 ... lookup wgc1` stayed; the tablet's route went `via <gateway> dev eth0`, and dnsleaktest on the tablet showed the home internet address. Three sightings now, on two configurations, with DNS Director on and off. The page restarted wgc5 (interface 86), which took the Quad9 routes.

### 3a. `ks1up`, `ksapp`, `ksappup`: on through the page, then the app's DISABLE and ENABLE

Each predicted beforehand from the start-order reading, and each matched.

- `ks1up` (page, Enable Yes): both tunnels restarted in slot order (wgc1 87, wgc5 88); main table's Quad9 routes via wgc1, copied into table `wgc5`; `prohibit`, table `wgc1`, `DNSVPN6` with the tablet's DNAT and the firewall entries back; the tablet `dev wgc1` for traffic and DNS; `DNSVPN6` first.
- **`ksapp` (app DISABLE): the leak again, the fourth sighting and the second through the app.** The confirmation named no device. Only wgc1 stopped (wgc5 still 88). The Quad9 routes went from the main table and from table `wgc5` with wgc1's interface, and nothing put them back, so the router's own lookups to Quad9 left by the WAN. The tablet went `dev eth0`; dnsleaktest showed the home address and resolvers named "Anycast Global Backbone", since with `DNSVPN6` gone its lookups went to the router. (Withdrawn the same day: these were first read as the internet provider's resolvers in plain text. Step 4 showed the router's own DNS is Cloudflare over DNS-over-TLS; who those resolvers belong to is not known.)
- `ksappup` (app ENABLE): only wgc1 started (89). It added the Quad9 routes to the main table, finding none, but neither table holds a copy: wgc1 copied the main table before adding them, and wgc5 didn't restart. This is the 2026-11-12 "ENABLE doesn't restore the copies in table wgc5" explained: the app restarts one slot, and Merlin copies routes only at a slot's start. Not a fault in ENABLE.

### 4 and 5. `vd2` and `vd1off`: the desktop to WGC5 (pia-aus_melbourne), then vd1 switched off

- As 2026-11-12. `vd2`: the record appended and the file rewritten whole (25 to 51 bytes); `12010: from <desktop> lookup wgc5`; the desktop's DNAT to Quad9 in `DNSVPN10`; no `prohibit`, wgc5's kill switch being off; the desktop `dev wgc5`, and its DNS `dev wgc5` too, table `wgc5` holding no copied Quad9 route at this point. `vd1off`: the record's first field `1` to `0`; `11210`, `12215` and the tablet's DNAT removed together; the tablet on the WAN. Neither step restarted a tunnel.
- With no rule, the tablet's traffic to Quad9 itself still goes `dev wgc1`, by the main table's route: any device's traffic to a slot's DNS servers follows whichever slot holds that route.
- The router's own DNS on the rebuilt router: WAN DNS set by hand (`wan0_dnsenable_x=0`) to 1.1.1.2 and 1.0.0.2, with DNS-over-TLS on to `security.cloudflare-dns.com`. It doesn't overlap the slots' Quad9, so README 5.2.1's router-DNS case doesn't arise on this router.

### 6 and 7. `block`, `unblock`, `rename`, `renameback`: from the network map

- Block and unblock the phone: as 2026-11-12, key for key. `MULTIFILTER_MAC`, `_DEVICENAME`, `_ENABLE=2` and two `MULTIFILTER_MACFILTER_DAYTIME_V2` schedule records; `MULTIFILTER_ALL=1`; `FORWARD` to `PControls`, `DROP` in `PControls` and `WGNPControls`, `PCREDIRECT` port 80 to the router's block page; `pc_block` running; the page added a `custom_clientlist` record for the phone. Unblock: `MULTIFILTER_ENABLE=0`, entry kept, `MULTIFILTER_ALL` stays 1, firewall rules and `pc_block` gone. Two sightings: DEVICES' switch-off needs no Merlin branch.
- **Rename, this time of the desktop, which has an address reservation:** only its `custom_clientlist` record's name changed. Its `dhcp_staticlist` record kept the old name. So the web interface's rename leaves a reservation's name alone on Merlin, where the app on stock rewrites both. A decision for ID-556: follow the app's stock behaviour, or Merlin's page.

### 8 to 10. `ks5`, `default`, `wanpin`

Each predicted beforehand; each matched.

- `ks5` (wgc5's kill switch, page): `wgc5_enforce=1`, `12219: from <desktop> prohibit`, the page's working copy switched to slot 5 (`wgc_unit=5`). Apply restarted both tunnels in slot order (wgc1 90, wgc5 91), so table `wgc5` copied wgc1's Quad9 routes, and **the desktop's DNS flipped to `dev wgc1`** while its traffic stayed on wgc5: the cross-slot effect in the other direction, made by an Apply on an unrelated setting.
- `default` (the whole LAN to WGC5): `12011: from 192.168.1.0/24 lookup wgc5` and a second `12219` for the subnet (two rules on one slot share its kill-switch number, now seen twice); DNAT for the subnet in `DNSVPN10`. Every test device went `dev wgc5` and the router stayed on the WAN. **Every device's DNS to Quad9 went `dev wgc1`:** with the default on wgc5, as README advises, and a second slot sharing Quad9, the whole network's lookups leave through the other slot.
- `wanpin` (the phone to WAN): the record first in the file; `10010: from <phone> lookup main`, beating the subnet rule; `RETURN` for the phone first in both `DNSVPN6` and `DNSVPN10`; the phone on the WAN, the others on wgc5. As 2026-11-12.

### 11. Precedence, the whole-network leak, and chain order

Run twice; the first attempt went astray, and the router was put back to the state after step 10 through the web page (both tunnels restarted in slot order, vd1 off) and checked against step 10's summary before the second.

- `vd1on` (vd1 back on, the tablet now in both its wgc1 rule and the wgc5 subnet rule): `11210` and `12215` back; **the tablet went `dev wgc1`: the lower slot's rule wins over the subnet rule, measured.** Its DNS rewritten by `DNSVPN6`, routed `dev wgc1`. dnsleaktest on the tablet: an Auckland address, Melbourne DNS servers (see the correction under step 2).
- **`ks5app` (the app's DISABLE on wgc5, kill switch on, whole LAN on it): the leak for a whole-network default, the fifth sighting.** The confirmation named no device. Both `12219` rules, table `wgc5`, `DNSVPN10` and wgc5's firewall entries went; `12010` and `12011` stayed and fell through to the main table; the desktop went `via <gateway> dev eth0`, and dnsleaktest on the desktop showed the home address with the router's own Cloudflare resolvers. The tablet stayed on wgc1 by its own rule; the phone on the WAN by its pin.
- `ks5appup` (the app's ENABLE on wgc5): only wgc5 restarted; its table copied wgc1's Quad9 route, so the desktop's DNS went `dev wgc1` again; `12219` rules back. **`DNSVPN6` stayed first**, against the prediction: see the second correction under "Merlin's source". Chain order is by slot number, always.

### After step 11: block seen, watchdogs, the router's DNS

- Block, seen on the phone: blocked from the network map, it couldn't load websites, with its mobile data off (Android falls back to mobile data when Wi-Fi has no internet).
- **ID-572 confirmed:** with watchdogs on both slots and wgc1 started first, wgc5's watchdog logged "Could not aim a lookup at 9.9.9.9 through wgc5; skipping the name check" and wgc1's checked names normally. The app's bug, not the old settings.
- The router's own DNS: WAN DNS set by hand to Cloudflare's 1.1.1.2 and 1.0.0.2, DNS-over-TLS strict to `security.cloudflare-dns.com` through stubby, DNSSEC on, rebind protection on, DNS Director off, LAN clients given the router as their DNS. `dns_local_cache=0`, so `/etc/resolv.conf` lists 1.1.1.2 and 1.0.0.2 directly: the router's own programs look names up in plain DNS to Cloudflare, and only LAN clients' lookups go through dnsmasq to stubby's DNS-over-TLS. As ROUTER-DNS 3 already says of the router's own lookups.
- **The router's own DNS servers bypass the tunnel for routed devices (ID-574), Merlin's counterpart of ID-347.** Each slot's table holds `1.1.1.2` and `1.0.0.2 via <gateway> dev eth0 metric 1`, copied from the main table at the slot's start. `ip route get` from the desktop (wgc5) to 1.1.1.2 and from the tablet (wgc1) to 1.0.0.2 both gave `via <gateway> dev eth0`; 1.1.1.1 from the desktop gave `dev wgc5`. On stock the app's guard holds these addresses to the tunnel (build 480); on Merlin nothing does, so DEVICES on Merlin needs the same. So on Merlin, two slots sharing DNS servers means a device pinned to one has its lookups leave through whichever slot started first. Still inside a PIA tunnel, so not exposed to the ISP, but the wrong tunnel, and a dependency: a broken wgc5 would take the tablet's DNS with it while wgc1 is healthy. The app gives every slot the same default DNS (Quad9), so any app user with two slots on Merlin meets this. Input for ID-556. Stock routes the router's DNS by rule (ROUTER-DNS 7.2) and is not known to do this; not measured there.
- More housekeeping to ignore: `freeze_duck` (2 while the page applied, back to 0), `wan0_expires`, `curllst`, and a multicast route.

## What this means for DEVICES on Merlin (ID-556)

From the measurements above, as a starting point for the design, not the design itself.

- **Assign** = edit `/jffs/openvpn/vpndirector_rulelist`, then apply. The file is the whole state: one record per rule, `<enable>description>local IP>remote IP>interface`, interface `WGC1` to `WGC5` or `WAN`. What applying a file edited outside the page takes (`service restart_vpnrouting0`, which the watchdog and `check-claims.sh` already call) is to be measured, not assumed.
- **Precedence is by slot, not by rule.** WAN rules (10010 up) beat wgc1 (11210 up), which beats wgc5 (12010 up), whatever the order in the file. Stock's model, a per-device pin overriding the default connection, maps directly only when the default's slot is higher than every pinned device's slot, or for pins to Internet. DEVICES must either restrict the default on Merlin, or write per-device rules for everyone instead of a subnet rule, or explain the clash. A design decision for Andrew. (Decided 2026-11-13: see "ID-556 direction".)
- **Kill switch** = Merlin's own, per slot (`wgcN_enforce`), one `prohibit` rule per routed source at 12214 + slot. It holds while the slot is enabled; it goes when the slot is switched off (ID-567).
- **DNS** follows the rule by itself (`DNSVPN<unit>` DNAT per source; `RETURN` for WAN rules). Stock's DNS work, the app's `VPN_FUSION` redirects, has no Merlin counterpart to build.
- **Switch a device off** = the same `MULTIFILTER_*` keys and firewall rules as stock: no Merlin branch.
- **Rename** = `custom_clientlist`, as on stock. A reserved device's `dhcp_staticlist` name is untested.
- **The app's ENABLE** restarts only its slot and so leaves out two DNS server routes in other slots' tables that the page's Apply restores (3a). Harmless so far; watch it.
- Still to measure (ID-569): the reboot (step 11), and applying a rules file edited from a shell rather than the page.
- **The router's own DNS is decided differently on Merlin.** Stock uses fixed rules, so the highest-numbered slot always carries it (README 5.2.1). Merlin uses a route that the first slot to start adds, and nothing moves it when that slot stops. At boot that is the lowest-numbered enabled slot; after that it depends on what was stopped and started. An earlier draft said "lowest-numbered" from the measurements alone. The `ksapp` result disproves that: with wgc1 stopped on its own, the route went to no slot at all.

## Merlin's source (read 2026-11-12)

Tag `3004.388.13` of `RMerl/asuswrt-merlin.ng`, files `release/src/router/rc/wireguard.c` and `release/src/router/libovpn/amvpn_routing.c`. Read to check the measurements, and each point below matches what was measured.

- **Rule numbers are by design.** A comment in `amvpn_routing.c` allocates the ranges: WAN 10010-10209; WGC 1 11210-11409, WGC 2 11410, WGC 3 11610, WGC 4 11810, WGC 5 12010-12209; WireGuard kill switch 12215-12219, one per slot. So a lower slot beats a higher one, for every rule, by design.
- **DNS server routes: the first slot to start wins.** `_wg_client_dns_setup()` runs `ip route add <server> dev wgcN` in the main table for each of the slot's DNS servers. `add` fails if the route exists, so a second slot with the same server adds nothing. `start_wgcall()` starts slots 1 to 5 in order, so at boot the lowest enabled slot wins. When a slot stops, its interface goes and the kernel drops the route with it; no other slot adds it back until that slot restarts. That fits every measurement: `slots` (wgc1), `ks1down` (the page restarted every enabled slot, by then only wgc5, so wgc5), `ks1up` (both restarted, wgc1 first), `ksapp` (wgc1 stopped alone: none), `ksappup` (wgc1 started: wgc1).
- **A slot's table copies the main table when the slot starts** (`_wg_config_route`, "copy from main"). So a slot started after another copies the other's DNS server route: `9.9.9.9 dev wgc1 table wgc5`. A device routed through wgc5 whose DNS goes to 9.9.9.9 would leave through wgc1. Read from the routes and the source; not yet shown with `ip route get`.
- **DNS chain order is start order.** `wgc_set_exclusive_dns()` writes `/etc/wg/dnsN.sh`, which inserts the slot's `DNSVPN` jump at the top of PREROUTING (`-I`), after `amvpn_clear_exclusive_dns()` deleted the old one. So the slot started most recently is checked first. A device pinned to wgc1 inside a whole-LAN wgc5 rule matches both slots' chains; after wgc5 is restarted on its own (a watchdog rebuild, say), its DNS would go to wgc5's servers while its traffic stays on wgc1. That matters only when the two slots use different DNS servers, such as a family filter on one. Not measured.
  - Corrected 2026-11-13: only partly right. On the rebuilt router (step 3a), a web-page Apply started wgc1 then wgc5, and `DNSVPN6` (wgc1) stayed first, not `DNSVPN10`. The reading that fits, from the source: after the tunnels start, the firewall restart runs `run_wgc_fw_scripts()` (`wireguard.c`), which runs each slot's `dnsN.sh` from wgc5 down to wgc1, so wgc1's jump is inserted last and ends on top. So after a full restart the lowest slot is checked first; a slot started on its own (the app's ENABLE, a watchdog rebuild) goes on top until the next firewall restart. Inferred from one measurement and the source.
  - Corrected again 2026-11-13, step 11c, and now settled: **the chain order is always lowest slot first.** `start_wgc()` ends by calling `amvpn_update_exclusive_dns_rules()` (`amvpn_routing.c`), commented "Recreate the port 53 PREROUTING rules to ensure they are in the correct order", which deletes and re-inserts every slot's jump from wgc5 down to wgc1. The call was at `wireguard.c` line 1535 and was read past, not into. Measured: the app's ENABLE restarted wgc5 alone and `DNSVPN6` stayed first. So a device in two slots' rules has its DNS rewritten by the lower slot's chain, the same slot that wins its routing. The risk above (a pinned device taking another slot's DNS servers) doesn't arise.
- **Stop** (`stop_wgc`) clears the slot's VPN Director rules, flushes its table and removes its DNS chain, which is the ID-567 leak once `wgcN_enable=0` keeps it from coming back.

## ID-556 direction (Andrew's decision, 2026-11-13)

Andrew wants stock and Merlin to give users the same recommendations, so nothing reads differently between them. Recommended on 2026-11-13 after the remeasurement; Andrew agreed the direction the same day ("It sounds really good"). The design detail (hook rules and their priorities) is written after ID-569, and Andrew gives it a go before code.

### The promises users see, the same on both firmwares

1. Put the VPN you use most on wgc5 and make it the default; lower slots for other regions. README 5.2.1 already says so.
2. A device pinned to a tunnel gets that tunnel or nothing: through a rebuild, an expired configuration and DISABLE, which warns first and names the devices. Stock's promise today.
3. A pinned device's DNS goes through its own tunnel.
4. Renaming a device renames it everywhere the router shows it.

None of them mentions VPN Director, slot numbering or copied routes. The work is making Merlin keep the same four.

### How the app keeps them on Merlin

- **Default and pins.** DEVICES writes the default as one whole-network VPN Director rule (`192.168.x.0/24`), so devices that join later are covered, and each pin as its own rule (a WAN rule for a pin to Internet). A pin to a slot numbered higher than the default's is refused, with a message pointing to promise 1, because Merlin would silently ignore it: the lower slot always wins (Merlin's priority ranges). Anyone following promise 1 never sees the refusal.
- **One hook script does the guard's work.** Merlin runs `/jffs/scripts/wgclient-start <unit>` at the end of `start_wgc()` and `wgclient-stop <unit>` at the start of `stop_wgc()` (`wireguard.c`, `run_custom_script`). The app already appends to Merlin's `services-start` for the watchdog and sets `jffs2_scripts=1` (`router_watchdog.dart`), so this is the same mechanism, not a new one. Three jobs:
  - remove other slots' DNS server routes copied into this slot's table (promise 3; the cross-slot DNS measured 2026-11-13);
  - hold the addresses the slot's table sends to the WAN, the router's own DNS servers among them, to the tunnel for routed devices (ID-574, as ID-347 does on stock);
  - keep a disabled slot's devices offline until it's enabled again or they're moved (ID-567; promise 2). Merlin's `amvpn_clear_routing_rules()` deletes rules in its own priority ranges (10000 to about 12220), so the app's rules sit outside them; whether they survive is one of ID-569's measurements.
- **The router's own address is exempted** whenever DEVICES writes a whole-network default: `from <router's LAN address> lookup main` below Merlin's ranges (9990 in run E), re-added at boot with the app's other rules. Without it the kill switch cuts the router off from its LAN while the default's tunnel is down (run E). The exemption matches only packets the router sends from its LAN address.
- **Rule descriptions:** the web page refuses `<`, `>`, `'` and `%` ("<,>,',% are invalid characters"; `<` and `>` separate the file's records and fields), and accepts spaces and brackets (Andrew's own rules, 2026-11-13). DEVICES refuses the same four when it writes a rule, and reads a description as everything between its separators.
- **Rename** writes `custom_clientlist` and the reservation's `dhcp_staticlist` name, as the app does on stock (promise 4). Merlin's page writes only the first (step 7).
- **ID-572 mostly fixes itself:** with the copied route removed, the watchdog's probe needs only Merlin's table names (`wgc1` to `wgc5`) in place of stock's numbers.
- **DNS Director: supported, not required, not in README's advice.** It sends every device's plain DNS to one place, which helps with gadgets that have a DNS server built in, and does nothing against DoH. Merlin users may already have it on, so DEVICES must work alongside it. Both it and VPN Director rewrite port 53 in PREROUTING; from the source, VPN Director's `DNSVPN` jumps are re-inserted at the top on every slot start, so routed devices should keep their tunnel's DNS. To measure in ID-569 with "Router" mode on, not assume. For Andrew's own network: worth switching on if that measurement shows it plays well with VPN Director.

### Order of work

1. ID-569 on the router: the reboot, a rules file edited over SSH, DNS Director's interaction, and an app rule from `wgclient-stop` surviving Merlin's clean-up.
2. ID-556's detail written here, then Andrew's go.
3. ID-557 (DEVICES on Merlin), ID-574 and ID-567 each with a `check-claims.sh` check seen failing first, ID-571, ID-558, ID-572. ID-570 (the widget's "Not checked") can go any time.

### ID-569: what the source predicts (read 2026-11-14)

Read through from `3004.388.13` before the runs, so each run confirms or contradicts a stated prediction.

- **A rules file edited over SSH.** `service restart_vpnrouting0` (`services.c`, the `vpnrouting` handler, unit 0) re-applies the WAN rules, then for each WireGuard slot from 5 down to 1 its kill switch, its routing rules and its DNS chain. So an edited `vpndirector_rulelist` takes effect on that call and not before; the page reads the same file, so it should show the edit.
- **What Merlin deletes.** `amvpn_clear_routing_rules()` deletes only rules numbered 10000 to 12210 whose action is `lookup` of that slot's table; `amvpn_clear_killswitch_rules()` deletes only its slot's one priority, 12214 + slot. A rule the app adds at any other priority, or one whose action isn't `lookup` (`prohibit`, `blackhole`), is never touched.
- **Why ID-567 leaks, read through.** `amvpn_set_killswitch_rules()` for WireGuard first clears the slot's prohibit rules, then returns without re-adding them when `wgcN_enforce` or `wgcN_enable` is 0. So switching a slot off removes its kill switch by design.
- **A simpler ID-567 fix than a hook, to test.** If the app keeps its own `prohibit` rule per pinned device at a priority between Merlin's kill switch (12219) and `main` (32766), say 12300, it is never deleted by Merlin. While the slot's table has routes, the device's `lookup wgcN` rule (11210 up) matches first, so the app rule never acts; when the slot is off or down, the lookup falls through and the app rule blocks it. That's stock's guard shape (ID-213: `lookup` at 90, `blackhole` at 91). It needs re-adding at boot (Merlin's `services-start`, which the app already uses). Open: a whole-network default would then block the whole LAN while its slot is off, which promise 2 covers only for pinned devices; a design question for ID-556.
- **Boot.** `start_services()` (`services.c`) logs "Initializing killswitch" and sets every enabled slot's kill-switch rules early in boot; `wan_up()` (`wan.c`) sets them again once the WAN has its default route, before `start_wgcall()` starts the tunnels and adds the VPN Director `lookup` rules. So with the kill switch on, a routed device should be blocked from before the WAN is up until its tunnel starts: no leak. With it off, there are no rules for the device between the WAN coming up and the tunnel starting, so it should leak for that gap, which `start_wgcall()` lengthens by waiting for the clock to be set. The kill-switch-off run is the check seen failing.
- **DNS Director.** Its `PREROUTING` jumps to `DNSFILTER` are appended at the end when the firewall is built (`firewall.c`, `dnsfilter.c`), for `-i br+` port 53; VPN Director's `DNSVPN` jumps are inserted at the top on every slot start. So a routed device's lookups are rewritten to its tunnel's DNS first and never reach `DNSFILTER`; a device with a WAN rule or no rule passes `DNSVPN` (`RETURN`) and is rewritten by DNS Director. Not yet measured.

### ID-569 run A: a rules file edited over SSH (2026-11-14), as predicted

- The desktop's switched-off rule turned on by editing `/jffs/openvpn/vpndirector_rulelist` with `sed`. The edit alone changed nothing but the file. `service restart_vpnrouting0` then applied it within seconds, without restarting a tunnel: `12010: from <desktop> lookup wgc5`, `12219: from <desktop> prohibit` (wgc5's kill switch on), and the desktop's DNAT in `DNSVPN10`. The web page then showed the rule ticked.
- **Merlin renumbers on each apply:** the whole-network rule moved from `12010` to `12011`, its number following its place among wgc5's records in the file. DEVICES reads rules by content (source, interface), never by number.
- So DEVICES on Merlin can write the file and call `service restart_vpnrouting0`, as the app's watchdog already does after a start.

### ID-569 run B: an app-owned `prohibit` at 12300 (2026-11-14), prediction half wrong

- Rule `12300: from <tablet> prohibit` added by hand, with the tablet on wgc1 by its own rule and every device on wgc5 by the whole-network rule (`12011`). Watchdogs were running on both slots.
- **Survived, as predicted:** through `restart_vpnrouting0`, the app's DISABLE on wgc1 and the app's ENABLE. Merlin deletes nothing outside its own `lookup` rules and its kill-switch numbers.
- **Didn't block, against the prediction:** with wgc1 off, the tablet's `lookup wgc1` fell through to the next matching rule, the whole-network `12011 lookup wgc5`, before reaching 12300; it went `dev wgc5` and loaded websites through Melbourne. Not an internet-provider leak, but promise 2 broken: a device pinned to one tunnel used another. The prediction ignored the broader rule between the two. (The tablet is Wi-Fi only, so mobile data plays no part.)
- **Corrected placement, to test:** the block rule goes at the end of the pinned slot's own number range, 11010 + 200 x slot + 199 (wgc1 11409, wgc5 12209), so it comes after every Merlin rule for that slot and before every rule for any other slot, the whole-network default included. Merlin numbers its rules up from the bottom of the range and deletes only `lookup` rules there, so a `prohibit` at the top should neither collide (short of 199 rules on one slot) nor be removed.

### ID-569 run B again: the `prohibit` at 11409 (2026-11-14), as predicted

- `11409: from <tablet> prohibit`, with the same rules as before. Survived `restart_vpnrouting0`, the app's DISABLE and ENABLE on wgc1.
- **With wgc1 off, the tablet was blocked:** `ip route get` from it gave `RTNETLINK answers: Permission denied`, and it had no internet. With wgc1 back on, it went `dev wgc1` (New Zealand) again, the rule never acting while the tunnel had routes.
- Run B at 12300 is the same check failing: the tablet left through wgc5. So a pinned device stays on its tunnel or nowhere through a DISABLE, with no hook script: **ID-567's fix is one app-owned `prohibit` per pinned device at 11010 + 200 x slot + 199**, re-added at boot (Merlin's `services-start`, which the app already uses). The `check-claims.sh` check is still to write (ID-567's DoD).
- Unchanged in the ID-556 direction, but simpler: the `wgclient-start`/`wgclient-stop` hook is now needed only for promise 3 (removing copied DNS routes) and ID-574, if at all. To revisit when ID-556's detail is written.

### ID-569 run C: DNS Director (2026-11-14)

- The desktop given a WAN rule, and a lookup sent straight to 8.8.8.8 from it, read in `/proc/net/nf_conntrack`. DNS Director off: answered by 8.8.8.8, out through the WAN. On, Global Filter Mode "Router": answered by the router (`src=<router>` in the reply). As predicted.
- `PREROUTING` with DNS Director on: both `DNSVPN6` and `DNSVPN10` jumps first, then `-i br+ ... -j DNSFILTER` appended; `DNSFILTER` holds one `DNAT --to-destination <router>`. As the source says.
- The tablet's half, run separately with DNS Director still on (and the desktop's rule back on WGC5): a lookup from the tablet to the router, `dport=53`, answered by `9.9.9.9` with the reply to wgc1's tunnel address. **A routed device keeps its tunnel's DNS with DNS Director on**, as predicted: VPN Director's `DNSVPN` rewrite comes first.
- So DNS Director and DEVICES work together: routed devices use their tunnel's DNS; devices on WAN or with no rule have plain DNS forced to the router, which sends it on encrypted. Recommended to Andrew for his own network; for users, supported and not required (ID-556 direction).

### ID-569 run D: the reboot (2026-11-14), the control didn't fail

`scripts/check-reboot.sh` from the desktop (routed to wgc5 by its own rule and the whole-network rule), key login from WSL, DNS Director on.

- **D1, wgc5's kill switch off (the control, predicted to leak): PASS.** 126 probes, 59 blocked, 67 through the tunnel, 0 through the WAN; router back by 60 s, the tunnel carrying the desktop at 62 s. One `prohibit` rule after the boot (the tablet's, wgc1's kill switch), so the desktop had none.
- **D2, kill switch on, three runs: PASS each**, 0 through the WAN; back by 160, 200 and 200 s, the tunnel at 160, 201 and 200 s.
- **So the check hasn't been seen to fail on Merlin**, and the three passes aren't yet evidence that the kill switch protects the boot. The prediction missed something in the source: `start_wgcall()` is called from `wan_up()` itself (`wan.c`), shortly after the default route is added, so any window with no rules may be far shorter than the probe's one second. Unless `start_wgcall()` waits for the clock (`_wait_time_sync`), when it installs a job and returns.
- **Boot time differed:** 60 s in D1 against 160 to 200 s in each D2 run. One against three; unexplained.
- D1's boot in the syslog (router clock, "Jan 1 11:00" until NTP set it): "Initializing killswitch" 11:00:17; the app's `services-start` 11:00:21, before the WAN; "WAN was restored", multi routes added and "Applying all killswitches" 11:00:29; ntpd started 11:00:33; "Initial clock set" 17:02:05; VPN Director's rules and "Starting client 1" and "client 5" 17:02:06. So the tunnels waited for the clock, and by an estimate across the two clocks the WAN was up about 35 s before any rule existed for the desktop. With its kill switch off, the source says it should have leaked for that long; the check counted 59 probes blocked and none through the WAN.
- Two readings fit, not yet told apart: (1) the check counts any answer other than the WAN address read *before* the reboot as "tunnel", so a WAN address that changed at the reboot would hide a leak (the address does change: it differed between 2026-11-13 and 2026-11-14); (2) something blocked forwarding until the clock was set. If (1), stock's GRD-7 passes were read the same way and need rechecking. A read-only block (WAN address now, DHCP lines) settles which.
- **Settled: (1).** The router's WAN address after the four reboots differed from the one in the connection table before them, so at least one reboot changed it; and the script's "tunnel" count would have taken a leak through the new address. D1 and D2 are void. `check-reboot.sh` now records the address that answered each probe and counts only the tunnel's own exit address as the tunnel, the WAN address before or after the reboot as a leak, and any other address as a failure named in the output; tests for each case, seen failing on the old script. Stock's GRD-7 passes were read the same way (ID-578). D1 and D2 to repeat with the fixed script: D1 predicted to fail for about 35 s, D2 to pass.

### ID-569 run D again, with the fixed check (2026-11-14)

- **D1, wgc5's kill switch off: FAIL**, the desktop's traffic leaving by the WAN for 8 s (62 to 69 s), through the address the router got at that reboot. The check seen failing. (The 35 s estimate came from joining two clocks; the measurement is 8 s.)
- **D2, kill switch on: PASS three times**, none through the WAN; in run 1 the WAN address changed at the reboot, so the fixed check was exercised. **Merlin's kill switch holds a routed device offline through a reboot**, measured failing without it and passing with it. The app's `services-start` runs about 8 s before the WAN is up (D1's syslog), so its own rules (run B's 11409 shape) could also be in place before the WAN.
- **The router can't reach its own LAN until the tunnel is up, with the kill switch on and a whole-network rule (inference, to measure).** "Back on a new boot" (the desktop's first SSH login) came at 160 to 200 s in all six kill-switch-on runs, each in the same second as the tunnel's first answer; at 60 s in both kill-switch-off runs. The reading that fits: the whole-network rule `from 192.168.1.0/24` also matches packets the router sends from its own LAN address, and its kill-switch rule `12219: from 192.168.1.0/24 prohibit` blocks them while wgc5's table is empty. If so, at every boot and every rebuild of the default's slot, the router answers nothing on the LAN: SSH, the web page, the app, and DNS from dnsmasq for every device. DEVICES' default is that rule, so ID-556 needs the router's own address exempted (a `from <router's LAN address> lookup main` rule below Merlin's ranges), if confirmed.

### ID-569 run E: the router cut off from its own LAN (2026-11-14), confirmed

- wgc5 stopped for a few seconds by `service "stop_wgc 5"` (enabled, kill switch on, as a watchdog rebuild does), run in the background on the router so it finished while SSH was cut off. `ip route get <desktop> from <router's LAN address>`: wgc5 up, `dev br0`; **wgc5 stopped, `RTNETLINK answers: Network is unreachable`** with both `12219` rules present; wgc5 stopped with `9990: from <router's LAN address> lookup main` added, `dev br0`; wgc5 back and 9990 removed, `dev br0`. (Run B's forwarded case read "Permission denied"; the router's own packets report a `prohibit` as "Network is unreachable", as understood, not read in the kernel today. Either way not sent.)
- **Confirmed: a whole-network VPN Director rule with its slot's kill switch on cuts the router off from its LAN whenever that slot's table is empty**: about two minutes at each boot (run D's 160 to 200 s), and each stop or rebuild. DNS from dnsmasq, the web page, SSH and the app all go, for every device. Merlin's own behaviour; the exemption rule fixes it, seen failing without and passing with.

### ID-569 closed

Every measurement done: A (a shell-edited rules file applies on `restart_vpnrouting0`), B (an app-owned `prohibit` at the top of the slot's range holds a pinned device through DISABLE), C (DNS Director works alongside), D (Merlin's kill switch holds through a reboot, the check seen failing and passing, `check-reboot.sh` fixed on the way), E (the router's own address needs exempting from a whole-network rule). "A rule added from `wgclient-stop`" was overtaken by B: no hook needed for it.

### Superseded: precedence, as recommended 2026-11-12

Kept so the reasoning isn't rediscovered. The first item above replaced it.

Andrew wants stock and Merlin to follow the same process and explanation. README 5.2.1 already tells stock users to put their main VPN on wgc5 and work downwards. On Merlin that advice is also what makes pins behave as on stock: with the default on the highest-numbered slot in use, every pin to a lower slot or to Internet outranks it. Recommendation, not yet decided:

- Same advice on both: main VPN, and so the default, on wgc5:pia-aus_melbourne.
- On Merlin, the default is one whole-LAN rule, so new devices are covered as on stock. A rule per device instead would leave a device that joins later outside the VPN.
- The one combination Merlin can't honour, a device pinned to a slot numbered higher than the default's, is refused in DEVICES with a line saying why, rather than written and silently overridden. With the default on wgc5 it can't arise.
