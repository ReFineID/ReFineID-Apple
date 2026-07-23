/// The directory a certificate file lives under, which the reader must
/// make current before selecting the file (FINEID S4-2 §3).
public enum CertificateDirectory: Equatable, Sendable {
  /// Directly under the master file.
  case masterFile

  /// Directly under the PKCS#15 application DF (already current after
  /// selecting the eID application).
  case pkcs15Application
}
