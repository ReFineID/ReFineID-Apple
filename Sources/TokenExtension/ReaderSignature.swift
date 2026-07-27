import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One signature taken through a reader, contact or contactless.
///
/// The counterpart of ``FieldSignature``, and the difference between
/// them is time rather than secrecy. Both may run inside a PACE channel;
/// only this one can afford to look at the card first. A reader holds
/// its field for as long as the work takes, so a signature here reads
/// the serial and the three attempt counters before it does anything
/// irreversible -- which is what lets a PIN be reused for the rest of a
/// login flow instead of asked for once per signature.
///
/// A card held against a phone gets none of that: the system ends the
/// slot about two seconds after the mint, so ``FieldSignature`` asks for
/// the PIN before touching the card and reads nothing it was not
/// already given.
internal enum ReaderSignature {
  /// Unseals the channel if the card asks for it, then signs in it.
  internal static func perform(
    in channel: SmartCardChannel,
    unsealingWith accessNumber: CardAccessNumber?,
    enteredPin: String?,
    request: SignRequest,
    publicKey: SecKey
  ) throws -> Data {
    try performSign(
      channel: try unsealed(channel, with: accessNumber),
      unsealed: accessNumber != nil,
      enteredPin: enteredPin,
      request: request,
      publicKey: publicKey
    )
  }

  /// The channel to work in: the plain one for a contact card, or a
  /// secure-messaging one for a card on an antenna.
  ///
  /// PACE has to start at master-file level -- the card refuses MSE:Set
  /// AT with 6985 anywhere else -- and the select is best effort, as
  /// everywhere else this runs: PACE is the step whose failure is worth
  /// reporting.
  private static func unsealed(
    _ channel: SmartCardChannel,
    with accessNumber: CardAccessNumber?
  ) throws -> any CardChannel {
    guard let accessNumber else { return channel }
    let started = ContinuousClock.now
    try? CardOperations(channel: channel).selectMasterFile()
    let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
    TokenLog.info(
      "sign: PACE ok ms="
        + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    )
    return SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
  }

  /// The PIN to spend: freshly entered, or reused from the card-bound
  /// cache, or none -- in which case the system is asked to prompt.
  ///
  /// The cache serves only a pristine card, the same serial, and an
  /// entry inside the idle window; anything else asks the holder again.
  private static func pin(
    entered: String?,
    serial: TokenSerial,
    pristine: Bool
  ) throws -> Pin1 {
    if let entered {
      guard let built = Pin1(digits: entered) else {
        throw TokenError.pinFormatInvalid
      }
      return built
    }
    guard
      let cached = CredentialMemory.pin1Cache.checkout(serial: serial, pristine: pristine)
    else {
      throw TokenError.authenticationRequired
    }
    TokenLog.info("sign: reusing cached PIN1 - no prompt")
    return cached
  }

  /// The full contact sign flow, inside the caller's exclusive session.
  ///
  /// Fully synchronous: CTK calls `sign` on ctkd's own thread and the card
  /// is a blocking device, so the whole chain runs straight through with no
  /// `Task`/`await` (the async bridge hung here). Mirrors the reference.
  private static func performSign(
    channel: any CardChannel,
    unsealed: Bool,
    enteredPin: String?,
    request: SignRequest,
    publicKey: SecKey
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    try operations.selectFineidApplication()
    let (serial, pristine) = try Self.probeAndGate(operations, overSecureChannel: unsealed)

    // Where the PIN came from is not a second answer to be returned:
    // reaching this line without one entered means the cache supplied it.
    let fromCache = enteredPin == nil
    let pin1 = try Self.pin(entered: enteredPin, serial: serial, pristine: pristine)

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
    Self.cacheOnSuccess(
      pristine: pristine,
      fromCache: fromCache,
      enteredPin: enteredPin,
      serial: serial
    )
    return der
  }

  /// A fresh probe of all three counters and the card-health gate.
  ///
  /// PIN1, PIN2, and PUK must all be above 2 (else fail closed); returns
  /// the serial and whether the card is pristine (5/5/5).
  private static func probeAndGate(
    _ operations: CardOperations,
    overSecureChannel: Bool
  ) throws -> (serial: TokenSerial, pristine: Bool) {
    TokenLog.info("sign: card-health probe")
    // Over a secure channel the PUK counter is not asked for at all: the
    // card refuses it and ends the channel doing so.
    let report = try operations.probeCredentials(includingPuk: !overSecureChannel)
    // Over a secure channel the card may decline a counter outright,
    // which is not the same as a counter that is low. See
    // `RetryFloor.evaluateReported`.
    let verdict =
      overSecureChannel
      ? RetryFloor.evaluateReported(report) : RetryFloor.evaluateAll(report)
    guard verdict == .proceed else {
      // Which counter, and what it said. A refusal names one of two very
      // different faults -- a card genuinely close to blocking, or a
      // reading that did not come back -- and they want opposite
      // responses. Attempt counts are not secrets; the status screen
      // shows the same three.
      TokenLog.error(
        "sign: card-health floor refuses (\(verdict)) - failing closed; "
          + "pin1=\(report.pin1) pin2=\(report.pin2) puk=\(report.puk)"
      )
      throw TokenError.signRefused
    }
    return (try operations.readTokenSerial(), report.reportedCountersArePristine)
  }

  /// Caches the just-used PIN for the rest of a login flow, pristine cards
  /// only: refresh the timestamp on a reuse, store on a fresh entry.
  private static func cacheOnSuccess(
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
