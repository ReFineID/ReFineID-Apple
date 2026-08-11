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

/// The `execute` payload carried inside the JWE (DVV SCS
/// specification v1.3 §2.7.3).
internal struct ScsExecuteDocument: Codable {
  /// The protocol version of the transaction.
  internal let version: String

  /// Base64 of the content or digest to sign.
  internal let content: String

  /// `data` or `digest`; `data` when absent.
  internal let contentType: String

  /// The digest name; SHA256 when absent.
  internal let hashAlgorithm: String

  /// The key algorithm name; RSA when absent.
  internal let signatureAlgorithm: String

  /// `signature` or `cms-pades`; `signature` when absent.
  internal let signatureType: String

  /// Decodes with the specification's optionality.
  internal init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.version = try container.decode(String.self, forKey: .version)
    self.content = try container.decode(String.self, forKey: .content)
    self.contentType =
      try container.decodeIfPresent(String.self, forKey: .contentType) ?? "data"
    self.hashAlgorithm =
      try container.decodeIfPresent(String.self, forKey: .hashAlgorithm) ?? "SHA256"
    self.signatureAlgorithm =
      try container.decodeIfPresent(String.self, forKey: .signatureAlgorithm) ?? "RSA"
    self.signatureType =
      try container.decodeIfPresent(String.self, forKey: .signatureType) ?? "signature"
  }
}
