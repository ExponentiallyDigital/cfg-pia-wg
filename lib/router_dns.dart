// router_dns.dart - what SETTINGS' ROUTER RESOLVER STATUS and ROUTER DNS ROUTING show (ID-194).
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
// Everything here only READS the router. The commands are built here, the answers parsed here, and
// both screens are described as a list of [DnsBlock]s, so the whole of it is testable without a
// widget or a router. The shapes parsed were measured on a stock router on 2026-09-27: BusyBox
// nslookup's output, `ip rule`'s `iif lo` rules, the VPN_FUSION chain with a device pinned and
// without, and the resolver files themselves.
import 'package:dartssh2/dartssh2.dart';

import 'device_assignment.dart'
    show DevicePolicy, deviceNamesByIp, kDeviceSourcesCommand, parseDeviceSources, parseDevicePolicyList;
import 'firmware.dart' show RouterFirmware, classifyFirmwareTag;
import 'input_checks.dart' show addressesIn;
import 'router_command.dart' show runRouterCommand;
import 'merlin_vpn_director.dart'
    show defaultRuleFor, kVpnDirectorRulelistPath, lanSubnet, merlinPolicies, parseMerlinSlots, parseVpnDirectorRules;
import 'router_slot_service.dart' show VpncRecord, parseVpncClientlist, slotLabel;
import 'router_watchdog.dart' show dohDescription;

// ── The report both screens are drawn from ───────────────────────────────────────────

/// One piece of a report screen, in the order it is shown.
sealed class DnsBlock {
  const DnsBlock();
}

/// A small teal label that starts a group of blocks ("YOUR DEVICES' LOOKUPS").
class DnsGroup extends DnsBlock {
  const DnsGroup(this.title);
  final String title;
}

/// A one-line statement of fact. [lead] marks the one at the top of a screen, drawn larger.
class DnsVerdict extends DnsBlock {
  const DnsVerdict(this.text, {this.lead = false});
  final String text;
  final bool lead;
}

/// "checked 04:08:12": when the router was read.
class DnsStamp extends DnsBlock {
  const DnsStamp(this.text);
  final String text;
}

/// A file, or a command's output, with a line saying what it is for.
class DnsFile extends DnsBlock {
  const DnsFile({required this.name, required this.role, required this.content, this.written, this.caution});
  final String name, role, content;

  /// When the firmware last wrote it, `HH:MM`, or null for something that is not a file.
  final String? written;

  /// An amber note: what to take care over before sharing a copy.
  final String? caution;
}

/// The live check, one row per resolver, and what to do when a row failed.
class DnsCheck extends DnsBlock {
  const DnsCheck({required this.rows, required this.checkedAt, this.advice});
  final List<DnsCheckRow> rows;
  final String checkedAt;
  final String? advice;
}

enum DnsCheckState { ok, failed, notUsed }

class DnsCheckRow {
  const DnsCheckRow({
    required this.who,
    required this.state,
    this.addresses = const [],
    this.detail = '',
    this.running,
    this.ms,
  });
  final String who;
  final DnsCheckState state;

  /// Every address the lookup returned, in the order it returned them.
  final List<String> addresses;

  /// Why it failed, or why it was not run.
  final String detail;

  /// Whether the program is running, or null when that was not read.
  final bool? running;

  /// How long the lookup took on the router, or null when it did not finish.
  final int? ms;
}

enum DnsTagKind { tunnel, internet, neutral, encrypted, plain }

class DnsTag {
  const DnsTag(this.label, this.kind);
  final String label;
  final DnsTagKind kind;
}

/// A line of the routing screen: what is looked up, where it goes, and whether anyone can read it.
class DnsFlowLine {
  const DnsFlowLine({required this.head, this.rest = '', this.note = '', required this.where, this.encryption});
  final String head, rest, note;
  final DnsTag where;
  final DnsTag? encryption;
}

class DnsFlow extends DnsBlock {
  const DnsFlow(this.lines);
  final List<DnsFlowLine> lines;
}

/// The report as plain text, for COPY: what the screen says, in the order it says it.
///
/// One function per kind of block since build 509 (ID-041 step 2); test/unit/router_dns_golden_test.dart
/// holds the text to what it was before the split.
String dnsReportText(String title, List<DnsBlock> blocks) => '$title\n${blocks.map(_blockText).join()}';

String _blockText(DnsBlock b) => switch (b) {
      DnsGroup(:final title) => '\n== $title ==\n',
      DnsVerdict(:final text) => '$text\n',
      DnsStamp(:final text) => '$text\n',
      DnsFile() => _fileText(b),
      DnsCheck() => _checkText(b),
      DnsFlow(:final lines) => lines.map(_flowLineText).join(),
    };

String _fileText(DnsFile f) =>
    '\n${f.name}${f.written == null ? '' : ' (written ${f.written})'}\n${f.role}\n${f.caution == null ? '' : '${f.caution}\n'}${f.content}\n';

String _checkText(DnsCheck c) =>
    '${c.rows.map(_checkRowText).join()}${c.advice == null ? '' : '${c.advice}\n'}${c.checkedAt}\n';

String _checkRowText(DnsCheckRow r) {
  final state = switch (r.state) {
    DnsCheckState.ok => 'OK',
    DnsCheckState.failed => 'FAILED',
    DnsCheckState.notUsed => 'NOT USED',
  };
  final extra = [
    if (r.running != null) r.running! ? 'running' : 'not running',
    if (r.ms != null) '${r.ms} ms',
  ];
  return '${r.who}: $state'
      '${r.addresses.isEmpty ? '' : ' ${r.addresses.join(', ')}'}'
      '${r.detail.isEmpty ? '' : ' ${r.detail}'}'
      '${extra.isEmpty ? '' : ' (${extra.join(', ')})'}\n';
}

String _flowLineText(DnsFlowLine l) {
  final tags = [l.where.label, if (l.encryption != null) l.encryption!.label].join(', ');
  return '${l.head}${l.rest} [$tags]${l.note.isEmpty ? '' : ' - ${l.note}'}\n';
}

// ── Reading the router ────────────────────────────────────────────────────────────────

