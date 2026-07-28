import CardCore
import CryptoKit
import CryptoTokenKit
import Foundation

/// The card read behind a reader-slot mint: SELECT, unseal when the
/// card asks to be, and the certificate pair.
///
/// Split from `Token` for length alone; this is the half that talks to
/// the card before a token exists.
extension Token {
  /// Reads the leaf and (best-effort) issuer certificates in one
  /// exclusive card session, unsealing the card first if it asks to be.
  ///
  /// The card is asked rather than assumed. A slot name says which
  /// reader answered, not which interface of it the card is on: this
  /// reader publishes its contact, contactless and SAM interfaces under
  /// one name that differs only by a trailing index, and nothing in the
  /// name says which index is the antenna. What does distinguish them is
  /// the card's own answer -- a contactless FINEID card refuses SELECT of
  /// the PKCS#15 application with `6982` until PACE has run, and a
  /// contact one simply selects it -- so the answer is the
  /// classification, and it costs one command to get.
  ///
  /// Only that one status word takes the second path. Any other failure
  /// is reported as itself, because a card that is missing, mute or
  /// something else entirely is not a card that wants a card access
  /// number, and running PACE at it would replace a legible fault with a
  /// wrong one.
  internal static func readIdentity(
    from smartCard: TKSmartCard
  ) throws -> (identity: PublishedIdentity, accessNumber: CardAccessNumber?) {
    TokenLog.info("readIdentity: opening session")
    let answerToReset = smartCard.slot.atr?.bytes
    return try SmartCardChannel(smartCard, waits: .reader).withSession { channel in
      do {
        TokenLog.info("readIdentity: selecting application")
        try CardOperations(channel: channel).selectFineidApplication()
      } catch CardOperationError.selectRejected(.securityNotSatisfied) {
        TokenLog.info("readIdentity: application is sealed; unsealing")
        return try Self.unsealed(over: channel, answerToReset: answerToReset)
      }
      return (try Self.certificates(read: CardOperations(channel: channel)), nil)
    }
  }

  /// Runs PACE over an already-open channel and reads through it.
  ///
  /// This is the priming flow the app runs on the phone, in the
  /// extension and without the deadline. A reader powers the card
  /// continuously, so there is no field to lose and nothing to store
  /// ahead of time: the certificate is read live, exactly as the contact
  /// path reads it, and the identity is published from what the card
  /// just said.
  ///
  /// The card access number is the one the holder entered. Absent, this
  /// stops here with a typed refusal -- a sealed card and no number is
  /// setup that has not been done, not a fault to keep retrying at.
  private static func unsealed(
    over channel: SmartCardChannel,
    answerToReset: Data?
  ) throws -> (identity: PublishedIdentity, accessNumber: CardAccessNumber?) {
    // The directory's model-matched numbers first, newest first; the
    // single unbound number last. A sealed card is anonymous before
    // PACE, so the model is the only filter there is -- and between
    // card models it is a complete one.
    let modelKey = answerToReset.flatMap { AnswerToReset(bytes: $0)?.modelKey }
    var candidates = modelKey.map(CardDirectory.candidates(forModelKey:)) ?? []
    if let single = CardCredentialStore.cardAccessNumber() {
      candidates.append(single)
    }
    guard !candidates.isEmpty else {
      // The status separates the two faults that look identical here:
      // nothing stored is setup not done, while a refusal is this
      // process being unable to read what the app wrote.
      TokenLog.error(
        "readIdentity: card is sealed and no card access number is readable "
          + "(status=\(CardCredentialStore.cardAccessNumberReadStatus()))"
      )
      throw TokenError.primeMissing
    }
    // The latch, before any card time is spent: a failed PACE tears the
    // field, the card re-arrives, and the system asks again with
    // nothing changed. Editing the directory changes the fingerprint,
    // which is what earns the card a fresh attempt.
    let fingerprint = Self.candidateFingerprint(modelKey: modelKey)
    if let fingerprint,
      RefusedUnseal.shared.isRefused(fingerprint: fingerprint, answerToReset: answerToReset)
    {
      TokenLog.info("readIdentity: these numbers were just refused by this card; not retrying yet")
      throw TokenError.unsealAlreadyRefused
    }
    let started = ContinuousClock.now
    var lastFailure: any Error = TokenError.primeMissing
    for (index, accessNumber) in candidates.enumerated() {
      // PACE has to start at master-file level: the card refuses
      // MSE:Set AT with 6985 anywhere else. Best effort: PACE is the
      // step whose failure should be the one reported.
      try? CardOperations(channel: channel).selectMasterFile()
      do {
        let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
        RefusedUnseal.shared.clear()
        let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
        TokenLog.info(
          "readIdentity: PACE ok, candidate \(index + 1)/\(candidates.count) "
            + "ms=\(Self.elapsed(since: started))")
        let operations = CardOperations(channel: secure)
        try operations.selectFineidApplication()
        return (try Self.certificates(read: operations), accessNumber)
      } catch let failure as PaceEstablishment.Failure {
        TokenLog.error(
          "readIdentity: candidate \(index + 1)/\(candidates.count) refused (\(failure))")
        lastFailure = failure
      } catch {
        // A transport death is not a refusal of this number: the card
        // stopped answering, and trying more numbers at a mute card
        // only spends the reader. Latch and report.
        if let fingerprint {
          RefusedUnseal.shared.record(fingerprint: fingerprint, answerToReset: answerToReset)
        }
        TokenLog.error("readIdentity: transport failed (\(error)); latched against immediate retry")
        throw error
      }
    }
    if let fingerprint {
      RefusedUnseal.shared.record(fingerprint: fingerprint, answerToReset: answerToReset)
    }
    TokenLog.error("readIdentity: every number refused; latched against immediate retry")
    throw lastFailure
  }

  /// One digest over everything the loop would try, or nil when there
  /// is nothing to try.
  private static func candidateFingerprint(modelKey: String?) -> Data? {
    let directory = modelKey.flatMap(CardDirectory.candidatesFingerprint(forModelKey:))
    let single = CardCredentialStore.cardAccessNumberFingerprint()
    if let directory, let single {
      return Data(SHA256.hash(data: directory + single))
    }
    return directory ?? single
  }

  /// Reads the leaf, serial, and the issuer if the card offers one.
  ///
  /// The serial is read before the issuer because the leaf read leaves the
  /// PKCS#15 application selected, while the issuer read navigates to the
  /// master file.
  private static func certificates(
    read operations: CardOperations
  ) throws -> PublishedIdentity {
    TokenLog.info("readIdentity: reading leaf EF.4331")
    let leaf = try operations.readCertificate(.authentication)
    TokenLog.info("readIdentity: leaf \(leaf.count) bytes; reading token serial")
    let serial = try operations.readTokenSerial()
    TokenLog.info("readIdentity: token serial read; resolving issuer")
    let issuer =
      BundledIssuerCertificate.der(matching: leaf)
      ?? (try? operations.readCertificate(.issuing))
    TokenLog.info("readIdentity: issuer \(issuer?.count ?? -1) bytes")
    return PublishedIdentity(leafDER: leaf, issuerDER: issuer, tokenSerial: serial)
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }
}
