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
check, and the transport preference hides what the platform cannot do.

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

1. **Prime, once per card.** The app opens an NFC slot, runs PACE with
   the CAN, reads the authentication and issuer certificates, and stores
   them plus the CAN in a keychain item shared with the extension. The
   card is identified by a hash of its ATR.
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

## Transport preference

Users can disable either transport. The preference exists because the two
transports have different costs: a contact reader is faster and needs no
CAN, while NFC needs no hardware but requires holding the card still for
several seconds. Disabling NFC also stops the app from ever prompting for
a CAN.

The preference must be visible to the token extension as well as the app,
since they are separate processes, and it must be inert on macOS, where
only the contact transport exists.
