# Status, 26.7.27

What works, what does not, and what each was measured with. Written from
device and Mac runs on 2026-07-27, not from intent.

## macOS: card login works, on both interfaces

Safari signs in with the card through a reader, driven entirely by this
app and its token extension -- with the card in the contact slot, and
with the card resting on a reader's contactless antenna. The second was
proven on 2026-07-27 against an ACR1581U, whose PICC interface the card
answers over T=CL:

    slots (3):
      ACS ACR1581 1S Dual Reader(1)
          state=valid card
          atr=3B 8F 80 01 80 31 B8 65 B0 85 05 10 24 12 24 60 82 90 00 22
    createSession: session requested, interface=contactless
    sign: exit ok out=103B ms=1012.7

A contactless signature costs about a second, nearly all of it the PACE
handshake that opens the secure channel; a contact one costs about a
third of that and needs no handshake at all. Measured across `admin.iki.fi` and
`card.refineid.fi`, several signatures each:

    supports: op=2 algo=msgX962SHA256 profile=ecdsaP384 -> YES
    sign: entry input=11782B
    sign: PIN1 verified; MSE:SET + PSO:HASH + PSO:CDS
    sign: local verify OK, 102 DER bytes
    sign: exit ok out=102B ms=343.8

Each signature is verified locally against the card's own public key
before it is handed back, so a wrong answer is caught here rather than by
the far end. PIN1 is asked for once and reused from the in-memory cache
for the following signatures (`reusing cached PIN1 - no prompt`), which
is what makes several sites in a row bearable.

Setup on macOS is nothing more than inserting the card: the extension
reads the leaf and issuer over the reader and publishes them.

## How the driver knows which interface it is on

It asks the card rather than reading the slot's name. A dual-interface
reader publishes its contact, contactless and SAM interfaces under one
name differing only by a trailing index, and nothing in the name says
which index is the antenna -- while the card answers the question
itself: SELECT of the PKCS#15 application returns `6982` on the
contactless interface until PACE has run, and succeeds on the contact
one. One command, and no guessing.

Taking "the first slot" instead was a bug in three places at once: the
status screen described the empty SAM socket beside the card, and a
probe reported "no reader or card" about a card that was signing for
Safari at the time. `CardSlotSearch` is now the one implementation.

## Handing the card access number to the driver on macOS

The two processes cannot share a keychain item there. An item carries an
access list naming the application that created it, and a token
extension is a different application: it finds the item and is refused
the value with `errSecInteractionNotAllowed` (-25308), which it cannot
resolve, because a driver hosted by `ctkd` has no interface to authorize
with. A shared keychain access group is the right answer and is what iOS
uses, but it is a restricted entitlement and the local signing profile
will not carry it.

CryptoTokenKit's own token configuration is the channel instead, which
its header documents for exactly this: data that the token
implementation and its hosting application both use, that the system
does not interpret, with access credentials as the stated example. Only
the hosting application can write it and every other caller is handed an
empty store, so the driver's own app bundle is the boundary.

It costs one oddity worth knowing: every token configuration is listed
as a token, so this entry appears in `TKTokenWatcher` beside real cards.
It holds no keychain items and so offers Safari nothing, but anything
asking "is a card available?" must exclude it by name or it answers yes
with no card present.

## The discovery extension is iOS-only

It declares the travel-document application identifier so the phone's
NFC polling has something selectable before PACE. On macOS a reader
hands the card over without one, and the extension there could only
claim a card in order to refuse it, so it is no longer embedded in the
Mac app.

## iOS: setup works, the login is unproven

Priming works end to end on the phone, over the phone's own NFC antenna,
in pure Swift:

    Card found -> Opening a secure channel -> Reading the certificate
    -> Card read -> Card details stored -> Card registered for Safari
    stored: true   registered: true

That exercises the ported PACE stack, secure messaging and the
certificate read against a real card. What has NOT yet been demonstrated
on this app is a completed Safari signature over NFC. The reference
implementation does it, and the same three rules are carried here, but
carrying a rule is not the same as having watched it hold.

## The rules the NFC path must not break

Each cost a measured failure to learn, and each looks like a platform
limitation when broken.

