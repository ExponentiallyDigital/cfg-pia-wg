# Plan: accept credentials from an Android password manager

**Status:** agreed for build 404. Implemented in the same session this was written — once it is in,
`.claude/CONTEXT.md` is the current state, not this file.

## Why

Every credential in this app is typed or pasted. Pasting is the realistic path — the user keeps
them in KeePass — and pasting is exactly what the 60-second clipboard auto-clear exists to mitigate.
Android's Autofill Framework lets the password manager put the value straight into the field, so the
clipboard never holds a secret at all. That removes the risk rather than mitigating it, and it
changes nothing about the app's zero-persistence model: the app still stores nothing.

The app currently opts **out** of autofill without meaning to. Flutter's own documentation:

> When set to null, this text input will not send its autofill information to the platform… on
> Android and web, setting this to null will disable autofill for this text field.

No field in `lib/` sets `autofillHints`, so every provider is blind to the app today.

**FLAG_SECURE was the open question and it is settled:** verified on a Pixel against a banking app
that sets the flag — KeePass still offered to fill. Autofill is a system service, not a screen
capture, so the flag does not block it.

## Scope

Minimum platform is API 26 for autofill; `minSdk` here is 24, so a 24/25 device silently gets the
old typing behaviour. Nothing to guard.

Five forms hold credentials. Each becomes its own `AutofillGroup`, so a provider can never conflate
PIA credentials with router SSH credentials with SMTP credentials:

| Form | File | Fields to hint |
| --- | --- | --- |
| Generate config | `screens/standalone_config_screen.dart` | PIA username, PIA password |
| Router connect | `widgets/router_slots_screen.dart` | SSH username, SSH password |
| DEL PIA CERT prompt | `screens/about_screen.dart` (`_SshCredsDialog`) | SSH username, SSH password |
| PIA credentials prompt | `widgets/slot_modal.dart` (`_PiaCredsDialog`) | PIA username, PIA password |
| Watchdog dialog | `watchdog_dialog.dart` | PIA username/password, SMTP username/password |

The hints themselves go on the shared widgets in `widgets/common_fields.dart`
(`PiaUsernameField`, `PiaPasswordField`, `SshUsernameField`, `SshPasswordField`) and on
`watchdog_dialog.dart`'s local `_field` builder, so each form site only gains an `AutofillGroup`.

Android has no hint for "SSH password" or "PIA password" — only generic `username` / `password`. The
user picks the right vault entry; separate groups are what stop the framework guessing.

**Not hinted:** router IP, DNS servers, ping targets, region, email addresses, SMTP host. They are
not secrets and a password vault has no business filling them.

## Save prompts

A provider only offers "save this?" when the app finishes the autofill context. Design:

- every group is created with `onDisposeAction: AutofillContextAction.cancel`, so dismissing a
  dialog or leaving a screen never raises a save prompt;
- `TextInput.finishAutofillContext()` is called explicitly at the points where the credentials have
  just been **proven correct** — after a successful config generation, and after a successful router
  connect.

So the prompt appears exactly once, only when the credentials worked. Cancelling asks nothing.

## Tests

- Each credential field carries the expected `autofillHints` (`username` / `password`).
- Each of the five forms is wrapped in an `AutofillGroup`, and PIA and SSH credentials are never in
  the same group.
- Fields that are not secrets carry no hints — a guard against a future field being wired up
  carelessly.
- `TextInput.finishAutofillContext` reaches the platform after a successful generate and after a
  successful connect (mock `SystemChannels.textInput`, assert the method call), and does **not**
  after a failure.

Device verification is still required for the thing tests cannot see: that KeePass actually offers
the fill, on a release build with FLAG_SECURE set.
