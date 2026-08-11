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
import CardCore
import Foundation

/// A canned SCS signing backend: fixed chain and signature, optional
/// scripted refusal, and a record of what was asked, so protocol
/// tests run without hardware.
internal final class ScriptedScsBackend: ScsSigningBackend {
  internal var chain: [Data]
  internal var algorithm: ScsKeyAlgorithm
  internal var signature: Data
  internal var refusal: ScsBackendFailure?
  internal private(set) var signedData: [Data] = []
  internal private(set) var signedHashes: [SigningHash] = []
  internal private(set) var signedPurposes: [ScsSignPurpose] = []

  internal init(
    chain: [Data],
    algorithm: ScsKeyAlgorithm,
    signature: Data
  ) {
    self.chain = chain
    self.algorithm = algorithm
    self.signature = signature
  }

  internal func certificateChain(for _: ScsSignPurpose) -> [Data] {
    chain
  }

  internal func keyAlgorithm(for _: ScsSignPurpose) -> ScsKeyAlgorithm {
    algorithm
  }

  internal func sign(
    purpose: ScsSignPurpose,
    hash: SigningHash,
    data: Data
  ) throws -> Data {
    if let refusal {
      throw refusal
    }
    signedData.append(data)
    signedHashes.append(hash)
    signedPurposes.append(purpose)
    return signature
  }
}
