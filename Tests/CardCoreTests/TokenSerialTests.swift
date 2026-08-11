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
import Testing

@Suite
internal struct TokenSerialTests {
  @Test
  internal func refusesEmpty() {
    #expect(TokenSerial(value: "") == nil)
  }

  @Test
  internal func refusesOversized() {
    let oversized = String(
      repeating: "A",
      count: TokenSerial.maximumLength + 1
    )
    #expect(TokenSerial(value: oversized) == nil)
  }

  @Test
  internal func acceptsMaximumLength() {
    let maximal = String(repeating: "9", count: TokenSerial.maximumLength)
    #expect(TokenSerial(value: maximal) != nil)
  }

  @Test
  internal func refusesNonPrintableAndSpaces() {
    #expect(TokenSerial(value: "ABC 123") == nil)
    #expect(TokenSerial(value: "ABC\n123") == nil)
    #expect(TokenSerial(value: "sarja\u{0000}") == nil)
    #expect(TokenSerial(value: "sarjanumero-ä") == nil)
  }

  @Test
  internal func distinctSerialsDiffer() throws {
    let first = try #require(TokenSerial(value: "9990000001"))
    let second = try #require(TokenSerial(value: "9990000002"))
    #expect(first != second)
  }
}
