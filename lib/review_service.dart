// review_service.dart - sending the user to the app's Play Store listing to leave a review.
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
// This deliberately does NOT use `InAppReview.requestReview()`, which 406 shipped and 407 removed.
//
// That call asks Play to draw its in-app rating card, and Play alone decides whether to draw one.
// It is quota-limited per user per app, and on a build Play did not install it never appears at
// all - so debug and release alike did nothing visible when the home-screen link was tapped, and
// the API cannot report that back: the plugin's own code says "the API does not indicate whether
// the user reviewed or if the dialog was shown" and returns success either way. Nothing downstream
// could tell a shown card from a silent no-op, so the link looked broken.
//
// Google's own guidance is that the in-app review flow must not be triggered by a button, for that
// reason. A link the user taps on purpose has to do something, every time, so it opens the store
// listing instead. `requestReview` would be right for an unprompted ask - after a successful
// watchdog deploy, say - and this file is where it would go back.

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

/// The channel the in_app_review plugin registers.
const String kInAppReviewChannel = 'dev.britannio.in_app_review';

/// Stands in for the plugin in tests. Mocking the method channel is not enough: `openStoreListing`
/// picks its behaviour from the host platform in Dart, and a test host is not Android, so the
/// channel is never reached.
@visibleForTesting
InAppReview? debugReviewOverride;

/// Opens the app's Play Store listing so the user can leave a review.
///
/// Returns false when nothing could be opened - a desktop host, a device with no Play Store, a
/// plain widget test - so the caller can say so rather than leave a tap with no effect.
Future<bool> openPlayStoreReview({InAppReview? review}) async {
  try {
    // Android: an ACTION_VIEW on the https listing URL, which the manifest's <queries> already
    // covers. Throws UnsupportedError off Android/iOS/Windows, which the catch handles.
    await (review ?? debugReviewOverride ?? InAppReview.instance).openStoreListing();
    return true;
  } catch (_) {
    return false;
  }
}
