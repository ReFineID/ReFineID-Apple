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
    guard let contentInfo = outer.next() else { return [] }
    var info = DerReader(token, within: contentInfo)
    guard
      info.next() != nil,
      let explicitWrap = info.next()
    else {
      return []
    }
    var wrapped = DerReader(token, within: explicitWrap)
    guard let signedData = wrapped.next() else { return [] }
    var reader = DerReader(token, within: signedData)
    // version, digestAlgorithms, encapContentInfo, then the optional
    // certificates field.
    guard
      reader.next() != nil,
      reader.next() != nil,
      reader.next() != nil,
      let candidate = reader.next(),
      candidate.tag == DerValues.tagContext0Constructed
    else {
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
