// review_service.dart - asking for a Play Store review from inside the app.
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
// Google Play's in-app review flow shows a rating card over the app rather than sending the user
// to the Play Store. It is deliberately unobservable: `requestReview` reports success as soon as
// the request is made, and Play decides on its own whether to draw anything - it is quota-limited
// per user per app, so most taps legitimately show nothing at all. Never build UI that claims a
// review was left, and never gate anything on the outcome.
//
// The flow needs Play Services and an app installed by Play, so it is unavailable on a debug or
// sideloaded build. There, [requestAppReview] opens the store listing instead, which is the only
// way a tap can do something visible during testing.

import 'package:in_app_review/in_app_review.dart';

/// The channel the in_app_review plugin registers; exposed so a test can answer it.
const String kInAppReviewChannel = 'dev.britannio.in_app_review';

/// Asks for a review, falling back to the store listing where the review flow is unavailable.
///
/// Returns false only when neither could be started - a plain widget test, a desktop host, a
/// device with no Play Store. True means the request was made, never that the user saw a card.
Future<bool> requestAppReview({InAppReview? review}) async {
  final api = review ?? InAppReview.instance;
  try {
    if (await api.isAvailable()) {
      await api.requestReview();
      return true;
    }
    // openStoreListing throws UnsupportedError off Android/iOS/Windows, which the catch handles.
    await api.openStoreListing();
    return true;
  } catch (_) {
    return false;
  }
}
