# DNS modes in SETTINGS (ID-621)

Not finalised. This is a proposal to put to users before anything is built. Reasoning and findings only; status lives in BACKLOG and CHANGELOG. Device names and LAN addresses are invented, as CONTEXT.md section 1 requires.

## The problem

A device pinned to a slot whose DNS servers are set has its lookups redirected to those servers, so the router's own names stop resolving on it. Measured on Merlin 388.13 on 2026-11-17:

- The firewall's NAT table sends every port 53 packet from the LAN to the slot's DNS server, to any destination. A phone pinned to a slot got `ERR_NAME_NOT_RESOLVED` for the router's name. The same lookup made on the router itself, against dnsmasq, resolved.
- dnsmasq answers local names, from its hosts file and DHCP leases, only to devices whose lookups reach it. A device with a per-slot DNS rule never asks it.
- Nothing in the app says so. The slot DNS setting reads as a privacy choice, not as "this device can no longer use the router's names".

Stock firmware has not been measured. Its rules are built differently.

## What people want

- Type a bare local name (`nas`, `printer`) in a browser and have it resolve.
- Have any external name resolve through a tunnel.
- Some want a different resolver for one device, such as a family filter on a child's tablet and full access on adult devices.

## Proposal: three modes in SETTINGS

1. **Per slot (today, the default for existing installs).** Each slot's DNS applies to the devices pinned to it. Per-device resolvers work. Bare local names don't resolve on those devices.
2. **One path for all.** Devices ask the router. dnsmasq answers local names and sends everything else out through the one slot the user picks, through the router-DNS routing that already exists. Bare local names work everywhere. There are no per-device resolvers.
3. **One path, plus device exceptions.** Mode 2, with chosen devices redirected to a resolver the user picks (a family filter, a malware filter). Those devices lose bare local names, and the screen says so beside each one.

Existing installs stay on mode 1 on update, with a notice pointing to SETTINGS. A DNS change is never made silently.

What happens when the chosen path is down is not an option. Lookups fail, never fall back to the WAN: the project's core requirement.

## Further options, in order of value

1. **Rebind-protection exceptions.** dnsmasq's `stop-dns-rebind` drops a public name that resolves to a private address, which breaks NAS and media-server names that people point at their LAN. A list of exempted domains.
2. **Split DNS by domain.** Send a named domain to a given resolver, everything else the normal way.
3. **Custom local names.** Add entries to the router's hosts list from the app, for devices with no DHCP hostname.
4. **Which networks the mode covers.** Guest networks, and the DNS a WireGuard server client gets when it connects home.
5. **DNSSEC on or off.** Now on, and a known cause of failed lookups with some upstreams.
6. **Block a device's own encrypted DNS.** Android's Private DNS and Chrome's Secure DNS skip every setting above. Port 853 is already blocked for the router's clients; known DNS-over-HTTPS servers are not.
7. **IPv6 answers.** Whether the router returns AAAA records when a tunnel carries only IPv4. An idea only: not measured.

Left out: ad and tracker lists (Pi-hole's job), a DNS leak test (declined), and a fallback to the WAN.

## What was measured, 2026-11-17, Merlin 388.13

- dnsmasq 2.93 takes an upstream per domain (`--server=/domain/ip`) and has no form for one per client. Per-device resolvers therefore need a redirect, never dnsmasq alone.
- The kernel has the iptables `string` and `u32` matches, and ASUS's own rules use `--hex-string`. A redirect could skip `*.int.example.lan`, but not a bare name, which carries no domain to match, so this doesn't replace mode 2.
- Merlin's firewall lists the app's DNS chains as `DNSVPN<slot>` in the NAT table, each matching a source address.

## Not yet measured

- What the router's own lookups do while their slot is down. Mode 2 depends on it.
- Anything on stock firmware.
- Whether a given phone sends a bare name as typed or adds the DHCP search domain first. Both resolve under mode 2, so it matters only to a redirect that tries to skip local names.

## A caution

A DNS filter on a child's tablet is bypassable: a VPN app, a different browser setting or a hotspot gets around it. The setting must be called a filter, not parental control, and any wording that claims protection needs a check that breaks it, under CHANGELOG's rule.

VPN Director in Merlin may help here by forcing named devices to use specific name resolvers.

## Questions to ask users

For r/WireGuard-style forums and the Merlin forum, before building:

1. Do you type bare hostnames (`nas`, `printer`) on your LAN, and do they work for devices behind a VPN?
2. Do you need different DNS resolvers for different devices, or is one external resolver for the whole LAN enough?
3. If you filter DNS for some devices (children's tablets, say), what do you use today, and does it matter that those devices lose bare names?
4. Which of these have you hit: names that resolve to a LAN address being dropped (rebind), a work domain needing its own resolver, guest-network or remote-client DNS?
5. Would you rather have three clear modes, or a toggle for each choice?
6. Should lookups fail when the tunnel is down, or fall back to your ISP? (The app's answer is that they fail. Do you disagree?)

## Order of work

1. A line in the slot DNS field's helper text now: devices using the slot's DNS can't look up the router's names. A small, certain change that helps today's users whatever is decided.
2. Measure the unmeasured above, on Merlin and stock.
3. Ask the questions above and record the answers here.
4. Finalise the modes, then split this into work items.
