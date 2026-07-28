import CardCore
import CryptoTokenKit
import Foundation

/// CryptoTokenKit entry point. `com.apple.ctk.driver-class` in
/// Config/TokenExtension-Info.plist names this class; the system
/// instantiates it when a smart card is inserted and asks the delegate to
/// create a token.
///
/// The two transports are minted differently, and the slot name is the
/// only thing there is to tell them apart before any card I/O. A contact
/// slot is read: the token reads the card's authentication certificate
/// and publishes the identity. A contactless slot is NOT read - it is
/// materialized from what the app stored while priming the card, because
/// that interface answers nothing before PACE and the system owns the
/// slot for barely two seconds. A card without the FINEID application,
/// without a readable auth certificate, without a prime, or with an
/// unsupported key profile is refused with a typed error - refusal is
/// safe: the system treats the card as not handled by this driver.
///
/// Provenance: the slot classification and the primed mint are the donor
/// `platform/apple/RefineIDTokenExtension/TokenDriver.swift`, whose
/// contactless branch was proven on device.
internal final class TokenDriver: TKSmartCardTokenDriver, TKSmartCardTokenDriverDelegate {
  /// What the system calls the phone's own contactless slot.
  ///
  /// `TKSmartCardSlotManager.createNFCSlot` names the slot it opens
  /// "Built-in NFC Slot"; a PC/SC reader carries the reader's own name.
  /// The name is all the driver has to classify a slot by, and it must
  /// classify without touching the card.
  private static let nearFieldSlotMarker = "NFC"

  override internal init() {
    super.init()
    delegate = self
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }

  internal func tokenDriver(
    _ driver: TKSmartCardTokenDriver,
    createTokenFor smartCard: TKSmartCard,
    aid: Data?
  ) throws -> TKSmartCardToken {
    let transport: CardTransport =
      smartCard.slot.name.localizedCaseInsensitiveContains(Self.nearFieldSlotMarker)
      ? .nearField : .reader
    let started = ContinuousClock.now
    TokenLog.info("createToken called: aid=\(aid?.count ?? -1) B via \(transport.rawValue)")
    do {
      // Transport selection is automatic. CryptoTokenKit calls this
      // driver only for a slot that exists, so an attached reader or the
      // phone's active NFC slot is, by definition, available for use.
      let token: Token =
        switch transport {
        case .nearField:
          try mintFromPrime(smartCard: smartCard, aid: aid, tokenDriver: driver)
        case .reader:
          try Token(smartCard: smartCard, aid: aid, tokenDriver: driver)
        }
      if transport == .reader {
        token.supersedeStoredContactlessIdentity()
      }
      TokenLog.info(
        "createToken succeeded ms=\(Self.elapsed(since: started))"
      )
      return token
    } catch let error as TokenError {
      TokenLog.error(
        "createToken failed (TokenError): \(error) ms=\(Self.elapsed(since: started))"
      )
      throw error.asTKError
    } catch {
      TokenLog.error(
        "createToken failed (other): \(error) ms=\(Self.elapsed(since: started))"
      )
      throw error
    }
  }

  /// Materializes the contactless token from the prime store without
  /// touching the card.
  ///
  /// Both halves were bought with measured failures. The mint does NO
  /// card I/O: the system owns this slot, and a read here disrupts the
  /// session it manages - the slot goes missing about a second later and
  /// the identity never reaches Safari. The one-time registration field
  /// publishes metadata and deliberately does not take a card session.
  /// A later signing field takes the session at the end: the minting slot
  /// ends about two seconds from there, and a `beginSession` issued when
  /// the signature arrives fails with `TKError -7`.
  ///
  /// The card is live in the slot for all of this, which is the app's
  /// side of the contract: `registerSmartCard` accepts only a token
  /// created for a live slot, so a field to hold is exactly what this
  /// path can assume.
  private func mintFromPrime(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws -> Token {
    // Each of the three is a different fault wearing the same error, and
    // the difference is the whole diagnosis: no ATR means the slot never
    // identified a card, no identifier means the ATR was empty, and no
    // prime means this card family has no active prime on this device.
    guard let answerToReset = smartCard.slot.atr?.bytes else {
      TokenLog.error("mintFromPrime: slot reports no answer to reset")
      throw TokenError.primeMissing
    }
    guard let lookupID = PrimeLookupIdentifier(answerToReset: answerToReset) else {
      TokenLog.error("mintFromPrime: atr=\(answerToReset.count)B names no card")
      throw TokenError.primeMissing
    }
    guard
      let match = PrimeStore.readContactless(
        lookupID: lookupID,
        answerToReset: answerToReset)
    else {
      TokenLog.error(
        "mintFromPrime: prime MISS for \(lookupID.value), "
          + "\(PrimeStore.storedCount()) prime(s) stored"
      )
      throw TokenError.primeMissing
    }
    guard
      let serialText = match.identity.tokenSerial,
      let serial = TokenSerial(value: serialText),
      let instanceID = CardInstanceIdentifier(tokenSerial: serial)
    else {
      TokenLog.error("mintFromPrime: prime has no supported printed card serial")
      throw TokenError.primeMissing
    }
    // Recorded rather than written: this is inside the two seconds the
    // system gives the mint, and the line is written out by whichever
    // `createToken` outcome line follows it.
    TokenLog.trace(
      "mintFromPrime: prime HIT for \(instanceID.value) "
        + "leaf=\(match.identity.certDER.count)B "
        + "issuer=\(match.identity.issuerDER?.count ?? -1)B "
        + "registration=\(match.isRegistrationField)"
    )
    return try Token(
      primedSmartCard: smartCard,
      aid: aid,
      tokenDriver: tokenDriver,
      instanceID: instanceID,
      primed: match.identity,
      shouldHoldSession: !match.isRegistrationField
    )
  }
}
