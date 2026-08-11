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

import CardCore
import Testing

/// Direct issuer-KeyUsage edge cases for complete, issuer-signed CRLs.
@Suite
internal struct CertificateRevocationListKeyUsageTests {
  /// Declared unused KeyUsage bits must be zero and cannot authorize cRLSign.
  @Test
  internal func issuerWithNonzeroUnusedKeyUsageBitsIsRejected() throws {
    let material = try CertificateRevocationListFixtures.make(
      kind: .ecdsaSha256,
      options: .standard,
      targetSignedByWrongKey: false,
      issuerKeyUsage: .malformedUnusedBits
    )

    #expect(
      throws: CertificateRevocationList.ValidationFailure.certificateUnparseable
    ) {
      _ = try CertificateRevocationList.validate(
        crl: material.crl,
        certificate: material.certificate,
        issuerCertificate: material.issuerCertificate,
        currentTime: material.currentTime
      )
    }
  }
}
