import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One session against a published token.
///
/// Advertises the ECDSA client-authentication shapes the card can sign,
/// prompts for PIN1 through the system UI, and performs a signature in
/// one exclusive card session: retry-floor check, VERIFY PIN1 (consumed
/// once, rejection remembered), MSE:SET + PSO:CDS, then the raw card
/// signature re-encoded as X9.62 DER.
internal final class TokenSession: TKSmartCardTokenSession, TKTokenSessionDelegate {
  /// PIN1 collected by the most recent `beginAuth`, consumed by the next
  /// `sign` and cleared immediately after (one prompt = one signature =
  /// one PIN use).
  private var collectedPin: String?

  // The @objc requirement is throwing; the ObjC bridge rejects a
  // non-throwing override, so `throws` stays though the body cannot fail.
  // swiftlint:disable unneeded_throws_rethrows
  internal func tokenSession(
    _: TKTokenSession,
    beginAuthFor operation: TKTokenOperation,
    constraint _: Any
  ) throws -> TKTokenAuthOperation {
    TokenLog.notice("beginAuth: op=\(operation.rawValue) - presenting PIN sheet")
    return Pin1AuthOperation { [weak self] pin in self?.collectedPin = pin }
  }
  // swiftlint:enable unneeded_throws_rethrows

  internal func tokenSession(
    _: TKTokenSession,
    supports operation: TKTokenOperation,
    keyObjectID _: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) -> Bool {
    guard let token = token as? Token else {
      TokenLog.error("supports: session token is not a ReFineID Token")
      return false
    }
    let supported =
      operation == .signData
      && SigningAlgorithmResolver.advertises(algorithm, profile: token.keyProfile)
    TokenLog.notice(
      "supports: op=\(operation.rawValue) algo=\(SigningAlgorithmResolver.describe(algorithm)) "
        + "profile=\(String(describing: token.keyProfile)) -> \(supported ? "YES" : "NO")"
    )
    return supported
  }

  internal func tokenSession(
    _: TKTokenSession,
    sign dataToSign: Data,
    keyObjectID _: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    TokenLog.notice(
      "sign: called algo=\(SigningAlgorithmResolver.describe(algorithm)) input=\(dataToSign.count)B"
    )
    guard
      let token = token as? Token,
      let request = SigningAlgorithmResolver.resolve(
        algorithm,
        input: dataToSign,
        profile: token.keyProfile
      )
    else {
      TokenLog.error("sign: no matching algorithm - returning badParameter")
      throw TKError(.badParameter)
    }
    // The freshly-entered PIN (from a preceding beginAuth), if any. When
    // nil, performSign may still proceed from the card-bound PIN1 cache;
    // otherwise it throws authenticationRequired and the system prompts.
    let entered = collectedPin.flatMap { $0.isEmpty ? nil : $0 }
    collectedPin = nil

    // getSmartCard() returns the card but not necessarily inside an open
    // session; open one explicitly (the reference does this on every sign),
    // synchronously - no Swift concurrency on the ctkd thread, which hangs.
    let smartCard = try getSmartCard()
    do {
      let signature = try SmartCardChannel(smartCard).withSession { channel in
        try self.performSign(channel: channel, enteredPin: entered, request: request)
      }
      TokenLog.notice("sign: success, \(signature.count) DER bytes")
      return signature
    } catch let error as TokenError {
      TokenLog.error("sign: failed \(error)")
      throw error.asTKError
    } catch let error as CardOperationError {
      // A raw card error (e.g. a signing SW) must not escape unmapped.
      // Fail as a communication error, not authenticationFailed, so a
      // genuine card-sign failure ends the handshake instead of re-looping
      // the PIN prompt (it is not a wrong PIN).
      TokenLog.error("sign: card failed \(error)")
      throw TKError(.communicationError)
    }
  }

