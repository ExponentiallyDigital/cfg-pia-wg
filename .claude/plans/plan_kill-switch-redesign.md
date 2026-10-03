# Plan: a stock kill switch built the way Merlin builds one

**Status:** AGREED 2026-10-03, measured on hardware and built for build 491 the same day. GRD-9 (`scripts/check-claims.sh quick`, two tunnels pinned) passed on hardware the same day, 33 checks and 0 failed; no `asd` crash in the 2 hours after it; after a reboot, `check-claims.sh dry` at one minute of uptime passed every guard check. Done. Tracked as ID-364. ARCHITECTURE.md 6.8.10 describes the design as built and is the current state; this plan is the record of why, and "As built" below says where the build departs from it.

## The end state

A pinned device gets its tunnel or nothing, and nothing has to keep running to make that true.

- **Two rules per pinned device**, added when it is pinned and left alone until it is unpinned:
  - `90: from <device> lookup <200 + slot>` - our table for that tunnel
  - `91: from <device> blackhole` - reached whenever that table cannot route it
- **One table per tunnel, defined by what it never holds: a route out of the WAN.** It carries the tunnel's default and the router's own local routes, and nothing else. When the tunnel is down, rebuilding or switched off, the table is empty and rule 91 blocks the device.
- **The guard runs when something happens, never on a timer:** at boot, on the boot hook's `firewall-start`, after the app's own actions, and once after a watchdog rebuild.
- **The NVRAM filter (ID-348) stays** as the backstop for the two windows no rule can cover.

## Why

A cron job every minute is repair after the fact. It accepts a window in which the protection is gone and closes it by repetition. Merlin doesn't work that way, and on stock the cron has cost us three things.

- **Complexity.** `guard.sh` is 281 lines. For six pinned devices it keeps 72 rules, 60 of them at priorities 88 and 89, and a run that changes nothing executes 2167 commands.
- **Staleness.** Rules 88 and 89 are built from the WAN routes a tunnel's table held when the guard last ran, so they fall out of date whenever the router's DNS servers or its WAN change.
- **The firmware's `asd` daemon.** Two guard runs about a second apart crash it, and at every watchdog tick the cron's run and the watchdog's run collide. In production that was a crash and a firewall restart about every 20 minutes (ID-361).

And the cron covers less than it seems to. The firmware wipes our rules in exactly two measured situations, a reboot and `restart_net_and_phy`, and the boot hook already handles the first.

## What Merlin does

Read from RMerl/asuswrt-merlin.ng on 2026-10-02.

- `amvpn_set_killswitch_rules()` in `libovpn/amvpn_routing.c` runs `ip rule add from <src> priority <KS> prohibit` for each VPN Director rule that sends a device to a WireGuard client. The priority sits after every lookup rule, and the whole thing is gated on `wgcN_enforce` and `wgcN_enable`.
- `amvpn_set_kilswitch_rules_all()` re-asserts every kill switch straight after `add_multi_routes()`, in `rc/wan.c`, `rc/wanduck.c` and `rc/rc.c` - in the same code path as the change that could open a leak.
- `stop_wgc()` removes the client's lookup rules and leaves the `prohibit` where it is, so stopping or rebuilding a client cannot open a leak.
- Its table is not clean. `_wg_config_route()` in `rc/wireguard.c` copies all of main, WAN default and WAN subnet included, then adds `0.0.0.0/1` and `128.0.0.0/1` via the tunnel, and `_wg_client_ep_route_add()` adds the endpoint's host route via the WAN. Merlin's safety comes from the rule lifecycle, not the table. Untested on Merlin, but on stock main itself holds host routes to the router's DNS servers via the WAN (measured 2026-10-03), so a table copied from main carries them, and a device's traffic to those servers would leave by the WAN while the tunnel is up - the class of leak ID-347 measured on stock.

We take the shape: a deny rule that stays put, after a lookup, kept true by events rather than a timer. We don't take the table. Ours holds no WAN route at all, which is stricter than Merlin's.

