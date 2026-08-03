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
issues one. Without the code App Store Connect blocks the build at
submission with error 90592 -- the upload itself completes; it is the
submission that stops -- and `Scripts/inspect-archive.sh` refuses the
archive before that, locally, in about a second.

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
| SHA-256 | `PaceKeyDerivation`, via CryptoKit | Deriving the PACE session keys. |
| SHA-224, SHA-256, SHA-384, SHA-512 | `SigningHash`, `SigningAlgorithmResolver` | Digests for the signatures the card makes; which one is the calling service's choice. |
| ECDSA P-384 | `EcdsaSignature` | Verifying what the card signed; the card holds the private key. |
| RSA-3072 PKCS#1 v1.5 | `Rsa3072Pkcs1Sha256EncodedMessage` | The same, for card generations with an RSA authentication key. |
| RSA-3072 PSS | `SigningAlgorithmResolver` | The shape TLS 1.3 asks for from an RSA card; the card computes it. |

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

Declaring non-exempt costs a self-classification or CCATS filing and a
French declaration. The French one is not annual: it is made once for
the means, and again only when what was declared changes. Declaring exempt on a judgement call costs
credibility, in a product whose entire subject is identity. The cost was
accepted deliberately rather than by default.

## The publicly available source route

`ReFineID-Apple` is a public repository, so the source-code question is
separate from the App Store binary question. The current EAR provision
to check for publicly available encryption source code is 15 CFR
742.15(b), not the old 740.13(e) text. The 2026-08-03 email that cited
740.13(e) is kept as an audit trail only; do not rely on it as the
operative notice.

Do not re-send mechanically. 742.15(b) is framed around publicly
available encryption source code, and ReFineID implements published
standard algorithms rather than non-standard cryptography. Confirm
whether any source-code notice is actually owed before sending another
one. If one is sent, it should cite the current provision and keep the
scope to the public source repository, for example:

    Subject: TSU notification - publicly available encryption source code

    Under 15 CFR 742.15(b), notice is given that the following publicly
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
dossier is `Documentation/anssi-declaration.md`, in French with an
English version; both stand on their own.

Excluding France was the alternative and was considered: it would have
removed this step entirely and shipped sooner. It was not taken. A
Finnish cardholder living in France has a French App Store account, and
an identity product that quietly does not exist where its holder lives
is a worse answer than a filing.

That dossier is a document for a regulator to read, not a page of our
notes, so it carries no repository cross-references and no task list.
Everything about *doing* the filing lives here instead. The exact
pipeline that produced the filed artifact:

    pandoc Documentation/anssi-declaration.md --pdf-engine=typst \
      -o "ReFineID - ANSSI declaration dossier.pdf"

    refineid card sign-document --format pades \
      --in  "ReFineID - ANSSI declaration dossier.pdf" \
      --out "ReFineID - ANSSI declaration dossier (signed).pdf" \
      --reason "Declaration d'un moyen de cryptologie -- decret 2007-663" \
      --location "Helsinki, Finlande" \
      --timestamp http://tsa.belgium.be/connect \
      --timestamp http://tsa.izenpe.com \
      --timestamp http://tss.accv.es:8318/tsa \
      --archive

    curl -s -X POST https://dvv.fineid.fi/api/v1/validate \
      -F locale=en -F includeDetails=true \
      -F "file=@ReFineID - ANSSI declaration dossier (signed).pdf"

Three qualified timestamp authorities so the proven time survives any
one of them losing its standing, and --archive for PAdES-B-LTA, the top
of the ETSI ladder. The validator must answer QES, PAdES-BASELINE-LTA,
TOTAL_PASSED; anything else means stop and look.

The markdown is the source of truth; the PDF is a rendering. Regenerate
rather than editing the PDF, or the two drift and the filed one wins.
Any edit to the markdown means render, sign and validate again -- the
signature covers the bytes, not the intent.

Before filing, have the French read by somebody who files these. It is
written to be accurate rather than idiomatic, and a regulator's form is
a poor place to find a translation error.

The dossier gives 1 October 2026 as the date placed on the market, and
the signature block keeps its own date. The gap is deliberate: the
decree requires the declaration to be filed at least one month before
the means is placed on the market, so the market date has to sit
comfortably after the filing, not on it. There is no hurry toward the
French market; if filing slips, move the market date before signing
rather than shaving the month.

### Where it goes

Checked against ANSSI rather than recalled. The dossier is not filed on
its own: it is the technical documentation attached to ANSSI's own form.

1. The declaration is `Documentation/anssi-declaration.md`, rendered and
   signed. It is drawn up according to annexe I: sections A to F in
   ANSSI's order, under ANSSI's own headings, carrying the attestation
   from section F of the form and the box-two statement from its first
   page.

   ANSSI's annexe I is a template -- a dynamic XFA PDF that only Adobe
   Reader can fill, and that carries no AcroForm fields, so no other
   tool can put a value in it. Filling a template is how you obtain a
   document; the document is what the decree asks for, and this one has
   the same content in the same order.

   The template is at
   https://cyber.gouv.fr/documents/330/crypto_declaration-demande_autorisation_operations_annexe1_v2.pdf
   if it is ever wanted. Do not take annexe 2 instead: it is titled
   *Déclaration de fourniture d'une prestation de cryptologie*, and a
   prestation is a service, not a moyen.

2. Render and sign, three qualified authorities and an archive
   timestamp, as above. Nothing is printed and nothing is scanned: a
   qualified electronic signature has the legal effect of a handwritten
   one under Article 25(2) of Regulation (EU) No 910/2014, and the
   attestation requires the declaration to be "datée et signée", not
   inked.
3. Email `controle@ssi.gouv.fr`, subject `[formalités] ReFineID - ReFineID`,
   attaching the signed declaration.

   Say in the body that the declaration follows annexe I section by
   section and is signed with a qualified electronic signature, and give
   the validation address so the reader can check it without installing
   anything. If ANSSI wants their own template back instead, they will
   say so, and that answer is worth keeping.

The form's own sections are A declarant, B the means, C category 3,
D renewal of a transfer or export authorisation, E documents attached,
F attestation. D applies only where a transfer or export authorisation
was granted before, so it is out of scope for a first declaration.

By post instead, if preferred:

    Secretariat general de la defense et de la securite nationale
    ANSSI / SDE / PSS / Bureau Controles Reglementaires
    51, boulevard de La Tour-Maubourg
    75700 PARIS 07 SP
    France

What comes back is an *attestation de déclaration*. That attestation is
what proves the obligation was met and what App Store Connect wants at
step 3. Ask for the *grand public* classification at declaration time rather
than afterwards; ANSSI rules on it within two months of the date of
receipt shown on the attestation. Until that ruling arrives the
classification is requested, not held: do not lean on category 3 for
exports outside the Union in the meantime, and treat the declaration
timetable as the one that applies.

## What is still needed

1. The ANSSI declaration filed, and its acknowledgement received.
2. That acknowledgement attached to App Encryption Documentation in App
   Store Connect.
3. The code Apple issues in return, added to
   `Config/ReFineID-Info.plist` as `ITSEncryptionExportComplianceCode`.

Until step 3, App Store Connect submission must stop at export
compliance. An archive may upload for inspection, but it must not be
submitted for release without the Apple code.
