import CardCore
import SwiftUI

/// A text binding that accepts only a bounded number of ASCII digits.
///
/// Keyboard types are hints, not validation: paste, hardware keyboards,
/// and accessibility input can still insert other characters. Filtering
/// at the binding keeps every credential field inside its domain while
/// the holder is typing.
internal enum LimitedDigitBinding {
  /// A CAN field: six ASCII digits and no more.
  internal static func cardAccessNumber(
    _ source: Binding<String>
  ) -> Binding<String> {
    Self.make(
      source,
      maximumCount: CardAccessNumber.digitCount)
  }

  /// A PIN1 field: ASCII digits up to the supported maximum.
  internal static func pin1(
    _ source: Binding<String>
  ) -> Binding<String> {
    Self.make(
      source,
      maximumCount: Pin1.maximumDigitCount)
  }

  /// Wraps `source`, discarding non-digits and input beyond `maximumCount`.
  private static func make(
    _ source: Binding<String>,
    maximumCount: Int
  ) -> Binding<String> {
    Binding(
      get: { source.wrappedValue },
      set: { candidate in
        source.wrappedValue = Self.normalized(
          candidate,
          maximumCount: maximumCount)
      })
  }

  /// Keeps only ASCII digits, preserving their original order.
  private static func normalized(
    _ candidate: String,
    maximumCount: Int
  ) -> String {
    let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
    let bytes = candidate.utf8.lazy
      .filter { byte in asciiDigits.contains(byte) }
      .prefix(maximumCount)
    return String(bytes: bytes, encoding: .ascii) ?? ""
  }
}
