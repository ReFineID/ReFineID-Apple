#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation
  import Security

  /// The one hold of the card that teaches this iPhone the card, so that
  /// no later hold has to.
  ///
  /// Priming opens the phone's NFC slot, runs PACE with the stored card
  /// access number, reads what is public and unchanging -- the
  /// authentication certificate, its issuer, the token serial -- writes it
  /// to the prime store, and, while the card is still live in the slot,
  /// registers the resulting token with the system so Safari can ask for
  /// it later.
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

    /// What the prime read from the card, in the shape the store wants.
    private struct Payload: Sendable {
      /// The name this card is primed under.
      let instance: CardInstanceIdentifier

      /// The DER authentication certificate.
      let certificate: Data

      /// The DER issuing-CA certificate, when the card offered one.
      let issuer: Data?

      /// The PKCS#15 token serial, when it could be read.
      let tokenSerial: String?
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

    /// The queue every blocking card exchange runs on.
    ///
    /// `SmartCardChannel` drives each APDU with a semaphore, so the wait
    /// must never land on the cooperative pool or the main thread.
    private static let cardQueue = DispatchQueue(label: "fi.refineid.priming.card")

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
    internal static func prime(progress: @escaping Progress) async -> Outcome {
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(message: Self.holdMessage)
      } catch {
        return Outcome(stored: false, registered: false, summary: Self.summary(for: error))
      }
      defer { session.end() }
      progress(String(localized: "Card found. Keep holding."))

      let payload: Payload
      do {
        payload = try await Self.onCardQueue {
          try Self.read(from: session, progress: progress)
        }
      } catch {
        session.update(message: String(localized: "Could not read the card."))
        return Outcome(stored: false, registered: false, summary: Self.summary(for: error))
      }

      guard Self.store(payload) else {
        session.update(message: String(localized: "Could not store the card details."))
        return Outcome(
          stored: false,
          registered: false,
          summary: Self.summary(for: Failure.primeNotStored))
      }
      progress(String(localized: "Card details stored on this iPhone."))

      // Registration has to happen HERE, with the card still live in the
      // slot. A registration attempted after the hold ends finds no card
      // to register and fails, and the holder would have to present the
      // card all over again.
      session.update(message: String(localized: "Setting up Safari. Keep holding."))
      let registered = await Self.register(
        instance: payload.instance, session: session, progress: progress)
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

    /// Reads everything the later signature must not have to read.
    ///
    /// Runs on the card queue, inside the card's exclusive session.
    private static func read(
      from session: NearFieldCardSession,
      progress: Progress
    ) throws -> Payload {
      guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
        throw Failure.cardAccessNumberMissing
      }
      return try session.withCardSession { channel in
        guard let instance = CardInstanceIdentifier(answerToReset: session.answerToReset) else {
          throw Failure.unidentifiedCard
        }
        // PACE runs from the master file. The card was discovered by
        // selecting the eMRTD application, and MSE:Set AT from an applet
        // context is answered 6985, so the master file is made current on
        // the plain channel before the first PACE command.
        //
        // Best effort on purpose: card generations differ in which SELECT
        // variant they acknowledge, and one that refuses both may still be
        // at the master file. PACE itself is the authoritative check --
        // its first command is the one that has to be accepted -- so a
        // refused reposition is not turned into a failure here.
        try? CardOperations(channel: channel).selectMasterFile()
        session.update(message: String(localized: "Opening a secure channel. Keep holding."))
        progress(String(localized: "Opening a secure channel with the card."))
        let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
        let operations = CardOperations(
          channel: SecureMessagingChannel(wrapping: channel, sessionKeys: keys))
        session.update(message: String(localized: "Reading your certificate. Keep holding."))
        progress(String(localized: "Reading the certificate from the card."))
        let certificate = try operations.readCertificate(.authentication)
        // The serial is read ONCE, here. It is public and it never
        // changes, and reading it during a signature costs more than the
        // field has left -- that read was measured dying part way
        // through. EF.TokenInfo lives under the PKCS#15 application, which
        // the certificate read above left current, so this comes before
        // the issuer read, which navigates to the master file.
        let serial = try? operations.readTokenSerial()
        let issuer = try? operations.readCertificate(.issuing)
        guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
          throw Failure.certificateUnreadable
        }
        progress(String(localized: "Card read."))
        return Payload(
          instance: instance,
          certificate: certificate,
          issuer: issuer,
          tokenSerial: serial?.value)
      }
    }

    /// Writes the primed identity for the token extension to find.
    ///
    /// The record is assembled inside `CardCredentialStore`, which owns
    /// the card access number: the digits go from the keychain into the
    /// prime without passing through this file.
    private static func store(_ payload: Payload) -> Bool {
      guard
        let identity = CardCredentialStore.primedIdentity(
          certificate: payload.certificate,
          issuer: payload.issuer,
          tokenSerial: payload.tokenSerial)
      else {
        return false
      }
      return PrimeStore.store(identity, forInstance: payload.instance)
    }

    /// Registers the live card so the system can ask for it later.
    private static func register(
      instance: CardInstanceIdentifier,
      session: NearFieldCardSession,
      progress: Progress
    ) async -> Bool {
      let manager = TKSmartCardTokenRegistrationManager.default
      let tokenID = await Self.tokenID(for: instance, session: session)
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
      for _ in 1...Self.tokenPollLimit {
        if let published = watcher.tokenIDs.first(where: { $0.contains(instance.value) }) {
          return published
        }
        guard session.holdsValidCard else { break }
        try? await Task.sleep(for: Self.tokenPollInterval)
      }
      return Self.tokenDriverClassID + Self.tokenIDSeparator + instance.value
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

    /// What to tell the holder about a failed run.
    ///
    /// Every sentence names something they can do differently, because a
    /// failed prime is a thing they are standing there holding a card
    /// for.
    private static func summary(for error: any Error) -> String {
      switch error {
      case Failure.cardAccessNumberMissing:
        String(localized: "Store the card access number first, then try again.")
      case Failure.certificateUnreadable:
        String(localized: "The card did not return a usable certificate.")
      case Failure.primeNotStored:
        String(localized: "The card details could not be stored on this iPhone.")
      case Failure.unidentifiedCard:
        String(localized: "The card was not recognized. Try holding it again.")
      case NearFieldCardSession.Failure.antennaBusy:
        String(localized: "The phone's card reader is busy. Try again in a moment.")
      case NearFieldCardSession.Failure.cardNeverArrived:
        String(localized: "No card was found. Hold the card against the top of the phone.")
      case NearFieldCardSession.Failure.slotRefused:
        String(localized: "This iPhone would not open a card reading session.")
      default:
        String(localized: "The card could not be read. Hold it still and try again.")
      }
    }
  }

#endif
