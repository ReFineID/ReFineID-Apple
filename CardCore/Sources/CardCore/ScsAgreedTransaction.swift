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

/// One agreed SCS transaction awaiting its `execute` (DVV SCS
/// specification v1.3 §2.7).
internal struct ScsAgreedTransaction: Sendable {
  /// The agreed A256GCM transaction key.
  internal let key: SymmetricKey

  /// The Origin that began the transaction; `execute` must match.
  internal let origin: String

  /// The card key the selector chose at `begin`.
  internal let purpose: ScsSignPurpose

  /// The service's base64 agreement key, which the authentication
  /// challenge must be bound to.
  internal let serverKey: String
}
