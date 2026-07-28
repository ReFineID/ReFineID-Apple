import CardCore
import CryptoTokenKit
import Foundation

/// Removes a rejected card's system registration outside the sign callback.
internal enum TokenRegistrationRevoker {
  /// Queues best-effort removal of the exact token registration.
  internal static func revoke(_ instanceID: CardInstanceIdentifier) {
    #if os(iOS)
      let tokenID = CardTokenNamespace.tokenIdentifier(for: instanceID)
      DispatchQueue.global(qos: .utility).async {
        let manager = TKSmartCardTokenRegistrationManager.default
        guard manager.registeredSmartCardTokens.contains(tokenID) else {
          TokenLog.info("PIN1 rejection registration already absent")
          return
        }
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          TokenLog.notice("PIN1 rejection unregistered token")
        } catch {
          // The persistent PIN and prime are already gone. Even if this
          // index removal fails, the driver cannot mint or sign the token
          // again until the holder deliberately creates a new identity.
          TokenLog.error("PIN1 rejection could not unregister token: \(error)")
        }
      }
    #endif
  }
}
