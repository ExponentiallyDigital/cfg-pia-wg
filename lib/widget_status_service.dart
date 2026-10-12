// widget_status_service.dart - the widget's status read, over the app's existing session (ID-376).
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
// [kWidgetStatusCommand] is two things at once, deliberately: it is what [WidgetStatusService.read]
// runs over the app's own (password or key) session today, AND it is what the widget's restricted
// key will be allowed to run once ID-376's next step installs it - the same command either way, so
// what the app reads with your login is exactly what the widget would read with its own. Built with
// single quotes around the separator on purpose: a restricted key's `command="…"` value sits inside
// double quotes in `authorized_keys`, and this string is meant to go there unescaped (see
// widget_key.dart's `widgetKeyRestriction`, which still escapes defensively in case that ever
// changes).
import 'package:dartssh2/dartssh2.dart';

import 'device_assignment.dart';
import 'router_command.dart';
import 'router_slot_service.dart' show kHandshakeAgesCommand, kUpInterfacesCommand;
import 'widget_status.dart';

/// The marker itself, as it appears in the command's OUTPUT - `echo` strips the shell quoting
/// that gets it there safely, so this is what [WidgetStatusService.read] splits on.
const String _marker = '@@CFGPIAWG-WIDGET@@';

/// The same marker, single-quoted for use as a shell word - see this file's header for why single
/// quotes, not double.
const String _sep = "'$_marker'";

/// One round trip: everything [buildWidgetStatus] needs, in the order [WidgetStatusService.read]
/// expects it back. Stock only - see widget_status.dart's header for why.
const String kWidgetStatusCommand = 'echo $_sep; nvram get vpnc_clientlist; '
    'echo $_sep; nvram get vpnc_dev_policy_list; '
    'echo $_sep; $kUpInterfacesCommand; '
    'echo $_sep; $kHandshakeAgesCommand; '
    'echo $_sep; nvram get dhcp_staticlist; '
    'echo $_sep; nvram get custom_clientlist; '
    'echo $_sep; nvram get cfg_device_list; '
    'echo $_sep; cat /jffs/nmp_cl_json.js 2>/dev/null; '
    'echo $_sep; cat /tmp/nmp_cache.js 2>/dev/null; '
    'echo $_sep';

/// Reads [kWidgetStatusCommand] over [client] and turns it into [WidgetStatus] - the I/O half;
/// widget_status.dart's [buildWidgetStatus] is the pure half this hands off to, and is what the
/// unit tests exercise in bulk. This class only has to be trusted to read the right things and
/// split them apart correctly, which is what its own tests check with a canned reply.
class WidgetStatusService {
  WidgetStatusService(this.client, {this.onLog, this.clock = DateTime.now});

  final SSHClient client;
  final void Function(String message, {bool isError, bool isSuccess, bool isWarning})? onLog;

  /// Where [WidgetStatus.checkedAt] comes from. Injected so a caller that also stamps its own
  /// "now" - widget_refresh.dart does, for the widget's age line - can hand both the same clock
  /// rather than reading it twice and getting two answers.
  final DateTime Function() clock;

  Future<WidgetStatus> read() async {
    final parts = (await runRouterCommand(client, kWidgetStatusCommand, allowFailure: true, onLog: onLog)).stdout.split(_marker);
    String at(int i) => i + 1 < parts.length ? parts[i + 1].trim() : '';

    final devices = buildDeviceList(
      nmpClJson: at(7),
      nmpCache: at(8),
      customClientlist: at(5),
      dhcpStaticlist: at(4),
      cfgDeviceList: at(6),
    );

    return buildWidgetStatus(
      vpncClientlist: at(0),
      devicePolicyList: at(1),
      upInterfaces: at(2),
      handshakeAgesRaw: at(3),
      devices: devices,
      checkedAt: clock(),
    );
  }
}
