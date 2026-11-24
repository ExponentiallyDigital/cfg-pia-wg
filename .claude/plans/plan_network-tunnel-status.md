# Tunnel status and speed on NETWORK (ID-600, ID-604)

Reasoning and design only; status lives in BACKLOG and CHANGELOG. Written 2026-11-15. Addresses in the mockup are invented.

## Where it goes

NETWORK, Andrew's decision, 2026-11-15. It already shows each tunnel's public address, asked of PIA through that tunnel, so each tunnel's card gains the rest:

```text
wgc1:pia-nz                               up
  203.0.113.7 · Auckland, New Zealand · PIA
  handshake 42 s ago · server 203.0.113.50
  since it started: 1.2 GB in, 310 MB out
  now: 3.1 Mbit/s in, 0.4 Mbit/s out
  speed: 87 Mbit/s down, 41 Mbit/s up (14:02)
                              [ TEST SPEED ]
```

- Line 2 is what NETWORK shows today.
- Lines 3 and 4 are ID-600, from `wg show`.
- Line 5 is the private version of a speed reading, below.
- Line 6 and the button are the speed test, ID-604.

## ID-600: status from `wg show`

On stock and Merlin: the age of the latest handshake, data received and sent since the tunnel started, and the endpoint, beside the watchdog's rebuilds from its log. The app already reads handshake ages (`kHandshakeAgesCommand` in `router_slot_service.dart`, DEVICES' tunnel health), so this extends a read the app already makes: `wg show wgcN transfer` and `wg show wgcN endpoints`.

## ID-604: a speed test for each tunnel

### What it measures

The router's own throughput through that tunnel to the test server. That depends on the router's CPU, which does the WireGuard encryption, the PIA server's load and the distance. It's the right figure for comparing slots. It isn't the speed a device gets over Wi-Fi.

### How it works

- **Routing:** NETWORK's lookup, `tunnelLookupCommand` in `network_lookup.dart`.
  - On stock, a rule for the one server address into the tunnel's table (10 minus the slot) at a priority of its own, 1004, after the watchdog's 1000, ENABLE's 1002 and NETWORK's 1003. Read back with `ip route get` before anything is sent, and taken out after. A route not through the tunnel is reported, never a test that might run by the WAN and look right. The hostname goes in the URL and the address in `--resolve`, because stock's curl refuses a URL whose host is an address (ARCHITECTURE 2, row 7).
  - On Merlin, `curl --interface wgcN`.
- **Download:** `curl -o /dev/null -w '%{speed_download}'` from the server's download URL, four streams at once, because one stream often falls short of a fast line. Each has a time limit.
- **Upload:** zeros piped to the server's upload URL, the same way.
- **One tunnel at a time,** so the tests don't compete with each other.
- **Data used:** about 25 MB down and 10 MB up per tunnel. TEST SPEED's confirmation states the total, and the result shows the time it was taken.
- **No test without a tunnel.** It would show the server the home address.

### The server, Andrew's decision

The usual free choice is Cloudflare's `speed.cloudflare.com/__down?bytes=N` and `/__up`. Through a tunnel, Cloudflare sees only that tunnel's PIA address, which many PIA users share, and never the home address. That's much less than a DNS leak test would hand over (ID-598), but it is still an outside party, and NETWORK's rule is that nobody new learns anything.

The option with no outside party is line 5 of the mockup: read `wg show wgcN transfer` twice, a few seconds apart, and show the rate. It shows how much a tunnel is carrying now, not how fast it could go.

### To measure first

On stock, a tunnel's table carries only `0.0.0.0/1`, so the server address has to be below 128.0.0.0 (`tunnelLookupAddress` in `network_lookup.dart`). Cloudflare's addresses for `speed.cloudflare.com` are believed to be above that. One of Cloudflare's lower addresses with `--resolve` may still answer for it, but that's unverified. One test on the stock router settles it before anything is built.

Built 2026-11-24 with Cloudflare, as ID-604's own line says. Its address is looked up on the phone like the PIA lookup's (`tunnelLookupAddress(host: ...)`), and only an IPv4 address below 128.0.0.0 is used; Cloudflare's `104.18.x.x` addresses are below it, which this note's earlier "believed to be above" got wrong in its favour, but no router has been asked. ID-696 tracks the run. Also unproven: the router's curl taking `--data-binary @-` for the upload, and the watchdog's restart lines (`Stopping wgcN`, `Restarting wgcN through VPN Fusion`, `No vpnc_clientlist row for wgcN`) being the only ones that mean a restart, read from `router_watchdog.dart`'s script text and not from a log. The no-outside-party option, the rate from two `wg show transfer` reads, was not built.

## Tests

- **Unit tests:** the router command for each firmware, the parsing of `wg show` and curl's output, and NETWORK's goldens.
- **A hand test in TESTING:** on stock and Merlin, the test runs through each tunnel. With the tunnel's route taken away, it reports the missing route rather than a figure from the WAN.

## Screenshots

NETWORK's card changes, so README's NETWORK image and both stores' screenshots need checking, and retaking where they show it.

## Work item detail, moved from BACKLOG.md (2026-11-24)

Moved verbatim on 2026-11-24: a work item line is at most two sentences (CHANGE-PROCESS.md section 3, `test/unit/work_item_length_test.dart`), and these items' lines were longer. Nothing was cut.

### ID-600

```text
- ID-600 ADD: status for each slot from `wg show`, on stock and Merlin: the age of the latest handshake, data received and sent, and the endpoint, beside the watchdog's rebuilds from its log. The app already reads handshake ages (`kHandshakeAgesCommand`, DEVICES' tunnel health). Shown on NETWORK, beside each tunnel's public address (Andrew, 2026-11-15). Raised 2026-11-15.
  - Plan: [plan_network-tunnel-status.md](.claude/plans/plan_network-tunnel-status.md)
```

### ID-604

```text
- ID-604 ADD: a speed test for each tunnel on NETWORK, on stock and Merlin: the router downloads and uploads a fixed amount through each tunnel in turn, and the card shows Mbit/s each way with the time it was taken. Use Cloudflare's free endpoints, which see only the tunnel's PIA address. Then a test on stock to see whether the server can be reached below 128.0.0.0. Raised 2026-11-15.
  - Plan: [plan_network-tunnel-status.md](.claude/plans/plan_network-tunnel-status.md)
```

## Latency and jitter under the speed (ID-703)

Built 2026-11-25, when Andrew asked for it. It costs almost no data. Latency is curl's `time_starttransfer` for ten small requests (`/__down?bytes=0`) through the tunnel, one after another, each on a new connection so the figure includes the handshake, or `time_connect` for the round trip alone; it is the median. Jitter is the mean of the differences between consecutive latencies, which is how Cloudflare's own test reports it. It goes through the same route as the speed test (stock's rule at 1004, Merlin's `--interface`), so it has the same no-route case. It would run before the speed test, while the tunnel is idle: run during the transfer it would measure the queue the test builds, not the tunnel.
