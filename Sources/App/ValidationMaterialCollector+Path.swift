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
  import Security

  /// Certificate-path construction for validation-material collection.
  extension ValidationMaterialCollector {
    /// Finds an embedded or AIA issuer and verifies its certificate signature.
    internal static func issuer(
      of subject: Data,
      facts: CertificateFacts,
      at referenceDate: Date,
      collection: inout Collection,
      dependencies: Dependencies
    ) async throws -> Data {
      if let embedded = collection.candidates.first(where: { candidate in
        candidate != subject
          && CertificateIssuer.isDirectlyIssued(
            subject, by: candidate, at: referenceDate
          )
      }) {
        return embedded
      }
      for address in Self.boundedCertificateAddresses(
        facts.issuerCertificateUrls
      ) {
        guard
          let body = try? await dependencies.get(address, false),
          let candidate = Self.certificate(from: body),
          CertificateIssuer.isDirectlyIssued(
            subject, by: candidate, at: referenceDate
          )
        else { continue }
        collection.addCandidate(candidate)
        return candidate
      }
      throw Failure.issuerUnavailable
    }

    /// PEM unwrapped to one DER certificate, or DER unchanged.
    private static func certificate(from body: Data) -> Data? {
      if SecCertificateCreateWithData(nil, body as CFData) != nil {
        return body
      }
      guard let text = String(data: body, encoding: .ascii) else { return nil }
      let base64 =
        text
        .split(whereSeparator: \.isNewline)
        .filter { !$0.hasPrefix("-----") }
        .joined()
      guard
        let decoded = Data(base64Encoded: String(base64)),
        SecCertificateCreateWithData(nil, decoded as CFData) != nil
      else { return nil }
      return decoded
    }
  }

#endif
