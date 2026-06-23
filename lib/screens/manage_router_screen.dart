// screens/manage_router_screen.dart - "Manage router PIA WireGuard configuration" (spec 2.1.2).
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

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../pia_service.dart';
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../widgets/router_slots_screen.dart';
import '../widgets/slot_modal.dart';

class ManageRouterScreen extends StatelessWidget {
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  final PiaService? piaService;
  final RouterSlotService Function(SSHClient)? slotServiceFactory;
  final RouterWatchdog Function(SSHClient)? watchdogServiceFactory;

  const ManageRouterScreen({
    super.key,
    this.testClientFactory,
    this.piaService,
    this.slotServiceFactory,
    this.watchdogServiceFactory,
  });

  @override
  Widget build(BuildContext context) => RouterSlotsScreen(
        mode: SlotModalMode.manage,
        testClientFactory: testClientFactory,
        piaService: piaService,
        slotServiceFactory: slotServiceFactory,
        watchdogServiceFactory: watchdogServiceFactory,
      );
}