  /// The full card sign flow, inside the caller's exclusive session.
  ///
  /// Fully synchronous: CTK calls `sign` on ctkd's own thread and the card
  /// is a blocking device, so the whole chain runs straight through with no
  /// `Task`/`await` (the async bridge hung here). Mirrors the reference.
  private func performSign(
    channel: SmartCardChannel,
    enteredPin: String?,
    request: SignRequest
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    try operations.selectFineidApplication()
    let (serial, pristine) = try probeAndGate(operations)

    // The PIN: freshly entered, or reused from the card-bound cache (only
    // on a pristine card, same serial, within the idle window), or ask the
    // system to prompt.
    let pin1: Pin1
    let fromCache: Bool
    if let entered = enteredPin {
      guard let built = Pin1(digits: entered) else {
        throw TokenError.pinFormatInvalid
      }
      pin1 = built
      fromCache = false
    } else if let cached = CredentialMemory.pin1Cache.checkout(serial: serial, pristine: pristine) {
      TokenLog.info("sign: reusing cached PIN1 - no prompt")
      pin1 = cached
      fromCache = true
    } else {
      throw TokenError.authenticationRequired
    }

    let fingerprint = pin1.fingerprint(boundTo: serial)
    guard !CredentialMemory.rejectedPins.isKnownRejected(fingerprint) else {
      TokenLog.error("sign: PIN already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    }

    TokenLog.info("sign: verifying PIN1")
    do {
      try operations.verifyPin1(pin1.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected {
      CredentialMemory.rejectedPins.recordRejection(fingerprint)
      CredentialMemory.pin1Cache.clear()
      throw TokenError.pinRejected
    }

    TokenLog.info("sign: PIN1 verified; MSE:SET + PSO:HASH + PSO:CDS")
    let raw = try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    guard let der = EcdsaSignature.derFromRawConcatenation(raw) else {
      TokenLog.error("sign: raw signature \(raw.count) bytes not re-encodable")
      throw TokenError.signatureMalformed
    }
    try verifyLocally(der: der, request: request)
    TokenLog.info("sign: local verify OK, \(der.count) DER bytes")
    cacheOnSuccess(pristine: pristine, fromCache: fromCache, enteredPin: enteredPin, serial: serial)
    return der
  }

  /// A fresh probe of all three counters and the card-health gate.
  ///
  /// PIN1, PIN2, and PUK must all be above 2 (else fail closed); returns
  /// the serial and whether the card is pristine (5/5/5).
  private func probeAndGate(
    _ operations: CardOperations
  ) throws -> (serial: TokenSerial, pristine: Bool) {
    TokenLog.info("sign: card-health probe")
    let report = try operations.probeCredentials()
    guard RetryFloor.evaluateAll(report) == .proceed else {
      TokenLog.error("sign: card-health floor refuses - failing closed")
      throw TokenError.signRefused
    }
    return (try operations.readTokenSerial(), report.retryState?.isPristine ?? false)
  }

  /// Caches the just-used PIN for the rest of a login flow, pristine cards
  /// only: refresh the timestamp on a reuse, store on a fresh entry.
  private func cacheOnSuccess(
    pristine: Bool,
    fromCache: Bool,
    enteredPin: String?,
    serial: TokenSerial
  ) {
    guard pristine else { return }
    if fromCache {
      CredentialMemory.pin1Cache.restamp(serial: serial)
    } else if let entered = enteredPin, let cachePin = Pin1(digits: entered) {
      CredentialMemory.pin1Cache.store(cachePin, serial: serial)
    }
  }

  /// Verifies the re-encoded signature against the leaf's public key
  /// before the token hands it to the TLS stack.
  ///
  /// The G4E card can sign silently-wrong bytes if the loaded hash was
  /// lost (S1 v4.2 §3.8.1.1). The exact-`Le` PSO:CDS prevents the known
  /// trigger, but verifying here fails closed on any residual card fault
  /// rather than returning garbage that breaks the handshake opaquely -
  /// and matches the reference implementation's verify-before-return.
  private func verifyLocally(der: Data, request: SignRequest) throws {
    guard let token = token as? Token else {
      throw TokenError.signatureMalformed
    }
    var error: Unmanaged<CFError>?
    let valid = SecKeyVerifySignature(
      token.leafPublicKey,
      request.verifyAlgorithm,
      request.digest as CFData,
      der as CFData,
      &error
    )
    guard valid else {
      TokenLog.error("sign: local verify FAILED - card returned a bad signature")
      throw TokenError.signatureMalformed
    }
  }
}
