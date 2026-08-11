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

import CryptoKit
import Foundation

/// An internal lookup key for a contactless card before PACE identifies it.
///
/// A contactless ATR identifies a card family, not one physical card. This
/// value therefore exists only to find the metadata that lets the extension
/// establish PACE. It must never be published as a CryptoTokenKit instance ID.
public struct PrimeLookupIdentifier: Equatable, Hashable, Sendable {
  /// A descriptive namespace keeps diagnostics readable without pretending
  /// this digest is a physical-card identity.
  private static let prefix = "refineid-prime-atr-sha256-"

  /// Formats one digest byte as two lowercase hexadecimal digits.
  private static let byteHexFormat = "%02x"

  /// The keychain account used for this ATR lookup.
  public let value: String

  /// Derives a lookup key from the complete answer to reset.
  ///
  /// Empty data identifies no card family and is refused.
  public init?(answerToReset: Data) {
    guard !answerToReset.isEmpty else { return nil }
    let digest = SHA256.hash(data: answerToReset)
      .map { byte in String(format: Self.byteHexFormat, byte) }
      .joined()
    self.value = Self.prefix + digest
  }
}