## What the design rests on

| Fact | Measured |
|---|---|
| Rules at 90 and 91 survive a tunnel rebuild and a DISABLE | 2026-09-24, run sheets FC, FG and FR |
| They survive `restart_firewall` | GRD-6, 2026-09-24 |
| `restart_vpnc`, `stop_vpnc`, `restart_vpnc_dev_policy`, `restart_dnsmasq` and `restart_vpnrouting0` leave policy rules alone - not even the firmware's own stale rule goes | 2026-09-10, ARCHITECTURE.md "Stock leaves the old routing rule behind" |
| `restart_net_and_phy` clears policy rules | 2026-09-10, same section |
| Routes in a tunnel's table are wiped by a rebuild or a DISABLE | 2026-09-24 |
| Stock calls the init scripts with `firewall-start` at boot, on `stop_vpnc` and on `restart_vpnc` - three times inside two seconds for the last | 2026-08-31, the capture in `.claude/testing/.watchdog-implementation/` |
| They're also called with `firewall-start` on `restart_vpnc_dev_policy` and `restart_firewall` (once each), a WAN reconnect (8 times over 18 s) and `restart_net_and_phy` (10 times over 26 s), with gaps of up to 9 s inside a burst | 2026-10-03, measurement 1 |
| With rules 90 and 91 and a table built this way, the kernel sends a pinned address's traffic for the internet, the WAN gateway and the router's DNS servers through the tunnel, and its LAN, guest-bridge and WireGuard-server traffic locally; with the table's default gone, the internet and DNS are refused and the LAN still answers | 2026-10-03, measurement 3, by `ip route get ... iif br0` for an address nothing on the LAN used |
| With the tunnel really stopped (`stop_vpnc`), its interface was gone within 0.26 s and our table's default with it, untouched, so the address was refused; with rule 91 removed its traffic went out of the WAN; `restart_vpnc` had the interface back in about a second, in the same second as the last of its three `firewall-start` calls, and the table stayed empty, so refused, until it was refilled; `wgcN_enable` was unchanged throughout | 2026-10-03, measurement 2 and the real tunnel-down test |
| After a reboot, the tunnel was already up when the hook was first called, at 29.6 s of uptime and before the clock had synced; three more `firewall-start` calls followed by 55 s, and stock's own `restart_wgc` retry job never appeared | 2026-10-03, the boot test |
| No call reaches the hook before the USB disk carrying it is mounted: the first came just after the mount, about 30 s into the boot | 2026-10-03, the boot test |
| Main holds host routes to the router's own DNS servers via the WAN, beside the default and the WAN subnet; the whitelist (`br`, `lo`, `wgs`, `tun`) copies every other route in it, and none of those | 2026-10-03 |
| Stock waits for those scripts, so anything slow in them holds up the VPN | the same capture: the VPN sat in "connecting" |
| Guard runs 1 to 2 seconds apart crash `asd` at 9 to 13% a run; 5 seconds or more apart, at 3 to 4% | 2026-10-02, ID-361 |

## Settled from source rather than measured

Read 2026-10-03, so none of these needed a test on hardware.

- **A background run doesn't hold the firmware up.** Stock's `app_init_run.sh` runs each init script in the foreground (`sh $s $2`) and waits for that script alone, so a guard run sent to the background with its output redirected leaves it free.
- **The hook depends on Download Master staying enabled.** On `start` and `firewall-start`, `app_init_run.sh` runs a package's script only while `app_get_field.sh <package> Enabled` says `yes`. True of today's boot hook as well; ARCHITECTURE should say so.
- **The stock originals the app keeps never answer.** `get_apps_name` turns `S50downloadmaster.old` into the package name `downloadmaster.old`, which isn't enabled, so on `start` and `firewall-start` stock skips it.
- **Stock's per-minute endpoint check never restarts our tunnels.** `check_wgc_endpoint()` skips any client whose endpoint is already an IP address, and the app always writes one.
- **The hook heals itself.** The app rewrites it from its own template on UPDATE WATCHDOG VERSION and when it deploys or stops a watchdog (`_refreshS50()` and friends), so the new hook comes back on its own - and anything added by hand is gone at the next refresh, as a test probe found out at 04:30 on 2026-10-03.

