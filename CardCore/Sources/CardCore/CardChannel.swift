import Foundation

/// The transport a card session runs over.
///
/// One conforming value represents one exclusive card session; the
/// platform layer adapts `TKSmartCard` to this in a single line. Keeping
/// the protocol in CardCore lets every operation above it run against a
/// scripted fake in tests, with no hardware and no CryptoTokenKit.
public protocol CardChannel {
  /// Sends one command APDU and returns the raw response bytes.
  func transmit(_ payload: Data) throws -> Data
}
