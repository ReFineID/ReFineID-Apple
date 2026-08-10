#if os(macOS)

  import CardCore
  import Foundation
  import os.log
  import Security

  /// Who the card in the reader says they are.
  ///
  /// The holder needs to know whose identity is about to sign, and
  /// someone carrying two cards needs to see which one is in the
  /// reader before spending a PIN on it.
  ///
  /// Read as stored certificate bytes - attributes and data only. The
  /// items are published with their contents, so the answer comes from
  /// the keychain's own store in milliseconds without waking the token
  /// behind them. Materializing identity references instead asks ctkd,
  /// and through it the extension and the card; that path has been
  /// observed hanging for tens of seconds and answering empty while
  /// Safari was using the very same identity.
  internal enum PublishedIdentityName {
    /// Query outcomes, visible in the unified log for field reports.
    ///
    /// Status codes and counts only; never a name or an identifier.
    private static let log = Logger(
      subsystem: "fi.refineid.ReFineID", category: "identity-name"
    )

    /// The holder's name from the card, or nil when none is published.
    internal static func current() -> String? {
      let query: [CFString: Any] = [
        kSecClass: kSecClassCertificate,
        kSecAttrAccessGroup: kSecAttrAccessGroupToken,
        kSecReturnAttributes: true,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitAll,
      ]
      var found: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &found)
      guard status == errSecSuccess, let matches = found as? [[CFString: Any]] else {
        Self.log.error("certificate query answered \(status)")
        return nil
      }
      Self.log.info("certificate query matched \(matches.count)")
      for match in matches {
        guard
          let tokenID = match[kSecAttrTokenID] as? String,
          CardTokenNamespace.owns(tokenIdentifier: tokenID),
          let der = match[kSecValueData] as? Data,
          let facts = CertificateFacts(der: der),
          !facts.isCertificateAuthority,
          let certificate = SecCertificateCreateWithData(nil, der as CFData),
          let name = SecCertificateCopySubjectSummary(certificate) as String?
        else {
          continue
        }
        return name
      }
      return nil
    }
  }

#endif
