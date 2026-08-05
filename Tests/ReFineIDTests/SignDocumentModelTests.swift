import AppKit
import Foundation
import Testing

@testable import ReFineID

/// Direct user-facing explanations for failures after the card signs.
@Suite
internal struct SignDocumentModelTests {
  private enum EvidenceFailure: Error {
    case unavailable
  }

  private static let stampCertificate = Data("stamp-certificate".utf8)

  /// A tiny synthetic signature image with ink surrounded by paper.
  private static func handwritingImage() throws -> Data {
    let side = 4
    let image = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    for across in 0..<side {
      for upward in 0..<side {
        let isInk = (1...2).contains(across) && (1...2).contains(upward)
        image.setColor(isInk ? .black : .white, atX: across, y: upward)
      }
    }
    return try #require(image.representation(using: .png, properties: [:]))
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

  @Test
  @MainActor
  internal func certificateIdentityProducesAStampWithoutHandwriting() throws {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: nil,
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    let mark = try #require(model.stampMark())
    #expect(mark.operators.contains("0.0000 5.0000 cm"))
    #expect(mark.operators.contains("0.0000 -10.0000 cm"))
    #expect(model.stampFailure?.contains("certificate identity") == true)
    #expect(
      model.visibleStamp(on: Data())?.signerCertificate
        == Self.stampCertificate
    )
  }

  @Test
  @MainActor
  internal func failedOrClearedReadCannotReuseAStampedIdentity() async {
    let model = SignDocumentModel()
    let identity = CardMaintenance.SignatureOutcome.mark(
      CardMaintenance.Mark(
        bytes: nil,
        certificate: Self.stampCertificate,
        name: "Example Person",
        identifier: "TEST-IDENTIFIER"
      )
    )

    model.applyStampOutcome(identity)
    #expect(model.stampMark() != nil)
    model.applyStampOutcome(.wrongAccessNumber)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.noCard)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.absent)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.imageUnreadable)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    await model.readStamp(accessNumber: "123")
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.clear()
    #expect(model.stampMark() == nil)
  }

  @Test
  @MainActor
  internal func malformedHandwritingCannotLeaveAnIdentityStamp() {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: Data("not an image".utf8),
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    #expect(model.stampMark() == nil)
    #expect(model.stampFailure?.contains("image could not be read") == true)
  }

  @Test
  @MainActor
  internal func validHandwritingKeepsTheCertificateBinding() throws {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: try Self.handwritingImage(),
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    let stamp = try #require(model.visibleStamp(on: Data()))
    #expect(stamp.signerCertificate == Self.stampCertificate)
    #expect(stamp.mark.operators.contains("-45.0000 -6.0000 m"))
    #expect(model.stampFailure == nil)
  }

  @Test
  @MainActor
  internal func changingOrCompletingADocumentClearsTheStampIdentity() {
    let model = SignDocumentModel()
    let identity = CardMaintenance.SignatureOutcome.mark(
      CardMaintenance.Mark(
        bytes: nil,
        certificate: Self.stampCertificate,
        name: "Example Person",
        identifier: "TEST-IDENTIFIER"
      )
    )

    model.applyStampOutcome(identity)
    model.accept(URL(fileURLWithPath: "/tmp/next.pdf"))
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    let destination = URL(fileURLWithPath: "/tmp/signed.pdf")
    model.complete(with: destination)
    #expect(model.stampMark() == nil)
    #expect(model.signed == destination)
  }

  @Test
  internal func qualifiedCertificateBindingRequiresTheExactDer() {
    let other = Data("other-certificate".utf8)

    #expect(
      CardMaintenance.qualifiedCertificate(
        Self.stampCertificate, matches: Self.stampCertificate
      )
    )
    #expect(
      !CardMaintenance.qualifiedCertificate(
        other, matches: Self.stampCertificate
      )
    )
    #expect(CardMaintenance.qualifiedCertificate(other, matches: nil))
  }

  @Test
  @MainActor
  internal func signerChangeExplainsThatNoFileWasWritten() {
    let message = SignDocumentModel.message(
      for: DocumentSigner.Failure.stampSignerChanged
    )

    #expect(message.contains("not the card read for the stamp"))
    #expect(message.contains("No signed file was written"))
  }
}