/// ROUTER DNS ROUTING's section headings. The screen colours any of them named in a box's text as it
/// colours the heading itself, so a pointer to a section reads as one (ID-581).
const String kDnsDevicesHeading = "YOUR DEVICES' LOOKUPS";
const String kDnsRouterHeading = "THE ROUTER'S OWN LOOKUPS";
const String kDnsWatchdogsHeading = "THE WATCHDOGS' LOOKUPS";
const String kDnsSlotsHeading = "THE SLOTS' DNS SERVERS";
const String kDnsEvidenceHeading = 'EVIDENCE';
const List<String> kDnsSectionHeadings = [
  kDnsDevicesHeading,
  kDnsRouterHeading,
  kDnsWatchdogsHeading,
  kDnsSlotsHeading,
  kDnsEvidenceHeading,
];

/// [text] in pieces, each a section heading or not, in order: for the screen to colour the headings.
List<(String, bool)> splitOnHeadings(String text) {
  final out = <(String, bool)>[];
  final re = RegExp(kDnsSectionHeadings.map(RegExp.escape).join('|'));
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) out.add((text.substring(at, m.start), false));
    out.add((m.group(0)!, true));
    at = m.end;
  }
  if (at < text.length) out.add((text.substring(at), false));
  return out;
}

/// Where dnsmasq answers the router itself, when the router uses it as its own resolver.
const String kDnsmasqAddress = '127.0.0.1';

/// Where stubby listens, on stock and Merlin alike. A resolver line naming it means DNS-over-TLS is on.
const String kStubbyAddress = '127.0.1.1';

/// dnsmasq's configuration: the router's DNS and DHCP server.
const String kDnsmasqConf = '/etc/dnsmasq.conf';

/// Where dnsmasq forwards the lookups it can't answer itself.
const String kResolvDnsmasq = '/tmp/resolv.dnsmasq';

/// The router's own resolver list.
const String kResolvConf = '/etc/resolv.conf';

/// The resolver files, in the order a device's lookup travels through them, then the router's own.
const List<String> kResolverFiles = [
  kDnsmasqConf,
  '/etc/hosts',
  kResolvDnsmasq,
  '/etc/stubby/stubby.yml',
  kResolvConf,
];

/// Each file under a marker line carrying its path and when it was last written. `date -r` follows
/// the /etc/resolv.conf link to the file it points at, whose time means something; the link's own
/// is 1970 (measured 2026-09-27).
String resolverFilesCommand([List<String> paths = kResolverFiles]) => [
      for (final p in paths) 'echo "@@FILE $p \$(date -r $p \'+%H:%M\' 2>/dev/null)"; cat $p 2>/dev/null',
    ].join('; ');

/// Whether each resolver is running, then the DNS settings the files are built from.
const String kResolverFactsCommand = 'echo "@@dnsmasq \$(pidof dnsmasq)"; echo "@@stubby \$(pidof stubby)"; '
    'echo "@@NVRAM"; nvram show 2>/dev/null | grep -E \'^(wan0_dns|dnspriv_)\' | sort';

/// Looks up example.com through dnsmasq and, when [withStubby], stubby too, side by side.
///
/// Bounded by hand, as the watchdog's own name check is: this BusyBox has no `timeout`, and its
/// nslookup waits 20 seconds for a server that does not answer. Each lookup times itself from
/// /proc/uptime, which counts in hundredths of a second, so the time is the lookup's own and not
/// the SSH round trip's.
String dnsCheckCommand({required bool withStubby}) {
  String one(String tag, String server) => '( T0=\$(cut -d" " -f1 /proc/uptime); '
      'nslookup example.com $server > \$D/$tag 2>&1; echo "@@RC \$?" >> \$D/$tag; '
      'echo "@@T \$T0 \$(cut -d" " -f1 /proc/uptime)" >> \$D/$tag ) & ${tag.toUpperCase()}=\$!';
  final tags = withStubby ? ['a', 'b'] : ['a'];
  final alive = tags.map((t) => 'kill -0 \$${t.toUpperCase()} 2>/dev/null').join(' || ');
  return [
    'D=/tmp/cfgpw_dns_\$\$; mkdir -p \$D',
    one('a', '127.0.0.1'),
    if (withStubby) one('b', kStubbyAddress),
    'W=0; while [ \$W -lt 5 ] && { $alive; }; do sleep 1; W=\$((W+1)); done',
    'kill -9 ${tags.map((t) => '\$${t.toUpperCase()}').join(' ')} 2>/dev/null',
    'for X in ${tags.join(' ')}; do echo "@@CHECK \$X"; cat \$D/\$X 2>/dev/null; done; rm -rf \$D',
  ].join('; ');
}

/// What ROUTER DNS ROUTING reads, in one round trip.
const String kDnsRoutingCommand = 'echo "@@RESOLV"; cat /etc/resolv.conf 2>/dev/null; '
    'echo "@@DNSMASQ"; cat /tmp/resolv.dnsmasq 2>/dev/null; '
    'echo "@@RULES"; ip rule show | grep "iif lo"; '
    // Stock's redirects are VPN Fusion's chain; Merlin's are VPN Director's, one chain per slot (ID-581).
    'echo "@@FUSION"; iptables -t nat -S VPN_FUSION 2>/dev/null; iptables -t nat -S 2>/dev/null | grep -E "^-A DNSVPN[0-9]+ "; '
    'echo "@@VPNDIRECTOR"; cat $kVpnDirectorRulelistPath 2>/dev/null; echo; '
    'echo "@@NVRAM"; nvram show 2>/dev/null | grep -E '
    '\'^(vpnc_clientlist|vpnc_dev_policy_list|dnspriv_enable|dnspriv_rulelist|wan0_dnsenable_x|lan_ipaddr|lan_netmask|'
    'wgc[1-5]_(desc|enable|dns|wd_doh_url|wd_doh_ip|wd_check_interval))=\'; '
    '$kDnsRouteGetCommand';

