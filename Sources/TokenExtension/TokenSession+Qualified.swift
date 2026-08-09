import CardCore
import CryptoTokenKit
import Foundation

/// The qualified-signature route: split from the session for length,
/// and because it shares nothing with the PIN1 paths but the
/// transport.
extension TokenSession {
  /// The qualified signature, reader interfaces only.
  ///
  /// A deadline field has no room for the probe-verify-sign chain and
  /// no qualified key is ever published from a prime, so reaching this
  /// with one is a system inconsistency answered with tokenNotFound.
  internal func qualifiedThroughReader(
    token: Token,
    dataToSign: Data,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard
      let profile = token.signKeyProfile,
      let signPublicKey = token.signLeafPublicKey,
      token.interface != .fieldWithDeadline
    else {
      throw TKError(.tokenNotFound)
    }
    guard
      let request = SigningAlgorithmResolver.resolve(
        algorithm,
        input: dataToSign,
        profile: profile
      )
    else {
      TokenLog.error("sign: no matching qualified algorithm - returning badParameter")
      throw TKError(.badParameter)
    }
    let entered = collectedPin2.flatMap { $0.isEmpty ? nil : $0 }
    TokenLog.info(
      "sign: qualified entry pin2Collected=\(entered != nil) "
        + "session=\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"
    )
    collectedPin2 = nil
    let smartCard = try getSmartCard()
    do {
      let signature = try SmartCardChannel(smartCard, waits: .reader).withSession { channel in
        try QualifiedSignature.perform(
          in: channel,
          unsealingWith: token.sealedAccessNumber,
          enteredPin: entered,
          request: request,
          signPublicKey: signPublicKey
        )
      }
      TokenLog.trace("sign: qualified path produced \(signature.count) DER bytes")
      return signature
    } catch let error as TokenError {
      TokenLog.error("sign: qualified failed \(error)")
      throw error.asTKError
    } catch let error as CardOperationError {
      TokenLog.error("sign: qualified card failed \(error)")
      throw TKError(.communicationError)
    }
  }
}
