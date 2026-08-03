# ReFineID -- déclaration d'un moyen de cryptologie

Dossier de déclaration au titre du Code de la sécurité intérieure
(articles R2321-1 et suivants, décret n° 2007-663). ReFineID fournit un
moyen de cryptologie assurant des fonctions de confidentialité et relève
à ce titre de l'obligation de déclaration.

Les rubriques suivent celles du formulaire annexe I de l'ANSSI, dans le
même ordre, afin que le dossier réponde au formulaire point par point.

Nature de la demande : **déclaration uniquement** (fourniture en France).

Une traduction anglaise suit à titre de référence ; le texte français
fait foi.

## A. Déclarant

Le déclarant est un particulier (rubrique A-2 du formulaire).

| Champ | Valeur |
|---|---|
| Nom et prénoms | Koistinen, Petri |
| Nationalité | Finlandaise |
| Adresse | Niittaajankatu 8a A 21, 00810 Helsinki, Finlande |
| Numéro de téléphone | +358 44 956 4098 |
| Adresse de courrier électronique | petri.koistinen@refineid.fi |

Personne que l'ANSSI peut contacter pour obtenir des informations
techniques sur le moyen : la même, aux mêmes coordonnées.

Le déclarant est également le fabricant du moyen ; la rubrique relative
à un fabricant tiers est sans objet.

## B.1. Informations générales sur le moyen

| Champ | Valeur |
|---|---|
| Dénomination du moyen | ReFineID |
| Désignation générique | Intergiciel pour carte nationale d'identité |
| Marque de distribution | ReFineID |
| Référence commerciale | ReFineID |
| Version | Versionnement calendaire `AA.M.J` (26.8.3 à la date du dossier) |
| Date de mise sur le marché | *[à compléter : date prévue de publication sur l'App Store]* |
| Plateformes | iOS 26, iPadOS 26, macOS 26 |

## B.2. Description fonctionnelle du moyen

Catégorie : **logiciel**. Le moyen ne comporte aucun élément matériel.

Catégorie de la fonction principale : **sécurité de l'information**
(bibliothèque et intergiciel cryptographiques).

Description générale : ReFineID rend la carte nationale d'identité
finlandaise utilisable comme identité à certificat client au travers des
cadriciels de sécurité d'Apple. Le moyen lit la carte via l'antenne NFC
du téléphone ou un lecteur de carte à contact, publie le certificat
d'authentification et la clé publique de la carte dans le trousseau du
système par CryptoTokenKit, et transmet les demandes de signature à la
carte. Safari et les autres consommateurs du système s'authentifient
ensuite avec la carte comme avec tout autre certificat client. Le porteur
s'en sert pour se connecter à des services en ligne avec sa carte
d'identité.

## B.3. Description technique des services de cryptologie fournis

### Fonctionnalités cryptographiques

Deux fonctions, et aucune autre :

1. **Établissement d'un canal sécurisé avec la carte.** La carte scelle
   son application PKCS#15 sur l'interface sans contact et refuse toute
   lecture (`SW=6982`) tant que PACE n'a pas été exécuté. PACE est un
   accord de clés authentifié par mot de passe, fondé sur le numéro
   d'accès imprimé sur la carte. Il établit la proximité et dérive des
   clés de session ; tous les échanges ultérieurs avec la carte sont
   chiffrés et authentifiés sous ces clés.
2. **Signatures d'authentification client.** La clé privée reste dans la
   carte, qui réalise la signature. Le moyen met en forme l'entrée, la
   transmet à la carte, et vérifie le résultat avec la clé publique de la
   carte avant de le rendre au système d'exploitation.

Le moyen ne chiffre pas les données de l'utilisateur au repos, ne chiffre
ni fichiers ni supports de stockage, n'offre ni messagerie ni téléphonie
chiffrée, ne met en oeuvre aucun RPV (VPN) ni tunnel de transport, et
n'effectue aucune communication réseau propre.

### Catégories de fonctions cryptographiques

Authentification, intégrité, confidentialité et signature -- toutes
quatre, exercées entre le moyen et la carte, et non sur les données de
l'utilisateur.

### Protocoles sécurisés utilisés

Ni IPsec, ni SSH, ni protocoles de VoIP, ni SSL/TLS. TLS est assuré par
le système d'exploitation ; le moyen ne met en oeuvre aucune pile TLS et
ne fournit que la signature de la carte.

Autres protocoles : PACE selon ICAO Doc 9303 partie 11 et BSI TR-03110-3,
suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4) ; messagerie sécurisée selon
ISO/IEC 7816-4.

