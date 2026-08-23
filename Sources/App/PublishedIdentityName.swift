// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)

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
    // MARK: Static Properties

    #if DEBUG
      /// Query outcomes, in development builds only.
      ///
      /// Status codes and counts, never a name or an identifier. A
      /// production build writes no diagnostics.
      private static let log = Logger(
        subsystem: "fi.refineid.ReFineID", category: "identity-name"
      )
    #endif

    /// How many times the lookup queries the keychain before giving up.
    private static let lookupAttempts = 20

    /// How long the lookup waits between attempts.
    private static let lookupInterval: TimeInterval = 0.1

    // MARK: Static Functions

    #if os(macOS)
      /// The holder's name from whichever ReFineID token is published,
      /// or nil when none is.
      ///
      /// Unnamed on macOS, where a token answers from what it published
      /// and a card that is not there matches nothing. iOS asks by name
      /// instead, for the reason in ``name(ofTokenIdentifier:)``.
      internal static func current() -> String? {
        Self.name(ofTokenIdentifier: nil)
      }
    #endif

    /// The holder's name from one named token, or nil when it
    /// publishes none.
    ///
    /// Naming the token is what makes this safe to ask on iOS. A broad
    /// `com.apple.token` search is active there - it was measured
    /// opening a "Ready to Scan" sheet from a screen that only wanted
    /// to count items - because a registered token has to be minted
    /// before it can answer for anything, and minting one over near
    /// field is a card read. A token that is already live has published
    /// its contents and answers from them, so the caller names one it
    /// has proved live rather than asking the keychain at large.
    internal static func name(ofTokenIdentifier tokenIdentifier: String?) -> String? {
      for attempt in 1...lookupAttempts {
        if let name = queryName(ofTokenIdentifier: tokenIdentifier) {
          #if DEBUG
            if attempt > 1 {
              Self.log.info("certificate query succeeded on attempt \(attempt)")
            }
          #endif
          return name
        }
        if attempt < lookupAttempts {
          Thread.sleep(forTimeInterval: lookupInterval)
        }
      }
      return nil
    }

    private static func queryName(ofTokenIdentifier tokenIdentifier: String?) -> String? {
      var query: [CFString: Any] = [
        kSecClass: kSecClassCertificate,
        kSecAttrAccessGroup: kSecAttrAccessGroupToken,
        kSecReturnAttributes: true,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitAll,
      ]
      if let tokenIdentifier {
        query[kSecAttrTokenID] = tokenIdentifier
      }
      var found: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &found)
      guard status == errSecSuccess, let matches = found as? [[CFString: Any]] else {
        #if DEBUG
          Self.log.error("certificate query answered \(status)")
        #endif
        return nil
      }
      #if DEBUG
        Self.log.info("certificate query matched \(matches.count)")
      #endif
      for match in matches {
        guard
          let matchedTokenIdentifier = match[kSecAttrTokenID] as? String,
          Self.owns(tokenIdentifier: matchedTokenIdentifier),
          let der = match[kSecValueData] as? Data,
          let facts = CertificateFacts(der: der),
          !facts.isCertificateAuthority,
          let name = DistinguishedName.holderLine(inName: facts.subjectName)
        else {
          continue
        }
        return name
      }
      return nil
    }

    /// Whether the item belongs to a ReFineID driver, local card or
    /// remote card.
    private static func owns(tokenIdentifier: String) -> Bool {
      CardTokenNamespace.owns(tokenIdentifier: tokenIdentifier)
        || PersistentTokenIdentity.owns(tokenIdentifier: tokenIdentifier)
    }
  }

#endif
