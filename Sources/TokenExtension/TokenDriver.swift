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

  internal func tokenDriver(
    _ driver: TKSmartCardTokenDriver,
    createTokenFor smartCard: TKSmartCard,
    aid: Data?
  ) throws -> TKSmartCardToken {
    let transport: CardTransport =
      smartCard.slot.name.localizedCaseInsensitiveContains(Self.nearFieldSlotMarker)
      ? .nearField : .reader
    TokenLog.info("createToken called: aid=\(aid?.count ?? -1) B via \(transport.rawValue)")
    do {
      // The holder's choice, read from the store the app writes it to. An
      // absent preference permits everything, so a Mac that has never
      // seen the settings screen keeps publishing from its reader.
      guard CardTransportStore.load().permits(transport) else {
        throw TokenError.transportDisabled
      }
      let token: Token =
        switch transport {
        case .nearField:
          try mintFromPrime(smartCard: smartCard, aid: aid, tokenDriver: driver)
        case .reader:
          try Token(smartCard: smartCard, aid: aid, tokenDriver: driver)
        }
      TokenLog.info("createToken succeeded")
      return token
    } catch let error as TokenError {
      TokenLog.error("createToken failed (TokenError): \(error)")
      throw error.asTKError
    } catch {
      TokenLog.error("createToken failed (other): \(error)")
      throw error
    }
  }

  /// Materializes the contactless token from the prime store without
  /// touching the card, and leaves it holding a live card session.
  ///
  /// Both halves were bought with measured failures. The mint does NO
  /// card I/O: the system owns this slot, and a read here disrupts the
  /// session it manages - the slot goes missing about a second later and
  /// the identity never reaches Safari. The session taken at the end is
  /// the field the signature will run in: the minting slot ends about two
  /// seconds from here, and a `beginSession` issued when the signature
  /// arrives fails with `TKError -7`.
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
    guard
      let answerToReset = smartCard.slot.atr?.bytes,
      let instanceID = CardInstanceIdentifier(answerToReset: answerToReset),
      let primed = PrimeStore.read(instanceID: instanceID)
    else {
      throw TokenError.primeMissing
    }
    let token = try Token(
      primedSmartCard: smartCard,
      aid: aid,
      tokenDriver: tokenDriver,
      instanceID: instanceID,
      primed: primed
    )
    token.holdSession(on: smartCard)
    return token
  }
}