### Algorithmes et longueurs maximales de clés

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

### Gestion des clés

- Les clés privées sont générées dans la carte par l'autorité émettrice
  et n'en sortent jamais. Le moyen ne peut pas les lire et ne les détient
  jamais.
- Les clés de session PACE sont éphémères : dérivées par session, gardées
  en mémoire seulement, détruites à la fin de la session.
- Le numéro d'accès de la carte, et le cas échéant le PIN1 si le porteur
  choisit de le conserver, sont stockés dans le trousseau Apple avec les
  attributs `WhenUnlockedThisDeviceOnly` et non synchronisable : jamais
  écrits dans une sauvegarde, jamais restaurés sur un autre appareil,
  jamais transmis à iCloud.
- Aucun séquestre de clés, aucun recouvrement, aucune gestion de clés à
  distance, aucune transmission de clé sur un réseau.

## C. Moyen relevant de la catégorie 3 (grand public)

### Mode de commercialisation et marché visé

Distribution exclusivement par l'App Store d'Apple, au grand public, sans
négociation, sans personnalisation et sans contrat particulier. Le marché
visé est le porteur d'une carte nationale d'identité finlandaise
souhaitant s'authentifier auprès de services en ligne. Le code source est
public : https://github.com/ReFineID/ReFineID-Apple

### Pourquoi la fonctionnalité cryptographique n'est pas modifiable par l'utilisateur

La suite cryptographique est fixée à la compilation. La suite PACE et les
paramètres de domaine sont imposés par la carte et inscrits dans le
produit ; aucune interface, aucun réglage et aucun fichier de
configuration ne permet de choisir un algorithme, une longueur de clé ou
un protocole différent. L'application est signée et son intégrité
vérifiée par le système d'exploitation, qui refuse d'exécuter un binaire
modifié.

### Pourquoi l'installation ne nécessite pas d'assistance ultérieure importante

L'installation se fait par l'App Store en une action. Il n'y a ni
serveur à paramétrer, ni certificat à installer, ni service à souscrire.
Le porteur saisit le numéro d'accès imprimé au dos de sa carte, présente
la carte une fois, et le moyen est opérationnel. Aucune intervention du
fournisseur n'est requise.

## E. Pièces jointes

Documentation technique : le présent dossier. Le code source complet est
publiquement accessible à l'adresse indiquée en C, ce qui couvre les
éléments relatifs à la conception du moyen.

## F. Signataire

| Champ | Valeur |
|---|---|
| Nom et prénoms | Koistinen, Petri |
| Qualité | Fournisseur et auteur du moyen |
| Société | ReFineID |
| Date | 3 août 2026 |

---

# English translation, for reference

Translation of the French dossier above, which prevails. Headings follow
ANSSI's annexe I form.

Nature of the request: **declaration only** (supply in France).

## A. Declarant

An individual (section A-2 of the form).

| Field | Value |
|---|---|
| Name | Koistinen, Petri |
| Nationality | Finnish |
| Address | Niittaajankatu 8a A 21, 00810 Helsinki, Finland |
| Telephone | +358 44 956 4098 |
| Email | petri.koistinen@refineid.fi |

Technical contact for ANSSI: the same person, same details. The declarant
is also the manufacturer, so the third-party manufacturer section does
not apply.

## B.1. General information

