// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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

    /// Everything dropped in one go, in the order it will be signed.
    ///
    /// A day's work arrives together, and signing it one file at a
    /// time means one drop, one panel and one PIN for each.
    internal private(set) var queued: [URL] = []

    /// What became of each document of a batch, as sentences.
    internal private(set) var batchOutcomes: [String] = []

    /// Whether a signature is in flight.
    internal private(set) var working = false

    /// What went wrong, as one user-facing sentence.
    internal private(set) var failure: String?

    /// Where the signed file landed.
    internal private(set) var signed: URL?

    /// The complete visible statement read from the card, with
    /// handwriting when the card carries it and identity alone otherwise.
    internal private(set) var stampState: DocumentStampState?

    /// Changes whenever the card leaves, invalidating card work already
    /// awaiting an answer without cancelling work that may still complete.
    @ObservationIgnored private var cardAppearance = 0

    /// A non-fatal note about what the visible stamp could contain.
    internal private(set) var stampFailure: String?

    /// A non-fatal fact the holder must see beside the signed output.
    internal private(set) var notice: String?

    /// Whether the card is being read for the signature right now.
    internal private(set) var readingStamp = false

    /// Whether the last sign action produced at least one signature.
    ///
    /// The one thing the PIN 2 cache needs to know: a PIN it should
    /// remember is one a signature accepted. Reset when an action
    /// begins, set as each document completes.
    internal private(set) var lastActionSignedSomething = false

    /// Adds documents to the pile, ignoring ones already in it.
    ///
    /// Dropping again piles onto what is there rather than replacing
    /// it, so a stack of documents is built up and signed in one pass.
    /// The newest addition is the one whose options are shown; the
    /// rest are signed with the same choices.
    internal func accept(_ urls: [URL]) {
      let present = Set(queued.map(\.standardizedFileURL))
      let additions = urls.filter { !present.contains($0.standardizedFileURL) }
      queued.append(contentsOf: additions)
      batchOutcomes = []
      guard let focus = additions.first ?? urls.first else { return }
      accept(focus)
    }

    /// Marks the start of one sign action, so acceptance is judged
    /// over the whole action rather than the last document alone.
    internal func beginAction() {
      lastActionSignedSomething = false
    }

    /// Empties the pile once its documents are signed, keeping the
    /// outcome on screen.
    internal func clearQueue() {
      queued = []
      pending = nil
    }

    /// Points the model at one document of a batch.
    internal func focus(on url: URL) {
      pending = url
    }

    /// Records what became of each document of a batch.
    internal func record(batch outcomes: [String]) {
      batchOutcomes = outcomes
    }

    /// Accepts a dropped or chosen file.
    internal func accept(_ url: URL) {
      if queued.isEmpty {
        queued = [url]
      }
      pending = url
      failure = nil
      signed = nil
      stampState = nil
      stampFailure = nil
      notice = nil
    }

    /// The page mark built from the identity the card supplied.
    internal func stampMark() -> StampMark? {
      stampState.map { StampRenderer.mark($0.statement) }
    }

    /// Reads the stamp identity and any handwritten signature off the card.
    ///
    /// Only a complete access number is taken to the card. A number
    /// is six digits, so anything shorter is not a wrong number, it
    /// is a number still being typed - reading it would refuse the
    /// holder's own card and say so while they were mid-entry.
    /// Reads only the data groups the chosen style needs.
    internal func readStamp(
      accessNumber digits: String,
      style: DocumentStampStyle
    ) async {
      guard digits.count == CardAccessNumber.digitCount else {
        stampState = nil
        stampFailure = nil
        return
      }
      guard !readingStamp else { return }
      readingStamp = true
      stampState = nil
      stampFailure = nil
      let appearance = cardAppearance
      defer { readingStamp = false }
      let outcome = await CardMaintenance.displayedSignature(
        accessNumber: digits,
        includePortrait: style.readsPortrait
      )
      guard appearance == cardAppearance else { return }
      applyStampOutcome(outcome)
    }

    /// Applies one card read atomically, so a failure can never retain
    /// another card holder's visible identity.
    internal func applyStampOutcome(
      _ outcome: CardMaintenance.SignatureOutcome
    ) {
      stampState = nil
      stampFailure = nil
      switch outcome {
      case .mark(let mark):
        let artwork: SignatureArtwork.Artwork?
        if let bytes = mark.bytes {
          guard let traced = SignatureArtwork.traced(bytes) else {
            stampFailure = String(
              localized: "The signature image could not be read."
            )
            return
          }
          artwork = traced
        } else {
          artwork = nil
          stampFailure = String(
            localized:
              "No handwritten signature; the stamp will show the certificate identity."
          )
        }
        stampState = DocumentStampState(
          statement: StampRenderer.Statement(
            name: mark.name,
            identifier: mark.identifier,
            signature: artwork,
            givenName: mark.givenName,
            surname: mark.surname
          ),
          signerCertificate: mark.certificate,
          portrait: mark.portrait
        )
      case .absent:
        stampFailure = String(
          localized: "The certificate identity could not be read."
        )
      case .imageUnreadable:
        stampFailure = String(
          localized:
            "The handwritten signature could not be read; no visible stamp was added."
        )
      case .wrongAccessNumber:
        stampFailure = String(
          localized: "That card access number was refused."
        )
      case .noCard:
        stampFailure = String(localized: "No readable card.")
      }
    }

    /// Forgets the pending file and any outcome.
    internal func clear() {
      pending = nil
      queued = []
      batchOutcomes = []
      failure = nil
      signed = nil
      stampState = nil
      stampFailure = nil
      notice = nil
    }

    /// Starts one signing attempt and captures its card appearance.
    private func beginSigning() -> Int {
      working = true
      failure = nil
      signed = nil
      notice = nil
      return cardAppearance
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
      format: SignatureFormat,
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
      let appearance = beginSigning()
      defer { working = false }
      do {
        switch format {
        case .asice:
          try await signContainer(source, pin2: pin2, to: destination)
        case .pades:
          try await signPdf(
            source, pin2: pin2, accessNumber: accessNumber, to: destination
          )
        }
        complete(with: destination)
      } catch {
        report(error, from: appearance)
      }
    }

    /// One ASiC-E signature: the file as it is, no visible stamp -
    /// the container carries the file unchanged, so there is no signed
    /// revision to draw a mark into.
    private func signContainer(
      _ source: URL,
      pin2: String,
      to destination: URL
    ) async throws {
      let document = try Data(contentsOf: source)
      let container = try await AsicSigner.sign(
        document,
        named: source.lastPathComponent,
        pin2: pin2
      )
      try container.write(to: destination, options: .atomic)
    }

    /// One PAdES signature, with the optional visible stamp.
    private func signPdf(
      _ source: URL,
      pin2: String,
      accessNumber: String,
      to destination: URL
    ) async throws {
      let stampStyle = DocumentStampStyle.load()
      // The card is read for the mark here, where the holder has
      // asked for a signature - not while they were still typing the
      // number that unlocks it.
      await readStamp(accessNumber: accessNumber, style: stampStyle)
      let document = try Data(contentsOf: source)
      let signedAt = Date()
      let visibleStamp = try await self.signedVisibleStamp(
        on: document,
        source: source,
        pin2: pin2,
        at: signedAt,
        style: stampStyle
      )
      #if DEBUG
        let reason =
          DebugRevokedDocumentSigning.isEnabled()
          ? DebugRevokedDocumentSigning.reason : nil
      #else
        let reason: String? = nil
      #endif
      let pdfClaim = PdfIncrementalSigner.SignatureClaim(
        signedAt: signedAt,
        reason: reason,
        location: nil
      )
      let result = try await DocumentSigner.sign(
        document,
        pin2: pin2,
        claim: pdfClaim,
        stamp: visibleStamp
      )
      try result.bytes.write(to: destination, options: .atomic)
      #if DEBUG
        if result.completion == .revokedSignerTest {
          notice = DebugRevokedDocumentSigning.warning
        }
      #endif
    }

    /// Records a completed write and releases the card identity state.
    internal func complete(with destination: URL) {
      signed = destination
      pending = nil
      stampState = nil
      stampFailure = nil
      lastActionSignedSomething = true
    }

    /// Reports a failure raised before the card was reached.
    internal func report(_ message: String) {
      failure = message
      signed = nil
      notice = nil
    }

    /// Removes outcomes and identity tied to a card that is no longer there.
    ///
    /// The chosen document remains ready for the next insertion.
    internal func cardRemoved() {
      cardAppearance &+= 1
      failure = nil
      stampState = nil
      stampFailure = nil
    }

    /// Publishes a signing failure only while its card is still present.
    private func report(_ error: Error, from appearance: Int) {
      guard appearance == cardAppearance else { return }
      failure = Self.message(for: error)
    }
  }

#endif
