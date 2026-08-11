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
internal struct CardExchangeTraceTests {
  /// A SELECT command APDU: CLA INS P1 P2 Lc, with a two-byte body.
  private static let selectRequest = Data([0x00, 0xA4, 0x04, 0x0C, 0x02, 0x3F, 0x00])

  /// A VERIFY command APDU carrying a padded PIN block.
  private static let verifyRequest = Data([
    0x00, 0x20, 0x00, 0x81, 0x08, 0x31, 0x32, 0x33, 0x34, 0xFF, 0xFF, 0xFF, 0xFF,
  ])

  @Test
  internal func namesInstructionSizesAndStatus() {
    let line = CardExchangeTrace.line(
      request: Self.selectRequest,
      response: Data([0x6F, 0x01, 0x90, 0x00]),
      elapsed: .milliseconds(12))
    #expect(line.contains("ins=A4"))
    #expect(line.contains("tx=7"))
    #expect(line.contains("rx=2"))
    #expect(line.contains("sw=9000"))
    #expect(line.contains("ms=12.0"))
  }

  @Test
  internal func redactsVerifyWholesale() {
    let line = CardExchangeTrace.line(
      request: Self.verifyRequest,
      response: Data([0x63, 0xC4]),
      elapsed: .milliseconds(8))
    // The instruction, the status word and the timing survive; nothing
    // that describes the PIN block does -- not even its length.
    #expect(line.contains("ins=20"))
    #expect(line.contains("sw=63C4"))
    #expect(line.contains("redacted"))
    #expect(!line.contains("tx=13"))
  }

  @Test
  internal func survivesAnAnswerlessExchange() {
    let line = CardExchangeTrace.line(
      request: Self.selectRequest,
      response: nil,
      elapsed: .seconds(1))
    #expect(line.contains("sw=?"))
    #expect(line.contains("ms=1000.0"))
  }

  @Test
  internal func survivesATruncatedRequest() {
    let line = CardExchangeTrace.line(
      request: Data([0x00]),
      response: Data([0x90, 0x00]),
      elapsed: .zero)
    #expect(line.contains("ins=?"))
    #expect(line.contains("sw=9000"))
  }
}
