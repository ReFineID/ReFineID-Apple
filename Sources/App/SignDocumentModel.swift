#if os(macOS)

  import CardCore
  import Foundation
  import Observation

  /// State for signing one document: the file chosen, the PIN2 entry,
  /// and what happened.
  ///
  /// The signed file lands beside the original, named for the instant
  /// it was signed, so signing twice never overwrites and the order is
  /// readable from the directory listing.
  @MainActor
  @Observable
  internal final class SignDocumentModel {
    /// The document waiting to be signed.
    internal private(set) var pending: URL?

    /// Whether a signature is in flight.
    internal private(set) var working = false

    /// What went wrong, as one user-facing sentence.
    internal private(set) var failure: String?

    /// Where the signed file landed.
    internal private(set) var signed: URL?

    /// The traced signature read from the card, when a card access
    /// number was given and the card carried one.
    internal private(set) var stamp: SignatureArtwork.Artwork?

    /// Why the stamp could not be read, as one user-facing sentence.
    internal private(set) var stampFailure: String?

    /// Why the signed document carries no code, kept beside the
    /// outcome rather than beside the entry field: the field goes
    /// away with the document, and a message that vanishes with it
    /// is a message nobody read.
    internal private(set) var codeFailure: String?

    /// Whether the card is being read for the signature right now.
    internal private(set) var readingStamp = false

    /// The common name the card's qualified certificate states, read
    /// beside the signature image.
    private var signerName: String?

    /// The identifier that goes under it.
    private var signerIdentifier = ""

    /// The signed file's place: beside the original, stamped with the
    /// UTC instant, colons replaced so the name is safe everywhere.
    nonisolated internal static func destination(
      for source: URL,
      at instant: Date
    ) -> URL {
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime]
      let instantText = formatter.string(from: instant)
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "+00-00", with: "Z")
      let name = source.deletingPathExtension().lastPathComponent
      return source.deletingLastPathComponent()
        .appendingPathComponent("\(name) - signed at \(instantText)")
        .appendingPathExtension(source.pathExtension)
    }

    /// The name a signed document should be offered under: the
    /// original's, with the instant it was signed.
    nonisolated internal static func suggestedName(for source: URL) -> String {
      Self.destination(for: source, at: Date()).lastPathComponent
    }

    /// One sentence per failure.
    internal static func message(for error: Error) -> String {
      switch error {
      case DocumentSigner.Failure.card(let outcome):
        Self.cardMessage(outcome)
      case DocumentSigner.Failure.document(.notAPdf):
        "That file is not a PDF."
      case DocumentSigner.Failure.document(.encrypted):
        "That PDF is encrypted; ReFineID will not modify it."
      case DocumentSigner.Failure.document(.crossReferenceStreamUnsupported):
        "That PDF uses a cross-reference stream, which this version "
          + "cannot extend yet."
      case DocumentSigner.Failure.document(.signatureTooLarge):
        "The signature did not fit the space reserved for it."
      case DocumentSigner.Failure.document:
        "That PDF's structure could not be read."
      case DocumentSigner.Failure.network:
        "A timestamp or revocation service could not be reached. An "
          + "archival signature needs both, so nothing was written."
      case DocumentSigner.Failure.validation:
        "Complete authenticated certificate and revocation evidence could "
          + "not be collected. No signed file was written."
      default:
        "The document could not be signed."
      }
    }

    /// What the card said, in the same words the PIN window uses.
    private static func cardMessage(_ outcome: CardMaintenance.Outcome) -> String {
      switch outcome {
      case .rejected(let remaining):
        "Wrong PIN2: \(remaining.attemptsRemaining) attempts remain."
      case .pinBlocked, .floorRefused(.refuseBlocked):
        "PIN2 is blocked; unblock it in PIN Management."
      case .floorRefused(.refuseLowAttempts):
        "Only one or two attempts remain on PIN2; ReFineID refuses to "
          + "spend a near-last attempt."
      case .invalidated:
        "The signature slot is not activated; activate the card first."
      case .noCard:
        "No readable card. Insert the card and try again."
      default:
        "The card refused the signature."
      }
    }
    /// Accepts a dropped or chosen file.
    internal func accept(_ url: URL) {
      pending = url
      failure = nil
      signed = nil
    }

    /// The page the mark goes on, when a signature was read from the
    /// card, and nothing when none was.
    private func stampMark() -> StampMark? {
      guard let stamp, let name = signerName else { return nil }
      return StampRenderer.mark(
        StampRenderer.Statement(
          name: name,
          identifier: signerIdentifier,
          signature: stamp
        )
      )
    }

    /// Reads the holder's handwritten signature off the card and
    /// traces it, so the stamp can be seen before anything is signed.
    ///
    /// Only a complete access number is taken to the card. A number
    /// is six digits, so anything shorter is not a wrong number, it
    /// is a number still being typed - reading it would refuse the
    /// holder's own card and say so while they were mid-entry.
    internal func readStamp(accessNumber digits: String) async {
      guard digits.count == CardAccessNumber.digitCount else {
        stamp = nil
        stampFailure = nil
        return
      }
      guard !readingStamp else { return }
      readingStamp = true
      stampFailure = nil
      defer { readingStamp = false }
      switch await CardMaintenance.displayedSignature(accessNumber: digits) {
      case .image(let mark):
        signerName = mark.name
        signerIdentifier = mark.identifier
        stamp = SignatureArtwork.traced(mark.bytes)
        stampFailure =
          stamp == nil
          ? String(localized: "The signature image could not be read.") : nil
      case .absent:
        stamp = nil
        stampFailure = String(
          localized: "This card carries no handwritten signature."
        )
      case .wrongAccessNumber:
        stamp = nil
        stampFailure = String(
          localized: "That card access number was refused."
        )
      case .noCard:
        stamp = nil
        stampFailure = String(localized: "No readable card.")
      }
    }

    /// Forgets the pending file and any outcome.
    internal func clear() {
      pending = nil
      failure = nil
      signed = nil
      stamp = nil
      stampFailure = nil
    }

    /// Signs the pending document into `destination`.
    ///
    /// Where it goes is decided by the caller, before this is called
    /// and before the card is touched: the sandbox the App Store
    /// requires hands this app a dropped file and not the folder
    /// around it, so the write has to be granted through a save panel,
    /// and a panel raised after signing could be cancelled with a PIN2
    /// signature already spent.
    internal func sign(
      pin2: String,
      accessNumber: String,
      to destination: URL
    ) async {
      guard let source = pending, !working else { return }
      // Replacing the original is refused rather than confirmed. It
      // destroys the only unsigned copy, and the signature is taken
      // over bytes already read into memory - so the file that
      // vanished would be the one the signature attests.
      guard destination.standardizedFileURL != source.standardizedFileURL else {
        failure = String(
          localized: "The signed document cannot replace the original."
        )
        return
      }
      working = true
      failure = nil
      signed = nil
      codeFailure = nil
      // The card is read for the mark here, where the holder has
      // asked for a signature - not while they were still typing the
      // number that unlocks it.
      await readStamp(accessNumber: accessNumber)
      defer { working = false }
      do {
        let document = try Data(contentsOf: source)
        let page = stampedMark()
        let result = try await DocumentSigner.sign(
          document,
          pin2: pin2,
          reason: nil,
          location: nil,
          stamp: page
        )
        try result.write(to: destination, options: .atomic)
        signed = destination
        pending = nil
      } catch {
        failure = Self.message(for: error)
      }
    }

    /// The mark, when the card gave a signature to stamp with.
    private func stampedMark() -> StampMark? {
      stampMark()
    }

    /// Reports a failure raised before the card was reached.
    internal func report(_ message: String) {
      failure = message
      signed = nil
    }
  }

#endif
