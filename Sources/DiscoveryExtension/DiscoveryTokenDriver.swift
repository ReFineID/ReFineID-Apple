import CryptoTokenKit
import Foundation

/// The discovery half of the CryptoTokenKit pair: a driver that exists only
/// so ctkd has a select-identifier to poll cards with, and that deliberately
/// mints nothing.
///
/// Do not "fix" this class into doing work. ctkd polls for a card using the
/// `com.apple.ctk.aid` an extension declares. A driver that declares no AID
/// gives the daemon nothing to select, so a contactless card is never
/// surfaced and the system's Ready-to-Scan sheet waits forever. Declaring
/// the AID on the driver that mints the token breaks the other half: ctkd
/// then stops invoking that driver even for the app's own slot, nothing is
/// minted, and `registerSmartCard` fails. The two roles therefore live in
/// separate extensions with different class-ids -- this one advertises the
/// AID (Config/DiscoveryExtension-Info.plist), and
/// `ReFineIDTokenExtension.TokenDriver` mints the real token from a plist
/// that declares no AID.
///
/// The advertised AID is the ICAO eMRTD LDS application, chosen because a
/// Finnish ID card implements it as a travel document and answers a SELECT
/// for it over the contactless interface before PACE has run, which the
/// PKCS#15 application does not.
///
/// On macOS the extension still builds and installs; there is no NFC slot
/// there, so it is simply never asked for anything.
internal final class DiscoveryTokenDriver: TKSmartCardTokenDriver,
  TKSmartCardTokenDriverDelegate
{
  /// Registers the driver as its own delegate, matching the shape
  /// CryptoTokenKit expects of a `TKSmartCardTokenDriver` subclass.
  override internal init() {
    super.init()
    delegate = self
  }

  /// Refuses politely: the real token comes from the minting extension.
  ///
  /// `tokenNotFound` tells CryptoTokenKit that this driver does not handle
  /// the card, which is the safe refusal -- the system moves on and lets
  /// `ReFineIDTokenExtension` mint for the slot the app registered.
  internal func tokenDriver(
    _: TKSmartCardTokenDriver,
    createTokenFor _: TKSmartCard,
    aid _: Data?
  ) throws -> TKSmartCardToken {
    throw TKError(.tokenNotFound)
  }
}
