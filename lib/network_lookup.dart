// network_lookup.dart - the public IP address, country, town and provider of this phone and of each
// tunnel, for the NETWORK screen (ID-458).
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// The address is a fact only the path itself can give, so each lookup is a request sent out the way
// being tested: from the phone for "This phone", and from the router through wgcN for a tunnel. The
// service that answers it is behind [IpLookupService], so changing service later is one new class and
// a change to [kIpLookupService]; nothing else here or in the screen names one (Andrew, 2026-10-25).
//
// The service is PIA's own, and only PIA's, Andrew's choice on 2026-10-25: the app needs PIA anyway, so
// PIA already sees this phone's address whenever the app logs in or fetches its servers, and each
// tunnel's address is PIA's own; no other company learns anything (plan_network-menu.md).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What a lookup service says about one address. Empty strings for what it didn't say.
class NetworkFacts {
  const NetworkFacts({required this.ip, this.country = '', this.city = '', this.provider = ''});

  final String ip, country, city, provider;

  /// "Melbourne, Australia", or whichever half is known, or ''.
  String get place => [city, country].where((s) => s.isNotEmpty).join(', ');
}

/// A service that tells a caller its own public address. One request, over HTTPS, to [host] and
/// [path], and the reply turned into [NetworkFacts] by [parse].
abstract class IpLookupService {
  const IpLookupService();

  /// The name the screen gives it, in the notice and under the results.
  String get name;

  /// An IPv4-only hostname, so the phone's row compares with the tunnels', which are IPv4.
  String get host;
  String get path;

  /// Its privacy page, linked from the notice.
  String get privacyUrl;

  /// What the notice says about who sees the lookups, after the link to [privacyUrl].
  String get notice;

  /// The facts in [body], or null when it isn't a reply this service gives.
  NetworkFacts? parse(String body);
}

/// PIA's own lookup, the one its "What is my IP" page uses: `https://www.privateinternetaccess.com/site-api/get-location-info`,
/// answering `ip`, `isp`, `cty` (the town) and `cn` (the country), among others. Measured 2026-10-25. Not a
/// published API, so it may change without notice: if it does, a replacement is a new [IpLookupService]. The
/// site has no IPv6 address, so the phone's row is IPv4 as the tunnels' are.
class PiaLookup extends IpLookupService {
  const PiaLookup();

  @override
  String get name => 'PIA';
  @override
  String get host => 'www.privateinternetaccess.com';
  @override
  String get path => '/site-api/get-location-info';
  @override
  String get privacyUrl => 'https://www.privateinternetaccess.com/privacy-policy';
  @override
  String get notice => 'PIA already sees this phone\'s address whenever the app logs in or fetches its servers, and each '
      'tunnel\'s address is PIA\'s own, so no one else learns anything.';

  @override
  NetworkFacts? parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      String text(String key) => json[key] is String ? (json[key] as String).trim() : '';
      final ip = text('ip');
      if (InternetAddress.tryParse(ip) == null) return null;
      return NetworkFacts(ip: ip, country: text('cn'), city: text('cty'), provider: text('isp'));
    } on FormatException {
      return null;
    }
  }
}

/// The service in use. Change this, and only this, to change service.
const IpLookupService kIpLookupService = PiaLookup();

