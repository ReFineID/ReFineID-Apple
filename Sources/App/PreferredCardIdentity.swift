#if os(macOS)

  import CryptoTokenKit
  import Foundation
  import Security

  /// Tells macOS which identity to offer a site, so Safari stops asking.
  ///
  /// The certificate picker is a consent step: handing a client
  /// certificate to a website reveals who the holder is, permanently, to
  /// that site. macOS lets that consent be given once per site instead of
  /// once per login, through a keychain identity preference, and this is
  /// the only supported way to do it. iOS has no equivalent -- there is
  /// no identity-preference API there at all -- so this is deliberately
  /// macOS only rather than an oversight.
  ///
  /// Nothing here weakens the consent. A preference is set for one named
  /// site at a time, by the holder, and it can be withdrawn. Signing
  /// still needs the card present and PIN1.
  internal enum PreferredCardIdentity {
    /// Why a preference could not be set.
    internal enum Failure: Error {
      /// No card identity is published; the card is absent or unprimed.
      case noIdentity

      /// The keychain refused the preference.
      case refused(OSStatus)
    }

    /// Offers this card automatically to `site` from now on.
    ///
    /// `site` is the URL Safari asks about, for example
    /// `https://admin.iki.fi`. The card must be readable at the moment
    /// this is called, because the preference names a real identity
    /// rather than a description of one.
    internal static func remember(forSite site: String) throws {
      guard let identity = Self.cardIdentity() else { throw Failure.noIdentity }
      let status = SecIdentitySetPreferred(identity, site as CFString, nil)
      guard status == errSecSuccess else { throw Failure.refused(status) }
    }

    /// Whether a card identity is already preferred for `site`.
    internal static func isRemembered(forSite site: String) -> Bool {
      SecIdentityCopyPreferred(site as CFString, nil, nil) != nil
    }

    /// The card identity this app publishes, if one is present.
    ///
    /// Looks only in the token access group: an identity from anywhere
    /// else is not this card and must never be offered as though it
    /// were.
    private static func cardIdentity() -> SecIdentity? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecAttrAccessGroup as String: kSecAttrAccessGroupToken,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnRef as String: true,
      ]
      var result: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
        return nil
      }
      guard CFGetTypeID(result) == SecIdentityGetTypeID() else { return nil }
      return unsafeDowncast(result as AnyObject, to: SecIdentity.self)
    }
  }

#endif
