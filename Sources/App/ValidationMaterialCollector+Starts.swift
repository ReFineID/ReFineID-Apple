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

#if os(macOS)

  import CardCore
  import Foundation

  /// Strict certificate-path ordering for validation-material collection.
  extension ValidationMaterialCollector {
    /// Orders TSA checks before any document-signer fallback can apply.
    internal static func orderedChainStarts(
      signerCertificate: Data,
      timestampTokens: [TimestampTokenVerifier.VerifiedToken],
      signerTrustCertificates: Set<Data>,
      evidenceTime: Date
    ) -> [ChainStart] {
      var starts = timestampTokens.map { token in
        ChainStart(
          certificate: token.signerCertificate,
          role: .timestampAuthority,
          referenceDate: token.generatedAt,
          trustedCertificates: [token.trustedCertificate]
        )
      }
      starts.append(
        ChainStart(
          certificate: signerCertificate,
          role: .documentSigner,
          referenceDate: timestampTokens.first?.generatedAt ?? evidenceTime,
          trustedCertificates: signerTrustCertificates
        )
      )
      return starts
    }
  }

#endif
