// firmware.dart - Router firmware detection flag + the stock-only paths that hang off it.
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
// Detection runs once per app session, on entry to either router screen (see
// widgets/router_slots_screen.dart), and the answer is cached here for the life of the process.
// The cache is a library global rather than a SessionController field because RouterSlotService
// and RouterWatchdog have no controller — threading a parameter through their four factories
// would cost more churn than this interim step is worth. It disappears when the planned
// FirmwareService / RouterCommandStrategy abstraction lands.

import 'package:flutter/foundation.dart';

enum RouterFirmware { merlin, stock }

RouterFirmware? _cached;

/// The detected firmware. Defaults to [RouterFirmware.merlin] until detection sets it, so every
/// pre-existing code path keeps its original behaviour.
RouterFirmware get routerFirmware => _cached ?? RouterFirmware.merlin;

/// True once detection has succeeded this session. A failed probe deliberately leaves this false
/// so the next navigation re-runs the check.
bool get firmwareDetected => _cached != null;

bool get isStockFirmware => routerFirmware == RouterFirmware.stock;

void setRouterFirmware(RouterFirmware firmware) => _cached = firmware;

@visibleForTesting
void resetRouterFirmware() => _cached = null;

/// Maps raw `nvram get 3rd-party` output to a firmware, or null when it names something we do not
/// support. Empty output is stock: the key simply does not exist on stock firmware.
RouterFirmware? classifyFirmwareTag(String raw) {
  final tag = raw.trim();
  if (tag.toLowerCase().contains('merlin')) return RouterFirmware.merlin;
  if (tag.isEmpty) return RouterFirmware.stock;
  return null;
}

// ─── Paths ───────────────────────────────────────────────────────────────────────
// Stock has no jq or mail binary on $PATH; the user installs both here (README §4).
/// The app's own directory on the router. Holds the binaries the user installs for stock
/// (`jq`, `mailsend-go`) and the cached PIA CA certificate, on both firmwares.
const String kRouterAppDir = '/jffs/cfg-pia-wg';
const String kStockJqPath = '$kRouterAppDir/jq';
const String kStockMailsendPath = '$kRouterAppDir/mailsend-go';

/// Merlin runs cron entries from services-start; stock has no equivalent, so the app hijacks an
/// unused init script that the firmware already executes at boot and on firewall restart.
const String kServicesStartPath = '/jffs/scripts/services-start';
const String kS50Path = '/opt/etc/init.d/S50downloadmaster';

const String kReadmePrereqUrl =
    'https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements';

/// How to invoke jq for [firmware] (defaults to the detected one).
String jqCommand([RouterFirmware? firmware]) => (firmware ?? routerFirmware) == RouterFirmware.stock ? kStockJqPath : 'jq';
