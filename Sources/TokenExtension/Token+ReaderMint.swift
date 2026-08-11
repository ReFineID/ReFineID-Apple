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
import CardCore

extension Token {
  /// Makes a deliberately inserted reader card the only active form of
  /// ReFineID identity on iOS.
  ///
  /// A live reader token needs no stored prime or absent-card
  /// registration. Keeping any ReFineID registration leaves Safari an
  /// NFC route even though the holder deliberately connected a reader
  /// and inserted a usable card. That physical action chooses the reader
  /// globally within ReFineID, not merely for a card with the same
  /// printed serial.
  ///
  /// Apple and third-party identities are outside both stores touched
  /// here. The token that was just minted remains live; ReFineID's stored
  /// CAN, PIN1, card directory, NFC primes, and Safari registrations do
  /// not. The connected reader is now the card and credential source.
  internal func supersedeStoredContactlessIdentities() {
    #if os(iOS)
      let primeCount = PrimeStore.storedCount()
      PrimeStore.forgetAll()
      CardCredentialStore.forgetAll()
      let registrationCount = TokenRegistrationRevoker.revokeAll(reason: .readerMint)
      TokenLog.notice(
        "reader mint superseded all ReFineID contactless identities; "
          + "primes=\(primeCount) registrations=\(registrationCount)"
      )
    #endif
  }
}
