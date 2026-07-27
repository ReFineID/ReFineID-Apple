import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One session against a published token.
///
/// Advertises the ECDSA client-authentication shapes the card can sign,
/// prompts for PIN1 through the system UI, and performs a signature.
///
/// The two transports part company at the first line of `sign`, and
/// deliberately so. The contact path is unchanged: a fresh exclusive
/// session, a retry-floor check, VERIFY PIN1 (consumed once, rejection
/// remembered), MSE:SET + PSO:CDS, and the raw card signature re-encoded
/// as X9.62 DER. The contactless path has none of that room. It runs
/// inside a field that lasts about two seconds after the mint, so it
/// takes the PIN before it touches the card at all, works in the session
/// the mint held open, reads nothing the prime already knows, and logs
/// nothing - a single diagnostic APDU there was measured costing the
/// whole handshake.
///
/// Provenance: the contactless order is the donor
/// `platform/apple/RefineIDTokenExtension/TokenSession.swift`, whose
/// transport was a Rust FFI relay; here it is CardCore's own PACE,
/// secure messaging and card operations.
internal final class TokenSession: TKSmartCardTokenSession, TKTokenSessionDelegate {
  /// PIN1 collected by the most recent `beginAuth`, consumed by the next
  /// `sign` and cleared immediately after (one prompt = one signature =
  /// one PIN use).
  private var collectedPin: String?

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }

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

  /// The signature the system asked for, timed end to end.
  ///
  /// Entry and exit are traced here rather than in the two transport
  /// bodies below, so that every signature costs exactly two lines
  /// whichever way the card was reached, and so that the elapsed time
  /// covers the whole of what Safari waited for. The exchanges in
  /// between arrive from ``SmartCardChannel``.
  internal func tokenSession(
    _: TKTokenSession,
    sign dataToSign: Data,
    keyObjectID _: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    let started = ContinuousClock.now
    TokenLog.notice(
      "sign: entry input=\(dataToSign.count)B "
        + "algo=\(SigningAlgorithmResolver.describe(algorithm))"
    )
    do {
      let signature = try signed(dataToSign: dataToSign, algorithm: algorithm)
      TokenLog.notice(
        "sign: exit ok out=\(signature.count)B ms=\(Self.elapsed(since: started))"
      )
      return signature
    } catch {
      TokenLog.error("sign: exit failed \(error) ms=\(Self.elapsed(since: started))")
      throw error
    }
  }

  /// Routes one signature to the transport the card was reached over.
  private func signed(dataToSign: Data, algorithm: TKTokenKeyAlgorithm) throws -> Data {
    guard let cardToken = token as? Token else {
      throw TKError(.badParameter)
    }
    // The primed card access number IS the transport. With one, this card
    // was reached through a field and every verb below has to travel
    // inside a PACE channel; without one, this is the contact path and
    // nothing about it changes.
    guard let accessNumber = cardToken.primedAccessNumber else {
      TokenLog.trace("sign: transport=reader")
      return try signThroughReader(
        token: cardToken,
        dataToSign: dataToSign,
        algorithm: algorithm
      )
    }
    TokenLog.trace(
      "sign: transport=near-field, held session=\(cardToken.heldSession.current != nil)")
    return try signInField(
      token: cardToken,
      accessNumber: accessNumber,
      dataToSign: dataToSign,
      algorithm: algorithm
    )
  }

  /// The contact signature, in one exclusive session opened here.
  private func signThroughReader(
    token: Token,
    dataToSign: Data,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard
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
        try self.performSign(
          channel: channel,
          enteredPin: entered,
          request: request,
          publicKey: token.leafPublicKey
        )
      }
      TokenLog.trace("sign: reader path produced \(signature.count) DER bytes")
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

  /// The contactless signature, in the order the field allows.
  ///
  /// That order is the whole of it, and no other order works. Nothing on
  /// this path writes: the lines it takes are recorded in memory and
  /// written out by the exit line in ``tokenSession(_:sign:keyObjectID:algorithm:)``,
  /// because a keychain round trip inside the field is exactly the kind
  /// of cost that was measured losing the handshake.
  private func signInField(
    token: Token,
    accessNumber: CardAccessNumber,
    dataToSign: Data,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard
      let request = SigningAlgorithmResolver.resolve(
        algorithm,
        input: dataToSign,
        profile: token.keyProfile
      )
    else {
      throw TKError(.badParameter)
    }
    // The PIN the system collected through beginAuth, or the one the
    // holder authorized earlier through the signing window. The window
    // exists because the system-driven path reaches supports(signData)
    // and then asks for a signature with no interface to ask for a PIN
    // with; without it that signature could never be attempted.
    let entered = collectedPin.flatMap { $0.isEmpty ? nil : $0 }
    collectedPin = nil
    let authorized: Pin1?
    if let entered {
      authorized = Pin1(digits: entered)
    } else {
      authorized = Pin1SigningWindow.pin1()
    }
    // Which of the two supplied the PIN is the first thing a failed
    // contactless login needs to know, and it is sayable without saying
    // anything about the PIN itself.
    TokenLog.trace(
      "sign: pin1 source=\(entered != nil ? "prompt" : "window") authorized=\(authorized != nil)"
    )
    // Ask for the PIN BEFORE touching the card. A contactless token never
    // reuses the card-bound PIN1 cache, so a signature with no PIN can
    // only end in this throw - and reaching it after PACE leaves the card
    // mid-secure-channel, where the next PACE attempt dies on SELECT with
    // SW 6999.
    guard let pin1 = authorized else {
      throw TKError(.authenticationNeeded)
    }
    do {
      let signature = FieldSignature(
        smartCard: try getSmartCard(),
        token: token,
        accessNumber: accessNumber
      )
      return try signature.perform(pin1: pin1, request: request)
    } catch let error as TokenError {
      throw error.asTKError
    } catch let error as TKError {
      throw error
    } catch {
      // A PACE refusal, a secure-messaging fault or a signing SW must not
      // escape unmapped, and must not look like a wrong PIN: a genuine
      // card failure ends the handshake instead of re-looping the prompt.
      throw TKError(.communicationError)
    }
  }

  /// The full contact sign flow, inside the caller's exclusive session.
  ///
  /// Fully synchronous: CTK calls `sign` on ctkd's own thread and the card
  /// is a blocking device, so the whole chain runs straight through with no
  /// `Task`/`await` (the async bridge hung here). Mirrors the reference.
  private func performSign(
    channel: SmartCardChannel,
    enteredPin: String?,
    request: SignRequest,
    publicKey: SecKey
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
    guard request.isSatisfied(by: der, from: publicKey) else {
      TokenLog.error("sign: local verify FAILED - card returned a bad signature")
      throw TokenError.signatureMalformed
    }
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
}