/// Where each address this screen names ACTUALLY goes, asked of the kernel (ID-337).
///
/// Until build 483 the tags were worked out from the `iif lo` rules alone. That missed Merlin's
/// main-table route for a slot's DNS server through its tunnel (ID-306: the screen said "No lookups
/// go through a tunnel" while the router's own lookups did), called a tunnel "encrypted to PIA"
/// while it was down, and stamped "tunnel" on every pinned device's redirect without routing its
/// target. Now: `ip route get` for every resolver, DoT, DoH and slot DNS address, each pinned
/// device's redirect target routed FROM that device, and which interfaces are up.
const String kDnsRouteGetCommand = r'''echo "@@ROUTES"; for A in $( (awk '/^nameserver/ {print $2}' /etc/resolv.conf; sed -n 's/^server=//p' /tmp/resolv.dnsmasq; nvram get dnspriv_rulelist | tr '<>' '\n\n'; for N in 1 2 3 4 5; do nvram get wgc${N}_dns | tr ', ' '\n\n'; nvram get wgc${N}_wd_doh_ip | tr ', ' '\n\n'; done) 2>/dev/null | grep -E '^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$' | sort -u); do echo "$A $(ip route get "$A" 2>&1 | head -1)"; done; echo "@@PINNEDROUTES"; iptables -t nat -S 2>/dev/null | grep -E '^-A (VPN_FUSION|DNSVPN[0-9]+) ' | awk '{s = ""; d = ""; for (i = 1; i < NF; i++) {if ($i == "-s") s = $(i + 1); if ($i == "--to-destination") d = $(i + 1)} sub("/32", "", s); if (s != "" && d != "" && index(s, "/") == 0) print s, d}' | while read -r S D; do echo "$S $D $(ip route get "$D" from "$S" iif br0 2>&1 | head -1)"; done; echo "@@UP"; ip -o link show up | awk -F': ' '{print $2}' ''';

// ── Parsing ───────────────────────────────────────────────────────────────────────────

/// Output split at lines starting with `@@`, keyed by the rest of that line.
Map<String, String> splitMarked(String output) {
  final out = <String, String>{};
  String? key;
  final buf = StringBuffer();
  void flush() {
    if (key case final k?) out[k] = buf.toString().trimRight();
    buf.clear();
  }

  for (final line in output.split('\n')) {
    if (line.startsWith('@@')) {
      flush();
      key = line.substring(2).trim();
      continue;
    }
    if (key != null) buf.writeln(line);
  }
  flush();
  return out;
}

/// `NAME=value` lines, as `nvram show` prints them.
Map<String, String> parseNvramLines(String raw) => {
      for (final line in raw.split('\n'))
        if (line.contains('=')) line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim(),
    };

/// Each lookup's output from [dnsCheckCommand], by its tag. Split on `@@CHECK` alone: a lookup's
/// own `@@RC` and `@@T` lines belong to it.
Map<String, String> splitChecks(String output) {
  final out = <String, String>{};
  for (final part in output.split(RegExp(r'^@@CHECK ', multiLine: true)).skip(1)) {
    final nl = part.indexOf('\n');
    out[(nl < 0 ? part : part.substring(0, nl)).trim()] = nl < 0 ? '' : part.substring(nl + 1);
  }
  return out;
}

class ResolverFile {
  const ResolverFile(this.path, this.written, this.content);
  final String path;
  final String? written;
  final String content;
}

/// The files from [resolverFilesCommand], in the order they were read.
List<ResolverFile> parseResolverFiles(String output) {
  final files = <ResolverFile>[];
  for (final e in splitMarked(output).entries) {
    if (!e.key.startsWith('FILE ')) continue;
    final parts = e.key.substring(5).trim().split(RegExp(r'\s+'));
    files.add(ResolverFile(parts.first, parts.length > 1 ? parts[1] : null, e.value));
  }
  return files;
}

class NslookupResult {
  const NslookupResult({required this.finished, required this.exitCode, required this.addresses, this.ms, this.error = ''});
  final bool finished;
  final int? exitCode;
  final List<String> addresses;
  final int? ms;
  final String error;
  bool get ok => finished && exitCode == 0 && addresses.isNotEmpty;
}

/// One lookup's output from [dnsCheckCommand].
///
/// BusyBox prints the server it asked first, as `Address 1: 127.0.0.1 localhost`, so only the
/// `Address` lines after `Name:` are answers. Newer BusyBox prints `Address: x`, taken as well.
NslookupResult parseNslookup(String raw) {
  final addresses = <String>[];
  var afterName = false;
  int? rc, ms;
  var error = '';
  for (final line in raw.split('\n').map((l) => l.trim())) {
    if (line.startsWith('@@RC ')) {
      rc = int.tryParse(line.substring(5).trim());
    } else if (line.startsWith('@@T ')) {
      final t = line.substring(4).trim().split(RegExp(r'\s+')).map(double.tryParse).toList();
      if (t.length == 2 && t[0] != null && t[1] != null) ms = ((t[1]! - t[0]!) * 1000).round();
    } else if (line.startsWith('Name:')) {
      afterName = true;
    } else if (afterName) {
      final m = RegExp(r'^Address(?:\s+\d+)?:\s*(\S+)').firstMatch(line);
      if (m != null) addresses.add(m.group(1)!);
    } else if (line.contains("can't resolve") || line.contains('timed out') || line.contains('NXDOMAIN')) {
      error = line;
    }
  }
  return NslookupResult(finished: rc != null, exitCode: rc, addresses: addresses, ms: ms, error: error);
}

/// `ip rule` lines of the form `1016: from all to 9.9.9.9 iif lo lookup 5`.
class DnsRule {
  const DnsRule(this.priority, this.address, this.table, this.line);
  final int priority;
  final String address, table, line;
}

List<DnsRule> parseDnsRules(String raw) => [
      for (final line in raw.split('\n'))
        if (RegExp(r'^(\d+):\s+from all to (\S+) iif lo lookup (\S+)').firstMatch(line.trim()) case final m?)
          DnsRule(int.parse(m.group(1)!), m.group(2)!, m.group(3)!, line.trim()),
    ];

/// VPN_FUSION's DNAT lines: the device address, and the DNS server its lookups are sent to.
Map<String, String> parseFusionRedirects(String raw) {
  final out = <String, String>{};
  for (final line in raw.split('\n')) {
    // A device's address only (/32 or bare): Merlin's whole-network redirect is read by
    // [parseNetworkRedirect]. The first redirect for a device is the one it's shown with; Merlin
    // writes one per DNS server (ID-581).
    if (RegExp(r'-s (\d+\.\d+\.\d+\.\d+)(?:/32)?\s.*--to-destination (\d+\.\d+\.\d+\.\d+)').firstMatch(line) case final m?) {
      out.putIfAbsent(m.group(1)!, () => m.group(2)!);
    }
  }
  return out;
}

