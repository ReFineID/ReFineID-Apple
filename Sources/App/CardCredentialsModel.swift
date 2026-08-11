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
import SwiftUI

/// What the credential screen knows and what it is allowed to do.
///
/// Nothing here ever holds a secret longer than the moment it is written:
/// the entry fields are cleared as soon as a value is stored. For PIN1
/// the model only ever reports *whether* something is stored, never what
/// it is -- a screen that can show a PIN is a screen that can leak one.
/// The card access number is the one value read back: it is printed on
/// the card face and is the holder's to see.
@MainActor
@Observable
internal final class CardCredentialsModel {
  /// What the device currently holds.
  internal private(set) var contents = CardCredentialStore.contents()

  /// The stored card access number, shown by the manager window.
  internal private(set) var storedCardAccessNumber =
    CardCredentialStore.displayedCardAccessNumber()

  /// Whether there is anything behind the destructive forget action.
  internal private(set) var hasForgettableState =
    CardStateReset.hasForgettableState()

  /// Set when the last action failed, for the holder to read.
  internal private(set) var failure: String?

  /// Refreshes what is stored, without touching PIN1.
  internal func refresh() {
    contents = CardCredentialStore.contents()
    storedCardAccessNumber = CardCredentialStore.displayedCardAccessNumber()
    hasForgettableState = CardStateReset.hasForgettableState()
  }

  /// Stores the card access number, with no gate in front.
  ///
  /// Ungated: the number is printed on the card face, so a prompt in
  /// front of storing it protected nothing and cost every setup an
  /// interruption.
  internal func saveCardAccessNumber(_ digits: String) {
    failure = nil
    let status = CardCredentialStore.save(cardAccessNumber: digits)
    if status != errSecSuccess {
      failure = String(
        localized: "Could not store the card access number (\(status)).")
    }
    refresh()
  }

  /// Stores PIN1, with no gate in front.
  ///
  /// Ungated like the card access number. A prompt here protected only
  /// the act of writing a PIN the holder just typed: the extension reads
  /// the stored value without any gate -- it must, inside a two-second
  /// signing field -- so possession of the unlocked phone plus the card
  /// already signs, gate or no gate. The card's own retry counter is the
  /// control that actually stops a guessed PIN.
  internal func savePin1(_ digits: String) {
    failure = nil
    let status = CardCredentialStore.save(pin1: digits)
    if status != errSecSuccess {
      failure = String(localized: "Could not store PIN 1 (\(status)).")
    }
    refresh()
  }

  /// Stores any credentials that are not already present before minting.
  ///
  /// A nil value means that credential is already stored. The operation
  /// stops at the first failed write so the NFC field never opens with an
  /// incomplete credential set.
  internal func prepareIdentity(
    cardAccessNumber: String?,
    pin1: String?
  ) -> Bool {
    if let cardAccessNumber {
      saveCardAccessNumber(cardAccessNumber)
      guard contents.hasCardAccessNumber else { return false }
    }
    if let pin1 {
      savePin1(pin1)
      guard contents.hasPin1 else { return false }
    }
    refresh()
    return contents.hasCardAccessNumber && contents.hasPin1
  }

  /// Forgets the card access number, so it can be entered again.
  ///
  /// Ungated, like storing it.
  internal func forgetCardAccessNumber() {
    failure = nil
    CardCredentialStore.forgetCardAccessNumber()
    refresh()
  }

  /// Forgets PIN1, so every signature asks again.
  ///
  /// Deletion is deliberately ungated: it removes signing authority from
  /// this device and never reveals the stored value.
  internal func forgetPin1() {
    failure = nil
    CardCredentialStore.forgetPin1()
    refresh()
  }

  /// Forgets everything this device knows about the card.
  ///
  /// This clears credentials, card-directory entries, primed identities,
  /// Safari registration, and diagnostic logs without authentication.
  /// Nothing is disclosed; authority is removed.
  internal func forgetEverything() {
    failure = nil
    let outcome = CardStateReset.perform()
    CardCredentialStore.forgetAll()
    refresh()
    if !outcome.succeeded {
      failure = outcome.summary
    }
  }
}
