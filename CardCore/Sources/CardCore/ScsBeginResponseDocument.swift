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

/// The `begin` response payload this service signs (DVV SCS
/// specification v1.3 §2.7.2).
internal struct ScsBeginResponseDocument: Codable {
  /// The protocol version.
  internal let version: String

  /// Base64 DER SPKI of this service's ephemeral agreement key.
  internal let transaction: String

  /// Base64 DER certificate chain, leaf first.
  internal let chain: [String]

  /// Always `ok`; a refused begin answers an error body instead.
  internal let status: String

  /// The specification reason code.
  internal let reasonCode: Int

  /// The human-readable reason.
  internal let reasonText: String
}