/// Merlin's redirect for a whole network, `-s 192.168.1.0/24 ... --to-destination 9.9.9.9`: the
/// network and its first target, or null when there is none.
(String, String)? parseNetworkRedirect(String raw) {
  for (final line in raw.split('\n')) {
    final m = RegExp(r'-s (\d+\.\d+\.\d+\.\d+/(\d+))\s.*--to-destination (\d+\.\d+\.\d+\.\d+)').firstMatch(line);
    if (m != null && m.group(2) != '32') return (m.group(1)!, m.group(3)!);
  }
  return null;
}

/// `nameserver` addresses in a resolv.conf, in order.
List<String> parseNameservers(String raw) => [
      for (final line in raw.split('\n'))
        if (RegExp(r'^\s*nameserver\s+(\S+)').firstMatch(line) case final m?) m.group(1)!,
    ];

/// `server=` addresses in /tmp/resolv.dnsmasq, in order.
List<String> parseDnsmasqServers(String raw) => [
      for (final line in raw.split('\n'))
        if (RegExp(r'^\s*server=(\S+)').firstMatch(line) case final m?) m.group(1)!,
    ];

/// The DoT Server List's addresses, in order, from `dnspriv_rulelist`.
List<String> parseDotAddresses(String rulelist) => [
      for (final record in rulelist.split('<'))
        if (record.split('>').first.trim().isNotEmpty) record.split('>').first.trim(),
    ];

// ── ROUTER RESOLVER STATUS ─────────────────────────────────────────────────────────────

String _role(String path) => switch (path) {
      kDnsmasqConf =>
        "The router's DNS and DHCP server: how it answers your devices' lookups, and which address each device gets.",
      '/etc/hosts' =>
        'Names dnsmasq answers without asking anyone. The watchdog adds your mail server here for a moment while it sends an alert.',
      kResolvDnsmasq => "Where dnsmasq sends your devices' lookups it can't answer itself.",
      '/etc/stubby/stubby.yml' => 'stubby, the DNS-over-TLS client: the encrypted servers it forwards lookups to.',
      kResolvConf => "The router's own lookups: your DNS Server setting, then stubby when DNS-over-TLS is on.",
      _ => '',
    };

String _group(String path) => path == kResolvConf ? "THE ROUTER'S OWN LOOKUPS" : "YOUR DEVICES' LOOKUPS";

/// What to do about a failed check, from which resolver failed and whether it is running. Null
/// when nothing failed. Facts and a next step, never a guess at the cause.
String? resolverAdvice({
  required NslookupResult dnsmasq,
  required bool dnsmasqRunning,
  required NslookupResult? stubby,
  required bool stubbyRunning,
  required bool dotOn,
}) {
  const unpinned = "devices that aren't pinned to a VPN can't look names up";
  if (!dnsmasqRunning) return "dnsmasq, the router's DNS server, isn't running, so $unpinned. Reboot the router.";
  if (dotOn && !stubbyRunning) {
    return "stubby, the DNS-over-TLS client, isn't running, so $unpinned. Reboot the router.";
  }
  final stubbyFailed = dotOn && stubby != null && !stubby.ok;
  if (!dnsmasq.ok && stubbyFailed) {
    return "stubby is running but can't reach your DNS-over-TLS servers, so $unpinned. "
        'Check the DoT Server List in the web interface, or reboot the router.';
  }
  if (!dnsmasq.ok && dotOn) return "dnsmasq isn't answering, though stubby is, so $unpinned. Reboot the router.";
  if (!dnsmasq.ok) {
    return "dnsmasq is running but can't get an answer from your DNS servers, so $unpinned. "
        'Check the WAN DNS settings in the web interface, or reboot the router.';
  }
  if (stubbyFailed) {
    return "stubby can't reach your DNS-over-TLS servers. dnsmasq answered from what it remembers, "
        'so lookups will start to fail as that runs out. Check the DoT Server List in the web interface, '
        'or reboot the router.';
  }
  return null;
}

/// Why a lookup failed, or nothing when it worked.
String _checkDetail(NslookupResult r) {
  if (r.ok) return '';
  if (!r.finished) return 'no answer in 5 s';
  return r.error.isEmpty ? 'no answer' : r.error;
}

DnsCheckRow _row(String who, NslookupResult r, bool running) => DnsCheckRow(
      who: who,
      state: r.ok ? DnsCheckState.ok : DnsCheckState.failed,
      addresses: r.addresses,
      detail: _checkDetail(r),
      running: running,
      ms: r.ok ? r.ms : null,
    );

/// The whole ROUTER RESOLVER STATUS screen, from the three commands' output.
List<DnsBlock> buildResolverStatus({
  required String facts,
  required String checks,
  required String files,
  required String checkedAt,
}) {
  final f = splitMarked(facts);
  // `pidof` prints nothing for a program that is not running, so the marker line stands alone.
  final dnsmasqRunning = RegExp(r'^@@dnsmasq \d', multiLine: true).hasMatch(facts);
  final stubbyRunning = RegExp(r'^@@stubby \d', multiLine: true).hasMatch(facts);
  final parsed = parseResolverFiles(files);
  final dnsmasqServers = parseDnsmasqServers(
      parsed.firstWhere((x) => x.path == kResolvDnsmasq, orElse: () => const ResolverFile('', null, '')).content);
  final dotOn = dnsmasqServers.contains(kStubbyAddress);
  final c = splitChecks(checks);
  final a = parseNslookup(c['a'] ?? '');
  final b = dotOn ? parseNslookup(c['b'] ?? '') : null;

  final blocks = <DnsBlock>[
    DnsCheck(
      rows: [
        _row('dnsmasq', a, dnsmasqRunning),
        if (b != null)
          _row('stubby', b, stubbyRunning)
        else
          DnsCheckRow(
              who: 'stubby', state: DnsCheckState.notUsed, detail: 'DNS-over-TLS is off', running: stubbyRunning),
      ],
      checkedAt: 'checked $checkedAt',
      advice: resolverAdvice(
          dnsmasq: a, dnsmasqRunning: dnsmasqRunning, stubby: b, stubbyRunning: stubbyRunning, dotOn: dotOn),
    ),
  ];
  String? group;
  for (final file in parsed) {
    final g = _group(file.path);
    if (g != group) blocks.add(DnsGroup(group = g));
    blocks.add(DnsFile(
      name: file.path,
      written: file.written,
      role: _role(file.path),
      content: file.content.isEmpty ? '(not present)' : file.content,
      caution: file.path == kDnsmasqConf && file.content.contains('dhcp-host=')
          ? "Lists every reserved device's MAC and address: review before sharing."
          : null,
    ));
  }
  blocks
    ..add(const DnsGroup('SETTINGS'))
    ..add(DnsFile(
      name: 'Active DNS settings (nvram)',
      role: 'What you set in the web interface. The files above are built from these; if they disagree, the router '
          'needs a restart.',
      content: (f['NVRAM'] ?? '').isEmpty ? '(none read)' : f['NVRAM']!,
    ));
  return blocks;
}

