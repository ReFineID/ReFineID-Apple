# Export compliance

What ReFineID declares to Apple about its cryptography, what it actually
implements, and the exact text submitted. Written so a later submission
says the same thing as this one, and so a reviewer asking "why did you
answer that" gets an answer rather than a shrug.

The declaration itself is recorded in `Documentation/decisions.md`
("Export compliance is declared as non-exempt"). This file is the
supporting detail.

## What is declared

`Config/ReFineID-Info.plist` carries:

    ITSAppUsesNonExemptEncryption = true

and must also carry `ITSEncryptionExportComplianceCode` once Apple
issues one. Without the code App Store Connect refuses the upload with
error 90592, and `Scripts/inspect-archive.sh` refuses the archive before
that, locally, in about a second.

## App Purpose, as submitted

App Store Connect asks for this in step 1 of App Encryption
Documentation, capped at 300 characters. Submitted verbatim:

> ReFineID is middleware for the Finnish national identity card. It
> reads the card over NFC or a smart-card reader, opens a PACE secure
> channel with the card access number, and publishes the card's
> certificate and key to the system keychain so Safari and other apps
> can sign in with the card.

290 characters. It names the three things a reviewer needs: what the app
is for, how it reaches the card, and what it hands to the system.

## What the app actually implements

This is the part that decides the answer. ReFineID does not merely call
the platform's cryptography -- it implements the card-side protocols in
Swift, in `CardCore`, because no Apple framework speaks them:

| Primitive | Where | Why it exists |
|---|---|---|
| ECDH on brainpoolP384r1 | `BrainpoolP384r1Values`, `PaceEstablishment` | The PACE key agreement. The curve is fixed by the card. |
| AES-256 CBC | `SecureMessagingChannel` | Confidentiality of every APDU after PACE. |
| AES-CMAC | `AesCmacValues`, `SecureMessagingChannel` | Integrity of every APDU after PACE. |
| SHA-256, SHA-384 | `SigningHash`, via CryptoKit | Digests for signing and for key derivation. |
| ECDSA P-384 | `EcdsaSignature` | Verifying what the card signed; the card holds the private key. |
| RSA-3072 PKCS#1 v1.5 | `Rsa3072Pkcs1Sha256EncodedMessage` | The same, for card generations with an RSA authentication key. |

The suite PACE runs is
`id-PACE-ECDH-GM-AES-CBC-CMAC-256` over brainpoolP384r1, which the card
advertises in EF.CardAccess and which this build sends without
negotiating (`Documentation/decisions.md`, "The PACE suite stays fixed").

None of it is proprietary. Every algorithm is published: PACE and secure
messaging in ICAO 9303-11 and BSI TR-03110, brainpoolP384r1 in RFC 5639,
AES in FIPS 197, CMAC in NIST SP 800-38B, ECDSA in FIPS 186, RSA PKCS#1
in RFC 8017.

## Why non-exempt rather than exempt

The exemption most nearly available is the one for cryptography limited
to authentication. It was considered and not taken.

PACE does authenticate -- it proves the terminal knows the card access
number and that the card is present -- but what it leaves behind is a
confidentiality channel: every APDU afterwards is AES-encrypted, and
that includes the certificate and the card serial read across it. An
exemption argued on "authentication only" would have to describe that
channel as incidental, which it is not; it is the reason the card
answers at all on the contactless interface.

Declaring non-exempt costs a self-classification or CCATS filing and an
annual French declaration. Declaring exempt on a judgement call costs
credibility, in a product whose entire subject is identity. The cost was
accepted deliberately rather than by default.

## What is still needed

1. Export compliance authorisation for the encryption -- in practice a
   US BIS Encryption Registration Number, plus the French declaration
   where that applies.
2. That documentation filed against the app in App Store Connect.
3. The code Apple issues in return, added to
   `Config/ReFineID-Info.plist` as `ITSEncryptionExportComplianceCode`.

Until step 3, nothing uploads, and the archive inspector says so.
