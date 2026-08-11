//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
import CryptoTokenKit

/// Creates signing sessions and retains a time-limited contactless card field.
extension Token {
  // The @objc requirement is throwing; keep `throws` for the bridge.
  // swiftlint:disable:next unneeded_throws_rethrows
  internal func createSession(_: TKToken) throws -> TKTokenSession {
    // Which interface this card is on is the useful half: it says which
    // sign path is about to run. `TKToken` publishes no instance
    // identifier to name it with.
    TokenLog.info("createSession: session requested, interface=\(interface)")
    return TokenSession(token: self)
  }

  /// Takes a card session now and keeps it, so the signature that
  /// follows still has a live field.
  ///
  /// A signing-field contactless mint calls this and nothing else does;
  /// the one-time registration field deliberately stays passive. On the
  /// system-driven signing path the slot that minted this token has ended
  /// by the time the signature is asked for, and a fresh `beginSession`
  /// then fails with `TKError -7`; this one session carries the mint, the
  /// PACE run and the signature.
  ///
  /// Best effort by design: a token that could not hold a session is
  /// still perfectly usable wherever the card stays present, so a
  /// failure here is swallowed rather than failing the mint.
  internal func holdSession(on smartCard: TKSmartCard) {
    guard heldSession.current == nil else { return }
    let channel = SmartCardChannel(smartCard, waits: .nearField)
    do {
      try channel.beginSession()
    } catch {
      TokenLog.info("Token.holdSession: no session retained (\(error))")
      return
    }
    heldSession.retain(channel)
    if let accessNumber = sealedAccessNumber {
      heldSession.startPACE(with: accessNumber)
    }
  }

  /// Releases the held session when the card is genuinely gone.
  ///
  /// Only `.missing` counts. Releasing on any other non-valid state was
  /// measured tearing a signature down part way through a read: a card
  /// momentarily out of the field is still the same card, and the slot
  /// says so a moment later.
  internal func observeSlotState(of smartCard: TKSmartCard) {
    slotStateObservation = smartCard.slot.observe(\.state, options: [.new]) {
      [held = heldSession] observed, change in
      let state = change.newValue ?? observed.state
      guard state == .missing else { return }
      held.release()
    }
  }
}
