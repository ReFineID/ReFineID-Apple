// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Publishes one token's signed identity to Safari.
extension Token {
  /// Label naming the PIN1 authentication identity.
  ///
  /// Both card certificates carry the identical subject, so a chooser
  /// showing only subjects shows two rows that read the same. The label
  /// is the one publishable field that can tell them apart, and Safari's
  /// chooser appends the subject to it on its own - so the label holds
  /// nothing but the role, in DVV's wording for the PIN it will ask for,
  /// resolved against the system language when the token is minted.
  private static var authenticationLabel: String {
    String(localized: "Basic (PIN1)")
  }

  /// Label naming the PIN2 qualified-signature identity.
  private static var signatureLabel: String {
    String(localized: "Signature (PIN2)")
  }

  #if os(macOS)
    /// The qualified-signature certificate and key as keychain items,
    /// macOS only.
    ///
    /// The key is sign-only and NOT suitable for login: it is the
    /// non-repudiation key, gated behind PIN2 through its own constraint,
    /// and every signature costs a fresh PIN2 entry - the session never
    /// caches one. Failure to build these is not failure to publish the
    /// token: the authentication identity stands on its own.
    ///
    /// Every consumer of this keychain entry is a Mac one: the PKCS#11
    /// sign module and document-signing applications, which reach the
    /// key through `SecKeyCreateSignature`. On iOS the only reader of
    /// published identities is Safari's client-certificate chooser,
    /// which matches candidates on issuer and titles rows with the
    /// subject - the card's two certificates share both - while the
    /// non-repudiation key completes no TLS handshake. Published there,
    /// this identity is a second identical row that can only ask for
    /// PIN2 and fail, so it is not published there at all.
    private static func qualifiedItems(
      leaf: SecCertificate,
      profile: CardKeyProfile
    ) -> [TKTokenKeychainItem] {
      guard
        let certificate = TKTokenKeychainCertificate(
          certificate: leaf,
          objectID: Self.signObjectID
        ),
        let key = TKTokenKeychainKey(
          certificate: leaf,
          objectID: Self.signObjectID
        )
      else {
        TokenLog.error("publish: qualified keychain item construction failed")
        return []
      }
      key.keyType = profile.keyType
      key.keySizeInBits = profile.keySizeInBits
      key.canSign = true
      key.canDecrypt = false
      key.canPerformKeyExchange = false
      key.isSuitableForLogin = false
      // swiftlint:disable:next legacy_objc_type
      let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
      key.constraints = [signOperationKey: Pin2AuthOperation.signDataConstraint]
      certificate.label = Self.signatureLabel
      key.label = Self.signatureLabel
      return [certificate, key]
    }
  #endif

  /// Builds and fills the keychain contents from the read identity.
  internal func publish(
    _ identity: PublishedIdentity,
    leaf: SecCertificate,
    profile: CardKeyProfile,
    signLeaf: SecCertificate?,
    signProfile: CardKeyProfile?
  ) throws {
    guard
      let keychainCertificate = TKTokenKeychainCertificate(
        certificate: leaf,
        objectID: Self.authObjectID
      ),
      let keychainKey = TKTokenKeychainKey(
        certificate: leaf,
        objectID: Self.authObjectID
      )
    else {
      TokenLog.error("publish: keychain item construction failed")
      throw TokenError.keychainItemConstructionFailed
    }

    keychainKey.keyType = profile.keyType
    keychainKey.keySizeInBits = profile.keySizeInBits
    keychainKey.canSign = true
    keychainKey.canDecrypt = false
    keychainKey.canPerformKeyExchange = false
    // Apple's flag means login to the system, not TLS client authentication.
    // macOS uses it for native smart-card pairing. The iPhone product does
    // not provide system login; Safari selects this identity from its signed
    // certificate and sign-capable key instead.
    #if os(macOS)
      keychainKey.isSuitableForLogin = true
    #else
      keychainKey.isSuitableForLogin = false
    #endif
    // The signature is gated behind PIN1: this constraint is what makes
    // CryptoTokenKit call beginAuth (the PIN sheet) before signing. Absent
    // it, the system signs without asking, our sign has no PIN, and Safari
    // fails with the identity selected but no prompt. The constraints map
    // requires NSNumber operation keys (the CryptoTokenKit ObjC API).
    // swiftlint:disable:next legacy_objc_type
    let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
    keychainKey.constraints = [signOperationKey: Pin1AuthOperation.signDataConstraint]
    keychainCertificate.label = Self.authenticationLabel
    keychainKey.label = Self.authenticationLabel

    var items: [TKTokenKeychainItem] = [keychainCertificate, keychainKey]
    #if os(macOS)
      if let signLeaf, let signProfile {
        items.append(contentsOf: Self.qualifiedItems(leaf: signLeaf, profile: signProfile))
      }
    #endif
    if let issuerDER = identity.issuerDER,
      let issuer = SecCertificateCreateWithData(nil, issuerDER as CFData),
      let issuerItem = TKTokenKeychainCertificate(
        certificate: issuer,
        objectID: Self.issuerObjectID
      )
    {
      items.append(issuerItem)
    }
    TokenLog.info(
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil) "
        + "publicKeyData=\(keychainKey.publicKeyData?.count ?? -1)B "
        + "publicKeyHash=\(keychainKey.publicKeyHash?.count ?? -1)B "
        + "constraints=\(keychainKey.constraints?.count ?? 0)"
    )
    keychainContents?.fill(with: items)
  }
}
