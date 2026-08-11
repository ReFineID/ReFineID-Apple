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
import CardCore
import Foundation
import Testing

@Suite
internal struct ResponseApduTests {
  @Test
  internal func statusOnlyResponseParses() throws {
    let response = try #require(ResponseApdu(raw: WireHex.data("9000")))
    #expect(response.payload.isEmpty)
    #expect(response.statusWord == .success)
  }

  @Test
  internal func payloadAndStatusSplitCorrectly() throws {
    let response = try #require(
      ResponseApdu(raw: WireHex.data("DEADBEEF9000"))
    )
    #expect(response.payload == WireHex.data("DEADBEEF"))
    #expect(response.statusWord == .success)
  }

  @Test
  internal func retryProbeResponseCarriesTheCounter() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let response = try #require(ResponseApdu(raw: WireHex.data("63C5")))
    #expect(response.statusWord == .pinIncorrect(remaining: five))
  }

  @Test
  internal func refusesTooShortAndOversized() {
    #expect(ResponseApdu(raw: Data()) == nil)
    #expect(ResponseApdu(raw: WireHex.data("90")) == nil)

    let oversized = Data(
      count: ResponseApdu.maximumPayloadLength + ResponseApdu.statusWordLength + 1
    )
    #expect(ResponseApdu(raw: oversized) == nil)
  }

  @Test
  internal func maximumPayloadIsAccepted() throws {
    var raw = Data(count: ResponseApdu.maximumPayloadLength)
    raw.append(WireHex.data("9000"))
    let response = try #require(ResponseApdu(raw: raw))
    #expect(response.payload.count == ResponseApdu.maximumPayloadLength)
    #expect(response.statusWord == .success)
  }
}
