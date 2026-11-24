// lib/router_facts.dart - the router's own identity, for the box at the top of NETWORK (ID-706).
//
// Read from the router's NVRAM over the session the app already has; nothing is sent to anyone else, which is
// NETWORK's rule. Read-only. Measured on a Merlin router, 2026-11-25: `wan0_ipaddr` is the WAN address,
// `lan_hostname` the router's name (`computer_name` was empty), `lan_domain` the domain, `ddns_enable_x` 1 and
// `ddns_hostname_x` the DDNS name. Stock uses the same keys; that is ID-711's to check on a stock router.

/// What the router calls itself and where it is.
class RouterFacts {
  const RouterFacts({this.wanIp = '', this.ddns = '', this.hostname = '', this.domain = '', this.lanIp = ''});

  /// The router's address on the WAN side, which behind a modem's NAT is not the public one.
  final String wanIp;

  /// The DDNS name, or empty when DDNS is off or has no name.
  final String ddns;
  final String hostname, domain, lanIp;
}

/// One read-only command, a `KEY=value` line each.
const String kRouterFactsCommand = r'''echo "WAN=$(nvram get wan0_ipaddr)"
echo "DDNSON=$(nvram get ddns_enable_x)"
echo "DDNS=$(nvram get ddns_hostname_x)"
echo "HOST=$(nvram get lan_hostname)"
echo "DOMAIN=$(nvram get lan_domain)"
echo "LAN=$(nvram get lan_ipaddr)"''';

/// [raw] from [kRouterFactsCommand]. The DDNS name counts only when DDNS is switched on, since the router keeps
/// the name it had after DDNS is turned off. Anything not given is empty.
RouterFacts parseRouterFacts(String raw) {
  final values = <String, String>{};
  for (final line in raw.split('\n')) {
    final i = line.indexOf('=');
    if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return RouterFacts(
    wanIp: values['WAN'] ?? '',
    ddns: values['DDNSON'] == '1' ? values['DDNS'] ?? '' : '',
    hostname: values['HOST'] ?? '',
    domain: values['DOMAIN'] ?? '',
    lanIp: values['LAN'] ?? '',
  );
}