// ── ROUTER DNS ROUTING ─────────────────────────────────────────────────────────────────

const _internet = DnsTag('Internet', DnsTagKind.internet);
const _dot = DnsTag('encrypted (DoT)', DnsTagKind.encrypted);
const _doh = DnsTag('encrypted (DoH)', DnsTagKind.encrypted);
const _pia = DnsTag('encrypted to PIA', DnsTagKind.encrypted);
const _plain = DnsTag('not encrypted', DnsTagKind.plain);

/// Everything ROUTER DNS ROUTING knows about the router, parsed once.
class DnsRouting {
  DnsRouting({
    required this.nameservers,
    required this.dnsmasqServers,
    required this.rules,
    required this.redirects,
    required this.fusionRaw,
    required this.nvram,
    required this.names,
    required this.merlin,
    this.routes = const {},
    this.pinnedRoutes = const [],
    this.up = const {},
    this.vpnDirectorRaw = '',
  }) {
    if (merlin) {
      // Merlin has neither of stock's lists: its slots and VPN Director's rules, in the same shapes
      // DEVICES uses (ID-581).
      records = parseMerlinSlots([for (var s = 1; s <= 5; s++) '$s>${nvram['wgc${s}_desc'] ?? ''}>${nvram['wgc${s}_enable'] ?? ''}'].join('\n'));
      policies = merlinPolicies(parseVpnDirectorRules(vpnDirectorRaw));
    } else {
      records = parseVpncClientlist(nvram['vpnc_clientlist'] ?? '');
      policies = parseDevicePolicyList(nvram['vpnc_dev_policy_list'] ?? '');
    }
  }

  /// VPN Director's rules file, as read on Merlin.
  final String vpnDirectorRaw;

  /// On Merlin, the whole-network rule's redirect: every device that isn't pinned has its lookups to
  /// the router sent here, through the default's tunnel. Null on stock, or with no such rule.
  (String, String)? get networkRedirect => merlin ? parseNetworkRedirect(fusionRaw) : null;

  /// On Merlin, the slot the whole-network rule sends every other device to.
  int? get networkSlot {
    if (!merlin) return null;
    final subnet = lanSubnet(nvram['lan_ipaddr'] ?? '', nvram['lan_netmask'] ?? '');
    return defaultRuleFor(parseVpnDirectorRules(vpnDirectorRaw), subnet)?.wgSlot;
  }

  final List<String> nameservers, dnsmasqServers;
  final List<DnsRule> rules;
  final Map<String, String> redirects;
  final String fusionRaw;
  final Map<String, String> nvram;

  /// Device address to the name DEVICE ASSIGNMENT shows.
  final Map<String, String> names;
  final bool merlin;

  /// Each address to the first line of `ip route get` for it, as the router's own traffic (ID-337).
  final Map<String, String> routes;

  /// Each pinned device's redirect: (device, target, the first line of `ip route get` for the target
  /// from that device) (ID-337).
  final List<(String, String, String)> pinnedRoutes;

  /// Interfaces that are up.
  final Set<String> up;

  /// Where a route actually goes, read from `ip route get`'s answer: a tunnel only while it is up;
  /// the internet; or nowhere, when the kernel refuses the route.
  DnsTag tagForRoute(String line) {
    if (RegExp(r'RTNETLINK|unreachable|prohibit|blackhole|Invalid argument').hasMatch(line)) {
      return const DnsTag('nowhere: blocked', DnsTagKind.neutral);
    }
    final dev = RegExp(r' dev (\S+)').firstMatch(line)?.group(1);
    // stubby listens on 127.0.1.1: a lookup to it never leaves the router.
    if (dev == 'lo') return const DnsTag('this router', DnsTagKind.neutral);
    // A resolver on the LAN (a Pi-hole, say): it doesn't leave by the internet from here.
    if (dev != null && RegExp(r'^br\d+$').hasMatch(dev)) return const DnsTag('your network', DnsTagKind.neutral);
    final slot =dev == null ? null : int.tryParse(RegExp(r'^wgc(\d)$').firstMatch(dev)?.group(1) ?? '');
    if (slot == null) return _internet;
    return up.contains(dev) ? DnsTag(label(slot), DnsTagKind.tunnel) : DnsTag('${label(slot)}, which is down', DnsTagKind.neutral);
  }
  late final List<VpncRecord> records;
  late final List<DevicePolicy> policies;

  String desc(int slot) {
    for (final r in records) {
      if (r.slot == slot && r.desc.trim().isNotEmpty) return r.desc.trim();
    }
    return (nvram['wgc${slot}_desc'] ?? '').trim();
  }

  bool configured(int slot) => desc(slot).isNotEmpty;
  String label(int slot) => configured(slot) ? slotLabel(slot, desc(slot)) : 'wgc$slot';

  /// The slot whose routing table is [table]: index 6 of its clientlist record (ARCHITECTURE 5.3).
  int? slotForTable(String table) {
    for (final r in records) {
      if ('${r.vpncStateIndex}' == table && r.slot != null) return r.slot;
    }
    return null;
  }

  int? slotForIndex(int? index) => index == null ? null : slotForTable('$index');

