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

/// The organization card's sign chain at the operations level: MSE:SET
/// DST exactly as on the citizen card, then the host digest inline in
/// PSO:CDS's data field - no PSO:HASH exists for an external hash there
/// (Idemia organizational cards specification §6.6.2.3).
@Suite
internal struct OrganizationSigningTests {
  @Test
  internal func qualifiedChainCarriesTheDigestInsidePsoCds() throws {
    let digest = String(repeating: "AB", count: 32)
    let firstSignaturePart = String(repeating: "11", count: 256)
    let secondSignaturePart = String(repeating: "22", count: 128)
    // PIN2 verification resolves the numbering; the sign chain then
    // reuses it without a probe of its own. The qualified key is
    // local to DF.ESIGN, so its reference carries the local bit
    // (IAS-ECC v1.0.1 §4.4): 84 01 82. RSA-3072 answers 384 bytes
    // through the usual GET RESPONSE continuation.
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "63C5"),
      ("0020000406363534333231", "9000"),
      ("002241B606800142840182", "9000"),
      ("002A9E9A20" + digest + "00", firstSignaturePart + "6180"),
      ("00C0000080", secondSignaturePart + "9000"),
    ])
    let operations = CardOperations(channel: channel)
    guard let pin = Pin2(digits: "654321") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin2(pin.consumeForSingleTransmission())

    let raw = try operations.computeQualifiedSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )

    #expect(raw == WireHex.data(firstSignaturePart + secondSignaturePart))
    #expect(raw.count == 384)
    #expect(channel.isExhausted)
  }

  @Test
  internal func citizenChainIsUnchangedWhenResolutionSaysCitizen() throws {
    let digest = String(repeating: "AB", count: 32)
    let signature = String(repeating: "11", count: 256)
    // A session resolved as citizen keeps the historical PSO:HASH +
    // empty PSO:CDS sequence byte for byte.
    let channel = ScriptedChannel([
      ("0020001100", "63C5"),
      ("002000110C313233343536000000000000", "9000"),
      ("002241B606800142840101", "9000"),
      ("002A90A0229020" + digest, "9000"),
      ("002A9E9A00", signature + "9000"),
    ])
    let operations = CardOperations(channel: channel)
    guard let pin = Pin1(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin.consumeForSingleTransmission())

    let raw = try operations.computeAuthenticationSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )

    #expect(raw == WireHex.data(signature))
    #expect(channel.isExhausted)
  }
}
