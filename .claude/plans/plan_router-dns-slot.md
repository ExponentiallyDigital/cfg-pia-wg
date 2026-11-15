# Choosing what carries the router's own DNS (ID-594)

Reasoning and design only; status lives in BACKLOG and CHANGELOG. Written 2026-11-15, from Andrew's question on how to send the router's own lookups to 9.9.9.9 and 149.112.112.112 through wgc5:pia-aus_melbourne rather than wgc1:pia-nz. Rewritten the same day, after the measurements below changed what the item is for.

## What the day's measurements showed

All on Merlin 388.13_0, 2026-11-15.

- **A slot's DNS servers pull the router's own traffic to those addresses into that slot.** With wgc1 on Cloudflare's 1.1.1.2 and 1.0.0.2, the servers the router's own DNS-over-TLS uses, every one of stubby's connections went through wgc1 to New Zealand, and so did wgc5's watchdog's encrypted lookups to 1.1.1.2. Moving wgc1 to other servers sent both back over the WAN.
- **Nothing on the router used the route it was first asked about.** With wgc1 and wgc5 both on Quad9 and the router's own DNS on Cloudflare, the only router traffic to Quad9 was each watchdog's test lookup, through its own slot by its rule at 1000. The route into wgc1 that ROUTER DNS ROUTING reported carried nothing (ID-610).
- **So the first version of this item solved a problem Andrew didn't have.** Choosing between slots that share DNS servers matters only when the router's own DNS servers are among them. What he wanted was the router's own DNS through wgc5, his nearest exit, and that is decided today by which slot happens to list the router's DNS servers as its own.
- **How he has it now, with no new code:** wgc5's DNS servers are the router's own DNS-over-TLS servers, 1.1.1.2 and 1.0.0.2, no other slot uses them, and neither watchdog's encrypted DNS is a slot's server. Measured after the change: the router's DNS-over-TLS through wgc5, every device's lookups through wgc5, the tablet's through wgc1, both watchdogs' encrypted lookups over the WAN.

## The problem, as it stands now

What carries the router's own DNS is a side effect of two settings that look unrelated: the router's DNS servers (the DNS Server setting, or DNS-over-TLS in `dnspriv_rulelist`) and each slot's DNS servers. Nothing in the app or the web interface asks the question directly.

- **Merlin:** as it starts each slot, Merlin adds routes to that slot's DNS servers to its main table, through that slot's tunnel. The first slot to start gets the route, and a later slot with the same servers doesn't replace it. After a boot that's always wgc1, though it can change at any restart (ARCHITECTURE 6.10, "DNS").
- **Stock:** the firmware's rules at 1016 to 1029, `from all to <dns> iif lo lookup <table>`, send them through the highest-numbered slot sharing the address (ARCHITECTURE 6.8.12, runsheet AN-2026-09-19_001).

The side effect reaches further than the router's resolver. Anything on the router that talks to one of those addresses follows the same route, a watchdog's encrypted DNS included, which then depends on a tunnel it may be trying to rebuild (ID-609 adds the warning for that).

## The design

