// merlin_guard.dart - DEVICES on Merlin: the app's rules beside VPN Director's (ID-557).
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
// Merlin's own kill switch holds a routed device while its tunnel is down, rebuilding or the router
// restarting (measured 2026-11-14), but lets go when the slot is switched off, and leaves three
// gaps that stock's guard closes (ID-567, ID-574, ID-572). [kMerlinGuardScript] closes them, from
// the rules file, so it runs the same from the app, at boot and as each tunnel starts. Merlin clears
// every rule as the WAN comes up (`ip rule flush` in `add_multi_routes()`, rc/wan.c at 388.13),
// after `services-start` has run and before any tunnel starts, so at boot the script also watches
// for a while and puts its rules back; once a tunnel starts, `wgclient-start` does (ID-582,
// measured 2026-11-14: the rules there 21 s after boot, gone at 31 s):
//
//  - each device VPN Director sends to a tunnel gets a `prohibit` at the top of its slot's range
//    ([merlinGuardPriority]), so a slot switched off holds it offline rather than letting it fall
//    through to the WAN or to another slot's whole-network rule (ID-567);
//  - the router's own address is exempted from a whole-network rule, or the kill switch cuts the
//    router off from its own LAN while that tunnel is down (measured 2026-11-14);
//  - each tunnel's table is tidied as Merlin starts it: Merlin copies the main table in, with
//    another tunnel's DNS server routes and the routes to the WAN for the router's own DNS servers,
//    so a routed device's lookups left by another tunnel, or by the WAN (ID-574, ID-572). Every
//    route in the table not through the tunnel, the LAN or the WireGuard server goes, except the
//    tunnel's own endpoint.

import 'firmware.dart' show kRouterAppDir, kServicesStartPath;
import 'merlin_vpn_director.dart'
    show VpnDirectorRule, kMerlinRouterExemptPriority, kVpnDirectorRulelistPath, merlinGuardPriority, serialiseVpnDirectorRules;
import 'router_script_integrity.dart' show writeRouterFile;
import 'router_watchdog.dart' show shellSingleQuote;

const String kMerlinGuardScriptPath = '$kRouterAppDir/merlin-guard.sh';

/// Merlin runs this at the end of every WireGuard client start, with the slot as its argument
/// (`run_custom_script("wgclient-start", ...)` in rc/wireguard.c at 388.13).
const String kWgclientStartPath = '/jffs/scripts/wgclient-start';

/// Merlin runs this after every service event, with the event and the service as its arguments: `restart wan_if`,
/// `restart stubby` and `restart dnsmasq` are what the web page's DNS Apply runs, and `service-event-end` fired for
/// each, with the hold's rule still in place afterwards (measured 2026-11-22, 388.13).
const String kServiceEventEndPath = '/jffs/scripts/service-event-end';

/// The tag on the app's line in each Merlin hook, so it can be found and taken out again.
const String kMerlinGuardHookTag = '# cfg-pia-wg merlin-guard';

/// The app's line in `services-start`: the rules at boot, and the watch that puts them back once the
/// WAN coming up has cleared them.
const String kMerlinGuardBootLine = "[ -x '$kMerlinGuardScriptPath' ] && '$kMerlinGuardScriptPath' boot $kMerlinGuardHookTag";

/// The app's line in `wgclient-start`: the rules put back, and the starting tunnel's table tidied.
const String kMerlinGuardStartLine = "[ -x '$kMerlinGuardScriptPath' ] && '$kMerlinGuardScriptPath' table \"\$1\" $kMerlinGuardHookTag";

/// The app's line in `service-event-end`: the hold re-read when a DNS setting is applied (ID-636). In the
/// background, so the event isn't held up, and for the events a DNS change runs only.
const String kMerlinGuardEventLine = 'case "\$1 \$2" in "restart wan_if"|"restart wan_dns"|"restart stubby"|"restart dnsmasq"|"restart dnspriv") '
    "[ -x '$kMerlinGuardScriptPath' ] && '$kMerlinGuardScriptPath' hold </dev/null >/dev/null 2>&1 & ;; esac $kMerlinGuardHookTag";

