// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import CardCore
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
/// for it before PACE has run, which the PKCS#15 application does not.
/// Measured on 2026-08-04, that SELECT is answered on either interface -
/// contact as well as contactless - though every file inside stays sealed
/// until PACE, so what discovery gains is only the answer itself.
///
/// On macOS the extension still builds and installs; there is no NFC slot
/// there, so it is simply never asked for anything.
internal final class DiscoveryTokenDriver: TKSmartCardTokenDriver,
  TKSmartCardTokenDriverDelegate
{
  /// The last line this process wrote, so a repeated poll cannot flood
  /// the trace.
  ///
  /// `@unchecked Sendable` is sound because every access holds the lock;
  /// `ctkd` may ask on more than one thread.
  internal final class LastWritten: @unchecked Sendable {
    /// Serialises the threads that reach the remembered line.
    private let lock = NSLock()

    /// The line most recently written, or nil before the first.
    private var line: String?

    /// Records `candidate` and says whether it is new.
    internal func admit(_ candidate: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard line != candidate else { return false }
      line = candidate
      return true
    }
  }

  /// What this process has already said.
  ///
  /// `ctkd` polls, and a poll that repeats every second would fill the
  /// rolling buffer with this one line and evict the mint and signature
  /// lines it exists to preserve. The first of each distinct line is
  /// worth having; the hundredth is worth less than what it displaces.
  private static let lastWritten = LastWritten()

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
  ///
  /// The refusal is traced, and that line matters more than it looks: it
  /// is the proof that `ctkd` polled a card with the advertised AID at
  /// all. A login that fails with no such line failed before discovery,
  /// which is a different fault from a mint that refused -- and without
  /// the trace the two are indistinguishable.
  internal func tokenDriver(
    _: TKSmartCardTokenDriver,
    createTokenFor smartCard: TKSmartCard,
    aid: Data?
  ) throws -> TKSmartCardToken {
    #if DEBUG
      let line =
        "discovery: asked for a token, aid=\(aid?.count ?? -1)B "
        + "slot=\(smartCard.slot.name) -- refusing with tokenNotFound"
      if Self.lastWritten.admit(line) {
        ExtensionTrace.append(line)
      }
    #endif
    throw TKError(.tokenNotFound)
  }
}
