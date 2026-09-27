// input_checks.dart - what a typed value has to look like before it goes near the router (ID-237).
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
// Every check returns the sentence to show the user, or null when the value is fine, so each screen
// can collect them and show them together. One place for the rules, so a DNS field means the same
// thing on every screen that has one.
//
// Why this exists: on 2026-09-26/27 a DoH address field held two addresses, and then the URL and
// address fields held each other's values. Nothing refused either, and the watchdog script built a
// curl command that silently did the wrong thing. An audit then found the same gap on most of the
// fields that reach the router.

import 'router_watchdog.dart' show isValidIpv4;

/// The addresses in a list, which people write with commas, spaces or both.
List<String> addressesIn(String raw) => [
      for (final p in raw.split(RegExp(r'[,\s]+')))
        if (p.trim().isNotEmpty) p.trim(),
    ];

/// One to [max] IPv4 addresses. Null when [raw] is fine.
String? checkIpv4List(String raw, {required String field, int max = 2, bool required = true}) {
  final list = addressesIn(raw);
  if (list.isEmpty) return required ? '$field is required.' : null;
  final bad = list.where((a) => !isValidIpv4(a)).toList();
  if (bad.isNotEmpty) return '$field: "${bad.first}" is not an IPv4 address, like 9.9.9.9.';
  if (list.length > max) return '$field takes at most $max addresses.';
  return null;
}

/// A single IPv4 address.
String? checkIpv4(String raw, {required String field}) {
  final v = raw.trim();
  if (v.isEmpty) return '$field is required.';
  if (!isValidIpv4(v)) return '$field: "$v" is not an IPv4 address, like 8.8.8.8.';
  return null;
}

final RegExp _hostname = RegExp(r'^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');

/// A hostname, like smtp.gmail.com. Not an address, not a URL.
bool isHostname(String raw) => _hostname.hasMatch(raw.trim()) && !isValidIpv4(raw.trim());

final RegExp _dohUrlShape = RegExp(r'^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/+=?&:-]*)?$');

/// Control characters: a newline in a stored value becomes a new line in an email header or a
/// log, and nothing typed into a single-line field needs one.
final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');

/// Whether [raw] holds a control character.
bool hasControlCharacter(String raw) => _control.hasMatch(raw);

/// An encrypted DNS URL: `https://` and a hostname. The router's curl refuses an address there,
/// and without a hostname the watchdog has no encrypted lookup to build.
String? checkDohUrl(String raw) {
  final v = raw.trim();
  final uri = Uri.tryParse(v);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return isValidIpv4(v) || addressesIn(v).every(isValidIpv4)
        ? 'DoH URL: "$v" is an address. The URL goes here, like https://dns.quad9.net/dns-query, and '
            'the address in "DoH server address".'
        : 'DoH URL must start with https:// and name a server, like https://dns.quad9.net/dns-query.';
  }
  if (isValidIpv4(uri.host)) return 'DoH URL must name the server by its hostname, not its address.';
  // The URL is written into the watchdog script inside double quotes, so a `$`, backtick, quote or
  // backslash in its path would run as shell on every check. No DoH URL needs any of them.
  if (!_dohUrlShape.hasMatch(v) || !isHostname(uri.host)) {
    return 'DoH URL: only letters, digits and . - _ ~ / % + = ? & : are allowed, like https://dns.quad9.net/dns-query.';
  }
  return null;
}

/// The watchdog's own encrypted DNS: both fields or neither, each the right shape.
List<String> checkDohPair(String url, String ip) {
  final u = url.trim(), a = ip.trim();
  if (u.isEmpty && a.isEmpty) return const [];
  if (u.isEmpty || a.isEmpty) {
    return ['The watchdog\'s encrypted DNS needs both the DoH URL and the DoH server address, or neither.'];
  }
  return [
    if (checkDohUrl(u) case final e?) e,
    if (a.contains('://')) 'DoH server address: that is a URL. The address goes here, like 9.9.9.9, and the URL in "DoH URL".'
    else if (checkIpv4List(a, field: 'DoH server address') case final e?) e,
  ];
}

