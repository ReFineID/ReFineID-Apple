```{=typst}
// Table cells are short phrases, not prose: justifying them stretches
// "ECDH on brainpoolP384r1" into "ECDH      on    brainpoolP384r1".
// Body text stays justified.
#show table: set par(justify: false)
```

Déclaration de fourniture et de transfert depuis un État membre de
l'Union européenne d'un moyen de cryptologie, au titre de l'article 30
de la loi n° 2004-575 du 21 juin 2004 pour la confiance dans l'économie
numérique et du chapitre II du décret n° 2007-663 du 2 mai 2007.

ReFineID est un intergiciel qui rend la carte nationale d'identité
finlandaise utilisable comme identité numérique sur les plateformes
Apple.

Le déclarant demande la délivrance de l'attestation de déclaration.

## A. Déclarant (personne physique)

| Champ | Valeur |
|:---------------------------|:-----------------------------------------------|
| Nom et prénoms | Koistinen, Petri |
| Nationalité | finlandaise |
| Adresse | Niittaajankatu 8a A 21, 00810 Helsinki, Finlande |
| Numéro de téléphone | +358 44 956 4098 |
| Adresse de courrier électronique | petri.koistinen@iki.fi |

## B. Moyen de cryptologie auquel s'applique la déclaration

### B.1. Informations générales sur le moyen

| Champ | Valeur |
|:---------------------------|:-----------------------------------------------|
| Nom | ReFineID |
| Désignation générique | Intergiciel pour carte nationale d'identité |
| Référence commerciale | Aucune |
| Version | 26 |
| Date prévue de mise sur le marché | 1er novembre 2026 |
| Plateformes | iOS, iPadOS, macOS |

### B.2. Description fonctionnelle du moyen

#### B.2.1. Classez le moyen dans la ou les catégorie(s) correspondante(s)

**Logiciel.**

#### B.2.2. Description générale du moyen

Le moyen lit la carte via l'antenne NFC du téléphone ou un lecteur de
carte à contact, publie le certificat d'authentification et la clé
publique de la carte dans le trousseau du système par CryptoTokenKit, et
transmet les demandes de signature à la carte. Safari et les autres
applications du système s'authentifient ensuite avec la carte comme avec
tout autre certificat client.

#### B.2.3. Indiquez à quelle catégorie se rapporte la fonction principale du moyen

**Sécurité de l'information** (bibliothèque et intergiciel
cryptographiques).

### B.3. Description technique des services de cryptologie fournis

#### B.3.1. Description des fonctionnalités cryptographiques du moyen

Messagerie sécurisée PACE avec la carte, signatures d'authentification
client et, sur macOS, signatures de documents PAdES avec horodatage
RFC 3161.

#### B.3.2. Indiquez à quelle(s) catégorie(s) se rapporte(nt) la ou les fonctions cryptographiques du moyen

Authentification, intégrité, confidentialité et signature.

#### B.3.3. Indiquez le(s) protocole(s) sécurisé(s) utilisés par le moyen

Autres protocoles : PACE selon ICAO Doc 9303 partie 11 et BSI
TR-03110-3 ; messagerie sécurisée selon ISO/IEC 7816-4.

#### B.3.4. Précisez les algorithmes cryptographiques utilisés et leurs longueurs maximales de clés

Les opérations sur la courbe brainpoolP384r1 et le CMAC sont écrits dans
le moyen ; l'AES, le SHA-2 et la vérification des signatures ECDSA et RSA
sont appelés dans les bibliothèques du système d'exploitation. Tous les
algorithmes sont publiés par des organismes de normalisation
internationaux ; aucun n'est propriétaire.

| Algorithme | Mode | Taille de clé | Fonction |
|:-------------------|:-------------|:------------|:-------------------------------|
| ECDH sur brainpoolP384r1 | PACE-GM (mappage générique) | 384 bits | Accord de clés PACE |
| AES | CBC | 256 bits | Confidentialité de chaque APDU après PACE |
| AES | CMAC | 256 bits | Intégrité de chaque APDU après PACE |
| SHA-256 | s.o. | s.o. | Dérivation des clés de session PACE |
| SHA-224, SHA-256, SHA-384, SHA-512 | s.o. | s.o. | Condensats des signatures d'authentification |
| ECDSA sur NIST P-384 | s.o. | 384 bits | Signature d'authentification client |
| RSA | PKCS#1 v1.5 | 3072 bits | Signature d'authentification client |
| RSA | PSS | 3072 bits | Signature d'authentification client |

La fonction de condensation des signatures ECDSA est choisie par le
service appelant ; les cartes à clé RSA n'emploient que SHA-256.

