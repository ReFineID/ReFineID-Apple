import CardCore
import CryptoTokenKit
import Foundation

/// Removes a rejected card's system registration outside the sign callback.
internal enum TokenRegistrationRevoker {
  /// Why an automatic registration no longer represents the desired path.
  internal enum Reason {
    /// The card rejected the credential authorizing automatic signatures.
    case pin1Rejection

    /// The holder deliberately inserted the same card into a reader.
    case readerMint

    /// Stable diagnostic wording that contains no card or credential data.
    internal var logPrefix: String {
      switch self {
      case .pin1Rejection:
        "PIN1 rejection"
      case .readerMint:
        "reader mint"
      }
    }
  }

  /// Queues best-effort removal of the exact token registration.
  internal static func revoke(
    _ instanceID: CardInstanceIdentifier,
    reason: Reason
  ) {
    #if os(iOS)
      let tokenID = CardTokenNamespace.tokenIdentifier(for: instanceID)
      DispatchQueue.global(qos: .utility).async {
        let manager = TKSmartCardTokenRegistrationManager.default
        guard manager.registeredSmartCardTokens.contains(tokenID) else {
          TokenLog.info("\(reason.logPrefix) registration already absent")
          return
        }
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          TokenLog.notice("\(reason.logPrefix) unregistered token")
        } catch {
          // The persistent PIN and prime are already gone. Even if this
          // index removal fails, the driver cannot mint or sign the token
          // again until the holder deliberately creates a new identity.
          TokenLog.error("\(reason.logPrefix) could not unregister token: \(error)")
        }
      }
    #endif
  }
}
