#if canImport(CoreNFC) && os(iOS)

  import CardCore
  @preconcurrency import CoreNFC
  import Foundation
  import Security

  /// Reads the public, unchanging identity metadata in an app-owned field.
  ///
  /// The reader retains itself until exactly one continuation is resumed.
  /// Card work runs on a GCD queue because ``CoreNFCCardChannel`` blocks
  /// for each Core NFC completion callback.
  @available(iOS 26.0, *)
  internal final class CoreNFCPrimeSession: NSObject, NFCTagReaderSessionDelegate,
    @unchecked Sendable
  {
    /// What the following CTK registration field needs.
    internal struct Payload: Sendable {
      /// Public CTK identity name derived from the printed card serial.
      internal let instance: CardInstanceIdentifier

      /// Bytes that must occur in the following field's CTK answer to reset.
      ///
      /// This proves transport compatibility, while the holder keeping the
      /// card in place preserves the physical-card identity between fields.
      internal let identification: Data

      /// Authentication certificate DER.
      internal let certificate: Data

      /// Issuing certificate DER when the card supplied it.
      internal let issuer: Data?

      /// Full PKCS#15 serial retained for exact reconstruction.
      internal let tokenSerial: String
    }

    /// Failures specific to opening and driving the Core NFC field.
    internal enum Failure: Error {
      /// This device cannot open an ISO 14443 reader session.
      case unavailable

      /// The detected tag was not an ISO 7816 smart card.
      case unsupportedTag

      /// Core NFC did not return one APDU callback within ten seconds.
      case commandTimedOut

      /// The card supplied no stable pre-PACE identification bytes.
      case identificationMissing
    }

    /// Serializes duplicate detections and completion callbacks.
    private final class State: @unchecked Sendable {
      private let lock = NSLock()
      private var reading = false
      private var finished = false

      var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
      }

      func beginReading() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !reading, !finished else { return false }
        reading = true
        return true
      }

      func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
      }
    }

    /// Keeps non-Sendable Core NFC handles together across GCD callbacks.
    private final class Handles: @unchecked Sendable {
      let session: NFCTagReaderSession
      let tag: any NFCISO7816Tag

      init(session: NFCTagReaderSession, tag: any NFCISO7816Tag) {
        self.session = session
        self.tag = tag
      }
    }

    /// Every blocking card operation runs here, never on a delegate queue.
    private static let cardQueue = DispatchQueue(label: "fi.refineid.priming.corenfc")

    private let accessNumber: CardAccessNumber
    private let progress: CardPriming.Progress
    private let step: CardPriming.StepReport
    private let continuation: CheckedContinuation<Result<Payload, any Error>, Never>
    private let state = State()
    private var session: NFCTagReaderSession?

    /// Deliberate self-retain until the delegate finishes or invalidates.
    private var lifetime: CoreNFCPrimeSession?

    private init(
      accessNumber: CardAccessNumber,
      progress: @escaping CardPriming.Progress,
      step: @escaping CardPriming.StepReport,
      continuation: CheckedContinuation<Result<Payload, any Error>, Never>
    ) {
      self.accessNumber = accessNumber
      self.progress = progress
      self.step = step
      self.continuation = continuation
    }

    /// Opens Core NFC and returns only after the first field is closed.
    internal static func read(
      accessNumber: CardAccessNumber,
      progress: @escaping CardPriming.Progress,
      step: @escaping CardPriming.StepReport
    ) async throws -> Payload {
      let result = await withCheckedContinuation { continuation in
        let reader = Self(
          accessNumber: accessNumber,
          progress: progress,
          step: step,
          continuation: continuation)
        reader.start()
      }
      return try result.get()
    }

    private func start() {
      lifetime = self
      guard NFCTagReaderSession.readingAvailable,
        let reader = NFCTagReaderSession(
          pollingOption: .iso14443,
          delegate: self,
          queue: nil)
      else {
        complete(.failure(Failure.unavailable))
        return
      }
      session = reader
      reader.alertMessage = String(
        localized: "Hold your Finnish identity card at the top of the phone.")
      progress(String(localized: "Opening the phone's card reader."))
      reader.begin()
    }

    internal func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
      session.alertMessage = String(
        localized: "Move the card slowly near the top edge of the phone.")
      progress(String(localized: "Waiting for the card."))
    }

    internal func tagReaderSession(
      _: NFCTagReaderSession,
      didInvalidateWithError error: any Error
    ) {
      guard !state.isFinished else { return }
      step(.found, .failed)
      complete(.failure(error))
    }

    internal func tagReaderSession(
      _ session: NFCTagReaderSession,
      didDetect tags: [NFCTag]
    ) {
      guard state.beginReading() else { return }
      guard tags.count == 1, let found = tags.first,
        case .iso7816(let tag) = found
      else {
        step(.found, .failed)
        complete(
          .failure(Failure.unsupportedTag),
          errorMessage: String(localized: "This is not a supported identity card."))
        return
      }
      let handles = Handles(session: session, tag: tag)
      session.alertMessage = String(localized: "Card found. Keep holding.")
      progress(String(localized: "Card found. Keep holding."))
      session.connect(to: found) { [weak self] error in
        guard let self else { return }
        if let error {
          step(.found, .failed)
          complete(
            .failure(error),
            errorMessage: String(localized: "Connection lost. Hold the card flat and try again."))
          return
        }
        step(.found, .done)
        step(.secureChannel, .running)
        progress(String(localized: "Card connected. Keep holding."))
        Self.cardQueue.async { [weak self] in
          guard let self else { return }
          do {
            complete(.success(try readPayload(handles: handles)))
          } catch {
            complete(
              .failure(error),
              errorMessage: CardPriming.sheetMessage(for: error))
          }
        }
      }
    }

    /// Runs PACE, then reads data that a later signing field must not.
    private func readPayload(handles: Handles) throws -> Payload {
      let channel = CoreNFCCardChannel(tag: handles.tag)
      let identification = channel.identification
      guard !identification.isEmpty else {
        throw Failure.identificationMissing
      }
      let plainOperations = CardOperations(channel: channel)
      try? plainOperations.selectMasterFile()
      handles.session.alertMessage = String(localized: "Opening a secure channel. Keep holding.")
      progress(String(localized: "Opening a secure channel with the card."))
      let keys: PaceSessionKeys
      do {
        keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
      } catch {
        step(.secureChannel, .failed)
        throw error
      }
      step(.secureChannel, .done)
      step(.certificate, .running)
      progress(String(localized: "Secure channel opened."))

      let operations = CardOperations(
        channel: SecureMessagingChannel(wrapping: channel, sessionKeys: keys))
      handles.session.alertMessage = String(localized: "Reading the certificate. Keep holding.")
      progress(String(localized: "Reading the certificate from the card."))
      do {
        let certificate = try operations.readCertificate(.authentication)
        let serial = try operations.readTokenSerial()
        guard let instance = CardInstanceIdentifier(tokenSerial: serial) else {
          throw CardPriming.Failure.unidentifiedCard
        }
        let issuer =
          (try? operations.readCertificate(.issuing))
          ?? BundledIssuerCertificate.der(matching: certificate)
        guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
          throw CardPriming.Failure.certificateUnreadable
        }
        step(.certificate, .done)
        progress(String(localized: "Card identity read."))
        return Payload(
          instance: instance,
          identification: identification,
          certificate: certificate,
          issuer: issuer,
          tokenSerial: serial.value)
      } catch {
        step(.certificate, .failed)
        throw error
      }
    }

    /// Completes exactly once and releases the delegate lifetime.
    private func complete(
      _ result: Result<Payload, any Error>,
      errorMessage: String? = nil
    ) {
      guard state.finish() else { return }
      if let errorMessage {
        session?.invalidate(errorMessage: errorMessage)
      } else {
        session?.alertMessage = String(localized: "Card identity read.")
        session?.invalidate()
      }
      session = nil
      continuation.resume(returning: result)
      lifetime = nil
    }
  }

#endif
