# ReFineID -- déclaration d'un moyen de cryptologie

Dossier de déclaration au titre du Code de la sécurité intérieure
(articles R2321-1 et suivants, décret n° 2007-663). ReFineID fournit un
moyen de cryptologie assurant des fonctions de confidentialité et relève
à ce titre de l'obligation de déclaration.

Les rubriques suivent celles du formulaire annexe I de l'ANSSI, dans le
même ordre, afin que le dossier réponde au formulaire point par point.

Nature de la demande : deuxième case du formulaire, **déclaration de
fourniture, de transfert depuis ou vers un État membre de l'Union
européenne, d'importation et d'exportation vers un État n'appartenant
pas à l'Union européenne** d'un moyen de cryptologie, au titre du seul
chapitre II du décret n° 2007-663.

La distribution se faisant par l'App Store d'Apple, elle n'est pas
limitée à la France : la fourniture, le transfert vers les autres États
membres et l'exportation hors de l'Union européenne sont tous
susceptibles de se produire, et sont donc tous couverts par la présente
déclaration. La déclaration d'exportation est ouverte au moyen parce
qu'il relève de la catégorie 3 de l'annexe 2 du décret, justifiée en
rubrique C.

Aucune demande d'autorisation au titre du chapitre III n'est formée.

Une traduction anglaise suit à titre de référence ; le texte français
fait foi.

## A. Déclarant

Le déclarant est un particulier (rubrique A.2 du formulaire). ReFineID
est un nom commercial employé par le déclarant en son nom propre ; il ne
désigne aucune personne morale. La rubrique A.1 est sans objet : il n'y
a ni dénomination sociale, ni numéro SIRET, ni société pour le compte de
laquelle la déclaration serait faite.

| Champ | Valeur |
|---|---|
| Nom et prénoms | Koistinen, Petri |
| Nationalité | Finlandaise |
| Adresse | Niittaajankatu 8a A 21, 00810 Helsinki, Finlande |
| Numéro de téléphone | +358 44 956 4098 |
| Adresse de courrier électronique | petri.koistinen@iki.fi |

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
| Date de mise sur le marché | 3 août 2026 |
| Plateformes | iOS 26, iPadOS 26, macOS 26 |

## B.2. Description fonctionnelle du moyen

### B.2.1. Classez le moyen dans la ou les catégorie(s) correspondante(s)

**Logiciel.** Le moyen ne comporte aucun élément matériel.

### B.2.2. Description générale du moyen

ReFineID rend la carte nationale d'identité
finlandaise utilisable comme identité à certificat client au travers des
cadriciels de sécurité d'Apple. Le moyen lit la carte via l'antenne NFC
du téléphone ou un lecteur de carte à contact, publie le certificat
d'authentification et la clé publique de la carte dans le trousseau du
système par CryptoTokenKit, et transmet les demandes de signature à la
carte. Safari et les autres consommateurs du système s'authentifient
ensuite avec la carte comme avec tout autre certificat client. Le porteur
s'en sert pour se connecter à des services en ligne avec sa carte
d'identité.

### B.2.3. Indiquez à quelle catégorie se rapporte la fonction principale du moyen

**Sécurité de l'information** (bibliothèque et intergiciel
cryptographiques). Aucune des autres catégories proposées -- ordinateur,
envoi/stockage/réception d'informations, réseau -- ne s'applique.

## B.3. Description technique des services de cryptologie fournis

### B.3.1. Description des fonctionnalités cryptographiques du moyen

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

### B.3.2. Indiquez à quelle(s) catégorie(s) se rapporte(nt) la ou les fonctions cryptographiques du moyen

Authentification, intégrité, confidentialité et signature -- toutes
quatre, exercées entre le moyen et la carte, et non sur les données de
l'utilisateur.

### B.3.3. Indiquez le(s) protocole(s) sécurisé(s) utilisés par le moyen

Ni IPsec, ni SSH, ni protocoles de VoIP, ni SSL/TLS. TLS est assuré par
le système d'exploitation ; le moyen ne met en oeuvre aucune pile TLS et
ne fournit que la signature de la carte.

