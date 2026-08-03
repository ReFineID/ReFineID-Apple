# ANSSI declaration dossier

France regulates the supply of cryptographic means under the Code de la
sécurité intérieure (articles R2321-1 and following, décret n° 2007-663).
Supplying a means that provides confidentiality requires a declaration to
ANSSI; a means limited to authentication and integrity does not. ReFineID
establishes an encrypted channel to the card, so it is declarable.

This file is the technical dossier the declaration is built from. ANSSI's
own form asks for the declarant, the product and a technical description;
what follows is that description, in English for the record and in French
for the filing. The declaration is submitted by a person, not by this
repository -- nothing here is a substitute for filing it.

The equivalent US notice is in `Documentation/export-compliance.md`
(15 CFR 740.13(e), sent 2026-08-03).

## Declarant

| Field | Value |
|---|---|
| Supplier | ReFineID |
| Contact | Petri Koistinen, petri.koistinen@refineid.fi |
| Country of establishment | Finland |
| Postal address | *to be completed on the form* |

## Product

| Field | Value |
|---|---|
| Name | ReFineID |
| Version | Calendar versioning, `YY.M.D` (26.8.3 at the time of writing) |
| Platforms | iOS 26, iPadOS 26, macOS 26 |
| Distribution | Apple App Store; source code public at https://github.com/ReFineID/ReFineID-Apple |
| Category | Middleware for a national identity card |

ReFineID makes the Finnish national identity card usable as a client
certificate identity through Apple's security frameworks. It reads the
card over the phone's NFC antenna or a contact smart-card reader,
publishes the card's authentication certificate and public key to the
system keychain through CryptoTokenKit, and passes signature requests to
the card. Safari and other system consumers then authenticate with the
card as they would with any other client certificate.

## What the cryptography is for

Two things, and nothing else:

1. **Opening a secure channel to the card.** A Finnish identity card
   seals its PKCS#15 application on the contactless interface and answers
   `SW=6982` to every read until PACE has run. PACE is a
   password-authenticated key agreement keyed by the card access number
   printed on the card. It proves proximity and derives session keys, and
   every command afterwards is encrypted and authenticated under them.
2. **Client authentication signatures.** The card holds the private key
   and performs the signature. ReFineID formats the input, passes it to
   the card, and verifies the result against the card's own public key
   before handing it back to the operating system.

The product does **not** encrypt user data at rest, does not encrypt
files or storage, provides no messaging or voice encryption, implements
no VPN or transport tunnel, and performs no network communication of its
own. TLS is terminated by the operating system; ReFineID contributes only
the card's signature.

## Algorithms implemented

Implemented in Swift in the `CardCore` module, because no Apple framework
speaks the card's protocols. All are published; none are proprietary.

| Algorithm | Key length | Standard | Purpose |
|---|---|---|---|
| ECDH on brainpoolP384r1 | 384 bits | RFC 5639, BSI TR-03111 | PACE key agreement |
| AES-CBC | 256 bits | FIPS 197, NIST SP 800-38A | Confidentiality of each APDU after PACE |
| AES-CMAC | 256 bits | NIST SP 800-38B, RFC 4493 | Integrity of each APDU after PACE |
| SHA-256, SHA-384 | n/a | FIPS 180-4 | Key derivation and signature digests |
| ECDSA on NIST P-384 | 384 bits | FIPS 186-4, ANSI X9.62 | Verification of the card's signature |
| RSA PKCS#1 v1.5 | 3072 bits | RFC 8017 | Verification, RSA card generations |
| RSA PSS | 3072 bits | RFC 8017 | Verification, RSA card generations |

Protocols: PACE as specified in ICAO Doc 9303 Part 11 and BSI TR-03110-3,
using the suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4); Secure Messaging as specified in
ISO/IEC 7816-4.

## Key management

- The card's private keys are generated on the card by the issuing
  authority and never leave it. ReFineID cannot read them and never
  holds them.
- PACE session keys are ephemeral. They are derived per card session,
  held in memory only, and discarded when the session ends.
- The card access number, and optionally PIN1 if the holder chooses to
  store it, are held in the Apple keychain with the attributes
  `WhenUnlockedThisDeviceOnly` and non-synchronizable: never written to
  a backup, never restored onto another device, never sent to iCloud.
- There is no key escrow, no key recovery, no remote key management, and
  no transmission of any key over a network.

---

# Fiche technique (français)

## Déclarant

| Champ | Valeur |
|---|---|
| Fournisseur | ReFineID |
| Contact | Petri Koistinen, petri.koistinen@refineid.fi |
| Pays d'établissement | Finlande |
| Adresse postale | *à compléter sur le formulaire* |

