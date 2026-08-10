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
smart-card reader.

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
- The app listens on 127.0.0.1:53952 (loopback only). This is the
  Signature Creation Service interface specified by the Finnish
  Digital and Population Data Services Agency (DVV, specification
  v1.3); Finnish e-services call it from the browser to request
  card signatures. It serves one request per connection and never
  binds a non-loopback interface - the sandbox's network-server
  entitlement exists for this.
- App Transport Security allows plain HTTP because RFC 3161
  time-stamping and RFC 6960 OCSP are specified over HTTP, and the
  fetched objects are themselves signed and verified by the app;
  the addresses come from the user's settings or from inside
  certificates being validated, so no exception domain list can
  enumerate them.
- No accounts, no login, no data collection. The privacy policy is
  at https://www.refineid.fi/privacy-policy/.

## Evidence held ready

- Hardware demonstration video (to record: full flow, no PIN or
  cardholder data visible; synthetic or redacted where possible).
- Export compliance rationale: `Documentation/export-compliance.md`.
- Sandbox and entitlement rationale: comments in
  `Config/ReFineID.entitlements`.
- ATS rationale: comment in `Config/ReFineID-Info.plist`.

## Open decisions

- Whether to provision a dedicated non-production card and reader
  for the review team (TASKS.md section 12); any review PIN stays
  out of source, issues, logs, and recordings.