| Field | Value |
|---|---|
| Name of the means | ReFineID |
| Generic designation | Middleware for a national identity card |
| Brand | ReFineID |
| Commercial reference | ReFineID |
| Version | Calendar versioning `YY.M.D` (26.8.3 at the date of this dossier) |
| Date placed on the market | *[to be completed: planned App Store release date]* |
| Platforms | iOS 26, iPadOS 26, macOS 26 |

## B.2. Functional description

Category: **software**. The means contains no hardware component.

Principal function category: **information security** (cryptographic
library and middleware).

ReFineID makes the Finnish national identity card usable as a client
certificate identity through Apple's security frameworks. It reads the
card over the phone's NFC antenna or a contact smart-card reader,
publishes the card's authentication certificate and public key to the
system keychain through CryptoTokenKit, and passes signature requests to
the card. Safari and other system consumers then authenticate with the
card as they would with any other client certificate. The holder uses it
to sign in to online services with their identity card.

## B.3. Technical description

### Cryptographic functionality

Two functions, and nothing else:

1. **Opening a secure channel to the card.** The card seals its PKCS#15
   application on the contactless interface and refuses every read
   (`SW=6982`) until PACE has run. PACE is a password-authenticated key
   agreement keyed by the card access number printed on the card. It
   establishes proximity and derives session keys; every exchange with
   the card afterwards is encrypted and authenticated under them.
2. **Client authentication signatures.** The private key stays in the
   card, which performs the signature. The means formats the input,
   passes it to the card, and verifies the result against the card's own
   public key before returning it to the operating system.

The means does not encrypt user data at rest, does not encrypt files or
storage, provides no encrypted messaging or telephony, implements no VPN
or transport tunnel, and performs no network communication of its own.

### Categories of cryptographic function

Authentication, integrity, confidentiality and signature -- all four,
exercised between the means and the card, not on the user's data.

### Secure protocols used

Neither IPsec, SSH, VoIP protocols, nor SSL/TLS. TLS is handled by the
operating system; the means implements no TLS stack and contributes only
the card's signature.

Other protocols: PACE as specified in ICAO Doc 9303 Part 11 and BSI
TR-03110-3, suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4); Secure Messaging as specified in
ISO/IEC 7816-4.

### Algorithms and maximum key lengths

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

### Key management

- The card's private keys are generated on the card by the issuing
  authority and never leave it. The means cannot read them and never
  holds them.
- PACE session keys are ephemeral: derived per session, held in memory
  only, destroyed when the session ends.
- The card access number, and PIN1 where the holder chooses to store it,
  are held in the Apple keychain with the attributes
  `WhenUnlockedThisDeviceOnly` and non-synchronizable: never written to a
  backup, never restored onto another device, never sent to iCloud.
- There is no key escrow, no key recovery, no remote key management, and
  no transmission of any key over a network.

## C. Category 3 (mass market)

### Marketing and target market

Distributed solely through the Apple App Store, to the general public,
with no negotiation, no customisation and no individual contract. The
target market is the holder of a Finnish national identity card wishing
to authenticate to online services. The source code is public:
https://github.com/ReFineID/ReFineID-Apple

### Why the cryptographic functionality cannot easily be modified by the user

The cryptographic suite is fixed at compile time. The PACE suite and
domain parameters are imposed by the card and written into the product;
no interface, setting or configuration file allows a different algorithm,
key length or protocol to be chosen. The application is signed and its
integrity verified by the operating system, which refuses to run a
modified binary.

### Why installation requires no significant subsequent support

Installation is a single action through the App Store. There is no server
to configure, no certificate to install and no service to subscribe to.
The holder enters the access number printed on their card, presents the
card once, and the means is operational. No supplier intervention is
required.

## E. Attachments

Technical documentation: this dossier. The complete source code is
publicly accessible at the address given in section C, which covers the
design elements of the means.

## F. Signatory

| Field | Value |
|---|---|
| Name | Koistinen, Petri |
| Capacity | Supplier and author of the means |
| Company | ReFineID |
| Date | 3 August 2026 |
