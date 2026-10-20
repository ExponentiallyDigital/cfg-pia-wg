// review_service.dart - sending the user to the app's store listing to leave a review.
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
//
// On iOS every review ask names the App Store and opens its listing instead (ID-417). Were
// [kAppStoreListingUrl] ever empty again, a tap would say so rather than send an iPhone to Play's web
// page.

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's App Store listing: its App Store Connect record, Apple ID 6824823717 (ID-427). The page
/// is live once the first submission is approved (ID-436); an iOS build reaches nobody before then.
const String kAppStoreListingUrl = 'https://apps.apple.com/app/id6824823717';

/// True when this build's reviews go to the App Store: iOS, read through [defaultTargetPlatform] so a
/// test can run as iOS. Everything else goes to Play.
bool reviewsGoToAppStore() => defaultTargetPlatform == TargetPlatform.iOS;

/// The store a review goes to, as the app names it: "App Store" on iOS, "Play Store" elsewhere.
String reviewStoreName() => reviewsGoToAppStore() ? 'App Store' : 'Play Store';

/// The listing a review goes to, or null on iOS while there is no App Store listing yet.
String? reviewListingUrl() {
  if (!reviewsGoToAppStore()) return kPlayStoreListingUrl;
  return kAppStoreListingUrl.isEmpty ? null : kAppStoreListingUrl;
}

/// What a review tap did.
enum ReviewOpen { opened, failed, noListingYet }

/// What the app log says when a review tap opened nothing.
String reviewNotOpenedMessage(ReviewOpen result) => result == ReviewOpen.noListingYet
    ? "cfg-pia-wg isn't on the App Store yet, so there's no listing to review it on."
    : 'Could not open the ${reviewStoreName()} listing on this device.';

/// The app's Play Store listing. The id is the Play application id, which never changes
/// (`android/app/build.gradle.kts` marks it as tied to the Play Store), so it is written out rather
/// than read from the running package; a test holds the two together.
const String kPlayStoreListingUrl =
    'https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga';

/// Opens the app's listing in this platform's store so the user can leave a review.
///
/// Anything but [ReviewOpen.opened] means nothing was opened - a desktop host, a device with no store,
/// a plain widget test, or iOS before there is a listing - so the caller can say so rather than leave
/// a tap with no effect.
Future<ReviewOpen> openStoreReview() async {
  final url = reviewListingUrl();
  if (url == null) return ReviewOpen.noListingYet;
  try {
    // externalApplication, not platformDefault: for an https link platformDefault opens an in-app
    // browser tab, which shows the store's web page instead of handing the link to the store app.
    // The manifest's <queries> already covers an https VIEW intent.
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) ? ReviewOpen.opened : ReviewOpen.failed;
  } catch (_) {
    // No handler, or a platform error: failed either way, and the caller logs it.
    return ReviewOpen.failed;
  }
}
