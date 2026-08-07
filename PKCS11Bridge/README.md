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

Status: scaffold. The module loads, initializes, reports itself, and
implements the full PKCS#11 v3.2 surface: all 104 entry points exist
(unimplemented ones return `CKR_FUNCTION_NOT_SUPPORTED`, and the
legacy parallel-management pair returns `CKR_FUNCTION_NOT_PARALLEL`,
both as the spec directs). `C_GetInterfaceList`/`C_GetInterface`
publish three "PKCS 11" interfaces -- 3.2, 3.0, and legacy 2.40 -- and
`C_GetFunctionList` serves pre-3.0 consumers (OpenSSH, NSS, older
`SunPKCS11`) with the 2.40 list, whose version field the spec fixes at
2.40. Token enumeration, the object model, and ECDSA signing are the
next milestones; the compatibility ladder is `pkcs11-tool`, then
`ssh`, then `keytool` (`SunPKCS11`), then a PAdES signature from EU
DSS.

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

Specifications (https://docs.oasis-open.org/pkcs11/):

- Spec v3.2 (OASIS Standard, os include files): the implemented ABI.
  `Cryptoki.h` is verified against the official `pkcs11t.h`,
  `pkcs11f.h`, and `pkcs11.h` -- constants, structure layouts, all
  three function-list member orders, and all 104 prototype signatures.
  The legacy 2.40 surface is additionally verified against the v2.40
  errata01/os includes.
- Profiles v3.2: conformance targets. The object model follows the
  Public Certificates Token behavior (certificates readable without
  login, key pairs discoverable through matching `CKA_ID`); Baseline
  Provider conformance additionally needs a `CKO_PROFILE` object,
  tracked in TASKS.md.
- Current Mechanisms v3.0 (pkcs11-curr): normative mechanism
  definitions for the advertised set (CKM_ECDSA family first, RSA
  PKCS#1/PSS after). Note the signature format: CKM_ECDSA returns raw
  r||s, so the bridge converts the X9.62 DER that
  SecKeyCreateSignature produces.
- Historical Mechanisms and Functions v3.0: the do-not-implement
  register; nothing listed there ships in this module.
- Usage Guide v3.2: non-normative companion.
