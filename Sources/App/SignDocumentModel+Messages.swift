#if os(macOS)

  import CardCore
  import Foundation

  extension SignDocumentModel {
    /// A signed portrait QR could not be turned into a printable mark.
    internal enum StampPreparationFailure: Error {
      case rendering
    }

    /// One sentence per failure.
    internal static func message(for error: Error) -> String {
      switch error {
      case DocumentSigner.Failure.card(let outcome):
        Self.cardMessage(outcome)
      case DocumentSigner.Failure.document(let failure):
        Self.documentMessage(failure)
      case DocumentSigner.Failure.network:
        "A timestamp or revocation service could not be reached. An "
          + "archival signature needs both, so nothing was written."
      case DocumentSigner.Failure.validation:
        "Complete authenticated certificate and revocation evidence could "
          + "not be collected. No signed file was written."
      case DocumentSigner.Failure.stampSignerChanged:
        "The card used for signing is not the card read for the stamp. "
          + "No signed file was written."
      case StampPreparationFailure.rendering:
        "The signed portrait QR could not be rendered. No signed file was written."
      case AsicSigner.Failure.container:
        "The signed container could not be written."
      case AsicSigner.Failure.signedOctetsChanged:
        "The card signed unexpected bytes. No signed file was written."
      default:
        "The document could not be signed."
      }
    }

    /// Structural PDF failures in terms a person can act on.
    private static func documentMessage(_ failure: PdfSigningError) -> String {
      switch failure {
      case .notAPdf:
        "That file is not a PDF."
      case .encrypted:
        "That PDF is encrypted; ReFineID will not modify it."
      case .crossReferenceStreamUnsupported:
        "That PDF uses a cross-reference stream, which this version "
          + "cannot extend yet."
      case .signatureTooLarge:
        "The signature did not fit the space reserved for it."
      default:
        "That PDF's structure could not be read."
      }
    }

    /// What the card said, in the same words the PIN window uses.
    private static func cardMessage(_ outcome: CardMaintenance.Outcome) -> String {
      switch outcome {
      case .rejected(let remaining):
        "Wrong PIN 2: \(remaining.attemptsRemaining) attempts remain."
      case .pinBlocked, .floorRefused(.refuseBlocked):
        "PIN 2 is blocked; unblock it in PIN Management."
      case .floorRefused(.refuseLowAttempts):
        "Only one or two attempts remain on PIN 2; ReFineID refuses to "
          + "spend a near-last attempt."
      case .invalidated:
        "The signature slot is not activated; activate the card first."
      case .noCard:
        "No readable card. Insert the card and try again."
      default:
        "The card refused the signature."
      }
    }
  }

#endif