Autres protocoles : PACE selon ICAO Doc 9303 partie 11 et BSI TR-03110-3,
suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4) ; messagerie sécurisée selon
ISO/IEC 7816-4.

### B.3.4. Précisez les algorithmes cryptographiques utilisés et leurs longueurs maximales de clés

Mis en oeuvre en Swift dans le module `CardCore`, aucun cadriciel Apple
ne mettant en oeuvre les protocoles propres à la carte. Tous les
algorithmes sont publiés par des organismes de normalisation
internationaux ; aucun n'est propriétaire.

Les colonnes reprennent celles de la rubrique B.3.4 du formulaire.

| Algorithme | Mode | Taille de clé associée | Fonction |
|---|---|---|---|
| ECDH sur brainpoolP384r1 | PACE-GM (mappage générique) | 384 bits | Accord de clés PACE |
| AES | CBC | 256 bits | Confidentialité de chaque APDU après PACE |
| AES | CMAC | 256 bits | Intégrité de chaque APDU après PACE |
| SHA-256, SHA-384 | s.o. | s.o. | Dérivation de clés et condensats de signature |
| ECDSA sur NIST P-384 | s.o. | 384 bits | Vérification de la signature de la carte |
| RSA | PKCS#1 v1.5 | 3072 bits | Vérification, cartes à clé RSA |
| RSA | PSS | 3072 bits | Vérification, cartes à clé RSA |

Normes correspondantes : ECDH, RFC 5639 et BSI TR-03111 ; AES,
FIPS 197 avec NIST SP 800-38A (CBC) et NIST SP 800-38B avec RFC 4493
(CMAC) ; SHA-2, FIPS 180-4 ; ECDSA, FIPS 186-4 et ANSI X9.62 ; RSA,
RFC 8017.

### Gestion des clés (hors rubriques du formulaire)

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

## C. Cas d'un moyen de cryptologie relevant de la catégorie 3 de l'annexe 2 du décret n° 2007-663

La case est cochée : le déclarant déclare que le moyen relève de la
catégorie 3 de l'annexe 2 du décret n° 2007-663 du 2 mai 2007. Les
éléments justificatifs demandés suivent, dans l'ordre du formulaire.

### Présentez le mode de commercialisation du moyen de cryptologie et le marché auquel il s'adresse

Distribution exclusivement par l'App Store d'Apple, au grand public, sans
négociation, sans personnalisation et sans contrat particulier. Le marché
visé est le porteur d'une carte nationale d'identité finlandaise
souhaitant s'authentifier auprès de services en ligne. Le code source est
public : https://github.com/ReFineID/ReFineID-Apple

### Expliquez pourquoi la fonctionnalité cryptographique du moyen ne peut pas être modifiée facilement par l'utilisateur

La suite cryptographique est fixée à la compilation. La suite PACE et les
paramètres de domaine sont imposés par la carte et inscrits dans le
produit ; aucune interface, aucun réglage et aucun fichier de
configuration ne permet de choisir un algorithme, une longueur de clé ou
un protocole différent. L'application est signée et son intégrité
vérifiée par le système d'exploitation, qui refuse d'exécuter un binaire
modifié.

### Expliquez en quoi les modalités d'installation du moyen ne nécessitent pas d'assistance importante ultérieure de la part du fournisseur

L'installation se fait par l'App Store en une action. Il n'y a ni
serveur à paramétrer, ni certificat à installer, ni service à souscrire.
Le porteur saisit le numéro d'accès imprimé au dos de sa carte, présente
la carte une fois, et le moyen est opérationnel. Aucune intervention du
fournisseur n'est requise.

## D. Renouvellement d'autorisation de transfert ou d'exportation

Sans objet. La rubrique D ne concerne qu'un moyen ayant déjà fait
l'objet d'une autorisation de transfert ou d'exportation ; la présente
demande est une première déclaration et n'en invoque aucune.

