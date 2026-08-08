import CCryptoki
import Foundation
import Security

/// Composes the CKA_LABEL for a token identity's objects.
///
/// The label reads "Given name Surname - card number - PIN
/// designation": unique because the keys are bound to the card,
/// holder-readable, and shown verbatim by OpenSSH as the public key
/// comment. The name comes from the certificate subject's givenName
/// and surname RDNs (not parsed out of the CN), title-cased for
/// readability; the card number from the ReFineID token instance
/// identifier; and the PIN designation from the token's key name,
/// whose text outside parentheses is localized while the parenthesized
/// designation is stable.
internal enum KeyLabel {
  /// X.500 attribute OIDs used to compose the label.
  private static let surnameOid = "2.5.4.4"
  private static let givenNameOid = "2.5.4.42"

  /// The token-ID marker preceding the card number in ReFineID token
  /// instance identifiers.
  private static let cardNumberMarker = "refineid-card-"

  /// The designation of the card's default key.
  ///
  /// The default key is the one ssh and browser login use. In the
  /// authentication profile its designation is left off the label,
  /// since that profile shows no other keys; the signing profile
  /// labels every key with its designation so a signing application's
  /// key picker reads unambiguously.
  private static let defaultDesignation = "PIN 1"

  /// The composed label; falls back to the certificate summary plus
  /// the key name when the subject lacks the person attributes.
  internal static func compose(
    keyName: String, certificate: SecCertificate, tokenID: String
  ) -> String {
    let subject = subjectAttributes(certificate)
    guard let surname = subject[surnameOid],
      let givenName = subject[givenNameOid],
      let cardNumber = cardNumber(tokenID: tokenID)
    else {
      guard let summary = SecCertificateCopySubjectSummary(certificate) as String?
      else { return keyName }
      return "\(summary) - \(keyName)"
    }
    let base = "\(givenName.capitalized) \(surname.capitalized) - \(cardNumber)"
    let designation = pinName(keyName)
    let omitDesignation =
      designation == defaultDesignation && !IdentityPolicy.isSigningProfile
    return omitDesignation ? base : "\(base) - \(designation)"
  }

  /// Subject RDN values keyed by attribute OID.
  private static func subjectAttributes(
    _ certificate: SecCertificate
  ) -> [String: String] {
    let wanted = [kSecOIDX509V1SubjectName] as CFArray
    guard
      let values = SecCertificateCopyValues(certificate, wanted, nil)
        as? [String: [String: Any]],
      let subject = values[kSecOIDX509V1SubjectName as String],
      let members = subject[kSecPropertyKeyValue as String] as? [[String: Any]]
    else { return [:] }
    var attributes: [String: String] = [:]
    for member in members {
      guard let oid = member[kSecPropertyKeyLabel as String] as? String,
        let value = member[kSecPropertyKeyValue as String] as? String
      else { continue }
      attributes[oid] = value
    }
    return attributes
  }

  /// The card number carried in a ReFineID token instance identifier,
  /// uppercased as printed on the card; nil for other tokens.
  private static func cardNumber(tokenID: String) -> String? {
    guard let range = tokenID.range(of: cardNumberMarker) else { return nil }
    let number = tokenID[range.upperBound...]
    guard !number.isEmpty else { return nil }
    return number.uppercased()
  }

  /// Extracts the token key name's PIN designation.
  ///
  /// The designation is the text the key name carries in parentheses:
  /// "Perus (PIN 1)" becomes "PIN 1". Names without parentheses pass
  /// through unchanged, since only the text outside the parentheses is
  /// localized.
  private static func pinName(_ label: String) -> String {
    guard let open = label.firstIndex(of: "("),
      let close = label.lastIndex(of: ")"),
      open < close
    else { return label }
    let designation = String(label[label.index(after: open)..<close])
    return designation.isEmpty ? label : designation
  }
}
