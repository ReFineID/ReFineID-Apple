import CryptoTokenKit
import Foundation

/// Typed failures inside the token extension, each mapped to the
/// CryptoTokenKit error the system expects.
internal enum TokenError: Error {
  /// No usable PIN yet (none entered, no valid cache): the system must
  /// present the PIN sheet and retry.
  case authenticationRequired

  /// The leaf certificate DER did not construct a `SecCertificate`.
  case certificateUnreadable

  /// The system rejected construction of a keychain item.
  case keychainItemConstructionFailed

  /// The entered PIN was already rejected by this card; not resent.
  case pinAlreadyRejected

  /// The collected PIN is not a valid PIN1 (length or characters).
  case pinFormatInvalid

  /// The card rejected the PIN during VERIFY.
  case pinRejected

  /// The card's raw signature could not be re-encoded.
  case signatureMalformed

  /// Signing was refused (retry floor, unreadable state, or a rejected
  /// signing command).
  case signRefused

  /// The leaf's key is not one of the supported profiles.
  case unsupportedKeyProfile

  /// The system error to surface to CryptoTokenKit.
  internal var asTKError: TKError {
    switch self {
    case .authenticationRequired:
      TKError(.authenticationNeeded)
    case .keychainItemConstructionFailed:
      TKError(.corruptedData)
    case .certificateUnreadable, .signatureMalformed:
      TKError(.corruptedData)
    case .pinAlreadyRejected, .pinFormatInvalid, .pinRejected, .signRefused:
      TKError(.authenticationFailed)
    case .unsupportedKeyProfile:
      TKError(.tokenNotFound)
    }
  }
}
