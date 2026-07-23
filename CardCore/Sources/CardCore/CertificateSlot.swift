/// A certificate the card publishes, and where it lives.
///
/// Reads only the authentication identity and its issuer chain.
/// The qualified-signature slots (EF.4332/EF.4335) are out of
/// scope for now. Directory placement follows FINEID S4-2 §3.
public enum CertificateSlot: Equatable, Sendable, CaseIterable {
  /// EF.4331, directly under the PKCS#15 application: the client
  /// authentication leaf Safari uses.
  case authentication

  /// EF.4336, under the master file: the issuing intermediate CA that
  /// chains the leaf upward.
  case issuing

  /// EF.4334, under the master file: the on-card root CA.
  case root

  /// The elementary file holding this certificate.
  public var file: FileIdentifier {
    switch self {
    case .authentication:
      .authCertificate
    case .issuing:
      .issuingCertificate
    case .root:
      .rootCertificate
    }
  }

  /// Where the file lives, which decides the SELECT navigation.
  public var directory: CertificateDirectory {
    switch self {
    case .authentication:
      .pkcs15Application
    case .issuing, .root:
      .masterFile
    }
  }
}