/// Shell printing each slot VPN Director sends a device to by a rule of its own that is switched
/// on, once: the slots the script holds devices to, and so the ones whose watchdogs email about its
/// faults (ID-607). The same reading of the rules file as the script's `wanted`: a record is
/// enable>description>local>remote>interface. The echo gives the last record, which the file doesn't
/// end with a newline, a line of its own. Stock's counterpart is `kGuardedSlotsShell`.
const String kMerlinGuardedSlotsShell = "F='$kVpnDirectorRulelistPath'; [ -f \"\$F\" ] && "
    "{ tr '<' '\\n' < \"\$F\"; echo; } | awk -F'>' "
    r"""'$1 == "1" && $3 != "" && $3 !~ /\// && $4 == "" && $5 ~ /^WGC[1-5]$/ { s = substr($5, 4); if (!(s in seen)) { seen[s] = 1; print s } }'""";

/// The script. The priorities in it are [kMerlinRouterExemptPriority] and [merlinGuardPriority]'s,
/// written out so the shell reads plainly; merlin_guard_test.dart holds them to the Dart constants.
/// The rules [kMerlinGuardScript] owns, as an extended regular expression on `ip rule show`.
const String kMerlinGuardRulePattern = '^(9990|11409|11609|11809|12009|12209):';

