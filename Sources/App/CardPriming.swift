#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// The setup flow that teaches this iPhone the card, so later signing
  /// fields spend their time only on PACE, PIN1, and the signature.
  ///
  /// Priming uses two consecutive system NFC fields while the holder keeps
  /// the same card in place. Core NFC owns the first field, runs PACE, and
  /// reads the public, unchanging authentication metadata. CryptoTokenKit
  /// owns the second field, binds that live card to the staged metadata,
  /// and registers the resulting token so Safari can ask for it later.
  ///
  /// Three rules shape this flow, each bought with a measured on-device
  /// failure:
  ///
  /// 1. On the system-driven path `ctkd` owns the slot and ends it about
  ///    two seconds after the mint. The token extension therefore takes
  ///    its card session during `createToken` and KEEPS it for the
  ///    signature; a fresh `beginSession` in the sign fails with TKError
  ///    -7. That is the extension's side of this arrangement, and it is
  ///    what the two seconds are spent on.
  /// 2. That held session is released only when the slot state is
  ///    genuinely `.missing` (``NearFieldCardSession/isMissing``).
  ///    Releasing on any other non-`validCard` state tore a signature
  ///    down part way through a read.
  /// 3. The signature reads NOTHING it could already know. Everything
  ///    read here is public and unchanging, so it is read once, here,
  ///    where the holder is deliberately holding the card still and the
  ///    field is not rationed. This is what turned an intermittent
  ///    signature into a reliable one.
  ///
  /// `registerSmartCard` is called while the card is LIVE in the slot.
  /// Registering after the card has left finds nothing to register.
  ///
  /// Provenance: `SafariIdentityPrime.primeAndRegisterWithOneSystemNFC`
  /// and `registerVisibleTokens` in the donor
  /// `platform/apple/RefineID/Local/SafariIdentityPrime+OneSystemNFC.swift`
  /// and `SafariIdentityPrime+LiveRegistration.swift`.
  @available(iOS 26.0, *)
  internal enum CardPriming {
    /// Where a running prime reports what it is doing.
    ///
    /// Called from the card queue as well as the caller's context, so it
    /// must be safe to invoke from anywhere.
    internal typealias Progress = @Sendable (String) -> Void

    /// Reports which setup step a run has reached, and how it went.
    ///
    /// Separate from the text progress because the two answer different
    /// questions: the text says what is happening, the steps say how far
    /// the hold got and where it broke.
    internal typealias StepReport = @Sendable (CardPrimingStep, CardPrimingStep.State) -> Void

    /// What one priming run achieved.
    internal struct Outcome: Sendable {
      /// Whether the primed identity reached the prime store.
      internal let stored: Bool

      /// Whether the live card was registered for system logins.
      internal let registered: Bool

      /// One sentence for the holder, whatever happened.
      internal let summary: String
    }

    /// Why a priming run stopped short.
    internal enum Failure: Error {
      /// No card access number is stored, so PACE cannot be run.
      case cardAccessNumberMissing

      /// The certificate came off the card but is not a certificate.
      case certificateUnreadable

      /// The prime could not be written, so nothing would be there to
      /// serve the next login.
      case primeNotStored

      /// The card in the CTK registration field did not match the card
      /// that Core NFC had just read.
      case registrationCardMismatch

      /// The slot reported no answer to reset, so the card cannot be
      /// named -- and an unnamed card would be served another card's
      /// primed identity.
      case unidentifiedCard
    }

    /// Shown under Apple's own "Ready to Scan" title whenever the system
    /// later asks for this card.
    ///
    /// The title already says an action is wanted, so this only names the
    /// card.
    internal static let registrationPrompt = String(
      localized: "Present your Finnish identity card.")

    /// The minting extension's CryptoTokenKit class id.
    ///
    /// Keep in sync with `Config/TokenExtension-Info.plist`. A token id
    /// is this class id, a colon, and the token's instance id; addressing
    /// any other class would register a token this app cannot service.
    private static let tokenDriverClassID = "fi.refineid.ReFineID.ctk"

    /// Separates the class id from the instance id in a token id.
    private static let tokenIDSeparator = ":"

    /// How many times registration is attempted while the card is live.
    ///
    /// The attempts are immediate and back to back: they separate a
    /// transient miss, where one succeeds, from a deterministic
    /// precondition failure, where they all fail the same way. Waiting
    /// between them would only spend the hold.
    private static let registrationAttemptLimit: Int = 3

    /// How many times the token watcher is asked whether `ctkd` has
    /// published the token for this card yet.
    private static let tokenPollLimit: Int = 20

    /// Wait between two looks at the token watcher.
    private static let tokenPollInterval: Duration = .milliseconds(100)

    /// What the system sheet says while the holder is finding the spot.
    private static var holdMessage: String {
      String(
        localized: """
          Hold the card flat against the top of the phone. Keep holding \
          until ReFineID says it is done.
          """)
    }

    /// Primes the card the holder is about to present.
    ///
    /// Never throws: a prime is a thing a person is doing, and every way
    /// it can fail is something they need to read rather than something a
    /// caller needs to catch.
    internal static func prime(
      progress: @escaping Progress,
      step: @escaping StepReport
    ) async -> Outcome {
      guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
        step(.found, .failed)
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: Failure.cardAccessNumberMissing))
      }

      // Field one belongs only to Core NFC. No CTK slot exists yet, so
      // the token extension cannot take a session or start a competing
      // PACE exchange while the app reads the identity.
      step(.found, .running)
      let payload: CoreNFCPrimeSession.Payload
      do {
        payload = try await CoreNFCPrimeSession.read(
          accessNumber: accessNumber,
          progress: progress,
          step: step)
      } catch {
        return Outcome(stored: false, registered: false, summary: Self.summary(for: error))
      }

      guard let identity = Self.stageIdentity(payload, progress: progress) else {
        step(.stored, .failed)
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: Failure.primeNotStored))
      }
      defer { PrimeStore.forgetStaged() }
      return await Self.registerStagedIdentity(
        identity,
        payload: payload,
        progress: progress,
        step: step)
    }

    /// Stores the short-lived bridge consumed by the next CTK field.
    private static func stageIdentity(
      _ payload: CoreNFCPrimeSession.Payload,
      progress: Progress
    ) -> PrimedIdentity? {
      guard
        let identity = CardCredentialStore.primedIdentity(
          certificate: payload.certificate,
          issuer: payload.issuer,
          tokenSerial: payload.tokenSerial),
        PrimeStore.stage(
          identity,
          contactlessIdentification: payload.identification)
      else {
        return nil
      }
      progress(String(localized: "Identity staged for Safari registration."))
      return identity
    }

    /// Opens the second field, binds it to the first, and registers it.
    private static func registerStagedIdentity(
      _ identity: PrimedIdentity,
      payload: CoreNFCPrimeSession.Payload,
      progress: @escaping Progress,
      step: StepReport
    ) async -> Outcome {
      // The staged record is already visible to the token extension, so
      // it publishes metadata without touching the card. Later fields
      // have no staged record and retain the session for PACE plus signing.
      step(.stored, .running)
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(message: Self.holdMessage)
      } catch {
        step(.stored, .failed)
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: error))
      }
      defer { session.end() }
      progress(String(localized: "Safari registration field opened. Keep holding."))

      guard
        session.answerToReset.contains(payload.identification)
      else {
        step(.stored, .failed)
        session.update(message: Self.sheetMessage(for: Failure.registrationCardMismatch))
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: Failure.registrationCardMismatch))
      }
      guard
        let lookup = PrimeLookupIdentifier(answerToReset: session.answerToReset),
        PrimeStore.store(identity, forLookup: lookup)
      else {
        step(.stored, .failed)
        session.update(message: String(localized: "Could not save the card details."))
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: Failure.primeNotStored))
      }
      step(.stored, .done)
      progress(String(localized: "Card details stored on this iPhone."))

      return await Self.finish(
        instance: payload.instance, session: session, progress: progress, step: step)
    }

    /// Registers the live card and reports how the hold ended.
    ///
    /// Split from `prime` only so each stays readable; it must still run
    /// with the card in the slot, which is why it takes the live session
    /// rather than being called after the hold.
    private static func finish(
      instance: CardInstanceIdentifier,
      session: NearFieldCardSession,
      progress: @escaping Progress,
      step: StepReport
    ) async -> Outcome {
      session.update(message: String(localized: "Setting up Safari. Keep holding."))
      step(.registered, .running)
      let registered = await Self.register(
        instance: instance, session: session, progress: progress)
      step(.registered, registered ? .done : .failed)
      session.update(
        message: registered
          ? String(localized: "Your card is ready to use.")
          : String(localized: "Safari setup did not finish."))
      return Outcome(
        stored: true,
        registered: registered,
        summary: registered
          ? String(localized: "Your card is set up. Safari can now ask for it.")
          : String(
            localized: """
              The card details were stored, but Safari setup did not \
              finish. Try priming the card again.
              """))
    }

    /// Registers the live card so the system can ask for it later.
    private static func register(
      instance: CardInstanceIdentifier,
      session: NearFieldCardSession,
      progress: Progress
    ) async -> Bool {
      let manager = TKSmartCardTokenRegistrationManager.default
      let tokenID = await Self.tokenID(for: instance, session: session)
      if manager.registeredSmartCardTokens.contains(tokenID) {
        progress(String(localized: "Card registered for Safari."))
        return true
      }
      for attempt in 1...Self.registrationAttemptLimit {
        guard session.holdsValidCard else {
          progress(String(localized: "The card left before setup finished."))
          return false
        }
        do {
          try manager.registerSmartCard(
            tokenID: tokenID, promptMessage: Self.registrationPrompt)
          progress(String(localized: "Card registered for Safari."))
          return true
        } catch {
          // CryptoTokenKit may publish while the throwing call unwinds;
          // already registered is also success for this idempotent action.
          if manager.registeredSmartCardTokens.contains(tokenID) {
            progress(String(localized: "Card registered for Safari."))
            return true
          }
          progress(String(localized: "Setup attempt \(attempt) did not take."))
        }
      }
      return false
    }

    /// The token id to register, preferring the one the system already
    /// publishes for this card.
    ///
    /// `ctkd` mints the token from the prime store moments after the
    /// prime is written, so the watcher is asked a few times before the
    /// id is constructed from the class id instead. The constructed form
    /// is the same string the system uses, so it registers the same
    /// token; it just cannot be confirmed first.
    private static func tokenID(
      for instance: CardInstanceIdentifier,
      session: NearFieldCardSession
    ) async -> String {
      let watcher = TKTokenWatcher()
      let expected = Self.tokenDriverClassID + Self.tokenIDSeparator + instance.value
      for _ in 1...Self.tokenPollLimit {
        if let published = watcher.tokenIDs.first(where: { tokenID in tokenID == expected }) {
          return published
        }
        guard session.holdsValidCard else { break }
        try? await Task.sleep(for: Self.tokenPollInterval)
      }
      return expected
    }
  }

#endif
