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

/// The signed response JWT's protected header (DVV SCS specification
/// v1.3 §2.7.2).
internal struct ScsResponseHeaderDocument: Codable {
  /// The JWS algorithm name.
  internal let alg: String

  /// The signing certificate's key identifier.
  internal let kid: String

  /// Always `JWT`.
  internal let typ: String
}
