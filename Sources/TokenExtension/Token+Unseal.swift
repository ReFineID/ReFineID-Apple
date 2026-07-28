import CardCore
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
    guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
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
    // nothing changed. Failing fast here is what keeps a wrong stored
    // number from blinking the reader for as long as the card rests on
    // it.
    let fingerprint = CardCredentialStore.cardAccessNumberFingerprint()
    if let fingerprint,
      RefusedUnseal.shared.isRefused(fingerprint: fingerprint, answerToReset: answerToReset)
    {
      TokenLog.info("readIdentity: this number was just refused by this card; not retrying yet")
      throw TokenError.unsealAlreadyRefused
    }
    let started = ContinuousClock.now
    // PACE has to start at master-file level: the card refuses MSE:Set AT
    // with 6985 anywhere else. Best effort, as everywhere else this runs:
    // PACE is the step whose failure should be the one reported.
    try? CardOperations(channel: channel).selectMasterFile()
    let keys: PaceSessionKeys
    do {
      keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
    } catch {
      if let fingerprint {
        RefusedUnseal.shared.record(fingerprint: fingerprint, answerToReset: answerToReset)
      }
      TokenLog.error("readIdentity: PACE failed (\(error)); latched against immediate retry")
      throw error
    }
    RefusedUnseal.shared.clear()
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    TokenLog.info("readIdentity: PACE ok ms=\(Self.elapsed(since: started))")
    let operations = CardOperations(channel: secure)
    try operations.selectFineidApplication()
    return (try Self.certificates(read: operations), accessNumber)
  }

  /// Reads the leaf, and the issuer if the card offers one.
  private static func certificates(
    read operations: CardOperations
  ) throws -> PublishedIdentity {
    TokenLog.info("readIdentity: reading leaf EF.4331")
    let leaf = try operations.readCertificate(.authentication)
    TokenLog.info("readIdentity: leaf \(leaf.count) bytes; reading issuer EF.4336")
    let issuer = try? operations.readCertificate(.issuing)
    TokenLog.info("readIdentity: issuer \(issuer?.count ?? -1) bytes")
    return PublishedIdentity(leafDER: leaf, issuerDER: issuer)
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }
}
