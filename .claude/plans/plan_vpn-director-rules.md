# VPN Director rules in DEVICES, on Merlin (ID-596, ID-597)

Reasoning and design only; status lives in BACKLOG and CHANGELOG. Written 2026-11-15. The UI below is the initial concept Andrew liked, still to be discussed further before anything is built. Addresses in the mockups are invented; devices are named by type.

## Why

On Merlin, DEVICES already writes VPN Director rules: one per pinned device, and the whole-network rule for the default. What's missing is everything else. You can't see rules as rules, and the app can't touch the ones it doesn't own. On 2026-11-15 Andrew had to switch off two rules, "wanpin" and "vd2", in the web UI, because DEVICES had no way to show or change them. A change in the web UI also runs no custom script, so the guard doesn't catch up until the next tunnel start, boot or app action (ARCHITECTURE 6.10, "Not covered").

## What the app handles today

From `lib/merlin_vpn_director.dart` and `lib/merlin_guard.dart`:

- **What DEVICES owns:** rules for one device's address, with no remote address, to a WireGuard slot or WAN (`isDeviceRule`). Everything else passes through untouched and isn't shown anywhere in the app.
- **A device set to "default":** DEVICES switches its rule off rather than deleting it. Switched-off rules build up, and only the web UI shows them.
- **What the guard holds:** an enabled single-device rule to a tunnel gets the guard's `prohibit` at the top of its slot's range (11409 for wgc1), so the device fails closed. A range gets only the router's exemption at 9990, and only for a whole-network rule. A rule with a remote address gets nothing. Neither fails closed.

## Scope, Andrew's decisions 2026-11-15

- **Both stages, WireGuard only.** Rules can be made and changed for WGC1 to WGC5 and WAN, never OpenVPN.
- **OpenVPN rules are still listed, read-only.** By VPN Director's numbering (WAN from 10010, wgc1 from 11210, blocks of 200 per slot), the range between, 10210 to 11209, appears to be OpenVPN's, so its rules would act before any WireGuard rule. Hiding them would make the screen wrong about which rule wins. To be confirmed against Merlin's source or the router before the list's order is built.
- **Merlin only.** Stock's VPN Fusion has only per-device assignments, which DEVICES already covers; stock's web UI to be checked to confirm. Stock doesn't show the BY RULE switch.
- **Two items**, so stage 1 can ship without waiting on the guard work stage 2 needs.

## Where it goes

Inside DEVICES, as a second view, with BY DEVICE and BY RULE at the top. A separate menu entry would mean two screens each holding unapplied changes to the same file. One screen keeps one set of pending changes, one APPLY and one confirmation.

## Stage 1 (ID-596): see, switch on and off, and delete any rule

### The BY RULE view

Grouped in the order VPN Director acts on them, with each group showing its tunnel's state:

```text
  [ BY DEVICE ]  [ BY RULE ]

  Internet
  ┌──────────────────────────────────────┐
  │ wanpin                          off  │
  │ PHONE (192.168.1.20), everything     │
  └──────────────────────────────────────┘
  OpenVPN                    (left alone)
  └ none
  wgc1:pia-nz                         up
  ┌──────────────────────────────────────┐
  │ TABLET                               │
  │ TABLET (192.168.1.30), everything    │
  │ held: its tunnel or nothing          │
  └──────────────────────────────────────┘
  wgc5:pia-aus_melbourne              up
  ┌──────────────────────────────────────┐
  │ default (cfg-pia-wg)                 │
  │ the whole network, everything        │
  └──────────────────────────────────────┘
  Show switched-off rules (2)

        [ ADD RULE ]      [ APPLY ]
```

ADD RULE arrives with stage 2.

- **Each rule is a tile like DEVICES' tiles:**
  - the description first;
  - then from and to, with known devices named as DEVICES names them;
  - then a line saying whether the guard holds it to its tunnel, so you can see which rules fail closed.
- **Switched-off rules** sit behind a "Show switched-off rules" line at the end, so they don't crowd the list.
- **The whole-network rule** opens DEVICES' default picker when tapped, so the default is changed in one place only.
- **Actions:** switch any WireGuard or WAN rule on or off, delete it, and clear out the rules DEVICES has switched off.

### The write path

DEVICES' own, unchanged: write beside the live file with `printf`, rename it over, read it back, `service restart_vpnrouting0`, then run the guard. ARCHITECTURE 6.10's "Not covered" then applies only to changes made in the web UI.

- **Pending changes:** a change marks the tile changed; nothing is written until APPLY. DISCARD CHANGES works as it does in DEVICES.
- **APPLY's confirmation** lists every change in plain words, for example "Switch off wanpin: PHONE to the internet", then shows the applying panel. Anything the read-back or the guard reports goes to the app log.
- **The refusals:** DEVICES' refusal of a pin above the default's slot applies here too. Switching a rule on can't leave a pin that VPN Director would silently ignore (ARCHITECTURE 6.10, "A lower slot always wins").

## Stage 2 (ID-597): add and edit WireGuard rules, ranges and remote addresses included

### The rule editor

A dialog like MANAGE, EDIT, opened by tapping a rule or by ADD RULE:

```text
  Description   [ wanpin                ]  6/32
  From          ( ) a device   [ PHONE         v ]
                ( ) an address or range [            ]
  To            ( ) everything
                ( ) an address or range [            ]
  Send through  [ Internet              v ]
                  Internet, wgc1:pia-nz … wgc5 (WireGuard only)
  On            [x]

      [ DELETE ]   [ CANCEL ]   [ OK ]
```

- **Checked as you type:** the 32-character limit, the four characters the web page refuses (`<>'%`), and addresses and ranges inside the LAN.
- **Refused in the editor:** a pin above the default's slot, with DEVICES' wording.
- **Warned in the editor:** changing a device's own rule so it has a range or a remote address. The warning says DEVICES will stop showing it as that device's pin.
- **OK** stages the change, as in stage 1.

### What the guard needs first

Before range rules can be made in the app, the guard needs a `prohibit` for a range sent to a tunnel, so its devices fail closed as single devices do. That's a measurement on the router first, as the 11409 priority was: where the rule sits, that it holds through DISABLE, a tunnel's restart and a reboot, and that it doesn't catch the router's own address.

### Open decision, Andrew's

A rule that sends one remote address of a device pinned to a tunnel out the internet connection is a deliberate exception to "its tunnel or nothing". The app either refuses it, or allows it with a warning that names the device and the address.

## Not changed

- **The widget.** It names devices pinned to each tunnel, and a range or remote rule isn't a pin. It stays that way unless Andrew wants ranges counted.

## Screenshots

DEVICES gets a new view, so README's DEVICES images and both stores' screenshots need checking, and retaking where they show it.

## Tests, for either stage

- **Unit tests:** the file kept byte for byte as the web page writes it, OpenVPN rules passed through untouched, the screen's goldens, and the refusals.
- **A check in `check-claims.sh`:** a rule switched off in the app is gone from `ip rule` and the guard's `prohibit` goes with it; deleting it by hand makes the check fail. For stage 2, a range sent to a tunnel is held, and fails closed with the tunnel stopped.
- **A hand test in TESTING**, on Merlin, through a reboot.

## Still to discuss

The UI further, per Andrew, 2026-11-15: the concept above is agreed, the details aren't.