## Design

### Rules

One pair per pinned device, as above. A device pinned to a profile that no longer exists gets rule 91 alone, as today. Nothing else at 88 to 91.

### Tables

One per tunnel with pins, `200 + slot`, filled whenever the guard runs:

```sh
ip route flush table $T
ip -o link show up | grep -q " wgc$N:" || continue        # down: leave it empty, so 91 blocks
ip route show table main | grep -E ' dev (br|lo|wgs|tun)[0-9.]*( |$)' |
  while read -r R; do ip route add $R table $T 2>/dev/null; done
ip route add default dev wgc$N table $T
```

The local routes are a whitelist by device type - LAN and guest bridges, loopback, the router's own WireGuard and OpenVPN servers - so an interface nobody thought of is left out, which fails closed. A route copied from main via the WAN can't appear, because the WAN isn't on the list.

### Triggers

| When | How |
|---|---|
| Boot | the boot hook's existing `start` path |
| `firewall-start` | the boot hook backgrounds `guard.sh soon` and returns at once |
| The app's APPLY, DISABLE, DELETE, deploy, UPDATE WATCHDOG VERSION and UNINSTALL | directly, as today, because the screens report the result |
| A watchdog rebuild, once the tunnel is up | `guard.sh soon` |

`soon` turns a burst of events into one run, 10 seconds after the last. Ten, because the bursts measured on 2026-10-03 have gaps of up to nine seconds inside them, and a shorter wait splits a burst into two runs:

```sh
echo $$ > /tmp/cfg-pia-wg-guard.next; sleep 10
[ "$(cat /tmp/cfg-pia-wg-guard.next)" = "$$" ] || exit 0    # a later event will do it
```

There's no cron entry, and the watchdog no longer runs the guard on every check.

### Two rules for the design itself

1. **Correctness is static; events only restore service.** An empty table, a missed event, a tunnel that never came back: each leaves the device blocked, never let out.
2. **The guard never causes the event it listens to unless something changed.** A guard run that restarts the firewall raises `firewall-start`, which runs the guard. Today `lw_sync` restarts the firewall whenever its read-back comes up short; hung off `firewall-start`, that's a loop of firewall restarts. In the new design a restart is asked for only when the filter's NVRAM list actually changed, so the next run finds nothing to do and the chain ends.

## What it costs

- **A gap in service after a tunnel restart**, until the coalesced run refills the table. About ten seconds, and it fails closed: measured 2026-10-03, the tunnel was up in the same second as the last event, so the run finds it ready.
- **A WireGuard-server peer added after the guard last ran** has no route in the tunnel tables until the next event, so a pinned device's replies to it go into the tunnel: its remote access fails closed until then. Main holds these as one host route per peer, not one subnet.
- **Pins changed in the web interface** take effect at the next event rather than within a minute. Andrew's call, 2026-10-03: the README says so.
- **Unchanged from today:** non-tcp/udp traffic in the moments after `restart_net_and_phy` wipes the rules, which the filter can't cover, and IPv6, which hasn't been measured.
- **Also unchanged, and now written down:** the hook only runs while Download Master is enabled in the router's USB applications, so turning it off there silently stops the guard's boot run today, and every event in this design.

## Migration

On a router running the current guard: delete the `cfg_pia_wg_guard` cron entry and its line in the boot hook, delete every rule at 88 and 89, replace each rule 90 that looks up a firmware table with one that looks up ours, and drop the watchdog's per-check guard call with the next UPDATE WATCHDOG VERSION.

## Before building: four measurements

