// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Generic persistent-token principal selected by the extension plist.
///
/// The direct smart-card driver remains a separate extension on every
/// platform; this driver owns only the delegated persistent identity.
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

  /// The @objc delegate requirement fixes the throwing signature even
  /// though this implementation cannot fail.
  // swiftlint:disable:next unneeded_throws_rethrows
  fileprivate func createSession(_: TKToken) throws -> TKTokenSession {
    PersistentTokenSession(token: self)
  }
}

private final class PersistentTokenSession: TKTokenSession,
  TKTokenSessionDelegate
{
  /// The requesting surface named on the authorizer's approval sheet.
  private static var displayContext: String {
    #if os(macOS)
      "macOS CryptoTokenKit"
    #else
      "iOS CryptoTokenKit"
    #endif
  }

  private let persistentToken: PersistentToken

  fileprivate init(token: PersistentToken) {
    persistentToken = token
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
      )
    else {
      throw TKError(.notImplemented)
    }

    guard
      let relayAlgorithm = RappOperationDriver.SignatureAlgorithm(
        request.algorithm
      )
    else {
      throw TKError(.notImplemented)
    }
    #if DEBUG
      let vault = RappDeviceVault()
      ExtensionTrace.record(
        "rapp vault: active=\(((try? vault.activePairIDs()) ?? []).count)"
          + " selected=\((try? vault.selectedPairID()) != nil)")
    #endif
    let signature: Data
    do {
      let response = try RappPersistentRequesterClient(
        displayName: "ReFineID Token"
      ).perform(
        .browserAuthentication(
          displayContext: Self.displayContext,
          keyProfile: RappOperationDriver.KeyProfile(persistentToken.profile),
          algorithm: relayAlgorithm,
          digest: request.digest
        )
      )
      guard case .signature(let receivedSignature) = response else {
        throw RappRequesterClientError.unexpectedResult
      }
      signature = receivedSignature
    } catch {
      // CryptoTokenKit carries one code back to the caller, so the reason
      // the relay gave is lost at this boundary. It is the only account of
      // why a browser was refused an identity, so it is recorded before
      // the throw narrows it to a communication failure.
      #if DEBUG
        ExtensionTrace.record("rapp sign failed: \(String(describing: error))")
        ExtensionTrace.flush()
      #endif
      throw TKError(.communicationError)
    }
    guard request.isSatisfied(by: signature, from: persistentToken.publicKey) else {
      throw TKError(.corruptedData)
    }
    return signature
  }
}
