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

## The publicly available source route

`ReFineID-Apple` is a public repository, so the whole implementation is
publicly available encryption source code. 15 CFR 740.13(e) treats that
differently from closed commercial software: notification by email
rather than a registration.

**Sent 2026-08-03, 11:22 EEST, to `enc@nsa.gov`, copy to
`crypt@bis.doc.gov`.** No reply is expected and none is required; the
regulation asks for notice, not permission. The text, kept so a later
notice for a new repository or a moved URL says the same thing:

    Subject: TSU notification - publicly available encryption source code

    Under 15 CFR 740.13(e), notice is given that the following publicly
    available encryption source code is available at no cost:

    ReFineID - Finnish identity card middleware for Apple platforms
    https://github.com/ReFineID/ReFineID-Apple

    The software implements PACE (ICAO 9303-11, BSI TR-03110) with ECDH on
    brainpoolP384r1, AES-256 CBC and AES-CMAC secure messaging, and ECDSA
    and RSA PKCS#1 v1.5 signature verification. All algorithms are published
    by international standard bodies; none are proprietary.

    Petri Koistinen
    ReFineID
    Finland
    petri.koistinen@refineid.fi

What this does not settle, and what a qualified answer is worth getting
before relying on it: whether the exception reaches the App Store
binary, or only the source in the repository. If only the source, the
binary falls back to the mass-market route -- an Encryption
Registration Number, which is a free SNAP-R submission usually answered
in about a business day, not a CCATS. The French declaration is a
separate regime either way.

## France

The app is to be available in France, so the French declaration applies:
supplying a cryptographic means that provides confidentiality requires a
declaration to ANSSI, and PACE's channel is exactly that. The technical
dossier is `Documentation/anssi-declaration.md`, in English and in
French. App Store Connect asks for ANSSI's acknowledgement at step 3 of
App Encryption Documentation.

Excluding France was the alternative and was considered: it would have
removed this step entirely and shipped sooner. It was not taken. A
Finnish cardholder living in France has a French App Store account, and
an identity product that quietly does not exist where its holder lives
is a worse answer than a filing.

## What is still needed

1. The ANSSI declaration filed, and its acknowledgement received.
2. That acknowledgement attached to App Encryption Documentation in App
   Store Connect.
3. The code Apple issues in return, added to
   `Config/ReFineID-Info.plist` as `ITSEncryptionExportComplianceCode`.

Until step 3, nothing uploads, and the archive inspector says so.
