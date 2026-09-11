// entitlement.dart - one place that answers "has this user paid?".
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
// A seam, deliberately, and not yet a paywall. BACKLOG 1.2 puts everything except config
// generation behind a lifetime unlock, and device assignment is router management, so it is paid
// by that rule. But RevenueCat is not wired up yet.
//
// Threading a purchase check through finished UI later is the mistake this avoids: every gated
// screen asks [isUnlocked] from today, so landing RevenueCat means replacing ONE implementation
// rather than editing every caller. Until then it answers true, and nothing is withheld from
// anyone - which is also the honest state of the app while it has no way to take money.

/// Whether the paid features are available to this user.
///
/// Replace the body when RevenueCat lands; do not add checks at the call sites.
abstract class Entitlement {
  /// True when the lifetime unlock is held. Always true until purchasing exists.
  static bool get isUnlocked => _override ?? true;

  /// Test seam only - pins the answer for one test. `null` restores the real behaviour.
  static bool? _override;

  /// Visible for testing.
  static void debugSetUnlocked(bool? value) => _override = value;
}
