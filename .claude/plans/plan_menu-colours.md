# Plan: main menu colours (ID-478)

On hold, Andrew's decision, 2026-10-26. Where it stands is ID-478 in BACKLOG.md, not here. Nothing in the app has changed.

## How a colour reaches the screen

`lib/app_colors.dart`'s `kDestinationColours` gives each destination one colour, used by its menu row, the drawer and its screen's header. SETTINGS and ABOUT share `kUtilityColour`, grey #8A97A0, so giving them their own colours means a constant each. The row outlines stay teal. Changing a router row's colour changes its screen too (WATCHDOG's headings, DEVICES' DISABLE), and every README image and store screenshot showing it.

## What Andrew said, in order, 2026-10-26

- SETTINGS in orange: shown in Orange #FF9800 and Deep orange #FF7043; he preferred deep orange. Then, for ABOUT, pink #F06292, light grey #CFD8DC and warm brown #A1887F: none liked, and the orange set aside.
- Pairs: periwinkle #9FA8DA with lime #D4E157; lavender #B39DDB with mint #80CBC4; gold #FFD54F with pale sky #B3E5FC. He liked gold and pale sky, but wanted the sky more saturated; light blue #81D4FA, vivid sky #80D8FF and cornflower #82B1FF were not liked.
- From a sheet of 14 (`menu-colours/menu-colour-swatches.png`), he chose gold #FFD54F for SETTINGS and violet #B388FF for ABOUT (`menu-colours/gold-violet-mockup.png`).
- Asked what Claude would choose for every row: one brightness for all (OKLCH lightness about 0.78; today ROUTER LOG is 0.54 and APP LOG 0.56, both dim), hues spread evenly, STANDALONE's teal and EXIT's red kept. Not mad on pink for APP LOG; of lighter indigo, lime and white, white was "the best so far", but ROUTER LOG's periwinkle #99B5FE looked washed out. Three more saturated blues are in `menu-colours/router-log-options-mockup.png`; Claude's pick was #7598FF.
- Then on hold, with a note: Andrew liked orange for SETTINGS (`menu-colours/settings-orange-mockup.png`).

## The full set as it stood

| Row | Today | Last proposal |
| --- | --- | --- |
| STANDALONE | #00D4AA | #00D4AA |
| MANAGE | #29B6F6 | #65C1FE |
| WATCHDOG | #8BC34A | #77D163 |
| DEVICES | #FFB300 | #FF9B52 |
| NETWORK | #4DD0E1 | #11CEE2 |
| ROUTER LOG | #8E5499 | #7598FF (or #87A7FE, #6489FE) |
| APP LOG | #6052FF | #E8EAF0 |
| SETTINGS | #8A97A0 | gold #FFD54F, or orange (Andrew liked orange) |
| ABOUT | #8A97A0 | violet #B388FF |
| EXIT | #FF5C5C | #FF5C5C |

With orange for SETTINGS, DEVICES' proposed orange #FF9B52 would need to move, probably back towards its amber.

## How the mock-ups were drawn

A throwaway widget test pumped `PiaWgApp` at 1440 x 3120, 3.0, with Flutter's Roboto and MaterialIcons and Windows' Consolas standing in for `monospace`, after temporarily editing `kDestinationColours`; Pillow laid the goldens side by side. The test was deleted and `app_colors.dart` restored each time.

## 2026-11-04: resumed, three sets drawn

- Andrew liked none of the earlier mock-ups, and wants the menu colourful, saturated and rich. Asked what the best set would be.
- The rules used: every row its own colour; each hue at the most saturation sRGB can show at its lightness; STANDALONE's teal and EXIT's red kept, being the accent and the error colour; every colour at least 6:1 against the background (4.5 is the usual minimum).
- A (`menu-colours/menu-set-A.png`): a spectrum from teal to red the cool way round, all at OKLCH lightness 0.70. Calm, but STANDALONE, MANAGE and WATCHDOG are hard to tell apart.
- B (`menu-set-B.png`): ten hues 36 degrees apart, all at lightness 0.70, EXIT kept red. Better apart, but yellow at 0.70 is olive.
- C (`menu-set-C.png`), Claude's recommendation: B's order, MANAGE moved towards sky, and the warm hues at their own lightness so they glow rather than go muddy.

| Row | Today | C |
| --- | --- | --- |
| STANDALONE | #00D4AA | #00D4AA |
| MANAGE | #29B6F6 | #19B3EE |
| WATCHDOG | #8BC34A | #699CFC |
| DEVICES | #FFB300 | #A288FC |
| NETWORK | #4DD0E1 | #E550FC |
| ROUTER LOG | #8E5499 | #FD55AC |
| APP LOG | #6052FF | #FD932F |
| SETTINGS | #8A97A0 | #F4CE1F |
| ABOUT | #8A97A0 | #4EE11C |
| EXIT | #FF5C5C | #FF5C5C |

- Drawn by a throwaway widget test of `PiaWgApp` at 1080 x 2340, 2.625, with Flutter's own Roboto and icon fonts, after a temporary edit of `kDestinationColours`; the test was deleted and `app_colors.dart` restored each time. `menu-today.png` is today's set, drawn the same way.

## 2026-11-04: C chosen; SETTINGS rows too

- Andrew chose C: "it feels natural and not jarring like the current menu colours".
- He wants SETTINGS' row names and icons colourised as well, similar to the menu but not the same: today every row is teal, or red for the three destructive ones (REBOOT ROUTER, MAX ACTIVE VPNS, UNINSTALL), which looks disorganised.
- v1 (`menu-colours/settings-v1-all-spectrum.png`): all 11 rows' names and icons in a spectrum from cyan to green, the destructive three keeping a red outline. UNINSTALL came out green, which reads as "go".
- v2 (`settings-v2-red-kept.png`), Claude's recommendation: the destructive three stay red, outline and all, so red means danger and nothing else; the other eight take an 8-step spectrum, not C's colours, so a SETTINGS row isn't mistaken for a menu row. Outlines stay teal.

