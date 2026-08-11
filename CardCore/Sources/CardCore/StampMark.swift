// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
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

  /// How much room the mark needs, from its centre.
  ///
  /// Wider than the radius: the outermost ring is stroked, and a
  /// stroke straddles the line it follows, so half the pen falls
  /// outside the radius. Anything sizing a box for the mark, or
  /// looking for somewhere to put it, must use this rather than the
  /// radius - a box cut to the radius shaves the ring flat.
  public var reach: Double { self.radius + PdfValues.stampBleed }

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
