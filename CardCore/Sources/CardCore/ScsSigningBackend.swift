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

/// The signing seam behind the SCS protocol surface.
///
/// The dispatcher and the transaction flow are pure protocol logic;
/// everything that touches a card - certificates, key algorithms, the
/// PIN-gated sign itself - crosses this seam. The production backend
/// drives a card session; tests supply canned material so the whole
/// protocol surface is exercised without hardware.
public protocol ScsSigningBackend {
  /// The DER certificate chain for `purpose`, leaf first.
  func certificateChain(for purpose: ScsSignPurpose) -> [Data]

  /// The key algorithm behind `purpose`, for the response's
  /// `signatureAlgorithm` field.
  func keyAlgorithm(for purpose: ScsSignPurpose) -> ScsKeyAlgorithm

  /// Signs `data` with the `purpose` key after hashing it with
  /// `hash`. Throws `ScsBackendFailure` so the protocol layer can
  /// answer the specified reason code.
  func sign(purpose: ScsSignPurpose, hash: SigningHash, data: Data) throws -> Data
}
