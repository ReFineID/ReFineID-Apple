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
internal struct Pin2Tests {
  @Test
  internal func refusesTooShortAndTooLong() {
    let tooShort = String(
      repeating: "1",
      count: Pin2.minimumDigitCount - 1
    )
    let tooLong = String(
      repeating: "1",
      count: Pin2.maximumDigitCount + 1
    )
    #expect(!canConstruct(tooShort))
    #expect(!canConstruct(tooLong))
  }

  @Test
  internal func acceptsBoundaryLengths() {
    let shortest = String(repeating: "7", count: Pin2.minimumDigitCount)
    let longest = String(repeating: "7", count: Pin2.maximumDigitCount)
    #expect(canConstruct(shortest))
    #expect(canConstruct(longest))
  }

  @Test
  internal func refusesNonAsciiDigits() {
    #expect(!canConstruct("12a456"))
    #expect(!canConstruct("12 456"))
    #expect(!canConstruct("١٢٣٤٥٦"))
    #expect(!canConstruct("12.456"))
  }

  @Test
  internal func fingerprintDiffersFromPin1WithTheSameDigits() throws {
    // Domain separation: the same digits under the PIN1 and PIN2 roles
    // must never collide in the rejected-PIN memory.
    let serial = try #require(TokenSerial(value: "9990000001"))
    guard
      let pin1 = Pin1(digits: "123456"),
      let pin2 = Pin2(digits: "123456")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    #expect(
      pin1.fingerprint(boundTo: serial) != pin2.fingerprint(boundTo: serial)
    )
  }

  @Test
  internal func consumingForTransmissionEndsTheValue() {
    // The at-most-once property itself is compile-time: after
    // `consumeForSingleTransmission()` any further use of the Pin2 is a
    // compiler error, which cannot be demonstrated in a runtime test.
    // This test pins down that consumption produces the transmission
    // value exactly once.
    guard let pin = Pin2(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    _ = pin.consumeForSingleTransmission()
  }

  /// `#expect` requires copyable operands, so noncopyable construction
  /// results are reduced to a Bool here.
  private func canConstruct(_ digits: String) -> Bool {
    switch Pin2(digits: digits) {
    case .some:
      true
    case .none:
      false
    }
  }
}
