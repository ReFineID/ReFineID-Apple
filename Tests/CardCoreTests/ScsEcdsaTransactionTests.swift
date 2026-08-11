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
import CryptoKit
import Foundation
import Testing

/// The transaction flow over an ECDSA card key.
///
/// The begin JWT signs as ES384 over SHA-384 - the digest the P-384
/// qualified key serves - and execute accepts the ECDSA algorithm
/// name (RFC 7518 section 3.1; DVV SCS specification v1.3 §2.7).
@Suite
internal struct ScsEcdsaTransactionTests {
  private static let origin = "https://dvv.fineid.fi"

  @Test
  internal func beginSignsEs384OverSha384() throws {
    let material = ScsTestCertificate.make()
    let agreement = P256.KeyAgreement.PrivateKey()
    let scripted = ScriptedScsBackend(
      chain: [material.der],
      algorithm: .ecdsa,
      signature: Data(repeating: 0xEC, count: 96)
    )
    func segment(_ json: [String: Any]) -> String {
      let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
      return Base64Url.encode(data)
    }
    let payload: [String: Any] = [
      "version": "1.3",
      "serverKey": agreement.publicKey.derRepresentation.base64EncodedString(),
      "serverCert": material.der.base64EncodedString(),
      "selector": ["keyusages": ["nonRepudiation"]],
    ]
    let input = segment(["alg": "ES256"]) + "." + segment(payload)
    let signature =
      (try? material.key.signature(for: Data(input.utf8)))?.rawRepresentation ?? Data()
    let compact = Data((input + "." + Base64Url.encode(signature)).utf8)

    let begun = ScsTransactionManager().begin(
      compactJws: compact,
      origin: Self.origin,
      at: Date(),
      backend: scripted
    )
    let response = try begun.get()
    let headerData = try #require(
      Base64Url.decode(response.components(separatedBy: ".")[0]))
    let header = try #require(
      try JSONSerialization.jsonObject(with: headerData) as? [String: Any])
    #expect(header["alg"] as? String == "ES384")
    #expect(scripted.signedHashes == [.sha384])
    #expect(scripted.signedPurposes == [.qualified])
  }
}
