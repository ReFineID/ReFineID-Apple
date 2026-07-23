import Foundation

/// The certificate material read from a card for publication: the
/// authentication leaf (required) and the issuing-CA certificate
/// (best-effort - absent on cards that do not carry EF.4336).
internal struct PublishedIdentity {
  /// DER of the authentication leaf certificate.
  internal let leafDER: Data

  /// DER of the issuing-CA certificate, when the card provides it.
  internal let issuerDER: Data?
}
