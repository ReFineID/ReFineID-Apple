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
import Testing

/// The minimal detached SignedData the SCS `cms-pades` form embeds
/// (RFC 5652 section 5).
@Suite
internal struct ScsDetachedCmsTests {
  @Test
  internal func refusesADigestOfTheWrongLength() {
    let outcome = ScsDetachedCms.prepare(
      digest: Data(repeating: 0x11, count: 20),
      certificates: [ScsTestCertificate.make().der],
      hashName: "SHA256"
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.code == 400)
    #expect(error.message.contains("32 bytes"))
  }

  @Test
  internal func refusesAnUnknownHashName() {
    let outcome = ScsDetachedCms.prepare(
      digest: Data(repeating: 0x11, count: 20),
      certificates: [ScsTestCertificate.make().der],
      hashName: "SHA1"
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.code == 400)
  }

  @Test
  internal func buildsASignedDataAroundTheSignature() throws {
    let leaf = ScsTestCertificate.make().der
    let digest = Data(repeating: 0x42, count: 32)
    let prepared = ScsDetachedCms.prepare(
      digest: digest,
      certificates: [leaf],
      hashName: "SHA256"
    )
    let cms = try prepared.get()

    // The data the card signs is the DER SET of signed attributes,
    // carrying the message digest verbatim.
    #expect(cms.signedAttributes.first == 0x31)
    #expect(cms.signedAttributes.firstRange(of: digest) != nil)

    let signature = Data(repeating: 0xEE, count: 384)
    let signedData = cms.signedData(signature: signature)
    // ContentInfo: SEQUENCE { id-signedData, [0] SignedData }.
    #expect(signedData.first == 0x30)
    let signedDataOid = DerEncoder.objectIdentifier("1.2.840.113549.1.7.2")
    #expect(signedData.firstRange(of: signedDataOid) != nil)
    // The chain and the signature ride inside.
    #expect(signedData.firstRange(of: leaf) != nil)
    #expect(signedData.firstRange(of: signature) != nil)
    // The signed attributes reappear retagged [0] IMPLICIT: same
    // content, context tag.
    let implicitAttributes =
      Data([0xA0]) + cms.signedAttributes.dropFirst()
    #expect(signedData.firstRange(of: implicitAttributes) != nil)
  }
}