/// This phone's own public address, by a request from the phone. Throws when there's no answer, or
/// an answer that isn't the service's. [client] stands in for the network in a test.
Future<NetworkFacts> lookUpThisPhone({IpLookupService service = kIpLookupService, http.Client? client}) async {
  final http.Client c = client ?? http.Client();
  try {
    final res = await c.get(Uri.https(service.host, service.path)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('${service.name} answered HTTP ${res.statusCode}');
    return service.parse(res.body) ?? (throw Exception('${service.name} sent something that is not an address'));
  } finally {
    if (client == null) c.close();
  }
}

/// [service]'s address for the router to aim at, from the phone's DNS. It has to be IPv4 and below
/// 128.0.0.0: stock's tunnel table carries only `0.0.0.0/1`, and the rest goes out of the WAN, which
/// the router command would catch and report rather than use. Null when no such address is found.
Future<String?> tunnelLookupAddress({
  IpLookupService service = kIpLookupService,
  Future<List<InternetAddress>> Function(String host)? lookup,
}) async {
  try {
    final found = await (lookup ?? InternetAddress.lookup)(service.host);
    for (final a in found) {
      if (a.type == InternetAddressType.IPv4 && a.rawAddress.first < 128) return a.address;
    }
  } catch (_) {
    // No DNS from here: the tunnel rows say so.
  }
  return null;
}

/// How one tunnel's lookup ended.
enum TunnelLookupOutcome {
  /// Answered through the tunnel.
  found,

  /// The request couldn't be aimed through the tunnel, so it wasn't sent: the tunnel is down, or the
  /// address isn't one the tunnel carries.
  noRoute,

  /// Sent through the tunnel, and no usable answer came back.
  failed,
}

class TunnelLookup {
  const TunnelLookup(this.outcome, [this.facts]);
  final TunnelLookupOutcome outcome;
  final NetworkFacts? facts;
}

/// The marker that starts each tunnel's part of the router's reply.
const String kTunnelLookupMarker = '@@NETWORK wgc';

/// The policy rule priority the stock path uses, its own: ENABLE's ping uses 1002 and the watchdog's
/// DNS probe 1000, and each removes only its own.
const int kTunnelLookupPriority = 1003;

/// One router command that asks [service] through each of [slots] in turn, for a router at
/// [address] (from [tunnelLookupAddress]).
///
/// Stock, as ENABLE's ping does it (kStockTunnelPingBody, ID-396): a rule for the one address into the
/// tunnel's own table (10 minus the slot), read back with `ip route get` before anything is sent, and
/// taken out after. A route not through the tunnel is NOROUTE, never a request that might answer by
/// the WAN and look right. The hostname goes in the URL and the address in `--resolve`, because stock's
/// curl refuses a URL whose host is an address (ARCHITECTURE 2, row 7). Measured with Cloudflare's
/// trace through wgc1 and wgc5, 2026-10-20.
///
/// Merlin binds to the tunnel instead, as its ENABLE ping does (`ping -I`). Not yet measured on Merlin.
String tunnelLookupCommand(List<int> slots, String address, {required bool stock, IpLookupService service = kIpLookupService}) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(address)) throw ArgumentError.value(address, 'address');
  final h = service.host, url = 'https://${service.host}${service.path}';
  final curl = 'curl -s --max-time 10 --resolve "$h:443:\$IP"';
  final body = stock
      ? '''TBL=\$((10 - N))
  while ip rule del to "\$IP" iif lo lookup "\$TBL" priority $kTunnelLookupPriority 2>/dev/null; do :; done
  ip rule add to "\$IP" iif lo lookup "\$TBL" priority $kTunnelLookupPriority 2>/dev/null
  if ip route get "\$IP" 2>/dev/null | grep -qE " dev wgc\$N( |\$)"; then
    $curl "$url" || echo "@@FAIL"
  else
    echo "@@NOROUTE"
  fi
  while ip rule del to "\$IP" iif lo lookup "\$TBL" priority $kTunnelLookupPriority 2>/dev/null; do :; done'''
      : '''$curl --interface "wgc\$N" "$url" || echo "@@FAIL"''';
  return '''IP=$address
for N in ${slots.join(' ')}; do
  echo
  echo "$kTunnelLookupMarker\$N"
  $body
done''';
}

/// Each slot's outcome from [tunnelLookupCommand]'s output. A slot missing from it is [TunnelLookupOutcome.failed].
Map<int, TunnelLookup> parseTunnelLookups(String raw, List<int> slots, {IpLookupService service = kIpLookupService}) {
  final found = <int, TunnelLookup>{};
  for (final part in raw.split(kTunnelLookupMarker).skip(1)) {
    final slot = int.tryParse(part.isEmpty ? '' : part[0]);
    if (slot == null) continue;
    final text = part.substring(1).trim();
    if (text.contains('@@NOROUTE')) {
      found[slot] = const TunnelLookup(TunnelLookupOutcome.noRoute);
    } else {
      final facts = service.parse(text);
      found[slot] = facts == null ? const TunnelLookup(TunnelLookupOutcome.failed) : TunnelLookup(TunnelLookupOutcome.found, facts);
    }
  }
  return {for (final s in slots) s: found[s] ?? const TunnelLookup(TunnelLookupOutcome.failed)};
}