/// The DoH address list as the script uses it: comma-separated, no spaces, which is the form
/// curl's `--resolve host:443:a,b` takes (measured on the router 2026-09-27).
String normaliseAddressList(String raw) => addressesIn(raw).join(',');

/// `host:port`, with a real hostname or address and a port from 1 to 65535.
String? checkHostPort(String raw, {required String field}) {
  final v = raw.trim();
  final i = v.lastIndexOf(':');
  if (i <= 0) return '$field must be host:port, like smtp.gmail.com:465.';
  final host = v.substring(0, i), port = int.tryParse(v.substring(i + 1));
  if (!isHostname(host) && !isValidIpv4(host)) return '$field: "$host" is not a server name or address.';
  if (port == null || port < 1 || port > 65535) return '$field: the port must be a number from 1 to 65535.';
  return null;
}

/// A whole number in a range.
String? checkIntRange(String raw, {required String field, required int min, required int max}) {
  final n = int.tryParse(raw.trim());
  if (n == null || n < min || n > max) return '$field must be a whole number from $min to $max.';
  return null;
}

/// A slot's description. `<` and `>` separate the records and fields of the router's own VPN list,
/// so one of them here corrupts every VPN profile on the router, not just this one. Spaces are
/// allowed: a profile made in the router's web interface can have them.
String? checkSlotDescription(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'The description is required.';
  if (RegExp(r'[<>"]').hasMatch(v) || hasControlCharacter(v)) return 'The description cannot contain < > or ".';
  return null;
}

/// A WireGuard key: 44 characters of base64 ending in `=`.
String? checkWireGuardKey(String raw, {required String field}) =>
    RegExp(r'^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$').hasMatch(raw.trim())
        ? null
        : '$field must be a WireGuard key: 44 characters ending in =.';

/// One IPv4 address with a prefix length, like 10.0.0.2/32.
bool isIpv4Cidr(String raw) {
  final parts = raw.trim().split('/');
  if (parts.length != 2 || !isValidIpv4(parts[0])) return false;
  final p = int.tryParse(parts[1]);
  return p != null && p >= 0 && p <= 32;
}

/// A comma-separated list of CIDRs, like 0.0.0.0/0.
String? checkCidrList(String raw, {required String field}) {
  final list = addressesIn(raw);
  if (list.isEmpty) return '$field is required.';
  final bad = list.where((c) => !isIpv4Cidr(c)).toList();
  return bad.isEmpty ? null : '$field: "${bad.first}" is not an address with a prefix, like 10.0.0.2/32.';
}

/// Everything wrong with a slot's parameters from MANAGE -> EDIT, in the order the form shows them.
List<String> slotParamErrors(Map<String, String> p) => [
      if (p.containsKey('desc')) if (checkSlotDescription(p['desc']!) case final e?) e,
      if (p.containsKey('addr') && !isIpv4Cidr(p['addr']!)) 'Address must be like 10.0.0.2/32.',
      if (p.containsKey('ep_addr') && !isValidIpv4(p['ep_addr']!) && !isHostname(p['ep_addr']!))
        'Endpoint must be a server address or name.',
      if (p.containsKey('ep_port')) if (checkIntRange(p['ep_port']!, field: 'Endpoint port', min: 1, max: 65535) case final e?) e,
      if (p.containsKey('ppub')) if (checkWireGuardKey(p['ppub']!, field: 'Server public key') case final e?) e,
      if (p.containsKey('priv')) if (checkWireGuardKey(p['priv']!, field: 'Private key') case final e?) e,
      if (p.containsKey('dns')) if (checkIpv4List(p['dns']!, field: 'DNS servers') case final e?) e,
      if (p.containsKey('mtu')) if (checkIntRange(p['mtu']!, field: 'MTU', min: 1280, max: 1500) case final e?) e,
      if (p.containsKey('alive')) if (checkIntRange(p['alive']!, field: 'Keepalive', min: 0, max: 65535) case final e?) e,
      if (p.containsKey('aips')) if (checkCidrList(p['aips']!, field: 'Allowed IPs') case final e?) e,
    ];
