// app_colors.dart - Shared colour palette for the reorganised UI.
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
// Centralises the colour values that were previously inlined across main.dart and
// watchdog_dialog.dart so every screen and widget renders consistently.

import 'package:flutter/material.dart';

import 'session_controller.dart';

const kHighlight = Color(0xFF00D4AA); // primary accent (teal)
const kSecondary = Color(0xFF00A882);
const kBg = Color(0xFF12141A); // scaffold background
const kSurface = Color(0xFF1A1D23); // app bar / dialog surface
const kField = Color(0xFF1E2128); // input fill
const kBorder = Color(0xFF2E3240); // input border
const kText = Color(0xFFE8EAF0); // primary text
const kMuted = Color(0xFF8892A4); // secondary text
const kHint = Color(0xFF4A5268); // hint text
const kError = Color(0xFFFF5C5C); // error / destructive
const kOnPrimary = Color(0xFF12141A); // text on accent buttons
const kConfigBg = Color(0xFF0E1016); // generated-config / log viewport background
const kWarn = Color(0xFFEF9F27); // kill-switch badge
const kWatchdogText = Color(0xFFB69CFF); // watchdog lines in the router log: apart from teal, red, amber and kText

// ── One colour map for the whole app (ID-112) ────────────────────────────────────────────────
//
// Every place that names a destination takes its colour from here: the main menu rows, the
// drawer, and each screen's heading. They were coloured at different times, in different files,
// which is how the drawer and the menu came to disagree about what WATCHDOG looks like.
//
// The menu's row OUTLINES stay teal; only the icon and the label take these colours, so the rows
// still read as one control set rather than nine unrelated buttons.

// Set C (ID-478, Andrew's choice, 2026-11-04): a spectrum down the menu from STANDALONE's teal to
// EXIT's red, each hue as saturated as sRGB allows at its lightness, the warm ones lighter so they
// glow rather than go muddy. Every one is at least 6:1 against kBg. The reasoning and the mock-ups
// are in .claude/plans/plan_menu-colours.md.
const kManageColour = Color(0xFF19B3EE); // MANAGE, and the EDIT verb that belongs to it
const kWatchdogColour = Color(0xFF699CFC); // WATCHDOG, and its CREATE/EDIT and LOG headings
const kAssignColour = Color(0xFFA288FC); // DEVICES, and the DISABLE verb
const kNetworkColour = Color(0xFFE550FC); // NETWORK (ID-458)
const kRouterLogColour = Color(0xFFFD55AC); // ROUTER LOG, and VIEW ROUTER WATCHDOG LOG
const kAppLogColour = Color(0xFFFD932F);
const kSettingsColour = Color(0xFFF4CE1F);
const kAboutColour = Color(0xFF4EE11C);
const kLinkIconColour = Color(0xFFBFB27C); // HOME's two footer links (ID-109)

/// The colour of each destination. `menu` is HOME, which only the drawer shows.
const Map<AppDestination, Color> kDestinationColours = {
  AppDestination.menu: kHighlight,
  AppDestination.standalone: kHighlight,
  AppDestination.manageRouter: kManageColour,
  AppDestination.watchdog: kWatchdogColour,
  AppDestination.deviceAssignment: kAssignColour,
  AppDestination.network: kNetworkColour,
  AppDestination.routerLog: kRouterLogColour,
  AppDestination.log: kAppLogColour,
  AppDestination.settings: kSettingsColour,
  AppDestination.about: kAboutColour,
};

/// [dest]'s colour, falling back to the house teal so a new destination is never invisible.
Color destinationColour(AppDestination dest) => kDestinationColours[dest] ?? kHighlight;

/// The colour of a slot action, keyed by the button's LABEL (ID-118). Keyed by label and not by
/// widget key because WATCHDOG's CREATE/EDIT and MANAGE's EDIT share the key `slot_edit` while
/// taking different colours - the verb is what carries the colour here, not the button.
///
/// A verb keeps the colour of the thing it acts on: CREATE is WATCHDOG green, EDIT is MANAGE blue,
/// DISABLE is the amber the device screen uses, ENABLE stays the house teal, and DELETE stays red -
/// the one destructive action in either set.
const Map<String, Color> kSlotActionColours = {
  'CREATE': kWatchdogColour,
  'CREATE/EDIT': kWatchdogColour,
  'ENABLE': kHighlight,
  'EDIT': kManageColour,
  'DISABLE': kAssignColour,
  'DELETE': kError,
  // ROUTER LOG's colour, the log it opens a part of. It was grey, which read as a disabled button (ID-168).
  'VIEW ROUTER WATCHDOG LOG': kRouterLogColour,
};

/// [label]'s colour, falling back to the house teal for a verb the map does not name.
Color slotActionColour(String label) => kSlotActionColours[label] ?? kHighlight;

// ── SETTINGS' rows (ID-514) ──────────────────────────────────────────────────────────────────
//
// Each row's name and icon in a spectrum down the screen, in its order there; not the menu's
// colours, so a SETTINGS row isn't taken for a menu row. REBOOT ROUTER, MAX ACTIVE VPNS and UNINSTALL
// aren't here: they make major changes, and stay red. Andrew's choice, 2026-11-04.
const Map<String, Color> kSettingsRowColours = {
  'settings_resolver_status': Color(0xFF1ABAC8),
  'settings_dns_routing': Color(0xFF1FAFFC),
  'settings_widget_key': Color(0xFF8B9CFC),
  'settings_secure_startup': Color(0xFFBF84FC),
  'settings_restore_purchase': Color(0xFFFD52E1),
  'settings_forget_router_ip': Color(0xFFFDA75C),
  'settings_del_pia_servers': Color(0xFFDEBB1B),
  'settings_del_pia_cert': Color(0xFF90D61C),
};

// ── One colour per VPN slot (ID-515) ─────────────────────────────────────────────────────────
//
// A slot's whole `wgcN:region` label takes its colour wherever the app shows one, logs included,
// so the same tunnel looks the same on every screen. Andrew's choice, 2026-11-04: none is near the
// teal, red or amber that mean OK, error and warning, and each is at least 6:1 against kBg.
const Map<int, Color> kSlotColours = {
  5: Color(0xFFBBDC17), // lime
  4: Color(0xFFFE7CE8), // pink
  3: Color(0xFFAC88FD), // violet
  2: Color(0xFF80B3FD), // blue
  1: Color(0xFF19D7F9), // cyan
};

/// [slot]'s colour, or null for a number that isn't a WireGuard slot.
Color? slotColour(int slot) => kSlotColours[slot];

// ── The DNS screens' tags (ID-194) ───────────────────────────────────────────────────────────
//
// ROUTER DNS ROUTING tags each lookup with where it goes and whether it is encrypted. Blue for the
// open internet sets it apart from the teal of a tunnel; amber for "not encrypted" is the app's
// caution colour. Each background is the tint the slot badges use for the same colour.
const kTagTunnelBg = Color(0xFF0F3D2E); // teal on this: tunnel, encrypted, OK
const kTagInternet = Color(0xFF64B5F6);
const kTagInternetBg = Color(0xFF0F2438);
const kTagPlainBg = Color(0xFF2A1F0E); // amber on this: not encrypted
const kTagNeutralBg = Color(0xFF1F242D); // muted on this: not configured, shared by N
const kTagFailedBg = Color(0xFF3D1A1A); // red on this: FAILED