## E. Pièces jointes

Documentation technique : le présent dossier. Le code source complet est
publiquement accessible à l'adresse indiquée en C, ce qui couvre les
éléments relatifs à la conception du moyen.

## F. Signataire

| Champ | Valeur |
|---|---|
| Nom et prénoms | Koistinen, Petri |
| Agissant en qualité de | Fournisseur et auteur du moyen, personne physique |
| Pour le compte de | Lui-même, en son nom propre (aucune personne morale) |
| Date | 3 août 2026 |

```{=typst}
#place(bottom + left, block(width: 100%)[
  #line(length: 100%, stroke: 0.4pt)
  #v(0.3em)
  #text(style: "italic", size: 9pt)[
    Ce document est signé électroniquement. La signature est une signature
    électronique qualifiée au sens du règlement (UE) nº 910/2014
    (article 3, point 12), créée par un dispositif qualifié de création de
    signature électronique et fondée sur un certificat qualifié délivré par
    l'Agence des services de données numériques et démographiques
    (Digi- ja väestötietovirasto, DVV), prestataire de services de confiance
    qualifié finlandais. En vertu de l'article 25, paragraphe 2, du même
    règlement, elle a l'effet juridique d'une signature manuscrite.

    La validation est possible en ligne et gratuitement à l'adresse
    #link("https://dvv.fineid.fi/fr/validation"), ou par tout autre moyen
    retenu par le destinataire.
  ]
])
```

```{=typst}
#pagebreak()
```

# English translation, for reference

Translation of the French dossier above, which prevails. Headings follow
ANSSI's annexe I form.

Nature of the request: the form's second checkbox, **declaration of
supply, of transfer from or to a member state of the European Union, of
import and of export to a state outside the European Union** of a means
of cryptology, under chapter II of decree No 2007-663 alone.

Distribution is through Apple's App Store and so is not confined to
France: supply, transfer to other member states and export outside the
European Union may all occur, and are all covered by this declaration.
Export is declarable rather than subject to authorisation because the
means falls under category 3 of annex 2 to the decree, justified in
section C.

No authorisation under chapter III is requested.

## A. Declarant

An individual (section A.2 of the form). ReFineID is a trading name
used by the declarant in a personal capacity; it names no legal entity.
Section A.1 does not apply: there is no registered company name, no
SIRET number, and no company on whose behalf the declaration is made.

| Field | Value |
|---|---|
| Name | Koistinen, Petri |
| Nationality | Finnish |
| Address | Niittaajankatu 8a A 21, 00810 Helsinki, Finland |
| Telephone | +358 44 956 4098 |
| Email | petri.koistinen@iki.fi |

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
| Date placed on the market | 3 August 2026 |
| Platforms | iOS 26, iPadOS 26, macOS 26 |

## B.2. Functional description

### B.2.1. Classification of the means

**Software.** The means contains no hardware component.

### B.2.2. General description of the means

ReFineID makes the Finnish national identity card usable as a client
certificate identity through Apple's security frameworks. It reads the
card over the phone's NFC antenna or a contact smart-card reader,
publishes the card's authentication certificate and public key to the
system keychain through CryptoTokenKit, and passes signature requests to
the card. Safari and other system consumers then authenticate with the
card as they would with any other client certificate. The holder uses it
to sign in to online services with their identity card.

### B.2.3. Category of the principal function

**Information security** (cryptographic library and middleware). None of
the other categories offered -- computer, sending/storage/reception of
information, network -- applies.

## B.3. Technical description

### B.3.1. Description of the cryptographic functionality

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

### B.3.2. Categories the cryptographic functions fall under

Authentication, integrity, confidentiality and signature -- all four,
exercised between the means and the card, not on the user's data.

### B.3.3. Secure protocols used by the means

Neither IPsec, SSH, VoIP protocols, nor SSL/TLS. TLS is handled by the
operating system; the means implements no TLS stack and contributes only
the card's signature.

