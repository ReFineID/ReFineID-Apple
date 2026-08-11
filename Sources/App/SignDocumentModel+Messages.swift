// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
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
