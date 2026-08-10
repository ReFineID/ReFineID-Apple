#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation
  import os.log
  import Security

  /// Who the card in the reader says they are.
  ///
  /// The holder needs to know whose identity is about to sign, and
  /// someone carrying two cards needs to see which one is in the
  /// reader before spending a PIN on it.
  ///
  /// Read from the certificate the token publishes, never stored: the
  /// name belongs to the card, and the moment the card leaves there is
  /// nothing to show.
  ///
  /// Never called from the main actor. Reaching the certificate reaches
  /// the token, and a card that is slow to answer would otherwise be a
  /// window that will not open.
  internal enum PublishedIdentityName {
    /// The holder's name from the card, or nil when none is published.
    ///
    /// Read straight from the token access group: every published
    /// identity carries its token identifier, so the keychain answer
    /// is also the token listing. A token watcher would say the same
    /// thing, but a freshly created watcher answers empty until it has
    /// connected to the token daemon, and this read must be right the
    /// first time the window asks - a card already in the reader at
    /// launch shows its holder at once.
    /// Query outcomes, visible in the unified log for field reports.
    /// Status codes and counts only; never a name or an identifier.
    private static let log = Logger(
      subsystem: "fi.refineid.ReFineID", category: "identity-name"
    )

    internal static func current() -> String? {
      Self.log.info("read requested")
      let query: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecAttrAccessGroup: kSecAttrAccessGroupToken,
        kSecReturnRef: true,
        kSecReturnAttributes: true,
        kSecMatchLimit: kSecMatchLimitAll,
      ]
      var found: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &found)
      guard status == errSecSuccess, let matches = found as? [[CFString: Any]] else {
        Self.log.error("identity query answered \(status)")
        return nil
      }
      Self.log.info("identity query matched \(matches.count)")
      for match in matches {
        guard
          let tokenID = match[kSecAttrTokenID] as? String,
          CardTokenNamespace.owns(tokenIdentifier: tokenID),
          let untyped = match[kSecValueRef],
          CFGetTypeID(untyped as CFTypeRef) == SecIdentityGetTypeID()
        else {
          continue
        }
        let identity = unsafeDowncast(untyped as AnyObject, to: SecIdentity.self)
        var certificate: SecCertificate?
        guard
          SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
          let certificate
        else {
          continue
        }
        if let name = SecCertificateCopySubjectSummary(certificate) as String? {
          return name
        }
      }
      return nil
    }
  }

#endif
