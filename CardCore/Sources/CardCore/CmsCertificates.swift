import Foundation

/// The certificates carried inside a CMS SignedData (RFC 5652 §5.1).
///
/// A timestamp token embeds the authority's certificate and its chain,
/// because the request asked for them. A validator needs revocation
/// evidence for those as well as for the signer, so the signing side
/// has to be able to read them back out of the token it just received.
public enum CmsCertificates {
  /// Every certificate in the token's `certificates [0]` field, in the
  /// order written, or an empty array when there are none.
  public static func inside(_ token: Data) -> [Data] {
    var outer = DerReader(token)
    guard
      let contentInfo = outer.next(),
      contentInfo.tag == DerValues.tagSequence,
      outer.isAtEnd
    else { return [] }
    var info = DerReader(token, within: contentInfo)
    guard
      let contentType = info.next(),
      info.data(of: contentType)
        == DerEncoder.objectIdentifier(SignOids.signedData),
      let explicitWrap = info.next(),
      explicitWrap.tag == DerValues.tagContext0Constructed,
      info.isAtEnd
    else {
      return []
    }
    var wrapped = DerReader(token, within: explicitWrap)
    guard
      let signedData = wrapped.next(),
      signedData.tag == DerValues.tagSequence,
      wrapped.isAtEnd
    else { return [] }
    var reader = DerReader(token, within: signedData)
    // version, digestAlgorithms, encapContentInfo, then the optional
    // certificates field.
    guard
      let version = reader.next(),
      version.tag == DerValues.tagInteger,
      let algorithms = reader.next(),
      algorithms.tag == DerValues.tagSet,
      let content = reader.next(),
      content.tag == DerValues.tagSequence,
      let candidate = reader.next(),
      candidate.tag == DerValues.tagContext0Constructed
    else {
      return []
    }
    var trailing = reader.next()
    if trailing?.tag == DerValues.tagContext1Constructed {
      trailing = reader.next()
    }
    guard trailing?.tag == DerValues.tagSet, reader.isAtEnd else {
      return []
    }
    var list = DerReader(token, within: candidate)
    var certificates: [Data] = []
    while let element = list.next() {
      // Only plain certificates; the other choices are attribute
      // certificates a validator does not want here.
      guard element.tag == DerValues.tagSequence else { continue }
      certificates.append(list.data(of: element))
    }
    return certificates
  }
}