The user chooses, on ROUTER DNS ROUTING, what carries the router's own DNS: the firmware's choice (today's behaviour), a named slot, or the internet connection. The app then owns one routing rule for each of the router's own DNS server addresses, and the guard puts it back.

```sh
ip rule add to 1.1.1.2 iif lo lookup <table> priority 1010
```

- **The table, for a slot:** on Merlin, the slot's own table, `wgc1` to `wgc5` (116 to 120). On stock, `10 - slot`.
- **The table, for the internet connection:** a rule into `main` can't beat the route Merlin put in `main`, so the app keeps a table of its own holding only the WAN's default route, and the rule points there.
- **The priority:** rules are checked lowest number first, so 1010 comes before stock's own rules at 1016 to 1029 and before Merlin's main table. It comes after the watchdog's test lookup at 1000 (ID-078), ENABLE's ping on stock at 1002 (ID-396, `router_slot_service.dart`) and NETWORK's lookup at 1003 (`kTunnelLookupPriority`), so each still tests its own tunnel.
- **Only the router's own traffic:** `iif lo` matches what the router itself sends. A device's lookups are forwarded, so they keep following VPN Director or VPN Fusion.
- **If the chosen slot is down:** its routing table is empty, so the rule matches nothing and lookups fall back to what the firmware does today. They go through another slot or out the internet connection; they don't fail. Recommended, to be confirmed by Andrew: blocking instead could cut the router off from name lookups exactly when a watchdog needs them.
- **The watchdogs' encrypted DNS stays out of it.** A watchdog must reach its DoH server without the tunnel it watches. The rule covers the router's resolver addresses only, and the app refuses, or warns, when one of them is also a watchdog's DoH address and the choice is that watchdog's own slot.

### Measured, 2026-11-15

With wgc1 holding the main-table route to 9.9.9.9:

- `ip rule add to 9.9.9.9 iif lo lookup wgc5 priority 1010`: `ip route get 9.9.9.9` moved from `dev wgc1` to `dev wgc5`, a lookup sent to 9.9.9.9 answered, and the router's connection table showed it leaving by wgc5's address.
- A table holding only the WAN's default route, and the same rule pointing at it: `dev eth0`.
- With each rule deleted, `dev wgc1` again.

One run each. Not yet seen: the rule through a reboot, a slot restart, or with the chosen slot stopped.

### Where it goes in the app

ROUTER DNS ROUTING, beside the line for the router's own lookups: a choice of "the firmware's choice", each configured slot, or "your internet connection". The choice is saved on the router, so the scripts can read it at boot without the app. The screen is read-only today, so this is its first control; an alternative is SETTINGS.

### Keeping the rule in place

- **Merlin:** the WAN coming up clears every rule (`add_multi_routes()`, ARCHITECTURE 6.10), so `merlin-guard.sh` puts this rule back wherever it already puts back its others: at boot, during the boot watch, and from `wgclient-start` as each tunnel starts. The WAN-only table is rebuilt at the same points, since the WAN's gateway can change.
- **Stock:** the same treatment as the app's other rules there, through its boot hook.
- **Both:** the rules follow the router's DNS servers, so a change to those in the web interface is picked up the next time the guard runs. They are removed when the choice goes back to the firmware's, when the chosen slot is deleted, and at UNINSTALL.

### What else changes

- ARCHITECTURE 6.8.12's rule table gets a row for priority 1010.
- The screen's line for the router's own lookups says what carries them and why: the firmware's choice, or the user's.
- The MANAGE, EDIT warning about sharing the router's DNS addresses says the chosen route wins.
- CONTEXT.md section 1's "The app never changes the DNS settings the user made in the router's WebUI" still holds: this changes a route, at the user's request, and no DNS setting.

### Not part of this item

Left out on 2026-11-15, Andrew's decision ("That sounds too risky"): leaving a slot with no DNS servers of its own so that every device uses the router's encrypted DNS, which would close the unencrypted stretch between PIA's server and the DNS provider. EDIT refuses an empty DNS field, and the app would have to hold every device's lookups to the tunnel by this rule alone.

### Tests

- **Unit tests:** the script text, the guard against a fake `ip`, and the screen's goldens.
- **A check in `check-claims.sh`:** `ip route get <address>` shows the chosen route; stopping the chosen slot shows the fallback; deleting the rule by hand makes the check fail.
- **A hand test in TESTING:** on each firmware, through a reboot.

## Open decisions, Andrew's

1. **Whether to build it.** The setup above already sends his router's DNS through wgc5 with no new code. The item earns its place if that arrangement proves fragile, or if users can't be expected to work it out; ID-610's wording and ID-609's warnings may be enough.
2. **The fallback** when the chosen slot is down: fall through, as recommended above, or block.
3. **Where the choice lives:** ROUTER DNS ROUTING or SETTINGS.
