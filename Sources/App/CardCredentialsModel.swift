import CardCore
import SwiftUI

/// What the credential screen knows and what it is allowed to do.
///
/// Nothing here ever holds a secret longer than the moment it is written:
/// the entry fields are cleared as soon as a value is stored, and the
/// model only ever reports *whether* something is stored, never what it
/// is. Reading a stored secret back for display is deliberately not
/// offered -- the holder can replace a value they have forgotten, and a
/// screen that can show a PIN is a screen that can leak one.
@MainActor
@Observable
internal final class CardCredentialsModel {
  /// What the device currently holds.
  internal private(set) var contents = CardCredentialStore.contents()

  /// Set when the last action failed, for the holder to read.
  internal private(set) var failure: String?

  /// Refreshes what is stored, without touching any secret.
  internal func refresh() {
    contents = CardCredentialStore.contents()
  }

  /// Stores the card access number after the holder authenticates.
  internal func saveCardAccessNumber(_ digits: String) async {
    await gated(
      reason: String(localized: "Save the card access number for this device")
    ) {
      guard CardCredentialStore.save(cardAccessNumber: digits) else {
        return String(localized: "That is not a valid card access number.")
      }
      return nil
    }
  }

  /// Stores PIN1 after the holder authenticates.
  internal func savePin1(_ digits: String) async {
    await gated(
      reason: String(localized: "Save PIN1 so this device can sign without asking")
    ) {
      guard CardCredentialStore.save(pin1: digits) else {
        return String(localized: "That is not a valid PIN1.")
      }
      return nil
    }
  }

  /// Forgets the card access number, so it can be entered again.
  internal func forgetCardAccessNumber() async {
    await gated(reason: String(localized: "Replace the card access number")) {
      CardCredentialStore.forgetCardAccessNumber()
      return nil
    }
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
