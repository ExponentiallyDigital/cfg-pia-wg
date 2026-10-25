# Network menu - plan for ID-458

Reference for BACKLOG ID-458: a future main menu item, "Network", that looks up the public IP address and provider of the device the app runs on, and of each tunnel.

This is the answer Andrew got from Cloudflare's assistant on 2026-10-20 when he asked how to use Cloudflare Radar to find his IP address and provider. It's recorded as given, and nothing in it has been checked yet: confirm the endpoints, the response shape and the token permissions against Cloudflare's API documentation before building on it.

## The answer, as given

For a Flutter app you can use Cloudflare Radar's entity lookup endpoints: `/radar/entities/ip` returns geolocation, and `/radar/entities/asns/ip` returns the AS/ISP for an IP. You first need the device's external IP; the simplest reliable way is an HTTPS call to a service such as `https://1.1.1.1/cdn-cgi/trace` (or `https://api.ipify.org?format=json`), then pass it to Radar. Radar API calls require an API token with read permissions — read-only endpoints can generally be called with the token in an `Authorization: Bearer <token>` header.

Here is a minimal Dart example using `http`:

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

const cloudflareToken = '<YOUR_CLOUDFLARE_API_TOKEN>';

Future<String?> getExternalIp() async {
  final res = await http.get(Uri.parse('https://api.ipify.org?format=json'));
  if (res.statusCode == 200) {
    return jsonDecode(res.body)['ip'] as String?;
  }
  return null;
}

