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