  /// The rule the router's own lookups to [address] follow, or null for the main table. The lowest
  /// priority number wins, which is the highest-numbered slot (ROUTER-DNS.md).
  DnsRule? ruleFor(String address) {
    final matching = rules.where((r) => r.address == address).toList()..sort((a, b) => a.priority.compareTo(b.priority));
    return matching.isEmpty ? null : matching.first;
  }

  String tableLabel(String table) {
    final slot = slotForTable(table);
    return slot == null ? 'table $table' : label(slot);
  }

  DnsTag whereFor(String address) {
    // What the kernel says, when it was asked (ID-337); the rules alone missed Merlin's main-table
    // routes and could not tell an up tunnel from a down one.
    if (routes[address] case final line?) return tagForRoute(line);
    final rule = ruleFor(address);
    return rule == null ? _internet : DnsTag(tableLabel(rule.table), DnsTagKind.tunnel);
  }

  /// One tag for several addresses: the path they share, or each path when they differ.
  DnsTag whereForAll(List<String> addresses) {
    final tags = {for (final a in addresses) whereFor(a).label};
    if (tags.length <= 1) return addresses.isEmpty ? _internet : whereFor(addresses.first);
    return DnsTag(tags.join(' / '), DnsTagKind.tunnel);
  }

  List<String> get dotServers => parseDotAddresses(nvram['dnspriv_rulelist'] ?? '');
  bool get dotOn => dnsmasqServers.contains(kStubbyAddress);
}

DnsRouting parseDnsRouting(String output, {required Map<String, String> names, required bool merlin}) {
  final m = splitMarked(output);
  return DnsRouting(
    nameservers: parseNameservers(m['RESOLV'] ?? ''),
    dnsmasqServers: parseDnsmasqServers(m['DNSMASQ'] ?? ''),
    rules: parseDnsRules(m['RULES'] ?? ''),
    redirects: parseFusionRedirects(m['FUSION'] ?? ''),
    fusionRaw: (m['FUSION'] ?? '').trim(),
    nvram: parseNvramLines(m['NVRAM'] ?? ''),
    names: names,
    merlin: merlin,
    routes: {
      for (final l in (m['ROUTES'] ?? '').split('\n'))
        if (l.trim().split(' ').length > 1) l.trim().split(' ').first: l.trim().substring(l.trim().indexOf(' ') + 1),
    },
    pinnedRoutes: [
      for (final l in (m['PINNEDROUTES'] ?? '').split('\n'))
        if (l.trim().split(' ').length > 2)
          (l.trim().split(' ')[0], l.trim().split(' ')[1], l.trim().split(' ').skip(2).join(' ')),
    ],
    up: {for (final l in (m['UP'] ?? '').split('\n')) if (l.trim().isNotEmpty) l.trim()},
    vpnDirectorRaw: (m['VPNDIRECTOR'] ?? '').trim(),
  );
}

String _join(List<String> xs) => switch (xs.length) {
      <= 1 => xs.join(),
      2 => '${xs[0]} and ${xs[1]}',
      _ => '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}',
    };

DnsTag? _encryptionOver(DnsTag where) => switch (where.kind) {
      DnsTagKind.tunnel => _pia,
      DnsTagKind.internet => _plain,
      _ => null,
    };

/// The whole ROUTER DNS ROUTING screen.
///
/// One function per section since build 509 (ID-041 step 2); test/unit/router_dns_golden_test.dart
/// holds the screen to what it was before the split.
List<DnsBlock> buildDnsRouting(DnsRouting r, {required String readAt}) {
  final pinned = _pinnedLines(r);
  final everyone = _everyoneLine(r);
  final routerOwn = _routerOwnLines(r);
  final watchdogs = _watchdogLines(r);
  final slotDns = _slotDnsLines(r);

  return [
    // On Merlin a whole-network rule puts every device's lookups in a tunnel: said as that, not as the
    // router's own (ID-581).
    DnsVerdict(
        r.networkRedirect != null &&
                everyone.where.kind == DnsTagKind.tunnel &&
                ![...routerOwn, ...watchdogs].any((l) => l.where.kind == DnsTagKind.tunnel)
            ? "Every device's lookups go through a tunnel: pinned devices' through their own, every other device's through "
                "VPN Director's rule for the whole network."
            : _routingVerdict(pinned: pinned, others: [...routerOwn, everyone, ...watchdogs]),
        lead: true),
    DnsStamp('read $readAt'),
    const DnsGroup(kDnsDevicesHeading),
    DnsFlow([...pinned, everyone]),
    const DnsGroup(kDnsRouterHeading),
    DnsFlow(routerOwn),
    const DnsGroup(kDnsWatchdogsHeading),
    DnsFlow(watchdogs),
    const DnsGroup(kDnsSlotsHeading),
    if (slotDns.isEmpty) const DnsVerdict('No slot has DNS servers set.') else DnsFlow(slotDns),
    ..._routingEvidence(r),
  ];
}

/// Pinned devices, grouped by the slot they are pinned to: at most five lines however many are
/// pinned (agreed 2026-09-27). The redirect names the device and its DNS server; the policy list
/// says which slot it is pinned to.
List<DnsFlowLine> _pinnedLines(DnsRouting r) {
  final bySlot = <String, List<String>>{};
  final dnsFor = <String, Set<String>>{};
  final devicesFor = <String, Set<String>>{};
  for (final e in r.redirects.entries) {
    final policy = r.policies.where((p) => p.ip == e.key && p.enabled).firstOrNull;
    final slot = r.slotForIndex(policy?.vpncIndex);
    final key = slot == null ? 'another profile' : r.label(slot);
    (bySlot[key] ??= []).add(r.names[e.key] ?? e.key);
    (dnsFor[key] ??= {}).add(e.value);
    (devicesFor[key] ??= {}).add(e.key);
  }
  // Where each group's lookups actually go, routed from the devices themselves (ID-337). Worst
  // first: one device's lookups leaving by the internet is what the line has to say.
  DnsTag pinnedWhere(String key) {
    final devices = devicesFor[key] ?? const <String>{};
    final tags = [for (final pr in r.pinnedRoutes) if (devices.contains(pr.$1)) r.tagForRoute(pr.$3)];
    // Nothing was read for these devices: say so, rather than claim a tunnel.
    if (tags.isEmpty) return const DnsTag('route not read', DnsTagKind.neutral);
    return tags.firstWhere((t) => t.kind == DnsTagKind.internet,
        orElse: () => tags.firstWhere((t) => t.kind == DnsTagKind.neutral, orElse: () => tags.first));
  }

  return [
    for (final e in bySlot.entries)
      () {
        final where = pinnedWhere(e.key);
        return DnsFlowLine(
          head: e.key,
          rest: ' → ${dnsFor[e.key]!.join(', ')}',
          note: e.value.join(', '),
          where: where,
          encryption: _encryptionOver(where),
        );
      }(),
  ];
}