Normes correspondantes : ECDH, RFC 5639 et BSI TR-03111 ; AES,
FIPS 197 avec NIST SP 800-38A (CBC) et NIST SP 800-38B avec RFC 4493
(CMAC) ; SHA-2, FIPS 180-4 ; ECDSA, FIPS 186-5 et ANSI X9.62 ; RSA,
RFC 8017.

#### Gestion des clés

- Les clés privées sont générées dans la carte par l'autorité émettrice
  et n'en sortent jamais.
- Les clés de session PACE sont éphémères.
- Aucun séquestre de clés, aucun recouvrement, aucune gestion de clés à
  distance.

## C. Cas d'un moyen de cryptologie relevant de la catégorie 3 de l'annexe 2 du décret n° 2007-663 du 2 mai 2007

Le déclarant déclare que le moyen relève de la catégorie 3.

### Présentez le mode de commercialisation du moyen de cryptologie et le marché auquel il s'adresse

Le moyen sera mis à disposition du public sur l'App Store d'Apple. Il
s'adresse aux titulaires d'une carte nationale d'identité finlandaise
résidant en France qui souhaitent s'authentifier auprès de services en
ligne.

### Expliquez pourquoi la fonctionnalité cryptographique du moyen ne peut pas être modifiée facilement par l'utilisateur

La suite cryptographique est imposée par la carte à puce finlandaise
délivrée par l'État et ne peut pas être modifiée par l'utilisateur.

### Expliquez en quoi les modalités d'installation du moyen ne nécessitent pas d'assistance importante ultérieure de la part du fournisseur

L'utilisateur installe l'application depuis l'App Store, puis utilise
celle-ci pour installer le certificat de sa carte sur l'iPhone, sans
intervention du fournisseur.

## D. Renouvellement d'autorisation de transfert ou d'exportation

Aucune autorisation antérieure.

## E. Pièces à joindre

| Pièce demandée | État |
|:---------------------------|:-----------------------------------------------|
| Document général présentant la société | Personne physique. |
| Extrait K bis de moins de trois mois | Aucune société immatriculée. |
| Brochure commerciale | Aucune. |
| Brochure technique | Présent dossier, rubriques B.2 et B.3. |
| Manuel utilisateur | Aucun. |
| Guide administrateur | Aucune fonction d'administration. |

## F. Attestation

Je soussigné, Koistinen Petri, agissant en qualité de fournisseur et
pour mon propre compte, certifie que les
renseignements figurant dans le présent dossier sont exacts et ont été
établis de bonne foi, et m'engage à porter à la connaissance de l'Agence
nationale de la sécurité des systèmes d'information, sans délai, tout
élément nouveau de fait ou de droit de nature à modifier la présente
déclaration.

Fait à Helsinki, le 4 août 2026.

```{=typst}
#v(1fr)
#block(breakable: false)[
  #line(length: 100%, stroke: 0.4pt)
  #v(0.3em)
  #text(style: "italic", size: 9pt)[
    Ce document est signé électroniquement. La signature est une signature
    électronique qualifiée : en vertu de l'article 25, paragraphe 2, du
    règlement (UE) n° 910/2014, elle a un effet juridique équivalent à celui
    d'une signature manuscrite. Validation en ligne et gratuite à l'adresse
    #link("https://dvv.fineid.fi/fr/validation"), entre autres services.
  ]
]
```

```{=typst}
#pagebreak()
```

```{=typst}
// The second half is English: mark it so a screen reader switches
// voice and Typst hyphenates by English rules rather than French.
#set text(lang: "en", region: none)
```

# English version

Declaration of the supply of a cryptographic product and its transfer
from a Member State of the European Union under Article 30 of Law
No. 2004-575 of 21 June 2004 on confidence in the digital economy and
Chapter II of Decree No. 2007-663 of 2 May 2007.

ReFineID is middleware that makes the Finnish national identity card
usable as a digital identity on Apple platforms.

The declarant requests an attestation confirming this declaration.

## A. Declarant (individual)

| Field | Value |
|:---------------------------|:-----------------------------------------------|
| Name | Koistinen, Petri |
| Nationality | Finnish |
| Address | Niittaajankatu 8a A 21, 00810 Helsinki, Finland |
| Telephone | +358 44 956 4098 |
| Email | petri.koistinen@iki.fi |

## B. Cryptographic product covered by this declaration

### B.1. General information

| Field | Value |
|:---------------------------|:-----------------------------------------------|
| Name | ReFineID |
| Generic designation | Middleware for a national identity card |
| Commercial reference | None |
| Version | 26 |
| Planned market placement date | 1 November 2026 |
| Platforms | iOS, iPadOS, macOS |

