// dns_wording.dart - what the app says about whose lookups depend on the router's resolver, for each firmware (ID-640).
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
// The app's messages said, in four places, that devices that aren't pinned to a slot "can't look names up"
// when the router's resolver fails. That is stock's behaviour (September 2026, ROUTER-DNS.md). On Merlin
// with a tunnel as the default connection those devices have their lookups rewritten to the default slot's
// DNS servers and never ask the router's resolver (measured on 388.13, 2026-11-20; ARCHITECTURE 6.10), so the
// sentence was wrong there, and nothing tied a sentence to the firmware it was measured on.
//
// A model answers three questions for a firmware and a default connection: who answers a device that isn't
// pinned, whose lookups the router's resolver carries, and what the screens call it. The wording is a table of
// sentences, not branches, so a wrong sentence for a firmware is one table cell and a test fixture away.
//
// What each cell rests on:
//  - stock: ROUTER-DNS.md and ARCHITECTURE 6.8, measured September 2026 and not re-measured (ID-639). The
//    sentences are the ones the app has always shown, unchanged, byte for byte.
//  - Merlin, tunnel as the default: unpinned devices' lookups go to the default slot's DNS servers through
//    that tunnel; the router's own programs ask the local dnsmasq (`/etc/resolv.conf` is 127.0.0.1).
//    Measured 2026-11-20 on 388.13, one router.
//  - Merlin, the internet as the default: unpinned devices' plain DNS is forced to the router (measured
//    2026-11-20, DNS Director on and off), so they depend on its resolver as on stock.
//  - Merlin, default not known: both are said, because neither can be claimed.
import 'firmware.dart' show RouterFirmware;

/// The router's default connection, as far as the app could read it.
enum DefaultConnection {
  /// A whole-network VPN Director rule sends every device not pinned to a tunnel.
  tunnel,

  /// No such rule: devices that aren't pinned go out the internet connection.
  internet,

  /// Not read, or not a firmware where it matters.
  unknown,
}

/// The firmware and default connection the wording is for.
class DnsWording {
  const DnsWording(this.firmware, [this.defaultConnection = DefaultConnection.unknown]);

  /// What the app showed before there was a model: stock's text.
  static const DnsWording stock = DnsWording(RouterFirmware.stock);

  final RouterFirmware firmware;
  final DefaultConnection defaultConnection;

  bool get _merlin => firmware == RouterFirmware.merlin;

  /// Whether this is Asuswrt-Merlin.
  bool get merlin => _merlin;

  /// The clause after "so" in the resolver check's advice.
  String get unpinnedLookupsFail {
    if (!_merlin) return _stockUnpinned;
    return switch (defaultConnection) {
      DefaultConnection.tunnel => _merlinTunnelUnpinned,
      DefaultConnection.internet => _merlinInternetUnpinned,
      DefaultConnection.unknown => _merlinUnknownUnpinned,
    };
  }

  /// The heading over the files that make up the router's resolver, on ROUTER RESOLVER STATUS.
  String get resolverGroup {
    if (!_merlin || defaultConnection == DefaultConnection.internet) return _stockGroup;
    return _merlinGroup;
  }

  /// Whose lookups dnsmasq answers, in the descriptions of its files. With a tunnel as the default, devices that
  /// aren't pinned don't ask it, so "your devices'" would be wrong.
  String get askedLookups => resolverGroup == _stockGroup ? "your devices' lookups" : 'the lookups it is asked';

  /// The ending of the watchdog's "Router resolver FAILED" log lines, which are written when the script is, so
  /// they hold for any default connection.
  String get watchdogResolverTail => _merlin ? _merlinWatchdogTail : _stockWatchdogTail;

  /// The slot form's note under a DNS address the router also uses for its own encrypted lookups (ID-005).
  String get overlapNote => _merlin ? _merlinOverlap : _stockOverlap;
}

const String _stockUnpinned = "devices that aren't pinned to a VPN can't look names up";
const String _merlinTunnelUnpinned = "the router's own lookups fail, though devices that aren't pinned use the default "
    "tunnel's DNS servers and still look names up";
const String _merlinInternetUnpinned = "the router's own lookups fail, and so do those of devices that aren't pinned, "
    'which use its resolver while the default connection is the internet';
const String _merlinUnknownUnpinned = "the router's own lookups fail, and so do those of any device that relies on its "
    "resolver: devices that aren't pinned, when the default connection is the internet (with a tunnel as the default "
    "they use its DNS servers instead)";
const String _stockWatchdogTail = "so devices that aren't pinned can't look names up";
const String _merlinWatchdogTail = "so the router's own lookups fail, and so do those of any device that relies on its resolver";

const String _stockGroup = "YOUR DEVICES' LOOKUPS";
const String _merlinGroup = "THE ROUTER'S RESOLVER";

const String _stockOverlap = 'Your router uses this address for its own encrypted DNS. While this slot is running, the '
    "router's lookups, and those of every device you have not pinned, travel through it - and stop "
    'if it stops answering.';
const String _merlinOverlap = 'Your router uses this address for its own lookups. While this slot is running they travel '
    "through it, and stop if it stops answering; so do those of any device that relies on the router's resolver "
    "(devices that aren't pinned, when the default connection is the internet; with a tunnel as the default they use "
    "that tunnel's DNS servers instead). While this slot is stopped, disabled or being rebuilt, the router refuses "
    'them rather than send them over your internet connection, so they fail until it is back. The first two minutes '
    'after a reboot are not covered. Different DNS servers for the router and this slot avoid all of this.';
