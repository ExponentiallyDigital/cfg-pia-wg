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