| Row | v2 |
| --- | --- |
| REBOOT ROUTER | red, as today |
| ROUTER RESOLVER STATUS | #1ABAC8 |
| ROUTER DNS ROUTING | #1FAFFC |
| HOME SCREEN WIDGET KEY | #8B9CFC |
| FORGET ROUTER IP | #BF84FC |
| REMOVE CACHED PIA CERT | #FD52E1 |
| REMOVE CACHED PIA SERVERS | #FDA75C |
| MAX ACTIVE VPNS | red, as today |
| SECURE STARTUP | #DEBB1B |
| RESTORE PURCHASE | #90D61C |
| UNINSTALL FEATURES DEPLOYED TO ROUTER | red, as today |

- Drawn the same way as the menu sets, with `_Action` temporarily given a colour per row; restored after. The heading reads grey in both, as today; with C it becomes SETTINGS' gold.
- Andrew chose v2, 2026-11-04. He also asked for the best order for SETTINGS' rows: REBOOT ROUTER is at the top as the one used most, UNINSTALL at the bottom as the one used least, and both are red as commands that make major changes, as MAX ACTIVE VPNS is. The order today is his from 2026-10-14 (ID-325), pinned by a test in `settings_screen_test.dart`.
- Drawn in that order with v2's colours by position and C's gold heading: `menu-colours/settings-v2-new-order.png`.
- Andrew liked `settings-v2-new-order.png`, 2026-11-04: C for the menu, v2's colours, and the new order. Not yet built.

## 2026-11-04: a colour per VPN slot, in DEVICES and NETWORK

- Andrew asked what DEVICES would look like with each VPN slot in its own colour, matched in NETWORK.
- Five fixed colours, one per slot wherever it appears, none near teal (OK), red (error) or amber (warning): wgc5 #1BBEDC cyan, wgc4 #6AA5FC blue, wgc3 #AE8DFC violet, wgc2 #FD51E5 magenta, wgc1 #B5D51D lime; contrast 6.6 to 11 against the background. Internet stays white; "default - wgcN" takes wgcN's colour.
- Drawn with five invented tunnels and seven devices, headings in C: `menu-colours/slots-devices.png`, `menu-colours/slots-network.png`. In DEVICES the picker's text takes the slot's colour; in NETWORK the card's title does. The two grey blocks under DEVICES' list are its disabled buttons, whose font the test didn't have, not part of the design.
- Seen in the render: DEVICES' violet heading is close to wgc3's violet, and NETWORK's magenta heading to wgc2's magenta. Ten menu colours and five slot colours can't all differ.
- Andrew: wgc1's colour liked; wgc2 too bright, wgc3 to wgc5 too dark. Redrawn (`slots-devices-2.png`, `slots-network-2.png`) nearer wgc1's lightness, with wgc2 less saturated: wgc5 #20D3F4, wgc4 #86B6FD, wgc3 #BCA3FD, wgc2 #F48EE1, wgc1 #B5D51D, contrast 8.6 to 11. At wgc1's own lightness (OKLCH 0.82) blue and violet can only be pale, so wgc3 and wgc4 sit at 0.77 to keep some richness.
- Andrew: "good and well balanced"; asked for slightly more luminosity so they pop. All five lifted by 0.04 in OKLCH lightness, each at the most saturation sRGB allows there (`slots-network-3.png`): wgc5 #52DFFD, wgc4 #9CC3FD, wgc3 #C7B3FD, wgc2 #FD9EEB, wgc1 #C2E31F; contrast 9.9 to 12.5.
- Andrew asked for more saturation. At set 3's lightness, sRGB has none to give: wgc5 and wgc2 were within 1% of their limit, the others at it. Set 4 (`slots-network-4.png`) steps lightness back halfway towards set 2, every colour at full saturation there: wgc5 #19D7F9, wgc4 #80B3FD, wgc3 #B99EFE, wgc2 #FE7CE8, wgc1 #BBDC17; contrast 8.1 to 11.7.
- Andrew liked set 4, with more saturation for wgc3: wgc3 at OKLCH 0.71, full saturation, #AC88FD, contrast 6.7 (`slots-network-5.png`). Close to DEVICES' C heading, #A288FC.
- Andrew, 2026-11-04: "that's great", with the order reversed so wgc5 is green. Final slot colours: wgc5 #BBDC17 lime, wgc4 #FE7CE8 pink, wgc3 #AC88FD violet, wgc2 #80B3FD blue, wgc1 #19D7F9 cyan. Internet stays white; "default - wgcN" takes wgcN's colour.
- Drawn reversed: `slots-final-devices.png`, `slots-final-network.png`.
- Andrew, 2026-11-04: use the slot colours everywhere a slot is shown, MANAGE, WATCHDOG and both logs included, with only "wgcN" coloured and the region left white. Drawn with one helper colouring each "wgcN" in place: `token-devices.png`, `token-network.png`, `token-applog.png`. In the logs the rest of each line keeps its own colour (teal info, white success, amber warning, red error), so a red line still reads as an error.
- Andrew changed his mind, 2026-11-04: the region takes the slot's colour too, so the whole "wgcN:region" label is coloured, as in `slots-final-devices.png` and `slots-final-network.png`, everywhere including both logs. A bare "wgcN" is coloured on its own; the rest of a log line keeps its own colour.
