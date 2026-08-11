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

import Foundation

/// The stable CryptoTokenKit instance ID for one physical card.
///
/// One card has one token across transports and authentication-key
/// generations. The identifier contains the serial printed on the card, so a
/// diagnostics report can be checked against the plastic without translating
/// an ATR hash or certificate fingerprint.
public struct CardInstanceIdentifier: Equatable, Hashable, Sendable {
  /// Namespace owned by the ReFineID token driver.
  private static let prefix = "refineid-card-"

  /// The public CTK instance identifier.
  public let value: String

  /// Builds the public identifier from a supported FINEID token serial.
  public init?(tokenSerial: TokenSerial) {
    guard let printed = PrintedCardSerial(tokenSerial: tokenSerial) else {
      return nil
    }
    self.value = Self.prefix + printed.value.lowercased()
  }
}
