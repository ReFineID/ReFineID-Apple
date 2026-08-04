import Foundation
import Testing

@testable import ReFineID

/// Direct user-facing explanations for failures after the card signs.
@Suite
internal struct SignDocumentModelTests {
  private enum EvidenceFailure: Error {
    case unavailable
  }

  @Test
  @MainActor
  internal func validationFailureExplainsThatNoFileWasWritten() {
    let message = SignDocumentModel.message(
      for: DocumentSigner.Failure.validation(EvidenceFailure.unavailable)
    )

    #expect(message.contains("authenticated certificate and revocation"))
    #expect(message.contains("No signed file was written"))
  }
}
