import Foundation

/// The RFC 3161 request and response handling for qualified
/// timestamps.
///
/// Building the request and checking the answer are pure; the HTTP
/// exchange belongs to the caller. The binding check is what keeps a
/// wrong or replayed token out: status granted, TSTInfo of the right
/// type and version, the message imprint byte-equal to what was
/// asked, and the nonce echoed exactly. Chain validation is
/// deliberately left to validators - the signer cannot anchor trust
/// for the reader.
public enum RfcTimestamp {
  /// A refused or unusable timestamp answer.
  public enum TokenFailure: Error, Equatable {
    /// The token's imprint is not the digest that was sent.
    case imprintMismatch

    /// The response did not parse as a TimeStampResp with a token.
    case malformed

    /// The token's nonce is absent or not the one sent.
    case nonceMismatch

    /// The authority answered with a non-granted status.
    case rejected(status: Int)
  }

  /// The TimeStampReq: version 1, the SHA-384 imprint, a nonce, and
  /// an explicit request for the signing certificate.
  public static func request(digest: Data, nonceBytes: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.integer(SignOids.timestampRequestVersion),
      DerEncoder.sequence([
        DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384)]),
        DerEncoder.octetString(digest),
      ]),
      DerEncoder.unsignedInteger(nonceBytes),
      DerEncoder.booleanTrue(),
    ])
  }

  /// The verified TimeStampToken out of a TimeStampResp, verbatim.
  public static func token(
    fromResponse response: Data,
    digest: Data,
    nonceBytes: Data
  ) throws -> Data {
    var outer = DerReader(response)
    guard let envelope = outer.next(), envelope.tag == DerValues.tagSequence
    else {
      throw TokenFailure.malformed
    }
    var reader = DerReader(response, within: envelope)
    guard let statusInfo = reader.next() else {
      throw TokenFailure.malformed
    }
    var statusReader = DerReader(response, within: statusInfo)
    guard
      let status = statusReader.next(), status.tag == DerValues.tagInteger,
      let statusValue = statusReader.integerValue(of: status)
    else {
      throw TokenFailure.malformed
    }
    guard SignOids.grantedStatuses.contains(statusValue) else {
      throw TokenFailure.rejected(status: statusValue)
    }
    guard let tokenElement = reader.next() else {
      throw TokenFailure.malformed
    }
    try checkBinding(
      response: response,
      element: tokenElement,
      digest: digest,
      nonceBytes: nonceBytes
    )
    return reader.data(of: tokenElement)
  }

  /// The TSTInfo checks: type, version, imprint, nonce.
  private static func checkBinding(
    response: Data,
    element: DerReader.Element,
    digest: Data,
    nonceBytes: Data
  ) throws {
    guard let tstInfo = Self.tstInfoContent(response: response, element: element)
    else {
      throw TokenFailure.malformed
    }
    var outer = DerReader(tstInfo)
    guard let sequence = outer.next() else { throw TokenFailure.malformed }
    var reader = DerReader(tstInfo, within: sequence)
    guard
      let version = reader.next(),
      reader.integerValue(of: version) == SignOids.tstInfoVersion,
      reader.next() != nil,
      let imprint = reader.next()
    else {
      throw TokenFailure.malformed
    }
    var imprintReader = DerReader(tstInfo, within: imprint)
    guard
      imprintReader.next() != nil,
      let hashed = imprintReader.next(),
      hashed.tag == DerValues.tagOctetString
    else {
      throw TokenFailure.malformed
    }
    guard imprintReader.contentData(of: hashed) == digest else {
      throw TokenFailure.imprintMismatch
    }
    // Fields after the imprint: the serial INTEGER, genTime, then the
    // optional run where the nonce is the first INTEGER (RFC 3161).
    guard reader.next() != nil, reader.next() != nil else {
      throw TokenFailure.malformed
    }
    let expected = DerEncoder.unsignedInteger(nonceBytes)
    while let candidate = reader.next() {
      guard candidate.tag == DerValues.tagInteger else { continue }
      guard reader.data(of: candidate) == expected else {
        throw TokenFailure.nonceMismatch
      }
      return
    }
    throw TokenFailure.nonceMismatch
  }

  /// The TSTInfo eContent octets inside the token's SignedData.
  private static func tstInfoContent(
    response: Data,
    element: DerReader.Element
  ) -> Data? {
    var contentInfo = DerReader(response, within: element)
    guard
      let typeOid = contentInfo.next(),
      contentInfo.data(of: typeOid)
        == DerEncoder.objectIdentifier(SignOids.signedData),
      let explicitWrap = contentInfo.next()
    else {
      return nil
    }
    var wrapped = DerReader(response, within: explicitWrap)
    guard let signedData = wrapped.next() else { return nil }
    var signedReader = DerReader(response, within: signedData)
    guard
      signedReader.next() != nil,
      signedReader.next() != nil,
      let encapsulated = signedReader.next()
    else {
      return nil
    }
    var encapsulatedReader = DerReader(response, within: encapsulated)
    guard
      let contentType = encapsulatedReader.next(),
      encapsulatedReader.data(of: contentType)
        == DerEncoder.objectIdentifier(SignOids.tstInfo),
      let eContent = encapsulatedReader.next()
    else {
      return nil
    }
    var eContentReader = DerReader(response, within: eContent)
    guard
      let octets = eContentReader.next(),
      octets.tag == DerValues.tagOctetString
    else {
      return nil
    }
    return eContentReader.contentData(of: octets)
  }
}
