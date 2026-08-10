#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation
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
  internal enum PublishedIdentityName {
    /// The holder's name from the card, or nil when none is published.
    internal static func current() -> String? {
      for tokenID in TKTokenWatcher().tokenIDs
      where CardTokenNamespace.owns(tokenIdentifier: tokenID) {
        if let name = holderName(tokenID: tokenID) {
          return name
        }
      }
      return nil
    }

    /// The common name on the certificate this token publishes.
    ///
    /// Attributes and references together, unfiltered, then matched
    /// here: filtering the query by `kSecAttrTokenID` returns nothing
    /// for an identity the same query returns when asked for
    /// everything.
    private static func holderName(tokenID: String) -> String? {
      let query: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecAttrAccessGroup: kSecAttrAccessGroupToken,
        kSecReturnRef: true,
        kSecReturnAttributes: true,
        kSecMatchLimit: kSecMatchLimitAll,
      ]
      var found: CFTypeRef?
      guard
        SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
        let matches = found as? [[CFString: Any]]
      else {
        return nil
      }
      for match in matches {
        guard
          match[kSecAttrTokenID] as? String == tokenID,
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
