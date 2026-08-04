import Foundation

/// A page appended to a document to carry the signature's visible
/// mark.
///
/// The mark goes on a page of its own rather than over the document's
/// own content. Nothing of the original is covered, no page geometry
/// has to be guessed at, and a reader can tell at a glance which
/// marks were on the paper before it was signed and which this
/// program added.
///
/// The page is written into the same revision as the signature, so it
/// is inside what the signature covers. Adding it afterwards would
/// leave a document that validators report as modified after signing,
/// which is the one thing a qualified signature must not look like.
public struct StampPage: Sendable {
  /// The page's width in points.
  public let width: Double

  /// The page's height in points.
  public let height: Double

  /// The content stream drawing the mark, in PDF operators.
  public let operators: String

  /// Where the signature's widget sits on this page.
  ///
  /// A rectangle of zero area makes the field invisible, which is
  /// what a page with no visible mark wants; anything else is drawn
  /// by its own appearance and this only says where.
  public var widgetRectangle: String {
    "[0 0 0 0]"
  }

  /// Composes a page.
  public init(width: Double, height: Double, operators: String) {
    self.width = width
    self.height = height
    self.operators = operators
  }
}
