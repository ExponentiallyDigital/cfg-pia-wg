#!/bin/sh
# Prepares Xcode to buy Router features over and over in the simulator (ID-543).
#
# Xcode builds normally have no RevenueCat key, so they unlock everything and never show the purchase
# screen. This writes the iOS key into Flutter's Xcode settings (ios/Flutter/Generated.xcconfig, which
# git ignores), then opens the workspace. In Xcode, choose the "cfg-pia-wg StoreKit" scheme and a
# simulator, and press Run: purchases go to Xcode's local store (ios/StoreKit/cfg-pia-wg.storekit),
# never to the App Store. Debug, StoreKit, Manage Transactions deletes a purchase to buy it again.
#
# The key comes from REVENUECAT_IOS_KEY, else from secrets/revenuecat_ios_key, which git ignores.
# Any later `flutter run` or `flutter build` rewrites Generated.xcconfig without it: run this again.
set -eu
cd "$(dirname "$0")/.."

key="${REVENUECAT_IOS_KEY:-}"
if [ -z "$key" ] && [ -f secrets/revenuecat_ios_key ]; then
  key=$(tr -d '[:space:]' < secrets/revenuecat_ios_key)
fi
if [ -z "$key" ]; then
  echo "No RevenueCat iOS key: set REVENUECAT_IOS_KEY, or put the key in secrets/revenuecat_ios_key." >&2
  echo "It is the public app key starting appl_, under RevenueCat, Project Settings, API keys." >&2
  exit 1
fi

flutter build ios --config-only --debug --dart-define=REVENUECAT_IOS_KEY="$key"
open ios/Runner.xcworkspace
echo "In Xcode: choose the \"cfg-pia-wg StoreKit\" scheme and a simulator, then Run (Command-R)."
