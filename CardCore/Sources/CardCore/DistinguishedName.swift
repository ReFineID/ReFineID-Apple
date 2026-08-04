import Foundation

/// The one human-readable name in an X.509 subject: its common name.
///
/// A FINEID citizen certificate carries the holder's identity four
/// times over: a common name of `SURNAME FORENAME <identifier>`, and
/// then that surname, forename and identifier again as attributes of
/// their own. Everything that shows a name to a person shows the
/// common name, so the reading lives here once rather than in each of
/// them.
public enum DistinguishedName {
  /// `id-at-commonName` (RFC 5280 appendix A), encoded the same way
  /// the writer encodes every other identifier so the comparison is
  /// against one encoding rather than a hand-copied one.
  private static var commonNameOid: Data {
    DerEncoder.objectIdentifier(SignOids.commonName)
  }

  /// The common name in a DER-encoded Name, or nil when it carries
  /// none this can read.
  ///
  /// A Name is a sequence of relative names, each a set of
  /// type-and-value pairs; the common name is the pair whose type is
  /// `id-at-commonName`. Its value is a text string in one of several
  /// ASN.1 flavours, and only the flavours that are plainly text are
  /// accepted - a name this cannot read honestly is better absent
  /// than mangled.
  public static func commonName(inName name: Data) -> String? {
    var outer = DerReader(name)
    guard
      let sequence = outer.next(),
      sequence.tag == DerValues.tagSequence
    else {
      return nil
    }
    var relativeNames = DerReader(name, within: sequence)
    while let relativeName = relativeNames.next() {
      var pairs = DerReader(name, within: relativeName)
      while let pair = pairs.next() {
        guard let found = Self.commonName(inPair: pair, of: name) else {
          continue
        }
        return found
      }
    }
    return nil
  }

  /// The value of one type-and-value pair, when its type is the
  /// common name.
  private static func commonName(
    inPair pair: DerReader.Element,
    of name: Data
  ) -> String? {
    var parts = DerReader(name, within: pair)
    guard
      let type = parts.next(),
      DerReader(name).data(of: type) == Self.commonNameOid,
      let value = parts.next(),
      Self.isTextTag(value.tag)
    else {
      return nil
    }
    let text = DerReader(name).contentData(of: value)
    return String(data: text, encoding: .utf8)
      ?? String(data: text, encoding: .isoLatin1)
  }

  /// Whether a tag introduces a string this can read as text.
  ///
  /// UTF-8, printable and IA5 strings are plain text. The wide
  /// encodings a Name may also use are not accepted: they would need
  /// their own decoding, and guessing at one produces a name that
  /// looks right and is not.
  private static func isTextTag(_ tag: UInt8) -> Bool {
    tag == DerValues.tagUtf8String
      || tag == DerValues.tagPrintableString
      || tag == DerValues.tagIa5String
  }
}
