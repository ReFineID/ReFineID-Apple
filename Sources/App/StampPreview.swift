#if os(macOS)

  import AppKit
  import SwiftUI

  /// Draws the traced signature, so the stamp can be seen before
  /// anything is signed.
  ///
  /// The same outlines that will be written into the page are drawn
  /// here - not the card's bitmap - so what is shown is what the
  /// document will carry, including how the tracing turned out.
  internal struct StampPreview: View {
    /// Fields in one path operator: two coordinates and the operator
    /// itself.
    private static let operatorFields = 3

    /// The traced artwork and its natural size.
    internal let artwork: SignatureArtwork.Artwork

    internal var body: some View {
      Canvas { context, size in
        let scale = min(
          size.width / artwork.width, size.height / artwork.height
        )
        guard scale > 0 else { return }
        // The operators are in PDF coordinates, which count up from
        // the bottom; a canvas counts down from the top. Without the
        // flip the preview shows the signature upside down while the
        // page it previews is the right way up.
        context.translateBy(x: 0, y: artwork.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.fill(Self.path(from: artwork.operators), with: .color(.primary))
      }
      .accessibilityHidden(true)
    }

    /// Rebuilds the outlines from the operators the page will carry.
    ///
    /// Reading back what will be written keeps the preview honest: a
    /// picture drawn from the bitmap could look right while the
    /// operators were wrong.
    private static func path(from operators: String) -> Path {
      var path = Path()
      for line in operators.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count == Self.operatorFields,
          let first = Double(parts[0]),
          let second = Double(parts[1])
        else {
          continue
        }
        let point = CGPoint(x: first, y: second)
        switch parts[Self.operatorFields - 1] {
        case "m":
          path.move(to: point)
        case "l":
          path.addLine(to: point)
        default:
          break
        }
      }
      path.closeSubpath()
      return path
    }
  }

#endif
