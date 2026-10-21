# Demo video for App Review: the shot list

ID-456. App Review has no ASUS router and no PIA account, so the review notes send them to a short video of the app working against a real router. Andrew records it once on an iPhone with the iPhone's own screen recording; this file is every step, in order. About 15 minutes all told, of which the video itself is 2 to 3.

The video goes only to Apple: it is attached in App Store Connect, never posted anywhere public, since it shows the home network's device names and addresses.

## Before you start

You need:

- an iPhone with the **TestFlight** build of cfg-pia-wg on it (ID-431), with the router unlock already bought on the sandbox account (ID-401), so no payment screen interrupts the recording;
- the iPhone on the home Wi-Fi, the same network as the router;
- the router's password and the PIA login, ready to type;
- slot **wgc4** empty on the router. It is the spare slot the video creates a VPN in, and deletes again afterwards.

## Part 1: put the screen-recording button on the iPhone (once only)

1. On the iPhone, find the grey **Settings** app (a picture of cogs) on the home screen, and tap it.
2. Scroll down and tap **Control Center**.
3. On newer iOS, Settings may not list "Customize Controls". If so, skip to step 6.
4. Tap **Customize Controls**.
5. Under **More Controls**, find **Screen Recording** and tap the green **+** next to it. It moves up into the list at the top. Go to step 9.
6. Leave Settings: swipe up from the very bottom edge of the screen.
7. Open Control Center: put your finger on the **very top-right corner** of the screen (above the battery symbol) and slide it down. A panel of round buttons appears.
8. If you don't see a round button with a solid dot inside a circle (that's Screen Recording), touch and hold an empty part of the panel, tap **Add a Control**, find **Screen Recording**, and tap it. Then tap an empty part of the panel to finish.
9. Close Control Center: swipe up from the bottom of the screen, or tap an empty area.

## Part 2: practise once, without recording

Go through Part 3's steps once without recording, so nothing on the router surprises you on camera. Then delete wgc4 again (Part 4) before recording.

## Part 3: the recording

Speak nothing; the video has no sound. Move slowly: pause a second or two on each screen so a reviewer can read it.

**Start recording**

1. Open Control Center: slide down from the **top-right corner**.
2. Tap the **Screen Recording** button (the dot inside a circle). A 3, 2, 1 countdown shows, then recording starts.
3. Close Control Center: tap an empty area. A small **red** marker at the top-left of the screen shows it is recording.

**Shot 1: the app opens (10 seconds)**

4. Tap the **cfg-pia-wg** icon on the home screen.
5. Wait on the main menu for 3 seconds.

**Shot 2: connect to the router (20 seconds)**

6. Tap **MANAGE**.
7. If it asks for the router's details, type the router password (it shows as dots) and tap **CONNECT TO ROUTER**.
8. Wait until the list of slots shows, with your running tunnels marked ACTIVE. Pause 3 seconds.

**Shot 3: create a VPN in the spare slot (40 seconds)**

9. Tap the **wgc4** row (it reads `wgc4 <empty slot>`).
10. Tap **CREATE**.
11. Choose a region from the list (any you like).
12. Type the PIA username and password (the password shows as dots), then tap **CONTINUE**.
13. Wait for "Slot created". Pause 3 seconds.

**Shot 4: turn it on (30 seconds)**

14. With wgc4 still selected, tap **ENABLE**.
15. If it shows "Connectivity check targets" with 8.8.8.8 and 1.1.1.1, tap **ENABLE** again.
16. Wait until wgc4 shows **ACTIVE**. Pause 3 seconds.

**Shot 5: the watchdog (30 seconds)**

17. Go back to the main menu (the back arrow at the top-left).
18. Tap **WATCHDOG**, then the **wgc4** row, then **CREATE/EDIT**.
19. If the form asks for the PIA username and password, type them (the password shows as dots). Leave everything else as it is, and leave email alerts off.
20. Scroll to the bottom and tap **SAVE**.
21. Wait for the message that the watchdog was deployed. Pause 3 seconds.

**Shot 6: the router's own record (15 seconds)**

22. Go back to the main menu, and tap **ROUTER LOG**.
23. Pause 3 seconds on the newest lines: they show the app's ENABLE check and the watchdog starting.

**Stop recording**

24. Open Control Center again (slide down from the top-right corner).
25. Tap the **Screen Recording** button. It stops, and the iPhone says the video was saved to **Photos**.

## Part 4: put the router back (not recorded)

1. In the app, open **MANAGE**, select **wgc4**, and tap **DELETE**.
2. Read the prompt: it says the watchdog goes too. Confirm. The row reads `wgc4 <empty slot>` again, as before the video.

## Part 5: check the video and send it to the Mac

1. Open the **Photos** app (a coloured flower icon). The newest item, at the bottom, is the video. Tap it and play it through, to check every shot is there.
2. If a password or anything private shows in clear text, delete the video (the bin icon) and record again.
3. To get it onto the Mac: with the video open, tap the **Share** button (a square with an arrow pointing up, at the bottom-left).
4. Tap **AirDrop**, then your MacBook's name. On the Mac, a box may ask to accept it: click **Accept**.
5. On the Mac the video lands in the **Downloads** folder: click the Finder icon (the blue and white face, at the left end of the Dock along the bottom of the screen), then **Downloads** in the list on the left.

Then tell Claude it's on the Mac. Attaching it to the review notes in App Store Connect comes with the listing (ID-455), with its own steps.
