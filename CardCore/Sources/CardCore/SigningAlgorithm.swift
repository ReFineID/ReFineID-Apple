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
/// A FINEID signing algorithm, as the MSE:SET algorithm-reference byte.
public struct SigningAlgorithm: Equatable, Sendable {
  /// Number of bits in one nibble, for composing the reference byte.
  private static let nibbleWidth: UInt8 = 4

  /// The hash function.
  public let hash: SigningHash

  /// The signature scheme.
  public let scheme: SigningScheme

  /// The algorithm-reference byte: hash high nibble, scheme low nibble.
  internal var reference: UInt8 {
    hash.highNibble << Self.nibbleWidth | scheme.lowNibble
  }

  /// Composes an algorithm from its hash and scheme.
  public init(hash: SigningHash, scheme: SigningScheme) {
    self.hash = hash
    self.scheme = scheme
  }
}
