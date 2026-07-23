/// The dedicated home for FINEID-specific wire values.
///
/// Sources: FINEID S1 v4.2 (VERIFY, PIN references), FINEID S4-1 v3.1
/// (stored PIN length), and the DVV application note "iOS NFC" v1.0
/// (application identifiers). Values are cross-checked against the Rust
/// reference implementation. No raw hex literal may appear outside this
/// directory (`.swiftlint.yml` `unexplained_hex`).
internal enum FineidValues {
  /// IAS application AID, "PKCS-15" - the eID application on every
  /// supported card (DVV iOS NFC note; ASCII `A0 00 00 00 63` prefix
  /// plus "PKCS-15").
  internal static let applicationAidHexDigits = "A000000063504B43532D3135"

  /// PIN1 reference for VERIFY P2: global PIN (S1 v4.2 §3.5.2).
  internal static let pin1Reference: UInt8 = 0x11

  /// PIN2 reference for VERIFY P2: local PIN (S1 v4.2 §3.5.2).
  internal static let pin2Reference: UInt8 = 0x82

  /// PUK reference (PKCS#15 numbering, reference implementation).
  internal static let pukReference: UInt8 = 0x83

  /// Stored PIN block length: entered digits are right-padded to this
  /// many bytes (S4-1 v3.1).
  internal static let pinStoredLength: Int = 12

  /// The padding byte for the PIN block.
  ///
  /// FINEID cards reject any non-zero padding.
  internal static let pinPadByte: UInt8 = 0x00

  /// EF.ODF: the PKCS#15 object directory file under the eID DF.
  internal static let fileIdObjectDirectory: UInt16 = 0x5031

  /// EF.TokenInfo: the PKCS#15 token information file (carries the full
  /// hardware serial).
  internal static let fileIdTokenInfo: UInt16 = 0x5032

  /// The master file (root) selected before reaching MF-level EFs
  /// (ISO 7816-4).
  internal static let fileIdMasterFile: UInt16 = 0x3F00

  /// EF.4331: the authentication certificate leaf, directly under the
  /// PKCS#15 application (FINEID S4-2 §3).
  ///
  /// This is the identity Safari uses for client authentication.
  internal static let fileIdAuthCertificate: UInt16 = 0x4331

  /// EF.4334: the on-card issuing root CA, under the master file.
  internal static let fileIdRootCertificate: UInt16 = 0x4334

  /// EF.4336: the on-card issuing intermediate CA (DVV Citizen
  /// Certificates G4E), under the master file - the certificate that
  /// chains the auth leaf toward the root.
  internal static let fileIdIssuingCertificate: UInt16 = 0x4336

  /// CRDO tag for the algorithm reference inside MSE:SET data
  /// (S1 v4.2 §3.6.3).
  internal static let crdoAlgorithmReferenceTag: UInt8 = 0x80

  /// CRDO tag for the key reference inside MSE:SET data (S1 v4.2 §3.6.3).
  internal static let crdoKeyReferenceTag: UInt8 = 0x84

  /// CRDO value length: ReFineID emits one-byte algorithm and key
  /// references.
  internal static let crdoValueLength: UInt8 = 0x01

  /// Key reference for the PIN1-gated authentication key (S1 v4.2).
  internal static let keyReferenceAuthentication: UInt8 = 0x01

  /// Algorithm-reference hash high-nibble values (S1 v4.2 §3.6.3
  /// Table 6): SHA-224/256/384/512.
  internal static let hashNibbleSha224: UInt8 = 0x3
  internal static let hashNibbleSha256: UInt8 = 0x4
  internal static let hashNibbleSha384: UInt8 = 0x5
  internal static let hashNibbleSha512: UInt8 = 0x6

  /// Algorithm-reference signature low-nibble values (S1 v4.2 §3.6.3
  /// Table 6): RSASSA-PKCS1-v1_5 and ECDSA.
  internal static let schemeNibbleRsaPkcs1: UInt8 = 0x2
  internal static let schemeNibbleEcdsa: UInt8 = 0x4

  /// GET DATA P1 for the PIN-container query (S1 v4.2 §3.15.2).
  internal static let pinContainerP1: UInt8 = 0x00

  /// GET DATA P2 for the PIN-container query (S1 v4.2 §3.15.2).
  internal static let pinContainerP2: UInt8 = 0xFF

  /// Lc of the PIN-container query: the five-byte constructed template.
  internal static let pinContainerRequestLength: UInt8 = 0x05

  /// PIN-container request template tag (constructed, `A0`).
  internal static let pinContainerTemplateTag: UInt8 = 0xA0

  /// PIN-container request template length (three bytes follow).
  internal static let pinContainerTemplateLength: UInt8 = 0x03

  /// PIN-reference tag inside the template (`83`).
  internal static let pinReferenceTag: UInt8 = 0x83

  /// PIN-reference length inside the template (one byte).
  internal static let pinReferenceLength: UInt8 = 0x01

  /// PIN-attributes DO tag, high byte (`DF 21`, §3.15.3 Table 19).
  internal static let pinAttributesTagHigh: UInt8 = 0xDF

  /// PIN-attributes DO tag, low byte.
  internal static let pinAttributesTagLow: UInt8 = 0x21

  /// PIN-attributes DO length: four attribute bytes, the first of
  /// which is the retries-remaining counter.
  internal static let pinAttributesLength: UInt8 = 0x04

  /// The VERIFY P2 reference for a credential role.
  internal static func reference(for role: CredentialRole) -> UInt8 {
    switch role {
    case .pin1:
      pin1Reference
    case .pin2:
      pin2Reference
    case .puk:
      pukReference
    }
  }
}
