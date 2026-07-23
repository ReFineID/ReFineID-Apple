/// A two-byte ISO 7816-4 file identifier.
public struct FileIdentifier: Equatable, Sendable {
  /// EF.ODF: the PKCS#15 object directory under the eID application.
  public static let objectDirectory = Self(
    value: FineidValues.fileIdObjectDirectory
  )

  /// EF.TokenInfo: the PKCS#15 token information file, source of the
  /// full hardware serial.
  public static let tokenInfo = Self(value: FineidValues.fileIdTokenInfo)

  /// The master file (root).
  public static let masterFile = Self(value: FineidValues.fileIdMasterFile)

  /// EF.4331: the authentication certificate leaf.
  public static let authCertificate = Self(
    value: FineidValues.fileIdAuthCertificate
  )

  /// EF.4334: the on-card issuing root CA.
  public static let rootCertificate = Self(
    value: FineidValues.fileIdRootCertificate
  )

  /// EF.4336: the on-card issuing intermediate CA.
  public static let issuingCertificate = Self(
    value: FineidValues.fileIdIssuingCertificate
  )

  /// The identifier as a 16-bit value.
  public let value: UInt16

  /// The two wire bytes, big-endian.
  internal var bytes: [UInt8] {
    [
      UInt8(value >> Iso7816Values.byteShift),
      UInt8(value & Iso7816Values.lowByteMask),
    ]
  }

  /// Any two-byte value is a structurally valid identifier; whether the
  /// file exists is the card's answer, not the type's.
  public init(value: UInt16) {
    self.value = value
  }
}
