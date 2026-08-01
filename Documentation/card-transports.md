# Card transports: contact reader and iPhone NFC

ReFineID reaches a Finnish identity card over two physical transports.
Both terminate in the same place -- a CryptoTokenKit token extension that
publishes the card's certificate and key to the keychain, so Safari,
`URLSession`, and any other system consumer use the card as an ordinary
client-certificate identity.

| Transport | Platforms | Card interface | Access control |
|---|---|---|---|
| Contact / PC-SC reader | macOS, iPadOS, iOS (USB-C) | contact | PIN1 |
| Phone antenna (NFC) | iOS 26+, iPadOS 26+ | contactless | CAN, then PIN1 |

macOS has no NFC smart-card slot at all: `TKSmartCardSlotManager`'s NFC
surface is `API_UNAVAILABLE(macos)`. Every NFC path in this repository is
therefore behind `#if canImport(CoreNFC)` plus an iOS 26 availability
check. The app and extension derive the usable transport from what the
platform actually presents; there is no separate preference to become
stale.

## Why the contactless interface needs a CAN

A FINEID card seals its PKCS#15 application on the contactless
interface: every read is refused with `SW=6982` ("security status not
satisfied") until **PACE** has run. PACE is a password-authenticated key
agreement -- here over brainpoolP384r1, keyed by the six-digit **CAN**
printed on the card -- that both proves proximity and establishes a
secure-messaging channel for all later APDUs.

So the contactless flow has one extra step and one extra secret compared
to contact:

    contact:      SELECT -> read -> VERIFY PIN1 -> PSO:CDS
    contactless:  PACE(CAN) -> SELECT -> read -> VERIFY PIN1 -> PSO:CDS

The CAN is not a PIN: it authorizes *reading* the card in a field, not
signing. PIN1 still gates every signature.

## The NFC architecture on iOS 26

iOS 26 added `TKSmartCardSlotManager.createNFCSlot(message:)` and
`TKSmartCardTokenRegistrationManager`. The shape that works, proven on
device (see `refineid-mono-internal/doc/ios-native-nfc-safari.md`):

1. **Prime, once per card, in one field.** The app opens an NFC slot,
   runs PACE with the CAN, reads the authentication certificate and card
   serial, stores them plus the CAN in a keychain item shared with the
   extension, and registers the token -- all inside the same hold.
   A known public issuing CA comes from the app bundle after an exact
   issuer/subject match; only an unknown issuer is read from the card.
   The card is identified by a hash of its ATR. Two bridges make the
   single field work: a registration mark, written before the slot
   opens, tells the extension to publish without taking the card
   session; and the extension's mint waits briefly for the prime
   (`TokenDriver.awaitPrime`), because `ctkd` asks for the token the
   moment the card arrives, while PACE is still running. An
   already-primed card skips the card I/O and the whole hold is the
   registration.
2. **Login.** The app opens an NFC slot; ctkd asks the driver for a
   token; the driver materializes it from the stored prime (no card I/O
   is possible before PACE, so it must not try). The app waits for
   publication with `TKTokenWatcher`, then materializes a `SecIdentity`
   from the `com.apple.token` keychain group, passing PIN1 in an
   `LAContext` so no separate prompt is needed.
3. **Handshake.** The identity answers the client-certificate challenge.
   The extension runs PACE, verifies PIN1, and performs the on-card
   signature -- reaching the card through the slot the app is holding.

### Four rules that the implementation must not violate

Each of these was learned from a measured failure, and each looks like a
platform limitation when broken.

1. **Always open a card session (`beginSession`) before card I/O, on the
   NFC slot too.** A sessionless `TKSmartCard.transmit` on the built-in
   NFC slot is parked by ctkd indefinitely: no error, no timeout. With a
   session, the same card answers in about 20 ms.
2. **Never release the NFC slot session while a signature is in
   flight.** CryptoTokenKit deletes a token's keychain items when the
   token goes away, and the slot session's lifetime is the slot's
   lifetime. Releasing it mid-handshake destroys the key the handshake
   needs; TLS fails with `errSSLClosedAbort` (-9858).
3. **Keep diagnostics off the handshake path.** A single bounded probe
   APDU at the head of the sign path is enough to miss the TLS deadline.
4. **Register a token only while its card is live in the slot.**
   `TKSmartCardTokenRegistrationManager.registerSmartCard` accepts a
   driver-created live-slot token; a persistent token injected through a
   driver configuration is rejected.

A cross-process token use also raises a one-time system "Token Access
Request" dialog. Until the user grants it, identity queries block for
roughly 25 seconds and then return `errSecItemNotFound`.

## What is still open

System **Safari** with the card absent is not solved: a registered
token's certificate attributes are visible cold, but the `SecIdentity`
reference is not, because the reference requires a usable private key and
the key requires a live card. Safari enumerates non-interactively, gets
nothing, and never offers the certificate. In-app flows are unaffected --
they hold the card in the field for the whole handshake.

## Automatic transport selection

The physical environment is the preference. A connected reader is used
when the platform offers its slot; otherwise iOS can open the built-in
NFC slot. The app does not expose switches for transports that are either
present or absent independently of those switches.

The token extension makes the same decision from the slot that caused
CryptoTokenKit to invoke it. macOS offers only contact slots; iOS can
offer contact or built-in NFC.

On iOS, a successful connected-reader mint removes every stored ReFineID
NFC prime and persistent ReFineID smart-card registration. Connecting a
reader and inserting a usable card is the holder's global transport
choice within ReFineID, even when the reader card and a previously primed
NFC card have different serials or key profiles. Apple and third-party
identities are untouched. The live reader token is then the sole ReFineID
transport until the holder deliberately mints an NFC identity again.

When several readers contain supported cards, CryptoTokenKit still mints
and keeps one live token for every card. Every live token publishes its
authentication certificate and key. Safari's native client-certificate
sheet selects the identity; ReFineID does not rank the cards or add a
second picker.

Safari renders the signed X.509 subject in that sheet, not the CTK item's
`kSecAttrLabel`. Cards issued to the same subject can therefore appear as
duplicate rows. This is intentional: altering the signed certificate
would make it unusable, while cards issued to different people already
carry distinguishable subjects.
