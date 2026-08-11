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

/// Why the signing backend refused an SCS sign.
///
/// The protocol maps these to the specification's reason codes: a
/// credential refusal answers 401, everything else 500 (DVV SCS
/// specification v1.3 §2.6.3). The text rides in `reasonText` and
/// never carries a credential or a serial.
public enum ScsBackendFailure: Error, Equatable, Sendable {
  /// The credential was refused, missing, or not entered.
  case credentialRefused(String)

  /// The card, reader, or sign chain failed.
  case signingUnavailable(String)

  /// The specification reason code for this failure.
  internal var reasonCode: Int {
    switch self {
    case .credentialRefused:
      ScsValues.reasonUnauthorized
    case .signingUnavailable:
      ScsValues.reasonInternalError
    }
  }

  /// The reason-text prefix plus detail for this failure.
  internal var reasonText: String {
    switch self {
    case .credentialRefused(let detail):
      "Unauthorized: " + detail
    case .signingUnavailable(let detail):
      "Internal Server Error: " + detail
    }
  }
}
