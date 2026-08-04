#if os(macOS)

  import CardCore
  import CoreText
  import Foundation

  /// Draws the signature's visible mark: a ring carrying the article
  /// that gives the signature its effect, the holder's own handwriting
  /// inside it, and the name the certificate states underneath.
  ///
  /// Every part is vector. Nothing here is evidence - the signature is
  /// the evidence, and it is in the file - so the mark says what was
  /// signed and by whom, and claims nothing a reader could not check.
  internal enum StampRenderer {
    /// What the mark states.
    internal struct Statement {
      /// The article the signature takes its effect from, around the
      /// top of the ring.
      internal let ringTop: String

      /// Its citation, around the bottom.
      internal let ringBottom: String

      /// The common name the certificate states.
      internal let name: String

      /// The holder's traced handwriting.
      internal let signature: SignatureArtwork.Artwork

      /// The signed statement the code carries, when there is one.
      internal let attestation: QrCode.Modules?
    }

    /// The page the mark is drawn on, in points.
    private static let pageWidth = 320.0
    private static let pageHeight = 560.0

    /// The ring.
    private static let outerRadius = 64.0
    private static let innerRadius = 57.0
    private static let outerLineWidth = 1.8
    private static let innerLineWidth = 0.9

    /// How far a glyph's baseline sits from the ring it follows.
    private static let ringMargin = 1.6

    /// The signature's width inside the ring, and the baseline it
    /// stands on.
    private static let signatureWidth = 86.0
    private static let baselineHalfWidth = 45.0
    private static let baselineDrop = 6.0
    private static let signatureLift = 2.0
    private static let baselineWidth = 1.2

    /// Type sizes.
    private static let ringTextSize = 4.3
    private static let nameSize = 5.0

    /// How far the name sits below the line the signature stands on.
    private static let nameDrop = 9.0

    /// The circle's Bezier constant: how far a control point sits
    /// along the tangent to approximate a quarter turn.
    private static let arcControl = 0.5523

    /// Quarter turns in a circle.
    private static let quarterTurns = 4

    /// The fallback advance for a character the font has no glyph
    /// for, as a fraction of the type size.
    private static let fallbackAdvanceShare = 0.5

    /// Two, for the halves a centred thing is placed by.
    private static let halves = 2.0

    /// A quarter turn, which both arcs measure their rotations from.
    private static let quarterTurn = Double.pi / Self.halves

    /// The mark's colour, #0033A0, as the fractions PDF wants.
    private static let inkColour = "0.0 0.2 0.6275"

    /// The code's side, and how far it sits above the page's foot.
    ///
    /// Large on purpose. A code carrying a signature and a qualified
    /// timestamp needs a great many modules, and a phone camera needs
    /// each of them to be about half a millimetre - so the code is
    /// the size it has to be to scan, not the size that would look
    /// tidy.
    private static let codeSize = 190.0
    private static let codeMargin = 18.0

    /// The page carrying the mark.
    internal static func page(_ statement: Statement) -> StampPage {
      let centreX = Self.pageWidth / Self.halves
      let centreY = Self.pageHeight - Self.outerRadius - Self.nameDrop
      var body = "q\n\(Self.inkColour) RG \(Self.inkColour) rg\n"
      let centre = (x: centreX, y: centreY)
      body += Self.circle(
        centre: centre, radius: Self.outerRadius, lineWidth: Self.outerLineWidth
      )
      body += Self.circle(
        centre: centre, radius: Self.innerRadius, lineWidth: Self.innerLineWidth
      )
      // Top glyphs grow outward from their baseline and bottom glyphs
      // grow inward, so the two baselines sit on opposite sides of the
      // band to leave the same margin against both rings.
      body += Self.arcText(
        statement.ringTop,
        radius: Self.innerRadius + Self.ringMargin,
        centre: (centreX, centreY),
        overTheTop: true
      )
      body += Self.arcText(
        statement.ringBottom,
        radius: Self.outerRadius - Self.ringMargin,
        centre: (centreX, centreY),
        overTheTop: false
      )
      body += Self.handwriting(statement.signature, centre: (centreX, centreY))
      body += Self.name(statement.name, centre: (centreX, centreY))
      if let attestation = statement.attestation {
        body += QrCode.pdfOperators(
          attestation,
          size: Self.codeSize,
          atX: centreX - Self.codeSize / Self.halves,
          atY: Self.codeMargin
        )
      }
      body += "Q\n"
      return StampPage(
        width: Self.pageWidth, height: Self.pageHeight, operators: body
      )
    }

    /// The holder's handwriting, scaled into the ring and standing on
    /// a ruled line.
    private static func handwriting(
      _ artwork: SignatureArtwork.Artwork,
      centre: (x: Double, y: Double)
    ) -> String {
      let scale = Self.signatureWidth / artwork.width
      let left = centre.x - Self.signatureWidth / Self.halves
      var body = "q \(scale) 0 0 \(scale) \(left) \(centre.y - Self.signatureLift) cm\n"
      body += artwork.operators
      body += "Q\n"
      body += "\(Self.baselineWidth) w "
      body += "\(centre.x - Self.baselineHalfWidth) \(centre.y - Self.baselineDrop) m "
      body += "\(centre.x + Self.baselineHalfWidth) \(centre.y - Self.baselineDrop) l S\n"
      return body
    }

    /// The name, centred under the ring by measurement.
    private static func name(
      _ text: String,
      centre: (x: Double, y: Double)
    ) -> String {
      let width = Self.width(text, font: "Helvetica", size: Self.nameSize)
      // Under the line the signature stands on, inside the ring: the
      // hand above, the name it belongs to below.
      let baseline = centre.y - Self.baselineDrop - Self.nameDrop
      let left = centre.x - width / Self.halves
      return """
        BT /F1 \(Self.nameSize) Tf 1 0 0 1 \(left) \(baseline) Tm
        (\(Self.escaped(text))) Tj ET

        """
    }

    /// A circle, as four Bezier quarters.
    ///
    /// Each quarter's control points sit along the tangents at its
    /// ends, which is what makes four curves indistinguishable from a
    /// circle at any zoom.
    private static func circle(
      centre: (x: Double, y: Double),
      radius: Double,
      lineWidth: Double
    ) -> String {
      let pull = Self.arcControl * radius
      var body = "\(lineWidth) w\n\(centre.x + radius) \(centre.y) m\n"
      for quarter in 0..<Self.quarterTurns {
        let opens = Double(quarter) * Self.quarterTurn
        let closes = opens + Self.quarterTurn
        let start = (
          x: centre.x + radius * cos(opens), y: centre.y + radius * sin(opens)
        )
        let end = (
          x: centre.x + radius * cos(closes), y: centre.y + radius * sin(closes)
        )
        let leaving = (x: start.x - pull * sin(opens), y: start.y + pull * cos(opens))
        let arriving = (x: end.x + pull * sin(closes), y: end.y - pull * cos(closes))
        body +=
          "\(leaving.x) \(leaving.y) \(arriving.x) \(arriving.y)"
          + " \(end.x) \(end.y) c\n"
      }
      return body + "h\nS\n"
    }

    /// Glyphs laid along an arc at their measured widths.
    ///
    /// `overTheTop` places them for the top of the ring, heads
    /// outward, reading clockwise; otherwise they are turned to read
    /// left to right along the bottom.
    private static func arcText(
      _ text: String,
      radius: Double,
      centre: (x: Double, y: Double),
      overTheTop: Bool
    ) -> String {
      let widths = Self.advances(text, font: "Helvetica", size: Self.ringTextSize)
      let sweep = widths.reduce(0, +) / radius
      let half = Self.quarterTurn
      // The text is centred on the top or the bottom of the ring, so
      // it starts half its own sweep away from there.
      let fromCentre = sweep / Self.halves
      var angle = overTheTop ? half + fromCentre : -half - fromCentre
      var body = "BT /F1 \(Self.ringTextSize) Tf\n"
      for (index, character) in text.enumerated() {
        let step = widths[index] / radius
        let toGlyphMiddle = step / Self.halves
        let middle =
          overTheTop ? angle - toGlyphMiddle : angle + toGlyphMiddle
        let rotation = overTheTop ? middle - half : middle + half
        let placed =
          "\(cos(rotation)) \(sin(rotation))"
          + " \(-sin(rotation)) \(cos(rotation))"
          + " \(centre.x + radius * cos(middle))"
          + " \(centre.y + radius * sin(middle))"
        body += "\(placed) Tm (\(Self.escaped(String(character)))) Tj\n"
        angle += overTheTop ? -step : step
      }
      return body + "ET\n"
    }

    /// Each character's advance, measured rather than assumed, so the
    /// ring text is spaced the way the font intends.
    private static func advances(
      _ text: String,
      font: String,
      size: Double
    ) -> [Double] {
      let measured = CTFontCreateWithName(font as CFString, size, nil)
      return text.map { character in
        var glyph = CGGlyph(0)
        var codeUnits = Array(String(character).utf16)
        guard
          CTFontGetGlyphsForCharacters(
            measured, &codeUnits, &glyph, codeUnits.count
          )
        else {
          return size * Self.fallbackAdvanceShare
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(measured, .horizontal, &glyph, &advance, 1)
        return Double(advance.width)
      }
    }

    /// One string's width at a size.
    private static func width(
      _ text: String,
      font: String,
      size: Double
    ) -> Double {
      Self.advances(text, font: font, size: size).reduce(0, +)
    }

    /// A literal string's escapes.
    private static func escaped(_ text: String) -> String {
      text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
    }
  }

#endif
