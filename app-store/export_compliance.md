# Export compliance: the facts for Andrew's decision

ID-430. App Store Connect asks whether the app uses encryption, and `ITSAppUsesNonExemptEncryption` in `ios/Runner/Info.plist` answers it once for every upload. The answer is Andrew's; these are the facts it rests on, read from the code on 2026-10-19. What exempts what is set by US export rules and Apple's page on them ("Complying with Encryption Export Regulations"), which could not be fetched here, so nothing below says which answer is right.

## What the app encrypts, and with whose code

- **SSH to the user's router**, the app's main job: the `dartssh2` package, whose ciphers and key exchange are Dart code (`pointycastle`, `pinenacl`), not Apple's. It encrypts the session, including the router password and every command.
- **HTTPS to PIA**, for the server list and a WireGuard key: Dart's `HttpClient` in `pia_service.dart`. The TLS is Dart's own, built into the Flutter engine, not Apple's.
- **WireGuard key pairs**, made on the phone (`x25519` in `pia_service.dart`). The app makes keys; the router's WireGuard does the tunnel encryption, not the app.
- **PIA's server list signature**, checked with RSA and SHA-256 (`pointycastle`, `server_list_verify.dart`). Authentication only.
- **The home screen widget's Ed25519 key** (`pinenacl`, `widget_key.dart`). Android only for now (ID-425); authentication only.

## What every one of them is

Standard, published algorithms, used for the purposes they were designed for. Nothing proprietary, nothing the user can configure beyond choosing a server, and no encryption offered as a service to anything else on the phone.

## What Andrew decides

1. Which of Apple's answers fits these facts: encryption within Apple's operating system only; standard algorithms instead of, or as well as, Apple's; or something else.
2. Whether that answer needs documents in App Store Connect, or a report anywhere else, and if so, who prepares them.
3. Then `ITSAppUsesNonExemptEncryption` is set to match, and the first upload (ID-431) should ask no encryption question.
