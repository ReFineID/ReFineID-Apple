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

/// Direct extraction checks for the DG2 portrait boundary.
@Suite
internal struct DisplayedPortraitTests {
  private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

  private static let jpeg2000 = Data([
    0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20,
    0x0D, 0x0A, 0x87, 0x0A,
  ])

  private static func element(_ tag: UInt8, _ content: Data) -> Data {
    Data([tag, UInt8(content.count)]) + content
  }

  @Test
  internal func jpegIsFoundAfterTheBiometricHeader() throws {
    let prefix = Data([0x7F, 0x61, 0x03, 0x01, 0x02, 0x03])
    let group = Self.element(0x75, prefix + Self.jpeg)

    let portrait = try DisplayedPortrait.image(inDataGroup: group)

    #expect(portrait.bytes == Self.jpeg)
    #expect(portrait.format == .jpeg)
  }

  @Test
  internal func jpeg2000IsFoundAfterTheBiometricHeader() throws {
    let group = Self.element(0x75, Data([0x01, 0x02]) + Self.jpeg2000)

    let portrait = try DisplayedPortrait.image(inDataGroup: group)

    #expect(portrait.bytes == Self.jpeg2000)
    #expect(portrait.format == .jpeg2000)
  }

  @Test
  internal func anotherDataGroupIsRefused() {
    #expect(throws: DisplayedPortrait.Failure.notADataGroup) {
      _ = try DisplayedPortrait.image(
        inDataGroup: Self.element(0x67, Self.jpeg)
      )
    }
  }

  @Test
  internal func aDg2WithoutAnImageIsRefused() {
    #expect(throws: DisplayedPortrait.Failure.noImage) {
      _ = try DisplayedPortrait.image(
        inDataGroup: Self.element(0x75, Data([0x01, 0x02, 0x03]))
      )
    }
  }
}
