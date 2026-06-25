// main.dart - Application entry point.
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
// The UI lives in app_shell.dart and the screens/ + widgets/ directories. PiaWgApp is re-exported
// here so `import 'package:cfg_pia_wireguard/main.dart'` keeps resolving the root widget.

import 'package:flutter/material.dart';

import 'app_shell.dart';

export 'app_shell.dart' show PiaWgApp;

void main() => runApp(const PiaWgApp());
