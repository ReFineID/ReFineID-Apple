//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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

  /// A scripted transport stands in for a reader: plain responses, plain
  /// chunk.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

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
