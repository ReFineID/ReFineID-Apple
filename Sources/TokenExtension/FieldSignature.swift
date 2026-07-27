import CardCore
import CryptoTokenKit
import Foundation

/// One signature made through the contactless interface, in the order the
/// field allows.
///
/// A contactless card seals its PKCS#15 application until PACE has run,
/// so everything here travels inside the secure-messaging channel PACE
/// yields. What shapes the rest is time: on the system-driven path `ctkd`
/// owns the slot and ends it about two seconds after the token is minted,
/// so this reads nothing the prime already knows, spends no APDU on
/// diagnostics, and writes no log line at all - a single probe APDU at
/// the head of this path was measured costing the whole handshake.
///
/// Provenance: the contactless branch of the donor
/// `platform/apple/RefineIDTokenExtension/TokenSession.swift`, whose
/// transport was a Rust FFI relay; here it is CardCore's own PACE,
/// secure messaging and card operations.
internal struct FieldSignature {
  /// The card, as the session handed it over.
  private let smartCard: TKSmartCard

  /// The token this signature belongs to, and the source of everything
  /// the prime already read: the leaf public key and the card serial.
  private let token: Token

  /// The primed card access number PACE opens the card with.
  private let accessNumber: CardAccessNumber

  internal init(smartCard: TKSmartCard, token: Token, accessNumber: CardAccessNumber) {
    self.smartCard = smartCard
    self.token = token
    self.accessNumber = accessNumber
  }

  /// Whether this failure is the card refusing an approach because an
  /// earlier session left its PACE channel open on it.
  ///
  /// The card answers `SW 6999` until it is met again in a fresh session;
  /// one retry recovers it, measured on hardware, and a second never has.
  private static func refusesStaleChannel(_ error: Error) -> Bool {
    if let failure = error as? PaceEstablishment.Failure,
      case .cardRejected(.staleSecureChannel) = failure
    {
      return true
    }
    if let failure = error as? CardOperationError,
      case .selectRejected(.staleSecureChannel) = failure
    {
      return true
    }
    return false
  }

  /// Establishes the contactless channel and signs `request` in it.
  ///
  /// The PIN is spent exactly once: everything the retry repeats is
  /// idempotent and PIN-free, so a stale-channel refusal cannot cause a
  /// second VERIFY.
  internal func perform(pin1: consuming Pin1, request: SignRequest) throws -> Data {
    // Prefer the session the mint took and kept open. On the
    // system-driven path the slot that minted this token has ended by
    // now, and a fresh beginSession fails with TKError -7 - there is no
    // field left to open, while the retained one still has one. It is
    // released when the slot reports the card missing, and never here.
    let retained = token.heldSession.current
    var opened: SmartCardChannel?
    defer { opened?.endSession() }

    func secureChannel() throws -> SecureMessagingChannel {
      let plain: SmartCardChannel
      if let retained {
        plain = retained
      } else {
        opened?.endSession()
        let fresh = SmartCardChannel(smartCard)
        // Always inside a session: a sessionless transmit on the built-in
        // contactless slot is parked by ctkd forever, with no error and
        // no timeout.
        try fresh.beginSession()
        opened = fresh
        plain = fresh
      }
      let started = ContinuousClock.now
      let keys = try PaceEstablishment(channel: plain).establish(with: accessNumber)
      let secure = SecureMessagingChannel(wrapping: plain, sessionKeys: keys)
      try CardOperations(channel: secure).selectFineidApplication()
      // Recorded, never written: a keychain round trip inside the field
      // is the cost this whole path is shaped to avoid. The exit line of
      // the signature writes this out afterwards.
      TokenLog.trace(
        "pace: channel open retained=\(retained != nil) "
          + "ms=\(TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)))"
      )
      return secure
    }

    let secure: SecureMessagingChannel
    do {
      secure = try secureChannel()
    } catch {
      guard Self.refusesStaleChannel(error) else {
        TokenLog.trace("pace: failed \(error)")
        throw error
      }
      TokenLog.trace("pace: card refused a stale channel, retrying once")
      secure = try secureChannel()
    }
    return try sign(in: secure, pin1: pin1, request: request)
  }

  /// VERIFY PIN1 and the on-card signature, inside the PACE channel.
  ///
  /// Nothing here reads what the prime already knows. The authentication
  /// certificate and the token serial are public, unchanging and stored
  /// by the prime; re-reading either costs more than the field has left,
  /// and that read was measured dying part way through - not re-reading
  /// them is what turned an intermittent signature into a reliable one.
  /// The certificate is present as the token's cached leaf public key,
  /// which checks the signature below; the serial is present as the
  /// cached serial the rejected-PIN memory binds to.
  private func sign(
    in channel: SecureMessagingChannel,
    pin1: consuming Pin1,
    request: SignRequest
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    let fingerprint: PinFingerprint?
    if let serial = token.primedSerial {
      fingerprint = pin1.fingerprint(boundTo: serial)
    } else {
      fingerprint = nil
    }
    if let fingerprint, CredentialMemory.rejectedPins.isKnownRejected(fingerprint) {
      throw TokenError.pinAlreadyRejected
    }
    do {
      try operations.verifyPin1(pin1.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected {
      if let fingerprint {
        CredentialMemory.rejectedPins.recordRejection(fingerprint)
      }
      throw TokenError.pinRejected
    }
    let raw = try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    guard
      let der = EcdsaSignature.derFromRawConcatenation(raw),
      request.isSatisfied(by: der, from: token.leafPublicKey)
    else {
      throw TokenError.signatureMalformed
    }
    return der
  }
}
