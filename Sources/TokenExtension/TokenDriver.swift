import CryptoTokenKit

/// CryptoTokenKit entry point. `com.apple.ctk.driver-class` in
/// Config/TokenExtension-Info.plist names this class; macOS instantiates
/// it when a smart card is inserted and asks the delegate to create a
/// token.
///
/// The token reads the card's authentication certificate and publishes
/// the identity. A card without the FINEID application, without a
/// readable auth certificate, or with an unsupported key profile is
/// refused with a typed error - refusal is safe: the system treats the
/// card as not handled by this driver.
internal final class TokenDriver: TKSmartCardTokenDriver, TKSmartCardTokenDriverDelegate {
  override internal init() {
    super.init()
    delegate = self
  }

  internal func tokenDriver(
    _ driver: TKSmartCardTokenDriver,
    createTokenFor smartCard: TKSmartCard,
    aid: Data?
  ) throws -> TKSmartCardToken {
    TokenLog.info("createToken called: aid=\(aid?.count ?? -1) bytes")
    do {
      let token = try Token(smartCard: smartCard, aid: aid, tokenDriver: driver)
      TokenLog.info("createToken succeeded")
      return token
    } catch let error as TokenError {
      TokenLog.error("createToken failed (TokenError): \(error)")
      throw error.asTKError
    } catch {
      TokenLog.error("createToken failed (other): \(error)")
      throw error
    }
  }
}
