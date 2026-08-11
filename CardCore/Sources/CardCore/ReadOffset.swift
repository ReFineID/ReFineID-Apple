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
/// A READ BINARY direct offset: 15 bits, encoded in P1-P2 with the top
/// bit of P1 clear.
public struct ReadOffset: Equatable, Sendable {
  /// The highest encodable offset.
  public static let maximum: UInt16 = Iso7816Values.readBinaryOffsetMaximum

  /// Bytes addressable from offset zero through the highest offset.
  public static let maximumAddressableLength = Int(Self.maximum) + 1

  /// The validated offset value.
  public let value: UInt16

  /// P1 byte: the high seven bits.
  internal var p1Byte: UInt8 {
    UInt8(value >> Iso7816Values.byteShift)
  }

  /// P2 byte: the low byte.
  internal var p2Byte: UInt8 {
    UInt8(value & Iso7816Values.lowByteMask)
  }

  /// Refuses offsets above the 15-bit maximum.
  public init?(value: UInt16) {
    guard value <= Self.maximum else { return nil }
    self.value = value
  }
}