/// Every device's lookups that aren't pinned: through stubby when DNS-over-TLS is on, otherwise
/// straight to dnsmasq's servers.
/// The head of the line for every device not pinned.
const String _kEverythingElse = 'Everything else';

DnsFlowLine _everyoneLine(DnsRouting r) {
  // On Merlin, a whole-network VPN Director rule redirects every other device's lookups too (ID-581).
  final (network, target) = r.networkRedirect ?? ('', '');
  final slot = r.networkSlot;
  if (target.isNotEmpty && slot != null) {
    final up = r.up.contains('wgc$slot');
    final where = up ? DnsTag(r.label(slot), DnsTagKind.tunnel) : DnsTag('${r.label(slot)}, which is down', DnsTagKind.neutral);
    return DnsFlowLine(
      head: _kEverythingElse,
      rest: ' → $target',
      note: "VPN Director's rule for $network",
      where: where,
      encryption: _encryptionOver(where),
    );
  }
  final dot = r.dotServers;
  return r.dotOn
      ? DnsFlowLine(
          head: _kEverythingElse,
          rest: ' → dnsmasq → stubby → ${dot.join(', ')}',
          note: 'DNS-over-TLS',
          where: r.whereForAll(dot),
          encryption: _dot,
        )
      : DnsFlowLine(
          head: _kEverythingElse,
          rest: ' → dnsmasq → ${r.dnsmasqServers.join(', ')}',
          note: 'ordinary DNS',
          where: r.whereForAll(r.dnsmasqServers),
          encryption: _encryptionOver(r.whereForAll(r.dnsmasqServers)),
        );
}

/// The router's own resolvers, other than stubby and dnsmasq.
List<String> _ordinaryNameservers(DnsRouting r) =>
    r.nameservers.where((n) => n != kStubbyAddress && n != kDnsmasqAddress).toList();

/// The router's own lookups, one line per resolver in `/etc/resolv.conf`.
List<DnsFlowLine> _routerOwnLines(DnsRouting r) {
  final dot = r.dotServers;
  final fromIsp = r.nvram['wan0_dnsenable_x'] == '1';
  final ordinary = _ordinaryNameservers(r);
  return [
    for (final n in r.nameservers)
      if (n == kDnsmasqAddress)
        _localCacheLine(r)
      else if (n == kStubbyAddress)
        DnsFlowLine(
          head: n,
          rest: ' stubby',
          note: 'to ${_join(dot)}, ${switch (ordinary.length) {
            2 => 'only if both of the above fail',
            1 => 'only if the one above fails',
            _ => 'only if all of the above fail',
          }}',
          where: r.whereForAll(dot),
          encryption: _dot,
        )
      else
        DnsFlowLine(
          head: n,
          note: '${fromIsp ? 'from your internet provider' : 'DNS Server setting'}, ordinary DNS',
          where: r.whereFor(n),
          encryption: _encryptionOver(r.whereFor(n)),
        ),
  ];
}

/// The router's own lookups through dnsmasq, as the LAN's are: what Merlin's "Use local caching DNS
/// server as system resolver" sets (`dns_local_cache=1`). With DNS-over-TLS on, dnsmasq hands them
/// to stubby, so they are encrypted, not "ordinary DNS" as this screen said until ID-581.
DnsFlowLine _localCacheLine(DnsRouting r) {
  final dot = r.dotServers;
  return r.dotOn
      ? DnsFlowLine(
          head: kDnsmasqAddress,
          rest: ' dnsmasq → stubby → ${dot.join(', ')}',
          note: 'local caching DNS server, DNS-over-TLS',
          where: r.whereForAll(dot),
          encryption: _dot,
        )
      : DnsFlowLine(
          head: kDnsmasqAddress,
          rest: ' dnsmasq → ${r.dnsmasqServers.join(', ')}',
          note: 'local caching DNS server, ordinary DNS',
          where: r.whereForAll(r.dnsmasqServers),
          encryption: _encryptionOver(r.whereForAll(r.dnsmasqServers)),
        );
}

/// Each slot's watchdog: its encrypted DNS when it has one, otherwise the router's own resolvers.
List<DnsFlowLine> _watchdogLines(DnsRouting r) {
  final ordinary = _ordinaryNameservers(r);
  return [
    for (var slot = 1; slot <= 5; slot++)
      if (!r.configured(slot))
        DnsFlowLine(head: 'wgc$slot', where: const DnsTag('not configured', DnsTagKind.neutral))
      else if ((r.nvram['wgc${slot}_wd_check_interval'] ?? '').isEmpty)
        DnsFlowLine(head: r.label(slot), where: const DnsTag('no watchdog', DnsTagKind.neutral))
      else if (dohDescription(r.nvram['wgc${slot}_wd_doh_url'] ?? '', r.nvram['wgc${slot}_wd_doh_ip'] ?? '')
          case final doh when doh.isNotEmpty)
        DnsFlowLine(
          head: r.label(slot),
          note: doh,
          where: r.whereForAll(addressesIn(r.nvram['wgc${slot}_wd_doh_ip'] ?? '')),
          encryption: _doh,
        )
      else
        DnsFlowLine(
          head: r.label(slot),
          note: "no encrypted DNS set: the router's DNS Server setting",
          where: r.whereForAll(ordinary),
          encryption: _encryptionOver(r.whereForAll(ordinary)),
        ),
  ];
}

