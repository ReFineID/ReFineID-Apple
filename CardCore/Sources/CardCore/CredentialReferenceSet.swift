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
/// Which credential reference numbering the card in session uses.
///
/// The citizen card numbers its credentials as FINEID S1 v4.2 §3.5.2
/// reads: global PIN1 `11`, local PIN2 `82`, PUK `83`. The organization
/// card numbers them by their FINEID S4-2 v4.0 §4.2 security-data-object
/// identifiers instead: PIN AUTH `03`, PIN SIG `04`, PIN PUK `12`.
///
/// The S4-2 v4.0 §5.2 EF.AOD sample prints other references,
/// contradicting the same document's §4.2 tables and shipped cards;
/// the sample is stale. Resolution therefore asks the card rather
/// than trusting any printed sample, and the probe is retry-safe: a
/// VERIFY status query against an absent reference answers
/// `referenceDataNotFound` without touching any retry counter, so
/// asking costs nothing but one command.
public enum CredentialReferenceSet: Equatable, Sendable {
  /// FINEID S1 v4.2 §3.5.2 numbering, the citizen cards.
  case citizen

  /// FINEID S4-2 v4.0 §4.2 security-data-object numbering, the
  /// organization cards.
  case organization

  /// The VERIFY P2 reference for a role under this numbering.
  internal func reference(for role: CredentialRole) -> UInt8 {
    switch self {
    case .citizen:
      FineidValues.reference(for: role)
    case .organization:
      FineidValues.organizationReference(for: role)
    }
  }
}
