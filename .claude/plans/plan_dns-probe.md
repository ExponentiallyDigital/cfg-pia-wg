# ID-078 / ID-006 - a tunnel that handshakes but resolves nothing

**Status: approved by Andrew and BUILT in build 455 (ID-078, closing ID-006).** Kept as the record of why it is shaped this way; the code is the `dns_probe` function in the script template in `lib/router_watchdog.dart`.

**The problem, measured.** CHANGELOG ID-006: devices pinned to `wgc4` had no name resolution for two days while the watchdog logged a healthy handshake every five minutes. A WireGuard handshake proves the peer is answering the tunnel. It proves nothing about whether anything *behind* the peer answers, and PIA's in-tunnel resolvers can stop answering while the tunnel itself stays up.

**What ID-063 already fixed, and what it did not.** A rebuild now waits for a handshake before calling itself a success, so a rebuild that produces a dead tunnel is reported. A tunnel that handshakes and resolves nothing still passes every check the watchdog makes.

---

## What the router measurements settled

All from `runsheet_AN-2026-09-19_001`, on stock, with two slots sharing the Quad9 pair.

**A lookup aimed at a slot's DNS server does travel through that slot's tunnel.** `ip route get 9.9.9.9` named `dev wgc5` with wgc5's tunnel address as the source, and `nslookup wikipedia.org 9.9.9.9` answered in 0.52 s.

**A temporary `ip rule` can aim that lookup at a chosen slot.** Adding `to 9.9.9.9 iif lo lookup 9 priority 1000` moved the route from wgc5 to wgc1, source address and all; the lookup answered through wgc1; deleting the rule put it back. This is what makes a probe possible for a slot that does not own its DNS address.

**A stopped slot silently falls through to the WAN, and the probe passes anyway.** With wgc1 disabled, the same temporary rule produced `9.9.9.9 via <gateway> dev eth0` and the lookup succeeded in 1.84 s. **A probe that does not check where it is going will call a stopped tunnel healthy.** This is the finding that shapes the whole design.

**A dead resolver costs 20 seconds.** `nslookup example.net 192.0.2.1` took 20.02 s to fail, and BusyBox's `nslookup` (v1.24.1) has no timeout option - `nslookup [HOST] [SERVER]` is the whole usage. Anything built on it needs an external timeout.

**Most slots have no DNS to probe.** Until ID-126, a slot built from the watchdog form had no `wgcN_dns` at all. Existing deployments are full of them.

---

## The design

### 1. Preconditions, checked in this order

1. The slot has DNS servers (`wgcN_dns` non-empty). If not, **skip the probe entirely** and log once that it was skipped. Do not treat a slot with no DNS as failing: it is the normal state for anything built before build 454.
2. The interface is up and has handshaked within 300 s - the checks that already exist. A tunnel that is down is not a DNS problem.

### 2. Aim the probe, then verify the aim

Take the slot's **first** DNS address. On stock the firmware only ever redirects a pinned device to the first one, so it is the address that matters.

```sh
ip route get "$DNS1"          # does it already name our interface?
```

- **Already `dev $IFACE`** - nothing to do; this slot owns the address.
- **Names another interface, or the WAN** - add a temporary rule, then **check again**:

```sh
ip rule add to "$DNS1" iif lo lookup "$TABLE" priority 1000
ip route get "$DNS1"          # MUST now name $IFACE
```

If the second `ip route get` does not name `$IFACE`, **remove the rule and skip the probe**. That is the stopped-slot case from B8, and running the lookup anyway would produce a false pass.

`$TABLE` is `10 - SLOT`: wgc1 is 9 through wgc5 is 5, measured. Derive it, do not hardcode a map.

### 3. The probe itself

**Measured 2026-09-19: `which timeout` finds nothing on this router.** BusyBox's build has no `timeout`, and its `nslookup` takes 20 seconds to give up with no option to shorten that. So the bound has to be built by hand: run the lookup in the background, poll for it, and kill it if it outstays its welcome.

```sh
nslookup "$NAME" "$DNS1" > "$TMPNS" 2>&1 &
NSPID=$!
i=0
while [ $i -lt 6 ] && kill -0 "$NSPID" 2>/dev/null; do
  sleep 1
  i=$((i + 1))
done
if kill -0 "$NSPID" 2>/dev/null; then
  kill -9 "$NSPID" 2>/dev/null
  wait "$NSPID" 2>/dev/null
  DNSOK=0                      # outstayed six seconds: treat as no answer
else
  wait "$NSPID" && DNSOK=1 || DNSOK=0
fi
```

Six seconds against a measured 0.52 s for a healthy lookup through a tunnel, and 2.09 s for a cold one. `kill -0` polls rather than assumes, so a fast answer costs one second at most.

`nc` is on the router and `nc -w` has its own timeout, which would make a cheaper reachability probe
- but it tests that something accepts a connection on port 53, not that it answers a question, and "answers nothing" is the fault being caught. Kept in reserve.

Two consecutive failures before acting, held in a counter file beside the backoff file, so a single lost packet cannot bounce a healthy tunnel. The name to look up should be one that is not the same every time - a fixed name invites caching somewhere in the path - and must not be a PIA name, which would make the probe itself a signal.

### 4. Cleanup, on every path

The temporary rule must be removed when the probe finishes, when it times out, when the script aborts, and at the start of the next run in case a previous one was killed. Same discipline as ID-077's `/etc/hosts` entry, and the same marker-and-sweep shape: `priority 1000` is the marker, since nothing else uses it.

### 5. What a failure means

Two consecutive failures with the aim verified means the tunnel carries packets and resolves nothing. Treat it exactly as a lost tunnel: log it, count it, rebuild, and let the existing backoff and alerting do the rest. The alert should say which check failed, because "the tunnel is up and handshaking but its DNS server answers nothing" is a different sentence from "the tunnel is down".

---

## What I am not proposing

**Probing the router's own resolver.** The other half of the ID-006 design note. It tests whichever slot owns the address today, not this slot, and the shared-address case makes that unpredictable. The temporary rule above is what makes a per-slot probe possible; probing `127.0.1.1` would tell us about the house, not about this tunnel.

**Probing on every check.** A lookup every five minutes, per slot, forever, is a lot of traffic to add for a fault seen once. Probe only when the cheap checks pass - the probe exists to catch what they miss.

---

## The questions, and what was decided

1. **Probe every check, or only every Nth?** Every check, while the handshake is healthy. One lookup per slot per interval is nothing, and the fault is invisible any other way.
2. **What name should it look up?** `example.com` - IANA-reserved, always resolves, neutral, sends no traffic to a real service, and `nslookup` asks the slot's resolver directly so the router's own cache never sees it.
3. ~~Does `timeout` exist on the router?~~ **Answered 2026-09-19: no.** The design above bounds the lookup by hand instead.
4. **Should a DNS failure email differently from a tunnel failure?** They are different faults with the same remedy.

Once those are answered this is a contained change: one function in the script, one counter file, and the preconditions above.
