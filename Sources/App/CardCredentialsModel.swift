import CardCore
import SwiftUI

/// What the credential screen knows and what it is allowed to do.
///
/// Nothing here ever holds a secret longer than the moment it is written:
/// the entry fields are cleared as soon as a value is stored. For PIN1
/// the model only ever reports *whether* something is stored, never what
/// it is -- a screen that can show a PIN is a screen that can leak one.
/// The card access number is the one value read back: it is printed on
/// the card face and is the holder's to see (decision 2026-07-28).
@MainActor
@Observable
internal final class CardCredentialsModel {
  /// What the device currently holds.
  internal private(set) var contents = CardCredentialStore.contents()

  /// The stored card access number, shown by the manager window.
  internal private(set) var storedCardAccessNumber =
    CardCredentialStore.displayedCardAccessNumber()

  /// Set when the last action failed, for the holder to read.
  internal private(set) var failure: String?

  /// Refreshes what is stored, without touching PIN1.
  internal func refresh() {
    contents = CardCredentialStore.contents()
    storedCardAccessNumber = CardCredentialStore.displayedCardAccessNumber()
  }

  /// Stores the card access number, with no gate in front.
  ///
  /// Ungated by decision 2026-07-28: the number is printed on the card
  /// face, so a prompt in front of storing it protected nothing and
  /// cost every setup an interruption.
  internal func saveCardAccessNumber(_ digits: String) {
    failure = nil
    let status = CardCredentialStore.save(cardAccessNumber: digits)
    if status != errSecSuccess {
      failure = String(
        localized: "Could not store the card access number (\(status)).")
    }
    refresh()
  }

  /// Stores PIN1 after the holder authenticates.
  internal func savePin1(_ digits: String) async {
    await gated(
      reason: String(localized: "Save PIN1 so this device can sign without asking")
    ) {
      let status = CardCredentialStore.save(pin1: digits)
      guard status == errSecSuccess else {
        return String(localized: "Could not store PIN1 (\(status)).")
      }
      return nil
    }
  }

  /// Forgets the card access number, so it can be entered again.
  ///
  /// Ungated, like storing it: decision 2026-07-28.
  internal func forgetCardAccessNumber() {
    failure = nil
    CardCredentialStore.forgetCardAccessNumber()
    refresh()
  }

  /// Forgets PIN1, so every signature asks again.
  internal func forgetPin1() async {
    await gated(reason: String(localized: "Forget the stored PIN1")) {
      CardCredentialStore.forgetPin1()
      return nil
    }
  }

  /// Forgets everything this device knows about the card's secrets.
  internal func forgetEverything() async {
    await gated(reason: String(localized: "Forget the card details on this device")) {
      CardCredentialStore.forgetAll()
      return nil
    }
  }

  /// Runs `work` only once the holder has authenticated, then refreshes.
  ///
  /// `work` returns a message when it failed, or nil when it succeeded.
  ///
  /// This is the gate, and it is the only one: the keychain items
  /// themselves carry no access control, because the token extension has
  /// to read PIN1 while signing a request made in Safari and has no
  /// interface to answer a prompt with. Every path that writes or drops
  /// PIN1 therefore comes through here; the card access number needs no
  /// gate at all (decision 2026-07-28).
  ///
  /// ``CardCredentialGate`` is also the single place a debug build can be
  /// told to skip the prompt, and nothing outside `#if DEBUG` can ask it
  /// to.
  private func gated(reason: String, work: () -> String?) async {
    failure = nil
    do {
      try await CardCredentialGate.authenticate(reason: reason)
    } catch CardCredentialGate.Refusal.unavailable {
      failure = String(
        localized: "Set a device passcode before storing card details.")
      return
    } catch {
      failure = String(localized: "Not authenticated.")
      return
    }
    failure = work()
    refresh()
  }
}
