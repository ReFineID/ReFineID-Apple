// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// One localized failure vocabulary shared by macOS and iOS signing.
internal enum DocumentSigningMessage {
  internal static func message(for error: Error) -> String {
    switch error {
    case DocumentSigner.Failure.card(let outcome):
      cardMessage(outcome)
    case DocumentSigner.Failure.document(let failure):
      documentMessage(failure)
    case DocumentSigner.Failure.network:
      text(
        "error.network",
        "A timestamp or revocation service could not be reached. Nothing was written.")
    case DocumentSigner.Failure.validation(let evidence):
      validationMessage(evidence)
    case DocumentSigner.Failure.stampSignerChanged:
      text("error.cardChanged", "The signing card changed. Nothing was written.")
    case AsicSigner.Failure.container:
      text("error.container", "The signed container could not be written.")
    case AsicSigner.Failure.signedOctetsChanged:
      text(
        "error.unexpectedSignature",
        "The card signed unexpected data. Nothing was written.")
    case AsicSigner.Failure.unusableName:
      text(
        "error.names",
        "Two documents have the same name, or a name is reserved. Rename one and try again.")
    default:
      text("error.generic", "The documents could not be signed.")
    }
  }

  private static func cardMessage(_ outcome: CardMaintenance.Outcome) -> String {
    switch outcome {
    case .rejected(let remaining):
      CredentialOutcomeMessage.rejection(
        credentialName: "PIN 2", remaining: remaining)
    case .pinBlocked, .floorRefused(.refuseBlocked):
      text("error.pin2Blocked", "PIN 2 is blocked. Reset it in PIN settings.")
    case .floorRefused(.refuseLowAttempts):
      CredentialOutcomeMessage.lowAttemptRefusal()
    case .invalidated:
      text(
        "error.notActivated",
        "The signature PIN is not activated. Activate the card first.")
    case .noCard:
      text("error.noCard", "No readable identity card was found.")
    default:
      text("error.cardRefused", "The identity card refused the signature.")
    }
  }

  private static func documentMessage(_ failure: PdfSigningError) -> String {
    switch failure {
    case .notAPdf:
      text("error.notPDF", "The selected file is not a PDF.")
    case .encrypted:
      text("error.encryptedPDF", "That PDF is encrypted and cannot be modified.")
    case .crossReferenceStreamUnsupported:
      text(
        "error.pdfEncoding",
        "That PDF uses an unsupported cross-reference encoding.")
    case .signatureTooLarge:
      text("error.signatureTooLarge", "The signature did not fit in the PDF.")
    default:
      text("error.pdfStructure", "That PDF structure could not be read.")
    }
  }

  private static func validationMessage(_ failure: Error) -> String {
    switch failure {
    case ValidationMaterialCollector.Failure.revoked(.documentSigner):
      text("error.cardRevoked", "The card is revoked and cannot sign.")
    case ValidationMaterialCollector.Failure.revoked(.timestampAuthority):
      text(
        "error.timestampRevoked",
        "The timestamp service certificate is revoked.")
    default:
      text(
        "error.validation",
        "Authenticated certificate and revocation evidence could not be collected.")
    }
  }

  private static func text(
    _ key: StaticString,
    _ fallback: String.LocalizationValue
  ) -> String {
    String(localized: key, defaultValue: fallback, table: "DocumentSigning")
  }
}
