#if os(macOS)

  import CoreGraphics
  import CoreText
  import Foundation

  /// Turns a line of text into PDF path operators.
  ///
  /// The stamp draws no text, only shapes. A page's font resources
  /// belong to the document, not to a mark laid over it, and every
  /// font-shaped thing on this stamp has gone wrong at least once:
  /// accents written in one encoding and read in another, advances
  /// measured at a size where they come back rounded, a font name a
  /// page might already mean something else by. Outlines have none of
  /// those failure modes and render identically in every reader.
  ///
  /// What is given up is selectable, searchable text. For a mark that
  /// is a picture of a rubber stamp, that is the right side of the
  /// trade.
  internal enum TextOutline {
    /// A traced line: its operators, centred on the origin, and how
    /// wide it came out.
    internal struct Line {
      /// Operators filling the glyphs.
      internal let operators: String

      /// The line's width at the requested size.
      internal let width: Double
    }

    /// The size glyphs are measured and traced at, large enough that
    /// hinting cannot round the answer; the caller scales down.
    private static let traceSize = 1_000.0

    /// Places digits after the decimal point in emitted coordinates.
    private static let decimals = 2

    /// Halves, for centring a line on the origin.
    private static let halves = 2.0

    /// Where a curve's points sit in the element it belongs to.
    private static let firstPoint = 0
    private static let secondPoint = 1
    private static let thirdPoint = 2

    /// Traces one line, centred horizontally on the origin and
    /// sitting on it.
    internal static func line(
      _ text: String,
      font: String,
      size: Double
    ) -> Line {
      let traced = CTFontCreateWithName(font as CFString, Self.traceSize, nil)
      let scale = size / Self.traceSize
      var body = ""
      var pen = 0.0
      for character in text {
        var glyph = CGGlyph(0)
        var codeUnits = Array(String(character).utf16)
        guard
          CTFontGetGlyphsForCharacters(
            traced, &codeUnits, &glyph, codeUnits.count
          )
        else {
          continue
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(traced, .horizontal, &glyph, &advance, 1)
        if let path = CTFontCreatePathForGlyph(traced, glyph, nil) {
          body += Self.operators(of: path, offsetBy: pen)
        }
        pen += Double(advance.width)
      }
      let width = pen * scale
      // Scaled here rather than by the caller, so the line arrives in
      // the coordinates it will be drawn in.
      let placed = "q \(scale) 0 0 \(scale) \(-width / Self.halves) 0 cm\n\(body)Q\n"
      return Line(operators: placed, width: width)
    }

    /// One glyph's path as operators, shifted along the line.
    private static func operators(of path: CGPath, offsetBy pen: Double) -> String {
      var body = ""
      path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
          body += "\(Self.at(points[Self.firstPoint], pen)) m\n"
        case .addLineToPoint:
          body += "\(Self.at(points[Self.firstPoint], pen)) l\n"
        case .addQuadCurveToPoint:
          body +=
            "\(Self.at(points[Self.firstPoint], pen)) \(Self.at(points[Self.secondPoint], pen)) v\n"
        case .addCurveToPoint:
          body +=
            "\(Self.at(points[Self.firstPoint], pen)) \(Self.at(points[Self.secondPoint], pen))"
            + " \(Self.at(points[Self.thirdPoint], pen)) c\n"
        case .closeSubpath:
          body += "h\n"
        @unknown default:
          break
        }
      }
      return body.isEmpty ? "" : body + "f\n"
    }

    /// One point, shifted and rounded.
    private static func at(_ point: CGPoint, _ pen: Double) -> String {
      String(
        format: "%.\(Self.decimals)f %.\(Self.decimals)f",
        Double(point.x) + pen,
        Double(point.y)
      )
    }
  }

#endif
