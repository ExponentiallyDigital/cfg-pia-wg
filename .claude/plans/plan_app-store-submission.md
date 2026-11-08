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

### 2026-11-02 and 03: App Review's questions, answered and resubmitted

- 2026-11-02, 2:51 AM, App Review's message on the submission page: version 0.8.164 (534) Rejected under 2.1.0 Performance: App Completeness, reviewed on an iPad Air 11-inch (M3); Router features left Ready for Review. Both points were Information Needed, not a fault in the build:
  - 2.1: what user information the app collects using VPN, why, and whether it is shared with third parties, and where.
  - 2.1(b): they couldn't find the in-app purchase, and asked for the steps to reach it; with the usual reminder that the Paid Apps Agreement must be accepted.
- Why they couldn't find it: the notes said only "Any of those buttons offers the purchase", and almost all of those need a router. SETTINGS, MAX ACTIVE VPNS opens the purchase before any router question, in build 534 as now, so no new build was needed.
- Checked before replying (Andrew, Business in App Store Connect): the Paid Apps Agreement Active from 20 Oct 2026, and the bank account, tax forms and Digital Services Act Active too.
- 2026-11-03: Andrew replied with the VPN answers and the steps, as now in `app-store/review_notes.md` (ID-509). Resubmitting asked two new age rating questions, social media and social media disabled for users under 13; Andrew answered both No and the rating stayed 4+ (ID-510). He asked whether to add anything for encryption: no, already decided under ID-430 (`app-store/export_compliance.md`). Resubmitted 2026-11-03 at 11:07 AM, the same submission ID.
- Still open, from 2026-10-31: guideline 5.4 allows VPN apps only from organisations, and the membership is individual (ID-421). The questions suggest the reviewer read the app as a VPN app; the reply says it isn't one.

### 2026-11-08: rejected again, a crash on launch

- 2026-11-08, 4:08 AM, App Review's message: 0.8.164 (534) rejected under 2.1(a), "it quits unexpectedly on launch", reviewed 2026-11-07 on an iPad Air 11-inch (M3), iPadOS 27.0.1. No crash log attached. The 2.1 VPN and 2.1(b) purchase questions weren't raised again.
- Not reproduced, Claude, 2026-11-08: debug builds of v0.8.164 and v0.8.199 both launch on the iPad Air 11-inch (M4) simulator, iOS 27.0, Xcode 27.1, and 0.8.164 relaunched three times with its data kept; no crash report. A simulator can't run a release build, so this doesn't rule out a release-only or device-only crash.
- A dry run of promoting build 569 to App Store production (run 42418425239) would turn the rejected 0.8.164 into 0.8.199. The real run would then set "What's New", which Apple likely refuses on a first version (not confirmed), so 569 goes in by hand on the version page instead.
- Next: Apple's crash log, if any, from Xcode Organizer; 534 and 569 from TestFlight on an iPhone 11, iOS 27.0.1; then 569 to App Review with a reply.
- 2026-11-08, Andrew ran "Promote release", build 569 to production, App Store only, twice, 19 seconds apart (runs 42421667488 and 42421695275). The first renamed the version to 0.8.199, set "What's New" (accepted on a first version after all) and attached build 569. Both then failed at the last call, `PATCH /v1/reviewSubmissions/abd22430-...` with `submitted: true`: HTTP 409 STATE_ERROR, "Version is not ready to be submitted yet, please try again later." A dry run straight after (run 42421808266): 0.8.199 is PREPARE_FOR_SUBMISSION with build 569 attached. Left: submitting it from App Store Connect, which names whatever is missing.
- 2026-11-08: Andrew's reply of 2026-11-03 added to the notes in full, 3,916 characters (ID-541). The listing workflow's only run, 2026-11-04 (run 41847377363), failed with the version then in review ("You cannot create a new version of the App in the current state"), so ID-509's answers likely never reached App Store Connect's Notes; Andrew pastes the notes in by hand.
- 2026-11-08, Claude read App Store Connect in Andrew's Chrome. Version 0.8.199 with build 569, the notes saved (7 characters left, ending with Andrew's crash log line), the demo video attached, automatic release. Submission abd22430: Router features Ready for Review, the version Rejected, Resubmit to App Review offered. App Privacy: Purchase History, App Functionality only, where `privacy_and_age_rating.md` also has Analytics. Age rating 4+ (Brazil AL, Korea ALL, Vietnam 00+). Content rights No. Mac and Apple Vision Pro availability both ticked. The in-app purchase has its review screenshot and no review notes. The privacy policy URL answers 200.
- 2026-11-08, Andrew: build 569 from TestFlight on a MacBook Pro (M1 Pro, macOS 27.0.1), running as an iPad app: every function works, and SETTINGS, MAX ACTIVE VPNS opens the purchase. The first sight of a release build on Apple silicon outside an iPhone. ABOUT reads iOS 27.0, iOS 26.5 SDK, minimum iOS 18.0, Xcode 26.6 (17F113). Router features' Review Notes can't be edited while it's in the submission, so the purchase steps are only in the version's notes.
- 2026-11-08, 11:13 AM: Andrew replied to App Review and resubmitted, the same submission ID, with 0.8.199 (569) and Router features. Waiting on App Review.
- 2026-11-08: Andrew deleted the TestFlight group Family and made Family and friends (testers Kim and Richard Musgrave, David Phelan); build 569 added to it, Waiting for Review. `EXTERNAL_GROUP` changed to match (ID-542).
- 2026-11-08: Andrew renamed the Xcode project to cfg-pia-wg_iOS; Claude put it back (Flutter, CI and five tests need Runner). ID-441 built: the Associated Domains entitlement and the website's file.
- 2026-11-08: ID-441 closed on D1: every login offered for saving and filled.
