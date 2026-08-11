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

/// The key algorithm behind an SCS signature, as the protocol names it.
///
/// The response's `signatureAlgorithm` field composes the digest and
/// key names in the `SHA256withRSA` Java convention (DVV SCS
/// specification v1.3 §2.6.3).
public enum ScsKeyAlgorithm: Equatable, Sendable {
  /// An elliptic-curve card key.
  case ecdsa

  /// An RSA card key.
  case rsa

  /// The protocol's digest-name spelling for `hash`.
  public static func scsName(hash: SigningHash) -> String {
    switch hash {
    case .sha224:
      "SHA224"
    case .sha256:
      "SHA256"
    case .sha384:
      "SHA384"
    case .sha512:
      "SHA512"
    }
  }

  /// Parses the protocol's digest-name spelling; the SCS surface
  /// accepts SHA-256, SHA-384 and SHA-512 (v1.3 §2.5.2).
  public static func hash(named name: String) -> SigningHash? {
    switch name {
    case "SHA256":
      .sha256
    case "SHA384":
      .sha384
    case "SHA512":
      .sha512
    default:
      nil
    }
  }

  /// The composed `signatureAlgorithm` response value for this key
  /// under `hash`.
  public func scsName(hash: SigningHash) -> String {
    let key =
      switch self {
      case .ecdsa:
        "ECDSA"
      case .rsa:
        "RSA"
      }
    return Self.scsName(hash: hash) + "with" + key
  }
}
