//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
/// Which card key an SCS request selects.
///
/// The request's selector names key usages; `nonRepudiation` selects
/// the qualified-signature key and everything else the authentication
/// key (DVV SCS specification v1.3 §2.6.2). The two keys carry
/// different obligations: an authentication signature must only ever
/// cover an origin-bound challenge, a qualified signature covers the
/// document the holder chose to sign.
public enum ScsSignPurpose: Equatable, Sendable {
  /// The PIN1-gated authentication key.
  case authentication

  /// The PIN2-gated qualified-signature key.
  case qualified
}
