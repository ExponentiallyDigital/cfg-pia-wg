// lib/router_facts.dart - the router's own identity, for the box at the top of NETWORK (ID-706).
//
// Read from the router's NVRAM over the session the app already has; nothing is sent to anyone else, which is
// NETWORK's rule. Read-only. Measured on a Merlin router, 2026-11-25: `wan0_ipaddr` is the WAN address,
// `lan_hostname` the router's name (`computer_name` was empty), `lan_domain` the domain, `ddns_enable_x` 1 and
// `ddns_hostname_x` the DDNS name. Stock uses the same keys; that is ID-711's to check on a stock router.
//
// The WAN is the one carrying the traffic (ID-720): `wan_primary` names its unit, 0 or 1, and `wans_dualwan` lists
// each unit's kind in order (`wan usb`). Measured the same day with the first WAN down and a phone on USB taking
// over: `wan_primary` was 1, `wan0_ipaddr` read 0.0.0.0 and the address in use was `wan1_ipaddr`.

/// What the router calls itself and where it is.
class RouterFacts {
  const RouterFacts({
    this.wanIp = '',
    this.wanUnit = 0,
    this.wanKind = '',
    this.ddns = '',
    this.hostname = '',
    this.domain = '',
    this.lanIp = '',
  });

  /// The router's address on the WAN side, which behind a modem's NAT is not the public one.
  final String wanIp;

  /// The WAN unit carrying the traffic: 0 for the first, 1 when a second (a phone on USB, say) has taken over.
  final int wanUnit;

  /// The kind of that unit as the router lists it (`wan`, `usb`), or empty when not read.
  final String wanKind;

  /// The DDNS name, or empty when DDNS is off or has no name.
  final String ddns;
  final String hostname, domain, lanIp;

  /// What NETWORK shows for the WAN: the address alone for the first, and for a second the address with what it is,
  /// so a card that reads 10.x is not taken for the home connection.
  String get wanText {
    if (wanUnit == 0) return wanIp;
    final kind = switch (wanKind) {
      '' => '',
      'usb' => ', USB',
      _ => ', $wanKind',
    };
    final label = 'secondary WAN$kind';
    return wanIp.isEmpty ? '($label)' : '$wanIp ($label)';
  }
}

/// One read-only command, a `KEY=value` line each. The unit is read first, and the address is that unit's.
const String kRouterFactsCommand = r'''U="$(nvram get wan_primary)"; case "$U" in 0 | 1) ;; *) U=0 ;; esac
echo "UNIT=$U"
echo "WAN=$(nvram get wan${U}_ipaddr)"
echo "WANKIND=$(nvram get wans_dualwan | awk -v n="$U" '{print $(n + 1)}')"
echo "DDNSON=$(nvram get ddns_enable_x)"
echo "DDNS=$(nvram get ddns_hostname_x)"
echo "HOST=$(nvram get lan_hostname)"
echo "DOMAIN=$(nvram get lan_domain)"
echo "LAN=$(nvram get lan_ipaddr)"''';

/// [raw] from [kRouterFactsCommand]. The DDNS name counts only when DDNS is switched on, since the router keeps
/// the name it had after DDNS is turned off. A unit that isn't 0 or 1 is not believed. Anything not given is empty.
RouterFacts parseRouterFacts(String raw) {
  final values = <String, String>{};
  for (final line in raw.split('\n')) {
    final i = line.indexOf('=');
    if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final unit = int.tryParse(values['UNIT'] ?? '');
  return RouterFacts(
    wanIp: values['WAN'] ?? '',
    wanUnit: unit == 1 ? 1 : 0,
    wanKind: values['WANKIND'] ?? '',
    ddns: values['DDNSON'] == '1' ? values['DDNS'] ?? '' : '',
    hostname: values['HOST'] ?? '',
    domain: values['DOMAIN'] ?? '',
    lanIp: values['LAN'] ?? '',
  );
}