const String kMerlinGuardScript = '#!/bin/sh\n'
    "# merlin-guard.sh - auto-generated by cfg-pia-wg: DEVICES' rules beside VPN Director's (ID-557).\n"
    '#   (no argument)  holds each device VPN Director sends to a tunnel to that tunnel or nothing,\n'
    "#                  exempts the router's own address from a whole-network rule, and tidies the\n"
    '#                  table of every tunnel that is running.\n'
    '#   boot           the same, from services-start, then watches: Merlin clears every rule as the\n'
    '#                  WAN comes up, after services-start and before any tunnel starts.\n'
    '#   table N        puts the rules back and tidies table wgcN: run by $kWgclientStartPath as\n'
    '#                  Merlin starts N.\n'
    '#   hold           places or lifts the hold on a DNS address a slot shares with the router (ID-636):\n'
    '#                  run by $kServiceEventEndPath when a DNS setting is applied, and by every other mode.\n'
    '#   lift N         lets go of the hold on what slot N lists, for a rebuild by its watchdog (ID-653); restore puts it back.\n'
    '#   clear          takes out every rule this script adds, the hold included (UNINSTALL).\n'
    '# The app keeps it as its version has it.\n'
    "F='$kVpnDirectorRulelistPath'\n"
    '\n'
    '# The slots VPN Director sends a device to by a rule of its own, each once: the slots whose\n'
    "# devices this script holds, whose watchdogs email about its faults (ID-607).\n"
    'guarded_slots() { $kMerlinGuardedSlotsShell; }\n'
    r'''
# Whole, or say so, before anything else (ID-607): this part runs even when the rest of the file is
# missing. The watchdog of each slot with a device of its own emails about it, by its own settings,
# as guard.sh does on stock (ID-484).
if [ "$(tail -n 1 "$0" 2>/dev/null)" != "# end of merlin-guard.sh" ]; then
  GMSG="merlin-guard.sh is damaged ($(wc -c < "$0" 2>/dev/null | tr -d ' ') bytes, and its last line is missing), so the app's rules beside VPN Director are not being kept. Open the app to replace it, or update it in ABOUT."
  logger -t cfg-pia-wg "ERROR: $GMSG"
  for S in $(guarded_slots); do
    W="${GUARD_APPDIR:-/jffs/cfg-pia-wg}/watchdog_wgc$S.sh"
    [ -x "$W" ] && "$W" fault "$GMSG" </dev/null >/dev/null 2>&1
  done
  exit 1
fi
# Every error this run writes is kept, and the next watchdog run reports it, as it does guard.sh's
# on stock (ID-485). An empty file is removed on the way out.
GERR="${GUARD_ERR:-/tmp/cfg-pia-wg-guard.err}.$$"
exec 2>>"$GERR"
trap '[ -s "$GERR" ] || rm -f "$GERR"' EXIT

OURS='^(9990|11409|11609|11809|12009|12209):'

# The rules wanted, one "priority from action" per line. The echo gives the last record, which the
# file doesn't end with a newline, a line of its own.
wanted() {
  [ -f "$F" ] || return 0
  LANIP="$(nvram get lan_ipaddr)"
  { tr '<' '\n' < "$F"; echo; } | while IFS='>' read -r EN DESC SRC DST IFACE; do
    [ "$EN" = 1 ] && [ -n "$SRC" ] && [ -z "$DST" ] || continue
    case "$IFACE" in WGC[1-5]) N="${IFACE#WGC}" ;; *) continue ;; esac
    case "$SRC" in
      */*) [ -n "$LANIP" ] && echo "9990 $LANIP lookup main" ;;
      *) echo "$((11209 + 200 * N)) $SRC prohibit" ;;
    esac
  done | awk '!seen[$0]++'
}

# The rules of ours the kernel holds, in the same form.
held() {
  ip rule show | awk -v re="$OURS" '$0 ~ re { p = $1; sub(":", "", p); if ($4 == "lookup") print p, $3, "lookup", $5; else print p, $3, $4 }'
}

# Adds what's wanted before taking out what isn't, so a device moved between slots is never
# without one. Says how many of the devices it should hold it does. `ip`'s own complaints are
# dropped: two runs at once, the boot watch and a tunnel start, both add a missing rule, and the
# second is told it exists. What counts is read back from the kernel, and a shortfall there is the
# error kept for the watchdog (ID-607).
rules() {
  W="$(wanted)"; H="$(held)"
  echo "$W" | while read -r P S A; do
    [ -n "$P" ] || continue
    echo "$H" | grep -qxF "$P $S $A" || ip rule add from "$S" priority "$P" $A 2>/dev/null
  done
  echo "$H" | while read -r P S A; do
    [ -n "$P" ] || continue
    echo "$W" | grep -qxF "$P $S $A" || ip rule del from "$S" priority "$P" $A 2>/dev/null
  done
  H="$(held)"
  T="$(echo "$W" | grep -c ' prohibit$')"
  G="$(printf '%s\n--\n%s\n' "$H" "$W" | awk '/^--$/ { w = 1; next } !w { h[$0] = 1; next } / prohibit$/ && h[$0] { c++ } END { print c + 0 }')"
  [ "$G" -lt "$T" ] && echo "merlin-guard.sh holds $G of $T devices to their tunnel: the router refused a rule" >&2
  echo "guarded $G of $T"
}

# Says it in the router's log as well as here.
say() { logger -t cfg-pia-wg "merlin-guard: $*"; echo "$*"; }

# How many of the rules wanted the kernel doesn't hold.
missing() {
  W="$(wanted)"; H="$(held)"
  echo "$W" | while read -r P S A; do
    [ -n "$P" ] && ! echo "$H" | grep -qxF "$P $S $A" && echo x
  done | grep -c x || true
}

# Merlin clears every rule as the WAN comes up (`ip rule flush` in add_multi_routes), after
# services-start and before any tunnel starts, so after boot the rules are put back whenever they're
# found missing. Stops two minutes after the clock is set, by when the tunnels have started and
# wgclient-start does this, or after half an hour.
watch() {
  N=0; SYNCED=0
  while [ "$N" -lt "${GUARD_WATCH_MAX:-900}" ]; do
    sleep "${GUARD_WATCH_STEP:-2}"; N=$((N + 1))
    M="$(missing)"
    [ "$M" -gt 0 ] && say "put back $M rule(s) the router cleared: $(rules)"
    hold >/dev/null
    [ "$(nvram get ntp_ready)" = 1 ] && SYNCED=$((SYNCED + 1))
    [ "$SYNCED" -ge "${GUARD_WATCH_AFTER_SYNC:-60}" ] && break
  done
}

# Every route in tunnel N's table that doesn't go through the tunnel, the LAN or the WireGuard
# server goes, except to the tunnel's own endpoint: Merlin copies the main table in as the tunnel
# starts, another tunnel's DNS server routes and the router's DNS servers by the WAN with it.
tidy() {
  T="wgc$1"; EP="$(nvram get "wgc$1_ep_addr_r")"
  ip route show table "$T" 2>/dev/null | while read -r DEST REST; do
    case " $REST " in *" dev $T "*|*" dev br"*|*" dev lo "*|*" dev wgs"*) continue ;; esac
    [ "$DEST" = "$EP" ] && continue
    ip route del "$DEST" $REST table "$T" 2>/dev/null && echo "tidied $T: $DEST $REST"
  done
}

# The addresses the router uses for its own lookups, one a line: its DoT list while DNS-over-TLS is on, its DNS
# Server setting while it is off. Measured 2026-11-22 with the two set to different addresses: the other one is
# not used, so a slot that lists only it leaks nothing (ID-636).
router_dns() {
  if [ "$(nvram get dnspriv_enable)" = 1 ]; then
    nvram get dnspriv_rulelist | tr '<' '\n' | cut -d'>' -f1
  else
    nvram get wan0_dns | tr ' ' '\n'
  fi | grep -E '^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$' | awk '!seen[$0]++'
}

# The DNS servers of every slot that has a server to connect to, one a line. A slot that is stopped, disabled
# or being rebuilt still lists them: that is when its route is gone.
slot_dns() {
  for N in 1 2 3 4 5; do
    [ -n "$(nvram get "wgc${N}_ep_addr")" ] && { nvram get "wgc${N}_dns"; echo; } | tr ', ' '\n\n'
  done | grep -E '^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$' | awk '!seen[$0]++'
}

# The addresses to hold: those the router uses that a slot also lists. None until the clock is set: held from
# boot the router's time sync, which resolves its server through these, cannot run, and Merlin waits for the
# clock before it starts a tunnel (measured 2026-11-22: 274 s to the clock instead of 105 s with one of two held,
# and none until the release with both). The boot leak of about two minutes stays. GUARD_HOLD_ADDRS names
# addresses outright, for check-claims.sh.
holds() {
  if [ -n "${GUARD_HOLD_ADDRS:-}" ]; then echo "$GUARD_HOLD_ADDRS" | tr ' ' '\n'; return 0; fi
  [ "$(nvram get ntp_ready)" = 1 ] || return 0
  SD="$(slot_dns)"
  LS="$(lifted_slot)"
  LD=""
  [ -n "$LS" ] && LD="$({ nvram get "wgc${LS}_dns"; echo; } | tr ', ' '\n\n')"
  router_dns | while read -r A; do
    echo "$SD" | grep -qxF "$A" || continue
    echo "$LD" | grep -qxF "$A" && continue
    echo "$A"
  done
}

# A rebuild's lift (ID-653): "<epoch> <slot>", written by `lift N`. A watchdog with no DoH server of its own looks
# PIA's names up through the router's resolver, and its alert email looks the mail server up the same way, and
# the hold refuses that while the slot is down. So the addresses that slot lists are let go until the watchdog
# says `restore`, and no longer than ten minutes: a watchdog that dies leaves the hold back on by itself.
LIFTF="${GUARD_LIFT_FILE:-/tmp/cfg-pia-wg-hold-lift}"
lifted_slot() {
  [ -f "$LIFTF" ] || return 0
  { read -r LT LS; } < "$LIFTF"
  case "$LT$LS" in ''|*[!0-9]*) return 0 ;; esac
  [ $(( $(date +%s) - LT )) -lt 600 ] && echo "$LS"
  return 0
}

# The addresses held now: this script's rules in the raw table, `-d <addr> ! -o wgc+ -j DROP`. The raw table, not
# filter: Merlin rebuilds the filter table and leaves the rule out for about half a second, and a rule there let
# 8 to 31 connections out per rebuild with the slot stopped; a raw rule survived a firewall rebuild and a WAN
# bounce with none (measured 2026-11-22). Only the WAN path is refused: a tunnel's traffic matches `-o wgc+`.
held_addrs() {
  iptables -t raw -S OUTPUT 2>/dev/null | awk '$3 == "-d" && $5 == "!" && $6 == "-o" && $7 == "wgc+" && $9 == "DROP" { sub("/32", "", $4); print $4 }'
}

# Puts the hold on what's wanted before taking it off what isn't, and says what it did, here and in the router's log.
hold() {
  W="$(holds)"; H="$(held_addrs)"
  echo "$W" | while read -r A; do
    [ -n "$A" ] || continue
    echo "$H" | grep -qxF "$A" && continue
    iptables -t raw -I OUTPUT -d "$A" ! -o wgc+ -j DROP 2>/dev/null && say "hold: the router's lookups to $A are refused outside a tunnel, as a slot lists it too"
  done
  echo "$H" | while read -r A; do
    [ -n "$A" ] || continue
    echo "$W" | grep -qxF "$A" && continue
    iptables -t raw -D OUTPUT -d "$A" ! -o wgc+ -j DROP 2>/dev/null && say "hold: $A is let go, no slot lists it now"
  done
  H="$(held_addrs)"
  for A in $(echo "$W"); do
    echo "$H" | grep -qxF "$A" || echo "merlin-guard.sh could not hold $A: the router refused the rule" >&2
  done
  takeover
  echo "holding $(echo "$H" | grep -c .) address(es)"
}

# The takeover (ID-652): Merlin adds a slot's route to its DNS address only as the slot starts, and only the first slot
# to start gets one, so with the hold on, a second running slot that lists the address wouldn't carry the router's
# lookups when the first stopped: they would be refused until a slot restarted. One rule for each running slot
# that lists a held address, `to <addr> iif lo lookup wgcN`, at 1050 minus N, so the highest-numbered running slot wins, as
# on stock. A stopped slot's table is flushed, so its rule finds nothing and the lookup falls to the next slot's, and
# last to the main table, where the hold refuses it. The watchdog's own probe, at 1000, is ahead of them.
takeover_wanted() {
  holds | while read -r A; do
    [ -n "$A" ] || continue
    for N in 1 2 3 4 5; do
      ip link show "wgc$N" >/dev/null 2>&1 || continue
      { nvram get "wgc${N}_dns"; echo; } | tr ', ' '\n\n' | grep -qxF "$A" && echo "$((1050 - N)) $A wgc$N"
    done
  done
}
takeover_held() {
  ip rule show | awk '$2 == "from" && $3 == "all" && $4 == "to" && $6 == "iif" && $7 == "lo" && $8 == "lookup" && $1 ~ /^104[5-9]:$/ { p = $1; sub(":", "", p); print p, $5, $9 }'
}
takeover() {
  TW="$(takeover_wanted)"; TH="$(takeover_held)"
  echo "$TW" | while read -r P A T; do
    [ -n "$P" ] || continue
    echo "$TH" | grep -qxF "$P $A $T" && continue
    ip rule add to "$A" iif lo lookup "$T" priority "$P" 2>/dev/null && say "hold: the router's lookups to $A go through $T while it runs"
  done
  echo "$TH" | while read -r P A T; do
    [ -n "$P" ] || continue
    echo "$TW" | grep -qxF "$P $A $T" && continue
    ip rule del to "$A" iif lo lookup "$T" priority "$P" 2>/dev/null
  done
}

case "${1:-}" in
  table) [ -n "${2:-}" ] && { say "wgc$2 started: $(rules)"; hold; tidy "$2"; } ;;
  boot)
    say "boot: $(rules)"
    for I in 1 2 3 4 5; do ip link show "wgc$I" >/dev/null 2>&1 && tidy "$I"; done
    watch </dev/null >/dev/null 2>&1 & ;;
  watch) watch ;;
  hold) hold ;;
  lift) [ -n "${2:-}" ] && { echo "$(date +%s) $2" > "$LIFTF"; say "hold: lifted for wgc$2's rebuild, which looks names up through the router"; hold; } ;;
  restore) rm -f "$LIFTF"; say "hold: back after the rebuild"; hold ;;
  clear)
    rm -f "$LIFTF"
    held | while read -r P S A; do ip rule del from "$S" priority "$P" $A; done
    held_addrs | while read -r A; do [ -n "$A" ] && iptables -t raw -D OUTPUT -d "$A" ! -o wgc+ -j DROP; done
    takeover_held | while read -r P A T; do ip rule del to "$A" iif lo lookup "$T" priority "$P"; done
    echo "cleared" ;;
  *)
    rules
    hold
    for I in 1 2 3 4 5; do ip link show "wgc$I" >/dev/null 2>&1 && tidy "$I"; done ;;
esac
exit 0
# end of merlin-guard.sh
''';