1. **Hold the card session taken during `createToken` and reuse it in the
   signature.** `ctkd` owns the NFC slot and ends it about two seconds
   after the mint, so a fresh session in the signature finds nothing and
   fails with `TKError -7`.
2. **Release that session only when the slot is genuinely `missing`.**
   Releasing on any other state tore down a signature part way through a
   read.
3. **Never read from the card what the prime already holds.** The
   certificate and the token serial are public and unchanging; re-reading
   either costs more than the field has left.

Two more, learned the same way: a sessionless `TKSmartCard.transmit` on
the built-in NFC slot is parked by `ctkd` forever, and `createToken` on
that slot must do no card I/O at all.

## Why there are two token extensions

`ctkd` polls for NFC cards using the select-identifier set an *extension*
declares. A driver that declares none gives it nothing to select, so the
card is never surfaced and the system's scan sheet waits forever.
Declaring the identifier on the driver that mints the token breaks the
other half: `ctkd` then stops invoking that driver even for the app's own
slot, nothing is minted, and registration fails on a token that does not
exist.

So the roles are split. `ReFineIDTokenExtension` mints and holds the
registration and declares no identifier; `ReFineIDDiscoveryExtension`
declares the eMRTD identifier and refuses to create tokens. The
identifier is the travel-document application, which a Finnish identity
card genuinely implements and which is selectable before PACE -- unlike
PKCS#15, which answers `SW=6982` until the secure channel exists.

## Secrets on the device

The card access number and PIN1 are stored as keychain items that are
`WhenUnlockedThisDeviceOnly` and non-synchronizable, so neither is
written into a backup, restored onto another device, or sent to iCloud.
Neither attribute implies the other; both are set.

Neither is behind a biometric access control at present. PIN1 was
briefly, and it is worth recording why it is not now: the token extension
has no interface to answer a prompt with while signing a request made in
Safari, so a gated value cannot serve the flow this app exists for.
Gating it also broke storage outright, because a protected item survives
a delete that skips the authentication interface and the add that follows
fails as a duplicate. The gate can return once the flow it must not block
is proven.

PIN1 additionally travels through a signing window that closes after
fifteen idle minutes, sliding on each use, so an abandoned phone stops
being able to sign without anyone doing anything.

## Instruments

Every fix on 2026-07-27 came from an instrument rather than from
reasoning about the code, including the two that made priming work at
all. They are worth keeping.

- **In-app diagnostics** (Status -> Diagnostics): registered tokens,
  watcher tokens, driver configurations, prime presence, signing-window
  idle time, transport preference, keychain counts, and the extension
  trace, with share and copy.
- **Extension trace**: a rolling keychain buffer both extensions write
  and the app reads. On iOS 26 `log stream --device` is gone and
  `log collect` fails, so this is the only way to see inside an
  extension. Sizes, instruction bytes, status words and timings only --
  never a PIN, CAN, serial or holder name, and `VERIFY` is redacted
  wholesale.
- **DEBUG-only launch modes**: `--diagnostics`, `--trace`,
  `--reset-card-state`, `--set-can`, `--set-pin1`,
  `--open-signing-window`, `--prime`. Absent from a Release build,
  verified by grepping the built binary.
- **macOS logging still works**, unlike iOS: `log show --predicate
  'subsystem == "fi.refineid.ReFineID"'` shows the extension directly.

## Known rough edges

- The certificate picker cannot be preselected on iOS. `SecIdentitySetPreferred`
  is macOS only, and the picker is a consent step rather than
  disambiguation: handing over a client certificate reveals the holder's
  identity to that site permanently. macOS can now remember a site
  through the card-details screen.
- On iOS the picker and the NFC sheet are both system UI and can overlap,
  with the picker drawing behind the sheet. Their stacking is not ours to
  set; a shorter signature is the only lever.
- On macOS the app and its extensions share no keychain access group, so
  the app cannot show the extensions' trace there. macOS logging covers
  it; on iOS the shared group is present and the trace works.
- Stale registrations from old build locations produce duplicate
  identities in the picker, one of which cannot sign. Deregister with
  `pluginkit -r` and re-insert the card so `ctkd` re-enumerates.
