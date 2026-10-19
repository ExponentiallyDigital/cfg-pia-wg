# App Store listing material

Everything the App Store listing needs that is not the app itself, drafted before there is an App Store Connect record (ID-434, ID-435, ID-430). Nothing here is published yet; ID-455 enters it in App Store Connect.

| File | What it is |
| --- | --- |
| `description.md` | The full description, at most 4,000 characters. From Play's, with what doesn't hold on iOS taken out. |
| `listing.md` | The short fields: name, subtitle, promotional text, keywords, categories and URLs. |
| `privacy_and_age_rating.md` | The App Privacy answers and the age rating answers, each with why. |
| `review_notes.md` | The notes for App Review: what the app is and isn't, and how to review it without a router. |
| `export_compliance.md` | The facts for the encryption question, for Andrew to decide (ID-430). |

`test/unit/app_store_listing_test.dart` holds the description and the short fields to Apple's limits, and fails if any of them names another platform, which App Review refuses.

## Andrew's decisions before submission

- **The price on iOS.** Until RevenueCat reaches the App Store (ID-401), an iOS build has no store key, so it sells nothing and unlocks everything. Either the first iOS release is free, or it waits for ID-401. The description says nothing about price until this is decided.
- **The name.** `cfg pia wg` matches the name under the icon. It must be unique across the App Store, and "pia" may draw App Review's questions under guideline 5.2.
- **The encryption answer** (ID-430).
