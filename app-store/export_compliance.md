# Export compliance: the facts for Andrew's decision

ID-430. App Store Connect asks whether the app uses encryption, and `ITSAppUsesNonExemptEncryption` in `ios/Runner/Info.plist` answers it once for every upload. The answer is Andrew's; these are the facts it rests on, read from the code on 2026-10-19. What exempts what is set by US export rules and Apple's pages on them, read on 2026-10-20 and summarised in the next section. The answer is still Andrew's: Apple says the developer carries the liability for claiming an exemption wrongly.

## What the app encrypts, and with whose code

- **SSH to the user's router**, the app's main job: the `dartssh2` package, whose ciphers and key exchange are Dart code (`pointycastle`, `pinenacl`), not Apple's. It encrypts the session, including the router password and every command.
- **HTTPS to PIA**, for the server list and a WireGuard key: Dart's `HttpClient` in `pia_service.dart`. The TLS is Dart's own, built into the Flutter engine, not Apple's.
- **WireGuard key pairs**, made on the phone (`x25519` in `pia_service.dart`). The app makes keys; the router's WireGuard does the tunnel encryption, not the app.
- **PIA's server list signature**, checked with RSA and SHA-256 (`pointycastle`, `server_list_verify.dart`). Authentication only.
- **The home screen widget's Ed25519 key** (`pinenacl`, `widget_key.dart`). Android only for now (ID-425); authentication only.

## What every one of them is

Standard, published algorithms, used for the purposes they were designed for. Nothing proprietary, nothing the user can configure beyond choosing a server, and no encryption offered as a service to anything else on the phone.

## What Apple's pages say, read 2026-10-20

- **[Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations):** an upload goes to a server in the US, so an app distributed outside the US or Canada is subject to US export law "regardless of where your legal entity is based". `ITSAppUsesNonExemptEncryption` is set to NO if the app, "including any third-party libraries it links against", uses no encryption or "only uses forms of encryption that are exempt from export compliance documentation requirements", and to YES otherwise. Encryption built into the operating system, such as HTTPS through `URLSession`, is "typically" exempt; proprietary encryption is not. An app using exempt encryption "might alternatively be required to submit a year-end self-classification report to the U.S. government"; one that provides documentation to Apple does not.
- **[Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)**, Apple's table:

  | Encryption in use | Documentation in App Store Connect |
  | --- | --- |
  | Limited to that within Apple's operating system | None |
  | An industry standard algorithm, not provided within Apple's operating system | The French encryption declaration |
  | Proprietary algorithms not accepted by standards bodies (IEEE, IETF, ITU) | A US CCATS, and the French encryption declaration |

  The French declaration is needed only if the app is on the App Store in France.
- **[Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance):** apps using standard encryption algorithms need a determination too. "Non-standard cryptography" means proprietary or unpublished cryptography not adopted by a recognised standards body. The developer is "responsible for all liabilities associated with misinterpretation of export regulations or claiming exemption inaccurately". In France the controlled items are mainly secure storage, secure communications and anti-virus apps.
- **[Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation):** App Store Connect asks its questions under App Information, App Encryption Documentation. Documents are reviewed in about two business days, and an approved one gives a code for `ITSEncryptionExportComplianceCode` in `Info.plist`. Questions go to Apple's export process contact form.

## What the facts and the table point to

Every algorithm the app uses is an industry standard one (IETF's SSH and TLS, X25519, Ed25519, RSA, SHA-256), and none of it is Apple's, so the app sits in the table's middle row. The SSH session protects the router password and every command, so its encryption is for data security, not authentication alone. So, read from Apple's pages and not a legal opinion:

- **Sold in France:** the French encryption declaration is uploaded in App Store Connect.
- **Not sold in France:** the table asks for no document. Whether `ITSAppUsesNonExemptEncryption` is then NO, or YES with no document, is the open question, along with whether the year-end self-classification report applies. App Store Connect's own questions, or Apple's export contact form, settle it.

## Decided, 2026-10-20

Andrew's decision: the app is on sale in France. So, following Apple's table and its rule for the key:

- **`ITSAppUsesNonExemptEncryption` is YES** in `ios/Runner/Info.plist`. Apple says NO only for an app with no encryption or only encryption "exempt from export compliance documentation requirements", and the French declaration is such a document.
- **The French encryption declaration** is prepared and uploaded in App Store Connect, under App Information, App Encryption Documentation, before the first build goes to TestFlight review.
- **Once Apple approves it**, the code App Store Connect gives goes into `Info.plist` as `ITSEncryptionExportComplianceCode`, and uploads stop asking.
- Since documentation goes to Apple, Apple's page says the year-end self-classification report "isn't necessary".

## Revised, 2026-10-20: France left out of the first release

Andrew's decision, so the declaration can't delay shipping; it replaces the decision above. Selling in France later is ID-462.

- **`ITSAppUsesNonExemptEncryption` is NO.** Outside France, Apple's table asks for no document for standard encryption, and NO is the value for an app whose encryption is "exempt from export compliance documentation requirements".
- **France is unticked** in App Store Connect's availability, by country or region, before the first submission.
- **The year-end self-classification report:** Apple's page says an app using exempt encryption "might alternatively be required to submit" one to the US government. It is a yearly report, not something App Store Connect waits for, so it doesn't hold up shipping. Whether it applies is in Andrew's list below.

## What Andrew decides

1. Whether the App Store sells the app in France, which decides whether the French encryption declaration is needed. **Decided:** not in the first release (ID-462).
2. Which answer App Store Connect's questions give, and whether the year-end self-classification report applies: answered in App Store Connect, or asked of Apple through its export contact form.
3. Then `ITSAppUsesNonExemptEncryption` is set to match, and the first upload (ID-431) should ask no encryption question.
