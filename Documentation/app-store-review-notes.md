# App Review notes

What goes into App Store Connect's "Notes" field for the macOS
review, and the evidence kept ready for reviewer questions. Reviewers
have no Finnish identity card, so the notes must explain what the app
is and what they can exercise without one.

## What the first submission taught

The iOS submission of 26.8.12 (135) was rejected under guideline
2.1(a), Information Needed, on 2026-08-12. The reply asked for a demo
account or a demonstration mode and said in terms that a video of the
app in use is not sufficient.

The notes at the time offered exactly that video, so the offer is
removed. What replaced it says the two things the guideline turns on:
there is no account to supply because the app has none, and the
hardware is a legal identity document issued to one citizen, which
cannot be duplicated or lent. The notes then list what does run
without a card, and ask whether a demonstration mode is the expected
remedy.

Beta App Review approved the same binary on both platforms the same
day. The rejection is about reviewer access, not about the build.

## Where the notes live

`Metadata/appstore.json`, under `review.notes`, and they reach App
Store Connect with
`Scripts/apple-app-store-connect-release-manager.swift review-contact
<ios|macos> <version>`. They were duplicated here once and the copy
went stale, so the text is not repeated: read it there.

## Evidence held ready

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
