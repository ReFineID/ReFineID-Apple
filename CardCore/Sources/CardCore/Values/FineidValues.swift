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

  /// The ICAO eMRTD LDS application.
  ///
  /// A Finnish identity card also implements it. Measured on
  /// 2026-08-04 it answers a SELECT on either interface, but every
  /// file inside stays sealed until PACE.
  internal static let travelDocumentAidHexDigits = "A0000002471001"

  /// EF.COM: the list of data groups this card actually carries.
  internal static let fileIdCommonData: UInt16 = 0x011E

  /// EF.DG2: the holder's facial image.
  internal static let fileIdDisplayedPortrait: UInt16 = 0x0102

  /// EF.DG7: the displayed signature or usual mark.
  internal static let fileIdDisplayedSignature: UInt16 = 0x0107

  /// The tag EF.COM uses for its data-group list.
  internal static let dataGroupListTag: UInt8 = 0x5C

  /// The tag DG7 marks the whole displayed-signature template with.
  internal static let displayedSignatureTag: UInt8 = 0x67

  /// The tag DG2 marks the whole facial-image template with.
  internal static let displayedPortraitTag: UInt8 = 0x75

  /// The first byte of the biometric image's two-byte tag, the
  /// high-tag-number form's introducer.
  internal static let biometricTemplateTag: UInt8 = 0x5F

  /// The second byte, which names the image itself.
  internal static let biometricImageTag: UInt8 = 0x43

  /// The data-group list entry standing for DG7.
  internal static let dataGroupSevenMarker: UInt8 = 0x67

  /// The data-group list entry standing for DG2.
  internal static let dataGroupTwoMarker: UInt8 = 0x75

  /// EF.CardAccess: the SecurityInfos a terminal reads BEFORE PACE to
  /// learn which variants the card supports, under the master file
  /// (ICAO 9303-11 section 9.2.11).
  ///
  /// Freely readable by design: the terminal cannot open a secure
  /// channel until the card has said how.
  internal static let fileIdCardAccess: UInt16 = 0x011C

  /// EF.4331: the authentication certificate leaf, directly under the
  /// PKCS#15 application (FINEID S4-1).
  ///
  /// This is the identity Safari uses for client authentication.
  internal static let fileIdAuthCertificate: UInt16 = 0x4331

  /// EF.4332: the qualified-signature certificate leaf, directly under
  /// the PKCS#15 application (FINEID S4-1).
  internal static let fileIdSignatureCertificate: UInt16 = 0x4332

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

  /// Key reference for the PIN2-gated qualified-signature key, private
  /// key #2 on the FINEID S4-1 v3.1 card (S1 v4.2).
  internal static let keyReferenceQualifiedSignature: UInt8 = 0x02

  /// Algorithm-reference hash high-nibble values (S1 v4.2 §3.6.3
  /// Table 6): SHA-224/256/384/512.
  internal static let hashNibbleSha224: UInt8 = 0x3
  internal static let hashNibbleSha256: UInt8 = 0x4
  internal static let hashNibbleSha384: UInt8 = 0x5
  internal static let hashNibbleSha512: UInt8 = 0x6

  /// Algorithm-reference signature low-nibble values (S1 v4.2 §3.6.3
  /// Table 6): RSASSA-PKCS1-v1_5, ECDSA, and RSASSA-PSS.
  internal static let schemeNibbleRsaPkcs1: UInt8 = 0x2
  internal static let schemeNibbleEcdsa: UInt8 = 0x4
  internal static let schemeNibbleRsaPss: UInt8 = 0x5

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

  /// PIN-attributes DO length: four attribute bytes - retries
  /// remaining, usage allowance, unblocking allowance, and the
  /// authentication method (S1 v4.2 §3.15.3 Table 19).
  internal static let pinAttributesLength: UInt8 = 0x04

  /// Usage-allowance byte meaning the credential may be presented
  /// without limit (S1 v4.2 §3.15.3 Table 19).
  internal static let usageUnlimited: UInt8 = 0xFF

  /// Unblocking-allowance byte meaning the credential may be
  /// unblocked without limit.
  ///
  /// A different marker from the usage one, and measured on a card in
  /// hand: a PIN reporting this can be unblocked as often as its
  /// holder needs, which is what makes a PUK reusable rather than
  /// spent by its first use.
  internal static let unblockingUnlimited: UInt8 = 0xA5

  /// PIN-changed DO tag, high byte (`DF 2F`, S1 v4.2 §3.15.3): whether
  /// the PIN has been changed since manufacture, which is how a card
  /// issued from 13 January 2026 reports activation (S4-1 §4.6.2).
  internal static let pinChangedTagHigh: UInt8 = 0xDF

  /// PIN-changed DO tag, low byte.
  internal static let pinChangedTagLow: UInt8 = 0x2F

  /// PIN-changed DO length: one flag byte.
  internal static let pinChangedLength: UInt8 = 0x01

  /// PIN-changed flag value meaning "never changed since manufacture".
  internal static let pinChangedFlagUnchanged: UInt8 = 0x00

  /// PIN-changed flag value meaning "changed at least once".
  internal static let pinChangedFlagChanged: UInt8 = 0x01

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