/// VPN Director's rules file, byte for byte as the web page writes it: no trailing newline, which
/// would end up in the last rule's interface name. Written beside the live file, renamed over it,
/// and read back. [read] never throws and [run] throws on a non-zero exit. DEVICES' APPLY and
/// DELETE both write it this way.
Future<void> writeVpnDirectorRules(
  List<VpnDirectorRule> rules, {
  required Future<String> Function(String cmd) read,
  required Future<String> Function(String cmd) run,
}) async {
  const path = kVpnDirectorRulelistPath;
  final body = serialiseVpnDirectorRules(rules);
  await run("mkdir -p -m 700 /jffs/openvpn && printf '%s' ${shellSingleQuote(body)} > '$path.cfgtmp' && "
      "chmod 660 '$path.cfgtmp' && mv '$path.cfgtmp' '$path'");
  if ((await read("cat '$path' 2>/dev/null")).trim() != body) {
    throw Exception("VPN Director's rules file didn't read back as written. Check VPN > VPN Director in the router's "
        'web interface before trying again.');
  }
}

typedef MerlinGuardLog = void Function(String message, {bool isError, bool isSuccess, bool isWarning});

/// Installs and runs [kMerlinGuardScript], and keeps its two hooks in place, over an existing
/// session: [read] never throws, [run] throws on a non-zero exit, as for the stock guard.
class MerlinGuard {
  MerlinGuard({required this.read, required this.run, this.onLog});