### B.2. Functional description

#### B.2.1. Classification of the product

**Software.**

#### B.2.2. General description of the product

The product reads the card over the phone's NFC antenna or a contact
smart-card reader, publishes the card's authentication certificate and
public key to the system keychain through CryptoTokenKit, and passes
signature requests to the card. Safari and other system consumers then
authenticate with the card as they would with any other client
certificate.

#### B.2.3. Category of the principal function

**Information security** (cryptographic library and middleware).

### B.3. Technical description

#### B.3.1. Description of the cryptographic functionality

PACE secure messaging with the card, client-authentication signatures
and, on macOS, PAdES document signatures with RFC 3161 timestamps.

#### B.3.2. Categories the cryptographic functions fall under

Authentication, integrity, confidentiality and signature.

#### B.3.3. Secure protocols used by the product

Other protocols: PACE as specified in ICAO Doc 9303 part 11 and BSI
TR-03110-3; secure messaging as specified in ISO/IEC 7816-4.

#### B.3.4. Cryptographic algorithms used and their maximum key lengths

The brainpoolP384r1 curve operations and the CMAC are written in the
product; AES, SHA-2 and ECDSA and RSA signature verification are called
from the operating system's libraries. All algorithms are
published by international standards bodies; none is proprietary.

| Algorithm | Mode | Key size | Function |
|:-------------------|:-------------|:------------|:-------------------------------|
| ECDH on brainpoolP384r1 | PACE-GM (generic mapping) | 384 bits | PACE key agreement |
| AES | CBC | 256 bits | Confidentiality of each APDU after PACE |
| AES | CMAC | 256 bits | Integrity of each APDU after PACE |
| SHA-256 | n/a | n/a | Derivation of the PACE session keys |
| SHA-224, SHA-256, SHA-384, SHA-512 | n/a | n/a | Digests of the authentication signatures |
| ECDSA on NIST P-384 | n/a | 384 bits | Signed by the card, verified locally |
| RSA | PKCS#1 v1.5 | 3072 bits | Signed by the card, verified locally |
| RSA | PSS | 3072 bits | Signed by the card, verified locally |

The digest for an ECDSA signature is chosen by the calling service; RSA
card generations use SHA-256 alone.

Corresponding standards: ECDH, RFC 5639 and BSI TR-03111; AES, FIPS 197
with NIST SP 800-38A (CBC) and NIST SP 800-38B with RFC 4493 (CMAC);
SHA-2, FIPS 180-4; ECDSA, FIPS 186-5 and ANSI X9.62; RSA, RFC 8017.

#### Key management

- The card's private keys are generated on the card by the issuing
  authority and never leave it.
- PACE session keys are ephemeral.
- There is no key escrow, no key recovery and no remote key
  management.

## C. Cryptographic product within category 3 of annex 2 to decree No 2007-663 of 2 May 2007

The declarant declares that the product falls within category 3.

### Describe the product's distribution model and target market

The product will be made available to the public through Apple's App Store.
It is intended for holders of a Finnish national identity card residing
in France who wish to authenticate to online services.

### Explain why the cryptographic functionality cannot easily be modified by the user

The cryptographic suite is imposed by the Finnish government-issued
smart card and cannot be modified by the user.

### Explain how installation requires no significant subsequent support from the supplier

The user installs the app from the App Store and uses it to install the
card certificate on the iPhone, without supplier assistance.

## D. Renewal of a transfer or export authorisation

No prior authorisation.

## E. Documents to attach

| Item requested | Status |
|:---------------------------|:-----------------------------------------------|
| General document presenting the company | Private individual. |
| Extract K bis less than three months old | No registered company. |
| Commercial brochure | None. |
| Technical brochure | This dossier, sections B.2 and B.3. |
| User manual | None. |
| Administrator guide | No administration function. |

## F. Attestation

I, the undersigned, Koistinen Petri, acting on my own behalf as the
supplier, certify that the information in this
dossier is accurate and has been established in good faith, and
undertake to inform the Agence nationale de la sécurité des systèmes
d'information without delay of any new matter of fact or of law liable
to alter this declaration.

Done at Helsinki, 4 August 2026.

```{=typst}
#v(1fr)
#block(breakable: false)[
  #line(length: 100%, stroke: 0.4pt)
  #v(0.3em)
  #text(style: "italic", size: 9pt)[
    This document is electronically signed. The signature is a qualified
    electronic signature: under Article 25(2) of Regulation (EU) No 910/2014
    it has legal effect equivalent to that of a handwritten signature.
    Validation is available online, free of charge, at
    #link("https://dvv.fineid.fi/en/validation"), among other services.
  ]
]
```
