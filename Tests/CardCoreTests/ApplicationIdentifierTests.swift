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
internal struct ApplicationIdentifierTests {
  @Test
  internal func fineidApplicationConstantExists() {
    // The DVV-documented IAS "PKCS-15" AID parses to 12 bytes.
    let aid = ApplicationIdentifier.fineidApplication
    #expect(aid == ApplicationIdentifier(hexDigits: "A000000063504B43532D3135"))
  }

  @Test
  internal func refusesWrongLengths() {
    // Four bytes: below the five-byte RID minimum.
    #expect(ApplicationIdentifier(hexDigits: "A0000000") == nil)
    // Seventeen bytes: above the maximum.
    let seventeenBytes = String(repeating: "AB", count: 17)
    #expect(ApplicationIdentifier(hexDigits: seventeenBytes) == nil)
    // Odd number of hex digits.
    #expect(ApplicationIdentifier(hexDigits: "A00000006") == nil)
    #expect(ApplicationIdentifier(hexDigits: "") == nil)
  }

  @Test
  internal func refusesNonHexInput() {
    #expect(ApplicationIdentifier(hexDigits: "A0000000635G") == nil)
    #expect(ApplicationIdentifier(hexDigits: "A0 00 00 00 63") == nil)
  }

  @Test
  internal func acceptsBoundaryLengths() {
    let fiveBytes = String(repeating: "A0", count: 5)
    let sixteenBytes = String(repeating: "A0", count: 16)
    #expect(ApplicationIdentifier(hexDigits: fiveBytes) != nil)
    #expect(ApplicationIdentifier(hexDigits: sixteenBytes) != nil)
  }
}
