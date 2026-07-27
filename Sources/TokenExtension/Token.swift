import CardCore
import CryptoTokenKit
import Foundation
import Security
/// The token instance for one inserted card.
///
/// At creation it reads the on-card authentication certificate through
/// CardCore, discovers the key profile, and publishes into the keychain
/// the leaf certificate, a sign-only key gated behind PIN1, and (when
/// present) the issuing-CA certificate - so Safari offers the identity
/// at a service's client-certificate request. Signing itself is the
/// session's responsibility.
internal final class Token: TKSmartCardToken, TKTokenDelegate {
  /// The auth certificate and its key share this keychain object ID.
  private static let authObjectID = "auth"
  /// The published issuing-CA certificate's object ID (cert-only).
  private static let issuerObjectID = "issuer-ca"
  /// The authentication key's profile, resolved from the leaf and used
  /// by the session to advertise and select signing algorithms.
  internal let keyProfile: CardKeyProfile

  /// The leaf's public key, used by the session to verify each raw card
  /// signature before returning it - a card that lost its loaded hash
  /// signs silently-wrong bytes with no error SW (S1 v4.2 §3.8.1.1), and
  /// the token must fail closed rather than feed the TLS stack garbage.
  ///
  /// On the contactless path this is also the cached form of the
  /// certificate the prime read: the leaf is public and unchanging, so
  /// the signature never spends its field re-reading EF.4331 to get it.
  internal let leafPublicKey: SecKey

  /// The card access number this card must be unsealed with; nil when the
  /// card answered in the clear.
  ///
  /// Never logged. Its presence, not the slot it arrived on, is what
  /// tells the session which card it is holding: with one, every verb
  /// travels inside a PACE channel; without one, the card is spoken to
  /// directly.
  ///
  /// A contactless card is sealed whichever antenna reaches it -- the
  /// phone's own or the one in a desk reader -- so this is set on both,
  /// and the two differ only in where the number came from. The phone
  /// takes it from the prime, because the system ends that slot about two
  /// seconds after the mint and there is no room to read anything. A
  /// reader holds its field indefinitely, so there the card is unsealed
  /// and read on the spot, and no prime is needed at all.
  internal let sealedAccessNumber: CardAccessNumber?

  /// How this card is reached, which decides what a signature may spend.
  internal let interface: CardInterface

  /// The card's token serial as the prime read it, contactless tokens
  /// only.
  ///
  /// Cached for the same reason as the certificate: it is public, it
  /// cannot change, and re-reading it costs more than the field has left
  /// - that read was measured dying part way through, which is a login
  /// lost for nothing.
  internal let primedSerial: TokenSerial?

  /// The card session taken at the mint and kept open for the signature.
  ///
  /// Empty on the contact path, which opens a session per operation.
  internal let heldSession = HeldCardSession()

  /// Releases the held session when the card leaves the slot.
  private var slotStateObservation: NSKeyValueObservation?

