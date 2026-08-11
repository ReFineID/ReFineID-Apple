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
internal struct TokenInfoFileTests {
  @Test
  internal func parsesMinimalTokenInfo() {
    let content = WireHex.data("300B020100040612AB34CD56EF")
    let serial = TokenInfoFile.serial(fromContent: content)
    #expect(serial?.value == "12AB34CD56EF")
  }

  @Test
  internal func parsesLongFormOuterLength() {
    // SEQUENCE with a long-form (81) length byte; trailing fields
    // beyond the serial are ignored.
    let content = WireHex.data("30810D02010004021234040411223344")
    let serial = TokenInfoFile.serial(fromContent: content)
    #expect(serial?.value == "1234")
  }

  @Test
  internal func refusesMalformedStructures() {
    // Not a SEQUENCE.
    #expect(TokenInfoFile.serial(fromContent: WireHex.data("0401AA")) == nil)
    // SEQUENCE whose inner length overruns the data.
    #expect(TokenInfoFile.serial(fromContent: WireHex.data("30FF0201")) == nil)
    // Fields in the wrong order (serial before version).
    #expect(
      TokenInfoFile.serial(fromContent: WireHex.data("300704021234020100")) == nil
    )
    // Empty serial octet string.
    #expect(
      TokenInfoFile.serial(fromContent: WireHex.data("30050201000400")) == nil
    )
    // Empty input.
    #expect(TokenInfoFile.serial(fromContent: WireHex.data("")) == nil)
  }
}
