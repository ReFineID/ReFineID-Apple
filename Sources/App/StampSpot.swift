#if os(macOS)

  import AppKit
  import Foundation
  import PDFKit

  /// Finds somewhere on the last page the mark can sit without
  /// covering anything.
  ///
  /// The page is rendered and looked at, rather than its content
  /// streams read. A stream says what is drawn but not where the ink
  /// lands - text needs font metrics, an image needs its transform,
  /// and a form XObject needs all of it again one level down. A
  /// picture of the page answers directly, and it answers for
  /// annotations too, so a mark left by an earlier signer counts as
  /// occupied without being treated as a special case.
  internal enum StampSpot {
    /// Pixels per point when the page is rendered.
    ///
    /// Coarse on purpose: this looks for empty regions, and does not
    /// read the page.
    private static let renderScale = 1.0

    /// How far the search moves between candidate positions.
    private static let searchStep = 6.0

    /// Clear space demanded around the mark.
    private static let clearance = 4.0

    /// How far from white a pixel may be and still count as blank,
    /// so that a faint rule or a page's own texture does not.
    private static let blankLevel: UInt8 = 250

    /// A free centre for a mark of `radius`, in the last page's own
    /// coordinates, or nil when the page has no room.
    ///
    /// Searched from the bottom-right corner, the margin a signature
    /// conventionally occupies, working left and then up.
    internal static func free(
      inLastPageOf document: Data,
      radius: Double
    ) -> (x: Double, y: Double)? {
      guard
        let pdf = PDFDocument(data: document),
        pdf.pageCount > 0,
        let page = pdf.page(at: pdf.pageCount - 1)
      else {
        return nil
      }
      let box = page.bounds(for: .mediaBox)
      let ink = Self.coverage(of: page, box: box)
      guard !ink.isEmpty else { return nil }
      let reach = radius + Self.clearance
      var centreY = box.minY + reach
      while centreY + reach <= box.maxY {
        var centreX = box.maxX - reach
        while centreX - reach >= box.minX {
          if Self.isBlank(
            around: (centreX, centreY), reach: reach, ink: ink, box: box
          ) {
            return (centreX - box.minX, centreY - box.minY)
          }
          centreX -= Self.searchStep
        }
        centreY += Self.searchStep
      }
      return nil
    }

    /// The page as one byte of grey per point.
    private static func coverage(
      of page: PDFPage,
      box: CGRect
    ) -> [UInt8] {
      let width = Int(box.width * Self.renderScale)
      let height = Int(box.height * Self.renderScale)
      guard width > 0, height > 0 else { return [] }
      var pixels = [UInt8](repeating: UInt8.max, count: width * height)
      guard
        let context = CGContext(
          data: &pixels,
          width: width,
          height: height,
          bitsPerComponent: UInt8.bitWidth,
          bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else {
        return []
      }
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.scaleBy(x: Self.renderScale, y: Self.renderScale)
      context.translateBy(x: -box.minX, y: -box.minY)
      page.draw(with: .mediaBox, to: context)
      return pixels
    }

    /// Whether every point around a centre is blank.
    private static func isBlank(
      around centre: (x: Double, y: Double),
      reach: Double,
      ink: [UInt8],
      box: CGRect
    ) -> Bool {
      let width = Int(box.width * Self.renderScale)
      let height = Int(box.height * Self.renderScale)
      let left = Int((centre.x - reach - box.minX) * Self.renderScale)
      let right = Int((centre.x + reach - box.minX) * Self.renderScale)
      // The page's own coordinates count up; the rendered rows do too,
      // because the context was drawn into with its origin at the
      // bottom left.
      let bottom = Int((centre.y - reach - box.minY) * Self.renderScale)
      let top = Int((centre.y + reach - box.minY) * Self.renderScale)
      guard left >= 0, bottom >= 0, right < width, top < height else {
        return false
      }
      for row in bottom...top {
        let start = row * width
        for column in left...right where ink[start + column] < Self.blankLevel {
          return false
        }
      }
      return true
    }
  }

#endif
