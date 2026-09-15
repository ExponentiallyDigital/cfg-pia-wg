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
// This deliberately does NOT ask Play for its in-app rating card (`requestReview()`), which 406
// shipped and 407 removed.
//
// Play alone decides whether to draw that card. It is quota-limited per user per app, and on a build
// Play did not install it never appears at all - so debug and release alike did nothing visible when
// the home-screen link was tapped, and the API cannot report that back: it returns success whether
// or not a card was shown. Nothing downstream could tell a shown card from a silent no-op, so the
// link looked broken.
//
// Google's own guidance is that the in-app review flow must not be triggered by a button, for that
// reason. A link the user taps on purpose has to do something, every time, so it opens the store
// listing instead.
//
// Until build 449 this went through the in_app_review plugin's `openStoreListing()`, which on Android
// is only an ACTION_VIEW on the https listing URL. The plugin was removed (ID-042) because it applies
// the Kotlin Gradle plugin unconditionally, which fails the build under AGP 9's built-in Kotlin
// (ID-043). url_launcher, already a dependency, does the same job. An unprompted ask - after a
// successful watchdog deploy, say - would need a review plugin back, one that supports built-in Kotlin.

import 'package:url_launcher/url_launcher.dart';

/// The app's Play Store listing. The id is the Play application id, which never changes
/// (`android/app/build.gradle.kts` marks it as tied to the Play Store), so it is written out rather
/// than read from the running package; a test holds the two together.
const String kPlayStoreListingUrl =
    'https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga';

/// Opens the app's Play Store listing so the user can leave a review.
///
/// Returns false when nothing could be opened - a desktop host, a device with no Play Store, a
/// plain widget test - so the caller can say so rather than leave a tap with no effect.
Future<bool> openPlayStoreReview() async {
  try {
    // externalApplication, not platformDefault: for an https link platformDefault opens an in-app
    // browser tab, which shows Play's web page instead of handing the link to the Play Store app.
    // The manifest's <queries> already covers an https VIEW intent.
    return await launchUrl(Uri.parse(kPlayStoreListingUrl), mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler, or a platform error: false either way, and the caller logs it.
    return false;
  }
}
