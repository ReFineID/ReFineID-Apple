// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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
      case DocumentSigner.Failure.validation(let evidence):
        Self.validationMessage(evidence)
      case DocumentSigner.Failure.stampSignerChanged:
        "The card used for signing is not the card read for the stamp. "
          + "No signed file was written."
      case StampPreparationFailure.rendering:
        "The signed portrait QR could not be rendered. No signed file was written."
      case AsicSigner.Failure.container:
        "The signed container could not be written."
      case AsicSigner.Failure.signedOctetsChanged:
        "The card signed unexpected bytes. No signed file was written."
      case AsicSigner.Failure.unusableName:
        "Two documents share a file name, or one uses a name the "
          + "container reserves. Rename one and try again."
      default:
        "The document could not be signed."
      }
    }

    /// Evidence failures: the revoked verdicts by name, the rest as
    /// what they are.
    ///
    /// "Revoked" is an authenticated answer, not a collection
    /// problem, and the message says the fact instead of describing
    /// the machinery that learned it.
    private static func validationMessage(_ failure: Error) -> String {
      switch failure {
      case ValidationMaterialCollector.Failure.revoked(.documentSigner):
        "The card is revoked and cannot sign. No signed file was written."
      case ValidationMaterialCollector.Failure.revoked(.timestampAuthority):
        "The timestamp service's certificate is revoked. "
          + "No signed file was written."
      default:
        "Complete authenticated certificate and revocation evidence could "
          + "not be collected. No signed file was written."
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
        "That PDF's cross-reference data uses an encoding this "
          + "version cannot read."
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
        CredentialOutcomeMessage.rejection(
          credentialName: "PIN 2",
          remaining: remaining)
      case .pinBlocked, .floorRefused(.refuseBlocked):
        "PIN 2 is blocked; reset it in the PIN settings."
      case .floorRefused(.refuseLowAttempts):
        CredentialOutcomeMessage.lowAttemptRefusal()
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
