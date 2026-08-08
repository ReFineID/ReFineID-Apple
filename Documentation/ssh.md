# ssh with the Finnish identity card

The PKCS#11 bridge lets OpenSSH authenticate with the identity card's
basic PIN (PIN1) key -- DVV's terminology for the authentication PIN,
see <https://dvv.fi/en/managing-pin-codes>. The card never reveals the
private key; every login is signed on the card itself.

## Prerequisites

- The ReFineID app installed, so its CryptoTokenKit token extension is
  registered. The bridge reads identities the extension publishes; it
  does no card communication of its own.
- A card reader with the identity card inserted.
- The bridge installed (from a source checkout):

  ```sh
  Scripts/install-pkcs11-macos.sh
  ```

  This installs `/usr/local/lib/librefineid_pkcs11.dylib`, the module
  every ssh command below uses. It exposes only the authentication
  identity. The companion `librefineid_pkcs11_sign.dylib` exposes only
  the qualified-signature identity for document-signing applications;
  it is never used with ssh.

## Getting your public key

```sh
ssh-keygen -D /usr/local/lib/librefineid_pkcs11.dylib
```

This prints one `authorized_keys` line and needs no PIN -- the public
key is public data. The comment identifies the certificate holder and
the card, schematically:

```
ecdsa-sha2-nistp384 AAAA... SURNAME GIVENNAME 99999999A (AB1234567)
```

Append the line to `~/.ssh/authorized_keys` on each server you log in
to. The key type is `ecdsa-sha2-nistp384`; any current sshd accepts
it.

## Logging in

Two ways to use the card; both end with the card signing the login.

### Without an agent

Add to `~/.ssh/config`:

```
Host *
  PKCS11Provider /usr/local/lib/librefineid_pkcs11.dylib
```

Plain `ssh host` then uses the card, and the system PIN dialog appears
when the connection is signed (the token advertises the protected
authentication path, so no PIN is typed into the terminal). The dialog
appears per connection; `ControlMaster` connection reuse avoids
repeats.

### With ssh-agent

```sh
ssh-add -s /usr/local/lib/librefineid_pkcs11.dylib
```

The prompt reads `Enter passphrase for PKCS#11:` -- OpenSSH's fixed
wording; what it means here is the card's basic PIN (PIN1). OpenSSH
refuses an empty PIN for login-required tokens, so the PIN must be
entered at this prompt. Afterwards logins need no further prompts
while the card stays in the reader.

```sh
ssh-add -l                                            # list held keys
ssh-add -e /usr/local/lib/librefineid_pkcs11.dylib    # remove again
```

`ssh-agent` only loads PKCS#11 modules from its allowlist, by default
`/usr/lib*` and `/usr/local/lib*` -- which is why the module lives in
`/usr/local/lib`. A module elsewhere needs the agent started with an
explicit `-P` override.

## Troubleshooting

- **`ssh-keygen -D` lists nothing**: is the card in the reader, and
  does `security list-smartcards` show the token? If the token is
  listed but enumeration is slow (multiples of ten seconds) and
  empty, the token daemon may hold a stale extension handle;
  `killall ctkd` recovers it.
- **`agent refused operation` from `ssh-add`**: an empty PIN was
  entered, or the module path is outside the agent's allowlist.
- **After reinserting the card**: an agent that held the keys before
  removal may need the module removed and added again
  (`ssh-add -e` then `ssh-add -s`).
