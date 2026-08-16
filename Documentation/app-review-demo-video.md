# App Review demo video, 26.8.16 (114)

What App Review asked for on 2026-08-16, what to film, and the exact text
to send back. Submission `48f4b685-f48a-4a48-9c4b-d2478e42e586`, reviewed
on an iPad Air 11-inch (M3).

## What was asked

Guideline 2.1, Information Needed. Not a rejection of the build: a
request for evidence. App Review wants one video that shows

- the current version of the app running on a physical Apple device,
  not a simulator;
- the initial pairing between the app and the designated hardware;
- the entire app workflow with that hardware, including every NFC
  interaction;
- both the hardware and the Apple device in the same frame.

The link goes in App Review Information, and the Resolution Center
message is then answered.

## Why it arrived now

The previous rejection (26.8.12, 2.1(a), 2026-08-12) asked for a demo
account or a demonstration mode and said a video was not sufficient.
That was about reviewer access to the app, and it was answered with the
Virtual ID Card demonstration mode. This request is a different thing:
evidence that the hardware interaction exists. Demonstration mode cannot
supply it, because it deliberately touches no card.

The review device explains the emphasis. An iPad has no NFC antenna, so
on an iPad the app can never open a scan sheet. A reviewer holding only
an iPad cannot see the NFC path at any setting, and nothing in the app
can change that. The video is the only way to show it.

## Proving the version on camera

The shipping build displays no version anywhere: `BundledVersions` is
read only by the Debug diagnostics screen, and the TestFlight and
Release configurations exclude those sources. Do not add a version label
for the video - that means a new build, and the video would then show a
build that is not the one under review.

Film the proof instead. Open TestFlight, show the ReFineID entry reading
`26.8.16 (114)`, and launch the app from that screen without cutting.
The internal tester group has access to every build, so 114 installs
there without any distribution step.

## Shot list

One continuous take is best; cuts are acceptable at the marked points.
Landscape, 1080p or better, three minutes or less. Narrate or caption in
English. Keep the card and the phone screen in frame together whenever
the card is being read.

1. **Version.** TestFlight showing `ReFineID 26.8.16 (114)`, then open
   the app from there.
2. **The hardware.** Hold up the identity card, masked as below, and say
   what it is: a Finnish identity card issued by the Police, whose
   certificates are issued by the Digital and Population Data Services
   Agency. It is a contactless smart card under ISO/IEC 14443, read over
   the phone's NFC antenna.
3. **Initial pairing.** The card setup flow: entering the card access
   number printed on the card, then presenting the card to the top of
   the phone. Show the system scan sheet appearing, the card being read,
   and the screen reporting that the card is registered for Safari. This
   is the pairing App Review asked to see; the app has no other pairing
   step.
4. **Workflow, authentication.** Open Safari, go to a Finnish public
   e-service that asks for a certificate, choose the ReFineID identity,
   present the card again when the system asks, enter PIN 1 off camera,
   and show the service reporting a completed sign-in.
5. **Workflow, signing.** Back in the app, pick a PDF, sign it with
   PIN 2 entered off camera, and show the finished signed document.
6. **The reader alternative, filmed on iPad.** Switch devices for the
   last minute: connect a USB-C smart-card reader to the iPad, insert
   the card, and show the same identity signing in. Filming this part on
   the iPad answers the review device in its own terms - the hardware
   the reviewer held has no NFC antenna, and this is what it does
   instead.

## Sanitization, not optional

`TASKS.md` requires a credential-free video, and the repository rules
forbid publishing PINs, PUKs, full serials, and personal identifiers.
Before filming:

- Cover the printed fields on both faces of the card: photograph, name,
  personal identity code, card number, card access number, signature,
  and the machine-readable zone. Leave the card shape and the issuer
  design visible so it is recognizable as the hardware.
- Never film the card access number being typed. Cover the field, cut,
  or film the entry from behind the phone.
- Never film PIN 1, PIN 2, or a PUK being typed, and keep the keypad out
  of frame while a credential is entered. The fields are masked on
  screen; fingers on a keypad are not.
- Blur the electronic client identifier (SATU) wherever a screen shows
  it. The holder name may stay: it is already public as the developer of
  record.
- Retain no unsanitized master file. If the raw take contains anything
  above, the raw take is deleted after the sanitized export.

## Hosting

The link must open without a login, from anywhere, and stay up while the
version is in review. `refineid.fi` is preferable to a video platform
because the file stays under our control and carries no recommendations
or comments beside it. An unlisted upload is acceptable if it needs no
account to view.

Record the exact URL in the release record for 26.8.16.

## Text to add to App Review Information

Append to `review.notes.ios` in `Metadata/appstore.json`, then push it
with the release manager's `review-contact` command. Fill the URL first;
do not push a placeholder.

```text
NFC AND THE DEMONSTRATION VIDEO

This app uses NFC. The designated hardware is the Finnish identity card
itself: a contactless smart card under ISO/IEC 14443, read over the
iPhone's NFC antenna through CryptoTokenKit. It is not an NDEF tag and
carries no writable payload; the app opens a PACE secure channel to it
and reads a certificate.

Demonstration video, no login required: <URL>

Filmed on a physical iPhone running exactly this build, 26.8.16 (114),
the video shows the version in TestFlight, the initial setup with the
card over NFC, a completed sign-in to a Finnish public e-service in
Safari, a signed PDF, and the same card working through a USB-C reader.
Printed card fields and personal identifiers are masked, and no card
access number, PIN, or PUK is visible at any point.

One note on review devices: iPad has no NFC antenna, so the NFC path
cannot run on the iPad Air used for the previous review. On iPad the
same card is used through a USB-C smart-card reader, which the video
also shows.
```

## Resolution Center reply

Send after the link is live and the notes are pushed.

```text
Thank you for the guidance, and for naming the review device - that
detail explains what could not be reproduced.

Yes, the app includes NFC functionality. The designated hardware is a
Finnish identity card: a contactless smart card under ISO/IEC 14443,
read over the iPhone's NFC antenna. It is not an NDEF tag. The app
establishes a PACE secure channel with the card and reads the
certificate the operating system then offers to Safari.

A demonstration video is now linked in App Review Information. It is
filmed on a physical iPhone running build 26.8.16 (114), the build under
review, and shows the version in TestFlight, the initial setup with the
card over NFC including the system scan sheet, a completed
certificate-based sign-in to a Finnish public e-service in Safari, a
signed PDF, and the same card used through a USB-C smart-card reader.
The card and the phone are in frame together throughout.

The review was performed on an iPad Air 11-inch (M3). iPad has no NFC
antenna, so the NFC path cannot execute there in hardware; on iPad the
card is used through a USB-C reader instead. That is why the video is
filmed on iPhone.

There is no demo account to supply: the app has no login, no server, and
no registration. The identity card is a legal identity document issued
to one citizen and cannot be duplicated or issued for testing, which is
why the build also carries the Virtual ID Card demonstration mode
described in the review notes. That mode exercises the app's screens
without a card; the video covers what only physical hardware can show.
```

## After approval of this step

The macOS submission of the same version is independent and unaffected;
it was still awaiting review when this arrived. Keep the video linked
for later versions: the requirement recurs whenever hardware interaction
cannot be reproduced by a reviewer.
