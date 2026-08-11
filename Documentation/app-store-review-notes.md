# App Review notes (draft, 2026-08-10)

What goes into App Store Connect's "Notes" field for the macOS
review, and the evidence kept ready for reviewer questions. Reviewers
have no Finnish identity card, so the notes must explain what the app
is, what they can exercise without one, and where the video stands in
for hardware.

## Submitted notes (draft)

ReFineID is a driver and signing app for the Finnish national
identity card (FINEID). It requires physical hardware the review
team is unlikely to have: a FINEID smart card and a USB CCID
smart-card reader, contact or contactless (dual-interface).

What works without the card:

- The app launches to its status window and reports "Insert your
  card" - this is the intended no-hardware state, not an error.
- Settings (time-stamp authorities, with optional HTTP Basic
  credentials) can be inspected.
- The attached video demonstrates the full flow on real hardware:
  card insertion, the identity appearing, Safari certificate login
  to a public Finnish e-service, and signing a dropped PDF with the
  card's qualified certificate.

Technical notes for review:

- The bundled CryptoTokenKit persistent token extension is the
  card driver. It is what makes the card's certificates available
  system-wide (Safari, Mail, other apps), which is the product's
  purpose; the app itself is the status and signing surface.
- A card presented contactlessly asks for its card access number
  (CAN), the six digits printed on the card face - a proximity
  proof required by the card's PACE protocol (FINEID S1), not a
  secret. The app tries an entered number once, then walks the
  holder through presenting the card again; a wrong number shakes
  the entry red. The number is held only while the app runs and
  is never written to disk outside the app group container it
  travels through, where it is deleted at quit.
- The app makes outbound connections for one purpose: an archival
  signature (PAdES-B-LTA) fetches a qualified timestamp and the
  revocation data proving its chain. It binds no listening socket
  and holds no network-server entitlement.
- App Transport Security allows plain HTTP because RFC 3161
  time-stamping and RFC 6960 OCSP are specified over HTTP, and the
  fetched objects are themselves signed and verified by the app;
  the addresses come from the user's settings or from inside
  certificates being validated, so no exception domain list can
  enumerate them.
- No accounts, no login, no data collection. The privacy policy is
  at https://www.refineid.fi/privacy-policy/.
- macOS may offer to pair the inserted card for system login (its
  built-in smart-card pairing). That prompt is the operating
  system's, not the app's; ReFineID does not drive or require it,
  and it can be ignored.

## Evidence held ready

- Hardware demonstration video (to record: full flow, no PIN or
  cardholder data visible; synthetic or redacted where possible).
- Export compliance rationale: `Documentation/export-compliance.md`.
- Sandbox and entitlement rationale: comments in
  `Config/ReFineID.entitlements`.
- ATS rationale: comment in `Config/ReFineID-Info.plist` (the macOS
  plist; the iOS build uses `Config/ReFineID-iOS-Info.plist`, which
  declares no ATS exception because the iOS binary makes no network
  request).

## Open decisions

- Whether to provision a dedicated non-production card and reader
  for the review team (TASKS.md section 12); any review PIN stays
  out of source, issues, logs, and recordings.