  final Future<String> Function(String cmd) read;
  final Future<String> Function(String cmd) run;
  final MerlinGuardLog? onLog;

  /// Puts the script and hooks in place, runs it, and returns how many pinned devices it holds.
  /// Never throws: a guard that couldn't be put in place mustn't stop the change it follows. It
  /// says what that means instead, and returns null.
  Future<int?> ensure({bool quiet = false}) async {
    try {
      await install();
      await _hooks();
      final out = await run("'$kMerlinGuardScriptPath'");
      final m = RegExp(r'guarded (\d+) of (\d+)').firstMatch(out);
      final held = int.tryParse(m?.group(1) ?? ''), total = int.tryParse(m?.group(2) ?? '');
      if (held != null && total != null && held < total) {
        onLog?.call(
          'The app holds only $held of $total pinned devices to their tunnel. Until it holds the rest, '
          "switching a tunnel off lets its devices out by another route.",
          isWarning: true,
        );
      } else if (!quiet && held != null && held > 0) {
        onLog?.call('$held pinned device${held == 1 ? '' : 's'} held to their tunnel or nothing.');
      }
      return held;
    } catch (e) {
      onLog?.call(
        "The app's rules beside VPN Director couldn't be put in place ($e). Until they are, a device sent to a "
        'tunnel that is switched off can reach the internet another way.',
        isWarning: true,
      );
      return null;
    }
  }

