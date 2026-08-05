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
    /// One visible statement and the exact certificate that states it.
    private struct StampState {
      let statement: StampRenderer.Statement
      let signerCertificate: Data
      let portrait: Data?
    }

    /// The document waiting to be signed.
    internal private(set) var pending: URL?

    /// Whether a signature is in flight.
    internal private(set) var working = false

    /// What went wrong, as one user-facing sentence.
    internal private(set) var failure: String?

    /// Where the signed file landed.
    internal private(set) var signed: URL?

    /// The complete visible statement read from the card, with
    /// handwriting when the card carries it and identity alone otherwise.
    private var stampState: StampState?

    /// A non-fatal note about what the visible stamp could contain.
    internal private(set) var stampFailure: String?

    /// A non-fatal fact the holder must see beside the signed output.
    internal private(set) var notice: String?

    /// Whether the card is being read for the signature right now.
    internal private(set) var readingStamp = false

    /// Reuses the exact certificate names captured with the card portrait.
    private static func portraitStatement(
      from state: StampState,
      qrPortrait: QrPortrait.Artwork
    ) -> StampRenderer.Statement {
      StampRenderer.Statement(
        name: state.statement.name,
        identifier: state.statement.identifier,
        signature: state.statement.signature,
        qrPortrait: qrPortrait,
        givenName: state.statement.givenName,
        surname: state.statement.surname
      )
    }

    /// Accepts a dropped or chosen file.
    internal func accept(_ url: URL) {
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
    internal func readStamp(accessNumber digits: String) async {
      guard digits.count == CardAccessNumber.digitCount else {
        stampState = nil
        stampFailure = nil
        return
      }
      guard !readingStamp else { return }
      readingStamp = true
      stampState = nil
      stampFailure = nil
      defer { readingStamp = false }
      applyStampOutcome(
        await CardMaintenance.displayedSignature(accessNumber: digits)
      )
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
        stampState = StampState(
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
      failure = nil
      signed = nil
      stampState = nil
      stampFailure = nil
      notice = nil
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
      notice = nil
      // The card is read for the mark here, where the holder has
      // asked for a signature - not while they were still typing the
      // number that unlocks it.
      await readStamp(accessNumber: accessNumber)
      defer { working = false }
      do {
        let document = try Data(contentsOf: source)
        let signedAt = Date()
        let visibleStamp = try await self.signedVisibleStamp(
          on: document,
          source: source,
          pin2: pin2,
          at: signedAt
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
        complete(with: destination)
      } catch {
        failure = Self.message(for: error)
      }
    }

    /// The placed mark and the exact certificate identity it states.
    internal func visibleStamp(on document: Data) -> DocumentSigner.VisibleStamp? {
      guard let state = stampState else { return nil }
      let rendered = StampRenderer.mark(state.statement)
      guard let placed = StampPlacement.placed(rendered, on: document) else {
        return nil
      }
      return DocumentSigner.VisibleStamp(
        mark: placed,
        signerCertificate: state.signerCertificate
      )
    }

    /// The portrait QR path, falling back to the existing mark when the
    /// card supplied no portrait or no handwriting.
    private func signedVisibleStamp(
      on document: Data,
      source: URL,
      pin2: String,
      at instant: Date
    ) async throws -> DocumentSigner.VisibleStamp? {
      guard let state = stampState else { return nil }
      guard
        let portraitBytes = state.portrait,
        let claim = StampAttestation.claim(
          identifier: state.statement.identifier,
          filename: source.lastPathComponent,
          at: instant
        )
      else {
        return self.visibleStamp(on: document)
      }
      let payload = try await DocumentSigner.attestation(
        over: claim,
        pin2: pin2,
        expectedCertificate: state.signerCertificate
      )
      guard
        let qrCode = QrCode.modules(of: payload),
        let fieldSide = StampRenderer.portraitFieldSide(
          forQrSide: qrCode.side
        ),
        let portrait = PortraitHalftone.map(
          imageData: portraitBytes,
          side: qrCode.side,
          fieldSide: fieldSide
        ),
        let qrPortrait = QrPortrait.artwork(qr: qrCode, portrait: portrait)
      else {
        throw StampPreparationFailure.rendering
      }
      let rendered = StampRenderer.mark(
        Self.portraitStatement(
          from: state,
          qrPortrait: qrPortrait
        )
      )
      guard
        let placed = StampPlacement.placed(
          rendered,
          on: document,
          minimumShare: 1
        )
      else { return nil }
      return DocumentSigner.VisibleStamp(
        mark: placed,
        signerCertificate: state.signerCertificate
      )
    }

    /// Records a completed write and releases the card identity state.
    internal func complete(with destination: URL) {
      signed = destination
      pending = nil
      stampState = nil
      stampFailure = nil
    }

    /// Reports a failure raised before the card was reached.
    internal func report(_ message: String) {
      failure = message
      signed = nil
      notice = nil
    }
  }

#endif
