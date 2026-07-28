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

  /// Stable public identity of the physical card represented by this token.
  ///
  /// This is also the revocation boundary: a confirmed PIN1 rejection
  /// removes only this card's stored prime and CryptoTokenKit registration.
  internal let cardInstanceID: CardInstanceIdentifier

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
    // Only publish an identity we can actually sign with. Publishing a
    // canSign key with no supported request shapes would offer Safari a
    // certificate that can never complete its handshake.
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
    guard let instanceID = CardInstanceIdentifier(tokenSerial: identity.tokenSerial) else {
      TokenLog.error("Token.init: token serial has no supported printed-card form")
      throw TokenError.unsupportedKeyProfile
    }
    self.cardInstanceID = instanceID
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID.value,
      tokenDriver: tokenDriver
    )
    delegate = self
    TokenLog.info("Token.init: super.init done, publishing profile=\(String(describing: profile))")
    try publish(identity, leaf: leaf, profile: profile)
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
    primed: PrimedIdentity,
    shouldHoldSession: Bool
  ) throws {
    // Recorded, not written: this whole initializer runs inside the two
    // seconds the system gives the mint, and every line here is written
    // out by the `createToken` outcome that follows. Each refusal is
    // named, because they all leave the same error at the boundary and
    // the difference between them is the diagnosis.
    TokenLog.trace("Token.init(primed): instance=\(instanceID.value)")
    let material = try Self.validated(primed: primed, instanceID: instanceID)
    self.keyProfile = material.profile
    self.leafPublicKey = material.publicKey
    self.sealedAccessNumber = material.accessNumber
    self.interface = .fieldWithDeadline
    self.primedSerial = material.serial
    self.cardInstanceID = instanceID
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID.value,
      tokenDriver: tokenDriver
    )
    delegate = self
    if shouldHoldSession {
      observeSlotState(of: smartCard)
      holdSession(on: smartCard)
    }
    try publish(
      PublishedIdentity(
        leafDER: primed.certDER,
        issuerDER: primed.issuerDER,
        tokenSerial: material.serial),
      leaf: material.leaf,
      profile: material.profile
    )
    TokenLog.trace(
      "Token.init(primed): published, profile=\(String(describing: material.profile))")
  }

  /// Validates every piece of a stored contactless identity.
  private static func validated(
    primed: PrimedIdentity,
    instanceID: CardInstanceIdentifier
  ) throws -> PrimedTokenMaterial {
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
    guard
      let serialText = primed.tokenSerial,
      let storedSerial = TokenSerial(value: serialText),
      CardInstanceIdentifier(tokenSerial: storedSerial) == instanceID
    else {
      TokenLog.trace("Token.init(primed): stored serial does not name this token")
      throw TokenError.primeMissing
    }
    return PrimedTokenMaterial(
      accessNumber: accessNumber,
      leaf: leaf,
      profile: profile,
      publicKey: publicKey,
      serial: storedSerial)
  }

  /// Revokes automatic signing authority after this card rejects PIN1.
  ///
  /// This path is deliberately narrower than a generic sign failure.
  /// Transport loss, PACE failure, malformed signatures, and TLS errors do
  /// not touch stored state. Only the card's VERIFY response reaches here.
  ///
  /// The rejected fingerprint and accepted-PIN memory are process state.
  /// The stored PIN and prime are persistent authority, so they are removed
  /// before the failure returns. Registration removal is queued off the CTK
  /// callback thread to avoid asking ctkd to unregister a token while ctkd is
  /// still executing that token's sign callback.
  internal func revokeAutomaticIdentityAfterPin1Rejection(
    serial: TokenSerial,
    fingerprint: PinFingerprint
  ) {
    CredentialMemory.rejectedPins.recordRejection(fingerprint)
    CredentialMemory.acceptedPin1.clear(serial: serial)

    guard CardInstanceIdentifier(tokenSerial: serial) == cardInstanceID else {
      TokenLog.error("PIN1 rejection serial did not match token instance")
      return
    }

    let representsStoredIdentity: Bool =
      switch interface {
      case .fieldWithDeadline:
        true
      case .contact, .steadyField:
        PrimeStore.contains(instanceID: cardInstanceID)
      }
    guard representsStoredIdentity else {
      TokenLog.notice("PIN1 rejected; no stored automatic identity belonged to this token")
      return
    }

    CardCredentialStore.forgetPin1()
    PrimeStore.forget(instanceID: cardInstanceID)
    PrimeStore.forgetStaged()
    TokenRegistrationRevoker.revoke(cardInstanceID, reason: .pin1Rejection)
    TokenLog.error("PIN1 rejected; stored PIN1, prime, and token registration revoked")
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
  /// A signing-field contactless mint calls this and nothing else does;
  /// the one-time registration field deliberately stays passive. On the
  /// system-driven signing path the slot that minted this token has ended
  /// by the time the signature is asked for, and a fresh `beginSession`
  /// then fails with `TKError -7`; this one session carries the mint, the
  /// PACE run and the signature.
  ///
  /// Best effort by design: a token that could not hold a session is
  /// still perfectly usable wherever the card stays present, so a
  /// failure here is swallowed rather than failing the mint.
  internal func holdSession(on smartCard: TKSmartCard) {
    guard heldSession.current == nil else { return }
    let channel = SmartCardChannel(smartCard, waits: .nearField)
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
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil) "
        + "publicKeyData=\(keychainKey.publicKeyData?.count ?? -1)B "
        + "publicKeyHash=\(keychainKey.publicKeyHash?.count ?? -1)B "
        + "constraints=\(keychainKey.constraints?.count ?? 0)"
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
