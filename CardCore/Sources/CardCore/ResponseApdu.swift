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

/// A parsed response APDU: bounded payload plus classified status word.
public struct ResponseApdu: Equatable, Sendable {
  /// The two trailing status bytes every response must carry.
  public static let statusWordLength: Int = 2

  /// The largest short-form payload a response may carry.
  public static let maximumPayloadLength: Int = ExpectedResponseLength.maximum

  /// The response body without the status word; may be empty.
  public let payload: Data

  /// The classified status word.
  public let statusWord: StatusWord

  /// Joins continuation parts inside the module.
  internal init(payload: Data, statusWord: StatusWord) {
    self.payload = payload
    self.statusWord = statusWord
  }

  /// Parses raw transport bytes; refuses responses shorter than a
  /// status word or larger than the short-form bound.
  public init?(raw: Data) {
    let bytes = Array(raw)
    guard
      bytes.count >= Self.statusWordLength,
      bytes.count <= Self.maximumPayloadLength + Self.statusWordLength
    else {
      return nil
    }
    let payloadLength = bytes.count - Self.statusWordLength
    self.payload = Data(bytes.prefix(payloadLength))
    self.statusWord = StatusWord(
      sw1: bytes[payloadLength],
      sw2: bytes[payloadLength + 1]
    )
  }
}