  /// Writes the script only when the router's copy differs.
  Future<void> install() async {
    final current = await read("cat '$kMerlinGuardScriptPath' 2>/dev/null || true");
    if (current.trim() == kMerlinGuardScript.trim()) return;
    await run("mkdir -p '$kRouterAppDir'");
    await writeRouterFile(
        path: kMerlinGuardScriptPath, body: kMerlinGuardScript, what: 'Merlin guard', mode: '755', run: run, read: read);
  }

  /// Merlin runs `/jffs/scripts` only with `jffs2_scripts` on; then each hook gets the app's line,
  /// once. A line of the app's that differs, an older version's, is replaced (ID-582 added `boot`).
  Future<void> _hooks() async {
    await run("[ \"\$(nvram get jffs2_scripts)\" = 1 ] || { nvram set jffs2_scripts=1; nvram commit; }");
    for (final (path, line) in [
      (kServicesStartPath, kMerlinGuardBootLine),
      (kWgclientStartPath, kMerlinGuardStartLine),
      (kServiceEventEndPath, kMerlinGuardEventLine),
    ]) {
      final quoted = line.replaceAll("'", r"'\''");
      await run("[ -f '$path' ] || { echo '#!/bin/sh' > '$path'; }; "
          "grep -qxF '$quoted' '$path' || { grep -vF '$kMerlinGuardHookTag' '$path' > '$path.tmp'; "
          "mv '$path.tmp' '$path'; echo '$quoted' >> '$path'; }; "
          "chmod +x '$path'");
    }
  }

  /// UNINSTALL: the rules out, and the app's line out of each hook.
  Future<void> clear() async {
    await read("[ -x '$kMerlinGuardScriptPath' ] && '$kMerlinGuardScriptPath' clear");
    for (final path in [kServicesStartPath, kWgclientStartPath, kServiceEventEndPath]) {
      await read("[ -f '$path' ] && grep -vF '$kMerlinGuardHookTag' '$path' > '$path.tmp' && mv '$path.tmp' '$path' && chmod +x '$path'");
    }
  }
}
