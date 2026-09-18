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

const kManageColour = Color(0xFF29B6F6); // MANAGE, and the EDIT verb that belongs to it
const kWatchdogColour = Color(0xFF8BC34A); // WATCHDOG, and its CREATE/EDIT and LOG headings
const kAssignColour = Color(0xFFFFB300); // DEVICE ASSIGNMENT, and the DISABLE verb
const kRouterLogColour = Color(0xFF8E5499);
const kAppLogColour = Color(0xFF6052FF);
const kUtilityColour = Color(0xFF8A97A0); // SETTINGS, ABOUT, and VIEW ROUTER WATCHDOG LOG
const kLinkIconColour = Color(0xFFBFB27C); // HOME's two footer links (ID-109)

/// The colour of each destination. `menu` is HOME, which only the drawer shows.
const Map<AppDestination, Color> kDestinationColours = {
  AppDestination.menu: kHighlight,
  AppDestination.standalone: kHighlight,
  AppDestination.manageRouter: kManageColour,
  AppDestination.watchdog: kWatchdogColour,
  AppDestination.deviceAssignment: kAssignColour,
  AppDestination.routerLog: kRouterLogColour,
  AppDestination.log: kAppLogColour,
  AppDestination.settings: kUtilityColour,
  AppDestination.about: kUtilityColour,
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
  'VIEW ROUTER WATCHDOG LOG': kUtilityColour,
};

/// [label]'s colour, falling back to the house teal for a verb the map does not name.
Color slotActionColour(String label) => kSlotActionColours[label] ?? kHighlight;
