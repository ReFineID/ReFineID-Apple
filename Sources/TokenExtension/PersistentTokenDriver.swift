// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  @_spi(TokenExtension) import CardCore
  import CryptoTokenKit
  import Foundation
  import Security

  /// Generic persistent-token principal selected by the macOS extension
  /// plist. The iOS build continues to select the existing smart-card driver.
  internal final class PersistentTokenDriver: TKTokenDriver,
    TKTokenDriverDelegate
  {
    override internal init() {
      super.init()
      delegate = self
    }

    internal func tokenDriver(
      _: TKTokenDriver,
      tokenFor configuration: TKToken.Configuration
    ) throws -> TKToken {
      try PersistentToken(tokenDriver: self, configuration: configuration)
    }
  }

  private final class PersistentToken: TKToken, TKTokenDelegate {
    fileprivate let certificate: SecCertificate
    fileprivate let publicKey: SecKey
    fileprivate let profile: CardKeyProfile

    fileprivate init(
      tokenDriver: TKTokenDriver,
      configuration: TKToken.Configuration
    ) throws {
      let item = try configuration.certificate(
        for: PersistentTokenIdentity.certificateObjectID
      )
      guard
        let certificate = SecCertificateCreateWithData(nil, item.data as CFData),
        let publicKey = SecCertificateCopyKey(certificate),
        let profile = CardKeyProfile.resolve(fromPublicKey: publicKey)
      else {
        throw TKError(.corruptedData)
      }
      self.certificate = certificate
      self.publicKey = publicKey
      self.profile = profile
      super.init(tokenDriver: tokenDriver, instanceID: configuration.instanceID)
      delegate = self
    }

    fileprivate func createSession(_: TKToken) throws -> TKTokenSession {
      PersistentTokenSession(token: self)
    }
  }

  private final class PersistentTokenSession: TKTokenSession,
    TKTokenSessionDelegate
  {
    private var persistentToken: PersistentToken {
      token as! PersistentToken
    }

    override fileprivate init(token: TKToken) {
      super.init(token: token)
      delegate = self
    }

    fileprivate func tokenSession(
      _: TKTokenSession,
      supports operation: TKTokenOperation,
      keyObjectID: Any,
      algorithm: TKTokenKeyAlgorithm
    ) -> Bool {
      operation == .signData
        && (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID
        && SigningAlgorithmResolver.advertises(
          algorithm,
          profile: persistentToken.profile
        )
    }

    fileprivate func tokenSession(
      _: TKTokenSession,
      sign dataToSign: Data,
      keyObjectID: Any,
      algorithm: TKTokenKeyAlgorithm
    ) throws -> Data {
      guard
        (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID,
        let request = SigningAlgorithmResolver.resolve(
          algorithm,
          input: dataToSign,
          profile: persistentToken.profile
        ),
        let relayAlgorithm = PersistentRelaySigningAlgorithm(request.algorithm)
      else {
        throw TKError(.notImplemented)
      }

      let id = UUID()
      let response: PersistentRelayMessage
      do {
        response = try PersistentRelayClient(displayName: "ReFineID Token")
          .perform(
            .signatureRequest(
              id: id,
              profile: PersistentRelayCardProfile(persistentToken.profile),
              algorithm: relayAlgorithm,
              digest: request.digest
            )
          )
      } catch {
        throw TKError(.communicationError)
      }

      guard case .signatureResponse(id, let signature) = response else {
        throw TKError(.communicationError)
      }
      guard request.isSatisfied(by: signature, from: persistentToken.publicKey) else {
        throw TKError(.corruptedData)
      }
      return signature
    }
  }
#endif
