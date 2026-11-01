# Plan: the first App Store submission (ID-436)

Where ID-436 stands is its `Now:` line in CHANGELOG.md 1.2, not here. This file holds the detail.

## Log

Moved from the CHANGELOG item, word for word, 2026-10-21, when work items were made short:

- ID-436 REL: **the first App Store submission is approved.** After ID-431, ID-435, ID-455 and ID-456.
  - **Done when:** the app is on sale, and on an iPhone the home screen's review link opens its listing (from ID-417).
  - **Built in build 534:** `scripts/app_store_connect.py attach-build` puts a processed build on the App Store version, and stops if the two version numbers differ, since Apple takes only a match. `release.yml`'s new `attach_build` option runs it after the TestFlight notes, once Apple has processed the build; a tag never does. The first submission's run ticks `testflight`, `app_store_listing` and `attach_build` together: the listing sets the version from pubspec.yaml, the upload carries the same number. A test holds the option's gate. Left: that run, the in-app purchase ticked on the version page (no API for the first one found), then Andrew's Add for Review and Submit.
  - **Run, 2026-10-21 (run 39522411279): passed.** The listing set the version to 0.8.164; build 534 uploaded, processed with `usesNonExemptEncryption = False`, took its TestFlight notes, and was attached: "build 534 (0.8.164) attached to App Store version 0.8.164". Left: Andrew ticking Router features under In-App Purchases and Subscriptions, choosing how the version is released, Add for Review, Submit to App Review, and App Review's answer.
  - **Submitted, 2026-10-21 (Andrew):** in this App Store Connect the in-app purchase isn't chosen on the version page: Andrew put Router features in a Draft Submission from its own page, then Add for Review on the version added 0.8.164 (534) to the same draft. Apple first asked for Content Rights, answered "No, it does not contain, show, or access third-party content", recorded in `privacy_and_age_rating.md` and now set by `listing` too. "2 Items Submitted": the version and Router features, reviewed together, up to 48 hours. Left: App Review's answer.
  - **Also:** Apple's email confirming the Small Business Program enrolment (ID-437) has arrived, so the US$9.99 pays 15% commission, not 30%.
  - **Confirmed, 2026-10-20:** Apple's email confirming the enrolment arrived.


### 2026-10-28: a status inquiry, a week in

- Five hours short of seven days after submission, the version was still not decided. A dry run of "Promote release" (run 40577566950) read its state: `IN_REVIEW`, so a reviewer had it, rather than it waiting in the queue.
- Likely cause, not confirmed: the app does nothing without an ASUS router, which a reviewer won't have; the demo video and review notes are for that.
- Andrew sent Apple a status inquiry through Contact Us, App Review, offering to answer questions or send more. Apple's case ID: 103010748637.
- Not done, on purpose: cancelling and resubmitting, which goes to the back of the queue, and an expedited review, which Apple keeps for urgent fixes.

### 2026-10-30: still In Review, no reply

- 04:18: no reply to case 103010748637, and the version still In Review; a dry run read `IN_REVIEW` again.
- 04:41, App Store Connect's submission page: both items, Router features (In-App Purchase) and iOS App 0.8.164 (534), "In Review"; neither "Developer Action Needed", and no message from the reviewer on that page.
- 04:47, Business in App Store Connect: a banner asked Andrew to accept the latest agreement, and he did. Apple doesn't approve a submission while an updated agreement waits to be accepted, so this may be what held the review, though Apple didn't say so. Afterwards every row read Active: the Free Apps Agreement (effective 29 Oct 2026, the one just accepted), the Paid Apps Agreement, the bank account, the three tax forms and the Digital Services Act compliance.
- Later on 2026-10-30: no messages from App Review.

### 2026-10-31: ten days, still In Review

- Andrew: still In Review, no email, and no reply to case 103010748637.
- The review notes already answer guideline 5.4's VPN question (no VPN service, no NEVPNManager or Network Extension). 5.4 also allows VPN apps only from developers enrolled as an organisation, and the membership is still individual (ID-421, after ID-440's D-U-N-S number). Not confirmed as the cause; it's the rejection that would take longest to fix if it came.
