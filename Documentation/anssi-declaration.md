# ReFineID -- déclaration d'un moyen de cryptologie

ReFineID fournit un moyen de cryptologie assurant des fonctions de
confidentialité, et relève à ce titre de la déclaration prévue par le
Code de la sécurité intérieure (articles R2321-1 et suivants, décret
n° 2007-663). Le présent dossier décrit le déclarant, le produit et la
cryptographie mise en oeuvre.

Une traduction anglaise suit à titre de référence ; le texte français
fait foi.

## Déclarant

| Champ | Valeur |
|---|---|
| Fournisseur | ReFineID |
| Contact | Petri Koistinen, petri.koistinen@refineid.fi |
| Pays d'établissement | Finlande |
| Adresse postale | Niittaajankatu 8a A 21, 00810 Helsinki, Finlande |

## Produit

| Champ | Valeur |
|---|---|
| Nom | ReFineID |
| Version | Versionnement calendaire `AA.M.J` (26.8.3 à la date du dossier) |
| Plateformes | iOS 26, iPadOS 26, macOS 26 |
| Distribution | App Store d'Apple ; code source public : https://github.com/ReFineID/ReFineID-Apple |
| Catégorie | Intergiciel pour carte nationale d'identité |

ReFineID rend la carte nationale d'identité finlandaise utilisable comme
identité à certificat client au travers des cadriciels de sécurité
d'Apple. Le produit lit la carte via l'antenne NFC du téléphone ou un
lecteur de carte à contact, publie le certificat d'authentification et la
clé publique de la carte dans le trousseau du système par CryptoTokenKit,
et transmet les demandes de signature à la carte. Safari et les autres
consommateurs du système s'authentifient ensuite avec la carte comme avec
tout autre certificat client.

## Fonctions cryptographiques

Deux fonctions, et aucune autre :

1. **Établissement d'un canal sécurisé avec la carte.** La carte scelle
   son application PKCS#15 sur l'interface sans contact et refuse toute
   lecture (`SW=6982`) tant que PACE n'a pas été exécuté. PACE est un
   accord de clés authentifié par mot de passe, fondé sur le numéro
   d'accès imprimé sur la carte. Il établit la proximité et dérive des
   clés de session ; tous les échanges ultérieurs sont chiffrés et
   authentifiés sous ces clés.
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

Mis en oeuvre en Swift dans le module `CardCore`, aucun cadriciel Apple
ne mettant en oeuvre les protocoles propres à la carte. Tous les
algorithmes sont publiés par des organismes de normalisation
internationaux ; aucun n'est propriétaire.

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

# English translation, for reference

Translation of the French dossier above, which prevails.

## Declarant

| Field | Value |
|---|---|
| Supplier | ReFineID |
| Contact | Petri Koistinen, petri.koistinen@refineid.fi |
| Country of establishment | Finland |
| Postal address | Niittaajankatu 8a A 21, 00810 Helsinki, Finland |

## Product

| Field | Value |
|---|---|
| Name | ReFineID |
| Version | Calendar versioning `YY.M.D` (26.8.3 at the date of this dossier) |
| Platforms | iOS 26, iPadOS 26, macOS 26 |
| Distribution | Apple App Store; public source code: https://github.com/ReFineID/ReFineID-Apple |
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

1. **Opening a secure channel to the card.** The card seals its PKCS#15
   application on the contactless interface and refuses every read
   (`SW=6982`) until PACE has run. PACE is a password-authenticated key
   agreement keyed by the card access number printed on the card. It
   establishes proximity and derives session keys; every exchange
   afterwards is encrypted and authenticated under them.
2. **Client authentication signatures.** The private key stays in the
   card, which performs the signature. The product formats the input,
   passes it to the card, and verifies the result against the card's own
   public key before returning it to the operating system.

The product does not encrypt user data at rest, does not encrypt files
or storage, provides no encrypted messaging or telephony, implements no
VPN or transport tunnel, and performs no network communication of its
own. TLS is handled by the operating system; ReFineID contributes only
the card's signature.

## Algorithms implemented

Implemented in Swift in the `CardCore` module, no Apple framework
implementing the card's own protocols. All algorithms are published by
international standard bodies; none are proprietary.

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
suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4); Secure Messaging as specified in
ISO/IEC 7816-4.

## Key management

- The card's private keys are generated on the card by the issuing
  authority and never leave it. The product cannot read them and never
  holds them.
- PACE session keys are ephemeral: derived per session, held in memory
  only, destroyed when the session ends.
- The card access number, and PIN1 where the holder chooses to store it,
  are held in the Apple keychain with the attributes
  `WhenUnlockedThisDeviceOnly` and non-synchronizable: never written to
  a backup, never restored onto another device, never sent to iCloud.
- There is no key escrow, no key recovery, no remote key management, and
  no transmission of any key over a network.