  internal init(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws {
    TokenLog.info("Token.init: reading identity")
    let (identity, accessNumber) = try Self.readIdentity(from: smartCard)
    TokenLog.info(
      "Token.init: leaf=\(identity.leafDER.count) issuer=\(identity.issuerDER?.count ?? -1)"
    )
    guard let leaf = SecCertificateCreateWithData(nil, identity.leafDER as CFData) else {
      TokenLog.error("Token.init: SecCertificateCreateWithData(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    guard let profile = CardKeyProfile.resolve(fromCertificate: leaf) else {
      TokenLog.error("Token.init: unsupported key profile")
      throw TokenError.unsupportedKeyProfile
    }
    // Only publish an identity we can actually sign with. An RSA card is
    // recognized but the sign path is ECDSA-only for now; publishing a
    // canSign key we cannot service would offer Safari a certificate that
    // never prompts for PIN and always fails the handshake.
    guard SigningAlgorithmResolver.supportsSigning(profile) else {
      TokenLog.error("Token.init: \(profile) recognized but signing not yet supported")
      throw TokenError.unsupportedKeyProfile
    }
    guard let publicKey = SecCertificateCopyKey(leaf) else {
      TokenLog.error("Token.init: SecCertificateCopyKey(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    self.keyProfile = profile
    self.leafPublicKey = publicKey
    self.sealedAccessNumber = accessNumber
    // A card read here was read through a reader, whichever of its
    // interfaces answered: this initializer does card I/O, which the
    // phone's path cannot afford at all.
    self.interface = accessNumber == nil ? .contact : .steadyField
    self.primedSerial = nil
    // Same derivation and same contents version as the contactless mint
    // below; only the material differs, because only here has the card
    // already been read. Unreachable in practice: these are the bytes
    // SecCertificateCreateWithData just accepted, so they are not empty.
    guard let instanceID = CardInstanceIdentifier(authenticationCertificate: identity.leafDER)
    else {
      TokenLog.error("Token.init: leaf certificate has no bytes to name the card with")
      throw TokenError.certificateUnreadable
    }
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID.value,
      tokenDriver: tokenDriver
    )
    TokenLog.info("Token.init: super.init done, publishing profile=\(String(describing: profile))")
    try publish(identity, leaf: leaf, profile: profile)
    // A fresh token means the card (re-)appeared: clear any cached PIN1 and
    // lift the disable latch a prior degradation may have set.
    CredentialMemory.pin1Cache.reset()
    TokenLog.info("Token.init: publish done")
  }

  /// Creates the token from a primed identity instead of from the card.
  ///
  /// The contactless interface seals the PKCS#15 application until PACE
  /// has run, so this cannot read the certificate the way the contact
  /// path does - and on the system-driven path it must not try at all:
  /// `ctkd` owns the slot, ends it about two seconds from here, and a
  /// read issued now was measured taking the slot away before the
  /// identity ever reached Safari. Everything needed is already in the
  /// prime the app stored - certificate, chain, serial and card access
  /// number, all read from this same card and none of them able to have
  /// changed since - so this mint does NO card I/O whatsoever and
  /// publishes exactly the items the contact path would.
  internal init(
    primedSmartCard smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver,
    instanceID: CardInstanceIdentifier,
    primed: PrimedIdentity
  ) throws {
    // Recorded, not written: this whole initializer runs inside the two
    // seconds the system gives the mint, and every line here is written
    // out by the `createToken` outcome that follows. Each refusal is
    // named, because they all leave the same error at the boundary and
    // the difference between them is the diagnosis.
    TokenLog.trace("Token.init(primed): instance=\(instanceID.value)")
    guard let accessNumber = CardAccessNumber(digits: primed.can) else {
      TokenLog.trace("Token.init(primed): stored card access number is not usable")
      throw TokenError.primeMissing
    }
    guard let leaf = SecCertificateCreateWithData(nil, primed.certDER as CFData) else {
      TokenLog.trace("Token.init(primed): stored leaf \(primed.certDER.count)B is not a cert")
      throw TokenError.certificateUnreadable
    }
    guard
      let profile = CardKeyProfile.resolve(fromCertificate: leaf),
      SigningAlgorithmResolver.supportsSigning(profile)
    else {
      TokenLog.trace("Token.init(primed): key profile unsupported for signing")
      throw TokenError.unsupportedKeyProfile
    }
    guard let publicKey = SecCertificateCopyKey(leaf) else {
      TokenLog.trace("Token.init(primed): leaf carries no usable public key")
      throw TokenError.certificateUnreadable
    }
    self.keyProfile = profile
    self.leafPublicKey = publicKey
    self.sealedAccessNumber = accessNumber
    self.interface = .fieldWithDeadline
    self.primedSerial = primed.tokenSerial.flatMap(TokenSerial.init(value:))
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID.value,
      tokenDriver: tokenDriver
    )
    observeSlotState(of: smartCard)
    holdSession(on: smartCard)
    try publish(
      PublishedIdentity(leafDER: primed.certDER, issuerDER: primed.issuerDER),
      leaf: leaf,
      profile: profile
    )
    TokenLog.trace("Token.init(primed): published, profile=\(String(describing: profile))")
  }

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
  private static func readIdentity(
    from smartCard: TKSmartCard
  ) throws -> (identity: PublishedIdentity, accessNumber: CardAccessNumber?) {
    TokenLog.info("readIdentity: opening session")
    return try SmartCardChannel(smartCard).withSession { channel in
      do {
        TokenLog.info("readIdentity: selecting application")
        try CardOperations(channel: channel).selectFineidApplication()
      } catch CardOperationError.selectRejected(.securityNotSatisfied) {
        TokenLog.info("readIdentity: application is sealed; unsealing")
        return try Self.unsealed(over: channel)
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
    over channel: SmartCardChannel
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
    let started = ContinuousClock.now
    // PACE has to start at master-file level: the card refuses MSE:Set AT
    // with 6985 anywhere else. Best effort, as everywhere else this runs:
    // PACE is the step whose failure should be the one reported.
    try? CardOperations(channel: channel).selectMasterFile()
    let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
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

  // The @objc requirement is throwing; keep `throws` for the bridge.
  // swiftlint:disable:next unneeded_throws_rethrows
  internal func createSession(_: TKToken) throws -> TKTokenSession {
    // Which interface this card is on is the useful half: it says which
    // sign path is about to run. `TKToken` publishes no instance
    // identifier to name it with.
    TokenLog.info("createSession: session requested, interface=\(interface)")
    return TokenSession(token: self)
  }

  /// Takes a card session now and keeps it, so the signature that
  /// follows still has a live field.
  ///
  /// The contactless mint calls this and nothing else does. On the
  /// system-driven path the slot that minted this token has ended by the
  /// time the signature is asked for, and a fresh `beginSession` then
  /// fails with `TKError -7`; this one session carries the mint, the
  /// PACE run and the signature.
  ///
  /// Best effort by design: a token that could not hold a session is
  /// still perfectly usable wherever the card stays present, so a
  /// failure here is swallowed rather than failing the mint.
  internal func holdSession(on smartCard: TKSmartCard) {
    guard heldSession.current == nil else { return }
    let channel = SmartCardChannel(smartCard)
    do {
      try channel.beginSession()
    } catch {
      TokenLog.info("Token.holdSession: no session retained (\(error))")
      return
    }
    heldSession.retain(channel)
    if let accessNumber = sealedAccessNumber {
      heldSession.startPACE(with: accessNumber)
    }
  }

  /// Releases the held session when the card is genuinely gone.
  ///
  /// Only `.missing` counts. Releasing on any other non-valid state was
  /// measured tearing a signature down part way through a read: a card
  /// momentarily out of the field is still the same card, and the slot
  /// says so a moment later.
  private func observeSlotState(of smartCard: TKSmartCard) {
    slotStateObservation = smartCard.slot.observe(\.state, options: [.new]) {
      [held = heldSession] observed, change in
      let state = change.newValue ?? observed.state
      guard state == .missing else { return }
      held.release()
    }
  }

  /// Builds and fills the keychain contents from the read identity.
  private func publish(
    _ identity: PublishedIdentity,
    leaf: SecCertificate,
    profile: CardKeyProfile
  ) throws {
    guard
      let keychainCertificate = TKTokenKeychainCertificate(
        certificate: leaf,
        objectID: Self.authObjectID
      ),
      let keychainKey = TKTokenKeychainKey(
        certificate: leaf,
        objectID: Self.authObjectID
      )
    else {
      TokenLog.error("publish: keychain item construction failed")
      throw TokenError.keychainItemConstructionFailed
    }

    keychainKey.keyType = profile.keyType
    keychainKey.keySizeInBits = profile.keySizeInBits
    keychainKey.canSign = true
    keychainKey.canDecrypt = false
    keychainKey.canPerformKeyExchange = false
    keychainKey.isSuitableForLogin = true
    // The signature is gated behind PIN1: this constraint is what makes
    // CryptoTokenKit call beginAuth (the PIN sheet) before signing. Absent
    // it, the system signs without asking, our sign has no PIN, and Safari
    // fails with the identity selected but no prompt. The constraints map
    // requires NSNumber operation keys (the CryptoTokenKit ObjC API).
    // swiftlint:disable:next legacy_objc_type
    let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
    keychainKey.constraints = [signOperationKey: Pin1AuthOperation.signDataConstraint]

    var items: [TKTokenKeychainItem] = [keychainCertificate, keychainKey]
    if let issuerDER = identity.issuerDER,
      let issuer = SecCertificateCreateWithData(nil, issuerDER as CFData),
      let issuerItem = TKTokenKeychainCertificate(
        certificate: issuer,
        objectID: Self.issuerObjectID
      )
    {
      items.append(issuerItem)
    }
    TokenLog.info(
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil)"
    )
    keychainContents?.fill(with: items)
  }
  /// Gives back the held session when the token itself goes away.
  ///
  /// The slot observation covers the card leaving; this covers `ctkd`
  /// dropping the token for any other reason. A session left open on the
  /// phone's own antenna keeps the radio, and the next hold then meets
  /// the busy answer ``NearFieldCardSession`` has to retry through -
  /// about 2.5 seconds of the holder's time for nothing.
  deinit {
    heldSession.release()
    // Last chance to get the trace out of a process ctkd is dropping: a
    // token going away is often the only sign of what ended a login, and
    // anything still only recorded would go with it.
    TokenLog.flush()
  }
}
