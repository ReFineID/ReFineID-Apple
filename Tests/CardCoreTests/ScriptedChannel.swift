import CardCore
import Foundation
import Testing

/// A scripted `CardChannel`.
///
/// Each transmit must match the next expected request and returns its
/// scripted response. Any deviation fails the test - the script *is*
/// the expected physical transmit sequence, so these tests double as
/// transmit-count checks.
internal final class ScriptedChannel: CardChannel {
  internal struct UnexpectedRequest: Error {}

  private var script: [(request: Data, response: Data)]

  /// True when every scripted exchange was consumed.
  internal var isExhausted: Bool {
    script.isEmpty
  }

  internal init(_ script: [(String, String)]) {
    self.script = script.map { entry in
      (request: WireHex.data(entry.0), response: WireHex.data(entry.1))
    }
  }

  internal func transmit(_ payload: Data) throws -> Data {
    guard let next = script.first, next.request == payload else {
      Issue.record("unexpected transmit: \(payload.count) bytes")
      throw UnexpectedRequest()
    }
    script.removeFirst()
    return next.response
  }
}
