# PKCS11Bridge

A PKCS#11 v2.40 module (read-and-sign only) implemented on top of
CryptoTokenKit and Security.framework. It never touches the card:
identities come from the keychain's token items and signatures from
`SecKeyCreateSignature`, so the system token daemon and the ReFineID
token extension do all card communication and PIN handling. The module
advertises the protected authentication path, so PIN entry uses the
system dialog.

Why it exists: macOS PKCS#11 consumers -- Java `SunPKCS11`, Firefox/NSS
card login, OpenSSH -- cannot reach CryptoTokenKit tokens. Apple's own
`/usr/lib/ssh-keychain.dylib` covers only RSA identities and only ssh;
current FINEID cards enroll EC P-384 keys by default, for which this
module is the only CTK-based PKCS#11 path.

Status: scaffold. The module loads, initializes, and reports itself,
and every entry point is present in `CK_FUNCTION_LIST` (unimplemented
ones return `CKR_FUNCTION_NOT_SUPPORTED`). Token enumeration, the
object model, and ECDSA signing are the next milestones; the
compatibility ladder is `pkcs11-tool`, then `ssh`, then `keytool`
(`SunPKCS11`), then a PAdES signature from EU DSS.

Why v2.40 and not PKCS#11 3.x: 2.40 is the newest version every target
consumer speaks -- OpenSSH and NSS discover modules via the 2.x
`C_GetFunctionList`, and older `SunPKCS11` releases have no 3.0
support -- while 3.x compliance requires exporting the 2.x entry
points anyway, and the 3.x additions (message-based cryptography,
`C_LoginUser`) do not apply to a read-and-sign token. Moving up later
is additive: export `C_GetInterfaceList`/`C_GetInterface` over the
same function table.

Build and test:

```sh
swift build
swift test
```

The dynamic library lands in `.build/debug/libPKCS11Bridge.dylib`
(`--configuration release` for `.build/release/`). Note for ssh use:
`ssh-agent` only loads PKCS#11 providers from an allowlist (by default
`/usr/lib*` and `/usr/local/lib*`); install accordingly or start the
agent with `ssh-agent -P` naming the module's path.
