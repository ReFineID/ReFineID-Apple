#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// The setup flow that teaches this iPhone the card, so later signing
  /// fields spend their time only on PACE, PIN1, and the signature.
  ///
  /// Priming uses ONE system NFC field: the app opens the CryptoTokenKit
  /// slot, and inside that single hold runs PACE, reads the public
  /// authentication metadata, stores it, and registers the resulting
  /// token. `ctkd` asks the token extension for a token the moment the
  /// card enters the slot -- while PACE is still running -- so the
  /// extension bridges the gap with a bounded wait for the prime this
  /// flow is about to write (`TokenDriver.awaitPrime`). A card this
  /// device has already primed skips the card I/O entirely and goes
  /// straight to registration, which is the fastest hold there is.
  ///
  /// Three rules shape this flow, each bought with a measured on-device
  /// failure:
  ///
  /// 1. On the system-driven path `ctkd` owns the slot and ends it about
  ///    two seconds after the mint. The token extension therefore takes
  ///    its card session during `createToken` and KEEPS it for the
  ///    signature; a fresh `beginSession` in the sign fails with TKError
  ///    -7. During THIS flow a registration mark, written before the
  ///    slot opens, tells the extension to publish metadata without
  ///    taking a session, so the app keeps the card to itself.
  /// 2. That held session is released only when the slot state is
  ///    genuinely `.missing` (``NearFieldCardSession/isMissing``).
  ///    Releasing on any other non-`validCard` state tore a signature
  ///    down part way through a read.
  /// 3. The signature reads NOTHING it could already know. Everything
  ///    read here is public and unchanging, so it is read once, here,
  ///    where the holder is deliberately holding the card still and the
  ///    field is the app's own rather than a rationed signing field.
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

    /// The queue every blocking card exchange runs on.
    ///
    /// `SmartCardChannel` drives each APDU with a semaphore, so the wait
    /// must never land on the cooperative pool or the main thread.
    private static let cardQueue = DispatchQueue(label: "fi.refineid.priming.card")

    /// What the system sheet says while the holder is finding the spot.
    ///
    /// One line, and only the part the holder cannot work out: where to
    /// put the card. Apple's own title above it already says a scan is
    /// wanted, and the meter and sound below say the hold is running, so
    /// a sentence telling them to keep holding is a third voice saying
    /// what two already said.
    private static var holdMessage: String {
      String(localized: "Hold the card on the top back of the phone.")
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
        return Self.failure(Failure.cardAccessNumberMissing)
      }
      // Marked BEFORE the slot opens: `ctkd` asks the extension for a
      // token the moment the card arrives, and a mark written after that
      // would lose the race. The mark makes the extension publish
      // without taking a card session, leaving the card to this flow.
      guard PrimeStore.markRegistrationField() else {
        step(.found, .failed)
        return Self.failure(Failure.primeNotStored)
      }
      defer { PrimeStore.clearRegistrationField() }

      step(.found, .running)
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(message: Self.holdMessage)
      } catch {
        step(.found, .failed)
        return Self.failure(error)
      }
      defer { session.end() }
      // The meter lives on the sheet from here on: the card is against
      // the phone and Apple's panel is over the app, so this is the only
      // surface the holder can actually see.
      let sheet = PrimingSheetReporter(
        session: session,
        activity: String(localized: "Card found"))
      let report: StepReport = { reached, state in
        step(reached, state)
        sheet.report(reached, state)
      }
      report(.found, .done)
      progress(String(localized: "Card found. Keep holding."))

      guard let lookup = PrimeLookupIdentifier(answerToReset: session.answerToReset) else {
        report(.secureChannel, .failed)
        sheet.fail(Self.sheetMessage(for: Failure.unidentifiedCard))
        return Self.failure(Failure.unidentifiedCard)
      }

      // A re-prime restores a lost registration without one APDU. The
      // extension finds the same record by the same lookup, so the mint
      // is immediate and the whole hold is the registration.
      if let instance = Self.storedInstance(lookup: lookup) {
        for done in [CardPrimingStep.secureChannel, .certificate, .stored] {
          report(done, .done)
        }
        progress(String(localized: "Card details already stored on this iPhone."))
        return await Self.finish(
          instance: instance, sheet: sheet, progress: progress, step: report)
      }

      return await Self.readStoreRegister(
        sheet: sheet,
        lookup: lookup,
        accessNumber: accessNumber,
        progress: progress,
        step: report)
    }

    /// An Outcome that achieved nothing, explained.
    private static func failure(_ error: any Error) -> Outcome {
      Outcome(stored: false, registered: false, summary: Self.summary(for: error))
    }

    /// The instance an existing prime already names, when one does.
    private static func storedInstance(
      lookup: PrimeLookupIdentifier
    ) -> CardInstanceIdentifier? {
      guard
        let existing = PrimeStore.read(lookupID: lookup),
        let serialText = existing.tokenSerial,
        let serial = TokenSerial(value: serialText)
      else {
        return nil
      }
      return CardInstanceIdentifier(tokenSerial: serial)
    }

    /// Reads the card in this same field, stores the prime, registers.
    private static func readStoreRegister(
      sheet: PrimingSheetReporter,
      lookup: PrimeLookupIdentifier,
      accessNumber: CardAccessNumber,
      progress: @escaping Progress,
      step: @escaping StepReport
    ) async -> Outcome {
      step(.secureChannel, .running)
      let payload: Payload
      do {
        payload = try await Self.onCardQueue {
          try Self.read(
            from: sheet,
            accessNumber: accessNumber,
            progress: progress,
            step: step)
        }
      } catch {
        // The sheet is the only thing a holder can see while holding, so
        // it carries the detail rather than a shrug. Nothing here names
        // a PIN, CAN or the holder.
        sheet.fail(Self.sheetMessage(for: error))
        return Self.failure(error)
      }

      // The exact record is what the extension's mint -- already waiting
      // in this field -- publishes from, and what every later signing
      // field reads. The registration mark written before the slot
      // opened keeps that waiting mint from taking the card session
      // away from this flow.
      step(.stored, .running)
      guard
        let identity = CardCredentialStore.primedIdentity(
          certificate: payload.certificate,
          issuer: payload.issuer,
          tokenSerial: payload.tokenSerial),
        PrimeStore.store(identity, forLookup: lookup)
      else {
        step(.stored, .failed)
        sheet.fail(String(localized: "Could not save card details"))
        return Self.failure(Failure.primeNotStored)
      }
      step(.stored, .done)
      progress(String(localized: "Card details stored on this iPhone."))

      return await Self.finish(
        instance: payload.instance, sheet: sheet, progress: progress, step: step)
    }

    /// Registers the live card and reports how the hold ended.
    ///
    /// Split from `prime` only so each stays readable; it must still run
    /// with the card in the slot, which is why it takes the live session
    /// rather than being called after the hold.
    private static func finish(
      instance: CardInstanceIdentifier,
      sheet: PrimingSheetReporter,
      progress: @escaping Progress,
      step: StepReport
    ) async -> Outcome {
      sheet.say(String(localized: "Setting up Safari"))
      step(.registered, .running)
      let registered = await Self.register(
        instance: instance, session: sheet.session, progress: progress)
      step(.registered, registered ? .done : .failed)
      if registered {
        sheet.say(String(localized: "Ready to use"))
      } else {
        sheet.fail(String(localized: "Safari setup did not finish"))
      }
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
      let expected = CardTokenNamespace.tokenIdentifier(for: instance)
      for _ in 1...Self.tokenPollLimit {
        if let published = watcher.tokenIDs.first(where: { tokenID in tokenID == expected }) {
          return published
        }
        guard session.holdsValidCard else { break }
        try? await Task.sleep(for: Self.tokenPollInterval)
      }
      return expected
    }

    /// Runs one blocking card exchange off the cooperative pool.
    private static func onCardQueue<Value: Sendable>(
      _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
      try await withCheckedThrowingContinuation { continuation in
        Self.cardQueue.async {
          continuation.resume(with: Result { try body() })
        }
      }
    }
  }

#endif
