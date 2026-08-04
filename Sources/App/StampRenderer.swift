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
      /// The holder as a person reads it.
      internal let name: String

      /// The identifier stated under it.
      internal let identifier: String

      /// The holder's traced handwriting.
      internal let signature: SignatureArtwork.Artwork
    }

    /// The ring.
    private static let outerRadius = 64.0
    private static let innerRadius = 57.0
    private static let outerLineWidth = 1.8
    private static let innerLineWidth = 0.9

    /// The signature's width inside the ring, and the baseline it
    /// stands on.
    private static let signatureWidth = 86.0
    private static let baselineHalfWidth = 45.0
    private static let baselineDrop = 6.0
    private static let signatureLift = 2.0
    private static let baselineWidth = 1.2

    /// Type sizes.
    private static let nameSize = 5.0

    /// How far the name sits below the line the signature stands on.
    private static let nameDrop = 9.0

    /// Clear space kept between the name's ends and the inner circle.
    private static let nameMargin = 10.0

    /// How far the identifier sits below the name.
    private static let nameLineGap = 7.0

    /// The identifier's size, as a share of the name's.
    private static let identifierShare = 0.85

    /// The circle's Bezier constant: how far a control point sits
    /// along the tangent to approximate a quarter turn.
    private static let arcControl = 0.5523

    /// Quarter turns in a circle.
    private static let quarterTurns = 4

    /// The fallback advance for a character the font has no glyph
    /// for, as a fraction of the type size.
    private static let fallbackAdvanceShare = 0.5

    /// Degrees in a half turn, for turning degrees into radians.
    private static let halfTurnDegrees = 180.0

    /// The size glyphs are measured at before scaling, large enough
    /// that hinting cannot round the answer.
    private static let metricSize = 1_000.0

    /// Two, for the halves a centred thing is placed by.
    private static let halves = 2.0

    /// A quarter turn, which both arcs measure their rotations from.
    private static let quarterTurn = Double.pi / Self.halves

    /// The mark's colour, #B02020, as the fractions PDF wants.
    private static let inkColour = "0.6902 0.1255 0.1255"

    /// The furthest the ring is turned, in degrees.
    ///
    /// A rubber stamp is never put down square, and a mark that lands
    /// at exactly the same angle every time looks like what it is: a
    /// drawing.
    private static let maximumTilt = 15.0

    /// The page carrying the mark.
    internal static func mark(_ statement: Statement) -> StampMark {
      let centreX = 0.0
      let centreY = 0.0
      var body = "q\n\(Self.inkColour) RG \(Self.inkColour) rg\n"
      body += Self.tilt(about: (centreX, centreY))
      let centre = (x: centreX, y: centreY)
      body += Self.circle(
        centre: centre, radius: Self.outerRadius, lineWidth: Self.outerLineWidth
      )
      body += Self.circle(
        centre: centre, radius: Self.innerRadius, lineWidth: Self.innerLineWidth
      )
      body += Self.handwriting(statement.signature, centre: (centreX, centreY))
      body += Self.name(statement, centre: (centreX, centreY))
      body += "Q\nQ\n"
      return StampMark(radius: Self.outerRadius, operators: body)
    }

    /// One number, written the way PDF reads them.
    ///
    /// Swift writes a very small double as 3.9e-15, and PDF has no
    /// exponent notation - a reader meeting one either skips the
    /// operator or rejects the stream. Rounding sines and cosines of
    /// right angles to fixed places writes them as 0.0000, which is
    /// what they are.
    private static func number(_ value: Double) -> String {
      String(format: "%.4f", value)
    }

    /// A turn of up to `maximumTilt` degrees clockwise, about the
    /// ring's own centre, so no two stamps land at the same angle.
    private static func tilt(about centre: (x: Double, y: Double)) -> String {
      let degrees = Double.random(in: 0...Self.maximumTilt)
      let turn = -degrees * Double.pi / Self.halfTurnDegrees
      let cosine = cos(turn)
      let sine = sin(turn)
      let shiftX = centre.x - centre.x * cosine + centre.y * sine
      let shiftY = centre.y - centre.x * sine - centre.y * cosine
      return "q \(Self.number(cosine)) \(Self.number(sine))"
        + " \(Self.number(-sine)) \(Self.number(cosine))"
        + " \(Self.number(shiftX)) \(Self.number(shiftY)) cm\n"
    }

    /// The holder's handwriting, fitted to the line it stands on.
    ///
    /// Scaled and placed by where the ink is, not by the card image's
    /// box: the box has blank margins around the writing, and placing
    /// it puts the margins on the line and the writing wherever they
    /// leave it. The writing starts where the line starts and ends
    /// before it does.
    private static func handwriting(
      _ artwork: SignatureArtwork.Artwork,
      centre: (x: Double, y: Double)
    ) -> String {
      let inkWidth = artwork.inkRight - artwork.inkLeft
      guard inkWidth > 0 else { return "" }
      let room = Self.baselineHalfWidth * Self.halves
      let scale = room / inkWidth
      let left = centre.x - Self.baselineHalfWidth
      let sits = centre.y - Self.baselineDrop + Self.signatureLift
      // The operators are in the image's own coordinates, so the
      // translation carries the ink's own corner to the line's end.
      var body = "q \(Self.number(scale)) 0 0 \(Self.number(scale))"
      body += " \(Self.number(left - artwork.inkLeft * scale))"
      body += " \(Self.number(sits - artwork.inkBottom * scale)) cm\n"
      body += artwork.operators
      body += "Q\n"
      body += "\(Self.number(Self.baselineWidth)) w "
      body +=
        "\(Self.number(centre.x - Self.baselineHalfWidth))"
        + " \(Self.number(centre.y - Self.baselineDrop)) m "
      body +=
        "\(Self.number(centre.x + Self.baselineHalfWidth))"
        + " \(Self.number(centre.y - Self.baselineDrop)) l S\n"
      return body
    }

    /// The name, on two lines: who, then the identifier.
    ///
    /// A common name on this card reads "SURNAME FORENAME" and then
    /// the identifier. On one line it reads like a database row and
    /// has to shrink to fit; on two it reads like a signature block,
    /// and each line is short enough to stay legible.
    private static func name(
      _ statement: Statement,
      centre: (x: Double, y: Double)
    ) -> String {
      var body = Self.line(
        statement.name, centre: centre, drop: Self.nameDrop, size: Self.nameSize
      )
      guard !statement.identifier.isEmpty else { return body }
      body += Self.line(
        statement.identifier,
        centre: centre,
        drop: Self.nameDrop + Self.nameLineGap,
        size: Self.nameSize * Self.identifierShare
      )
      return body
    }

    /// One line of the name, shrunk to the ring's width at its own
    /// height: the chord narrows as the line sits lower, so the room
    /// is computed for each line rather than shared.
    private static func line(
      _ text: String,
      centre: (x: Double, y: Double),
      drop: Double,
      size: Double
    ) -> String {
      let baseline = centre.y - Self.baselineDrop - drop
      let height = abs(baseline - centre.y)
      guard height < Self.innerRadius else { return "" }
      let halfChord =
        (Self.innerRadius * Self.innerRadius - height * height).squareRoot()
      let room = halfChord * Self.halves - Self.nameMargin
      var chosen = size
      var drawn = TextOutline.line(text, font: "Helvetica", size: chosen)
      if drawn.width > room, drawn.width > 0 {
        chosen *= room / drawn.width
        drawn = TextOutline.line(text, font: "Helvetica", size: chosen)
      }
      return "q 1 0 0 1 \(Self.number(centre.x)) \(Self.number(baseline)) cm\n"
        + "\(drawn.operators)Q\n"
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
      var body = "\(Self.number(lineWidth)) w\n"
      body += "\(Self.number(centre.x + radius)) \(Self.number(centre.y)) m\n"
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
          "\(Self.number(leaving.x)) \(Self.number(leaving.y))"
          + " \(Self.number(arriving.x)) \(Self.number(arriving.y))"
          + " \(Self.number(end.x)) \(Self.number(end.y)) c\n"
      }
      return body + "h\nS\n"
    }
  }

#endif