Future<Map<String, dynamic>?> radarIpDetails(String ip) async {
  final url = Uri.parse(
    'https://api.cloudflare.com/client/v4/radar/entities/ip?ip=$ip&format=JSON',
  );
  final res = await http.get(url, headers: {
    'Authorization': 'Bearer $cloudflareToken',
  });
  if (res.statusCode == 200) {
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
  return null;
}

Future<Map<String, dynamic>?> radarAsnDetails(String ip) async {
  final url = Uri.parse(
    'https://api.cloudflare.com/client/v4/radar/entities/asns/ip?ip=$ip&format=JSON',
  );
  final res = await http.get(url, headers: {
    'Authorization': 'Bearer $cloudflareToken',
  });
  if (res.statusCode == 200) {
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
  return null;
}
```

Call them like this:

```dart
void main() async {
  final ip = await getExternalIp();
  if (ip == null) return;

  final ipInfo = await radarIpDetails(ip);
  final asnInfo = await radarAsnDetails(ip);

  print('IP: $ip');
  print('Radar IP: ${ipInfo?['result']}');
  print('Radar ASN: ${asnInfo?['result']}');
}
```

If you only need a quick external-IP check without Radar details, `https://1.1.1.1/cdn-cgi/trace` returns a plain-text response where `ip=...` is the visitor's address, and your provider can often be inferred from DNS/rDNS; but Radar gives structured provider/AS data.

Also see the Radar "IP Address Information" page for the web version of this lookup.

## Follow-up: a tokenless, hostname-only approach

Andrew then asked for an approach that needs no token and uses hostnames only. The answer, again recorded as given and not yet checked:

For a tokenless, FQDN-only approach, Cloudflare's public `cdn-cgi/trace` endpoint works for the IP but does **not** return the provider/ASN. Radar's `/radar/entities/ip` and `/radar/entities/asns/ip` endpoints both require an API token, so you can't use Radar itself without one.

Best tokenless option that gives **both** IP and provider:

```bash
curl https://ipinfo.io/json
```

Returns something like:

```json
{
  "ip": "203.0.113.42",
  "hostname": "example.net",
  "city": "Lisbon",
  "region": "Lisbon",
  "country": "PT",
  "loc": "38.7167,-9.1333",
  "org": "AS12345 Example Provider",
  "postal": "1000-001",
  "timezone": "Europe/Lisbon"
}
```

Key fields: `ip` and `org` (which includes the AS number and provider name).

If you prefer to stay with Cloudflare for the IP lookup, use the FQDN form of the trace endpoint:

```bash
curl https://cloudflare-dns.com/cdn-cgi/trace
```

This returns plain text including:

```text
ip=203.0.113.42
colo=LIS
...
```

But you'll still need a second, tokenless lookup (such as `https://ipinfo.io/203.0.113.42/json`) to get the provider name and AS number.

So a practical no-token curl flow would be:

```bash
# Get external IP
IP=$(curl -s https://cloudflare-dns.com/cdn-cgi/trace | sed -n 's/^ip=//p')

# Get provider/ASN
curl -s "https://ipinfo.io/$IP/json"
```

If your curl environment truly requires an FQDN, avoid `1.1.1.1`/`1.0.0.1` and use `cloudflare-dns.com` or `www.cloudflare.com` for the trace; use `ipinfo.io` for the provider metadata.

## Follow-up: Radar's rate limits with a token

Andrew then asked about Radar's rate limits. The answer, recorded as given and not yet checked:

With a Cloudflare API token, Radar endpoints fall under the standard Cloudflare REST API rate limits:

**1,200 requests per 5 minutes** per user/account token — this is the global limit shared across dashboard, API keys, and API tokens. Exceeding it blocks all API calls for 5 minutes with `HTTP 429`.

Additional limits:

- **200 requests/second** per source IP
- **50** API tokens per user
- **500** API tokens per account

The API returns rate-limit headers you can use to back off:

- `Ratelimit` — remaining quota and reset time
- `Ratelimit-Policy` — quota policy details
- `Retry-After` — seconds until capacity returns (only on 429)

For a simple "what is my IP and provider" lookup, you'd typically call:

1. `/radar/entities/ip` — external IP geolocation
2. `/radar/entities/asns/ip` — provider/ASN

That's just **2 requests** per user lookup, so the 1,200/5 min limit is very generous unless you're calling it at scale across many users.

Enterprise customers can contact Cloudflare Support to raise the per-user or per-token limits.

## Follow-up: the two Radar URLs to try

A further answer from Cloudflare's assistant, recorded as given. It repeats the first answer's two calls with the URLs written out:

- IP geolocation: `https://api.cloudflare.com/client/v4/radar/entities/ip?ip={your_external_ip}&format=JSON`
- Provider / ASN: `https://api.cloudflare.com/client/v4/radar/entities/asns/ip?ip={your_external_ip}&format=JSON`
- Both with `-H "Authorization: Bearer <YOUR_CLOUDFLARE_API_TOKEN>"`, and the IP taken first from `curl https://cloudflare-dns.com/cdn-cgi/trace` (the `ip=` line).

Cloudflare's API documentation shows the first call alone already returns the ASN and provider name (see "Recommended design", section 2), so the second is only worth keeping if a hand run shows it adds something.

## Hand run, 2026-10-20

Andrew ran the trace and both Radar calls from the PC in PowerShell 7, with his own token, over his ISP connection (no tunnel). No addresses or names are recorded here, only what each call returned.

- **Trace:** returned `fl`, `h`, `ip`, `ts`, `visit_scheme`, `uag`, `colo`, `sliver`, `http`, `loc`, `tls`, `sni`, `warp`, `gateway`, `rbi` and `kex`. `ip` and `loc` (the country code) were both filled in. `colo` was the three-letter airport code of the Cloudflare data centre in his own city.
- **`/radar/entities/ip`:** the token worked. It returned `ip`, `ipVersion`, `location`, `locationName`, `asn` (as a string), `asnName`, `asnOrgName` and `asnLocation`. `asnName` is the registry handle (an `...-AS` name); `asnOrgName` is the company's name, which is the one to show.
- **`/radar/entities/asns/ip`:** returned `asn` (as a number), `name`, `aka` (the brand name customers know, shorter than the company's name), `website`, `country`, `countryName`, `orgName` (a registry handle, not a readable name), `source`, `confidenceLevel`, `estimatedUsers`, and a `related` list of the provider's other AS numbers that ran to over 60 entries.

What it settles:

- One call, `/radar/entities/ip`, is enough. It gives the IP, the country and a readable provider name. The second call adds only the brand name (`aka`), and the cost is a payload many times larger. It isn't worth it.
- The parser must take `asn` as either a string or a number, since the two endpoints differ.
- **A possible town without a database:** the trace's `colo` names the Cloudflare data centre the request reached, which is usually the one nearest the exit. For a tunnel, that's roughly where the traffic leaves PIA's network. It's a data centre, not a geolocation, and anycast routing doesn't always pick the nearest, so it would be labelled as such ("via Cloudflare, Singapore", for example), if used at all. It needs a table from airport code to city name. Measured through a tunnel, it would show whether it agrees with PIA's region name.

## Getting a Radar token

How Andrew made the token for the hand run on 2026-10-20. This becomes part of the app's setup instructions if Radar is chosen.

Radar needs a **user** API token, because its permission, User Details Read, is a user-level permission. It isn't offered on the account token page (Manage account → Account API tokens), which only has account-scoped permissions and a "Permission policies / Review token" flow. The user token page has the older "Create Custom Token" layout, with Account, Zone and User permission rows.

1. Sign in to Cloudflare and open **My Profile → API Tokens**: <https://dash.cloudflare.com/profile/api-tokens>
2. Select **Create Token**.
3. Scroll to **Create Custom Token** and select **Get started**.
4. **Token name:** `radar-api`
5. **Permissions:** add one row: **User** → **User Details** → **Read**
6. **Account Resources:** Include → All accounts
7. Select **Continue to summary**, then **Create Token**.
8. Copy the token. Cloudflare shows it only once.

To check it works, the same answer suggested:

```bash
curl https://api.cloudflare.com/client/v4/radar/annotations/outages \
  --header "Authorization: Bearer <YOUR_TOKEN>"
```

The check the app would use is a call to `/radar/entities/ip`, as in the hand run above.

To settle before this goes into the setup instructions:

- Whether step 6 is needed. The only permission is a user one, so the account choice may not matter. Try a token with no account resources.
- Whether to suggest the form's optional TTL (an expiry date) or client IP filtering. IP filtering won't work for a phone that moves between networks and tunnels, and an expiry date means the screen has to explain a token that has stopped working.
- Where the app keeps the token: the same secure storage as the router password (`flutter_secure_storage`), and never in the app log or an emailed report.

## Measured on the router, 2026-10-20

- **curl can't choose a tunnel on stock.** `--interface wgcN` and `--interface <wgcN's address>` both got no answer through wgc1 or wgc5.
- **The watchdog's way works (ID-078).** For one request: take the watchdog's DNS probe lock (`/tmp/cfg-pia-wg-dnsprobe.lock`, ID-193), add `ip rule add to <address> iif lo lookup <10 - slot> priority 1000`, check `ip route get <address>` names `dev wgcN`, make the request with `--resolve cloudflare-dns.com:443:<address>`, delete the rule, release the lock. Each tunnel answered with its own IP and its region's country, and no rule was left. It needs the address below 128.0.0.0: the firmware's table sends only `0.0.0.0/1` through the tunnel, and the rest out of the WAN, which the `ip route get` check catches.

## Radar's licence, checked 2026-10-20

Cloudflare's developer docs: data from the Radar API is under CC BY-NC 4.0, non-commercial; exceptions by request, from Radar's About page. The app is paid, so this rules Radar out without an exception, whoever's token is used. IPinfo Lite is the alternative: by IPinfo's own pages CC BY-SA 4.0, commercial use allowed with attribution ("IP address data is powered by IPinfo"), unlimited requests with a free token, country and provider only, at `https://api.ipinfo.io/lite/<IP>?token=<token>`. Not yet tried by hand.

## What it leaves open for this app

- **Radar's limit is per Cloudflare user, and the limit is shared with that user's dashboard and other API use.** If each user supplies their own token, the limit is theirs and two requests per lookup is nothing (one lookup per tunnel plus the device is under a dozen). The cost is that every user needs a Cloudflare account and has to make a token. A 429 means waiting out the `Retry-After`, and hitting it would also block that user's other Cloudflare API calls for 5 minutes.

- **ipinfo.io without a token.** It is rate-limited, and its terms for use without a token inside a published app need reading before relying on it. One `https://ipinfo.io/json` call gives both the IP and `org`, so the Cloudflare trace is only needed if the IP must come from Cloudflare.

- **The token.** The example compiles a Cloudflare API token into the app. Anything shipped in the app can be pulled out of it, and one shared token would be used, and rate-limited, by every user. The options are each user pasting their own read-only token, a token-free lookup, or no provider at all.
- **Per tunnel.** The phone only sees its own exit. A tunnel's exit IP has to be read on the router, by a request sent out through `wgcN` (for example `curl --interface wgcN`), and the Radar lookup can then run on the phone with that IP. Stock's curl refuses a URL whose host is an IP address (ARCHITECTURE 2, row 7; ID-127), so `https://1.1.1.1/cdn-cgi/trace` won't work there as written: it needs a hostname, such as `one.one.one.one`, or `--resolve`.
- **Privacy.** Each lookup tells Cloudflare (and ipify, if used) the address being looked up. The screen should say so before the first lookup.

## Recommended design (2026-10-20)

This is Claude's recommendation, and nothing is decided until Andrew says so. It separates the IP address, which is a fact you get by sending a request out through the path being tested, from the country, town and provider, which are a database's opinion and are looked up afterwards, once per IP.

### 1. The IP comes from the path itself

- **This device:** the phone fetches `https://cloudflare-dns.com/cdn-cgi/trace`.
- **Each tunnel:** one router command, over the SSH connection the app already has, fetches the same URL out through each `wgcN` that is up.
- The trace needs no token and also returns the country (`loc=`), so the screen works with no setup.
- Stock's other curl limits are already avoided: the URL uses a hostname, not an IP address, and the lookup runs from the screen, not from cron (ARCHITECTURE 2, rows 6 and 7; ID-127).

### 2. The provider is looked up on the phone, once per IP

- One Radar call, `/radar/entities/ip`, returns `asn`, `asnName`, `asnOrgName`, `location` (the country code) and `locationName`. The second call the first answer suggested, `/radar/entities/asns/ip`, isn't needed.
- It needs the user's own free Cloudflare token with "User Details Read" permission, stored the way the app already stores credentials. Without a token, the screen shows only the IP and country.
- Running it on the phone keeps any token there, and the app keeps one HTTPS client and one parser.
- Results are cached by IP, so a refresh only looks up addresses it hasn't seen.
- The lookup sits behind a small interface, so changing from Radar to ipinfo Lite later touches one class.

### 3. No town from a database

- Neither free option returns a town: Radar has no city field, and ipinfo's town data is on a paid plan.
- Town-level guesses for VPN exits are unreliable anyway.
- For each tunnel, the screen shows PIA's own region name instead.
- PIA offers some regions as virtual locations, where the server is in a different country from the region it is named after. When PIA's region and Cloudflare's country disagree, the screen shows both, and doesn't choose one.

### 4. ipinfo.io without a token is ruled out

- From ipinfo's own support pages: without an account, the limit is 1,000 requests a day, shared by everyone on the same IP. A PIA exit IP is shared by many PIA users, so lookups through a tunnel would fail at random.
- A free account with a token (IPinfo Lite) has no request cap and gives country and provider only. That makes it the fallback if Radar doesn't suit, not a better choice.

### 5. The screen

- One row for "This phone" and one for each tunnel that is up.
- Each row shows the IP, the country, the provider and AS number, and for a tunnel, the PIA region.
- A REFRESH button, with no polling in the background.
- A notice before the first lookup that the addresses are sent to Cloudflare.

### 6. Testing

- The trace parser and the Radar parser are pure functions with unit tests. The trace's fields are documented only by third parties, so the parser copes with a missing field.
- The HTTP calls are faked in widget tests.
- The router command gets an `e2e.sh` check that the IP read through each `wgcN` differs from the ISP's.

### First thing to measure, before anything is designed around it

Whether `curl --interface wgcN` on stock sends its request out through the tunnel. The router's own traffic may need policy routing that ASUS doesn't set up for `wgcN`. If it doesn't work, the request either fails or goes out through the ISP, and the second case shows the wrong IP while looking right. One read-only paste block on hardware settles it.

### Sources checked

- [Cloudflare API: Radar entities, get IP details](https://developers.cloudflare.com/api/resources/radar/subresources/entities/methods/get/): the response fields and the token permission.
- [IPinfo: public API without an account](https://support.ipinfo.io/hc/en-us/articles/30792479436562-What-Is-the-Difference-Between-Using-the-Authenticated-Free-Plan-and-the-Public-API-With-No-Account): 1,000 requests a day, shared per IP.
- [IPinfo: free plan usage limit](https://support.ipinfo.io/hc/en-us/articles/30792535492626-What-Is-the-Usage-Limit-for-the-Free-Plan): Lite with a token has no cap, and covers country and ASN only.
- [publicapi.dev: Cloudflare Trace fields](https://publicapi.dev/cloudflare-trace-api): `ip`, `loc` and `colo`, from a third party. Cloudflare doesn't document the trace.

## Decided, 2026-10-25

The BACKLOG item as it was, moved here word for word when it went to WIP:

- ID-458 ADD: a "Network" item on the main menu that shows the public IP address and provider of this device, and of each tunnel, using Cloudflare Radar. Raised 2026-10-20 by Andrew. Cloudflare's assistant suggested an approach, which is recorded as given, and not yet checked, in `.claude/plans/plan_network-menu.md`: get the external IP (`https://1.1.1.1/cdn-cgi/trace` or ipify), then call Radar's `/radar/entities/ip` (location) and `/radar/entities/asns/ip` (provider) with a read-only API token. A follow-up answer, recorded in the same file, gives a way that needs no token and uses hostnames only: `https://ipinfo.io/json` returns both the IP and the provider (`org`, e.g. "AS12345 Example Provider"), and `https://cloudflare-dns.com/cdn-cgi/trace` gives the IP alone. The plan file's "Recommended design" section holds Claude's recommendation, not yet decided: the IP from the trace, sent from the phone and through each `wgcN` on the router; the provider from one Radar call on the phone, with the user's own token; PIA's region name instead of a town. A hand run on 2026-10-20 confirmed that one Radar call, `/radar/entities/ip`, returns the country and a readable provider name, so the second call isn't needed. The steps Andrew used to make the token are in the plan's "Getting a Radar token" section, for the setup instructions. It rules out ipinfo.io without a token, because its 1,000 requests a day are shared by everyone on the same IP, and a PIA exit IP has many users.
  - To decide first: Radar with a token, which every user would have to supply because one compiled into the app can be pulled out (its limit, 1,200 requests per 5 minutes per Cloudflare user, is ample at two requests per lookup, but each user needs a Cloudflare account), or ipinfo.io without one, once its rate limit and terms are read; how each tunnel's exit IP is read on the router, by a request sent out through `wgcN` to a hostname, since stock's curl refuses a URL whose host is an IP address (ID-127); and what the screen tells the user about sending the address to the lookup service.
  - First probe: a read-only paste block on stock showing whether `curl --interface wgcN` sends its request out through the tunnel, and not out through the ISP.
  - DoD: decided, the probe has been run, the chosen service's endpoints and terms are confirmed against its own documentation, and the build items are written with their own done-when.
  - Decided, 2026-10-20 (Andrew): the plan's recommended design: the IP and country from Cloudflare's trace, with no token; the provider from one Radar call, with a token each user supplies; PIA's region name, not a town.
  - First probe, 2026-10-20: neither of curl's ways of choosing a tunnel works on stock. `--interface wgcN` and `--interface <wgcN's address>` each printed nothing, for wgc1 and wgc5, the second the same way a ping from a tunnel's address leaves by the WAN (ID-396). Next: a second probe with the watchdog's own way through a tunnel (ID-078), a rule `to <address> iif lo lookup <table>` at priority 1000 for one request, checked with `ip route get` before the request is made.
  - Second probe, 2026-10-20: it works. With the rule in place, `ip route get` named the tunnel, and the trace answered through each one with an IP different from the WAN's and the country of the tunnel's region: wgc1 New Zealand, wgc5 Australia. The rules were gone afterwards. It waited for the watchdog's DNS probe lock first (ID-193), and the router build will too.
  - Radar's licence, checked 2026-10-20: Cloudflare's developer docs say data from the Radar API is under CC BY-NC 4.0, non-commercial, with exceptions by request on Radar's About page. This app is paid, so the decided design needs either Cloudflare's exception or another provider. IPinfo Lite, also one call per IP with a free token of the user's own, is CC BY-SA 4.0 by IPinfo's pages, commercial use allowed with attribution, unlimited, country and provider only. Left: Andrew's choice between the two; then the build items.
  - Free tier, Andrew's decision, 2026-10-20: NETWORK needs no unlock, as "looking is free" (the Play listing), and the exception request to Cloudflare says so. That includes each tunnel's lookup, though it briefly adds a routing rule on the router: the build makes NETWORK reachable without `Entitlement.isUnlocked`, with a test.
  - Asked of Cloudflare, 2026-10-20: Andrew is emailing Radar's contact for an exception to the CC BY-NC 4.0 licence. IPinfo Lite is the fallback if the answer is no or doesn't come.
  - On hold, 2026-10-20, Andrew's decision: moved from CHANGELOG WIP to BACKLOG so the iOS release comes first. Picked up again once Cloudflare answers the exception request, or on 2026-10-28, whichever comes first (Andrew, 2026-10-21).

Andrew's decisions:

- No reply from Cloudflare to the request for a Radar exemption, so Radar is out (its data is CC BY-NC 4.0).
- The service must be privacy focused and not log, which rules out Google, Cloudflare's trace and IPinfo. Claude proposed Mullvad's connection check, `https://ipv4.am.i.mullvad.net/json`: one call, no token, and it returns `ip`, `country`, `city` and `organization` (the provider), plus `mullvad_exit_ip`, `blacklisted`, `latitude` and `longitude`, which aren't used (measured 2026-10-25). Mullvad's privacy policy says "our policy to never store any activity logs or metadata", but doesn't name the check site; Mullvad's blog says its API can be used "with your own software or script". Neither settles a paid app's use, so Andrew is to ask Mullvad. Built so it can change later: the service is one class behind `IpLookupService`, chosen by `kIpLookupService`.
- `ipv4.am.i.mullvad.net` resolves to 45.83.223.233, below 128.0.0.0, so stock's tunnel table carries it (its tables route `0.0.0.0/1` only). Devices pinned to a tunnel aren't affected by that limit: they use the guard's own tables, `200 + slot`, with the tunnel's default route.
- Free, since it only reads. A notice on the screen before any lookup, and a privacy policy paragraph for Andrew's approval, published before the release that carries it.
- Town is now available (Mullvad's `city`, GeoIP's estimate); a tunnel row shows PIA's region beside it, and doesn't choose between them.

The build:

- `lib/network_lookup.dart`: `IpLookupService` and `MullvadLookup`; `lookUpThisPhone`; `tunnelLookupAddress` (the service's IPv4 address below 128.0.0.0, resolved on the phone); `tunnelLookupCommand`, one router command for every tunnel that is up, stock by ENABLE's own route read-back method with its own rule priority 1003, Merlin by `curl --interface wgcN` (not measured on Merlin); `parseTunnelLookups`.
- Nothing is looked up until the user taps LOOK UP, under the notice, so the notice is read before every lookup, not only the first, and there is no remembered "seen it" to store.

### 2026-10-25: built, in build 541

- `lib/screens/network_screen.dart`: the notice, LOOK UP, "This phone", a row per tunnel that is up (highest slot first, `wgcN:region`, then address, place, provider and PIA region), and "Address data from Mullvad." Without a router login, the tunnels are offered by a login link, as ABOUT does. The firmware is read afresh (`nvram get 3rd-party`), since NETWORK can be the first router screen of a session. Drawer and menu: after DEVICES, `Icons.public`, `kNetworkColour`.
- Tests: `test/unit/network_lookup_test.dart` (15), with the stock command run in a shell against stand-in `ip` and `curl`: asked through each tunnel's own table by name, a tunnel the rule doesn't reach is NOROUTE with nothing sent, and no rule is left; seen to fail with the route read-back and the clean-up taken out. `test/screens/network_screen_test.dart` (7); seen to fail with the firmware check, the PIA region line and stock's command broken. The drawer gained a row, so main_test's two CLEAR-from-the-drawer tests drag the drawer before tapping (the list scrolls, 30 px of room in the test's 800x600 window). Full suite 2040 passed, 1 skipped, 95.9%.
- TESTING: NET-1 to NET-3.
- Not yet: the privacy policy paragraph below, approved and published; Andrew's question to Mullvad; NET-1 to NET-3 on hardware; Merlin's `curl --interface` measured.

### Drafts for Andrew's approval: the privacy policy

A new section after 1.4:

> **1.5 The NETWORK screen.** NETWORK shows the public internet address of your phone, and of each VPN tunnel your router has running, with the country, town and internet provider that address belongs to. Nothing is looked up until you tap LOOK UP. Each lookup is one request to Mullvad's connection check (am.i.mullvad.net), sent from your phone for its own address and from your router, through the tunnel, for each tunnel's. Mullvad sees the address each request comes from, which is how it answers, and Mullvad's own privacy policy says it keeps no activity logs. The app sends nothing else with the request, and keeps nothing it is told: the results are on screen until you leave it.

Added to 1.4's widget paragraph, after "If you do not add the widget, neither is ever stored.":

> With the widget set up, the app also keeps the time and outcome of each background refresh, such as "read the router" or "phone locked", the newest 500 of them, so you can see how often your phone lets it refresh. Nothing read from the router is kept in it.

