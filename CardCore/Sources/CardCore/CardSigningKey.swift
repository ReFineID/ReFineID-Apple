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
/// A signing key on the card, as the MSE:SET key-reference byte.
///
/// The two keys are gated by different credentials and are never
/// interchangeable: authentication is PIN1's, the qualified signature
/// is PIN2's. Every MSE:SET names its key explicitly - there is no
/// default, so a caller cannot select the wrong key by omission.
public enum CardSigningKey: Equatable, Sendable {
  /// The PIN1-gated authentication key, certificate in EF.4331.
  case authentication

  /// The PIN2-gated qualified-signature key, certificate in EF.4332.
  /// This is private key #2 on the FINEID S4-1 v3.1 card too.
  case qualifiedSignature

  /// The MSE:SET key-reference byte (S1 v4.2 §3.6.3).
  internal var reference: UInt8 {
    switch self {
    case .authentication:
      FineidValues.keyReferenceAuthentication
    case .qualifiedSignature:
      FineidValues.keyReferenceQualifiedSignature
    }
  }
}
