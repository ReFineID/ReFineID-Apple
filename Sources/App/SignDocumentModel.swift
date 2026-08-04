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

    /// The signed file's place: beside the original, stamped with the
    /// UTC instant, colons replaced so the name is safe everywhere.
    internal static func destination(for source: URL, at instant: Date) -> URL {
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime]
      let stamp = formatter.string(from: instant)
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "+00-00", with: "Z")
      let name = source.deletingPathExtension().lastPathComponent
      return source.deletingLastPathComponent()
        .appendingPathComponent("\(name) - signed at \(stamp)")
        .appendingPathExtension(source.pathExtension)
    }

    /// One sentence per failure.
    private static func message(for error: Error) -> String {
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

    /// Forgets the pending file and any outcome.
    internal func clear() {
      pending = nil
      failure = nil
      signed = nil
    }

    /// Signs the pending document with the entered PIN2.
    internal func sign(pin2: String) async {
      guard let source = pending, !working else { return }
      working = true
      failure = nil
      signed = nil
      defer { working = false }
      do {
        let document = try Data(contentsOf: source)
        let result = try await DocumentSigner.sign(
          document, pin2: pin2, reason: nil, location: nil
        )
        let destination = Self.destination(for: source, at: Date())
        try result.write(to: destination, options: .atomic)
        signed = destination
        pending = nil
      } catch {
        failure = Self.message(for: error)
      }
    }
  }

#endif
