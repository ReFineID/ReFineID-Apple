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
internal struct CardTransportSelectionTests {
  @Test
  internal func refusesEmptySelection() {
    #expect(CardTransportSelection(enabled: []) == nil)
  }

  @Test
  internal func defaultPermitsReaderOnly() {
    #expect(CardTransportSelection.readerOnly.permits(.reader))
    #expect(!CardTransportSelection.readerOnly.permits(.nearField))
  }

  @Test
  internal func allPermitsEveryTransport() {
    for transport in CardTransport.allCases {
      #expect(CardTransportSelection.all.permits(transport))
    }
  }

  @Test
  internal func disablingTheLastTransportIsRefused() {
    #expect(CardTransportSelection.readerOnly.disabling(.reader) == nil)
  }

  @Test
  internal func disablingOneOfTwoKeepsTheOther() throws {
    let remaining = try #require(CardTransportSelection.all.disabling(.nearField))
    #expect(remaining == .readerOnly)
  }

  @Test
  internal func enablingIsIdempotent() {
    #expect(CardTransportSelection.readerOnly.enabling(.reader) == .readerOnly)
    #expect(CardTransportSelection.readerOnly.enabling(.nearField) == .all)
  }

  @Test
  internal func clampingDropsUnsupportedTransports() throws {
    let nearFieldOnly = try #require(CardTransportSelection(enabled: [.nearField]))
    #expect(nearFieldOnly.clamped(to: .readerOnly) == .readerOnly)
    #expect(CardTransportSelection.all.clamped(to: .readerOnly) == .readerOnly)
  }

  @Test
  internal func clampingNeverEmptiesTheSelection() throws {
    let nearFieldOnly = try #require(CardTransportSelection(enabled: [.nearField]))
    #expect(!nearFieldOnly.clamped(to: .readerOnly).enabled.isEmpty)
  }

  @Test
  internal func rawValuesArePersistedIdentifiers() {
    #expect(CardTransport.nearField.rawValue == "near-field")
    #expect(CardTransport.reader.rawValue == "reader")
  }
}
