// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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
    let partiallyTypedAccessNumber = "123"
    await model.readStamp(
      accessNumber: partiallyTypedAccessNumber,
      style: .signatureAndIdentity
    )
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
    model.accept(URL.temporaryDirectory.appendingPathComponent("next.pdf"))
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    let destination = URL.temporaryDirectory.appendingPathComponent("signed.pdf")
    model.complete(with: destination)
    #expect(model.stampMark() == nil)
    #expect(model.signed == destination)
  }

  @Test
  @MainActor
  internal func cardRemovalClearsFailureButKeepsTheChosenDocument() {
    let model = SignDocumentModel()
    let source = URL.temporaryDirectory.appendingPathComponent("waiting.pdf")
    model.accept(source)
    model.report("A card-bound failure")
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

    model.cardRemoved()

    #expect(model.failure == nil)
    #expect(model.pending == source)
    #expect(model.stampMark() == nil)
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

  /// A pile of PDFs keeps the shape that signs each one in place.
  ///
  /// PDFs are signed one by one and stored one by one; the container
  /// is what a set of other file types has no alternative to. A pile
  /// of PDFs that could only take the container shape would have lost
  /// the ordinary way of signing several PDFs at once.
  @Test
  @MainActor
  internal func severalPdfsAreStillSignedOneByOne() {
    let pdfs = [
      URL(fileURLWithPath: "/documents/One.pdf"),
      URL(fileURLWithPath: "/documents/Two.pdf"),
      URL(fileURLWithPath: "/documents/Three.pdf"),
    ]
    #expect(StatusView.sharedFormat(for: pdfs) == .pades)
    // And the choice is genuinely offered, not merely defaulted: the
    // same pile can be sent into one container instead.
    #expect(SignatureFormat.available(for: pdfs[0]).contains(.asice))
  }

  /// One file type among PDFs leaves the container as the only shape.
  @Test
  @MainActor
  internal func aMixedPileCanOnlyTakeTheContainer() {
    let mixed = [
      URL(fileURLWithPath: "/documents/One.pdf"),
      URL(fileURLWithPath: "/documents/Ledger.ods"),
    ]
    #expect(StatusView.sharedFormat(for: mixed) == .asice)
  }

  /// A container covering a set is offered no document's name.
  ///
  /// Whichever document was chosen first is not the set, and a name
  /// taken from it would read as a fact rather than as the guess it
  /// is. What survives is the signing instant, which is not a guess.
  @Test
  @MainActor
  internal func aContainerOfSeveralIsOfferedNoDocumentName() throws {
    let instant = try #require(
      DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026, month: 8, day: 12, hour: 14, minute: 30, second: 12
      ).date
    )
    let offered = SignDocumentModel.suggestedContainerName(at: instant)

    #expect(offered == " - signed at 2026-08-12T14-30-12Z.asice")
    // One document keeps its own name, which is not a guess at all.
    #expect(
      SignDocumentModel.destination(
        for: URL(fileURLWithPath: "/documents/Agreement.odt"),
        at: instant,
        format: .asice
      ).lastPathComponent == "Agreement - signed at 2026-08-12T14-30-12Z.asice"
    )
  }
}
