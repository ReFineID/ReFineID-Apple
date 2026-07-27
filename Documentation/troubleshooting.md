# When the card reads but nothing offers it

Faults whose symptoms impersonate other faults. Each one here cost an
evening at least once, and each is recognisable in a single log line
once you know what to look for.

## The system holds an old copy of the driver

**Symptom.** The app reads the card perfectly -- name, counters, card
type -- but no identity is published, `security list-smartcards` says
`No smartcards found`, and Safari offers nothing. Sites that worked an
hour ago fail, and they fail differently from each other, which invites
theories about TLS versions, readers and server configuration.

**Cause.** Replacing `ReFineIDTokenExtension.appex` while `ctkd` is
running leaves PlugInKit holding the previous copy. `ctkd` says so:

    Token driver extension fi.refineid.ReFineID.ctk failed to start:
      Error Domain=PlugInKit Code=16 "other version in use", useCount = 1
    [CryptoTokenKit:slotwtch] No token driver found for card <TKSmartCardATR ...>

**Why `killall ctkd` does not fix it.** macOS runs more than one `ctkd`,
and the instance holding the slot watcher may belong to another user
account -- `afwd` on the development Mac, running since the previous
login. A kill from your own shell cannot touch it. Only a reboot or a
logout clears the state.

**Confirmed 2026-07-27.** After an evening of the appex being replaced
about fifteen times, four sites -- card.refineid.fi, admin.iki.fi,
suomi.fi and posti.fi -- all failed in different ways. A reboot restored
every one of them at once, with no code change. In that same evening the
driver signed 28 of 28 requests correctly, TLS 1.2 and TLS 1.3 alike.

**What to do.** During development, do not hot-swap the extension under a
running `ctkd` and then believe a failed login. Quit the app, install,
and reboot or log out before any test whose result you intend to trust.
When a card reads fine but publishes nothing, check for the PlugInKit
line above before looking at the wire or the server:

    log show --predicate 'process == "ctkd"' --last 10m --style compact \
      | grep -iE "no token driver|failed to start|other version"

## The system asks about a card only when it arrives

**Symptom.** A card access number is entered while the card is already in
the reader, and nothing happens. The status screen still says no identity
is available.

**Cause.** `ctkd` offers a card to a driver when the card *arrives*. A
card that was already present when the driver refused it -- because the
access number was not yet stored -- is never asked about again, and no
call from inside a sandbox makes the system look a second time.

**What to do.** Remove the card and put it back. The status screen says
this itself when it sees a readable card, stored credentials, and no
published identity.

## The app was taking the card away from Safari

**Fixed on 2026-07-27, recorded because the symptom was so misleading.**
The status screen's refresh dropped "stale" token configurations, which
included the configuration the system keeps for the *live* token -- so
opening the app unregistered the working card and then reported it
missing. Any login attempted after looking at the app failed. See the
commit "Stop the status screen unregistering the card it reports on".

## Sites ask for the certificate in different ways

Not a fault, but the reason results differ between sites with one card:

- **suomi.fi** asks during the initial handshake (TLS 1.2).
- **admin.iki.fi** asks by renegotiating after the page loads (TLS 1.2).
  If the renegotiation does not happen there is no prompt and no
  signature -- nothing reaches the driver to fail.
- **card.refineid.fi** and Telia certap are TLS 1.3, where the request is
  `ecdsa_secp384r1_sha384` and the signed content is 130 bytes: 64 bytes
  of padding, the 33-byte context string, a separator, and the transcript
  hash. A `sign: entry input=130B algo=msgX962SHA384` line in the driver
  log is a TLS 1.3 CertificateVerify and nothing else.
- **oma.posti.fi** authenticates through a single-use SAML conversation;
  a correct signature is not sufficient there by itself.

When a login fails, the first question is not which site or which reader,
but whether the driver was asked at all:

    log show --predicate 'subsystem == "fi.refineid.ReFineID"' --last 5m \
      --style compact | grep -E "supports:|sign: entry|sign: exit"

Asked and failed is ours. Never asked is not.
