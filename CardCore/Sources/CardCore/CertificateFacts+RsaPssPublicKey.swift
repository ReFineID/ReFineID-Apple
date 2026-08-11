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

extension CertificateFacts {
  /// Extracts a DER PKCS#1 RSA public key from the one current EU TSL signer
  /// profile that Security cannot import through `SecCertificateCopyKey`.
  ///
  /// This deliberately recognizes only an id-RSASSA-PSS SubjectPublicKeyInfo
  /// whose AlgorithmIdentifier parameters are absent. Callers must separately
  /// restrict how the returned unrestricted RSA key may be used.
  public static func rsaPssPublicKeyWithAbsentParameters(
    der: Data
  ) -> Data? {
    guard let publicKeyInfo = Self.subjectPublicKeyInfo(in: der) else {
      return nil
    }
    var fields = DerReader(der, within: publicKeyInfo)
    guard
      let algorithm = fields.next(),
      algorithm.tag == DerValues.tagSequence,
      let bitString = fields.next(),
      bitString.tag == DerValues.tagBitString,
      fields.isAtEnd,
      Self.isRsaPssWithAbsentParameters(algorithm, in: der)
    else { return nil }

    let content = fields.contentData(of: bitString)
    guard content.count > 1, content.first == 0 else { return nil }
    let publicKey = Data(content.dropFirst())
    guard Self.isCanonicalPkcs1RsaPublicKey(publicKey) else { return nil }
    return publicKey
  }

  /// Locates SubjectPublicKeyInfo in one complete X.509 certificate.
  private static func subjectPublicKeyInfo(
    in der: Data
  ) -> DerReader.Element? {
    var outer = DerReader(der)
    guard
      let certificate = outer.next(),
      certificate.tag == DerValues.tagSequence,
      outer.isAtEnd
    else { return nil }
    var certificateFields = DerReader(der, within: certificate)
    guard
      let tbs = certificateFields.next(),
      tbs.tag == DerValues.tagSequence,
      let signatureAlgorithm = certificateFields.next(),
      signatureAlgorithm.tag == DerValues.tagSequence,
      let signature = certificateFields.next(),
      signature.tag == DerValues.tagBitString,
      certificateFields.isAtEnd
    else { return nil }

    var fields = DerReader(der, within: tbs)
    guard var serial = fields.next() else { return nil }
    if serial.tag == DerValues.tagContext0Constructed {
      guard let following = fields.next() else { return nil }
      serial = following
    }
    guard
      serial.tag == DerValues.tagInteger,
      let tbsSignature = fields.next(),
      tbsSignature.tag == DerValues.tagSequence,
      let issuer = fields.next(),
      issuer.tag == DerValues.tagSequence,
      let validity = fields.next(),
      validity.tag == DerValues.tagSequence,
      let subject = fields.next(),
      subject.tag == DerValues.tagSequence,
      let publicKeyInfo = fields.next(),
      publicKeyInfo.tag == DerValues.tagSequence
    else { return nil }
    return publicKeyInfo
  }

  /// Requires the exact AlgorithmIdentifier shape seen in Germany's TSL.
  private static func isRsaPssWithAbsentParameters(
    _ algorithm: DerReader.Element,
    in der: Data
  ) -> Bool {
    var fields = DerReader(der, within: algorithm)
    guard
      let identifier = fields.next(),
      identifier.tag == DerValues.tagObjectIdentifier,
      fields.data(of: identifier)
        == DerEncoder.objectIdentifier(SignOids.rsaPss)
    else { return false }
    return fields.isAtEnd
  }

  /// Validates the canonical DER RSAPublicKey shape before Security sees it.
  private static func isCanonicalPkcs1RsaPublicKey(_ encoded: Data) -> Bool {
    var wrapper = DerReader(encoded)
    guard
      let sequence = wrapper.next(),
      sequence.tag == DerValues.tagSequence,
      wrapper.isAtEnd
    else { return false }
    var fields = DerReader(encoded, within: sequence)
    guard
      let modulus = fields.next(),
      modulus.tag == DerValues.tagInteger,
      let exponent = fields.next(),
      exponent.tag == DerValues.tagInteger,
      fields.isAtEnd
    else { return false }
    return Self.isCanonicalPositiveInteger(modulus, in: fields)
      && Self.isCanonicalPositiveInteger(exponent, in: fields)
  }

  /// Whether one INTEGER is a nonzero, positive, minimally encoded DER value.
  private static func isCanonicalPositiveInteger(
    _ integer: DerReader.Element,
    in reader: DerReader
  ) -> Bool {
    let value = reader.contentData(of: integer)
    guard
      let first = value.first,
      first & DerValues.signBitMask == 0,
      value.contains(where: { $0 != 0 })
    else { return false }
    if first == 0 {
      guard value.count > 1 else { return false }
      return value[value.index(after: value.startIndex)]
        & DerValues.signBitMask != 0
    }
    return true
  }
}