## Produit

ReFineID est un intergiciel qui rend la carte nationale d'identité
finlandaise utilisable comme identité à certificat client au travers des
cadriciels de sécurité d'Apple. Le produit lit la carte via l'antenne NFC
du téléphone ou un lecteur de carte à contact, publie le certificat
d'authentification et la clé publique de la carte dans le trousseau du
système par CryptoTokenKit, et transmet les demandes de signature à la
carte. Versions : versionnement calendaire `AA.M.J`. Plateformes : iOS 26,
iPadOS 26, macOS 26. Code source public :
https://github.com/ReFineID/ReFineID-Apple

## Fonctions cryptographiques

Deux fonctions, et aucune autre :

1. **Établissement d'un canal sécurisé avec la carte.** La carte scelle
   son application PKCS#15 sur l'interface sans contact et refuse toute
   lecture tant que PACE n'a pas été exécuté. PACE est un accord de clés
   authentifié par mot de passe, fondé sur le numéro d'accès imprimé sur
   la carte. Il établit la proximité et dérive des clés de session ; tous
   les échanges ultérieurs sont chiffrés et authentifiés sous ces clés.
2. **Signatures d'authentification client.** La clé privée reste dans la
   carte, qui réalise la signature. Le produit met en forme l'entrée, la
   transmet à la carte, et vérifie le résultat avec la clé publique de la
   carte avant de le rendre au système d'exploitation.

Le produit ne chiffre pas les données de l'utilisateur au repos, ne
chiffre ni fichiers ni supports de stockage, n'offre ni messagerie ni
téléphonie chiffrée, ne met en oeuvre aucun RPV (VPN) ni tunnel de
transport, et n'effectue aucune communication réseau propre. TLS est
assuré par le système d'exploitation ; ReFineID ne fournit que la
signature de la carte.

## Algorithmes mis en oeuvre

| Algorithme | Longueur de clé | Norme | Usage |
|---|---|---|---|
| ECDH sur brainpoolP384r1 | 384 bits | RFC 5639, BSI TR-03111 | Accord de clés PACE |
| AES-CBC | 256 bits | FIPS 197, NIST SP 800-38A | Confidentialité de chaque APDU après PACE |
| AES-CMAC | 256 bits | NIST SP 800-38B, RFC 4493 | Intégrité de chaque APDU après PACE |
| SHA-256, SHA-384 | s.o. | FIPS 180-4 | Dérivation de clés et condensats de signature |
| ECDSA sur NIST P-384 | 384 bits | FIPS 186-4, ANSI X9.62 | Vérification de la signature de la carte |
| RSA PKCS#1 v1.5 | 3072 bits | RFC 8017 | Vérification, cartes à clé RSA |
| RSA PSS | 3072 bits | RFC 8017 | Vérification, cartes à clé RSA |

Protocoles : PACE selon ICAO Doc 9303 partie 11 et BSI TR-03110-3, suite
`id-PACE-ECDH-GM-AES-CBC-CMAC-256` (OID 0.4.0.127.0.7.2.2.4.2.4) ;
messagerie sécurisée selon ISO/IEC 7816-4.

Tous les algorithmes sont publiés par des organismes de normalisation
internationaux ; aucun n'est propriétaire.

## Gestion des clés

- Les clés privées sont générées dans la carte par l'autorité émettrice
  et n'en sortent jamais. Le produit ne peut pas les lire et ne les
  détient jamais.
- Les clés de session PACE sont éphémères : dérivées par session, gardées
  en mémoire seulement, détruites à la fin de la session.
- Le numéro d'accès de la carte, et le cas échéant le PIN1 si le porteur
  choisit de le conserver, sont stockés dans le trousseau Apple avec les
  attributs `WhenUnlockedThisDeviceOnly` et non synchronisable : jamais
  écrits dans une sauvegarde, jamais restaurés sur un autre appareil,
  jamais transmis à iCloud.
- Aucun séquestre de clés, aucun recouvrement, aucune gestion de clés à
  distance, aucune transmission de clé sur un réseau.

---

## What remains to be done by a person

1. Submit the declaration to ANSSI with the fiche technique above.
2. Have the French text checked by someone who files these; it is written
   to be accurate rather than idiomatic, and a regulator's form is a poor
   place to discover a translation error.
3. Attach ANSSI's acknowledgement to App Encryption Documentation step 3
   in App Store Connect.
4. Add the compliance code Apple issues to `Config/ReFineID-Info.plist`
   as `ITSEncryptionExportComplianceCode`.

`Scripts/inspect-archive.sh` refuses any archive that declares non-exempt
encryption without that code, so step 4 cannot be forgotten.
