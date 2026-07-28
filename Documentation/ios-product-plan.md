# iOS product plan: ReFineID for iPhone (lead product)

Status: accepted direction, 2026-07-23

## 1. What the product is

An iOS app that makes a Finnish identity card usable.

1. Attach a USB-C smart-card reader, insert the card.
2. See card, reader, and PIN1/PIN2/PUK retry status, side-effect-free.
3. Log into Finnish services **in Safari** with the card's
   authentication certificate through the system client-cert flow.

v1 is exactly that and nothing more.

## 2. Minimal pure-Swift Safari driver

The is pure Swift and absolutely minimal - the smallest CTK
smart-card driver that makes Safari login work.

What the driver contains (the whole protocol surface of v1):

- card recognition and named application/file selection (SELECT AID);
- bounded certificate and chain reads with response continuation;
- side-effect-free retry-state reads;
- the retry floor (three or more attempts proceeds, one or two refuses
  before any prompt, unreadable state fails closed);
- PIN1 `VERIFY` with at-most-once transport and rejected-PIN memory;
- `MSE:SET` + `PSO:CDS` signing and ECDSA/RSA result normalization;
- token publication through the CTK extension.

No PACE, no secure messaging, no TLS, no X.509 parsing - the contact
path does not need the first two, and the platform provides the rest.
Minimality is the security argument: the driver stays reviewable.

The Rust core remains the reference oracle.

## 4. Features and conventions

- Calendar versioning `YY.M.D` with ten-minute-bucket build numbers;
  tagged releases.
- Safety invariants: the retry floor (proceed only at three or more
  attempts), pristine-only PIN1 caching, at-most-once credential
  transport, wrong-PIN rejection memory - identical policy on every
  platform, and the implementation already demonstrated the
  rejection memory and 5/5 preservation in hardware runs.

## 6. Future

- **NFC-for-Safari is proven on iPhone.** iOS 26 provides the full path:
  `createNFCSlot`, `TKSmartCardTokenRegistrationManager`, and
  system-summoned NFC on demand. The app first reads and stages the public
  identity metadata in a Core NFC field, then opens a CryptoTokenKit field
  that mints and registers `refineid-card-<printed-card-serial>`. Later
  Safari client-certificate requests summon a fresh CryptoTokenKit NFC
  field; the extension retains that card session, establishes PACE, checks
  PIN1, and signs. This two-field setup avoids the app and extension racing
  separate PACE exchanges against one card.
