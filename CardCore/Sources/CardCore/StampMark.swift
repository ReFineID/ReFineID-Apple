import Foundation

/// The signature's visible mark, drawn about its own centre.
///
/// It carries no page of its own. The mark is laid over the
/// document's last page, in its margin, inside the signature's own
/// revision - so it is covered by the signature, and nothing is added
/// to the document after it is signed.
///
/// Drawing about the origin is what lets the writer place it: the
/// mark does not know the page's size, and the writer does.
public struct StampMark: Sendable {
  /// How far the mark reaches from its centre, in points.
  public let radius: Double

  /// The operators drawing it, centred on the origin.
  public let operators: String

  /// How far across the page the mark's centre should sit.
  ///
  /// Set when the caller found somewhere clear for it; the writer
  /// falls back to the page's corner when nothing was found.
  public let acrossPage: Double?

  /// How far up the page it should sit, on the same terms.
  public let upPage: Double?

  /// Composes a mark, optionally placed.
  public init(
    radius: Double,
    operators: String,
    acrossPage: Double? = nil,
    upPage: Double? = nil
  ) {
    self.radius = radius
    self.operators = operators
    self.acrossPage = acrossPage
    self.upPage = upPage
  }
}