/// Each distinct set of slot DNS servers once, with the slots that use it, and the rules that
/// would carry the router's own lookups to it. Facts only (agreed 2026-09-27).
List<DnsFlowLine> _slotDnsLines(DnsRouting r) {
  final setUsers = <String, List<int>>{};
  for (var slot = 1; slot <= 5; slot++) {
    final dns = addressesIn(r.nvram['wgc${slot}_dns'] ?? '');
    if (r.configured(slot) && dns.isNotEmpty) (setUsers[dns.join(', ')] ??= []).add(slot);
  }
  return [for (final e in setUsers.entries) _slotDnsLine(r, e.key, e.value)];
}

/// One set of slot DNS servers: the slots that use it, and the rules that carry the router's own
/// lookups to it.
DnsFlowLine _slotDnsLine(DnsRouting r, String servers, List<int> slots) {
  final winners = [for (final a in servers.split(', ')) r.ruleFor(a)].whereType<DnsRule>().toList();
  final via = _slotDnsVia(r, servers, winners);
  return DnsFlowLine(
    head: servers,
    note: 'used by ${_join([for (final s in slots) r.label(s)])}.$via',
    where: DnsTag(slots.length == 1 ? '1 slot' : 'shared by ${slots.length}', DnsTagKind.neutral),
  );
}

/// How the router's own lookups reach a slot's DNS servers, as a sentence for its note, or empty.
/// Merlin has no rules for them: the first slot to start routes them in the main table (ID-581).
String _slotDnsVia(DnsRouting r, String servers, List<DnsRule> winners) {
  if (r.merlin) {
    final via = r.whereForAll(servers.split(', '));
    return via.kind == DnsTagKind.tunnel ? " The router's own lookups to them go through ${via.label}." : '';
  }
  if (winners.isEmpty) return '';
  return ' Rules ${_join([for (final w in winners) '${w.priority}'])} send the '
      "router's own lookups to them through ${r.tableLabel(winners.first.table)}.";
}

/// The rules box when there are none: on Merlin the reason goes above it (ID-581).
String _noRulesContent(DnsRouting r) => r.merlin ? '(none)' : '(none: every address goes out your internet connection)';

/// The redirects box when there are none.
String _noRedirectsContent(DnsRouting r) => r.merlin
    ? '(none: VPN Director sends no device to a slot with DNS servers)'
    : '(none: no device is pinned to a slot with DNS servers)';

/// The screen's first line: whether anything but pinned devices goes through a tunnel.
String _routingVerdict({required List<DnsFlowLine> pinned, required List<DnsFlowLine> others}) {
  if (others.any((l) => l.where.kind == DnsTagKind.tunnel)) {
    return "Some of the router's own lookups go through a tunnel: the lines tagged with one.";
  }
  return pinned.isNotEmpty ? "Only pinned devices' lookups go through a tunnel." : 'No lookups go through a tunnel.';
}

/// What the screen was read from: the rules, the redirects and each slot's DNS setting, as the router has them.
List<DnsBlock> _routingEvidence(DnsRouting r) {
  String annotateRule(DnsRule rule) => '${rule.line}  # ${rule.table == 'main' ? 'main' : r.tableLabel(rule.table)}';
  final slotDnsLines = [
    for (var slot = 1; slot <= 5; slot++)
      'wgc${slot}_dns=${r.nvram['wgc${slot}_dns'] ?? ''}  # ${r.configured(slot) ? r.label(slot) : 'not configured'}',
  ];
  return [
    const DnsGroup(kDnsEvidenceHeading),
    DnsFile(
      name: 'DNS routing rules (ip rule, iif lo)',
      // On Merlin the reason there are none goes above the box, which wraps; the box scrolls sideways,
      // as config does (ID-581).
      role: r.merlin && r.rules.isEmpty
          ? "Merlin has no such rules. It sends the router's own lookups to a slot's DNS servers by its main table, "
              'through the first slot to start. $kDnsSlotsHeading says which slot that is.'
          : "Which tunnel carries the router's own lookups to each address. The lowest rule number wins.",
      content: r.rules.isNotEmpty ? r.rules.map(annotateRule).join('\n') : _noRulesContent(r),
    ),
    DnsFile(
      name: r.merlin ? "DNS redirects (VPN Director's DNSVPN chains)" : 'DNS redirects (VPN_FUSION)',
      role: r.merlin
          ? "Lookups to the router from each device VPN Director sends to a tunnel, sent on to that slot's DNS servers."
          : "Pinned devices' lookups to the router, sent on to their slot's first DNS server.",
      content: r.redirects.isNotEmpty || r.networkRedirect != null ? r.fusionRaw : _noRedirectsContent(r),
    ),
    DnsFile(
      name: 'Slot DNS settings (nvram)',
      role: "Each slot's DNS servers, as set in MANAGE or the web interface.",
      content: slotDnsLines.join('\n'),
    ),
  ];
}

// ── Loading ────────────────────────────────────────────────────────────────────────────

String _clock(DateTime t) => [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

Future<String> _read(SSHClient client, String cmd) async =>
    (await runRouterCommand(client, cmd, allowFailure: true)).stdout;

/// Reads the router and builds ROUTER RESOLVER STATUS. Only reads.
Future<List<DnsBlock>> loadResolverStatus(SSHClient client, {DateTime Function()? now}) async {
  final facts = await _read(client, kResolverFactsCommand);
  final files = await _read(client, resolverFilesCommand());
  final dotOn = parseDnsmasqServers(
          parseResolverFiles(files).where((f) => f.path == kResolvDnsmasq).firstOrNull?.content ?? '')
      .contains(kStubbyAddress);
  final checks = await _read(client, dnsCheckCommand(withStubby: dotOn));
  return buildResolverStatus(facts: facts, checks: checks, files: files, checkedAt: _clock((now ?? DateTime.now)()));
}

/// Reads the router and builds ROUTER DNS ROUTING. Only reads.
Future<List<DnsBlock>> loadDnsRouting(SSHClient client, {DateTime Function()? now}) async {
  final merlin = classifyFirmwareTag(await _read(client, 'nvram get 3rd-party')) == RouterFirmware.merlin;
  final output = await _read(client, kDnsRoutingCommand);
  final names = deviceNamesByIp(parseDeviceSources(await _read(client, kDeviceSourcesCommand)));
  return buildDnsRouting(parseDnsRouting(output, names: names, merlin: merlin), readAt: _clock((now ?? DateTime.now)()));
}