Other protocols: PACE as specified in ICAO Doc 9303 Part 11 and BSI
TR-03110-3, suite `id-PACE-ECDH-GM-AES-CBC-CMAC-256`
(OID 0.4.0.127.0.7.2.2.4.2.4); Secure Messaging as specified in
ISO/IEC 7816-4.

### B.3.4. Cryptographic algorithms used and their maximum key lengths

Implemented in Swift in the `CardCore` module, no Apple framework
implementing the card's own protocols. All algorithms are published by
international standard bodies; none are proprietary.

The columns are those of section B.3.4 of the form.

| Algorithm | Mode | Associated key size | Function |
|---|---|---|---|
| ECDH on brainpoolP384r1 | PACE-GM (generic mapping) | 384 bits | PACE key agreement |
| AES | CBC | 256 bits | Confidentiality of each APDU after PACE |
| AES | CMAC | 256 bits | Integrity of each APDU after PACE |
| SHA-256, SHA-384 | n/a | n/a | Key derivation and signature digests |
| ECDSA on NIST P-384 | n/a | 384 bits | Verification of the card's signature |
| RSA | PKCS#1 v1.5 | 3072 bits | Verification, RSA card generations |
| RSA | PSS | 3072 bits | Verification, RSA card generations |

Corresponding standards: ECDH, RFC 5639 and BSI TR-03111; AES, FIPS 197
with NIST SP 800-38A (CBC) and NIST SP 800-38B with RFC 4493 (CMAC);
SHA-2, FIPS 180-4; ECDSA, FIPS 186-4 and ANSI X9.62; RSA, RFC 8017.

### Key management (outside the form's sections)

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

## C. Means falling under category 3 of annex 2 to decree No 2007-663

The box is ticked: the declarant states that the means falls under
category 3 of annex 2 to decree No 2007-663 of 2 May 2007. The
supporting points the form asks for follow, in its order.

### Present the means of commercialisation and the market it addresses

Distributed solely through the Apple App Store, to the general public,
with no negotiation, no customisation and no individual contract. The
target market is the holder of a Finnish national identity card wishing
to authenticate to online services. The source code is public:
https://github.com/ReFineID/ReFineID-Apple

### Explain why the cryptographic functionality cannot easily be modified by the user

The cryptographic suite is fixed at compile time. The PACE suite and
domain parameters are imposed by the card and written into the product;
no interface, setting or configuration file allows a different algorithm,
key length or protocol to be chosen. The application is signed and its
integrity verified by the operating system, which refuses to run a
modified binary.

### Explain how installation requires no significant subsequent support from the supplier

Installation is a single action through the App Store. There is no server
to configure, no certificate to install and no service to subscribe to.
The holder enters the access number printed on their card, presents the
card once, and the means is operational. No supplier intervention is
required.

## D. Renewal of a transfer or export authorisation

Not applicable. Section D concerns a means for which a transfer or
export authorisation was previously granted; this is a first
declaration and invokes none.

## E. Attachments

Technical documentation: this dossier. The complete source code is
publicly accessible at the address given in section C, which covers the
design elements of the means.

## F. Signatory

| Field | Value |
|---|---|
| Name | Koistinen, Petri |
| Acting in the capacity of | Supplier and author of the means, private individual |
| On behalf of | Himself, in his own name (no legal entity) |
| Date | 3 August 2026 |

```{=typst}
#place(bottom + left, block(width: 100%)[
  #line(length: 100%, stroke: 0.4pt)
  #v(0.3em)
  #text(style: "italic", size: 9pt)[
    This document is electronically signed. The signature is a qualified
    electronic signature within the meaning of Regulation (EU) No 910/2014
    (Article 3(12)), created by a qualified electronic signature creation
    device and based on a qualified certificate issued by the Digital and
    Population Data Services Agency (DVV), a Finnish qualified trust
    service provider. Under Article 25(2) of that Regulation it has the
    legal effect of a handwritten signature.

    Validation is available online, free of charge, at
    #link("https://dvv.fineid.fi/en/validation"), or by any other means the
    recipient prefers.
  ]
])
```