1. **Which events send `firewall-start`, and whether our rules survive each.** A `logger` line at the top of the deployed boot hook, then one of each: `restart_vpnc_dev_policy`, `restart_firewall`, a WAN reconnect, a VPN Fusion apply in the web interface, and `restart_net_and_phy`. Left in for a day, to catch what nobody thought of. **Done 2026-10-03:** every event known to wipe the rules or change routing calls the hook, as the facts above record. Whether `restart_net_and_phy` wipes our own rules wasn't settled, because no device was pinned at the time; the design doesn't depend on it, since the hook is called either way.
2. **Ordering.** After `restart_vpnc`, is the tunnel up when the last `firewall-start` plus five seconds arrives? A sampler started from cron, so an SSH logout can't kill it. **Done 2026-10-03,** in one run that stopped the tunnel for real, so it also proved the central claim: a stopped tunnel empties our table by itself, and the protection holds with no guard run at all. See the facts above.
3. **The table on hardware, with one device.** It reaches a public resolver through the tunnel, the LAN and the router's WireGuard server subnet still answer, and with the tunnel stopped nothing at all gets out. **Done 2026-10-03,** with routing decisions alone for an unused address, so no device was touched: every line came out as the design claims, as the facts above record.
4. **The boot.** Stock's source has a per-minute `restart_wgc` retry while the clock is unsynced, so a tunnel might come up after the hook's last call at boot and leave its table empty until the next event. **Done 2026-10-03:** it doesn't; the tunnel was up before the hook's first call. No boot step is needed.

Nothing else needs measuring before building. What's left is verifying the build itself: the breaking checks, a reboot with the real hook, and two tunnels pinned at once.

## The check that makes it done

The CHANGELOG rule for protection changes applies, and the check belongs in `scripts/check-claims.sh`. With a device pinned and its tunnel stopped, nothing from it may reach the internet by any protocol - seen to fail with rule 91 deleted, and to pass with it back. And with the tunnel up but its table's default deleted by hand, the same. Removing rule 91 with the tunnel up isn't enough to show a WAN leak on a router whose default connection is itself a tunnel: measured 2026-10-03, the traffic then went out through that tunnel instead. The WAN leak only shows with the tunnel stopped, which on such a router sends every device that follows the default out of the WAN while it's off, so the check needs a moment the user has chosen.

## As built

Built 2026-10-03, with the unit and harness tests passing. Where the build departs from the design above:

- **The table isn't flushed on every run.** `ip route replace` leaves a table that's already right untouched, so a run with nothing to do changes nothing, and a tunnel that's up never has an empty table while the guard refills it.
- **Every run takes out anything in the table it wouldn't have put there**, with the tunnel up or down: a route out of the WAN, put there by anything, can't outlive the next run. Added during the build, after writing the check showed that nothing removed a planted route. It also clears the two `/1` routes builds 480 to 490 kept in the same tables, `200 + slot`, for rules 88.
- **`lw_sync` no longer asks for a firewall restart when the filter reads back short**, only when its list changed: design rule 2. A short read-back is put right by the router's next firewall restart, since the list is already right in NVRAM.
- **Whatever writes the boot hook installs the guard first** (`_writeS50`, `_refreshS50`), so the hook never calls `guard.sh soon` on a guard too old to know `soon`, which would run in full on every `firewall-start` of a burst.
- **The check** (`scripts/check-claims.sh`, quick) wipes rule 90 and expects the router's own firewall restart to put it back; plants a WAN route in the table and expects the check to see it and the guard to take it out; empties the filter and expects the router's next firewall restart to rebuild it, with the restarts stopping by themselves; empties the table with the tunnel up and expects the device refused; and stops the tunnel, removing rule 91 for a moment to show the leak it stops. `GUARD-wgcN-back` times how long a pinned device waits after a tunnel restart.
- **The watchdog's alert email** counts a device as guarded when it holds rule 90 into `200 + slot` and rule 91, from the kernel, as before (ID-320).

## Out of scope

IPv6, until it's measured: it was off on the router every measurement here was made on, and the design, like today's, is IPv4 only. Merlin, which has its own kill switch (ID-353). Devices that follow the default connection rather than a pin, by design.
